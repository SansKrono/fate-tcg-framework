extends "res://tests/FateCommon.gd"
# Tests of the Fate turn system: the ten-step turn, the energy choice, playing cards in
# the main phase and mana payment. Rules: docs/FATE_RULES_SPEC.md, Sections 1 and 2.
# Setup and helpers: tests/FateCommon.gd. The game starts at turn 1, player 1, ENERGY phase.
#
# Cards used (all single-domain): Innovation "Garbage Heap" (relic, 1 + I), "Skulking Goblin"
# (creature, 1 + I), "Goblin Ledgerkeeper" (creature, 0 + I), "Battle Smith" (creature,
# 1 + II), "Rapid Scavenging" (regular spell, 2), "Factory Shutdown" (reaction, 2);
# Primal "Beetle Brawler" (creature, 1 + P).

const Phase := FateGame.Phase


# The stage 1 tests describe a turn WITHOUT the combat manager: with no combat object the three
# combat phases are passed at once. Stage 2 gave the game a real FateCombat, so these tests take
# it out again; the turn machine and its stand-in FakeCombat are what is tested here, the real
# combat manager is tested in test_fate_combat.gd.
func before_each():
	await super.before_each()
	game.combat = null


# A stand-in for the combat object of stage 2: records the hooks the turn machine calls
class FakeCombat:
	extends RefCounted
	var calls := []
	var game: FateGame
	# Advance from inside the hook, as a combat object with nothing to do could
	var advance_at_once := false

	func begin_declaration() -> void:
		_hook("declare")

	func begin_intercept() -> void:
		_hook("intercept")

	func begin_resolution() -> void:
		_hook("resolve")

	func cancel_combat() -> void:
		calls.append("cancel")

	func _hook(hook_name: String) -> void:
		calls.append(hook_name)
		if advance_at_once:
			game.advance_phase()


func _phase_log() -> Array:
	var log := []
	game.phase_begins.connect(func(pid, p): log.append("%d:%s" % [pid, FateTurn.phase_name(p)]))
	return log


# Plays through the energy phase by drawing an extra card
func _to_main() -> void:
	game.draw_extra_card()
	assert_eq(game.phase, Phase.MAIN, "Test setup: main phase reached")


# --- phases and signals ------------------------------------------------------------

func test_game_starts_in_the_energy_phase_of_turn_one():
	assert_eq(game.active_id, 1)
	assert_eq(game.turn_number, 1)
	assert_eq(game.phase, Phase.ENERGY, "Maintenance and draw already ran by themselves")
	assert_false(game.advance_phase(), "No skipping the energy phase (D3)")
	assert_eq(game.phase, Phase.ENERGY)
	assert_eq(game.energy_choice, "")


func test_phase_order_and_signals():
	_to_main()
	var phases := _phase_log()
	var counts := {"ended": 0}
	game.phase_ended.connect(func(): counts.ended += 1)
	var turns := []
	game.turn_started.connect(func(pid, n): turns.append([pid, n]))
	var finished := []
	game.turn_ended.connect(func(pid): finished.append(pid))
	var order := []
	game.end_phase_begins.connect(func(pid): order.append("end_phase_begins"))
	game.end_of_turn_expiry.connect(func(pid): order.append("expiry"))
	game.turn_ended.connect(func(pid): order.append("turn_ended"))
	game.turn_started.connect(func(pid, n): order.append("turn_started"))
	# With no combat object the three combat phases are entered and passed at once
	assert_null(game.combat)
	assert_true(game.advance_phase(), "Next phase from MAIN goes to combat")
	assert_eq(phases, ["1:Combat: declare attackers", "1:Combat: intercept", "1:Combat: resolve",
			"1:End", "2:Maintenance", "2:Draw", "2:Energy"])
	assert_eq(counts.ended, 7, "Every phase end is announced")
	assert_eq(turns, [[2, 2]], "The next player's turn started")
	assert_eq(finished, [1])
	assert_eq(order, ["end_phase_begins", "expiry", "turn_ended", "turn_started"],
			"End phase, expiry, then the turn changes")
	assert_eq(game.active_id, 2)
	assert_eq(game.phase, Phase.ENERGY, "Automatic phases ran, the player has to choose")


