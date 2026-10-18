extends "res://tests/FateCommon.gd"
# Combat restrictions: Unblockable, Cannot block and the forced single blocker (keywords
# KwUnblockable, KwCannotBlock, KwForcedBlocker). Rules: docs/FATE_RULES_SPEC.md, Section 4.
# Player 1 attacks, player 2 defends; tilted creatures guard.

const Forced := preload("res://src/custom/fate/keywords/KwForcedBlocker.gd")

var combat: FateCombat
var forced  # the KwForcedBlocker instance (untyped: it has methods of its own)


func before_each():
	await super.before_each()
	combat = game.combat
	forced = game.keywords.get_keyword("Forced blocker")


func after_each():
	# the chooser is static: never leak a test's chooser into the next test
	Forced.chooser = Callable()


func _life(pid: int) -> int:
	return game.player(pid).life


# Declares an attack (no confirmation yet) and returns it
func _declare(attacker: Card, target) -> FateAttack:
	assert_true(combat.declare_attack(attacker, target), "Test setup: attack allowed")
	return combat.attack_of(attacker)


# Declares one attack and confirms the attackers: ends in the intercept step. Returns the attack.
func _to_intercept(attacker: Card, target) -> FateAttack:
	var attack := _declare(attacker, target)
	combat.confirm_attackers()
	assert_eq(game.phase, FateGame.Phase.COMBAT_INTERCEPT, "Test setup: intercept step")
	return attack


func _untapped(pid: int) -> int:
	return game.mana.untapped_energy(pid).size()


# Main phase with 6 mana for player 1
func _main_with_mana() -> void:
	go_to_main()
	await fill_mana(1)


# --- Unblockable ------------------------------------------------------------------------------------

func test_an_unblockable_attacker_cannot_be_blocked_but_a_normal_one_can():
	var ghost := await put_creature(1, 2, 1, {"Unblockable": 1})
	var plain := await put_creature(1, 2, 1)
	var guard := await put_creature(2, 1, 4, {}, true)
	start_combat()
	var a := _declare(ghost, 2)
	var b := _declare(plain, 2)
	combat.confirm_attackers()
	assert_eq(game.phase, FateGame.Phase.COMBAT_INTERCEPT)
	assert_false(combat.declare_block(guard, a), "Unblockable: refused")
	assert_ne(combat.last_error, "")
	assert_true(guard in combat.eligible_blockers(b), "A normal attacker can be blocked")
	assert_false(guard in combat.eligible_blockers(a))
	assert_true(combat.declare_block(guard, b), "The same guard blocks the normal one")


func test_an_unblockable_attacker_hits_the_player_with_no_intercept():
	var ghost := await put_creature(1, 3, 1, {"Unblockable": 1})
	var guard := await put_creature(2, 1, 4, {}, true)
	var occupied := await put_creature(2, 1, 4, {}, false, "occupied")
	start_combat()
	var attack := _to_intercept(ghost, 2)
	assert_false(combat.declare_block(guard, attack))
	assert_false(combat.declare_block(occupied, attack))
	combat.confirm_blocks()
	assert_eq(_life(2), LIFE - 3, "Strike 3 went straight to the life total")
	assert_true(attack.resolved)
	assert_eq(attack.result.kind, "player")
	assert_true(FateZones.is_creature_in_play(guard), "Nobody fought")


func test_an_unblockable_attacker_on_a_creature_is_never_blocked():
	var ghost := await put_creature(1, 3, 1, {"Unblockable": 1})
	var target := await put_creature(2, 1, 2)
	var guard := await put_creature(2, 1, 4, {}, true)
	start_combat()
	var attack := _to_intercept(ghost, target)
	assert_false(combat.declare_block(guard, attack))
	combat.confirm_blocks()
	assert_eq(attack.result.kind, "creature")
	assert_false(target in game.creatures_in_play(2), "Strike 3 against Strike 1: destroyed")


func test_unblockable_granted_until_end_of_turn():
	var attacker := await put_creature(1, 2, 1)
	var guard := await put_creature(2, 1, 4, {}, true)
	game.stats.grant_keyword(attacker, "Unblockable", 1, "end_of_turn")
	start_combat()
	var attack := _to_intercept(attacker, 2)
	assert_false(combat.declare_block(guard, attack), "Granted: cannot be blocked")
	combat.confirm_blocks()
	assert_eq(game.phase, FateGame.Phase.END)
	game.end_turn()
	assert_false(game.keywords.has(attacker, "Unblockable"), "The grant ended with the turn")


