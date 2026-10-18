extends GutTest
# The pure-data pieces of the Fate AI: the combat simulator, the evaluation and the planners that work
# on a snapshot (no scene needed). The simulator mirrors FateCombat; the engine side of that promise is
# checked in tests/integration/test_fate_ai_sim_parity.gd.

const Sim := preload("res://src/custom/fate/ai/FateAISim.gd")
const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")
const Profile := preload("res://src/custom/fate/ai/FateAIProfile.gd")


func _unit(uid: int, ctrl: int, strike: int, guard: int, pos := "strike", kw := {}, mv := 2) -> Dictionary:
	return {"uid": uid, "card": null, "name": "U%d" % uid, "owner": ctrl, "ctrl": ctrl,
			"strike": strike, "guard": guard, "full_strike": strike, "full_guard": guard,
			"pos": pos, "kw": kw, "mv": mv, "unique": false, "sick": false, "can_attack": true}


func _state(units: Array, life1 := 10, life2 := 10) -> Dictionary:
	var s := {"me": 1, "opp": 2, "turn": 3, "active": 1, "life": {1: life1, 2: life2}, "units": {},
			"face_weight": 1.0}
	for u in units:
		s.units[u.uid] = u
	return s


func _profile() -> Profile:
	var p := Profile.new()
	p.configure(["Order"], Profile.Level.NORMAL, 1)
	return p


func test_unblocked_attack_hits_the_player() -> void:
	var s := _state([_unit(1, 1, 3, 1)])
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {})
	assert_eq(res.life[2], 9, "Strike 3 still takes only 1 life")
	assert_eq(res.life[1], 10)


func test_creatures_destroyed_in_combat_cost_their_controller_one_life_each() -> void:
	# Strike 3 into Guard 2: the blocker dies (player 2 loses 1); the attacker lives
	var s := _state([_unit(1, 1, 3, 1), _unit(2, 2, 1, 2, "guard")])
	var res := Sim.run(s, [Sim.make_attack(1, "unit", 2)], {})
	assert_eq(res.life[2], 9, "the lost creature costs 1 life")
	assert_eq(res.life[1], 10)
	# Both die: one life each
	s = _state([_unit(1, 1, 3, 3), _unit(2, 2, 1, 3, "guard")])
	res = Sim.run(s, [Sim.make_attack(1, "unit", 2)], {})
	assert_eq(res.life[1], 9)
	assert_eq(res.life[2], 9)


func test_attacker_wins_against_a_smaller_guard() -> void:
	# Strike 3 into Guard 2: the attacker is left with 1, the blocker is destroyed (spec Section 3)
	var s := _state([_unit(1, 1, 3, 1), _unit(2, 2, 1, 2, "guard")])
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2]})
	assert_true(Sim.is_alive(res, s.units[1]))
	assert_eq(Sim.stat(res, s.units[1], "strike"), 1)
	assert_false(Sim.is_alive(res, s.units[2]))
	assert_eq(res.life[2], 9, "A blocked attack does not reach the player: only the lost blocker costs 1 life")


func test_bigger_guard_destroys_the_attacker() -> void:
	var s := _state([_unit(1, 1, 2, 1), _unit(2, 2, 1, 3, "guard")])
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2]})
	assert_false(Sim.is_alive(res, s.units[1]))
	assert_true(Sim.is_alive(res, s.units[2]))
	assert_eq(Sim.stat(res, s.units[2], "guard"), 1)


func test_equal_stats_destroy_both() -> void:
	var s := _state([_unit(1, 1, 3, 1), _unit(2, 2, 1, 3, "guard")])
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2]})
	assert_false(Sim.is_alive(res, s.units[1]))
	assert_false(Sim.is_alive(res, s.units[2]))


func test_two_blockers_share_the_strike_in_order() -> void:
	var s := _state([_unit(1, 1, 3, 1), _unit(2, 2, 1, 2, "guard"), _unit(3, 2, 1, 2, "occupied")])
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2, 3]})
	assert_false(Sim.is_alive(res, s.units[2]), "the first blocker absorbs its Guard 2")
	assert_true(Sim.is_alive(res, s.units[3]))
	assert_eq(Sim.stat(res, s.units[3], "guard"), 1)
	assert_false(Sim.is_alive(res, s.units[1]), "the attacker loses 2 + 1 = its whole Strike")


func test_indomitable_blocker_survives_with_one() -> void:
	var s := _state([_unit(1, 1, 5, 1), _unit(2, 2, 1, 2, "guard", {"Indomitable": 1})])
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2]})
	assert_true(Sim.is_alive(res, s.units[2]))
	assert_eq(Sim.stat(res, s.units[2], "guard"), 1)
	assert_eq(Sim.stat(res, s.units[1], "strike"), 3, "the attacker still loses the blocker's whole Guard")