func test_phase_begins_reaches_card_scripts_through_the_propagator():
	var seen := []
	cfc.signal_propagator.signal_received.connect(func(trigger_card, trigger, details):
		if trigger == "phase_begins":
			seen.append([trigger_card, details.phase, details.player_id]))
	_to_main()
	game.advance_phase()
	var phases := []
	for s in seen:
		assert_eq(s[0], game, "The game node is the trigger card")
		phases.append(s[1])
	assert_eq(phases, [Phase.MAIN, Phase.COMBAT_DECLARE, Phase.COMBAT_INTERCEPT,
			Phase.COMBAT_RESOLVE, Phase.END, Phase.MAINTENANCE, Phase.DRAW, Phase.ENERGY])


func test_end_phase_can_wait_for_the_player():
	game.turn.end_phase_waits_for_player = true
	_to_main()
	assert_true(game.advance_phase())
	assert_eq(game.phase, Phase.END, "The turn waits in the end phase")
	assert_eq(game.active_id, 1)
	assert_true(game.advance_phase())
	assert_eq(game.active_id, 2)
	assert_eq(game.phase, Phase.ENERGY)


func test_end_turn_jumps_to_the_end_from_any_phase():
	var phases := _phase_log()
	game.end_turn()
	assert_eq(phases, ["1:End", "2:Maintenance", "2:Draw", "2:Energy"],
			"From the energy phase the phases in between are not entered")
	assert_eq(game.active_id, 2)
	assert_eq(game.turn_number, 2)
	_to_main()
	game.end_turn()
	assert_eq(game.active_id, 1)
	assert_eq(game.turn_number, 3)
	assert_eq(game.phase, Phase.ENERGY)


func test_combat_phases_call_the_combat_object():
	var combat := FakeCombat.new()
	combat.game = game
	game.combat = combat
	_to_main()
	assert_true(game.advance_phase())
	assert_eq(game.phase, Phase.COMBAT_DECLARE, "The turn waits for the combat object")
	assert_eq(combat.calls, ["declare"])
	assert_eq(game.active_id, 1)
	assert_true(game.advance_phase(), "The combat object says it is done")
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	assert_true(game.advance_phase())
	assert_eq(game.phase, Phase.COMBAT_RESOLVE)
	assert_eq(combat.calls, ["declare", "intercept", "resolve"])
	assert_true(game.advance_phase(), "After resolving, the turn ends")
	assert_eq(game.active_id, 2)
	assert_eq(game.phase, Phase.ENERGY)


func test_combat_object_may_advance_from_inside_its_hooks():
	var combat := FakeCombat.new()
	combat.game = game
	combat.advance_at_once = true
	game.combat = combat
	_to_main()
	game.advance_phase()
	assert_eq(combat.calls, ["declare", "intercept", "resolve"])
	assert_eq(game.active_id, 2)
	assert_eq(game.phase, Phase.ENERGY)


func test_ending_the_turn_cancels_the_combat():
	var combat := FakeCombat.new()
	combat.game = game
	game.combat = combat
	_to_main()
	game.advance_phase()
	game.advance_phase()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	game.end_turn()
	assert_eq(combat.calls, ["declare", "intercept", "cancel"])
	assert_eq(game.active_id, 2)


func test_next_phase_in_combat_asks_the_combat_object():
	var combat := FakeCombat.new()
	combat.game = game
	game.combat = combat
	_to_main()
	game.advance_phase()
	# No next_requested() method on the stand-in: the press advances
	assert_true(game.can_request_next_phase())
	assert_true(game.request_next_phase())
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)


# --- maintenance ---------------------------------------------------------------------

