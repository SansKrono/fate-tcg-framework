# Changing who controls a card. Assigned to `game.control`. No class_name (FateGame loads it by path).
# docs/FATE_TCG_DESIGN.md Section 4.1 and the SYS-CONTROL entry of Section 13. OWNER: the "control" session.
#
# Owner (`owner_id`, fixed by the deck the card came from) decides where a card goes when it dies or is
# returned; controller (`controller_id`) decides who may attack with it, use its abilities and which
# player's zones it stands in. Taking control moves the card to the new controller's zone (creature zone
# for creatures, relic zone for relics ...), keeps damage, modifiers and attachments, and the card is
# "new" for the new controller: it cannot attack the turn it changes sides unless it has Charge
# (entered_turn is set), exactly like Section 12 item 7 / FATE_RULES_SPEC.md says for entering play.
#
# Used by: Harbinger of Krelgar, Unseen Manipulator, Krelga, Murkmist Gemstone, Double Agent (until end of
# turn), Claimed by the Abyss (into the energy zone), Convert the Masses and Subtle Influence doctrines.
#
# What goes with the card, what does not (the choices this file makes):
#   * damage, stat modifiers and keyword grants (the stats layer keys them by card) stay on the card, whoever
#     created them. A buff or a debuff is an effect on the creature, not on its controller. What depends on
#     the controller (static effects of cards on the table: "creatures you control ...") follows by itself,
#     the registry asks the host card about `controller_id` on every query.
#   * tokens (counters on the card), cards attached to it (embodied energy, equipped relics) move with it;
#     the attached cards get the new controller too, their owner never changes.
#   * the card is an arrival for the new controller: `entered_turn` is the current turn (summoning sickness),
#     `card_entered` is told to game.card_effects (its on_enter script runs for the new side). The old
#     controller's side hears nothing.
#   * a creature arrives upright in the creature zone (also when it was occupied), unless `tilted`; a relic
#     keeps its tilt.
#   * combat: the card leaves combat (as an attacker its attack is removed, as a blocker it stops blocking),
#     and attacks aimed at it by its new controller's creatures are removed too.
#   * claimed into the energy zone: it stops being a permanent. Its modifiers and grants are gone, the cards
#     attached to it go to their owners' discard piles, a token ceases to exist.
#   * temporary control (`until: "end_of_turn"`) ends in the END phase (game.end_of_turn_expiry). If the
#     previous controller's zone is full by then, the card goes to its owner's discard pile. A card that
#     leaves the table meanwhile (it died: FateEffects.destroy sends it to its OWNER's pile) is just forgotten.
extends RefCounted

signal control_changed(card: Card, old_controller: int, new_controller: int)

# Where each kind of permanent may be put
const ZONES_BY_TYPE := {
	"Creature": ["creatures", "occupied", "energy"],
	"Relic": ["relics", "energy"],
}
# The zones a card can be taken from
const SOURCE_ZONES := ["creatures", "occupied", "relics"]

var game: FateGame
# card instance id -> {"until": "end_of_turn" | "permanent", "back_to": player id}
var _temporary := {}


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.end_of_turn_expiry.connect(_on_end_of_turn_expiry)
	game.creature_destroyed.connect(_on_creature_destroyed)


# --- the API -------------------------------------------------------------------------------------

# Gives `new_controller` control of a card on the table. `options`: {"until": "permanent" (default) or
# "end_of_turn" (returns to the previous controller in the END phase, or when the card leaves play),
# "tilted": bool (put it in guard position, Double Agent), "zone": String (override the destination grid;
# "energy" puts it face-down in the new controller's energy zone and it stops being a permanent),
# "heal": bool (forget damage and expiring modifiers, for a creature that comes back from "destroyed")}.
# Returns whether control changed. Emits control_changed and runs the card's on_enter for the new side
# only when the card really lands in a table zone.
#
# Taking control of a card the player controls already does nothing (false), except for the energy zone:
# "place target creature in your energy zone" works on your own creatures too.
func take_control(card: Card, new_controller: int, options := {}) -> bool:
	if take_problem(card, new_controller, options) != "":
		return false
	var until: String = options.get("until", "permanent")
	var zone := destination_zone(card, options)
	var old: int = card.controller_id
	if zone == "energy":
		_temporary.erase(card.get_instance_id())
		return _claim_into_energy(card, new_controller, old)
	var back_to := old
	if _temporary.has(card.get_instance_id()):
		# Stealing a stolen card for a while: it still goes back to whoever lent it first
		back_to = _temporary[card.get_instance_id()].back_to
	if not _arrive(card, new_controller, zone, options):
		return false
	if until == "end_of_turn":
		_temporary[card.get_instance_id()] = {"until": until, "back_to": back_to}
	else:
		_temporary.erase(card.get_instance_id())
	return true


