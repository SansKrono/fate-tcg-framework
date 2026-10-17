extends "res://tests/FateCommon.gd"
# Tests of the reaction subsystem (FateReactions, game.reactions): casting reaction spells in the
# reaction windows of combat. Rules: docs/FATE_RULES_SPEC.md, Section 4 and decision D8.
# Player 1 attacks, player 2 defends and holds the reaction spells. Every spell costs 2 generic
# (Wave of Fear 3); `_arm()` gives player 2 4 mana. The manager only holds a window while the
# defender has something castable, and holds are off in the tests by default, so before_each turns
# them on.

const Phase := FateGame.Phase

var combat: FateCombat
var reactions


func before_each():
	await super.before_each()
	combat = game.combat
	reactions = game.reactions
	reactions.hold_windows = true


func _discard(pid: int) -> Node:
	return FateZones.container("discard", pid)


func _mana(pid: int) -> int:
	return total_mana(game.mana_pool(pid))


# Gives player 2 exactly these cards in hand and `mana` energy (a multiple of 2). Returns the cards
func _arm(card_names: Array, mana := 4) -> Array:
	await empty_hand(2)
	var cards := []
	for n in card_names:
		cards.append(await put_in_hand(2, n))
	await fill_mana(2, mana / 2)
	return cards


# Starts combat, declares the attacks ([attacker, target] pairs) and confirms them: the declare_end
# window opens. Returns the attacks. If player 2 has a castable reaction the window is held.
func _declare(declares: Array) -> Array:
	start_combat()
	var made := []
	for d in declares:
		assert_true(combat.declare_attack(d[0], d[1]), "Test setup: attack allowed: " + combat.last_error)
		made.append(combat.attack_of(d[0]))
	combat.confirm_attackers()
	return made


# Passes the open window (what the Next phase button does)
func _next() -> void:
	game.request_next_phase()


# --- the manager ------------------------------------------------------------------------------------------

func test_every_reaction_effect_script_is_registered():
	for n in ["Factory Shutdown", "Safety Measure", "Hold the Line", "Forests Protection", "Wave of Fear"]:
		assert_not_null(reactions.effect_of(n), n)
	assert_null(reactions.effect_of("Double Agent"), "Out of scope: needs take-control")
	assert_eq(reactions.script_file_name("ReactWaveOfFear.gd.remap"), "ReactWaveOfFear.gd")
	assert_eq(reactions.script_file_name("FateReactionEffect.gd"), "", "The base class is not an effect")


func test_a_window_with_nothing_castable_continues_at_once():
	await _arm(["Factory Shutdown"], 0)
	var attacker := await put_creature(1, 2, 1)
	var made := _declare([[attacker, 2]])
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT, "No mana: the declare window did not wait")
	assert_null(combat.current_window)
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)
	assert_true(made[0].resolved)
	assert_eq(game.player(2).life, 18)


func test_a_window_without_any_reaction_in_hand_continues_at_once():
	await _arm([])
	var attacker := await put_creature(1, 2, 1)
	_declare([[attacker, 2]])
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)


func test_a_castable_reaction_holds_the_window_until_the_player_passes():
	await _arm(["Factory Shutdown"])
	var attacker := await put_creature(1, 2, 1)
	_declare([[attacker, 2]])
	assert_eq(game.phase, Phase.COMBAT_DECLARE, "Waiting for the defender")
	assert_not_null(combat.current_window)
	assert_eq(combat.current_window.step, "declare_end")
	assert_eq(combat.current_window.player_id, 2)
	_next()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT, "Passed: combat goes on")
	assert_eq(game.player(2).life, 20, "(still to resolve)")
	# The intercept_end window opens too
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	assert_eq(combat.current_window.step, "intercept_end")
	_next()
	assert_eq(game.phase, Phase.END)
	assert_eq(game.player(2).life, 18, "Nothing was cast: the attack hit")


func test_holding_is_off_by_default_while_tests_run():
	var fresh = load("res://src/custom/fate/FateReactions.gd").new(game)
	assert_false(fresh.hold_windows, "cfc.is_testing is on")
	fresh.attach(null)


