extends "res://tests/FateCommon.gd"
# Indomitable (src/custom/fate/keywords/KwIndomitable.gd). Rules: docs/FATE_RULES_SPEC.md,
# Section 4: the creature cannot die from combat damage, its used stat is held at 1 instead of
# reaching 0. Player 1 attacks, player 2 defends; a tilted creature guards. Combat goes through
# the real FateCombat (declare, block, resolve), not through the keyword hooks directly.

const IND := {"Indomitable": 1}

var combat: FateCombat


func before_each():
	await super.before_each()
	combat = game.combat


func _discard(pid: int) -> Node:
	return FateZones.container("discard", pid)


func _label_text(card: Card, stat: String) -> String:
	return card.card_front.card_labels[stat].text


# Declares and confirms attacks, then confirms the (given) blocks. Ends in the END phase.
func _fight(declares: Array, blocks := []) -> Array:
	var made := []
	for d in declares:
		assert_true(combat.declare_attack(d[0], d[1]), "Test setup: attack %s allowed" % str(d))
		made.append(combat.attack_of(d[0]))
	combat.confirm_attackers()
	for b in blocks:
		assert_true(combat.declare_block(b[0], made[b[1]]), "Test setup: block allowed: " + combat.last_error)
	combat.confirm_blocks()
	return made


func _stat(card: Card, stat: String) -> int:
	return game.stats.current(card, stat)


# --- as the attacker ----------------------------------------------------------------------------

func test_an_indomitable_attacker_blocked_by_a_bigger_guard_survives_with_strike_1():
	# The spec example: Strike 3 against Guard 5 would leave 0
	var attacker := await put_creature(1, 3, 2, IND)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	var made := _fight([[attacker, 2]], [[blocker, 0]])
	assert_true(FateZones.is_creature_in_play(attacker), "Does not die")
	assert_eq(_stat(attacker, "Strike"), 1, "Held at 1, not 0")
	assert_eq(_stat(attacker, "Guard"), 2, "The other stat is untouched")
	assert_eq(_stat(blocker, "Guard"), 2, "Combat damage dealt BY it is unchanged: 5 - 3")
	assert_eq(made[0].result.damage_to_target, 3)
	assert_eq(made[0].result.damage_to_attacker, 2, "Only 2 of the 3 were really lost")
	assert_eq(made[0].result.destroyed, [])


func test_without_indomitable_the_same_fight_kills_the_attacker():
	# The control of the test above
	var attacker := await put_creature(1, 3, 2)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_eq(attacker.get_parent(), _discard(1))


func test_an_indomitable_attacker_attacking_a_creature_in_strike_position_survives():
	var attacker := await put_creature(1, 2, 2, IND)
	var target := await put_creature(2, 5, 1)
	start_combat()
	_fight([[attacker, target]])
	assert_true(FateZones.is_creature_in_play(attacker))
	assert_eq(_stat(attacker, "Strike"), 1)
	assert_eq(_stat(target, "Strike"), 3, "5 - 2")


func test_an_indomitable_attacker_attacking_a_creature_in_guard_survives():
	var attacker := await put_creature(1, 2, 2, IND)
	var target := await put_creature(2, 1, 6, {}, true)
	start_combat()
	_fight([[attacker, target]])
	assert_true(FateZones.is_creature_in_play(attacker))
	assert_eq(_stat(attacker, "Strike"), 1)
	assert_eq(_stat(target, "Guard"), 4)


func test_an_indomitable_attacker_that_wins_loses_normally():
	# Strike 4 against Guard 2: the attacker is left with 2 (above 1, so the hold does not matter)
	var attacker := await put_creature(1, 4, 1, IND)
	var target := await put_creature(2, 1, 2, {}, true)
	start_combat()
	_fight([[attacker, target]])
	assert_eq(_stat(attacker, "Strike"), 2)
	assert_eq(target.get_parent(), _discard(2), "Its damage was not reduced: the target dies")


# --- as the defender ----------------------------------------------------------------------------

