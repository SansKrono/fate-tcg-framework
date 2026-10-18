extends "res://tests/FateCommon.gd"
# Charge (docs/FATE_RULES_SPEC.md, Section 4): a creature cannot attack the turn it enters play
# unless it has Charge (innate or granted). "Entered" = card.entered_turn == game.turn_number.
# Player 1 is the active player on turn 1.


# Marks a test creature as played this turn, as the turn system does when a creature is played
func _just_entered(card: Card) -> void:
	card.entered_turn = game.turn_number


func test_a_creature_that_entered_this_turn_cannot_attack():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	start_combat()
	assert_false(game.keywords.can_attack(card))
	assert_false(game.combat.declare_attack(card, 2))
	assert_eq(game.combat.last_error, "It cannot attack")
	assert_does_not_have(game.combat.eligible_attackers(), card)


func test_it_can_attack_on_its_owners_next_turn():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	game.end_turn()
	game.end_turn()
	assert_eq(game.active_id, 1)
	assert_eq(game.turn_number, 3)
	start_combat()
	assert_true(game.keywords.can_attack(card))
	assert_true(game.combat.declare_attack(card, 2))


func test_other_creatures_of_the_same_player_are_not_restricted():
	var old := await put_creature(1, 2, 2)
	var fresh := await put_creature(1, 2, 2)
	_just_entered(fresh)
	start_combat()
	assert_eq(game.combat.eligible_attackers(), [old])
	assert_true(game.combat.declare_attack(old, 2))
	assert_false(game.combat.declare_attack(fresh, 2))


func test_innate_charge_attacks_the_turn_it_enters():
	var card := await put_creature(1, 2, 2, {"Charge": 1})
	_just_entered(card)
	start_combat()
	assert_true(game.keywords.can_attack(card))
	assert_true(game.combat.declare_attack(card, 2))
	game.combat.confirm_attackers()
	game.combat.confirm_blocks()
	assert_eq(game.player(2).life, LIFE - 2, "The charging creature hit for its Strike 2")


func test_granted_charge_works_and_expires_at_the_end_of_the_turn():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	game.stats.grant_keyword(card, "Charge", 1, "end_of_turn")
	start_combat()
	assert_true(game.combat.declare_attack(card, 2), "Charge until end of turn")
	game.combat.confirm_attackers()
	game.combat.confirm_blocks()
	assert_eq(game.phase, FateGame.Phase.END)
	# "Until end of turn" effects expire on entering the END phase (spec Section 1, step 9)
	assert_false(game.keywords.has(card, "Charge"), "The grant expired")
	assert_false(game.keywords.can_attack(card), "Back to summoning sick for the rest of the turn")


func test_expired_grant_restricts_a_creature_again():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	var grant := game.stats.grant_keyword(card, "Charge", 1, "end_of_turn")
	assert_true(game.keywords.can_attack(card))
	game.stats.remove_grant(card, grant)
	assert_false(game.keywords.can_attack(card), "Without the grant it is summoning sick again")


func test_charge_granted_by_a_permanent_grant_keeps_working():
	var card := await put_creature(1, 2, 2)
	_just_entered(card)
	game.stats.grant_keyword(card, "Charge", 1, "permanent")
	assert_true(game.keywords.can_attack(card))


func test_charge_only_lifts_the_entry_rule_not_the_core_rules():
	var tilted := await put_creature(1, 2, 2, {"Charge": 1}, true)
	var occupied := await put_creature(1, 2, 2, {"Charge": 1}, false, "occupied")
	_just_entered(tilted)
	_just_entered(occupied)
	start_combat()
	assert_true(game.keywords.can_attack(tilted), "The keyword hook allows it...")
	assert_false(game.combat.declare_attack(tilted, 2), "...but a guarding creature still cannot attack")
	assert_false(game.combat.declare_attack(occupied, 2), "nor an occupied one")


func test_the_opponents_creature_is_restricted_on_its_own_turn_only():
	# Player 2's creature entered on turn 1 (player 1's turn, as a test setup); on turn 2 it is
	# the active player's creature and entered_turn != turn_number
	var card := await put_creature(2, 2, 2)
	_just_entered(card)
	game.end_turn()
	assert_eq(game.turn_number, 2)
	start_combat()
	assert_true(game.combat.declare_attack(card, 1))


func test_entered_turn_zero_is_not_restricted():
	var card := await put_creature(1, 2, 2)
	assert_eq(card.entered_turn, 0, "Placed by a helper, not played")
	start_combat()
	assert_true(game.keywords.can_attack(card))
	assert_true(game.combat.declare_attack(card, 2))


func test_a_creature_played_from_hand_cannot_attack_that_turn():
	await empty_hand(1)
	await fill_mana(1)
	var card := await put_in_hand(1, "Streetside Recruiter")
	go_to_main()
	card.move_to(board)
	await wait_seconds(0.6)
	assert_eq(card.get_parent(), board, "Played")
	assert_eq(card.entered_turn, game.turn_number)
	game.advance_phase()
	assert_eq(game.phase, FateGame.Phase.COMBAT_DECLARE)
	assert_false(game.combat.declare_attack(card, 2))
	assert_eq(game.combat.last_error, "It cannot attack")


func test_a_creature_played_from_hand_attacks_on_the_next_turn():
	await empty_hand(1)
	await fill_mana(1)
	var card := await put_in_hand(1, "Streetside Recruiter")
	go_to_main()
	card.move_to(board)
	await wait_seconds(0.6)
	game.end_turn()
	game.end_turn()
	assert_eq(game.active_id, 1)
	start_combat()
	assert_true(game.combat.declare_attack(card, 2))


func test_a_creature_played_from_hand_with_granted_charge_attacks_at_once():
	await empty_hand(1)
	await fill_mana(1)
	var card := await put_in_hand(1, "Streetside Recruiter")
	go_to_main()
	card.move_to(board)
	await wait_seconds(0.6)
	game.stats.grant_keyword(card, "Charge", 1, "end_of_turn")
	game.advance_phase()
	assert_true(game.combat.declare_attack(card, 2))