func test_cast_works_in_a_window_somebody_else_holds():
	reactions.hold_windows = false
	var cards := await _arm(["Factory Shutdown"])
	var attacker := await put_creature(1, 2, 1)
	var held := {}
	combat.reaction_window_requested.connect(func(w):
		if w.step == "declare_end":
			held["window"] = w
			held["token"] = w.hold())
	var made := _declare([[attacker, 2]])
	assert_eq(game.phase, Phase.COMBAT_DECLARE)
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_true(made[0].negated)
	assert_eq(game.phase, Phase.COMBAT_DECLARE, "The cast did not release the other handler's hold")
	held.window.release(held.token)
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT, "A held window completes after the reaction")
	combat.confirm_blocks()
	assert_eq(game.player(2).life, 20)


# --- Factory Shutdown --------------------------------------------------------------------------------------

func test_factory_shutdown_negates_every_attack_on_the_player_and_their_creatures():
	var cards := await _arm(["Factory Shutdown"])
	var a1 := await put_creature(1, 3, 1)
	var a2 := await put_creature(1, 3, 3)
	var defender := await put_creature(2, 2, 2)
	var made := _declare([[a1, 2], [a2, defender]])
	assert_true(reactions.can_cast(cards[0]))
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_true(made[0].negated and made[1].negated)
	assert_eq(cards[0].get_parent(), _discard(2), "The spell goes to its owner's discard pile")
	assert_eq(_mana(2), 2, "Paid 2 of 4")
	_next()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)
	assert_eq(game.player(2).life, 20, "Negated: no damage")
	assert_true(FateZones.is_creature_in_play(defender))
	assert_eq(game.stats.current(defender, "Strike"), 2)
	assert_eq(made[0].result.kind, "negated")
	assert_eq(made[1].result.kind, "negated")


func test_factory_shutdown_in_the_intercept_window_negates_a_blocked_attack():
	var cards := await _arm(["Factory Shutdown"])
	var attacker := await put_creature(1, 5, 1)
	var blocker := await put_creature(2, 1, 2, {}, true)
	var made := _declare([[attacker, 2]])
	_next()
	assert_true(combat.declare_block(blocker, made[0]))
	combat.confirm_blocks()
	assert_eq(combat.current_window.step, "intercept_end")
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_true(made[0].negated)
	_next()
	assert_eq(game.phase, Phase.END)
	assert_eq(game.stats.current(blocker, "Guard"), 2, "The negated attack dealt nothing")
	assert_eq(game.stats.current(attacker, "Strike"), 5)
	assert_eq(game.player(2).life, 20)


func test_factory_shutdown_needs_an_attack_on_the_caster():
	var cards := await _arm(["Factory Shutdown"])
	start_combat()
	var attacks := []
	combat.reaction_window_requested.connect(func(w): attacks.append(reactions.cast_problem(cards[0])))
	combat.confirm_attackers()
	assert_true(attacks[0].begins_with("No attack to negate"), attacks[0])
	assert_eq(cards[0].get_parent(), FateZones.container("hand", 2))


# --- Safety Measure ----------------------------------------------------------------------------------------

func test_safety_measure_destroys_the_attacker_with_the_highest_strike_by_default():
	var cards := await _arm(["Safety Measure"])
	var weak := await put_creature(1, 2, 2)
	var strong := await put_creature(1, 4, 1)
	var made := _declare([[weak, 2], [strong, 2]])
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_eq(strong.get_parent(), _discard(1), "Strike 4 destroyed")
	assert_true(made[1].removed, "Its attack left combat")
	assert_true(FateZones.is_creature_in_play(weak))
	assert_eq(cards[0].get_parent(), _discard(2))
	assert_eq(_mana(2), 2)
	_next()
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END, "Nothing castable is left: the intercept window did not wait")
	assert_eq(game.player(2).life, 18, "Only the weak attacker hit")


func test_safety_measure_ties_go_to_the_first_declared_attacker_and_uses_current_strike():
	var cards := await _arm(["Safety Measure"])
	var first := await put_creature(1, 3, 1)
	var second := await put_creature(1, 3, 1)
	var third := await put_creature(1, 2, 1)
	game.stats.add_modifier(third, "Strike", 1, "end_of_turn")
	_declare([[third, 2], [second, 2], [first, 2]])
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_eq(third.get_parent(), _discard(1), "Current Strike 3 (2 + 1), declared first")
	assert_true(FateZones.is_creature_in_play(first) and FateZones.is_creature_in_play(second))


