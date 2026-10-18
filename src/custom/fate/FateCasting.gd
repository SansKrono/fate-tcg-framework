# Casting cards from places other than the hand: flip cast, cast from the discard pile, temporary
# creatures from the energy zone. Assigned to `game.casting`. No class_name (FateGame loads it by path).
# docs/FATE_TCG_DESIGN.md Section 9.1 (Flip Cast), Section 14 (Chaos and Primal). OWNER: the "casting" session.
#
# Terms of the game:
#   * Flip cast: cast a card from your ENERGY zone (the face-down card turns up and is cast, paying its
#     cost or not, depending on the effect). The energy card is gone from the energy zone. It is only
#     allowed when an effect gives permission (Dockside Alter, Subtle Influence, Cultist Fanatic ...), see
#     `grant_permission`.
#   * Cast from the discard pile: Unending Echo (a creature), Rustmarket Tinkerer (a relic), Second Calling
#     (return to the field without casting).
#   * Temporary creature (Teshra's ability, Guardian Spirits): flip a CREATURE card from the energy zone
#     onto the table, it may attack this turn, and at end of turn it returns to the energy zone (face-down,
#     untapped). If it is destroyed or leaves, it does not return.
# Casting means the normal play rules for the card's type, minus the hand: creature -> its zone, regular
# spell -> resolve then discard, field / world spell -> slot. A "cast" fires card_played, on_play,
# on_enter (a flip cast also fires `flip_cast`).
#
# How the pieces fit:
#   * Permissions are the standing right of a PLAYER to flip cast (`grant_permission`, `can_flip_cast`,
#     `use_permission`). `flip_cast_card` itself is the action ("this effect says: cast that card") and
#     does not look at them, so a card that says "flip cast a card from your energy zone" just calls it.
#     A doctrine that allows one flip cast a turn uses `flip_cast_with_permission`.
#   * The card being flip cast never pays for itself: it leaves the energy zone first, then the cost is
#     paid with the other untapped energy (and ingots, FateMana decides).
#   * Reaction spells and doctrines cannot be cast this way (reactions only exist in reaction windows).
#   * A flip cast card owned by the other player (put in your energy zone by Dockside Ambusher ...) is
#     cast by the player whose energy zone it stands in: it lands in their zone and they control it; a
#     spell still goes to its OWNER's discard pile.
extends RefCounted

# A card was flip cast by a player, after it was cast completely (a spell has resolved). Cards on the table
# hear it through FateCardEffect.on_flip_cast (the registry connects to this signal).
signal flip_cast(card: Card, player_id: int)

const SCRIPTED := ["Scripted"]
const PERMISSION_ANY := ""

var game: FateGame
# player id -> {permission key: {"uses": uses left, "max": uses per turn, "every_turn": bool}}
var _permissions := {}
# Card -> id of the player whose energy zone it is on loan from (borrow_creature)
var _borrowed := {}


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.turn_started.connect(_on_turn_started)
	game.end_of_turn_expiry.connect(_on_end_of_turn_expiry)
	game.creature_destroyed.connect(_on_creature_destroyed)
	game.board_state_loaded.connect(func(_state_name): reset())


# Forgets permissions and loans (a new game, a loaded board state)
func reset() -> void:
	_permissions.clear()
	_borrowed.clear()


# --- permissions ---------------------------------------------------------------------------------------

# Lets `player_id` flip cast `uses` times this turn (a doctrine or card calls this each turn / when its
# condition is met). `key` names the source. A grant lasts until the next turn starts. With `every_turn`
# (a doctrine sets it once) the uses are renewed at the start of every turn and granting it again keeps
# the uses already spent this turn.
func grant_permission(player_id: int, key: String, uses := 1, every_turn := false) -> void:
	var table: Dictionary = _permissions.get(player_id, {})
	var entry: Dictionary = table.get(key, {})
	if every_turn and entry.get("every_turn", false):
		entry["max"] = uses
		entry["uses"] = mini(int(entry["uses"]), uses)
	else:
		table[key] = {"uses": uses, "max": uses, "every_turn": every_turn}
	_permissions[player_id] = table