func test_maintenance_untaps_and_returns_occupied_cards():
	var energy1 := await put_energy(1, "Scrap Cannon", true)
	var energy2 := await put_energy(1, "Garbage Heap", true)
	var relic := await put_on_table(1, "Garbage Heap", "relics")
	var guard := await put_on_table(1, "Battle Smith", "creatures")
	var occupied := await put_on_table(1, "Skulking Goblin", "occupied")
	var enemy_energy := await put_energy(2, "Rustmarket Tinkerer", true)
	relic.set_card_rotation(90)
	guard.set_card_rotation(90)
	occupied.set_card_rotation(90)
	assert_eq(game.player(1).cards_in_grid("occupied").size(), 1)
	game.end_turn()
	# The other player's maintenance untapped their own energy only
	assert_eq(enemy_energy.card_rotation, 0, "Player 2's maintenance untaps player 2's energy")
	assert_eq(energy1.card_rotation, 90, "Player 1's cards stay tapped during player 2's turn")
	enemy_energy.set_card_rotation(90)
	_to_main()
	# Record what is still tapped when maintenance_started fires (before anything untaps)
	var seen := {}
	var events := []
	game.phase_begins.connect(func(pid, p): events.append("phase:" + FateTurn.phase_name(p)))
	game.maintenance_started.connect(func(pid):
		events.append("maintenance_started")
		seen["pid"] = pid
		seen["energy"] = energy1.card_rotation
		seen["guard"] = guard.card_rotation
		seen["occupied_zone"] = game.player(1).cards_in_grid("occupied").size())
	game.end_turn()
	assert_eq(game.active_id, 1)
	await wait_seconds(0.8)
	var start := events.find("phase:Maintenance")
	assert_eq(events.slice(start, start + 3), ["phase:Maintenance", "maintenance_started", "phase:Draw"],
			"maintenance_started comes at the start of the maintenance phase")
	assert_eq(seen.pid, 1)
	assert_eq(seen.energy, 90, "maintenance_started fires before the energy untaps")
	assert_eq(seen.guard, 90, "... and before the creatures untap")
	assert_eq(seen.occupied_zone, 1, "... and before the occupied card returns")
	assert_eq(energy1.card_rotation, 0, "Energy untapped")
	assert_eq(energy2.card_rotation, 0, "Energy untapped")
	assert_eq(relic.card_rotation, 0, "Relics untapped")
	assert_eq(guard.card_rotation, 0, "Creatures return to the strike position")
	assert_eq(occupied.card_rotation, 0, "The occupied creature untapped")
	assert_eq(game.player(1).cards_in_grid("occupied").size(), 0, "The occupied zone is empty")
	assert_eq(occupied.get_parent(), board)
	assert_eq(occupied._placement_slot.get_grid_name(), "Creatures P1", "It is back in the creature zone")
	assert_eq(occupied._placement_slot.occupying_card, occupied)
	assert_true(guard._placement_slot != occupied._placement_slot, "On a slot of its own")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 2)
	await wait_card_settled(occupied)
	assert_almost_eq(occupied.global_position, occupied._placement_slot.global_position,
			Vector2(2, 2), "The card moved to the slot")
	assert_eq(enemy_energy.card_rotation, 90, "Maintenance only untaps the active player's cards")
	assert_eq(total_mana(game.mana_pool(1)), 2)


func test_maintenance_leaves_a_creature_in_a_full_creature_zone():
	var occupied := await put_on_table(1, "Skulking Goblin", "occupied")
	for _i in range(6):
		await put_on_table(1, "Battle Smith", "creatures")
	occupied.set_card_rotation(90)
	game.end_turn()
	game.end_turn()
	assert_eq(occupied.card_rotation, 0, "Untapped")
	assert_eq(occupied._placement_slot.get_grid_name(), "Occupied P1",
			"With no free creature slot it stays where it is")


# --- draw phase --------------------------------------------------------------------------