func test_safety_measure_with_an_explicit_target_and_a_chooser():
	var cards := await _arm(["Safety Measure", "Safety Measure"], 4)
	var a := await put_creature(1, 4, 1)
	var b := await put_creature(1, 1, 1)
	var c := await put_creature(1, 2, 1)
	_declare([[a, 2], [b, 2], [c, 2]])
	assert_true(reactions.cast(cards[0], b), "The explicit target wins")
	assert_eq(b.get_parent(), _discard(1))
	assert_true(FateZones.is_creature_in_play(a))
	var asked := []
	reactions.chooser = func(card, candidates):
		asked.append([card, candidates.duplicate()])
		return c
	assert_true(reactions.cast(cards[1]), reactions.last_error)
	assert_eq(asked.size(), 1)
	assert_eq(asked[0][0], cards[1])
	assert_eq(asked[0][1], [a, c], "The candidates: the attackers still attacking, in declaration order")
	assert_eq(c.get_parent(), _discard(1), "The chooser's pick")
	assert_true(FateZones.is_creature_in_play(a))


func test_safety_measure_refuses_a_target_that_is_not_an_attacker():
	var cards := await _arm(["Safety Measure"])
	var attacker := await put_creature(1, 2, 1)
	var idle := await put_creature(1, 5, 5)
	var own := await put_creature(2, 1, 1)
	_declare([[attacker, 2]])
	for bad in [idle, own]:
		assert_false(reactions.cast(cards[0], bad), "Not an attacking creature of an opponent")
		assert_ne(reactions.last_error, "")
	assert_eq(_mana(2), 4, "Nothing paid")
	assert_eq(cards[0].get_parent(), FateZones.container("hand", 2))
	assert_true(reactions.cast(cards[0], attacker), reactions.last_error)


func test_safety_measure_in_the_intercept_window_kills_a_blocked_attacker():
	var cards := await _arm(["Safety Measure"])
	var attacker := await put_creature(1, 5, 1)
	var blocker := await put_creature(2, 1, 3, {}, true)
	var made := _declare([[attacker, 2]])
	_next()
	combat.declare_block(blocker, made[0])
	combat.confirm_blocks()
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_eq(attacker.get_parent(), _discard(1))
	_next()
	assert_eq(game.stats.current(blocker, "Guard"), 3, "The blocker is untouched")
	assert_eq(game.phase, Phase.END)


# --- Hold the Line --------------------------------------------------------------------------------------------

func test_hold_the_line_switches_all_upright_creatures_to_guard_with_plus_one_guard():
	var cards := await _arm(["Hold the Line"])
	var attacker := await put_creature(1, 2, 1)
	var c1 := await put_creature(2, 2, 2)
	var c2 := await put_creature(2, 2, 3)
	var guard := await put_creature(2, 1, 4, {}, true)
	var occupied := await put_creature(2, 1, 1, {}, false, "occupied")
	var made := _declare([[attacker, 2]])
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_eq(c1.card_rotation, 90)
	assert_eq(c2.card_rotation, 90)
	assert_eq(game.stats.current(c1, "Guard"), 3)
	assert_eq(game.stats.current(c2, "Guard"), 4)
	assert_eq(game.stats.current(guard, "Guard"), 4, "Already guarding: not switched, no bonus")
	assert_eq(game.stats.current(occupied, "Guard"), 1, "Occupied creatures are not in the creature zone")
	assert_eq(cards[0].get_parent(), _discard(2))
	assert_eq(_mana(2), 2)
	_next()
	# The switched creatures can block now
	assert_true(combat.declare_block(c1, made[0]), combat.last_error)
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)
	assert_eq(game.player(2).life, 20, "Blocked")
	# (the +1 ended with the END phase, so look at the damage: without it Guard 2 would be dead)
	assert_true(FateZones.is_creature_in_play(c1), "Strike 2 against Guard 2 + 1: it survived")
	assert_eq(game.stats.damage_on(c1, "Guard"), 2)
	assert_eq(attacker.get_parent(), _discard(1), "The attacker's Strike reached 0")


