extends "res://tests/FateCommon.gd"
# Tests of take-control (src/custom/fate/FateControl.gd, `game.control`). Rules: docs/FATE_TCG_DESIGN.md
# Section 4.1. The owner of a card never changes; the controller does, and the card stands in the
# controller's zone. Player 1 is the active player in a fresh game; the victim is player 2's creature.

var control


func before_each():
	await super.before_each()
	control = game.control


func _discard(pid: int) -> Node:
	return FateZones.container("discard", pid)


func _grid_cards(pid: int, zone: String) -> Array:
	return game.player(pid).cards_in_grid(zone)


# --- taking control for good ---------------------------------------------------------------------------

func test_a_creature_moves_to_the_new_controllers_creature_zone_and_keeps_its_owner():
	var victim := await put_creature(2, 3, 2)
	var changed: Array = []
	control.control_changed.connect(func(c, old, new): changed.append([c, old, new]))
	assert_true(control.take_control(victim, 1))
	await get_tree().process_frame
	assert_eq(victim.controller_id, 1)
	assert_eq(victim.owner_id, 2, "The owner never changes")
	assert_eq(FateZones.zone_of(victim), "creatures")
	assert_true(victim in _grid_cards(1, "creatures"), "Stands in the new controller's zone")
	assert_false(victim in _grid_cards(2, "creatures"), "...and no longer in the old one")
	assert_eq(victim.mandatory_grid_name, FateZones.grid_name("creatures", 1))
	assert_eq(changed.size(), 1)
	assert_eq(changed[0], [victim, 2, 1])
	assert_false(control.is_temporary(victim))


func test_taking_control_of_your_own_card_or_a_wrong_target_is_refused():
	var mine := await put_creature(1, 1, 1)
	assert_false(control.take_control(mine, 1), "Already yours")
	assert_false(control.take_control(mine, 3), "No such player")
	var hand_card := await put_in_hand(2, "Moral Captain")
	assert_false(control.take_control(hand_card, 1), "Not on the table")
	var relic := await put_on_table(2, "Garbage Heap", "relics")
	assert_ne(control.take_problem(relic, 2, {"zone": "creatures"}), "", "A relic cannot go to the creature zone")
	assert_eq(relic.controller_id, 2)


func test_a_relic_goes_to_the_new_controllers_relic_zone():
	var relic := await put_on_table(2, "Garbage Heap", "relics")
	assert_true(control.take_control(relic, 1))
	await get_tree().process_frame
	assert_eq(relic.controller_id, 1)
	assert_eq(relic.owner_id, 2)
	assert_eq(FateZones.zone_of(relic), "relics")
	assert_true(relic in _grid_cards(1, "relics"))
	assert_false(relic in _grid_cards(2, "relics"))


func test_an_occupied_creature_arrives_ready_in_the_creature_zone():
	var victim := await put_creature(2, 3, 2, {}, false, "occupied")
	assert_true(control.take_control(victim, 1))
	await get_tree().process_frame
	assert_eq(FateZones.zone_of(victim), "creatures")
	assert_eq(victim.card_rotation, 0, "Upright, in strike position")


func test_the_tilted_option_puts_the_creature_in_guard_position():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1, {"tilted": true}))
	await get_tree().process_frame
	assert_eq(FateZones.zone_of(victim), "creatures")
	assert_eq(victim.card_rotation, 90)


func test_a_full_creature_zone_refuses_and_changes_nothing():
	var grid := game.player(1).grid("creatures")
	while grid.find_available_slot() != null and grid.get_available_slots().size() > 0:
		var filler := await put_creature(1, 1, 1)
		if filler == null:
			break
	assert_null(grid.find_available_slot(), "Test setup: the zone is full")
	var victim := await put_creature(2, 3, 2)
	assert_false(control.take_control(victim, 1))
	assert_ne(control.take_problem(victim, 1), "")
	assert_eq(victim.controller_id, 2)
	assert_true(victim in _grid_cards(2, "creatures"))


# --- what stays with the card -------------------------------------------------------------------------------

func test_damage_modifiers_grants_and_tokens_stay_with_the_card():
	var victim := await put_creature(2, 4, 3)
	game.stats.apply_damage(victim, "Strike", 1)
	game.stats.add_modifier(victim, "Guard", 2, FateStats.EXPIRY_PERMANENT)
	game.stats.grant_keyword(victim, "Swift", 1, FateStats.EXPIRY_PERMANENT)
	assert_eq(game.stats.current(victim, "Strike"), 3)
	assert_true(control.take_control(victim, 1))
	await get_tree().process_frame
	assert_eq(game.stats.damage_on(victim, "Strike"), 1, "Damage kept")
	assert_eq(game.stats.current(victim, "Strike"), 3)
	assert_eq(game.stats.current(victim, "Guard"), 5, "Modifier kept")
	assert_true(game.keywords.has(victim, "Swift"), "Keyword grant kept")