func test_the_draw_phase_draws_one_card():
	assert_false(FateGame.FIRST_PLAYER_SKIPS_FIRST_DRAW, "D1: every turn draws")
	assert_eq(FateZones.container("hand", 1).get_card_count(), FateGame.STARTING_HAND + 1,
			"The first player drew in turn 1")
	assert_eq(FateZones.container("hand", 2).get_card_count(), FateGame.STARTING_HAND)
	var deck_count: int = FateZones.container("deck", 2).get_card_count()
	game.end_turn()
	await wait_seconds(0.6)
	assert_eq(FateZones.container("hand", 2).get_card_count(), FateGame.STARTING_HAND + 1)
	assert_eq(FateZones.container("deck", 2).get_card_count(), deck_count - 1)


func test_first_player_can_skip_the_first_draw():
	var hand: Hand = FateZones.container("hand", 1)
	var before := hand.get_card_count()
	game.first_player_skips_first_draw = true
	game.turn_number = 0
	game.start_turn()
	assert_eq(game.turn_number, 1)
	assert_eq(game.active_id, 1)
	assert_eq(hand.get_card_count(), before, "The first turn does not draw")
	game.first_player_skips_first_draw = false
	game.turn_number = 0
	game.start_turn()
	await wait_seconds(0.4)
	assert_eq(hand.get_card_count(), before + 1, "... unless the rule is off")


func test_empty_deck_does_nothing_for_now():
	for c in FateZones.container("deck", 2).get_all_cards():
		c.move_to(FateZones.container("removed", 2), -1, null, ["Scripted"])
	await wait_seconds(0.3)
	var empties := []
	game.deck_empty.connect(func(pid): empties.append(pid))
	var hand_count: int = FateZones.container("hand", 2).get_card_count()
	game.end_turn()
	assert_eq(empties, [2], "The hook for the later win/loss rule fired")
	assert_eq(FateZones.container("hand", 2).get_card_count(), hand_count)
	assert_eq(game.phase, Phase.ENERGY, "The turn carries on")


# --- energy phase --------------------------------------------------------------------------

func test_energy_phase_play_a_card_as_energy():
	var choices := []
	game.energy_phase_choice_made.connect(func(): choices.append(game.energy_choice))
	var hand: Hand = FateZones.container("hand", 1)
	var before := hand.get_card_count()
	var card := find_in_hand(1, func(c): return true)
	assert_true(game.can_play_as_energy(card))
	assert_true(game.play_as_energy(card))
	await wait_seconds(0.5)
	assert_eq(choices, ["energy"], "The choice was announced once")
	assert_eq(game.energy_choice, "energy")
	assert_eq(game.phase, Phase.MAIN, "The choice ends the phase")
	assert_eq(hand.get_card_count(), before - 1)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 1)
	assert_false(card.is_faceup, "Energy is face-down")
	assert_false(game.draw_extra_card(), "Energy OR draw, not both")
	assert_eq(hand.get_card_count(), before - 1)


func test_energy_phase_draw_an_extra_card():
	var choices := []
	game.energy_phase_choice_made.connect(func(): choices.append(game.energy_choice))
	var hand: Hand = FateZones.container("hand", 1)
	var before := hand.get_card_count()
	assert_true(game.can_draw_extra_card())
	assert_true(game.draw_extra_card())
	await wait_seconds(0.5)
	assert_eq(choices, ["draw"])
	assert_eq(hand.get_card_count(), before + 1)
	assert_eq(game.phase, Phase.MAIN)
	assert_false(game.can_play_as_energy(find_in_hand(1, func(c): return true)),
			"... and no energy play afterwards")
	assert_false(game.draw_extra_card(), "Only one extra draw")
	assert_eq(hand.get_card_count(), before + 1)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 0)


func test_energy_phase_needs_a_choice():
	assert_false(game.advance_phase())
	assert_eq(game.phase, Phase.ENERGY)
	assert_false(game.can_end_turn(), "The UI does not offer End turn before the choice")
	assert_false(game.can_request_next_phase())


func test_energy_phase_is_for_the_active_player_only():
	var theirs := find_in_hand(2, func(c): return true)
	assert_false(game.can_play_as_energy(theirs))
	assert_false(game.play_as_energy(theirs))
	await theirs.execute_scripts()
	assert_eq(theirs.get_parent(), FateZones.container("hand", 2), "A double click does nothing either")
	assert_eq(game.phase, Phase.ENERGY)
	assert_eq(game.player(2).cards_in_grid("energy").size(), 0)


