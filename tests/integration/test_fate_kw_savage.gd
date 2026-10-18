extends "res://tests/FateCommon.gd"
# Tests of the Savage X keyword (src/custom/fate/keywords/KwSavage.gd). Rules: docs/FATE_RULES_SPEC.md,
# Section 4. Player 1 attacks with the Savage creature, player 2 blocks with tilted (guarding)
# creatures. Savage damage is dealt when the blocks are confirmed, before combat damage.

const Savage := preload("res://src/custom/fate/keywords/KwSavage.gd")
const Phase := FateGame.Phase


func after_each():
	# The chooser is static (shared by the whole process): never leak it into another test
	Savage.target_chooser = Callable()


func _life(pid: int) -> int:
	return game.player(pid).life


# Declares `attacker -> target`, confirms, blocks with `blockers`, confirms the blocks (the rest
# of the combat resolves at once). Returns the attack.
func _blocked_attack(attacker: Card, target, blockers: Array) -> FateAttack:
	start_combat()
	assert_true(game.combat.declare_attack(attacker, target), "Test setup: attack allowed")
	var attack: FateAttack = game.combat.attack_of(attacker)
	game.combat.confirm_attackers()
	for b in blockers:
		assert_true(game.combat.declare_block(b, attack), "Test setup: block allowed: " + game.combat.last_error)
	game.combat.confirm_blocks()
	return attack


# --- the value X -----------------------------------------------------------------------------------

func test_savage_1_deals_1_damage_to_the_blocking_player():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), LIFE - 1)
	assert_eq(_life(1), LIFE - 1, "Only the attacker dying to Guard 9 costs its player a life, Savage does not")


func test_savage_2_deals_2_damage():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), LIFE - 2)


func test_the_real_cards_have_their_savage_values():
	var beetle := await put_creature(1, "Ironside Beetle")
	var beast := await put_creature(1, "Feracious Beast")
	assert_eq(game.keywords.value(beetle, "Savage"), 1)
	assert_eq(game.keywords.value(beast, "Savage"), 2)
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(beast, 2, [blocker])
	assert_eq(_life(2), LIFE - 2, "Feracious Beast: Savage 2")


func test_a_granted_savage_gives_the_creature_savage():
	var attacker := await put_creature(1, 3, 3)
	game.stats.grant_keyword(attacker, "Savage", 1, "end_of_turn")
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), LIFE - 1)


func test_granted_and_innate_values_add_up():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	game.stats.grant_keyword(attacker, "Savage", 1, "end_of_turn")
	assert_eq(game.keywords.value(attacker, "Savage"), 3)
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), LIFE - 3, "Savage 2 + granted Savage 1 = 3")


func test_two_grants_stack():
	var attacker := await put_creature(1, 3, 3)
	game.stats.grant_keyword(attacker, "Savage", 1, "end_of_turn")
	game.stats.grant_keyword(attacker, "Savage", 1, "end_of_turn")
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), LIFE - 2)


func test_a_creature_without_savage_deals_no_extra_damage():
	var attacker := await put_creature(1, 3, 3)
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), LIFE)


# --- when it triggers -------------------------------------------------------------------------------------

func test_it_does_not_trigger_when_the_attack_is_not_blocked():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	await put_creature(2, 1, 9, {}, true)
	var attack := _blocked_attack(attacker, 2, [])
	assert_eq(_life(2), LIFE - 1, "Only the attack's own damage")
	assert_false(attack.metadata.has("savage"))


func test_it_triggers_once_however_many_blockers():
	var attacker := await put_creature(1, 5, 5, {"Savage": 2})
	var b1 := await put_creature(2, 1, 9, {}, true)
	var b2 := await put_creature(2, 1, 9, {}, true)
	var b3 := await put_creature(2, 1, 9, {}, true)
	var hits := []
	game.damage_dealt.connect(func(_s, t, a, c): if c == "savage": hits.append([t, a]))
	var attack := _blocked_attack(attacker, 2, [b1, b2, b3])
	assert_eq(hits.size(), 1)
	assert_eq(_life(2), LIFE - 2, "2 once, not 2 per blocker")
	assert_eq(attack.metadata.savage.amount, 2)


func test_it_triggers_on_an_attack_against_a_creature_too():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	var target := await put_creature(2, 2, 9)
	var blocker := await put_creature(2, 1, 9, {}, true)
	_blocked_attack(attacker, target, [blocker])
	assert_eq(_life(2), LIFE - 1, "Savage hits the blocking player, whatever the attack targeted")


func test_it_does_not_trigger_for_a_negated_attack():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	start_combat()
	game.combat.declare_attack(attacker, 2)
	var attack: FateAttack = game.combat.attack_of(attacker)
	game.combat.confirm_attackers()
	game.combat.declare_block(blocker, attack)
	game.combat.negate_attack(attack)
	game.combat.confirm_blocks()
	assert_eq(_life(2), LIFE)
	assert_false(attack.metadata.has("savage"))