# --- Cannot block ----------------------------------------------------------------------------------------

func test_a_cannot_block_creature_in_guard_position_cannot_block():
	var attacker := await put_creature(1, 2, 2)
	var wall := await put_creature(2, 0, 5, {"Cannot block": 1}, true)
	var normal := await put_creature(2, 0, 5, {}, true)
	start_combat()
	var attack := _to_intercept(attacker, 2)
	assert_false(combat.declare_block(wall, attack))
	assert_false(wall in combat.eligible_blockers(attack))
	assert_true(normal in combat.eligible_blockers(attack), "A normal guard can")
	assert_true(combat.declare_block(normal, attack))


func test_an_occupied_cannot_block_creature_cannot_block_either():
	var attacker := await put_creature(1, 2, 2)
	var occupied := await put_creature(2, 0, 5, {"Cannot block": 1}, false, "occupied")
	var normal_occupied := await put_creature(2, 0, 5, {}, false, "occupied")
	start_combat()
	var attack := _to_intercept(attacker, 2)
	assert_false(combat.declare_block(occupied, attack))
	assert_true(combat.declare_block(normal_occupied, attack), "Occupied creatures do block (D5)")


func test_a_cannot_block_creature_can_still_be_attacked():
	var attacker := await put_creature(1, 3, 2)
	var wall := await put_creature(2, 1, 1, {"Cannot block": 1}, true)
	var occupied := await put_creature(2, 1, 1, {"Cannot block": 1}, false, "occupied")
	start_combat()
	assert_true(combat.declare_attack(attacker, wall), "Targeted while guarding")
	combat.cancel_attack(attacker)
	assert_true(combat.declare_attack(attacker, occupied), "Targeted while occupied")


func test_cannot_block_granted_for_a_turn_stops_a_guard_from_blocking():
	var attacker := await put_creature(1, 2, 2)
	var guard := await put_creature(2, 1, 4, {}, true)
	game.stats.grant_keyword(guard, "Cannot block", 1, "end_of_turn")
	start_combat()
	var attack := _to_intercept(attacker, 2)
	assert_false(combat.declare_block(guard, attack))


func test_specter_of_hate_is_unblockable_and_cannot_block():
	var specter := await put_creature(1, "Specter of Hate")
	var specter_guard := await put_creature(2, "Specter of Hate", 1, {}, true)
	var guard := await put_creature(2, 1, 4, {}, true)
	start_combat()
	var attack := _to_intercept(specter, 2)
	assert_false(combat.declare_block(guard, attack), "Unblockable")
	assert_false(combat.declare_block(specter_guard, attack), "(and its twin cannot block anyway)")
	assert_false(game.keywords.can_block(specter_guard, attack), "Cannot block")


# --- Forced single blocker: the ability -----------------------------------------------------------------------

func test_force_block_pays_two_and_records_the_target():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var t1 := await put_creature(2, 1, 2, {}, true)
	assert_eq(_untapped(1), 6)
	assert_true(forced.force_block(brawler, t1))
	assert_eq(_untapped(1), 4, "Paid 2")
	assert_eq(forced.forced_target(brawler), t1)


func test_force_block_is_denied_when_the_mana_cannot_be_paid():
	go_to_main()
	var brawler := await put_creature(1, "Beetle Brawler")
	var t1 := await put_creature(2, 1, 2, {}, true)
	assert_false(forced.force_block(brawler, t1), "No mana at all")
	await put_energy(1, _energy_card_of(game.player(1).domains[0]))
	assert_false(forced.force_block(brawler, t1), "1 mana is not enough")
	assert_eq(_untapped(1), 1, "Nothing was tapped")
	assert_null(forced.forced_target(brawler))


func test_force_block_is_denied_outside_the_main_phase():
	await fill_mana(1)
	var brawler := await put_creature(1, "Beetle Brawler")
	var t1 := await put_creature(2, 1, 2, {}, true)
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	assert_false(forced.force_block(brawler, t1), "Energy phase")
	go_to_main()
	game.advance_phase()
	assert_eq(game.phase, FateGame.Phase.COMBAT_DECLARE)
	assert_false(forced.force_block(brawler, t1), "Combat phase")
	assert_eq(_untapped(1), 6)