func test_double_click_in_the_energy_phase_plays_energy():
	var card := find_in_hand(1, func(c): return true)
	await card.execute_scripts()
	await wait_seconds(0.4)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 1)
	assert_eq(game.phase, Phase.MAIN)


func test_no_energy_play_in_other_phases():
	_to_main()
	var card := find_in_hand(1, func(c): return true)
	assert_false(game.can_play_as_energy(card), "Not in the main phase")
	await card.execute_scripts()
	assert_eq(card.get_parent(), FateZones.container("hand", 1))
	game.end_turn()
	game.end_turn()
	assert_true(game.can_play_as_energy(find_in_hand(1, func(c): return true)),
			"Available again in the next energy phase")


func test_clicking_the_deck_draws_the_extra_card_in_the_energy_phase():
	var hand: Hand = FateZones.container("hand", 1)
	var before := hand.get_card_count()
	board._on_deck_clicked(FateZones.container("deck", 2))
	assert_eq(game.phase, Phase.ENERGY, "The other player's deck does nothing")
	board._on_deck_clicked(FateZones.container("deck", 1))
	assert_eq(game.phase, Phase.MAIN)
	await wait_seconds(0.5)
	assert_eq(hand.get_card_count(), before + 1)
	board._on_deck_clicked(FateZones.container("deck", 1))
	await wait_seconds(0.3)
	assert_eq(hand.get_card_count(), before + 1, "No more draws outside the energy phase")


# --- main phase: playing cards --------------------------------------------------------------

func test_cards_are_played_in_the_main_phase_only():
	await empty_hand(1)
	await fill_mana(1)
	var card := await put_in_hand(1, "Goblin Ledgerkeeper")
	card.move_to(board)
	await wait_seconds(0.5)
	assert_eq(card.get_parent(), FateZones.container("hand", 1), "Not in the energy phase")
	_to_main()
	card.move_to(board)
	await wait_seconds(0.6)
	assert_eq(card.get_parent(), board, "In the main phase it is played")
	assert_eq(card._placement_slot.get_grid_name(), "Creatures P1")
	assert_eq(card.entered_turn, 1, "It records the turn it entered play")


func test_no_playing_in_combat_phases_or_the_end_of_the_turn():
	var combat := FakeCombat.new()
	combat.game = game
	game.combat = combat
	await empty_hand(1)
	await fill_mana(1)
	var card := await put_in_hand(1, "Goblin Ledgerkeeper")
	_to_main()
	game.advance_phase()
	assert_eq(game.phase, Phase.COMBAT_DECLARE)
	assert_false(game.can_play_from_hand(card))
	card.move_to(board)
	await wait_seconds(0.5)
	assert_eq(card.get_parent(), FateZones.container("hand", 1), "Denied in a combat phase")
	assert_eq(card.entered_turn, 0)


func test_only_the_owner_plays_cards_in_their_own_turn():
	await empty_hand(1)
	await empty_hand(2)
	await fill_mana(1)
	await fill_mana(2)
	var mine := await put_in_hand(1, "Goblin Ledgerkeeper")
	var theirs := await put_in_hand(2, "Skulking Goblin")
	_to_main()
	theirs.move_to(board)
	await wait_seconds(0.5)
	assert_eq(theirs.get_parent(), FateZones.container("hand", 2), "Not the other player's cards")
	assert_eq(total_mana(game.mana_pool(2)), 6, "... and no mana was spent")
	game.end_turn()
	mine.move_to(board)
	await wait_seconds(0.5)
	assert_eq(mine.get_parent(), FateZones.container("hand", 1), "Player 1 cannot play in player 2's turn")