func test_hold_the_line_bonus_lasts_until_the_end_of_turn():
	var cards := await _arm(["Hold the Line"])
	var attacker := await put_creature(1, 1, 1)
	var c1 := await put_creature(2, 2, 2)
	_declare([[attacker, 2]])
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_eq(game.stats.current(c1, "Guard"), 3)
	_next()
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)
	game.end_turn()
	assert_eq(game.stats.current(c1, "Guard"), 2, "+1 Guard ended with the turn")


func test_hold_the_line_with_a_chosen_subset():
	var cards := await _arm(["Hold the Line"])
	var attacker := await put_creature(1, 1, 1)
	var c1 := await put_creature(2, 2, 2)
	var c2 := await put_creature(2, 2, 2)
	_declare([[attacker, c1]])
	assert_false(reactions.cast(cards[0], [attacker]), "Not the caster's creature")
	reactions.chooser = func(_card, candidates):
		assert_eq(candidates, [c1, c2])
		return [c2]
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_eq(c1.card_rotation, 0)
	assert_eq(c2.card_rotation, 90)
	assert_eq(game.stats.current(c1, "Guard"), 2)
	assert_eq(game.stats.current(c2, "Guard"), 3)


func test_hold_the_line_only_works_before_the_blockers():
	# Factory Shutdown is castable in the second window, which keeps it held
	var cards := await _arm(["Hold the Line", "Factory Shutdown"])
	var attacker := await put_creature(1, 1, 1)
	await put_creature(2, 2, 2)
	_declare([[attacker, 2]])
	_next()
	combat.confirm_blocks()
	assert_eq(combat.current_window.step, "intercept_end")
	assert_eq(reactions.cast_problem(cards[0]), "Hold the Line can only be cast at: declare_end")
	assert_false(reactions.cast(cards[0]))


func test_hold_the_line_needs_an_attack_and_with_a_window_without_attacks_nothing_holds():
	var cards := await _arm(["Hold the Line", "Wave of Fear", "Safety Measure", "Forests Protection"])
	await put_creature(2, 2, 2)
	start_combat()
	var problems := []
	combat.reaction_window_requested.connect(func(_w):
		for card in cards:
			problems.append(reactions.cast_problem(card)))
	combat.confirm_attackers()
	assert_eq(game.phase, Phase.END, "No attacks: no steps, nothing held")
	assert_eq(problems.size(), 4)
	for p in problems:
		assert_ne(p, "", "Nothing attacks, so nothing can be cast")
	assert_eq(problems[0], "Nothing attacks your field")


# --- Forests Protection ----------------------------------------------------------------------------------------

func test_forests_protection_grants_indomitable_until_end_of_turn():
	var cards := await _arm(["Forests Protection"])
	var attacker := await put_creature(1, 5, 1)
	var c1 := await put_creature(2, 1, 1)
	var occupied := await put_creature(2, 1, 1, {}, false, "occupied")
	_declare([[attacker, c1]])
	assert_false(game.keywords.has(c1, "Indomitable"))
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_true(game.keywords.has(c1, "Indomitable"))
	assert_true(game.keywords.has(occupied, "Indomitable"), "All the caster's creatures")
	assert_false(game.keywords.has(attacker, "Indomitable"), "Not the attacker's")
	assert_eq(cards[0].get_parent(), _discard(2))
	assert_eq(_mana(2), 2)
	_next()
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)
	if game.keywords.get_keyword("Indomitable") != null:
		assert_true(FateZones.is_creature_in_play(c1), "Indomitable: combat damage cannot kill it")
	game.end_turn()
	assert_false(game.keywords.has(c1, "Indomitable"), "Until end of turn")


func test_forests_protection_needs_an_attack_on_the_field():
	var cards := await _arm(["Forests Protection"])
	await put_creature(2, 1, 1)
	start_combat()
	var problems := []
	combat.reaction_window_requested.connect(func(_w): problems.append(reactions.cast_problem(cards[0])))
	combat.confirm_attackers()
	assert_eq(problems, ["Nothing attacks your field"])


# --- Wave of Fear -------------------------------------------------------------------------------------------------