# Takes a permission away
func revoke_permission(player_id: int, key: String) -> void:
	_permissions.get(player_id, {}).erase(key)


# Uses left of one permission (0 if there is none)
func permission_uses(player_id: int, key: String) -> int:
	return int(_permissions.get(player_id, {}).get(key, {}).get("uses", 0))


# Can this player flip cast now (they hold a permission)?
func can_flip_cast(player_id: int) -> bool:
	for key in _permissions.get(player_id, {}):
		if permission_uses(player_id, key) > 0:
			return true
	return false


# Spends one use of the permission `key` (PERMISSION_ANY: the first one with uses left). Returns whether
# the player had one.
func use_permission(player_id: int, key := PERMISSION_ANY) -> bool:
	var table: Dictionary = _permissions.get(player_id, {})
	for k in table:
		if (key == PERMISSION_ANY or k == key) and int(table[k]["uses"]) > 0:
			table[k]["uses"] = int(table[k]["uses"]) - 1
			return true
	return false


func _on_turn_started(_player_id: int, _turn_number: int) -> void:
	for pid in _permissions:
		var table: Dictionary = _permissions[pid]
		for key in table.keys():
			if table[key]["every_turn"]:
				table[key]["uses"] = table[key]["max"]
			else:
				table.erase(key)


# --- flip cast ----------------------------------------------------------------------------------------------

# The energy cards of the player that could be flip cast: spells (not reactions), creatures, relics.
# `filter` (optional Callable taking the card) narrows them; `pay_cost` true keeps only the ones the other
# energy cards can pay for. The permission is not looked at (see can_flip_cast).
func flip_castable(player_id: int, filter := Callable(), pay_cost := false) -> Array:
	var found := []
	if not game.players.has(player_id):
		return found
	for card in game.player(player_id).cards_in_grid("energy"):
		if flip_cast_problem(card, player_id, pay_cost) != "":
			continue
		if filter.is_valid() and not filter.call(card):
			continue
		found.append(card)
	return found


# Why `card` cannot be flip cast by the player now, or "" if it can: not in their energy zone, a type that
# cannot be cast, the card's own play_problem (no legal target), no free slot, cost not payable by the
# other energy.
func flip_cast_problem(card: Card, player_id: int, pay_cost := true) -> String:
	if not is_instance_valid(card) or not card is FateCardTemplate or not game.players.has(player_id):
		return "Not a card"
	if not card in game.player(player_id).cards_in_grid("energy"):
		return "Not in the player's energy zone"
	var why := _cast_problem(card, player_id)
	if why != "":
		return why
	if pay_cost and not _others_can_pay(card, player_id):
		return "The other energy cannot pay for it"
	return ""


# Flip casts `card` (a face-down energy card of `player_id`): it leaves the energy zone, turns up and is
# cast with the normal rules of its type, as if from the hand. `pay_cost` false casts it for free
# (Cultist Fanatic, Unforgotten Sacrifice). `choice` is passed on to a spell with a choice (null: the
# spell asks game.choices as usual). Returns whether it was cast. A coroutine.
func flip_cast_card(card: Card, player_id: int, pay_cost := true, choice = null) -> bool:
	if flip_cast_problem(card, player_id, pay_cost) != "":
		return false
	var slot: BoardPlacementSlot = card._placement_slot
	_detach(card)
	if pay_cost and not _pay(card, player_id):
		_attach(card, slot)
		return false
	game.mana_changed.emit(player_id)
	card.set_is_faceup(true, true)
	await _cast(card, player_id, choice, true)
	if not is_instance_valid(card):
		return true
	flip_cast.emit(card, player_id)
	return true