func test_playing_by_dragging_a_card_to_the_table():
	await empty_hand(1)
	await fill_mana(1)
	var card := await put_in_hand(1, "Goblin Ledgerkeeper")
	_to_main()
	var slot: BoardPlacementSlot = FateZones.grid("creatures", 1).get_slot(0)
	await drag_drop(card, slot.global_position + Vector2(20, 20))
	await wait_seconds(0.5)
	assert_eq(card.get_parent(), board, "Dropped on the creature zone")
	assert_eq(card._placement_slot, slot)
	assert_eq(total_mana(game.mana_pool(1)), 5, "The cost was paid")


func test_a_refused_drop_costs_nothing():
	# The board can refuse a play after the rules allowed it (here: the creature zone is
	# full), and the payment only happens once the card really lands on the table
	await empty_hand(1)
	await fill_mana(1)
	for _i in range(6):
		await put_on_table(1, "Battle Smith", "creatures")
	var card := await put_in_hand(1, "Goblin Ledgerkeeper")
	_to_main()
	assert_true(game.can_play_from_hand(card), "The rules allow it")
	card.move_to(board)
	await wait_seconds(0.6)
	assert_eq(card.get_parent(), FateZones.container("hand", 1), "No free slot: back in the hand")
	assert_eq(total_mana(game.mana_pool(1)), 6, "Nothing was paid")
	assert_eq(card.entered_turn, 0)
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 6)


func test_entered_turn_is_the_turn_it_was_played():
	await empty_hand(1)
	await fill_mana(1)
	var relic := await put_in_hand(1, "Garbage Heap")
	_to_main()
	relic.move_to(board)
	await wait_seconds(0.6)
	assert_eq(relic._placement_slot.get_grid_name(), "Relics P1")
	assert_eq(relic.entered_turn, 1)
	game.end_turn()
	game.end_turn()
	assert_eq(game.turn_number, 3)
	var creature := await put_in_hand(1, "Goblin Ledgerkeeper")
	_to_main()
	creature.move_to(board)
	await wait_seconds(0.6)
	assert_eq(creature.entered_turn, 3)
	assert_eq(relic.entered_turn, 1, "Other cards keep theirs")


func test_creatures_are_tilted_in_the_main_phase_only():
	var creature := await put_on_table(1, "Battle Smith", "creatures")
	var theirs := await put_on_table(2, "Battle Smith", "creatures")
	var relic := await put_on_table(1, "Garbage Heap", "relics")
	var buttons = creature.get_node("Control/ManipulationButtons")
	buttons._on_Rot90_pressed()
	assert_eq(creature.card_rotation, 0, "Not in the energy phase")
	_to_main()
	buttons._on_Rot90_pressed()
	assert_eq(creature.card_rotation, 90, "Guard position in the main phase")
	buttons._on_Rot90_pressed()
	assert_eq(creature.card_rotation, 0, "... and back to strike")
	theirs.get_node("Control/ManipulationButtons")._on_Rot90_pressed()
	assert_eq(theirs.card_rotation, 0, "Not the other player's creatures")
	relic.get_node("Control/ManipulationButtons")._on_Rot90_pressed()
	assert_eq(relic.card_rotation, 0, "Only creatures tilt")


# --- mana ------------------------------------------------------------------------------------

func test_mana_pool_counts_untapped_energy_per_domain():
	await put_energy(1, "Scrap Cannon")
	await put_energy(1, "Garbage Heap")
	await put_energy(1, "Beetle Brawler")
	await put_energy(1, "Dragon's Tooth", true)
	var pool := game.mana_pool(1)
	assert_eq(pool, {"Innovation": 2, "Chaos": 0, "Order": 0, "Primal": 1}, "Tapped energy is not mana")
	assert_eq(total_mana(game.mana_pool(2)), 0)