func test_wave_of_fear_removes_all_attackers_by_default():
	var cards := await _arm(["Wave of Fear"])
	var a1 := await put_creature(1, 3, 1)
	var a2 := await put_creature(1, 2, 1)
	var made := _declare([[a1, 2], [a2, 2]])
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_true(made[0].removed and made[1].removed)
	assert_true(FateZones.is_creature_in_play(a1) and FateZones.is_creature_in_play(a2), "Still in play")
	assert_eq(cards[0].get_parent(), _discard(2))
	assert_eq(_mana(2), 1, "Paid 3 of 4")
	_next()
	assert_eq(game.phase, Phase.END, "Nothing left to intercept or resolve")
	assert_eq(game.player(2).life, 20)


func test_wave_of_fear_with_chosen_attackers():
	var cards := await _arm(["Wave of Fear"])
	var a1 := await put_creature(1, 3, 1)
	var a2 := await put_creature(1, 2, 1)
	var made := _declare([[a1, 2], [a2, 2]])
	assert_false(reactions.cast(cards[0], []), "Pick at least one")
	assert_false(reactions.cast(cards[0], [await put_creature(2, 1, 1)]), "Not an attacker")
	assert_true(reactions.cast(cards[0], [a2]), reactions.last_error)
	assert_false(made[0].removed)
	assert_true(made[1].removed)
	_next()
	combat.confirm_blocks()
	assert_eq(game.player(2).life, 17, "Only the first attacker hit")


func test_wave_of_fear_with_a_chooser_and_in_the_intercept_window():
	var cards := await _arm(["Wave of Fear"])
	var a1 := await put_creature(1, 3, 1)
	var a2 := await put_creature(1, 2, 1)
	var blocker := await put_creature(2, 1, 5, {}, true)
	var made := _declare([[a1, 2], [a2, 2]])
	_next()
	combat.declare_block(blocker, made[0])
	combat.confirm_blocks()
	reactions.chooser = func(_card, candidates): return [candidates[0]]
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_true(made[0].removed, "The chooser picked the first attacker")
	assert_true(made[0].blockers.is_empty())
	_next()
	assert_eq(game.stats.current(blocker, "Guard"), 5, "The removed attack did not hurt the blocker")
	assert_eq(game.player(2).life, 18, "The second attacker hit")


# --- can_cast reasons -------------------------------------------------------------------------------------------------

func test_can_cast_explains_why_not():
	var cards := await _arm(["Factory Shutdown", "Double Agent", "Rapid Scavenging"], 4)
	var mine := await put_in_hand(1, "Factory Shutdown")
	var attacker := await put_creature(1, 2, 1)
	assert_eq(reactions.cast_problem(cards[0]), "No reaction window is open", "Before combat")
	assert_false(reactions.can_cast(cards[0]))
	_declare([[attacker, 2]])
	assert_eq(reactions.cast_problem(cards[2]), "Not a reaction spell")
	assert_eq(reactions.cast_problem(attacker), "Not a reaction spell")
	assert_eq(reactions.cast_problem(mine), "It is not your reaction window (Player 2 reacts)")
	assert_eq(reactions.cast_problem(cards[1]), "Double Agent cannot be cast yet")
	assert_eq(reactions.cast_problem(cards[0]), "")
	assert_true(reactions.can_cast(cards[0]))
	assert_false(reactions.cast(mine), "The attacking player cannot react to their own attack")
	assert_eq(mine.get_parent(), FateZones.container("hand", 1))
	assert_true(reactions.cast(cards[0]))
	assert_eq(reactions.cast_problem(cards[0]), "The card is not in your hand", "Already cast")
	assert_false(reactions.cast(cards[0]), "Cannot be cast twice")
	assert_eq(reactions.last_error, "The card is not in your hand")


func test_not_enough_mana_is_a_reason_and_pays_nothing():
	var cards := await _arm(["Wave of Fear"], 2)
	var attacker := await put_creature(1, 2, 1)
	_declare([[attacker, 2]])
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT, "Not castable (3 mana, only 2 available): not held")
	assert_eq(reactions.cast_problem(cards[0]), "No reaction window is open")
	assert_false(reactions.cast(cards[0]))
	assert_eq(_mana(2), 2)
	# With a window open (held by the test) the reason is the mana
	var hold := {}
	combat.reaction_window_requested.connect(func(w):
		hold["w"] = w
		hold["t"] = w.hold())
	combat.confirm_blocks()
	assert_eq(reactions.cast_problem(cards[0]), "Not enough mana")
	hold.w.release(hold.t)


