extends "res://tests/FateCommon.gd"
# The debug tools (FateDebug): spawning and moving any card, and the relaxed rules.


func test_debug_mode_is_off_at_the_start():
	assert_false(game.debug_mode)
	assert_false(board.debug.enabled)


func test_toggle_sets_the_game_flag():
	board.debug.set_enabled(true)
	assert_true(game.debug_mode)
	board.debug.set_enabled(false)
	assert_false(game.debug_mode)


func test_spawn_on_the_table_for_either_player():
	board.debug.set_enabled(true)
	var mine = await board.debug.spawn("Battle Smith", 1, "creatures")
	var theirs = await board.debug.spawn("Battle Smith", 2, "creatures")
	assert_eq(FateZones.zone_of(mine), "creatures")
	assert_eq(mine.owner_id, 1)
	assert_eq(FateZones.zone_of(theirs), "creatures")
	assert_eq(theirs.owner_id, 2)
	assert_eq(theirs._placement_slot.get_grid_name(), "Creatures P2")
	assert_eq(mine.entered_turn, 0, "Spawned cards are not summoning sick")


func test_spawn_in_the_hand_and_the_piles():
	board.debug.set_enabled(true)
	var hand: Hand = FateZones.container("hand", 2)
	var before := hand.get_card_count()
	var card = await board.debug.spawn("Ancient Tree", 2, "hand")
	await wait_seconds(0.5)
	assert_eq(card.get_parent(), hand)
	assert_eq(hand.get_card_count(), before + 1)
	var in_discard = await board.debug.spawn("Ancient Tree", 1, "discard")
	await wait_seconds(0.5)
	assert_eq(in_discard.get_parent(), FateZones.container("discard", 1))
	var in_removed = await board.debug.spawn("Ancient Tree", 1, "removed")
	await wait_seconds(0.5)
	assert_eq(in_removed.get_parent(), FateZones.container("removed", 1))


func test_spawned_energy_is_face_down_and_gives_mana():
	board.debug.set_enabled(true)
	var energy = await board.debug.spawn("Ancient Tree", 1, "energy")
	assert_true(energy.is_energy)
	assert_false(energy.is_faceup)
	assert_eq(FateZones.zone_of(energy), "energy")
	assert_eq(total_mana(game.mana_pool(1)), 1)


func test_spawn_reports_a_full_zone_and_unknown_cards():
	board.debug.set_enabled(true)
	for _i in range(6):
		await board.debug.spawn("Battle Smith", 1, "creatures")
	assert_null(await board.debug.spawn("Battle Smith", 1, "creatures"), "No free slot")
	assert_null(await board.debug.spawn("No such card", 1, "creatures"))


func test_move_a_card_to_the_other_player():
	board.debug.set_enabled(true)
	var card = await board.debug.spawn("Battle Smith", 1, "creatures")
	assert_true(await board.debug.move_card(card, 2, "occupied"))
	await wait_seconds(0.3)
	assert_eq(FateZones.zone_of(card), "occupied")
	assert_eq(card.owner_id, 2)
	assert_eq(card.card_rotation, 90, "Occupied creatures are tilted")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 0, "The old slot is free")
	assert_true(await board.debug.move_card(card, 1, "hand"))
	await wait_seconds(0.5)
	assert_eq(card.get_parent(), FateZones.container("hand", 1))


func test_moving_out_of_energy_makes_the_card_normal_again():
	board.debug.set_enabled(true)
	var card = await board.debug.spawn("Ancient Tree", 1, "energy")
	assert_true(await board.debug.move_card(card, 1, "relics"))
	await wait_seconds(0.3)
	assert_false(card.is_energy)
	assert_true(card.is_faceup)
	assert_eq(total_mana(game.mana_pool(1)), 0)


func test_delete_frees_the_slot():
	board.debug.set_enabled(true)
	var card = await board.debug.spawn("Battle Smith", 1, "creatures")
	board.debug.delete_card(card)
	await get_tree().process_frame
	assert_false(is_instance_valid(card) and card.is_inside_tree())
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 0)


func test_any_hand_card_can_be_played_for_free_at_any_time():
	# Player 2 has no energy and it is player 1's energy phase: normally refused
	await empty_hand(2)
	var card = await put_in_hand(2, "Goblin Ledgerkeeper")
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	card.move_to(board)
	await wait_seconds(0.5)
	assert_eq(card.get_parent(), FateZones.container("hand", 2), "Refused without debug mode")
	board.debug.set_enabled(true)
	card.move_to(board)
	await wait_seconds(0.5)
	assert_eq(card.get_parent(), board)
	assert_eq(FateZones.zone_of(card), "creatures")
	assert_eq(card.entered_turn, game.turn_number)


func test_debug_play_of_a_regular_spell_is_free():
	await empty_hand(1)
	var spell = await put_in_hand(1, "Primal Wraith")
	board.debug.set_enabled(true)
	spell.move_to(board)
	await wait_seconds(0.6)
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))


func test_debug_mode_allows_tilting_any_card_on_the_table():
	var card = await put_on_table(2, "Battle Smith", "creatures")
	assert_false(game.can_tilt(card), "Not player 2's turn")
	board.debug.set_enabled(true)
	assert_true(game.can_tilt(card))
	var relic = await put_on_table(1, "Ancient Tree", "relics")
	assert_true(game.can_tilt(relic))
