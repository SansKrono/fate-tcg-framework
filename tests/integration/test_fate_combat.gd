extends "res://tests/FateCommon.gd"
# Tests of the combat manager (FateCombat): declare, intercept, resolve, the damage algorithm and
# the turn integration. Rules: docs/FATE_RULES_SPEC.md, Section 3. Player 1 attacks, player 2
# defends. Creatures come from put_creature(pid, strike, guard); a tilted creature guards.
# The combat is driven through the public API (the UI calls the same methods); see
# test_fate_combat_ui.gd for the clicks.

const Phase := FateGame.Phase
const TestKeyword := preload("res://tests/FateTestKeyword.gd")

var combat: FateCombat


func before_each():
	await super.before_each()
	combat = game.combat


func _discard(pid: int) -> Node:
	return FateZones.container("discard", pid)


func _life(pid: int) -> int:
	return game.player(pid).life


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


# --- attacking a player --------------------------------------------------------------------------------

func test_an_unblocked_attack_on_a_player_lowers_their_life_by_the_current_strike():
	var attacker := await put_creature(1, 3, 1)
	game.stats.add_modifier(attacker, "Strike", 1, "end_of_turn")
	start_combat()
	var made := _fight([[attacker, 2]])
	assert_eq(_life(2), LIFE - 4, "Strike 3 + 1")
	assert_eq(made[0].result.kind, "player")
	assert_eq(made[0].result.life_lost, 4)
	assert_true(made[0].resolved)
	assert_eq(game.stats.damage_on(attacker, "Strike"), 0, "The attacker takes no damage from a player")
	assert_eq(game.stats.current(attacker, "Strike"), 3, "(the +1 ended with the turn's END phase)")
	assert_eq(game.phase, Phase.END, "Resolved: on to the end phase")


func test_attacking_with_the_player_object_and_the_player_id_both_work():
	var a := await put_creature(1, 1, 1)
	var b := await put_creature(1, 2, 1)
	start_combat()
	assert_true(combat.declare_attack(a, game.player(2)))
	assert_true(combat.declare_attack(b, 2))
	assert_false(combat.declare_attack(await put_creature(1, 1, 1), 1), "Not the opposing player")


# --- attacking creatures ----------------------------------------------------------------------------------

func test_attacking_an_upright_creature_both_use_strike():
	var attacker := await put_creature(1, 3, 3)
	var target := await put_creature(2, 2, 5)
	start_combat()
	_fight([[attacker, target]])
	assert_eq(game.stats.current(attacker, "Strike"), 1, "3 - 2")
	assert_eq(target.get_parent(), _discard(2), "Strike 2 - 3 = 0: destroyed")
	assert_eq(game.stats.current(attacker, "Guard"), 3, "Guard untouched")
	assert_eq(_life(2), LIFE)


func test_attacking_a_creature_in_guard_uses_its_guard():
	# Strike 3 against Guard 2: the attacker is left with 1, the defender is destroyed (the spec example)
	var attacker := await put_creature(1, 3, 1)
	var target := await put_creature(2, 4, 2, {}, true)
	start_combat()
	var made := _fight([[attacker, target]])
	assert_eq(game.stats.current(attacker, "Strike"), 1)
	assert_eq(target.get_parent(), _discard(2))
	assert_eq(made[0].result.damage_to_target, 2)
	assert_eq(made[0].result.damage_to_attacker, 2)
	assert_eq(made[0].result.destroyed, [target])


func test_the_attacker_dies_against_a_bigger_guard_and_the_defender_survives_damaged():
	var attacker := await put_creature(1, 2, 2)
	var target := await put_creature(2, 1, 3, {}, true)
	start_combat()
	_fight([[attacker, target]])
	assert_eq(attacker.get_parent(), _discard(1))
	assert_true(FateZones.is_creature_in_play(target))
	assert_eq(game.stats.current(target, "Guard"), 1, "3 - 2")
	assert_eq(game.stats.current(target, "Strike"), 1, "The other stat is untouched")