func test_paying_taps_energy_and_pays_pips_with_their_domain():
	await empty_hand(1)
	var inn1 := await put_energy(1, "Scrap Cannon")
	var inn2 := await put_energy(1, "Garbage Heap")
	var pri := await put_energy(1, "Beetle Brawler")
	var pri2 := await put_energy(1, "Dragon's Tooth")
	var goblin := await put_in_hand(1, "Skulking Goblin")
	# Beetle Brawler needs a Primal pip, so the Primal energy is kept for it
	var brawler := await put_in_hand(1, "Beetle Brawler")
	_to_main()
	var paid := []
	game.card_played.connect(func(c): paid.append(c))
	goblin.move_to(board)
	await wait_seconds(0.6)
	assert_eq(goblin.get_parent(), board)
	assert_eq(paid, [goblin])
	assert_eq(inn1.card_rotation, 90, "The Innovation pip was paid with Innovation")
	assert_eq(inn2.card_rotation, 90, "The generic cost took the other Innovation")
	assert_eq(pri.card_rotation, 0, "The Primal energy the hand still needs was kept")
	assert_eq(pri2.card_rotation, 0)
	assert_eq(game.mana_pool(1), {"Innovation": 0, "Chaos": 0, "Order": 0, "Primal": 2})
	assert_true(game.can_pay(brawler), "The card kept in hand is still affordable")


func test_generic_cost_is_paid_with_any_domain():
	await empty_hand(1)
	await put_energy(1, "Beetle Brawler")
	await put_energy(1, "Dragon's Tooth")
	var spell := await put_in_hand(1, "Rapid Scavenging")
	_to_main()
	assert_true(game.can_pay(spell), "Cost 2 with no pips: two Primal energy pay it")
	spell.move_to(board)
	await wait_seconds(0.7)
	assert_eq(total_mana(game.mana_pool(1)), 0)


func test_pips_need_their_own_domain():
	await empty_hand(1)
	for _i in range(3):
		await put_energy(1, "Beetle Brawler")
	var smith := await put_in_hand(1, "Battle Smith")
	_to_main()
	assert_eq(total_mana(game.mana_pool(1)), 3, "Three mana, as many as the cost")
	assert_false(game.can_pay(smith), "... but two of them must be Innovation")
	smith.move_to(board)
	await wait_seconds(0.5)
	assert_eq(smith.get_parent(), FateZones.container("hand", 1), "The card returns to the hand")
	assert_eq(total_mana(game.mana_pool(1)), 3, "Nothing was charged")
	assert_eq(smith.entered_turn, 0)


func test_insufficient_mana_denies_the_play():
	await empty_hand(1)
	await put_energy(1, "Scrap Cannon")
	await put_energy(1, "Garbage Heap", true)
	var smith := await put_in_hand(1, "Battle Smith")
	var goblin := await put_in_hand(1, "Skulking Goblin")
	_to_main()
	var hand_count: int = FateZones.container("hand", 1).get_card_count()
	assert_eq(total_mana(game.mana_pool(1)), 1, "One untapped energy: tapped energy does not count")
	goblin.move_to(board)
	await wait_seconds(0.5)
	assert_eq(goblin.get_parent(), FateZones.container("hand", 1), "Cost 1 + I needs two mana")
	smith.move_to(board)
	await wait_seconds(0.5)
	assert_eq(smith.get_parent(), FateZones.container("hand", 1))
	assert_eq(total_mana(game.mana_pool(1)), 1, "No cost was charged")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 0)
	assert_eq(FateZones.container("hand", 1).get_card_count(), hand_count)


func test_regular_spell_goes_to_the_discard_pile_after_paying():
	await empty_hand(1)
	await fill_mana(1, 1)
	await put_energy(1, "Scrap Cannon")
	var spell := await put_in_hand(1, "Rapid Scavenging")
	_to_main()
	var played := []
	game.card_played.connect(func(c): played.append(c))
	assert_eq(total_mana(game.mana_pool(1)), 3)
	spell.move_to(board)
	await wait_seconds(0.8)
	assert_eq(spell.get_parent(), FateZones.container("discard", 1), "The spell resolved into the discard pile")
	assert_eq(played, [spell])
	assert_eq(total_mana(game.mana_pool(1)), 1, "Its cost of 2 was paid")
	# Too expensive: a second one stays in the hand
	var second := await put_in_hand(1, "Fabrication Line")
	second.move_to(board)
	await wait_seconds(0.5)
	assert_eq(second.get_parent(), FateZones.container("hand", 1), "Cost 3 with 1 mana is denied")
	assert_eq(total_mana(game.mana_pool(1)), 1)