func test_an_indomitable_blocker_hit_by_a_bigger_strike_survives_with_guard_1():
	# The spec example: Guard 2 hit by Strike 4
	var attacker := await put_creature(1, 4, 1)
	var blocker := await put_creature(2, 1, 2, IND, true)
	start_combat()
	var made := _fight([[attacker, 2]], [[blocker, 0]])
	assert_true(FateZones.is_creature_in_play(blocker), "Does not die")
	assert_eq(_stat(blocker, "Guard"), 1)
	assert_eq(_stat(blocker, "Strike"), 1, "The other stat is untouched")
	assert_eq(_stat(attacker, "Strike"), 2, "The attacker still loses the blocker's whole Guard: 4 - 2")
	assert_eq(made[0].result.damage_to_target, 1)
	assert_eq(made[0].result.destroyed, [])


func test_the_held_stat_label_shows_1():
	var attacker := await put_creature(1, 4, 1)
	var blocker := await put_creature(2, 1, 2, IND, true)
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_eq(blocker.properties["Guard"], 1, "The card holds the current value")
	assert_eq(_label_text(blocker, "Guard"), "1", "... and the label shows it")
	assert_eq(_label_text(attacker, "Strike"), "2")


func test_an_attacked_indomitable_creature_in_guard_position_survives():
	var attacker := await put_creature(1, 5, 1)
	var target := await put_creature(2, 1, 3, IND, true)
	start_combat()
	_fight([[attacker, target]])
	assert_true(FateZones.is_creature_in_play(target))
	assert_eq(_stat(target, "Guard"), 1)
	assert_eq(_stat(attacker, "Strike"), 2, "5 - 3")


func test_an_attacked_indomitable_creature_in_strike_position_survives():
	var attacker := await put_creature(1, 5, 1)
	var target := await put_creature(2, 3, 1, IND)
	start_combat()
	_fight([[attacker, target]])
	assert_true(FateZones.is_creature_in_play(target))
	assert_eq(_stat(target, "Strike"), 1)
	assert_eq(_stat(target, "Guard"), 1)


func test_an_occupied_indomitable_blocker_survives_too():
	var attacker := await put_creature(1, 6, 1)
	var blocker := await put_creature(2, 1, 2, IND, false, "occupied")
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_true(FateZones.is_creature_in_play(blocker))
	assert_eq(_stat(blocker, "Guard"), 1)


func test_a_blocker_with_guard_0_is_not_killed_by_combat():
	# The used stat is already 0, so there is no damage to cap: the veto on destruction by combat
	# keeps it alive. Without the keyword the core destroys it (control below).
	var attacker := await put_creature(1, 2, 1)
	var blocker := await put_creature(2, 3, 0, IND, true)
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_true(FateZones.is_creature_in_play(blocker))
	assert_eq(_stat(blocker, "Guard"), 0, "Cannot be raised to 1 by combat, it just does not die")
	assert_eq(_stat(attacker, "Strike"), 2, "A Guard 0 blocker absorbs nothing")


func test_a_plain_blocker_with_guard_0_dies_in_the_same_fight():
	var attacker := await put_creature(1, 2, 1)
	var plain := await put_creature(2, 3, 0, {}, true)
	start_combat()
	_fight([[attacker, 2]], [[plain, 0]])
	assert_eq(plain.get_parent(), _discard(2), "Control for the test above")


# --- both sides, players, several blockers ------------------------------------------------------------

func test_two_indomitable_creatures_fighting_both_survive():
	var attacker := await put_creature(1, 3, 3, IND)
	var target := await put_creature(2, 1, 3, IND, true)
	start_combat()
	var made := _fight([[attacker, target]])
	assert_true(FateZones.is_creature_in_play(attacker))
	assert_true(FateZones.is_creature_in_play(target))
	assert_eq(_stat(attacker, "Strike"), 1)
	assert_eq(_stat(target, "Guard"), 1)
	assert_eq(made[0].result.destroyed, [])


func test_two_indomitable_creatures_with_a_blocker_between_them_survive():
	var attacker := await put_creature(1, 2, 2, IND)
	var blocker := await put_creature(2, 2, 2, IND, true)
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_eq(_stat(attacker, "Strike"), 1)
	assert_eq(_stat(blocker, "Guard"), 1)


func test_an_unblocked_attack_on_a_player_is_unchanged():
	var attacker := await put_creature(1, 3, 2, IND)
	start_combat()
	var made := _fight([[attacker, 2]])
	assert_eq(game.player(2).life, LIFE - 1, "1 life, whatever the Strike")
	assert_eq(made[0].result.life_lost, 1)
	assert_eq(_stat(attacker, "Strike"), 3, "The attacker takes no damage from a player")