func test_a_cast_pays_with_the_defenders_energy_and_leaves_the_attackers_alone():
	var cards := await _arm(["Factory Shutdown"])
	await fill_mana(1)
	var before := _mana(1)
	var attacker := await put_creature(1, 2, 1)
	_declare([[attacker, 2]])
	assert_true(reactions.cast(cards[0]))
	assert_eq(_mana(1), before, "Player 1's energy is untouched")
	assert_eq(_mana(2), 2)


# --- not in the main phase / outside windows ---------------------------------------------------------------------------------

func test_reaction_spells_cannot_be_cast_in_the_main_phase_or_outside_windows():
	var cards := await _arm(["Factory Shutdown"])
	var mine := await put_in_hand(1, "Factory Shutdown")
	await fill_mana(1)
	game.turn.end_phase_waits_for_player = true
	game.draw_extra_card()
	assert_eq(game.phase, Phase.MAIN)
	for card in [cards[0], mine]:
		assert_false(game.can_play_from_hand(card))
		assert_eq(reactions.cast_problem(card), "No reaction window is open")
		assert_false(reactions.cast(card))
	var before := _mana(1)
	mine.move_to(board)
	assert_eq(mine.get_parent(), FateZones.container("hand", 1), "D8: dragging it to the table is refused")
	assert_eq(_mana(1), before)
	assert_eq(_mana(2), 4)
	# The declare step before the attackers are confirmed is not a window either
	game.advance_phase()
	assert_eq(game.phase, Phase.COMBAT_DECLARE)
	assert_eq(reactions.cast_problem(mine), "No reaction window is open")
	# Nor is the resolve step
	combat.confirm_attackers()
	assert_eq(game.phase, Phase.END)
	assert_false(reactions.can_cast(cards[0]))


func test_the_window_is_closed_again_after_combat():
	var cards := await _arm(["Factory Shutdown"])
	var attacker := await put_creature(1, 2, 1)
	_declare([[attacker, 2]])
	_next()
	combat.confirm_blocks()
	_next()
	assert_eq(game.phase, Phase.END)
	assert_null(reactions.open_window())
	assert_false(reactions.window_open_for(2))
	assert_eq(reactions.cast_problem(cards[0]), "No reaction window is open")


# --- several reactions in one window ----------------------------------------------------------------------------------------

func test_several_reactions_in_one_window():
	var cards := await _arm(["Hold the Line", "Safety Measure"], 4)
	var a1 := await put_creature(1, 4, 1)
	var a2 := await put_creature(1, 1, 1)
	var c1 := await put_creature(2, 1, 1)
	var made := _declare([[a1, 2], [a2, c1]])
	assert_true(reactions.cast(cards[0]), reactions.last_error)
	assert_eq(game.phase, Phase.COMBAT_DECLARE, "The window stays open for further reactions")
	assert_true(reactions.window_open_for(2))
	assert_true(reactions.cast(cards[1]), reactions.last_error)
	assert_eq(a1.get_parent(), _discard(1))
	assert_eq(c1.card_rotation, 90)
	assert_eq(_mana(2), 0)
	assert_eq(game.phase, Phase.COMBAT_DECLARE, "Still the player's call")
	assert_eq(cards[0].get_parent(), _discard(2))
	assert_eq(cards[1].get_parent(), _discard(2))
	_next()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	assert_true(combat.declare_block(c1, made[1]), combat.last_error)
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)
	assert_true(FateZones.is_creature_in_play(c1), "Guard 1 + 1 against Strike 1: it survived")
	assert_eq(game.stats.damage_on(c1, "Guard"), 1)
	assert_eq(a2.get_parent(), _discard(1))