func test_it_does_not_trigger_for_an_attack_removed_from_combat_before_the_blocks_are_confirmed():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	start_combat()
	game.combat.declare_attack(attacker, 2)
	var attack: FateAttack = game.combat.attack_of(attacker)
	game.combat.confirm_attackers()
	game.combat.declare_block(blocker, attack)
	game.combat.remove_from_combat(attacker)
	game.combat.confirm_blocks()
	assert_eq(_life(2), LIFE)
	assert_false(attack.metadata.has("savage"))


func test_the_hook_itself_refuses_a_negated_or_removed_attack():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	start_combat()
	game.combat.declare_attack(attacker, 2)
	var attack: FateAttack = game.combat.attack_of(attacker)
	var kw: FateKeyword = game.keywords.get_keyword("Savage")
	attack.negated = true
	kw.on_blocked(attacker, attack, [blocker])
	assert_eq(_life(2), LIFE, "negated")
	attack.negated = false
	attack.removed = true
	kw.on_blocked(attacker, attack, [blocker])
	assert_eq(_life(2), LIFE, "removed")
	attack.removed = false
	kw.on_blocked(attacker, attack, [])
	assert_eq(_life(2), LIFE, "no blockers")
	kw.on_blocked(attacker, attack, [blocker])
	assert_eq(_life(2), LIFE - 2, "a live, blocked attack")
	kw.on_blocked(attacker, attack, [blocker])
	assert_eq(_life(2), LIFE - 2, "never twice for the same attack")


# --- ordering ---------------------------------------------------------------------------------------------------

func test_savage_damage_comes_before_combat_damage_and_before_the_intercept_window():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	var blocker := await put_creature(2, 1, 5, {}, true)
	var causes := []
	game.damage_dealt.connect(func(_s, _t, _a, c): causes.append(c))
	var life_at_window := []
	game.combat.reaction_window_requested.connect(func(w):
		if w.step == FateCombat.WINDOW_INTERCEPT_END:
			life_at_window.append(_life(2)))
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(causes[0], "savage", "Savage is the first damage")
	assert_true(causes.slice(1).all(func(c): return c == "combat") and causes.size() > 1,
			"then the combat damage")
	assert_eq(life_at_window, [LIFE - 1], "already dealt when the intercept reaction window opens")
	assert_eq(game.stats.damage_on(blocker, "Guard"), 3, "Combat damage still happens")


func test_an_unblocked_attack_deals_no_savage_before_resolving():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	await put_creature(2, 1, 5, {}, true)
	var causes := []
	game.damage_dealt.connect(func(_s, _t, _a, c): causes.append(c))
	_blocked_attack(attacker, 2, [])
	assert_eq(causes, ["combat"])


# --- choosing the target ----------------------------------------------------------------------------------------

func test_the_default_target_is_the_player_of_the_first_blocker():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var attack := _blocked_attack(attacker, 2, [blocker])
	assert_eq(attack.metadata.savage.target, game.player(2))


func test_a_chooser_can_pick_a_creature_which_loses_its_used_stat():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var bystander := await put_creature(2, 4, 4)
	Savage.target_chooser = func(_a, _atk, candidates, _n): return bystander
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(game.stats.current(bystander, "Strike"), 2, "Upright: Strike 4 - 2")
	assert_eq(game.stats.current(bystander, "Guard"), 4)
	assert_eq(_life(2), LIFE, "The player is not hit")


func test_savage_on_a_guarding_or_occupied_creature_lowers_its_guard():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var occupied := await put_creature(2, 1, 5, {}, false, "occupied")
	Savage.target_chooser = func(_a, _atk, _c, _n): return occupied
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(game.stats.current(occupied, "Guard"), 3)
	assert_eq(game.stats.current(occupied, "Strike"), 1)


func test_a_blocker_is_a_valid_target_too():
	var attacker := await put_creature(1, 1, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	Savage.target_chooser = func(_a, _atk, _c, _n): return blocker
	_blocked_attack(attacker, 2, [blocker])
	# 2 from Savage, plus 1 from the combat (the attacker's Strike 1)
	assert_eq(game.stats.damage_on(blocker, "Guard"), 3)


func test_the_chooser_gets_the_player_first_then_only_that_players_creatures():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var other := await put_creature(2, 2, 2)
	var mine := await put_creature(1, 2, 2)
	var seen := {}
	Savage.target_chooser = func(card, atk, candidates, amount):
		# merge, not assign: a lambda captures local variables by value
		seen.merge({"card": card, "attack": atk, "candidates": candidates.duplicate(), "amount": amount})
		return null
	var attack := _blocked_attack(attacker, 2, [blocker])
	assert_eq(seen.card, attacker)
	assert_eq(seen.attack, attack)
	assert_eq(seen.amount, 1)
	assert_eq(seen.candidates[0], game.player(2))
	assert_eq(seen.candidates.size(), 3)
	assert_true(blocker in seen.candidates)
	assert_true(other in seen.candidates)
	assert_false(mine in seen.candidates, "Not the attacker's creatures")
	assert_eq(_life(2), LIFE - 1, "A null answer falls back to the blocking player")


func test_an_answer_that_is_not_a_candidate_falls_back_to_the_blocking_player():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var mine := await put_creature(1, 2, 2)
	Savage.target_chooser = func(_a, _atk, _c, _n): return mine
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), LIFE - 1)
	assert_eq(game.stats.damage_on(mine, "Strike"), 0)


