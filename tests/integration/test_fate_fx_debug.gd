extends "res://tests/FateCommon.gd"
# Debug Card (cards/FxDebugCard.gd): "Occupy: create a Debug Token".


func _debug_tokens(pid: int) -> Array:
	return game.creatures_in_play(pid).filter(func(c): return c.canonical_name == "Debug Token")


func test_debug_card_occupies_and_creates_a_debug_token() -> void:
	await empty_hand(1)
	go_to_main()
	var debug := await put_creature(1, "Debug Card")
	assert_true(await game.actions.run(debug, "debug"))
	await wait_seconds(0.1)
	assert_eq(_debug_tokens(1).size(), 1, "a Debug Token was created")
	assert_eq(FateZones.zone_of(debug), "occupied")
	assert_false(await game.actions.run(debug, "debug"), "already occupied")
	assert_eq(_debug_tokens(1).size(), 1)