# flip_cast_card for a standing permission (a doctrine): needs a permission (`key`, default any), spends
# one use only if the card was really cast.
func flip_cast_with_permission(card: Card, player_id: int, pay_cost := true, choice = null,
		key := PERMISSION_ANY) -> bool:
	var table: Dictionary = _permissions.get(player_id, {})
	var allowed := false
	for k in table:
		if (key == PERMISSION_ANY or k == key) and int(table[k]["uses"]) > 0:
			allowed = true
	if not allowed:
		return false
	if not await flip_cast_card(card, player_id, pay_cost, choice):
		return false
	use_permission(player_id, key)
	return true


# --- cast from the discard pile -----------------------------------------------------------------------------

# Why `card` cannot be cast from its owner's discard pile by the player now, or "". Which cards may be
# cast from there is the calling card's decision (Unending Echo: itself; Rustmarket Tinkerer: a relic).
func cast_from_discard_problem(card: Card, player_id: int, pay_cost := true) -> String:
	if not is_instance_valid(card) or not card is FateCardTemplate or not game.players.has(player_id):
		return "Not a card"
	if card.owner_id != player_id or card.get_parent() != game.player(player_id).discard():
		return "Not in the player's discard pile"
	var why := _cast_problem(card, player_id)
	if why != "":
		return why
	if pay_cost and not _can_pay(card, player_id):
		return "The cost cannot be paid"
	return ""


# Casts a card from the owner's discard pile, paying its cost (or not), with the normal rules of its type.
# `choice` as in flip_cast_card. Returns whether it was cast. A coroutine.
func cast_from_discard(card: Card, player_id: int, pay_cost := true, choice = null) -> bool:
	if cast_from_discard_problem(card, player_id, pay_cost) != "":
		return false
	if pay_cost and not _pay(card, player_id):
		return false
	await _cast(card, player_id, choice, false)
	return true


# The hover action "Cast" of a card in its owner's discard pile (Unending Echo returns it from actions()):
# enabled in the owner's main phase when the card can be cast and paid. FateActions lists the actions of
# discard pile cards too, so the UI, the AI and tests run it with game.actions.run(card, "cast_from_discard").
func discard_action(card: Card, label := "Cast") -> Dictionary:
	var why := ""
	if game.phase != FateGame.Phase.MAIN or card.owner_id != game.active_id:
		why = "Only in its owner's main phase"
	else:
		why = cast_from_discard_problem(card, card.owner_id)
	return {"id": "cast_from_discard", "label": label,
			"tooltip": "Cast from the discard pile by paying its cost" + ("" if why == "" else " (%s)" % why),
			"enabled": why == "",
			"run": func(c: Card) -> bool: return await cast_from_discard(c, c.owner_id)}


# --- return to the table ------------------------------------------------------------------------------------

# Brings a card of a pile (the discard pile) to the table without casting it ("return target creature from
# your discard to the field"): no card_played, no on_play, but on_enter, and it is new on the table
# (entered_turn, so no attack without Charge). `options` as in FateTokens.create: {"tilted": bool (guard
# position), "zone": String (default: the zone of its type)}. The card enters `player_id`'s zones. Spells that
# resolve (regular / reaction) cannot be returned. Returns whether it is on the table now.
func return_to_table(card: Card, player_id: int, options := {}) -> bool:
	if not is_instance_valid(card) or not card is FateCardTemplate or not game.players.has(player_id):
		return false
	if not card.get_parent() is Pile or card.is_instant_spell() or card.properties.get("Type") == "Doctrine":
		return false
	var zone: String = options.get("zone", card.board_zone())
	var slot := _slot_for(zone, player_id)
	if slot == null:
		return false
	card.controller_id = player_id
	card.entered_turn = game.turn_number
	card.move_to(cfc.NMAP.board, -1, slot, SCRIPTED)
	if card.get_parent() != cfc.NMAP.board:
		return false
	card.apply_zone_look(zone, "up", bool(options.get("tilted", false)) if zone != "occupied" else true)
	return true


