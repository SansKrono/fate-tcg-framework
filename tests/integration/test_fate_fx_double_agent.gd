extends "res://tests/FateCommon.gd"
# Double Agent (reaction): when a player declares attacks, take control of another creature you do not control
# until end of turn; it enters in guard position.


func _declare_attack_by_player_one() -> Card:
	await empty_hand(1)
	await empty_hand(2)
	await fill_mana(2, 3)
	var attacker := await put_creature(1, 3, 3)
	start_combat()
	game.reactions.hold_windows = true
	game.combat.declare_attack(attacker, game.player(2))
	return attacker


func test_double_agent_takes_an_attacker_until_end_of_turn_in_guard_position() -> void:
	var attacker := await _declare_attack_by_player_one()
	var spell := await put_in_hand(2, "Double Agent")
	game.combat.confirm_attackers()
	assert_not_null(game.reactions.open_window())
	assert_true(game.reactions.cast(spell), game.reactions.last_error)
	assert_eq(attacker.controller_id, 2)
	assert_eq(attacker.card_rotation, 90, "guard position")
	assert_eq(attacker.owner_id, 1)
	game.combat.next_requested()
	await wait_seconds(0.2)
	game.end_turn()
	await wait_seconds(0.2)
	assert_eq(attacker.controller_id, 1, "returned at end of turn")


func test_double_agent_cannot_be_cast_with_nothing_to_take() -> void:
	await empty_hand(2)
	await fill_mana(2, 3)
	start_combat()
	game.reactions.hold_windows = true
	game.combat.confirm_attackers()
	var spell := await put_in_hand(2, "Double Agent")
	assert_ne(game.reactions.cast_problem(spell), "", "no creature of the opponent")