func test_cards_attached_to_the_creature_move_with_it():
	var wielder := await put_creature(2, "Spirit Wielder")
	go_to_main()
	var energy := await put_energy(2, "Thrang's Crafting Table")
	var embody = game.keywords.get_keyword("Embody")
	assert_true(embody.embody(wielder, energy, true), "Test setup: energy embodied")
	assert_eq(game.stats.current(wielder, "Strike"), 1 + energy.mana_value())
	assert_true(control.take_control(wielder, 1))
	await get_tree().process_frame
	assert_eq(embody.embodied_card(wielder), energy, "Still embodied")
	assert_eq(energy.controller_id, 1, "The attached card follows its host")
	assert_eq(energy.owner_id, 2)
	assert_eq(game.stats.current(wielder, "Strike"), 1 + energy.mana_value(), "The bonus stays")


func test_an_equipped_relic_follows_its_creature_into_the_new_controllers_relic_zone():
	var victim := await put_creature(2, 2, 2)
	var relic := await put_on_table(2, "Garbage Heap", "relics")
	assert_true(game.equip.equip(relic, victim), "Test setup: relic equipped")
	assert_true(control.take_control(victim, 1))
	await get_tree().process_frame
	assert_eq(game.equip.host_of(relic), victim, "Still equipped")
	assert_eq(relic.controller_id, 1)
	assert_eq(relic.owner_id, 2)
	assert_true(relic in _grid_cards(1, "relics"), "Its slot moved to the new controller's relic zone")
	assert_false(relic in _grid_cards(2, "relics"))
	assert_ne(control.take_problem(relic, 2), "", "An equipped relic is not taken on its own")


# --- summoning sickness --------------------------------------------------------------------------------------

func test_a_stolen_creature_cannot_attack_the_turn_it_changes_sides_without_charge():
	var victim := await put_creature(2, 3, 2)
	var charger := await put_creature(2, 3, 2, {"Charge": 1})
	assert_true(control.take_control(victim, 1))
	assert_true(control.take_control(charger, 1))
	await get_tree().process_frame
	assert_eq(victim.entered_turn, game.turn_number)
	start_combat()
	assert_false(game.combat.declare_attack(victim, 2), "Summoning sick")
	assert_true(game.combat.declare_attack(charger, 2), "Charge may attack at once")


func test_a_stolen_creature_can_attack_on_the_next_turn_of_its_new_controller():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1))
	game.turn.end_phase_waits_for_player = false
	game.end_turn()
	await get_tree().process_frame
	game.end_turn()
	await get_tree().process_frame
	assert_eq(game.active_id, 1)
	start_combat()
	assert_true(game.combat.declare_attack(victim, 2), "Not sick any more")


# --- combat after the steal ------------------------------------------------------------------------------------

func test_a_stolen_creature_blocks_for_its_new_controller_and_fights_with_kept_damage():
	var attacker := await put_creature(1, 3, 3)
	var thief_side := await put_creature(2, 2, 4)
	assert_true(control.take_control(thief_side, 1, {"tilted": true}))
	await get_tree().process_frame
	# the creature now defends player 1: player 2 attacks on their turn
	game.turn.end_phase_waits_for_player = false
	game.end_turn()
	await get_tree().process_frame
	assert_eq(game.active_id, 2)
	var raider := await put_creature(2, 3, 3)
	raider.entered_turn = 0
	start_combat()
	assert_true(game.combat.declare_attack(raider, game.player(1)))
	game.combat.confirm_attackers()
	assert_true(game.combat.declare_block(thief_side, game.combat.attack_of(raider)), game.combat.last_error)
	game.combat.confirm_blocks()
	assert_eq(game.player(1).life, LIFE, "The stolen creature blocked for player 1")
	assert_eq(game.stats.damage_on(thief_side, "Guard"), 3)
	assert_false(game.combat.declare_block(attacker, game.combat.attack_of(raider)), "Resolved already")


func test_an_attack_on_a_creature_that_changes_sides_to_the_attackers_side_is_removed():
	var attacker := await put_creature(1, 3, 3)
	var victim := await put_creature(2, 2, 2)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, victim))
	assert_true(control.take_control(victim, 1))
	await get_tree().process_frame
	assert_true(game.combat.attack_of(attacker).removed, "The target is on the attacker's side now")


