extends "res://tests/FateCommon.gd"
# Righteous Guard: Enters: create 1/1 soldiers equal to the number of Righteous Guards on your field.


func _soldiers(pid: int) -> Array:
	return game.creatures_in_play(pid).filter(func(c): return c.canonical_name == "Soldier Token")


func test_playing_a_righteous_guard_creates_a_soldier() -> void:
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()
	var guard := await put_in_hand(1, "Righteous Guard")
	assert_true(game.play_from_hand(guard))
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(guard), "creatures")
	var soldiers := _soldiers(1)
	assert_eq(soldiers.size(), 1, "one Righteous Guard, one soldier")
	assert_eq(game.stats.current(soldiers[0], "Strike"), 1)
	assert_eq(game.stats.current(soldiers[0], "Guard"), 1)
	assert_eq(soldiers[0].controller_id, 1)


func test_the_soldiers_equal_the_guards_on_your_field() -> void:
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()
	await put_creature(1, "Righteous Guard")
	await put_creature(2, "Righteous Guard")
	var guard := await put_in_hand(1, "Righteous Guard")
	game.play_from_hand(guard)
	await wait_seconds(0.2)
	assert_eq(_soldiers(1).size(), 2, "two of yours on the field, the opponent's does not count")
	assert_eq(_soldiers(2).size(), 0)