func test_force_block_needs_an_opposing_creature_and_the_ability_and_one_use():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var plain := await put_creature(1, 2, 2)
	var mine := await put_creature(1, 1, 1)
	var t1 := await put_creature(2, 1, 2, {}, true)
	assert_false(forced.force_block(brawler, mine), "Not an opposing creature")
	assert_false(forced.force_block(plain, t1), "A creature without the ability")
	assert_true(forced.force_block(brawler, t1))
	assert_false(forced.force_block(brawler, t1), "Once per turn")
	assert_eq(_untapped(1), 4, "Only paid once")


func test_the_ability_comes_from_the_text_or_from_the_keyword():
	await _main_with_mana()
	var ironside := await put_creature(1, "Ironside Beetle")
	var granted := await put_creature(1, 2, 2)
	var plain := await put_creature(1, 2, 2)
	var t1 := await put_creature(2, 1, 2, {}, true)
	assert_true(forced.has_ability(ironside), "Same forced-block ability")
	assert_true(forced.has_ability(await put_creature(1, "Beetle Brawler")))
	assert_false(forced.has_ability(plain))
	game.stats.grant_keyword(granted, "Forced blocker", 1, "end_of_turn")
	assert_true(forced.has_ability(granted))
	assert_true(forced.force_block(granted, t1))


# --- Forced single blocker: the action (hover button) ----------------------------------------------------------

func _action_ids(card: Card) -> Array:
	return game.actions.list(card).map(func(a): return a.id)


func test_the_action_shows_only_when_it_is_legal():
	var brawler := await put_creature(1, "Beetle Brawler")
	var t1 := await put_creature(2, 1, 2, {}, true)
	await fill_mana(1)
	assert_does_not_have(_action_ids(brawler), "force_block", "Energy phase")
	go_to_main()
	assert_has(_action_ids(brawler), "force_block")
	var action: Dictionary = game.actions.find(brawler, "force_block")
	assert_eq(action.label, "Force block (pay 2)")
	assert_does_not_have(_action_ids(await put_creature(1, 2, 2)), "force_block", "No ability")
	assert_does_not_have(_action_ids(t1), "force_block", "Not the controller's turn")
	assert_true(await game.actions.run(brawler, "force_block"))
	assert_does_not_have(_action_ids(brawler), "force_block", "Used already")
	game.advance_phase()
	assert_does_not_have(_action_ids(brawler), "force_block", "Combat phase")


func test_the_action_is_hidden_without_mana_or_without_an_opposing_creature():
	var brawler := await put_creature(1, "Beetle Brawler")
	go_to_main()
	assert_does_not_have(_action_ids(brawler), "force_block", "No opposing creature, no mana")
	await fill_mana(1)
	assert_does_not_have(_action_ids(brawler), "force_block", "No opposing creature")
	await put_creature(2, 1, 2, {}, true)
	assert_has(_action_ids(brawler), "force_block")
	for energy in game.mana.untapped_energy(1).slice(0, 5):
		energy.set_card_rotation(90)
	assert_eq(_untapped(1), 1)
	assert_does_not_have(_action_ids(brawler), "force_block", "Only 1 mana left")
	assert_false(await game.actions.run(brawler, "force_block"))


func test_the_action_picks_the_highest_guard_ties_by_node_order():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var low := await put_creature(2, 1, 1, {}, true)
	var high := await put_creature(2, 1, 3, {}, true)
	var high_too := await put_creature(2, 2, 3, {}, true)
	assert_true(await game.actions.run(brawler, "force_block"))
	assert_eq(forced.forced_target(brawler), high, "Guard 3 beats 1, first of the tie")
	assert_ne(forced.forced_target(brawler), low)
	assert_ne(forced.forced_target(brawler), high_too)
	assert_eq(_untapped(1), 4)


func test_a_chooser_can_name_the_target_and_cancel():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var low := await put_creature(2, 1, 1, {}, true)
	await put_creature(2, 1, 3, {}, true)
	Forced.chooser = func(_card, _candidates): return null
	assert_false(await game.actions.run(brawler, "force_block"), "Cancelled: nothing paid")
	assert_eq(_untapped(1), 6)
	Forced.chooser = func(_card, candidates): return candidates[0]
	assert_true(await game.actions.run(brawler, "force_block"))
	assert_eq(forced.forced_target(brawler), low)


# --- Forced single blocker: in combat --------------------------------------------------------------------------------

