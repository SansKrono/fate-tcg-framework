extends "res://tests/FateCommon.gd"
# Productive (docs/FATE_RULES_SPEC.md, Section 4): a creature cannot occupy the turn it enters
# play unless it has Productive (innate or granted). The core never asks by itself: the Occupy
# action asks game.keywords.can_occupy(card).


func _just_entered(card: Card) -> void:
	card.entered_turn = game.turn_number


func test_a_creature_that_entered_this_turn_cannot_occupy():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	assert_false(game.keywords.can_occupy(card))


func test_it_can_occupy_on_a_later_turn():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	game.end_turn()
	game.end_turn()
	assert_eq(game.turn_number, 3)
	assert_true(game.keywords.can_occupy(card))


func test_innate_productive_may_occupy_the_turn_it_enters():
	var card := await put_creature(1, 2, 2, {"Productive": 1})
	_just_entered(card)
	assert_true(game.keywords.can_occupy(card))


func test_a_real_productive_card_is_not_restricted():
	var brogir := await put_creature(1, "Brogir, Master Artificer")
	_just_entered(brogir)
	assert_true(game.keywords.has(brogir, "Productive"), "Brogir has Productive innately")
	assert_true(game.keywords.can_occupy(brogir))


func test_granted_productive_works_and_expires():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	var grant := game.stats.grant_keyword(card, "Productive", 1, "end_of_turn")
	assert_true(game.keywords.can_occupy(card))
	game.stats.remove_grant(card, grant)
	assert_false(game.keywords.can_occupy(card))


func test_granted_productive_ends_with_the_turn():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	game.stats.grant_keyword(card, "Productive", 1, "end_of_turn")
	game.end_turn()
	assert_false(game.keywords.has(card, "Productive"))
	assert_eq(game.turn_number, 2)
	assert_true(game.keywords.can_occupy(card), "Turn 2: it no longer counts as new")


func test_entered_turn_zero_is_not_restricted():
	var card := await put_creature(1, 2, 2)
	assert_eq(card.entered_turn, 0)
	assert_true(game.keywords.can_occupy(card))


func test_charge_does_not_give_productive_and_vice_versa():
	var charger := await put_creature(1, 2, 2, {"Charge": 1})
	var worker := await put_creature(1, 2, 2, {"Productive": 1})
	_just_entered(charger)
	_just_entered(worker)
	assert_false(game.keywords.can_occupy(charger), "Charge only lifts the attack rule")
	assert_true(game.keywords.can_occupy(worker))
	start_combat()
	assert_false(game.keywords.can_attack(worker), "Productive only lifts the occupy rule")
	assert_true(game.keywords.can_attack(charger))


func test_occupy_rule_does_not_block_attacking_and_the_reverse():
	# A fresh creature: no attack, no occupy. Neither restriction touches the other hook.
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	assert_false(game.keywords.can_occupy(card))
	assert_false(game.keywords.can_attack(card))
	card.entered_turn = 0
	assert_true(game.keywords.can_occupy(card))
	assert_true(game.keywords.can_attack(card))


func test_a_creature_played_from_hand_cannot_occupy_that_turn():
	await empty_hand(1)
	await fill_mana(1)
	var card := await put_in_hand(1, "Streetside Recruiter")
	go_to_main()
	card.move_to(board)
	await wait_seconds(0.6)
	assert_eq(card.entered_turn, game.turn_number)
	assert_false(game.keywords.can_occupy(card))
	game.end_turn()
	game.end_turn()
	assert_true(game.keywords.can_occupy(card), "Allowed on its owner's next turn")


func test_a_productive_creature_played_from_hand_may_occupy_at_once():
	await empty_hand(1)
	await fill_mana(1, 4)
	var card := await put_in_hand(1, "Brogir, Master Artificer")
	go_to_main()
	card.move_to(board)
	await wait_seconds(0.6)
	assert_eq(card.get_parent(), board, "Played (enough mana)")
	assert_eq(card.entered_turn, game.turn_number)
	assert_true(game.keywords.can_occupy(card))


func test_the_occupy_action_of_another_keyword_sees_the_rule():
	# Occupy (written by another agent) asks game.keywords.can_occupy(); here a stand-in keyword
	# does the same, so the integration with the registry is covered without depending on it.
	var TestKeyword := preload("res://tests/FateTestKeyword.gd")
	var kw = TestKeyword.make("Probe")
	game.keywords.register(kw)
	var card := await put_creature(1, 2, 2, {"Probe": 1})
	_just_entered(card)
	assert_false(game.keywords.can_occupy(card), "Probe allows, Productive's rule still denies")
	assert_true(kw.calls.any(func(c): return c[0] == "can_occupy"), "The registry asked the probe too")
