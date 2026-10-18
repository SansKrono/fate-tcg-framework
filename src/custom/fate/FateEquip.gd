# Permanents and their placement rules: relics attached to creatures, the field and world spell slots.
# Assigned to `game.equip`. No class_name (FateGame loads it by path). OWNER: the "permanents" session.
# docs/FATE_TCG_DESIGN.md Section 11.3 and Section 12 item 17.
#
#   * Equip: a relic "enters attached to a creature of your choice" (Dragon's Tooth, Teshra's War Gauntlets,
#     Holy Amulet, Murkmist Gemstone, Battle Hammer). Cannot be changed once equipped. If the creature leaves
#     the table the relic goes to the discard pile (a relic token ceases to exist). An equipped relic is
#     still a relic (targetable). What the relic grants (a keyword, a stat bonus) is set up by its card
#     script with `source` = the relic so it ends with it.
#   * Field spell slot: one per player. A new field spell sent to the slot sends the old one to the discard
#     pile. World spell slot: ONE shared by both players, same replacement rule.
#   * Persisting spells with a duration (counter on the spell, decremented by a phase trigger).
#
# How a relic sits on its creature. It stays in its slot of the relic zone (so it is still a relic zone
# permanent: zone_of() says "relics", game.card_effects sees it, it is targetable, the board state lists it
# in `relics` in the same slot) AND it is a framework attachment of the creature (attach_to_host,
# ATTACH_BEHIND, like the energy card beneath an Embody creature): its picture follows the creature around
# the table behind it. attach_to_host frees the grid slot of the attached card; equip() puts the occupation
# back. The link is `META_HOST` on the relic (the creature) plus `current_host_card`; both are checked, so a
# relic detached by anybody else is simply not equipped any more.
#
# A relic is only ever attached by equip(), once. It leaves its creature only when the creature leaves the
# table (release_all: the relic goes to its owner's discard pile, a relic token is deleted) or when the relic
# itself leaves. A creature that leaves the table by a move inside the table (taken into an energy zone)
# must call release_all(creature) itself; moves into a pile or the hand are caught by the signals below.
#
# Field and world slots. The board has one slot per grid, so a second field spell would be refused by the
# board. FateCardTemplate.common_pre_move_scripts calls make_room(card) for every field / world spell that is
# about to land on the table (played from the hand, flip cast, cast from the discard pile ...): the card in
# the slot goes to its OWNER's discard pile first. Board-state loads place cards directly (no move) and never
# come here.
#
# Durations. add_duration(card, turns, unit) puts a countdown on a card on the table. It ticks at the START
# of the END step (game.end_phase_begins) of the turns that count and the card is sent to its owner's
# discard pile when the count reaches 0 (its script hears on_leave like for any other card leaving the table).
# Units: "own_turn" (default; only the turns of the card's controller count) and "turn" (every turn of either
# player counts). The turn the card is played counts: a spell with 3 own turns played in turn 1 ticks at the
# end of turns 1, 3 and 5 and is gone after the third.
extends RefCounted

signal equipped(relic: Card, creature: Card)
# A persisting card ran out of turns (just before it moves to the discard pile)
signal duration_expired(card: Card)

# On the relic: the creature it is equipped to
const META_HOST := "fate_equipped_to"
# On a card: {"left": int, "unit": String}
const META_DURATION := "fate_duration"
const UNIT_OWN_TURN := "own_turn"
const UNIT_TURN := "turn"
const UNITS := [UNIT_OWN_TURN, UNIT_TURN]

var game: FateGame


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.end_phase_begins.connect(_on_end_phase)


# --- equipment ---------------------------------------------------------------------------------

# Why the relic cannot be equipped to the creature: "" if it can
func equip_problem(relic: Card, creature: Card) -> String:
	if not is_instance_valid(relic) or relic.properties.get("Type") != "Relic":
		return "Only a relic can be equipped"
	if FateZones.zone_of(relic) != "relics":
		return "The relic is not on the table"
	if not FateZones.is_creature_in_play(creature):
		return "A relic can only be equipped to a creature in play"
	if host_of(relic) != null:
		return "The relic is already equipped"
	return ""