# --- borrowed creatures --------------------------------------------------------------------------------------

# Teshra / Guardian Spirits: flips a creature card from the player's energy zone to the creature zone until
# the end of the turn (on_enter runs, it was not cast). It may attack this turn (it has Charge). In the END
# phase it returns face-down and untapped to the energy zone, unless it left the table meanwhile (then it
# stays where it went). Returns the creature or null.
func borrow_creature(card: Card, player_id: int) -> Card:
	if not is_instance_valid(card) or not card is FateCardTemplate or not game.players.has(player_id):
		return null
	if card.properties.get("Type") != "Creature" or not card in game.player(player_id).cards_in_grid("energy"):
		return null
	var grid := FateZones.grid("creatures", player_id)
	if grid == null or (grid.count_available_slots() == 0 and not grid.auto_extend):
		return null
	if _script_problem(card, player_id) != "":
		return null
	var slot := grid.find_available_slot()
	_detach(card)
	game.mana_changed.emit(player_id)
	card.controller_id = player_id
	card.entered_turn = game.turn_number
	card.move_to(cfc.NMAP.board, -1, slot, SCRIPTED)
	card.apply_zone_look("creatures", "up", false)
	game.stats.grant_keyword(card, "Charge", 1, FateStats.EXPIRY_END_OF_TURN, card)
	_borrowed[card] = player_id
	game.card_effects.card_entered(card)
	return card


# Is this creature on loan from an energy zone right now?
func is_borrowed(card: Card) -> bool:
	return _borrowed.has(card)


func _on_end_of_turn_expiry(_player_id: int) -> void:
	for card in _borrowed.keys():
		var pid: int = _borrowed[card]
		_borrowed.erase(card)
		if not is_instance_valid(card) or FateZones.zone_of(card) not in FateZones.CREATURE_ZONES:
			continue
		# It leaves the table for the energy zone: its modifiers, damage and Charge go, its script hears it
		game.card_effects.card_left(card, "energy")
		game.stats.clear_card(card)
		card.controller_id = pid
		_to_energy(card, pid)


func _on_creature_destroyed(card: Card, _cause: String) -> void:
	_borrowed.erase(card)


# --- the shared pipeline ----------------------------------------------------------------------------------------

# Type and script checks for casting `card` as `player_id`, and room for it on the table
func _cast_problem(card: FateCardTemplate, player_id: int) -> String:
	if game.is_over or not game.is_started:
		return "The game is not going on"
	match card.properties.get("Type"):
		"Creature", "Relic":
			var grid := FateZones.grid(card.board_zone(), player_id)
			if grid == null or (grid.count_available_slots() == 0 and not grid.auto_extend):
				return "No room on the table"
		"Spell":
			if card.is_reaction_spell():
				return "Reaction spells can only be cast in a reaction window"
		_:
			return "This card type cannot be cast"
	return _script_problem(card, player_id)


# The card's own play_problem (no legal target ...) with `player_id` as the caster
func _script_problem(card: Card, player_id: int) -> String:
	var effect = game.card_effects.effect_of(card.canonical_name)
	return effect.play_problem(card, player_id) if effect != null else ""


# Casts a card that is free to move (out of the energy zone, or still in the discard pile) and paid for:
# permanents go to their zone and fire card_played / on_enter, regular spells resolve and go to their
# destination
func _cast(card: FateCardTemplate, player_id: int, choice, from_energy: bool) -> void:
	if card.is_instant_spell():
		await _cast_spell(card, player_id, choice, from_energy)
		return
	var zone := card.board_zone()
	var slot := _slot_for(zone, player_id)
	card.controller_id = player_id
	card.entered_turn = game.turn_number
	card.move_to(cfc.NMAP.board, -1, slot, SCRIPTED)
	card.apply_zone_look(zone)
	game.card_effects.begin_cast(card, player_id, choice)
	game.card_played.emit(card)
	await _wait_cast(card)
	# A card that came from a pile is "entered" by its move; one that stood on the table (energy) is not
	if from_energy:
		game.card_effects.card_entered(card, true)