func test_equal_stats_destroy_both_at_the_same_time():
	var attacker := await put_creature(1, 3, 3)
	var target := await put_creature(2, 1, 3, {}, true)
	start_combat()
	var made := _fight([[attacker, target]])
	assert_eq(attacker.get_parent(), _discard(1))
	assert_eq(target.get_parent(), _discard(2))
	assert_eq(made[0].result.destroyed.size(), 2)


func test_damage_stays_until_the_owners_next_maintenance():
	var attacker := await put_creature(1, 3, 3)
	var target := await put_creature(2, 1, 5, {}, true)
	start_combat()
	_fight([[attacker, target]])
	assert_eq(game.stats.current(target, "Guard"), 2)
	assert_eq(attacker.get_parent(), _discard(1))
	var survivor := await put_creature(1, 4, 3)
	var other := await put_creature(2, 2, 4, {}, true)
	# a second combat is not possible this turn; damage them directly and watch the maintenance
	game.effects.deal_damage(survivor, 1)
	game.effects.deal_damage(other, 1)
	game.advance_phase()
	assert_eq(game.active_id, 2)
	assert_eq(game.stats.current(other, "Guard"), 4, "Player 2's maintenance cleared their damage")
	assert_eq(game.stats.current(target, "Guard"), 5)
	assert_eq(game.stats.current(survivor, "Strike"), 3, "Player 1's damage waits for player 1's maintenance")


# --- eligibility --------------------------------------------------------------------------------------------------

func test_only_upright_creatures_in_the_creature_zone_can_attack():
	var ready := await put_creature(1, 2, 2)
	var tilted := await put_creature(1, 2, 2, {}, true)
	var occupied := await put_creature(1, 2, 2, {}, false, "occupied")
	var enemy := await put_creature(2, 2, 2)
	start_combat()
	assert_eq(combat.eligible_attackers(), [ready])
	assert_false(combat.declare_attack(tilted, 2))
	assert_string_contains(combat.last_error, "strike position")
	assert_false(combat.declare_attack(occupied, 2))
	assert_string_contains(combat.last_error, "occupied")
	assert_false(combat.declare_attack(enemy, 1), "Not the active player's creature")
	assert_true(combat.declare_attack(ready, 2))
	assert_false(combat.declare_attack(ready, 2), "At most once per combat phase")
	assert_string_contains(combat.last_error, "already")
	assert_eq(combat.eligible_attackers(), [])


func test_targets_must_be_opposing_creatures_in_play_or_the_opposing_player():
	var attacker := await put_creature(1, 2, 2)
	var mine := await put_creature(1, 2, 2)
	var occupied := await put_creature(2, 2, 2, {}, false, "occupied")
	var hand_card := await put_in_hand(2, "Skulking Goblin")
	start_combat()
	assert_false(combat.declare_attack(attacker, mine), "Your own creature")
	assert_false(combat.declare_attack(attacker, hand_card), "Not in play")
	assert_false(combat.declare_attack(attacker, 1))
	assert_true(combat.declare_attack(attacker, occupied), "Occupied creatures can be targeted")


func test_nothing_can_be_declared_outside_the_declare_step():
	var attacker := await put_creature(1, 2, 2)
	game.draw_extra_card()
	assert_false(combat.declare_attack(attacker, 2), "Main phase")
	game.advance_phase()
	assert_true(combat.declare_attack(attacker, 2))
	combat.confirm_attackers()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	assert_false(combat.declare_attack(await put_creature(1, 2, 2), 2), "Intercept step")
	assert_false(combat.cancel_attack(attacker), "The attackers are locked in")


func test_an_attack_can_be_cancelled_in_the_declare_step():
	var attacker := await put_creature(1, 2, 2)
	start_combat()
	var cancelled := []
	combat.attack_cancelled.connect(func(a): cancelled.append(a))
	combat.declare_attack(attacker, 2)
	var attack := combat.attack_of(attacker)
	assert_true(combat.cancel_attack(attacker))
	assert_eq(cancelled, [attack])
	assert_null(combat.attack_of(attacker))
	assert_false(combat.cancel_attack(attacker))
	assert_true(combat.declare_attack(attacker, 2), "It can attack again")