func test_reaction_spells_cannot_be_played_in_the_main_phase():
	await empty_hand(1)
	await fill_mana(1)
	var reaction := await put_in_hand(1, "Factory Shutdown")
	assert_true(reaction.is_reaction_spell())
	_to_main()
	assert_false(game.can_play_from_hand(reaction))
	reaction.move_to(board)
	await wait_seconds(0.5)
	assert_eq(reaction.get_parent(), FateZones.container("hand", 1), "D8: no reactions in the main phase")
	assert_eq(total_mana(game.mana_pool(1)), 6, "Nothing was charged")


func test_energy_cards_stay_tapped_until_the_next_maintenance():
	await empty_hand(1)
	var e1 := await put_energy(1, "Scrap Cannon")
	var e2 := await put_energy(1, "Garbage Heap")
	var goblin := await put_in_hand(1, "Skulking Goblin")
	_to_main()
	goblin.move_to(board)
	await wait_seconds(0.6)
	assert_eq(e1.card_rotation, 90)
	assert_eq(e2.card_rotation, 90)
	game.end_turn()
	assert_eq(e1.card_rotation, 90, "Still tapped in the opponent's turn")
	game.end_turn()
	assert_eq(e1.card_rotation, 0, "Untapped by the next maintenance")
	assert_eq(e2.card_rotation, 0)
	assert_eq(goblin._placement_slot.get_grid_name(), "Creatures P1", "The creature stays in play")


# --- the status bar --------------------------------------------------------------------------------

func test_status_bar_follows_the_phases():
	assert_eq(board.status_label.text, "Turn 1 - Player 1 - Energy")
	assert_true(board.draw_button.visible, "Draw extra card is offered in the energy phase")
	assert_false(board.draw_button.disabled)
	assert_true(board.next_button.disabled, "Next phase waits for the choice")
	assert_true(board.end_turn_button.disabled, "... and so does End turn")
	assert_ne(board.prompt_label.text, "")
	board.draw_button.pressed.emit()
	assert_eq(game.phase, Phase.MAIN)
	assert_eq(board.status_label.text, "Turn 1 - Player 1 - Main")
	assert_false(board.draw_button.visible, "Only in the energy phase")
	assert_false(board.next_button.disabled)
	assert_false(board.end_turn_button.disabled)
	board.next_button.pressed.emit()
	assert_eq(board.status_label.text, "Turn 2 - Player 2 - Energy", "No combat yet: next phase runs through to the next turn")
	board.draw_button.pressed.emit()
	board.end_turn_button.pressed.emit()
	assert_eq(board.status_label.text, "Turn 3 - Player 1 - Energy")


func test_status_bar_shows_life_and_untapped_mana():
	await put_energy(1, "Scrap Cannon")
	await put_energy(1, "Beetle Brawler")
	await put_energy(1, "Beetle Brawler", true)
	game.mana_changed.emit(1)
	assert_string_contains(board.mana_label.text, "P1 life 20 mana Inn 1, Pri 1")
	assert_string_contains(board.mana_label.text, "P2 life 20 mana -")
	game.player(2).life = 17
	assert_string_contains(board.mana_label.text, "P2 life 17")


func test_status_bar_fits_the_band_between_the_front_rows():
	var bar: Control = board.get_node("StatusBar")
	await get_tree().process_frame
	await get_tree().process_frame
	var top_player_front: float = FateZones.grid("creatures", 2).global_position.y \
			+ FateZones.grid("creatures", 2).size.y
	var bottom_label_top: float = FateZones.grid("creatures", 1).global_position.y - 20.0
	assert_gte(bar.position.y, top_player_front, "Below the top player's front row")
	assert_lte(bar.position.y + bar.get_combined_minimum_size().y, bottom_label_top,
			"Above the bottom player's grid labels")
	assert_lte(bar.position.x + bar.size.x, FateBoard.SCREEN.x)
	assert_lte(bar.get_combined_minimum_size().x, bar.size.x, "The controls fit the bar width")
