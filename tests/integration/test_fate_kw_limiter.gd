extends "res://tests/FateCommon.gd"
# Tests of the limiter (src/custom/fate/FateLimiter.gd): Limiter X / "once per turn", "once per game", per
# card and per player counts, and the cost game.costs.once_per_turn / once_per_game.


func _tick_turn() -> void:
	game.turn_started.emit(game.active_id, game.turn_number + 1)


func test_once_per_turn_blocks_the_second_use_until_the_next_turn():
	var card := await put_creature(1, "Righteous Guard")
	assert_true(game.limiter.can_use(card, "x"))
	assert_true(game.limiter.use(card, "x"))
	assert_false(game.limiter.can_use(card, "x"))
	assert_false(game.limiter.use(card, "x"), "refused")
	assert_eq(game.limiter.uses(card, "x"), 1, "a refused use is not counted")
	assert_true(game.limiter.can_use(card, "y"), "keys are independent")
	_tick_turn()
	assert_true(game.limiter.can_use(card, "x"), "a new turn")
	assert_eq(game.limiter.uses(card, "x"), 0)


func test_limiter_x_allows_x_uses_a_turn():
	var card := await put_creature(1, "Righteous Guard")
	assert_true(game.limiter.use(card, "x", 3))
	assert_true(game.limiter.use(card, "x", 3))
	assert_eq(game.limiter.remaining(card, "x", 3), 1)
	assert_true(game.limiter.use(card, "x", 3))
	assert_false(game.limiter.use(card, "x", 3))
	assert_eq(game.limiter.remaining(card, "x", 3), 0)


func test_each_card_has_its_own_count():
	var a := await put_creature(1, "Righteous Guard")
	var b := await put_creature(1, "Righteous Guard")
	game.limiter.use(a, "x")
	assert_false(game.limiter.can_use(a, "x"))
	assert_true(game.limiter.can_use(b, "x"), "two copies of a card do not share a count")


func test_once_per_game_survives_turns():
	var card := await put_creature(1, "Righteous Guard")
	assert_true(game.limiter.use(card, "wish", 1, game.limiter.GAME))
	_tick_turn()
	assert_false(game.limiter.can_use(card, "wish", 1, game.limiter.GAME), "still used")
	assert_true(game.limiter.can_use(card, "wish"), "the turn mode is a different count")


func test_player_scope_is_shared_by_the_players_cards():
	assert_true(game.limiter.use_player(1, "first_spell"))
	assert_false(game.limiter.can_use_player(1, "first_spell"))
	assert_true(game.limiter.can_use_player(2, "first_spell"), "the other player has their own")
	assert_eq(game.limiter.uses_player(1, "first_spell"), 1)
	_tick_turn()
	assert_true(game.limiter.can_use_player(1, "first_spell"))
	assert_true(game.limiter.use_player(1, "once", 1, game.limiter.GAME))
	_tick_turn()
	assert_false(game.limiter.can_use_player(1, "once", 1, game.limiter.GAME))


func test_refund_and_reset():
	var card := await put_creature(1, "Righteous Guard")
	game.limiter.use(card, "x", 2)
	game.limiter.use(card, "x", 2)
	game.limiter.refund(card, "x")
	assert_eq(game.limiter.uses(card, "x"), 1)
	game.limiter.use(card, "y")
	game.limiter.reset(card, "x")
	assert_eq(game.limiter.uses(card, "x"), 0)
	assert_eq(game.limiter.uses(card, "y"), 1, "other keys stay")
	game.limiter.reset(card)
	assert_eq(game.limiter.uses(card, "y"), 0)
	game.limiter.use_player(1, "p")
	game.limiter.refund_player(1, "p")
	assert_eq(game.limiter.uses_player(1, "p"), 0)


func test_the_counts_are_forgotten_when_the_card_leaves_the_table():
	var card := await put_creature(1, "Righteous Guard")
	game.limiter.use(card, "x")
	game.limiter.use(card, "wish", 1, game.limiter.GAME)
	card.move_to(FateZones.container("hand", 1), -1, null, ["Scripted"])
	await wait_seconds(0.3)
	assert_eq(game.limiter.uses(card, "x"), 0)
	assert_eq(game.limiter.uses(card, "wish", game.limiter.GAME), 0, "a fresh card, even for once per game")


func test_moving_inside_the_table_keeps_the_counts():
	go_to_main()
	var card := await put_creature(1, "Rustmarket Tinkerer")
	game.limiter.use(card, "x")
	assert_true(game.keywords.get_keyword("Occupy").occupy(card, true))
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(card), "occupied")
	assert_false(game.limiter.can_use(card, "x"), "occupying is not leaving the table")


func test_loading_a_board_state_forgets_everything():
	var card := await put_creature(1, "Righteous Guard")
	game.limiter.use(card, "wish", 1, game.limiter.GAME)
	game.limiter.use_player(1, "p", 1, game.limiter.GAME)
	game.board_state_loaded.emit("x")
	assert_true(game.limiter.can_use(card, "wish", 1, game.limiter.GAME))
	assert_true(game.limiter.can_use_player(1, "p", 1, game.limiter.GAME))


# --- the costs ---------------------------------------------------------------------------------------------

func test_the_once_per_turn_cost():
	var card := await put_creature(1, "Righteous Guard")
	var cost: Dictionary = game.costs.once_per_turn("ping")
	assert_eq(game.costs.problem(card, [cost]), "")
	assert_true(await game.costs.pay(card, [cost]))
	assert_eq(game.costs.problem(card, [cost]), "Already used this turn")
	assert_false(await game.costs.pay(card, [cost]), "cannot be paid twice")
	_tick_turn()
	assert_eq(game.costs.problem(card, [cost]), "")


func test_the_once_per_turn_cost_with_x_uses_and_player_scope():
	var a := await put_creature(1, "Righteous Guard")
	var b := await put_creature(1, "Righteous Guard")
	var twice: Dictionary = game.costs.once_per_turn("ping", 2)
	assert_true(await game.costs.pay(a, [twice]))
	assert_true(await game.costs.pay(a, [twice]))
	assert_ne(game.costs.problem(a, [twice]), "")
	assert_eq(game.costs.problem(b, [twice]), "", "b has its own count")
	var shared: Dictionary = game.costs.once_per_turn("spell", 1, "player")
	assert_true(await game.costs.pay(a, [shared]))
	assert_ne(game.costs.problem(b, [shared]), "", "b shares the player's count")


func test_the_once_per_game_cost():
	var card := await put_creature(1, "Righteous Guard")
	var cost: Dictionary = game.costs.once_per_game("wish")
	assert_true(await game.costs.pay(card, [cost]))
	_tick_turn()
	assert_eq(game.costs.problem(card, [cost]), "Already used this game")


func test_the_limiter_inside_an_activated_ability():
	await empty_hand(1)
	go_to_main()
	var ran := []
	var script_class := GDScript.new()
	script_class.source_code = "extends \"res://src/custom/fate/cards/FateCardEffect.gd\"\nvar ran: Array\nfunc actions(card):\n\treturn [make_action(card, 'ping', 'Ping', 'tip', [game.costs.once_per_turn('ping')], func(c): ran.append(c.canonical_name))]\n"
	script_class.reload()
	var effect = script_class.new()
	effect.card_name = "Streetside Recruiter"
	effect.ran = ran
	game.card_effects.register(effect)
	var card := await put_creature(1, "Streetside Recruiter")
	assert_true(await game.actions.run(card, "ping"))
	assert_false(await game.actions.run(card, "ping"), "the second use is refused")
	assert_eq(ran.size(), 1)