func test_the_attacks_are_kept_in_declaration_order():
	var a := await put_creature(1, 1, 1)
	var b := await put_creature(1, 2, 1)
	var c := await put_creature(1, 3, 1)
	start_combat()
	combat.declare_attack(b, 2)
	combat.declare_attack(c, 2)
	combat.declare_attack(a, 2)
	combat.cancel_attack(c)
	assert_eq(combat.attacks.map(func(x): return x.attacker), [b, a])
	assert_eq(combat.attacks.map(func(x): return x.order), [0, 1], "Renumbered")


# --- blocking ----------------------------------------------------------------------------------------------------------

func test_a_guarding_creature_blocks_and_uses_its_guard():
	var attacker := await put_creature(1, 3, 3)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	var made := _fight([[attacker, 2]], [[blocker, 0]])
	assert_eq(_life(2), LIFE, "The player is not hit")
	assert_eq(game.stats.current(blocker, "Guard"), 2, "5 - 3")
	assert_eq(attacker.get_parent(), _discard(1), "Strike 3 - Guard 5 = 0: the attacker is destroyed")
	assert_eq(made[0].result.kind, "blocked")
	assert_true(made[0].was_blocked)


func test_an_occupied_creature_can_block():
	var attacker := await put_creature(1, 2, 2)
	var blocker := await put_creature(2, 1, 4, {}, false, "occupied")
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_eq(_life(2), LIFE)
	assert_eq(game.stats.current(blocker, "Guard"), 2)
	assert_eq(attacker.get_parent(), _discard(1))


func test_a_blocker_may_block_an_attack_on_another_creature():
	var attacker := await put_creature(1, 2, 2)
	var target := await put_creature(2, 3, 3)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	_fight([[attacker, target]], [[blocker, 0]])
	assert_eq(game.stats.current(target, "Strike"), 3, "The target was spared")
	assert_eq(game.stats.current(blocker, "Guard"), 3)


func test_blocker_rules():
	var a1 := await put_creature(1, 2, 2)
	var a2 := await put_creature(1, 2, 2)
	var upright := await put_creature(2, 1, 4)
	var guard := await put_creature(2, 1, 4, {}, true)
	start_combat()
	combat.declare_attack(a1, 2)
	combat.declare_attack(a2, 2)
	var one: FateAttack = combat.attack_of(a1)
	var two: FateAttack = combat.attack_of(a2)
	assert_false(combat.declare_block(guard, one), "Not in the intercept step yet")
	combat.confirm_attackers()
	assert_false(combat.declare_block(upright, one), "Only guarding or occupied creatures intercept")
	assert_false(combat.declare_block(a2, one), "Not the defending player's creature")
	assert_eq(combat.eligible_blockers(), [guard])
	assert_true(combat.declare_block(guard, one))
	assert_false(combat.declare_block(guard, one), "Already blocking it")
	assert_false(combat.declare_block(guard, two), "One blocker blocks one attack")
	assert_true(combat.cancel_block(guard))
	assert_false(one.was_blocked)
	assert_true(combat.declare_block(guard, two), "Free again")


func test_several_blockers_take_the_attackers_strike_in_order():
	# Strike 5 on Guard 2 then Guard 4: 2 absorbed by the first (destroyed), 3 by the second (left 1).
	# The attacker loses 2 + 4 = 6, more than it has: destroyed
	var attacker := await put_creature(1, 5, 5)
	var first := await put_creature(2, 1, 2, {}, true)
	var second := await put_creature(2, 1, 4, {}, true)
	start_combat()
	var made := _fight([[attacker, 2]], [[first, 0], [second, 0]])
	assert_eq(first.get_parent(), _discard(2))
	assert_eq(game.stats.current(second, "Guard"), 1)
	assert_eq(attacker.get_parent(), _discard(1))
	assert_eq(made[0].result.damage_to_target, 5)
	assert_eq(made[0].result.damage_to_attacker, 5, "At most its whole Strike")


