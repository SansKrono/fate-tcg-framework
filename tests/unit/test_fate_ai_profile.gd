extends GutTest
# The weighted AI profile (src/custom/fate/ai/FateAIProfile.gd): the parameter table, grades, styles, specs and how
# the planners read them. No scene needed.

const Profile := preload("res://src/custom/fate/ai/FateAIProfile.gd")
const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")


func _make(spec, domains := ["Order"]) -> Profile:
	var p := Profile.new()
	p.resolve(spec, domains, 5)
	return p


func _unit(uid: int, ctrl: int, strike: int, guard: int, pos := "strike", kw := {}, mv := 2) -> Dictionary:
	return {"uid": uid, "card": null, "name": "U%d" % uid, "owner": ctrl, "ctrl": ctrl,
			"strike": strike, "guard": guard, "full_strike": strike, "full_guard": guard,
			"pos": pos, "kw": kw, "mv": mv, "unique": false, "sick": false, "can_attack": true}


func _state(units: Array, profile: Profile, life1 := 10, life2 := 10) -> Dictionary:
	var s := {"me": 1, "opp": 2, "turn": 3, "active": 1, "life": {1: life1, 2: life2}, "units": {},
			"face_weight": profile.aggression, "w": profile.eval_weights(), "hand_count": {1: 0, 2: 0},
			"mana": {1: {"untapped": 0, "total": 0}, 2: {"untapped": 0, "total": 0}}}
	for u in units:
		s.units[u.uid] = u
	return s


# --- the table ------------------------------------------------------------------------------------------

func test_every_parameter_has_a_field_with_its_default() -> void:
	var p := Profile.new()
	for key in Profile.PARAMS:
		assert_true(key in p, "field %s exists" % key)
		assert_eq(p.get(key), Profile.PARAMS[key].def, "%s starts at its default" % key)


func test_every_field_is_a_parameter() -> void:
	# The declared fields (var ...) that are not bookkeeping must be in the table, or they cannot be tuned
	var bookkeeping := ["level", "label", "grade", "skill", "style", "domains", "overrides", "rng", "focus", "_eval_w"]
	var p := Profile.new()
	for prop in p.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if prop.name in bookkeeping:
			continue
		assert_true(Profile.PARAMS.has(prop.name), "%s is in the parameter table" % prop.name)


func test_the_table_is_consistent() -> void:
	for key in Profile.PARAMS:
		var spec: Dictionary = Profile.PARAMS[key]
		assert_true(spec.has("def") and spec.has("group") and spec.has("doc"), "%s is described" % key)
		if not spec.def is bool:
			assert_true(spec.has("min") and spec.has("max"), "%s has a range" % key)
			assert_between(float(spec.def), float(spec.min), float(spec.max), "%s default is in range" % key)


func test_eval_weights_cover_the_evaluation_defaults() -> void:
	var w := Profile.new().eval_weights()
	assert_eq(w.keys().size(), Eval.DEFAULT_W.keys().size())
	for key in Eval.DEFAULT_W:
		assert_true(w.has(key), key)
		assert_almost_eq(float(w[key]), float(Eval.DEFAULT_W[key]), 0.0001, key)


func test_set_param_clamps_and_converts() -> void:
	var p := Profile.new()
	assert_true(p.set_param("aggression", 99))
	assert_eq(p.aggression, 3.0, "clamped to the range")
	assert_true(p.set_param("think_width", 2.6))
	assert_eq(p.think_width, 3, "rounded for an int parameter")
	assert_true(p.set_param("hold_reactions", "false"))
	assert_false(p.hold_reactions, "text is read as a bool")
	assert_false(p.set_param("no_such_parameter", 1))
	assert_eq(p.apply({"caution": 0.1, "nope": 3}), ["nope"], "apply returns the unknown names")
	assert_eq(p.to_dict().keys().size(), 3, "to_dict lists what differs from the defaults")


# --- grades --------------------------------------------------------------------------------------------