# Why take_control would not work: "" if it would
func take_problem(card: Card, new_controller: int, options := {}) -> String:
	if not game.is_started or game.is_over:
		return "The game is not going on"
	if not game.players.has(new_controller):
		return "No such player"
	if not card is FateCardTemplate or not is_instance_valid(card):
		return "Not a card"
	var from_zone := FateZones.zone_of(card)
	if from_zone not in SOURCE_ZONES:
		return "Only a creature or a relic on the table can change sides"
	if card.current_host_card != null:
		return "It is attached to another card (it goes where its host goes)"
	var zone := destination_zone(card, options)
	if zone == "":
		return "It cannot go there"
	if zone != "energy" and card.controller_id == new_controller:
		return "Already under that player's control"
	if grid_for(new_controller, zone).find_available_slot() == null:
		return "That zone is full"
	return ""


# The grid zone the card would go to: the "zone" option if the card may go there, else the card's own
# zone ("" if the option is wrong for the card)
func destination_zone(card: Card, options := {}) -> String:
	var allowed: Array = ZONES_BY_TYPE.get(card.properties.get("Type"), [])
	var zone: String = options.get("zone", "")
	if zone == "":
		return allowed[0] if not allowed.is_empty() else ""
	return zone if zone in allowed else ""


# Gives control back to the owner (or to whoever had it before for temporary control). Returns whether the
# card changed sides. Nothing to return (the controller is the owner already): false. If the home zone is
# full the card goes to its owner's discard pile (and the result is true).
func return_control(card: Card) -> bool:
	if not is_instance_valid(card) or not card is FateCardTemplate:
		return false
	var id := card.get_instance_id()
	var target: int = _temporary[id].back_to if _temporary.has(id) else card.owner_id
	_temporary.erase(id)
	if card.controller_id == target or FateZones.zone_of(card) not in SOURCE_ZONES:
		return false
	var zone: String = "relics" if card.properties.get("Type") == "Relic" else "creatures"
	if grid_for(target, zone).find_available_slot() == null:
		_send_to_discard(card)
		return true
	# Home again with the position it has (a Double Agent creature stays in guard position)
	return _arrive(card, target, zone, {"tilted": card.card_rotation == 90})


# Is the card under temporary control right now (it goes back by itself)?
func is_temporary(card: Card) -> bool:
	return _temporary.has(card.get_instance_id())


# The player the card goes back to when the temporary control ends, or 0
func temporary_home(card: Card) -> int:
	return int(_temporary.get(card.get_instance_id(), {}).get("back_to", 0))


# --- queries ---------------------------------------------------------------------------------------------

# The cards `player_id` controls but does not own (doctrine "Count control"): permanents on the table and
# cards in their energy zone that came from the other player
func controlled_not_owned(player_id: int) -> Array:
	var found := []
	for card in game.card_effects.table_cards():
		if card is FateCardTemplate and card.controller_id == player_id and card.owner_id != player_id:
			found.append(card)
	if game.players.has(player_id):
		for card in game.player(player_id).cards_in_grid("energy"):
			if card is FateCardTemplate and card.owner_id != player_id:
				found.append(card)
	return found


# The cards `player_id` owns that somebody else controls right now (taken from them)
func controlled_by_owner(player_id: int) -> Array:
	var found := []
	for card in game.card_effects.table_cards():
		if card is FateCardTemplate and card.owner_id == player_id and card.controller_id != player_id:
			found.append(card)
	for pid in game.players:
		if pid == player_id:
			continue
		for card in game.player(pid).cards_in_grid("energy"):
			if card is FateCardTemplate and card.owner_id == player_id:
				found.append(card)
	return found


func is_controlled_by_owner(card: Card) -> bool:
	return card is FateCardTemplate and card.controller_id == card.owner_id


# --- doing it ----------------------------------------------------------------------------------------------

# The placement grid of a zone of a player (null for zones without a grid)
func grid_for(player_id: int, zone: String) -> BoardPlacementGrid:
	return FateZones.grid(zone, player_id)


# Moves a card to a table zone of the new controller and makes it theirs
func _arrive(card: FateCardTemplate, new_controller: int, zone: String, options: Dictionary) -> bool:
	var old: int = card.controller_id
	var slot := grid_for(new_controller, zone).find_available_slot()
	if slot == null:
		return false
	_leave_combat(card, new_controller)
	if card.properties.get("Type") == "Creature":
		card.set_card_rotation(90 if options.get("tilted", false) or zone == "occupied" else 0)
	# A "Scripted" move inside the board: the framework frees the old slot and takes the new one
	card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	if card._placement_slot != slot:
		return false
	_set_controller(card, new_controller)
	_move_equipped_relics(card, new_controller)
	card.mandatory_grid_name = FateZones.grid_name(card.board_zone(), new_controller)
	card.entered_turn = game.turn_number
	if options.get("heal", false):
		game.stats.reset_card(card)
	else:
		game.stats.refresh(card)
	control_changed.emit(card, old, new_controller)
	game.mana_changed.emit(old)
	game.mana_changed.emit(new_controller)
	if game.card_effects != null:
		game.card_effects.card_entered(card)
	return true