func test_a_creature_stolen_while_it_attacks_is_removed_from_the_attack():
	var victim := await put_creature(1, 3, 3)
	start_combat()
	assert_true(game.combat.declare_attack(victim, 2))
	assert_true(control.take_control(victim, 2))
	await get_tree().process_frame
	assert_true(game.combat.attack_of(victim).removed)


# --- until end of turn --------------------------------------------------------------------------------------------

func test_control_until_end_of_turn_returns_in_the_end_phase():
	var victim := await put_creature(2, 3, 2)
	game.turn.end_phase_waits_for_player = true
	go_to_main()
	assert_true(control.take_control(victim, 1, {"until": "end_of_turn"}))
	await get_tree().process_frame
	assert_true(control.is_temporary(victim))
	assert_eq(control.temporary_home(victim), 2)
	assert_eq(victim.controller_id, 1)
	game.end_turn()
	await get_tree().process_frame
	assert_eq(game.active_id, 2, "The turn passed on")
	assert_eq(victim.controller_id, 2, "Back home in the END phase")
	assert_eq(victim.owner_id, 2)
	assert_true(victim in _grid_cards(2, "creatures"))
	assert_false(control.is_temporary(victim))


func test_a_double_agent_creature_enters_in_guard_position_and_goes_home_tilted_or_not_at_will():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1, {"until": "end_of_turn", "tilted": true}))
	await get_tree().process_frame
	assert_eq(victim.card_rotation, 90)
	assert_true(control.return_control(victim))
	await get_tree().process_frame
	assert_eq(victim.controller_id, 2)
	assert_eq(FateZones.zone_of(victim), "creatures")
	assert_false(control.return_control(victim), "Already home")


func test_return_control_of_a_permanent_steal_goes_to_the_owner():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1))
	assert_true(control.return_control(victim))
	await get_tree().process_frame
	assert_eq(victim.controller_id, 2)


func test_a_loaned_card_stolen_again_goes_back_to_the_first_lender():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1, {"until": "end_of_turn"}))
	await get_tree().process_frame
	assert_true(control.take_control(victim, 2, {"until": "end_of_turn"}))
	await get_tree().process_frame
	assert_eq(control.temporary_home(victim), 2)


func test_a_full_home_zone_sends_the_returning_card_to_its_owners_discard_pile():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1, {"until": "end_of_turn"}))
	await get_tree().process_frame
	var grid := game.player(2).grid("creatures")
	while grid.find_available_slot() != null:
		var filler := game.place_card_on_table(define_creature(1, 1), 2, "creatures")
		if filler == null:
			break
	assert_true(control.return_control(victim))
	await wait_seconds(0.3)
	assert_eq(victim.get_parent(), _discard(2))


# --- dying ----------------------------------------------------------------------------------------------------------

func test_a_stolen_creature_that_is_destroyed_goes_to_its_owners_discard_pile():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1))
	await get_tree().process_frame
	assert_true(game.effects.destroy(victim))
	await wait_seconds(0.3)
	assert_eq(victim.get_parent(), _discard(2), "Owner's discard, not the controller's")
	assert_false(victim in _discard(1).get_all_cards())


func test_a_loaned_creature_that_dies_is_forgotten_and_goes_to_its_owners_pile():
	var victim := await put_creature(2, 3, 2)
	assert_true(control.take_control(victim, 1, {"until": "end_of_turn"}))
	await get_tree().process_frame
	assert_true(game.effects.destroy(victim))
	await wait_seconds(0.3)
	assert_eq(victim.get_parent(), _discard(2))
	assert_false(control.is_temporary(victim))


func test_the_heal_option_forgets_damage():
	var victim := await put_creature(2, 3, 2)
	game.stats.apply_damage(victim, "Strike", 2)
	assert_true(control.take_control(victim, 1, {"heal": true}))
	await get_tree().process_frame
	assert_eq(game.stats.current(victim, "Strike"), 3)


# --- the energy zone ---------------------------------------------------------------------------------------------------