func test_only_the_named_creature_can_block_the_forced_attacker():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var named := await put_creature(2, 1, 2, {}, true)
	var other := await put_creature(2, 1, 5, {}, true)
	var other_occupied := await put_creature(2, 1, 5, {}, false, "occupied")
	assert_true(forced.force_block(brawler, named))
	start_combat()
	var attack := _to_intercept(brawler, 2)
	assert_eq(attack.restrictions.size(), 1)
	assert_false(combat.declare_block(other, attack), "Another guard is refused")
	assert_false(combat.declare_block(other_occupied, attack), "So is an occupied one")
	assert_eq(combat.eligible_blockers(attack), [named])
	assert_true(combat.declare_block(named, attack))
	combat.confirm_blocks()
	assert_eq(attack.result.kind, "blocked")


func test_an_unforced_attacker_is_not_restricted_and_another_attacker_is_not_either():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var plain := await put_creature(1, 2, 2)
	var named := await put_creature(2, 1, 2, {}, true)
	var other := await put_creature(2, 1, 5, {}, true)
	assert_true(forced.force_block(brawler, named))
	start_combat()
	var a := _declare(brawler, 2)
	var b := _declare(plain, 2)
	combat.confirm_attackers()
	assert_eq(a.restrictions.size(), 1)
	assert_true(b.restrictions.is_empty())
	assert_false(combat.declare_block(other, a))
	assert_true(combat.declare_block(other, b), "The restriction is only on the brawler's attack")


func test_nothing_forced_means_no_restriction():
	var brawler := await put_creature(1, "Beetle Brawler")
	var guard := await put_creature(2, 1, 5, {}, true)
	start_combat()
	var attack := _to_intercept(brawler, 2)
	assert_true(attack.restrictions.is_empty())
	assert_true(combat.declare_block(guard, attack))


func test_if_the_named_creature_is_gone_nobody_can_block():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var named := await put_creature(2, 1, 2, {}, true)
	var other := await put_creature(2, 1, 5, {}, true)
	assert_true(forced.force_block(brawler, named))
	game.effects.destroy(named, null, "effect")
	assert_null(forced.forced_target(brawler), "Nothing to point at any more")
	start_combat()
	var attack := _to_intercept(brawler, 2)
	assert_false(combat.declare_block(other, attack), "The named creature left: nobody may block")
	combat.confirm_blocks()
	assert_eq(_life(2), LIFE - 2, "Unblocked: Strike 2 hit the player")


func test_if_the_named_creature_leaves_after_the_declaration_nobody_can_block():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var named := await put_creature(2, 1, 2, {}, true)
	var other := await put_creature(2, 1, 5, {}, true)
	assert_true(forced.force_block(brawler, named))
	start_combat()
	assert_true(combat.declare_attack(brawler, 2))
	var attack := combat.attack_of(brawler)
	combat.confirm_attackers()
	game.effects.destroy(named, null, "effect")
	assert_false(combat.declare_block(other, attack))
	assert_eq(combat.eligible_blockers(attack), [])


func test_if_the_named_creature_cannot_block_nobody_can():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var named := await put_creature(2, 1, 2, {"Cannot block": 1}, true)
	var other := await put_creature(2, 1, 5, {}, true)
	assert_true(forced.force_block(brawler, named), "A creature that cannot block can still be named")
	start_combat()
	var attack := _to_intercept(brawler, 2)
	assert_false(combat.declare_block(named, attack), "It cannot block")
	assert_false(combat.declare_block(other, attack), "And the others may not")


func test_the_forced_attack_can_target_a_creature_too():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var target := await put_creature(2, 1, 1)
	var named := await put_creature(2, 1, 3, {}, true)
	var other := await put_creature(2, 1, 3, {}, true)
	assert_true(forced.force_block(brawler, named))
	start_combat()
	var attack := _to_intercept(brawler, target)
	assert_false(combat.declare_block(other, attack))
	assert_true(combat.declare_block(named, attack))


func test_the_forced_block_ends_with_the_turn():
	await _main_with_mana()
	var brawler := await put_creature(1, "Beetle Brawler")
	var named := await put_creature(2, 1, 2, {}, true)
	assert_true(forced.force_block(brawler, named))
	assert_eq(forced.forced_target(brawler), named)
	game.turn.end_phase_waits_for_player = false
	game.end_turn()
	assert_eq(game.active_id, 2)
	game.end_turn()
	assert_eq(game.active_id, 1, "Back to player 1")
	assert_null(forced.forced_target(brawler), "The restriction is gone")
	assert_false(brawler.has_meta(Forced.META_KEY))
	# it can be used again in the new turn
	await fill_mana(1)
	go_to_main()
	assert_has(_action_ids(brawler), "force_block")