func test_the_attacker_orders_its_blockers():
	var attacker := await put_creature(1, 3, 5)
	var small := await put_creature(2, 1, 2, {}, true)
	var big := await put_creature(2, 1, 3, {}, true)
	start_combat()
	combat.declare_attack(attacker, 2)
	var attack: FateAttack = combat.attack_of(attacker)
	combat.confirm_attackers()
	combat.declare_block(small, attack)
	combat.declare_block(big, attack)
	assert_eq(attack.blockers, [small, big], "Declaration order by default")
	assert_false(combat.order_blockers(attack, [big]), "Must name every blocker")
	assert_false(combat.order_blockers(attack, [big, attacker]))
	assert_true(combat.order_blockers(attack, [big, small]))
	combat.confirm_blocks()
	assert_eq(big.get_parent(), _discard(2), "The big one took all 3")
	assert_eq(game.stats.current(small, "Guard"), 2, "The small one took nothing")
	assert_eq(attacker.get_parent(), _discard(1), "It lost its whole Strike (3 + 2 is more)")


func test_several_blockers_a_strong_attacker_survives_with_the_difference():
	var attacker := await put_creature(1, 7, 1)
	var first := await put_creature(2, 1, 1, {}, true)
	var second := await put_creature(2, 1, 2, {}, true)
	start_combat()
	_fight([[attacker, 2]], [[first, 0], [second, 0]])
	assert_eq(first.get_parent(), _discard(2))
	assert_eq(second.get_parent(), _discard(2))
	assert_eq(game.stats.current(attacker, "Strike"), 4, "7 - (1 + 2)")


# --- resolution order and special cases ----------------------------------------------------------------------------

func test_attacks_resolve_one_at_a_time_in_declaration_order():
	var a := await put_creature(1, 1, 1)
	var b := await put_creature(1, 2, 1)
	var c := await put_creature(1, 3, 1)
	start_combat()
	var order := []
	combat.attack_resolved.connect(func(attack, result): order.append([attack.attacker, _life(2)]))
	_fight([[c, 2], [a, 2], [b, 2]])
	assert_eq(order, [[c, LIFE - 3], [a, LIFE - 4], [b, LIFE - 6]], "Declaration order, one at a time")
	assert_eq(_life(2), LIFE - 6)


func test_an_earlier_attack_can_change_a_later_one():
	var killer := await put_creature(1, 5, 1)
	var second := await put_creature(1, 4, 1)
	var victim := await put_creature(2, 1, 1)
	start_combat()
	var made := _fight([[killer, victim], [second, victim]])
	assert_eq(victim.get_parent(), _discard(2))
	assert_eq(made[1].result.kind, "target_gone", "The target was removed before this attack resolved")
	assert_eq(game.stats.current(second, "Strike"), 4, "No damage dealt or taken")
	assert_eq(_life(2), LIFE)


func test_a_blocked_attack_still_fights_the_blockers_when_its_target_is_gone():
	var killer := await put_creature(1, 5, 1)
	var second := await put_creature(1, 4, 1)
	var victim := await put_creature(2, 1, 1)
	var blocker := await put_creature(2, 1, 6, {}, true)
	start_combat()
	var made := _fight([[killer, victim], [second, victim]], [[blocker, 1]])
	assert_eq(victim.get_parent(), _discard(2))
	assert_eq(made[1].result.kind, "blocked")
	assert_eq(game.stats.current(blocker, "Guard"), 2, "6 - 4")


func test_the_target_being_removed_before_resolution_deals_nothing():
	var attacker := await put_creature(1, 5, 1)
	var target := await put_creature(2, 1, 1)
	start_combat()
	combat.declare_attack(attacker, target)
	combat.confirm_attackers()
	game.effects.destroy(target)
	combat.confirm_blocks()
	assert_eq(attacker.get_parent(), board)
	assert_eq(game.stats.current(attacker, "Strike"), 5)
	assert_eq(combat.attacks[0].result.kind, "target_gone")
	assert_eq(_life(2), LIFE, "It does not turn into an attack on the player")


func test_if_every_blocker_is_gone_the_attack_does_not_hit_its_target():
	var attacker := await put_creature(1, 5, 1)
	var blocker := await put_creature(2, 1, 1, {}, true)
	start_combat()
	combat.declare_attack(attacker, 2)
	combat.confirm_attackers()
	combat.declare_block(blocker, combat.attacks[0])
	game.effects.destroy(blocker)
	assert_true(combat.attacks[0].was_blocked)
	combat.confirm_blocks()
	assert_eq(combat.attacks[0].result.kind, "blockers_gone")
	assert_eq(_life(2), LIFE)