func test_attacking_an_upright_creature_uses_strike_on_both_sides() -> void:
	var s := _state([_unit(1, 1, 3, 3), _unit(2, 2, 2, 5, "strike")])
	var res := Sim.run(s, [Sim.make_attack(1, "unit", 2)], {})
	assert_false(Sim.is_alive(res, s.units[2]), "Strike 2 against Strike 3: destroyed")
	assert_eq(Sim.stat(res, s.units[1], "strike"), 1)


func test_attacking_a_guarding_creature_uses_its_guard() -> void:
	var s := _state([_unit(1, 1, 3, 3), _unit(2, 2, 2, 5, "guard")])
	var res := Sim.run(s, [Sim.make_attack(1, "unit", 2)], {})
	assert_true(Sim.is_alive(res, s.units[2]))
	assert_eq(Sim.stat(res, s.units[2], "guard"), 2)
	assert_false(Sim.is_alive(res, s.units[1]), "Strike 3 against Guard 5 loses everything")


func test_savage_hits_the_blocking_player_first() -> void:
	var s := _state([_unit(1, 1, 3, 3, "strike", {"Savage": 2}), _unit(2, 2, 1, 4, "guard")])
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2]})
	assert_eq(res.life[2], 8)


func test_savage_of_an_ai_seat_destroys_a_valuable_creature_instead_of_hitting_the_player() -> void:
	var s := _state([_unit(1, 1, 3, 3, "strike", {"Savage": 3}), _unit(2, 2, 1, 4, "guard"),
			_unit(3, 2, 2, 2, "guard", {}, 5)])
	s["ai_seats"] = [1]
	var res := Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2]})
	assert_false(Sim.is_alive(res, s.units[3]), "Guard 2 dies to 3 Savage damage")
	assert_eq(res.life[2], 10, "the player was not hit")
	# A seat without an AI keeps the engine default (the blocking player takes the Savage damage)
	s["ai_seats"] = []
	assert_eq(Sim.run(s, [Sim.make_attack(1, "player", 2)], {0: [2]}).life[2], 7)


func test_a_removed_attacker_leaves_the_attack_empty() -> void:
	var s := _state([_unit(1, 1, 3, 3)])
	var a := Sim.make_attack(1, "player", 2)
	a.removed = true
	assert_eq(Sim.run(s, [a], {}).life[2], 10)


func test_unblockable_and_cannot_block() -> void:
	var s := _state([_unit(1, 1, 2, 1, "strike", {"Unblockable": 1}), _unit(2, 2, 1, 3, "guard"),
			_unit(3, 2, 0, 3, "guard", {"Cannot block": 1}), _unit(4, 1, 1, 1, "strike")])
	var a := Sim.make_attack(1, "player", 2)
	assert_eq(Sim.blockers_for(s, 2, a).size(), 0, "nobody can block an Unblockable attacker")
	var b := Sim.make_attack(4, "player", 2)
	assert_eq(Sim.blockers_for(s, 2, b).map(func(u): return u.uid), [2], "Cannot block stays out")


func test_the_defender_blocks_an_attacker_it_beats_for_free() -> void:
	var s := _state([_unit(1, 1, 3, 1), _unit(2, 2, 1, 4, "guard")])
	var attacks := [Sim.make_attack(1, "player", 2)]
	var blocks := Sim.best_blocks(s, attacks, 2)
	assert_eq(blocks.get(0, []), [2])


func test_the_defender_does_not_chump_block_when_the_loss_costs_as_much_as_the_hit() -> void:
	# An unblocked attack takes 1 life, a creature lost in combat takes 1 life too: a block that only loses the
	# creature is never better than taking the hit
	var s := _state([_unit(1, 1, 4, 4), _unit(2, 2, 1, 1, "guard")], 10, 3)
	var blocks := Sim.best_blocks(s, [Sim.make_attack(1, "player", 2)], 2)
	assert_true(blocks.is_empty(), "no chump block: %s" % str(blocks))


func test_lethal_attack_is_found() -> void:
	var s := _state([_unit(1, 1, 2, 2), _unit(2, 1, 2, 2), _unit(3, 2, 1, 1, "strike")], 10, 2)
	var plan := Combat.plan_attack(s, _profile())
	assert_true(plan.lethal, "1 + 1 = 2 damage against an empty guard line is lethal")
	assert_eq(plan.attacks.size(), 2)


func test_no_attack_into_a_wall_that_kills_the_attacker() -> void:
	var s := _state([_unit(1, 1, 2, 2), _unit(2, 2, 1, 5, "guard", {}, 4)])
	var plan := Combat.plan_attack(s, _profile())
	assert_eq(plan.attacks.size(), 0, "a 2/2 does not attack a 5 Guard blocker")


func test_attacks_an_open_player_with_everything_that_can_spare_it() -> void:
	var s := _state([_unit(1, 1, 2, 2), _unit(2, 1, 3, 1)])
	var plan := Combat.plan_attack(s, _profile())
	assert_gt(plan.attacks.size(), 0, "nobody can block: free damage")


func test_life_value_is_convex() -> void:
	assert_gt(Eval.life_value(3) - Eval.life_value(2), Eval.life_value(9) - Eval.life_value(8))
	assert_lt(Eval.life_value(0), -500.0)
