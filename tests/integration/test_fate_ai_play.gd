extends "res://tests/FateCommon.gd"
# The AI's knowledge of real cards: ability chains, Evolve, spells valued by the attack they enable, reactions it can
# cast. Each test builds the position on the table and lets the planners (or a whole AI turn) act on it.

const MainPhase := preload("res://src/custom/fate/ai/FateAIMain.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Profile := preload("res://src/custom/fate/ai/FateAIProfile.gd")
const Reactions := preload("res://src/custom/fate/ai/FateAIReactions.gd")


func after_each():
	FateGame.domain_override = {}


func _profile(spec = "normal", domains := ["Order"]) -> Profile:
	var p := Profile.new()
	p.resolve(spec, domains, 11)
	p.pace = 0.0
	return p


# A fresh table where the two players have these domains
func _fresh(domains1: Array, domains2: Array) -> void:
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
	FateGame.domain_override = {1: domains1, 2: domains2}
	await before_each()


func _wait_for_turn_end(turn_number: int, frames := 3000) -> void:
	var n := 0
	while game.turn_number == turn_number and not game.is_over and n < frames:
		await get_tree().process_frame
		n += 1


func test_the_scrap_chain_runs_in_one_turn() -> void:
	await _fresh(["Innovation"], ["Order"])
	await put_on_table(1, "Goblin Ledgerkeeper", "creatures")
	await put_on_table(1, "Acquisition Fabricator", "creatures")
	await put_on_table(1, "Factory Crafter", "creatures")
	await fill_mana(1)
	assert_eq(game.tokens.counter(1, "scrap"), 0)
	var ai = game.set_ai(1, true, "normal")
	await _wait_for_turn_end(game.turn_number)
	assert_eq(ai.problems, [], "nothing illegal")
	var made := false
	for line in ai.log_lines:
		if "craft" in line:
			made = true
	assert_true(made, "scrap became an ingot and the ingot an automaton in the same turn: %s" % str(ai.log_lines))


func test_evolve_brawler_before_the_attack() -> void:
	await _fresh(["Primal"], ["Order"])
	var brawler := await put_on_table(1, "Beetle Brawler", "creatures")
	var deck_pile: Pile = FateZones.container("deck", 1)
	var ironside: Card = cfc.instance_card("Ironside Beetle")
	deck_pile.add_child(ironside)
	ironside.assign_owner(1)
	ironside._determine_idle_state()
	await fill_mana(1)
	var ai = game.set_ai(1, true, "normal")
	await _wait_for_turn_end(game.turn_number)
	assert_eq(ai.problems, [])
	var evolved := false
	for line in ai.log_lines:
		if "evolves" in line:
			evolved = true
	assert_true(evolved, "Beetle Brawler became Ironside Beetle: %s" % str(ai.log_lines))


func test_legacy_style_does_not_evolve() -> void:
	await _fresh(["Primal"], ["Order"])
	await put_on_table(1, "Beetle Brawler", "creatures")
	var deck_pile: Pile = FateZones.container("deck", 1)
	var ironside: Card = cfc.instance_card("Ironside Beetle")
	deck_pile.add_child(ironside)
	ironside.assign_owner(1)
	ironside._determine_idle_state()
	await fill_mana(1)
	var ai = game.set_ai(1, true, "normal+legacy")
	await _wait_for_turn_end(game.turn_number)
	for line in ai.log_lines:
		assert_false("evolves" in line, "the legacy style never evolves")


func test_smite_is_kept_for_a_creature_worth_removing() -> void:
	await _fresh(["Order"], ["Primal"])
	await put_on_table(1, "Moral Captain", "creatures")
	var token_like := await put_on_table(2, "Meek Minion", "creatures")
	token_like.set_card_rotation(90)
	await put_in_hand(1, "Smite")
	await fill_mana(1)
	go_to_main()
	var profile := _profile()
	var plan := MainPhase.plan_plays(game, Snapshot.for_profile(game, 1, profile), profile)
	var names: Array = plan.plays.map(func(c): return c.canonical_name)
	assert_false("Smite" in names, "a 1/1 is not worth a Smite")


func test_smite_goes_for_the_blocker_that_stops_the_attack() -> void:
	await _fresh(["Order"], ["Primal"])
	await put_on_table(1, "Moral Captain", "creatures")
	await put_on_table(1, "Tactical Combatant", "creatures")
	var wall := await put_on_table(2, "Wraithful Treespirits", "creatures")
	wall.set_card_rotation(90)
	await put_in_hand(1, "Smite")
	await fill_mana(1)
	go_to_main()
	var profile := _profile()
	var plan := MainPhase.plan_plays(game, Snapshot.for_profile(game, 1, profile), profile)
	var names: Array = plan.plays.map(func(c): return c.canonical_name)
	assert_true("Smite" in names, "a 4/4 guard is worth a Smite: %s" % str(names))


func test_mana_is_only_held_for_reactions_the_ai_can_cast() -> void:
	await _fresh(["Chaos"], ["Order"])
	await put_creature(2, 3, 3)
	var agent := await put_in_hand(1, "Double Agent")
	go_to_main()
	var profile := _profile("normal", ["Chaos"])
	var state := Snapshot.for_profile(game, 1, profile)
	assert_gt(Reactions.hold_value(state, profile, agent), 0.0, "Double Agent is modelled now")
	var hold_the_line := await put_in_hand(1, "Hold the Line")
	assert_gt(Reactions.hold_value(state, profile, hold_the_line), 0.0)
	assert_true("Double Agent" in Reactions.MODELLED)