func test_a_destroyed_attacker_leaves_combat():
	var doomed := await put_creature(1, 5, 1)
	var other := await put_creature(1, 1, 1)
	start_combat()
	combat.declare_attack(doomed, 2)
	combat.declare_attack(other, 2)
	combat.confirm_attackers()
	game.effects.destroy(doomed)
	assert_true(combat.attacks[0].removed)
	combat.confirm_blocks()
	assert_eq(combat.attacks[0].result.kind, "removed")
	assert_eq(_life(2), LIFE - 1, "Only the other attack hit")


func test_negate_attack_and_remove_from_combat():
	var a := await put_creature(1, 3, 1)
	var b := await put_creature(1, 4, 1)
	var c := await put_creature(1, 2, 1)
	var d := await put_creature(1, 2, 1)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	for x in [a, b, c, d]:
		combat.declare_attack(x, 2)
	combat.confirm_attackers()
	assert_true(combat.negate_attack(combat.attack_of(a)))
	assert_false(combat.negate_attack(combat.attack_of(a)), "Only once")
	assert_false(combat.declare_block(blocker, combat.attack_of(a)), "No point blocking a negated attack")
	assert_true(combat.declare_block(blocker, combat.attack_of(b)))
	assert_true(combat.remove_from_combat(blocker), "A blocker leaves combat")
	assert_eq(combat.attack_of(b).blockers, [])
	assert_true(combat.remove_from_combat(c), "An attacker's attack is removed")
	combat.confirm_blocks()
	assert_eq(combat.attacks.map(func(x): return x.result.kind),
			["negated", "blockers_gone", "removed", "player"])
	assert_eq(_life(2), LIFE - 2, "Only d hit: b was blocked, and stays blocked when its blocker leaves")
	assert_eq(game.stats.current(blocker, "Guard"), 5)


func test_a_creature_with_strike_zero_destroys_itself_attacking():
	# Used stat 0 means destroyed, taken literally (documented in FateCombat)
	var weak := await put_creature(1, "Goblin Ledgerkeeper")
	var target := await put_creature(2, 2, 2, {}, true)
	start_combat()
	_fight([[weak, target]])
	assert_eq(weak.get_parent(), _discard(1))
	assert_eq(game.stats.current(target, "Guard"), 2)


# --- the end of the game -----------------------------------------------------------------------------------------------------

func test_lethal_damage_defeats_the_player_and_stops_the_game():
	game.player(2).life = 2
	var first := await put_creature(1, 3, 1)
	var second := await put_creature(1, 3, 1)
	start_combat()
	var defeated := []
	game.player_defeated.connect(func(pid): defeated.append(pid))
	var made := _fight([[first, 2], [second, 2]])
	assert_eq(defeated, [2])
	assert_true(game.is_over)
	assert_eq(game.winner_id, 1)
	assert_true(made[0].resolved)
	assert_false(made[1].resolved, "Nothing resolves after the game is over")
	assert_eq(_life(2), -1)
	assert_eq(game.phase, Phase.COMBAT_RESOLVE, "The turn stops")
	assert_false(game.advance_phase())
	assert_true(board.winner_banner.visible)
	assert_eq(board.winner_banner.text, "Player 1 wins")
	assert_eq(board.status_label.text, "Game over - Player 1 wins")
	assert_true(board.next_button.disabled)
	assert_true(board.end_turn_button.disabled)


# --- turn integration -----------------------------------------------------------------------------------------------------------

func test_the_combat_phases_run_through_the_combat_manager():
	assert_eq(game.combat, combat, "The game has a combat manager")
	var steps := []
	combat.step_changed.connect(func(s): steps.append(s))
	start_combat()
	assert_eq(combat.step, FateCombat.Step.DECLARE)
	assert_true(game.can_request_next_phase())
	assert_true(game.request_next_phase(), "Next phase confirms the attackers")
	assert_eq(game.phase, Phase.END, "Nobody attacked: intercept and resolve are passed at once")
	assert_eq(steps, [FateCombat.Step.DECLARE, FateCombat.Step.INTERCEPT, FateCombat.Step.RESOLVE,
			FateCombat.Step.IDLE])