# Puts the card face-down in the energy zone of the new controller: it is not a permanent any more
func _claim_into_energy(card: FateCardTemplate, new_controller: int, old: int) -> bool:
	_leave_combat(card, new_controller)
	_release_attachments(card)
	game.stats.clear_card(card)
	if game.tokens != null and game.tokens.is_token(card):
		# A token that leaves the table ceases to exist
		_dispose(card)
		control_changed.emit(card, old, new_controller)
		return true
	var slot := grid_for(new_controller, "energy").find_available_slot()
	card.set_card_rotation(0)
	card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	if card._placement_slot != slot:
		return false
	_set_controller(card, new_controller)
	card.entered_turn = 0
	card.apply_zone_look("energy")
	# The script hears it left the table; the framework does not report moves inside the board
	if game.card_effects != null:
		game.card_effects.card_left(card, "energy")
	control_changed.emit(card, old, new_controller)
	game.mana_changed.emit(old)
	game.mana_changed.emit(new_controller)
	return true


# Relics equipped to the creature stay attached (their picture follows it) but their slot in the relic zone
# moves to the new controller's. A relic with no room there leaves the creature for its owner's discard pile.
func _move_equipped_relics(creature: Card, new_controller: int) -> void:
	if game.equip == null:
		return
	for relic in game.equip.relics_on(creature):
		var slot := grid_for(new_controller, "relics").find_available_slot()
		if slot == null:
			game.equip.unequip(relic)
			continue
		var old_slot: BoardPlacementSlot = relic._placement_slot
		if old_slot != null and is_instance_valid(old_slot) and old_slot.occupying_card == relic:
			old_slot.occupying_card = null
		slot.occupying_card = relic
		relic._placement_slot = slot
		if relic is FateCardTemplate:
			relic.mandatory_grid_name = FateZones.grid_name("relics", new_controller)


func _set_controller(card: FateCardTemplate, player_id: int) -> void:
	card.controller_id = player_id
	for attached in card.attachments:
		if attached is FateCardTemplate:
			attached.controller_id = player_id


# A card changing sides stops attacking and blocking, and nobody attacks it from its new side
func _leave_combat(card: Card, new_controller: int) -> void:
	if game.combat == null:
		return
	for attack in game.combat.attacks:
		if attack.resolved or attack.removed:
			continue
		if attack.target_card == card and attack.attacker.controller_id == new_controller:
			game.combat.remove_from_combat(attack.attacker)
	game.combat.remove_from_combat(card)


# The cards attached to a card that leaves the table go to their owners' discard piles. The detaching is
# done by hand because the framework would move the attachments along with the host (KwEmbody.release
# does the same for the embodied card).
func _release_attachments(card: Card) -> void:
	# Equipped relics hold a slot of the relic zone: the permanents system lets them go properly
	if game.equip != null:
		game.equip.release_all(card)
	for attached in card.attachments.duplicate():
		card.attachments.erase(attached)
		card.state_finalized = false
		attached.current_host_card = null
		for key in attached.get_meta_list():
			if str(key).begins_with("fate_"):
				attached.remove_meta(key)
		attached.card_unattached.emit(attached, "card_unattached", {"host": card, "tags": ["Scripted"]})
		if game.tokens != null and game.tokens.is_token(attached):
			_dispose(attached)
			continue
		var pid: int = attached.owner_id if attached is FateCardTemplate else card.owner_id
		attached.is_energy = false
		attached.move_to(FateZones.container("discard", pid), -1, null, ["Scripted"])
	game.stats.refresh(card)


# The card goes to its owner's discard pile (a return that has no room, or a token that ceases to exist)
func _send_to_discard(card: FateCardTemplate) -> void:
	_leave_combat(card, card.owner_id)
	_release_attachments(card)
	if game.tokens != null and game.tokens.is_token(card):
		_dispose(card)
		return
	var slot: BoardPlacementSlot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	card._placement_slot = null
	card.set_card_rotation(0)
	# Leaving the board for a pile: FateCardTemplate tells the card script and clears the stats
	card.move_to(FateZones.container("discard", card.owner_id), -1, null, ["Scripted"])
	card.controller_id = card.owner_id


# Removes a token card from the game
func _dispose(card: Card) -> void:
	var slot: BoardPlacementSlot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	card._placement_slot = null
	if game.card_effects != null:
		game.card_effects.card_left(card, "removed")
	game.stats.clear_card(card)
	card.queue_free()


# --- end of turn -------------------------------------------------------------------------------------------

func _on_end_of_turn_expiry(_player_id: int) -> void:
	for id in _temporary.keys():
		var card = instance_from_id(id)
		if card == null or not is_instance_valid(card) or FateZones.zone_of(card) not in SOURCE_ZONES \
				or _temporary[id].until != "end_of_turn":
			_temporary.erase(id)
			continue
		return_control(card)


# A temporary card that dies goes to its owner's discard pile by itself; forget the loan
func _on_creature_destroyed(card: Card, _cause: String) -> void:
	_temporary.erase(card.get_instance_id())