# --- creatures that die ---------------------------------------------------------------------------------------

func test_a_creature_above_zero_after_savage_survives():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var victim := await put_creature(2, 5, 2)
	Savage.target_chooser = func(_a, _atk, _c, _n): return victim
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(game.stats.current(victim, "Strike"), 3)
	assert_eq(FateZones.zone_of(victim), "creatures")


func test_savage_kills_a_creature_at_zero():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var victim := await put_creature(2, 2, 2)
	Savage.target_chooser = func(_a, _atk, _c, _n): return victim
	var destroyed := []
	game.creature_destroyed.connect(func(c, cause): destroyed.append([c, cause]))
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(victim.get_parent(), FateZones.container("discard", 2))
	assert_eq(destroyed[0], [victim, "savage"], "Savage destroyed it first (the blocker later dies in combat)")


func test_savage_cannot_destroy_what_would_be_destroyed_prevention_forbids():
	# Destruction goes through effects.destroy(): a keyword that says "no" keeps the creature
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var victim := await put_creature(2, 2, 2, {"Protected": 1})
	var protector = load("res://tests/FateTestKeyword.gd").make("Protected")
	protector.allow_destroy = false
	game.keywords.register(protector)
	Savage.target_chooser = func(_a, _atk, _c, _n): return victim
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(game.stats.current(victim, "Strike"), 0)
	assert_eq(FateZones.zone_of(victim), "creatures", "Still on the table")


func test_the_only_blocker_dies_to_savage_and_the_attack_still_resolves_without_errors():
	var attacker := await put_creature(1, 3, 3, {"Savage": 1})
	var blocker := await put_creature(2, 1, 1, {}, true)
	Savage.target_chooser = func(_a, _atk, _c, _n): return blocker
	var attack := _blocked_attack(attacker, 2, [blocker])
	assert_eq(blocker.get_parent(), FateZones.container("discard", 2), "Guard 1 - 1: destroyed")
	assert_true(attack.resolved)
	assert_eq(attack.result.kind, "blockers_gone", "It was blocked, so it does not reach the player")
	assert_eq(_life(2), LIFE)
	assert_eq(game.stats.damage_on(attacker, "Strike"), 0)
	assert_eq(game.phase, Phase.END)


func test_one_of_several_blockers_dies_and_the_others_still_fight():
	var attacker := await put_creature(1, 4, 3, {"Savage": 2})
	var weak := await put_creature(2, 1, 2, {}, true)
	var strong := await put_creature(2, 1, 3, {}, true)
	Savage.target_chooser = func(_a, _atk, _c, _n): return weak
	var attack := _blocked_attack(attacker, 2, [weak, strong])
	assert_eq(weak.get_parent(), FateZones.container("discard", 2), "Guard 2 - 2")
	assert_eq(attack.result.kind, "blocked")
	assert_eq(attack.result.blockers, [strong], "Only the survivor takes part in the damage")
	assert_eq(strong.get_parent(), FateZones.container("discard", 2), "Strike 4 against Guard 3")
	assert_eq(game.stats.current(attacker, "Strike"), 1, "The attacker lost only the survivor's 3")


# --- defeating a player ----------------------------------------------------------------------------------------

func test_savage_damage_can_defeat_the_blocking_player():
	var attacker := await put_creature(1, 3, 3, {"Savage": 2})
	var blocker := await put_creature(2, 1, 9, {}, true)
	game.player(2).life = 2
	var defeated := []
	game.player_defeated.connect(func(pid): defeated.append(pid))
	var attack := _blocked_attack(attacker, 2, [blocker])
	assert_eq(_life(2), 0)
	assert_true(game.is_over)
	assert_eq(game.winner_id, 1)
	assert_eq(defeated, [2])
	assert_eq(attack.metadata.savage.amount, 2)


func test_savage_is_stopped_by_a_keyword_that_reduces_damage():
	# modify_damage_taken applies to creatures hit by Savage like to any other damage
	var attacker := await put_creature(1, 3, 3, {"Savage": 3})
	var blocker := await put_creature(2, 1, 9, {}, true)
	var armored := await put_creature(2, 6, 2, {"Armor": 1})
	var armor = load("res://tests/FateTestKeyword.gd").make("Armor")
	armor.damage_reduction = 2
	game.keywords.register(armor)
	Savage.target_chooser = func(_a, _atk, _c, _n): return armored
	_blocked_attack(attacker, 2, [blocker])
	assert_eq(game.stats.current(armored, "Strike"), 5, "3 - 2 = 1 damage")
