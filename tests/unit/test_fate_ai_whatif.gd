extends GutTest
# FateAIWhatIf: the worth of pump and removal effects as the gain of the re-planned attack (pure data, no scene).

const Profile := preload("res://src/custom/fate/ai/FateAIProfile.gd")
const WhatIf := preload("res://src/custom/fate/ai/FateAIWhatIf.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")
const Doctrine := preload("res://src/custom/fate/ai/FateAIDoctrine.gd")


func _profile(spec := "normal") -> Profile:
	var p := Profile.new()
	p.resolve(spec, ["Order"], 3)
	return p


func _unit(uid: int, ctrl: int, strike: int, guard: int, pos := "strike", kw := {}, unique := false) -> Dictionary:
	return {"uid": uid, "card": null, "name": "U%d" % uid, "owner": ctrl, "ctrl": ctrl,
			"strike": strike, "guard": guard, "full_strike": strike, "full_guard": guard,
			"pos": pos, "kw": kw, "mv": 2, "unique": unique, "sick": false, "can_attack": true,
			"token": false, "ability": false}


func _state(units: Array, profile: Profile, life1 := 10, life2 := 10) -> Dictionary:
	var s := {"me": 1, "opp": 2, "turn": 3, "active": 1, "life": {1: life1, 2: life2}, "units": {},
			"face_weight": profile.aggression, "w": profile.eval_weights(), "hand_count": {1: 0, 2: 0},
			"mana": {1: {"untapped": 0, "total": 0}, 2: {"untapped": 0, "total": 0}}}
	for u in units:
		s.units[u.uid] = u
	return s


func test_smite_is_worth_the_blocker_it_removes() -> void:
	var p := _profile()
	var s := _state([_unit(1, 1, 3, 3), _unit(2, 2, 3, 3, "guard")], p)
	var r := WhatIf.spell(s, p, "Smite")
	assert_gt(r.gain, 0.0, "removing the only blocker gains")
	assert_eq(r.focus, [2], "and the chooser is told which one")


func test_smite_leaves_unique_creatures_alone() -> void:
	var p := _profile()
	var s := _state([_unit(1, 1, 3, 3), _unit(2, 2, 6, 6, "guard", {}, true)], p)
	assert_true(WhatIf.spell(s, p, "Smite").is_empty(), "nothing to smite")


func test_smite_prefers_the_creature_in_the_way() -> void:
	var p := _profile()
	# A big attacker of theirs that is tilted cannot hurt me this turn; the blocker is what stops my attack
	var s := _state([_unit(1, 1, 4, 2), _unit(2, 2, 1, 5, "guard"), _unit(3, 2, 2, 2, "guard")], p)
	var r := WhatIf.spell(s, p, "Smite")
	assert_true(r.focus[0] in [2, 3])


func test_a_buff_without_creatures_gains_nothing() -> void:
	var p := _profile()
	var s := _state([_unit(2, 2, 3, 3, "guard")], p)
	assert_eq(WhatIf.spell(s, p, "Primal Wraith").gain, 0.0)


func test_primal_wraith_helps_a_blocked_attack() -> void:
	var p := _profile()
	var s := _state([_unit(1, 1, 3, 3), _unit(2, 2, 2, 4, "guard")], p)
	var r := WhatIf.spell(s, p, "Primal Wraith")
	assert_gte(r.gain, 0.0)


func test_battle_ready_turns_a_guard_into_an_attacker() -> void:
	var p := _profile()
	var s := _state([_unit(1, 1, 3, 2, "guard")], p)
	var r := WhatIf.spell(s, p, "Battle Ready")
	assert_gt(r.gain, 0.0, "a guard that could not attack now does")
	assert_true(1 in r.focus)
	assert_eq(r.attackers, 1)


func test_battle_ready_fills_up_with_enemy_guards() -> void:
	# The spell takes min(3, creatures) and my own come first; with one of mine the rest are theirs: an upright
	# enemy cannot intercept
	var p := _profile()
	var s := _state([_unit(1, 1, 3, 2, "guard"), _unit(2, 2, 2, 5, "guard"), _unit(3, 2, 1, 1, "guard")], p)
	var r := WhatIf.spell(s, p, "Battle Ready")
	assert_eq(r.focus.size(), 3)
	assert_true(2 in r.focus and 3 in r.focus)


func test_unmodelled_cards_have_no_model() -> void:
	var p := _profile()
	var s := _state([_unit(1, 1, 3, 3)], p)
	assert_true(WhatIf.spell(s, p, "Reinforcements").is_empty())
	assert_false(WhatIf.models_spell("Reinforcements"))
	assert_true(WhatIf.models_spell("Smite"))


func test_a_pump_ability_pays_for_its_energy_card() -> void:
	var cheap := _profile("normal;energy_card_value=0")
	var dear := _profile("normal;energy_card_value=5")
	var units := [_unit(1, 1, 3, 3), _unit(2, 1, 3, 3), _unit(3, 2, 3, 3, "guard")]
	units[0].name = "Devote Paladin"
	var a := WhatIf.ability(_state(units.duplicate(true), cheap), cheap, "Devote Paladin", 1)
	var b := WhatIf.ability(_state(units.duplicate(true), dear), dear, "Devote Paladin", 1)
	assert_almost_eq(float(a.gain) - float(b.gain), 5.0, 0.001, "the price is taken off the gain")


func test_doctrine_bonus_is_off_without_pursuit() -> void:
	var p := _profile("easy")
	assert_eq(p.doctrine_pursuit, 0.0)
	assert_eq(Doctrine.bonus(null, 1, null, p), 0.0, "no game needed when the profile does not pursue doctrines")
