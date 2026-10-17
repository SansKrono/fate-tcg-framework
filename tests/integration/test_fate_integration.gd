extends "res://tests/FateCommon.gd"
# Integration checks across the turn system, mana, combat, stats and keywords (stage 3 wrap-up).


func test_pay_generic_taps_energy_and_refuses_when_short():
	await fill_mana(1)
	go_to_main()
	assert_eq(total_mana(game.mana_pool(1)), 6)
	assert_true(game.mana.can_pay_generic(1, 4))
	assert_true(game.mana.pay_generic(1, 4), "4 of 6 mana paid")
	assert_eq(total_mana(game.mana_pool(1)), 2, "Four energy cards were tapped")
	assert_false(game.mana.pay_generic(1, 3), "Only 2 left")
	assert_eq(total_mana(game.mana_pool(1)), 2, "Nothing is tapped by a refused payment")
	assert_true(game.mana.pay_generic(1, 0), "Paying nothing always works")


func test_pay_generic_spares_the_cards_to_avoid():
	await fill_mana(1, 1)
	go_to_main()
	var keep: Card = game.mana.untapped_energy(1)[0]
	assert_true(game.mana.pay_generic(1, 1, [keep], true))
	assert_eq(keep.card_rotation, 0, "The card to avoid stays untapped when others can pay")
	assert_true(game.mana.pay_generic(1, 1, [keep], true), "It is used when nothing else is left")
	assert_eq(keep.card_rotation, 90)


func test_occupied_creature_cannot_be_tilted_back():
	go_to_main()
	var occupied := await put_creature(1, 2, 2, {}, false, "occupied")
	var standing := await put_creature(1, 2, 2)
	assert_false(game.can_tilt(occupied), "An occupied creature stays tilted")
	assert_true(game.can_tilt(standing), "A creature in the creature zone can be positioned")


func test_whole_turn_cycle_with_combat_damage_and_reset():
	# Player 1 attacks a guarding creature; damage lasts until player 1's own next maintenance
	var attacker := await put_creature(1, 3, 3)
	var blocker := await put_creature(2, 2, 2, {}, true)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, blocker), "Attack declared")
	game.combat.confirm_attackers()
	assert_eq(game.phase, FateGame.Phase.COMBAT_INTERCEPT)
	assert_true(game.combat.declare_block(blocker, game.combat.attack_of(attacker)))
	game.combat.confirm_blocks()
	await get_tree().process_frame
	assert_false(FateZones.is_creature_in_play(blocker), "Strike 3 beats Guard 2: the blocker is destroyed")
	assert_eq(blocker.get_parent(), FateZones.container("discard", 2), "It goes to its owner's discard pile")
	assert_eq(game.stats.current(attacker, "Strike"), 1, "The attacker lost 2 Strike (3 - 2)")
	assert_eq(attacker.get_property("Strike"), 1, "The card face shows the damage")
	# On to player 2's turn and back: the damage is reset at player 1's maintenance
	game.end_turn()
	assert_eq(game.active_id, 2)
	assert_eq(game.stats.current(attacker, "Strike"), 1, "Damage survives the opponent's maintenance")
	game.draw_extra_card()
	game.end_turn()
	assert_eq(game.active_id, 1)
	assert_eq(game.stats.current(attacker, "Strike"), 3, "Reset at the owner's maintenance")


func test_unblocked_attack_reduces_life_and_can_end_the_game():
	var attacker := await put_creature(1, 20, 1)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, game.player(2)))
	run_combat()
	assert_eq(game.player(2).life, 0, "Strike 20 on 20 life")
	assert_true(game.is_over, "The game is over")
	assert_eq(game.winner_id, 1)