func test_next_phase_confirms_each_step():
	var attacker := await put_creature(1, 2, 1)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	combat.declare_attack(attacker, 2)
	game.request_next_phase()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	combat.declare_block(blocker, combat.attacks[0])
	game.request_next_phase()
	assert_eq(game.phase, Phase.END)
	assert_eq(game.stats.current(blocker, "Guard"), 3)


func test_advancing_the_phase_directly_confirms_implicitly():
	var kw := TestKeyword.make("Direct Test")
	game.keywords.register(kw)
	var attacker := await put_creature(1, 2, 1, {"Direct Test": 1})
	start_combat()
	combat.declare_attack(attacker, 2)
	assert_true(game.advance_phase(), "Skipping the confirm calls")
	assert_eq(kw.hooks_called("on_attack_declared").size(), 1, "The attackers were confirmed on the way")
	assert_true(game.advance_phase())
	assert_eq(_life(2), LIFE - 2, "... and the attack resolved")


func test_ending_the_turn_cancels_the_combat():
	var attacker := await put_creature(1, 2, 1)
	start_combat()
	var cancelled := []
	combat.combat_cancelled.connect(func(): cancelled.append(true))
	combat.declare_attack(attacker, 2)
	game.end_turn()
	assert_eq(cancelled, [true])
	assert_eq(combat.step, FateCombat.Step.IDLE)
	assert_eq(game.active_id, 2)
	assert_eq(_life(2), LIFE, "Nothing resolved")
	game.draw_extra_card()
	game.advance_phase()
	assert_eq(combat.attacks, [], "A new combat phase starts with no attacks")


func test_a_new_turn_allows_attacking_again():
	var attacker := await put_creature(1, 2, 1)
	start_combat()
	_fight([[attacker, 2]])
	assert_eq(_life(2), LIFE - 2)
	game.advance_phase()
	assert_eq(game.active_id, 2)
	game.end_turn()
	game.draw_extra_card()
	game.advance_phase()
	assert_eq(game.phase, Phase.COMBAT_DECLARE)
	assert_eq(combat.eligible_attackers(), [attacker], "Once per combat phase, not once per game")


func test_resolution_waits_between_attacks():
	var a := await put_creature(1, 1, 1)
	var b := await put_creature(1, 1, 1)
	combat.resolve_delay = 0.15
	start_combat()
	combat.declare_attack(a, 2)
	combat.declare_attack(b, 2)
	combat.confirm_attackers()
	combat.confirm_blocks()
	assert_eq(_life(2), LIFE - 1, "One attack resolved, the pause is running")
	assert_eq(game.phase, Phase.COMBAT_RESOLVE)
	await wait_seconds(0.5)
	assert_eq(_life(2), LIFE - 2)
	assert_eq(game.phase, Phase.END)


func test_next_phase_skips_the_pause_between_attacks():
	var a := await put_creature(1, 1, 1)
	var b := await put_creature(1, 1, 1)
	var c := await put_creature(1, 1, 1)
	combat.resolve_delay = 30.0
	start_combat()
	for x in [a, b, c]:
		combat.declare_attack(x, 2)
	combat.confirm_attackers()
	combat.confirm_blocks()
	assert_eq(_life(2), LIFE - 1)
	game.request_next_phase()
	assert_eq(_life(2), LIFE - 3, "The rest resolved at once")
	assert_eq(game.phase, Phase.END)


func test_manual_resolution_with_resolve_next():
	var a := await put_creature(1, 1, 1)
	var b := await put_creature(1, 1, 1)
	combat.auto_resolve = false
	start_combat()
	combat.declare_attack(a, 2)
	combat.declare_attack(b, 2)
	combat.confirm_attackers()
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.COMBAT_RESOLVE)
	assert_eq(_life(2), LIFE)
	assert_eq(combat.resolve_next().attacker, a)
	assert_eq(_life(2), LIFE - 1)
	assert_eq(combat.resolve_next().attacker, b)
	assert_null(combat.resolve_next())
	combat.finish_resolution()
	assert_eq(game.phase, Phase.END)


# --- reaction windows ---------------------------------------------------------------------------------------------------------