func test_reactions_in_both_windows_of_one_combat():
	var cards := await _arm(["Wave of Fear", "Hold the Line"], 6)
	var a1 := await put_creature(1, 3, 1)
	var a2 := await put_creature(1, 1, 1)
	var c1 := await put_creature(2, 1, 1)
	var made := _declare([[a1, 2], [a2, 2]])
	assert_true(reactions.cast(cards[1]), reactions.last_error)
	_next()
	assert_true(combat.declare_block(c1, made[0]), combat.last_error)
	combat.confirm_blocks()
	assert_eq(combat.current_window.step, "intercept_end")
	assert_true(reactions.cast(cards[0], [a1]), reactions.last_error)
	assert_true(made[0].removed)
	_next()
	assert_eq(game.phase, Phase.END)
	assert_eq(game.player(2).life, 19, "Only the Strike 1 attacker hit")
	assert_eq(game.stats.damage_on(c1, "Guard"), 0, "Untouched: its attacker was removed")


# --- the owner's turn is unharmed ----------------------------------------------------------------------------------------------------

func test_the_attackers_turn_state_is_unharmed_and_mana_comes_back_for_the_defender():
	var cards := await _arm(["Factory Shutdown"])
	var attacker := await put_creature(1, 3, 1)
	_declare([[attacker, 2]])
	var life_1 := game.player(1).life
	var hand_1: int = FateZones.container("hand", 1).get_all_cards().size()
	assert_true(reactions.cast(cards[0]))
	assert_eq(game.active_id, 1)
	assert_eq(game.phase, Phase.COMBAT_DECLARE)
	assert_eq(game.energy_choice, "draw", "The attacker's turn flags are as they were")
	assert_eq(game.player(1).life, life_1)
	assert_eq(FateZones.container("hand", 1).get_all_cards().size(), hand_1)
	assert_eq(attacker.card_rotation, 0)
	assert_eq(game.stats.current(attacker, "Strike"), 3)
	_next()
	combat.confirm_blocks()
	assert_eq(game.phase, Phase.END)
	game.end_turn()
	assert_eq(game.active_id, 2)
	assert_eq(_mana(2), 4, "The defender's maintenance untapped the energy they spent")


func test_ending_the_turn_during_a_held_window_clears_everything():
	var cards := await _arm(["Factory Shutdown"])
	var attacker := await put_creature(1, 3, 1)
	_declare([[attacker, 2]])
	assert_ne(cards[0].modulate, Color(1, 1, 1, 1))
	game.end_turn()
	assert_null(combat.current_window)
	assert_null(reactions.open_window())
	assert_eq(cards[0].modulate, Color(1, 1, 1, 1), "The mark is gone")
	assert_eq(reactions.cast_problem(cards[0]), "No reaction window is open")


# --- the hand marks and the double-click ------------------------------------------------------------------------------------------------

func test_castable_reaction_spells_are_marked_while_the_window_is_open():
	var cards := await _arm(["Factory Shutdown", "Wave of Fear", "Rapid Scavenging"], 4)
	var attacker := await put_creature(1, 2, 1)
	_declare([[attacker, 2]])
	var plain := Color(1, 1, 1, 1)
	assert_ne(cards[0].modulate, plain, "Castable: marked")
	assert_ne(cards[1].modulate, plain, "Castable: marked")
	assert_eq(cards[2].modulate, plain, "A regular spell is never marked")
	# Spending the mana unmarks what can no longer be paid
	assert_true(reactions.cast(cards[1]))
	assert_eq(cards[0].modulate, plain, "Wave of Fear cost 3: 1 mana left, Factory Shutdown costs 2")
	_next()
	assert_eq(cards[1].modulate, plain)


func test_double_clicking_a_reaction_spell_casts_it_during_a_window():
	var cards := await _arm(["Factory Shutdown"])
	var attacker := await put_creature(1, 2, 1)
	var made := _declare([[attacker, 2]])
	assert_eq(cards[0].get_state_exec(), "hand")
	await cards[0].execute_scripts()
	assert_true(made[0].negated, "Cast through the card's own double-click")
	assert_eq(cards[0].get_parent(), _discard(2))
	assert_eq(_mana(2), 2)


func test_double_clicking_a_reaction_spell_outside_a_window_does_not_cast_it():
	var cards := await _arm(["Factory Shutdown"])
	await cards[0].execute_scripts()
	assert_eq(cards[0].get_parent(), FateZones.container("hand", 2), "Not cast, not played as energy")
	assert_eq(_mana(2), 4)