func test_the_player_is_unaffected_by_the_keyword():
	# Indomitable is for creatures; damage to a player is not capped by anything on the table
	var guard := await put_creature(2, 1, 1, IND)
	assert_eq(game.effects.deal_damage(game.player(2), 5, guard, FateEffects.CAUSE_COMBAT), 5)
	assert_eq(game.player(2).life, LIFE - 5)
	assert_true(FateZones.is_creature_in_play(guard))


func test_an_indomitable_attacker_blocked_by_several_blockers_survives_with_strike_1():
	# Strike 3 against Guard 2 and Guard 4: the attacker would lose 2 and then 1 (everything)
	var attacker := await put_creature(1, 3, 2, IND)
	var b1 := await put_creature(2, 1, 2, {}, true)
	var b2 := await put_creature(2, 1, 4, {}, true)
	start_combat()
	combat.declare_attack(attacker, 2)
	combat.confirm_attackers()
	var attack := combat.attack_of(attacker)
	combat.declare_block(b1, attack)
	combat.declare_block(b2, attack)
	combat.confirm_blocks()
	assert_true(FateZones.is_creature_in_play(attacker))
	assert_eq(_stat(attacker, "Strike"), 1)
	assert_eq(b1.get_parent(), _discard(2), "The first blocker took 2 and died")
	assert_eq(_stat(b2, "Guard"), 3, "The second took the last point: its damage is not reduced")
	assert_eq(attack.result.damage_to_attacker, 2, "2 lost, the point that would kill is held")
	assert_eq(attack.result.damage_to_target, 3)


func test_an_indomitable_attacker_whose_strike_is_gone_to_the_first_blocker_survives():
	# The whole Strike goes to the first of two blockers, the second one takes nothing
	var attacker := await put_creature(1, 2, 2, IND)
	var b1 := await put_creature(2, 1, 3, {}, true)
	var b2 := await put_creature(2, 1, 3, {}, true)
	start_combat()
	combat.declare_attack(attacker, 2)
	combat.confirm_attackers()
	var attack := combat.attack_of(attacker)
	combat.declare_block(b1, attack)
	combat.declare_block(b2, attack)
	combat.confirm_blocks()
	assert_true(FateZones.is_creature_in_play(attacker))
	assert_eq(_stat(attacker, "Strike"), 1)
	assert_eq(_stat(b1, "Guard"), 1)
	assert_eq(_stat(b2, "Guard"), 3)


# --- outside combat ----------------------------------------------------------------------------------------

func test_it_still_dies_to_non_combat_destruction():
	var card := await put_creature(1, 3, 3, IND)
	assert_true(game.effects.destroy(card, null, FateEffects.CAUSE_EFFECT))
	assert_eq(card.get_parent(), _discard(1))


func test_destruction_with_the_combat_cause_is_prevented():
	var card := await put_creature(1, 3, 3, IND)
	assert_false(game.effects.destroy(card, null, FateEffects.CAUSE_COMBAT))
	assert_true(FateZones.is_creature_in_play(card))


func test_effect_damage_is_not_capped_and_does_not_kill_by_itself():
	# Non-combat damage can take the used stat to 0, like for any creature (it only destroys
	# through the both-stats-zero rule)
	var card := await put_creature(1, 3, 2, IND)
	var dealt := game.effects.deal_damage(card, 5, null, FateEffects.CAUSE_EFFECT)
	assert_eq(dealt, 3, "All of the Strike, not held at 1")
	assert_eq(_stat(card, "Strike"), 0)
	assert_true(FateZones.is_creature_in_play(card), "Guard 2 is left")


func test_effect_damage_to_both_stats_destroys_it_by_the_stats_rule():
	var card := await put_creature(1, 3, 2, IND)
	var causes := []
	game.creature_destroyed.connect(func(_c, cause): causes.append(cause))
	game.effects.deal_damage(card, 5, null, FateEffects.CAUSE_EFFECT, "Strike")
	assert_true(FateZones.is_creature_in_play(card))
	game.effects.deal_damage(card, 5, null, FateEffects.CAUSE_EFFECT, "Guard")
	assert_eq(card.get_parent(), _discard(1))
	assert_eq(causes, [FateEffects.CAUSE_STATS], "The both-zero rule is not Indomitable's business")