func test_reaction_windows_continue_at_once_by_default():
	var attacker := await put_creature(1, 2, 1)
	start_combat()
	var windows := []
	combat.reaction_window_requested.connect(func(w): windows.append([w.step, w.player_id]))
	_fight([[attacker, 2]])
	assert_eq(windows, [["declare_end", 2], ["intercept_end", 2]])
	assert_eq(game.phase, Phase.END)


func test_a_handler_can_hold_the_declare_window():
	var attacker := await put_creature(1, 2, 1)
	start_combat()
	var held := {}
	combat.reaction_window_requested.connect(func(w):
		if w.step == "declare_end":
			held["window"] = w
			held["token"] = w.hold())
	combat.declare_attack(attacker, 2)
	combat.confirm_attackers()
	assert_eq(game.phase, Phase.COMBAT_DECLARE, "Waiting for the reaction")
	assert_eq(combat.current_window, held.window)
	assert_false(combat.attacks[0].resolved)
	held.window.release(held.token)
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT, "Released: combat continues")
	assert_null(combat.current_window)


func test_a_handler_can_hold_the_intercept_window_and_next_phase_closes_it():
	var attacker := await put_creature(1, 2, 1)
	start_combat()
	combat.reaction_window_requested.connect(func(w):
		if w.step == "intercept_end":
			w.hold())
	combat.declare_attack(attacker, 2)
	combat.confirm_attackers()
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	assert_not_null(combat.current_window)
	game.request_next_phase()
	assert_eq(game.phase, Phase.END, "Next phase closes the window and combat goes on")
	assert_eq(_life(2), LIFE - 2)


func test_ending_the_turn_during_a_reaction_window_abandons_the_combat():
	var attacker := await put_creature(1, 2, 1)
	start_combat()
	combat.reaction_window_requested.connect(func(w): w.hold())
	combat.declare_attack(attacker, 2)
	combat.confirm_attackers()
	game.end_turn()
	assert_null(combat.current_window)
	assert_eq(game.active_id, 2)
	assert_eq(game.phase, Phase.ENERGY, "The pending confirm did not move the new turn on")


# --- keyword hooks in combat -----------------------------------------------------------------------------------------------------

func test_keyword_hooks_fire_at_the_right_moments():
	var kw := TestKeyword.make("Hook Test")
	kw.use_shared_log = true
	game.keywords.register(kw)
	var attacker := await put_creature(1, 3, 3, {"Hook Test": 1})
	var blocker := await put_creature(2, 1, 5, {"Hook Test": 1}, true)
	start_combat()
	var made := _fight([[attacker, 2]], [[blocker, 0]])
	assert_eq(kw.hooks_called("on_attack_declared")[0].slice(1), [attacker, made[0]])
	assert_eq(kw.hooks_called("on_blocked")[0].slice(1), [attacker, made[0], [blocker]])
	assert_eq(kw.hooks_called("on_blocking")[0].slice(1), [blocker, made[0]])
	var before: Array = kw.hooks_called("before_combat_damage")
	assert_eq(before.map(func(c): return c[1]), [attacker, blocker], "Once per participant")
	var dealt: Array = kw.hooks_called("on_damage_dealt")
	assert_eq(dealt.size(), 2, "Each side dealt damage")
	assert_eq(dealt[0].slice(1), [attacker, blocker, 3, "combat"])
	assert_eq(dealt[1].slice(1), [blocker, attacker, 3, "combat"])
	var order: Array = kw.shared_log.filter(func(h): return h in ["Hook Test:on_attack_declared",
			"Hook Test:on_blocked", "Hook Test:before_combat_damage", "Hook Test:on_destroyed"])
	assert_eq(order[0], "Hook Test:on_attack_declared")
	assert_eq(order[1], "Hook Test:on_blocked")
	assert_eq(order[2], "Hook Test:before_combat_damage")
	assert_eq(order[-1], "Hook Test:on_destroyed")