# Attaches a relic on the table to a creature on the table. Returns whether it worked. Once equipped it
# cannot be changed: a second equip of the same relic returns false whoever the creature is.
func equip(relic: Card, creature: Card) -> bool:
	if equip_problem(relic, creature) != "":
		return false
	_connect(relic, creature)
	var slot = relic._placement_slot
	relic.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
	relic.set_meta(META_HOST, creature)
	relic.attach_to_host(creature, false, ["Scripted"])
	# attach_to_host emptied the grid slot of the relic: it still stands in its zone
	if slot != null and is_instance_valid(slot) and slot.occupying_card == null:
		slot.occupying_card = relic
		relic._placement_slot = slot
	creature.state_finalized = false
	game.stats.refresh(creature)
	equipped.emit(relic, creature)
	return true


# The creature a relic is equipped to, or null
func host_of(relic: Card) -> Card:
	if not is_instance_valid(relic) or not relic.has_meta(META_HOST):
		return null
	var host = relic.get_meta(META_HOST)
	if is_instance_valid(host) and relic.current_host_card == host and relic in host.attachments:
		return host
	return null


# The relics equipped to a creature
func relics_on(creature: Card) -> Array:
	var found := []
	if not is_instance_valid(creature):
		return found
	for attached in creature.attachments:
		if is_instance_valid(attached) and host_of(attached) == creature:
			found.append(attached)
	return found


# Is this card an equipped relic? (FateBoardStateCapture lists those under the relic zone, not under the
# creature)
func is_equipped(relic: Card) -> bool:
	return host_of(relic) != null


# The relic leaves its creature for its owner's discard pile (a token ceases to exist). Used when the
# creature leaves the table; callable for effects that unequip. Returns false if it was not equipped.
func unequip(relic: Card) -> bool:
	var host := host_of(relic)
	if host == null:
		return false
	_detach(relic, host)
	_remove_from_table(relic)
	game.stats.refresh(host)
	return true


# Every relic equipped to the creature leaves for the discard pile. Returns how many.
func release_all(creature: Card) -> int:
	var count := 0
	for relic in relics_on(creature):
		if unequip(relic):
			count += 1
	return count


func _detach(relic: Card, host: Card) -> void:
	# By hand, what Card._clear_attachment_status does without moving the host's other attachments:
	# the relic goes to ITS owner's discard pile, it does not follow the creature
	host.attachments.erase(relic)
	host.state_finalized = false
	relic.current_host_card = null
	if relic.has_meta(META_HOST):
		relic.remove_meta(META_HOST)
	relic.card_unattached.emit(relic, "card_unattached", {"host": host, "tags": ["Scripted"]})


func _connect(relic: Card, creature: Card) -> void:
	for sig in [creature.card_moved_to_pile, creature.card_moved_to_hand]:
		if not sig.is_connected(_on_host_moved):
			sig.connect(_on_host_moved)
	if not relic.card_unattached.is_connected(_on_unattached):
		relic.card_unattached.connect(_on_unattached)
	# The framework detaches a card only when its slide into a pile is over: do it at once
	for sig in [relic.card_moved_to_pile, relic.card_moved_to_hand]:
		if not sig.is_connected(_on_relic_moved):
			sig.connect(_on_relic_moved)


func _on_host_moved(creature: Card, _trigger: String, _details: Dictionary) -> void:
	if is_instance_valid(creature) and creature.get_parent() != cfc.NMAP.board:
		release_all(creature)


func _on_relic_moved(relic: Card, _trigger: String, _details: Dictionary) -> void:
	var host := host_of(relic) if is_instance_valid(relic) else null
	if host != null and relic.get_parent() != cfc.NMAP.board:
		_detach(relic, host)


# Somebody else detached the relic (it left the table): forget the link, refresh the creature
func _on_unattached(relic: Card, _trigger: String, details: Dictionary) -> void:
	if is_instance_valid(relic) and relic.has_meta(META_HOST):
		relic.remove_meta(META_HOST)
	var host = details.get("host")
	if is_instance_valid(host) and game != null and game.stats != null:
		game.stats.refresh(host)


# --- the slots ---------------------------------------------------------------------------------

# The card currently in a player's field spell slot or in the shared world slot, or null
func field_spell(player_id: int) -> Card:
	if not game.players.has(player_id):
		return null
	var found: Array = game.player(player_id).cards_in_grid("field")
	return found[0] if not found.is_empty() else null