func test_a_debuff_taking_both_stats_to_zero_destroys_it():
	var card := await put_creature(1, 2, 2, IND)
	game.stats.add_modifier(card, "Strike", -5, "permanent")
	game.stats.add_modifier(card, "Guard", -5, "permanent")
	assert_eq(card.get_parent(), _discard(1))


# --- both-zero interplay --------------------------------------------------------------------------------

func test_combat_never_takes_the_last_non_zero_stat_to_zero():
	# Strike 2 and Guard 0 (debuffed): a combat hit on the Strike is held at 1, so "Strike and
	# Guard both 0" cannot be reached by combat
	var attacker := await put_creature(1, 5, 1)
	var target := await put_creature(2, 2, 2, IND)
	game.stats.add_modifier(target, "Guard", -2, "permanent")
	assert_eq(_stat(target, "Guard"), 0)
	start_combat()
	_fight([[attacker, target]])
	assert_true(FateZones.is_creature_in_play(target), "Not destroyed by combat or by the both-zero rule")
	assert_eq(_stat(target, "Strike"), 1)
	assert_eq(_stat(target, "Guard"), 0)


func test_after_combat_held_it_at_1_a_non_combat_effect_can_finish_it():
	var attacker := await put_creature(1, 5, 1)
	var target := await put_creature(2, 2, 2, IND)
	game.stats.add_modifier(target, "Guard", -2, "permanent")
	start_combat()
	_fight([[attacker, target]])
	assert_true(FateZones.is_creature_in_play(target))
	game.effects.deal_damage(target, 1, null, FateEffects.CAUSE_EFFECT, "Strike")
	assert_eq(target.get_parent(), _discard(2), "Strike 0 and Guard 0")


# --- granted Indomitable -------------------------------------------------------------------------------------

func test_granted_indomitable_works_and_expires_at_the_end_of_the_turn():
	var attacker := await put_creature(1, 3, 3)
	var blocker := await put_creature(2, 1, 5, {}, true)
	game.stats.grant_keyword(attacker, "Indomitable", 1, "end_of_turn")
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_true(FateZones.is_creature_in_play(attacker), "Survives while it has the keyword")
	assert_eq(_stat(attacker, "Strike"), 1)
	# The END phase (where the combat ended) is when "until end of turn" effects expire
	assert_false(game.keywords.has(attacker, "Indomitable"), "Until end of turn")
	game.end_turn()
	assert_false(game.keywords.has(attacker, "Indomitable"))
	# No longer protected: the same kind of combat damage destroys it
	assert_eq(game.effects.deal_damage(attacker, 1, blocker, FateEffects.CAUSE_COMBAT), 1)
	assert_eq(attacker.get_parent(), _discard(1))


func test_a_grant_on_a_defender_lasts_through_the_opponents_turn_only_until_it_ends():
	# Granted by the defender's own effect on the attacker's turn: gone when that turn ends
	var attacker := await put_creature(1, 5, 1)
	var blocker := await put_creature(2, 1, 2, {}, true)
	game.stats.grant_keyword(blocker, "Indomitable", 1, "end_of_turn")
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_true(FateZones.is_creature_in_play(blocker))
	assert_eq(_stat(blocker, "Guard"), 1)
	game.end_turn()
	assert_false(game.keywords.has(blocker, "Indomitable"))
	assert_true(FateZones.is_creature_in_play(blocker), "Expiry does not kill a creature at 1")


func test_a_permanent_grant_keeps_the_protection():
	var attacker := await put_creature(1, 5, 1)
	var blocker := await put_creature(2, 1, 2, {}, true)
	game.stats.grant_keyword(blocker, "Indomitable", 1, "permanent")
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_true(FateZones.is_creature_in_play(blocker))
	game.end_turn()
	assert_true(game.keywords.has(blocker, "Indomitable"))


func test_a_real_card_has_the_keyword_innately():
	var teshra := await put_creature(1, "Teshra, Primal Mother")
	assert_true(game.keywords.has(teshra, "Indomitable"), "The real card has it innately")