func test_grades_get_better() -> void:
	var novice := _make("novice")
	var easy := _make("easy")
	var normal := _make("normal")
	var hard := _make("hard")
	var expert := _make("expert")
	assert_gt(novice.noise, easy.noise)
	assert_gt(easy.noise, normal.noise)
	assert_lt(novice.think_width, normal.think_width)
	assert_lt(normal.think_width, hard.think_width)
	assert_lt(hard.think_width, expert.think_width)
	assert_gt(novice.mistake_rate, easy.mistake_rate)
	assert_eq(normal.mistake_rate, 0.0)
	assert_lt(normal.lookahead, expert.lookahead)
	assert_lt(normal.reaction_fear, expert.reaction_fear)
	assert_false(novice.scrap_burn or easy.scrap_burn, "the Scrap Cannon burst is knowledge of the card")
	assert_true(normal.scrap_burn and expert.scrap_burn)


func test_levels_map_to_grades() -> void:
	assert_eq(_make(Profile.Level.EASY).grade, "easy")
	assert_eq(_make(Profile.Level.NORMAL).grade, "normal")
	assert_eq(_make(Profile.Level.HARD).grade, "hard")
	assert_eq(_make(Profile.Level.EXPERT).grade, "expert")
	assert_eq(_make(Profile.Level.NOVICE).grade, "novice")
	assert_eq(_make(1).level, Profile.Level.NORMAL)


func test_a_skill_between_grades_interpolates() -> void:
	var mid := _make("0.375")
	var easy := _make("easy")
	var normal := _make("normal")
	assert_between(mid.noise, normal.noise, easy.noise, "noise between easy and normal")
	assert_between(float(mid.think_width), float(easy.think_width), float(normal.think_width))
	assert_eq(mid.grade, "easy")


# --- specs ---------------------------------------------------------------------------------------------

func test_a_spec_text_names_grade_style_and_parameters() -> void:
	var p := _make("hard+control;aggression=1.7;caution=0.1")
	assert_eq(p.grade, "hard")
	assert_eq(p.style, "control")
	assert_eq(p.aggression, 1.7, "an explicit parameter wins over the style")
	assert_eq(p.caution, 0.1)
	assert_eq(p.guard_reserve, 1, "the style applies where nothing overrides it")
	assert_eq(p.think_width, 4, "the grade applies")


func test_a_dictionary_spec() -> void:
	var p := _make({"grade": "easy", "style": "ramp", "params": {"max_energy": 10}, "label": "slow ramp"})
	assert_eq(p.label, "slow ramp")
	assert_eq(p.max_energy, 10)
	assert_eq(p.grade, "easy")


func test_the_domain_sets_the_style_unless_one_is_named() -> void:
	assert_eq(_make("normal", ["Primal"]).style, "ramp")
	assert_eq(_make("normal", ["Order"]).style, "aggro")
	assert_eq(_make("normal+control", ["Order"]).style, "control")
	assert_gt(_make("normal", ["Order"]).aggression, _make("normal", ["Primal"]).aggression)


func test_the_old_domain_numbers_survive() -> void:
	var order := _make("normal", ["Order"])
	assert_eq(order.aggression, 1.2)
	assert_eq(order.caution, 0.5)
	assert_false(order.use_embody)
	var primal := _make("normal", ["Primal"])
	assert_eq(primal.energy_target, 6)


func test_unknown_parts_do_not_break_a_spec() -> void:
	var p := _make("hard+nonsense;made_up=3")
	assert_eq(p.grade, "hard")


func test_describe_lists_every_parameter() -> void:
	var text := Profile.describe()
	for key in Profile.PARAMS:
		assert_true(text.contains(key), key)


# --- the planners read the profile --------------------------------------------------------------------

func test_attack_margin_makes_the_ai_passive() -> void:
	var eager := _make("normal")
	var shy := _make("normal;attack_margin=3")
	# One point of Strike against an empty board gains about one life point of damage: below the shy margin
	var units := [_unit(1, 1, 1, 1)]
	assert_gt(Combat.plan_attack(_state(units.duplicate(true), eager), eager).attacks.size(), 0)
	assert_eq(Combat.plan_attack(_state(units.duplicate(true), shy), shy).attacks.size(), 0)