func world_spell() -> Card:
	var grid := FateZones.grid("world", 0)
	if grid == null:
		return null
	for slot in grid.get_all_slots():
		if slot.occupying_card != null and is_instance_valid(slot.occupying_card):
			return slot.occupying_card
	return null


# "field" or "world" for a field / world spell, otherwise ""
static func slot_kind(card: Card) -> String:
	if not is_instance_valid(card) or card.properties.get("Type") != "Spell":
		return ""
	match card.properties.get("_spell_kind"):
		"Field":
			return "field"
		"World":
			return "world"
	return ""


# The card a field / world spell would replace if it landed on the table now, or null
func occupant_for(card: Card) -> Card:
	match slot_kind(card):
		"field":
			return field_spell(card.owner_id if card is FateCardTemplate else game.active_id)
		"world":
			return world_spell()
	return null


# Called by FateCardTemplate.common_pre_move_scripts before a card lands on the table: a field / world
# spell sends the card in its slot (a field spell: the same player's, a world spell: whoever's) to that
# card's owner's discard pile. Does nothing if the spell is not going to the table's own slot (the board
# refuses a drop on another zone). Returns the replaced card, or null.
func make_room(card: Card) -> Card:
	var old := occupant_for(card)
	if old == null or old == card:
		return null
	var hovered: BoardPlacementSlot = card.get_potential_placement_slot()
	if hovered != null and hovered.get_grid_name() != card.mandatory_grid_name:
		return null
	send_to_discard(old)
	return old


# Moves a card on the table to its owner's discard pile right now (its slot is free at once, the move
# animates). The card's script hears on_leave and its modifiers end through FateCardEffects.card_left.
func send_to_discard(card: Card) -> void:
	_remove_from_table(card)


func _remove_from_table(card: Card) -> void:
	if not is_instance_valid(card):
		return
	var owner_id: int = card.owner_id if card is FateCardTemplate else game.active_id
	if card.has_meta(META_DURATION):
		card.remove_meta(META_DURATION)
	# Free the slot at once, the framework frees it only when the move into the pile is done
	var slot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	card._placement_slot = null
	if tokens_ceases_to_exist(card):
		# A token that leaves the table is gone, it does not go to the discard pile
		if game.card_effects:
			game.card_effects.card_left(card, "discard")
		game.stats.clear_card(card)
		game._delete_table_card(card)
		return
	card.move_to(FateZones.container("discard", owner_id), -1, null, ["Scripted"])


func tokens_ceases_to_exist(card: Card) -> bool:
	return game.tokens != null and game.tokens.has_method("is_token") and game.tokens.is_token(card)


# --- durations ---------------------------------------------------------------------------------

# Puts a countdown on a card on the table: after `turns` counted turns (see the header) the card goes to its
# owner's discard pile. Replaces a countdown the card had. `unit`: UNIT_OWN_TURN or UNIT_TURN.
func add_duration(card: Card, turns: int, unit := UNIT_OWN_TURN) -> void:
	if not is_instance_valid(card):
		return
	if not unit in UNITS:
		push_warning("FateEquip.add_duration: unknown unit '%s', using %s" % [unit, UNIT_OWN_TURN])
		unit = UNIT_OWN_TURN
	card.set_meta(META_DURATION, {"left": maxi(turns, 0), "unit": unit})


# Counted turns left, or -1 if the card has no countdown
func remaining(card: Card) -> int:
	if not is_instance_valid(card) or not card.has_meta(META_DURATION):
		return -1
	return int(card.get_meta(META_DURATION)["left"])


func _on_end_phase(active_id: int) -> void:
	var expired := []
	for card in _table_cards():
		if not card.has_meta(META_DURATION):
			continue
		var duration: Dictionary = card.get_meta(META_DURATION)
		var controller: int = card.controller_id if card is FateCardTemplate else active_id
		if duration["unit"] == UNIT_OWN_TURN and controller != active_id:
			continue
		duration["left"] = int(duration["left"]) - 1
		if duration["left"] <= 0:
			expired.append(card)
	for card in expired:
		duration_expired.emit(card)
		send_to_discard(card)


func _table_cards() -> Array:
	if game.card_effects != null:
		return game.card_effects.table_cards()
	var found := []
	for pid in game.players:
		for zone in ["creatures", "occupied", "relics", "field", "doctrines"]:
			found.append_array(game.players[pid].cards_in_grid(zone))
	var world := world_spell()
	if world != null:
		found.append(world)
	return found