func test_keyword_restrictions_on_attacking_and_blocking():
	var tired := TestKeyword.make("Tired Test")
	tired.allow_attack = false
	var passive := TestKeyword.make("Passive Test")
	passive.allow_block = false
	var elusive := TestKeyword.make("Elusive Test")
	elusive.allow_blocked_by = false
	var hidden := TestKeyword.make("Hidden Test")
	hidden.allow_attacked = false
	for kw in [tired, passive, elusive, hidden]:
		game.keywords.register(kw)
	var tired_one := await put_creature(1, 2, 2, {"Tired Test": 1})
	var elusive_one := await put_creature(1, 2, 2, {"Elusive Test": 1})
	var normal := await put_creature(1, 2, 2)
	var passive_one := await put_creature(2, 2, 2, {"Passive Test": 1}, true)
	var guard := await put_creature(2, 2, 2, {}, true)
	var hidden_one := await put_creature(2, 2, 2, {"Hidden Test": 1})
	start_combat()
	assert_false(combat.declare_attack(tired_one, 2), "can_attack")
	assert_true(not combat.eligible_attackers().has(tired_one))
	assert_false(combat.declare_attack(normal, hidden_one), "can_be_attacked: it cannot be targeted")
	assert_true(combat.declare_attack(normal, 2))
	assert_true(combat.declare_attack(elusive_one, 2))
	combat.confirm_attackers()
	assert_false(combat.declare_block(passive_one, combat.attack_of(normal)), "can_block")
	assert_false(combat.declare_block(guard, combat.attack_of(elusive_one)), "can_be_blocked_by")
	assert_true(combat.declare_block(guard, combat.attack_of(normal)))
	assert_eq(combat.eligible_blockers(combat.attack_of(elusive_one)), [])


func test_block_restrictions_on_the_attack_record_force_a_single_blocker():
	var attacker := await put_creature(1, 2, 2)
	var chosen := await put_creature(2, 1, 4, {}, true)
	var other := await put_creature(2, 1, 4, {}, true)
	start_combat()
	combat.declare_attack(attacker, 2)
	var attack: FateAttack = combat.attack_of(attacker)
	attack.add_restriction({"kind": "only", "cards": [chosen], "source": attacker})
	combat.confirm_attackers()
	assert_false(combat.declare_block(other, attack))
	assert_true(combat.declare_block(chosen, attack))
	attack.remove_restrictions_from(attacker)
	assert_true(combat.declare_block(other, attack), "Restriction gone")
	var none := FateAttack.new(attacker, 2)
	none.add_restriction({"kind": "none"})
	assert_false(none.restrictions_allow(chosen))
	var except := FateAttack.new(attacker, 2)
	except.add_restriction({"kind": "except", "cards": [chosen]})
	assert_false(except.restrictions_allow(chosen))
	assert_true(except.restrictions_allow(other))


func test_indomitable_style_damage_hold_and_untethered_style_destination_in_combat():
	var indomitable := TestKeyword.make("Hold Test")
	indomitable.hold_at_one = true
	var untethered := TestKeyword.make("Removal Test")
	untethered.destination = "removed"
	game.keywords.register(indomitable)
	game.keywords.register(untethered)
	var attacker := await put_creature(1, 2, 2, {"Hold Test": 1})
	var target := await put_creature(2, 1, 5, {"Removal Test": 1}, true)
	var other := await put_creature(2, 3, 5, {"Removal Test": 1})
	start_combat()
	_fight([[attacker, target]])
	assert_eq(game.stats.current(attacker, "Strike"), 1, "The hold kept it alive at 1")
	assert_eq(attacker.get_parent(), board)
	assert_eq(game.stats.current(target, "Guard"), 3)
	# A destroyed card with the Untethered-style keyword goes to the removed pile
	game.effects.destroy(other, null, "combat")
	assert_eq(other.get_parent(), FateZones.container("removed", 2))


func test_a_keyword_triggered_when_blocked_can_hurt_the_blocking_player():
	var savage := TestKeyword.make("Savage Test")
	savage.on_blocked_cb = func(card, attack, blockers):
		game.effects.deal_damage(game.player(blockers[0].controller_id), 2, card, "effect")
	game.keywords.register(savage)
	var attacker := await put_creature(1, 3, 3, {"Savage Test": 1})
	var blocker := await put_creature(2, 1, 4, {}, true)
	start_combat()
	_fight([[attacker, 2]], [[blocker, 0]])
	assert_eq(_life(2), LIFE - 2, "Two damage to the blocker's controller before the fight")