func _cast_spell(card: FateCardTemplate, player_id: int, choice, from_energy: bool) -> void:
	# Asked before the spell counts as played, like the hand does it (FateCardTemplate._spell_destination)
	var destination: String = game.card_effects.spell_destination(card)
	game.card_effects.begin_cast(card, player_id, choice)
	game.card_played.emit(card)
	await _wait_cast(card)
	if not is_instance_valid(card):
		return
	if from_energy and destination == "energy":
		_to_energy(card, card.owner_id)
		return
	var container = FateZones.container(destination, card.owner_id)
	if container == null and destination == "energy":
		game.library.to_energy(card, card.owner_id)
		return
	if container == null:
		container = FateZones.container("discard", card.owner_id)
	if card.get_parent() != container:
		card.move_to(container, -1, null, SCRIPTED)
		# The move finishes after its animation; from here on the card is no energy card anyway
		card.is_energy = false


func _wait_cast(card: Card) -> void:
	while game.card_effects.cast_running(card):
		await game.get_tree().process_frame
	game.card_effects.end_cast(card)


# A free slot in the zone grid of a player for a card that comes to the table. The field slot (one per
# player) and the world slot (shared) are emptied if taken: the old card goes to its owner's discard pile.
func _slot_for(zone: String, player_id: int) -> BoardPlacementSlot:
	var grid := FateZones.grid(zone, player_id)
	if grid == null:
		return null
	if zone in ["field", "world"] and grid.count_available_slots() == 0:
		for slot in grid.get_all_slots():
			if slot.occupying_card != null:
				game.equip.send_to_discard(slot.occupying_card)
				break
	return grid.find_available_slot()


# --- the energy zone -------------------------------------------------------------------------------------------

# The card leaves its energy slot (the slot is free, the card keeps `is_energy` until it lands somewhere,
# so that moving it away is not reported as a card leaving the table)
func _detach(card: Card) -> void:
	var slot: BoardPlacementSlot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	card._placement_slot = null


func _attach(card: Card, slot: BoardPlacementSlot) -> void:
	slot.occupying_card = card
	card._placement_slot = slot


# Puts a card face-down and untapped into a free slot of the player's energy zone
func _to_energy(card: Card, player_id: int) -> void:
	var grid := FateZones.grid("energy", player_id)
	var slot: BoardPlacementSlot = grid.find_available_slot() if grid != null else null
	if slot == null:
		card.move_to(FateZones.container("discard", card.owner_id), -1, null, SCRIPTED)
		return
	card.is_energy = true
	card.move_to(cfc.NMAP.board, -1, slot, SCRIPTED)
	card.apply_zone_look("energy")
	game.mana_changed.emit(player_id)


# --- paying ---------------------------------------------------------------------------------------------------------

# Would the cost of `card` be payable by `player_id` right now? A card in the energy zone does not count
# as mana for itself.
func _others_can_pay(card: Card, player_id: int) -> bool:
	var slot: BoardPlacementSlot = card._placement_slot
	_detach(card)
	var ok := _can_pay(card, player_id)
	_attach(card, slot)
	return ok


# FateMana plans by the card's owner; a card owned by the other player is paid for by `player_id`
func _can_pay(card: Card, player_id: int) -> bool:
	var owner_id: int = card.owner_id
	card.owner_id = player_id
	var ok: bool = game.mana.can_pay(card)
	card.owner_id = owner_id
	return ok


func _pay(card: Card, player_id: int) -> bool:
	var owner_id: int = card.owner_id
	card.owner_id = player_id
	var ok: bool = game.mana.pay(card)
	card.owner_id = owner_id
	return ok