func test_guard_reserve_keeps_creatures_home() -> void:
	var p := _make("normal;guard_reserve=2")
	var units := [_unit(1, 1, 3, 3), _unit(2, 1, 3, 3), _unit(3, 1, 3, 3), _unit(4, 2, 1, 5, "guard")]
	var plan := Combat.plan_attack(_state(units, p), p)
	assert_lte(plan.attacks.size(), 1, "three creatures, two stay home")


func test_valuation_weights_change_the_worth() -> void:
	var greedy := _make("normal;w_savage=3;w_strike=2")
	var plain := _make("normal")
	var unit := _unit(1, 1, 3, 3, "strike", {"Savage": 2})
	assert_gt(Eval.unit_value(unit, -1, -1, greedy.eval_weights()), Eval.unit_value(unit, -1, -1, plain.eval_weights()))
	var token := _unit(2, 1, 1, 1)
	token["token"] = true
	var cheap := _make("normal;w_token=0.5")
	assert_lt(Eval.unit_value(token, -1, -1, cheap.eval_weights()), Eval.unit_value(token, -1, -1, plain.eval_weights()))


func test_preserve_and_kill_value_scale_the_score() -> void:
	var careful := _make("normal;preserve_value=2")
	var units := [_unit(1, 1, 3, 3), _unit(2, 2, 3, 3)]
	var s1 := Eval.score(_state(units.duplicate(true), careful), null, 1)
	var plain := _make("normal")
	var s2 := Eval.score(_state(units.duplicate(true), plain), null, 1)
	assert_ne(s1, s2)


func test_life_curve_parameters() -> void:
	var w := _make("normal;life_slope=3").eval_weights()
	assert_gt(Eval.life_value(8, w), Eval.life_value(8))
	assert_eq(Eval.life_value(0, w), -Eval.LOSS)


func test_slips_follow_the_mistake_rate() -> void:
	var never := _make("normal")
	var always := _make("normal;mistake_rate=1")
	for _i in 20:
		assert_false(never.slips())
		assert_true(always.slips())


func test_lookahead_zero_ignores_the_counter_attack() -> void:
	# A creature that attacks stays upright and cannot block: with a look-ahead the AI sees that the enemy's big
	# creature then hits it, without one it only sees this combat
	var blind := _make("normal;lookahead=0;caution=1")
	var wary := _make("normal;lookahead=1;caution=1")
	var units := [_unit(1, 1, 1, 1), _unit(2, 2, 6, 6, "guard")]
	var s_blind := Combat.score_plan(_state(units.duplicate(true), blind), [Combat.Sim.make_attack(1, "player", 2)], blind)
	var s_wary := Combat.score_plan(_state(units.duplicate(true), wary), [Combat.Sim.make_attack(1, "player", 2)], wary)
	assert_gte(s_blind, s_wary, "ignoring the counter-attack never scores lower")


# --- profile files --------------------------------------------------------------------------------------

func test_the_shipped_profile_files_load() -> void:
	var names := Profile.file_names()
	assert_true("patient_wall" in names and "reckless_rush" in names, "the example profiles are found: %s" % str(names))
	for n in names:
		var p := _make(n)
		assert_ne(p.label, "", n)
		assert_eq(p.overrides.size() >= 0, true)
	var wall := _make("patient_wall")
	assert_eq(wall.grade, "hard")
	assert_eq(wall.guard_reserve, 2)
	assert_eq(wall.label, "patient wall")
	var rush := _make("reckless_rush")
	assert_eq(rush.aggression, 2.0)
	assert_false(rush.hold_reactions)
	var beginner := _make("sleepy_beginner")
	assert_lt(beginner.skill, 0.2)
	assert_eq(beginner.mistake_rate, 0.2)


func test_a_profile_file_can_be_combined_with_parameters() -> void:
	var p := _make("patient_wall;guard_reserve=0")
	assert_eq(p.guard_reserve, 0, "an override after the file wins")