func test_claiming_into_the_energy_zone_makes_it_a_face_down_untapped_energy_card():
	var theirs := await put_creature(2, 3, 2)
	game.stats.apply_damage(theirs, "Strike", 1)
	game.stats.add_modifier(theirs, "Strike", 1, FateStats.EXPIRY_PERMANENT)
	theirs.set_card_rotation(90)
	assert_true(control.take_control(theirs, 1, {"zone": "energy"}))
	await get_tree().process_frame
	assert_eq(FateZones.zone_of(theirs), "energy")
	assert_true(theirs in _grid_cards(1, "energy"))
	assert_false(theirs in _grid_cards(2, "creatures"))
	assert_true(theirs.is_energy)
	assert_false(theirs.is_faceup, "Face-down")
	assert_eq(theirs.card_rotation, 0, "Untapped")
	assert_eq(theirs.controller_id, 1)
	assert_eq(theirs.owner_id, 2, "Owner unchanged")
	assert_eq(game.stats.damage_on(theirs, "Strike"), 0, "No longer a creature: damage gone")
	assert_eq(game.stats.modifier_total(theirs, "Strike"), 0)
	assert_true(theirs in control.controlled_not_owned(1), "Counts for 'Count control'")
	assert_true(theirs in control.controlled_by_owner(2))
	assert_false(FateZones.is_creature_in_play(theirs))
	assert_eq(theirs.entered_turn, 0)


func test_a_claimed_card_pays_for_the_new_controllers_cards_and_tells_its_script_it_left():
	var seen: Array = []
	var before := game.mana.untapped_energy(1).size()
	var theirs := await put_creature(2, "Moral Captain")
	var listener = _LeaveRecorder.new("Moral Captain", seen)
	game.card_effects.register(listener)
	assert_true(control.take_control(theirs, 1, {"zone": "energy"}))
	await get_tree().process_frame
	assert_eq(game.mana.untapped_energy(1).size(), before + 1, "One more mana for the new controller")
	assert_eq(seen, [["leave", "energy", true]])
	game.card_effects.unregister("Moral Captain")


func test_claiming_your_own_creature_into_your_energy_zone_works():
	var mine := await put_creature(1, 2, 2)
	assert_true(control.take_control(mine, 1, {"zone": "energy"}))
	await get_tree().process_frame
	assert_true(mine in _grid_cards(1, "energy"))
	assert_true(mine.is_energy)


func test_the_cards_attached_to_a_claimed_creature_go_to_their_owners_discard_pile():
	var wielder := await put_creature(2, "Spirit Wielder")
	var energy := await put_energy(2, "Thrang's Crafting Table")
	var embody = game.keywords.get_keyword("Embody")
	assert_true(embody.embody(wielder, energy, true))
	var relic := await put_on_table(2, "Garbage Heap", "relics")
	assert_true(game.equip.equip(relic, wielder))
	assert_true(control.take_control(wielder, 1, {"zone": "energy"}))
	await wait_seconds(0.4)
	assert_eq(energy.get_parent(), _discard(2))
	assert_eq(relic.get_parent(), _discard(2))
	assert_true(wielder.attachments.is_empty())
	assert_true(wielder in _grid_cards(1, "energy"))


# --- the board state --------------------------------------------------------------------------------------------------------

func test_a_stolen_creature_survives_a_board_state_round_trip():
	var victim := await put_creature(2, "Moral Captain")
	game.stats.apply_damage(victim, "Strike", 1)
	assert_true(control.take_control(victim, 1))
	await get_tree().process_frame
	var state := capture_board()
	var entry = null
	for e in state.data["players"]["1"]["creatures"]:
		if e != null and e["card"] == "Moral Captain":
			entry = e
	assert_not_null(entry, "Listed under the controller's creatures")
	assert_eq(entry.get("owner"), 2)
	assert_false(entry.has("controller"), "The controller is the zone's player (the default)")
	await load_board(state)
	var back: Card = null
	for c in _grid_cards(1, "creatures"):
		if c.canonical_name == "Moral Captain":
			back = c
	assert_not_null(back)
	assert_eq(back.owner_id, 2)
	assert_eq(back.controller_id, 1)
	assert_eq(game.stats.damage_on(back, "Strike"), 1)


func test_the_energy_embodied_by_a_stolen_creature_keeps_its_owner_in_a_round_trip():
	var wielder := await put_creature(2, "Spirit Wielder")
	var energy := await put_energy(2, "Thrang's Crafting Table")
	assert_true(game.keywords.get_keyword("Embody").embody(wielder, energy, true))
	assert_true(control.take_control(wielder, 1))
	await get_tree().process_frame
	await load_board(capture_board())
	var back: Card = null
	for c in _grid_cards(1, "creatures"):
		if c.canonical_name == "Spirit Wielder":
			back = c
	assert_not_null(back)
	assert_eq(back.attachments.size(), 1)
	assert_eq(back.attachments[0].owner_id, 2, "The attached energy is still player 2's card")
	assert_eq(back.attachments[0].controller_id, 1)


# A card script that records leave events
class _LeaveRecorder:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var log: Array

	func _init(name_of_card: String, into: Array) -> void:
		card_name = name_of_card
		log = into

	func on_leave(card: Card, destination: String) -> void:
		log.append(["leave", destination, card.is_energy])
