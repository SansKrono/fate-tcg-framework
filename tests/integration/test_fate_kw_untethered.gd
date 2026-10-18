extends "res://tests/FateCommon.gd"
# Tests of the Untethered keyword (spec Section 4): a dying creature goes to its owner's removed
# pile instead of the discard pile. Player 1 attacks, player 2 defends.

const Phase := FateGame.Phase
const TestKeyword := preload("res://tests/FateTestKeyword.gd")
const UNTETHERED := {"Untethered": 1}


func _pile(zone: String, pid: int) -> Node:
	return FateZones.container(zone, pid)


func _count(zone: String, pid: int) -> int:
	return _pile(zone, pid).get_card_count()


# Declares and confirms one attack and the given block, ends in the END phase
func _fight(attacker: Card, target, blocker: Card = null) -> void:
	assert_true(game.combat.declare_attack(attacker, target), "Test setup: attack allowed")
	var attack: FateAttack = game.combat.attack_of(attacker)
	game.combat.confirm_attackers()
	if blocker != null:
		assert_true(game.combat.declare_block(blocker, attack), "Test setup: block allowed")
	game.combat.confirm_blocks()


func _assert_removed(card: Card, pid: int, removed_before: int, discard_before: int) -> void:
	assert_eq(card.get_parent(), _pile("removed", pid), "In the owner's removed pile")
	assert_eq(_count("removed", pid), removed_before + 1, "Removed pile count updated")
	assert_eq(_count("discard", pid), discard_before, "Discard pile untouched")
	assert_true(card.is_faceup, "Face-up")
	assert_eq(card.owner_id, pid, "Still owned by its owner")


# --- the real card ---------------------------------------------------------------------------------

func test_the_real_card_has_untethered_registered():
	assert_not_null(game.keywords.get_keyword("Untethered"))
	var card := await put_creature(1, "Wraithful Treespirits")
	assert_true(game.keywords.has(card, "Untethered"))
	var removed := _count("removed", 1)
	assert_true(game.effects.destroy(card, null, FateEffects.CAUSE_EFFECT))
	assert_eq(card.get_parent(), _pile("removed", 1))
	assert_eq(_count("removed", 1), removed + 1)


# --- death in combat -------------------------------------------------------------------------------------

func test_attacker_dying_in_combat_is_removed_from_the_game():
	var attacker := await put_creature(1, 1, 3, UNTETHERED)
	var target := await put_creature(2, 3, 5)
	var removed := _count("removed", 1)
	var discard := _count("discard", 1)
	start_combat()
	_fight(attacker, target)
	_assert_removed(attacker, 1, removed, discard)
	assert_true(FateZones.is_creature_in_play(target), "The target (Guard 5) survives")


func test_blocker_dying_in_combat_is_removed_from_the_game():
	var attacker := await put_creature(1, 4, 1)
	var blocker := await put_creature(2, 1, 1, UNTETHERED, true)
	var removed := _count("removed", 2)
	var discard := _count("discard", 2)
	start_combat()
	_fight(attacker, 2, blocker)
	_assert_removed(blocker, 2, removed, discard)
	assert_eq(game.player(2).life, LIFE, "The block worked")


func test_a_creature_without_untethered_still_goes_to_the_discard_pile():
	var victim := await put_creature(2, 1, 1)
	var removed := _count("removed", 2)
	var discard := _count("discard", 2)
	assert_true(game.effects.destroy(victim))
	assert_eq(victim.get_parent(), _pile("discard", 2))
	assert_eq(_count("discard", 2), discard + 1)
	assert_eq(_count("removed", 2), removed)


# --- non-combat deaths --------------------------------------------------------------------------------------

func test_dying_to_the_both_stats_zero_rule_is_removed():
	var card := await put_creature(2, 2, 2, UNTETHERED)
	var removed := _count("removed", 2)
	var discard := _count("discard", 2)
	game.effects.deal_damage(card, 2, null, FateEffects.CAUSE_EFFECT)
	assert_true(FateZones.is_creature_in_play(card), "Strike 0 but Guard 2: alive")
	game.effects.deal_damage(card, 2, null, FateEffects.CAUSE_EFFECT, "Guard")
	_assert_removed(card, 2, removed, discard)


func test_destroy_with_every_cause_removes_the_card():
	for cause in [FateEffects.CAUSE_COMBAT, FateEffects.CAUSE_EFFECT, FateEffects.CAUSE_STATS, "sacrifice"]:
		var card := await put_creature(1, 1, 1, UNTETHERED)
		var removed := _count("removed", 1)
		var discard := _count("discard", 1)
		assert_true(game.effects.destroy(card, null, cause), cause)
		_assert_removed(card, 1, removed, discard)


func test_the_owner_decides_not_the_destroyer():
	# Player 1's spell destroys player 2's Untethered creature: it goes to player 2's removed pile
	var mine := await put_creature(1, 1, 1)
	var theirs := await put_creature(2, 2, 2, UNTETHERED)
	var removed1 := _count("removed", 1)
	var removed2 := _count("removed", 2)
	var discard2 := _count("discard", 2)
	assert_true(game.effects.destroy(theirs, mine, FateEffects.CAUSE_EFFECT))
	_assert_removed(theirs, 2, removed2, discard2)
	assert_eq(_count("removed", 1), removed1, "Not the destroyer's pile")


func test_a_creature_that_took_control_is_still_removed_to_its_owners_pile():
	var card := await put_creature(2, 2, 2, UNTETHERED)
	card.controller_id = 1
	var removed2 := _count("removed", 2)
	var removed1 := _count("removed", 1)
	game.effects.destroy(card)
	assert_eq(card.get_parent(), _pile("removed", 2), "Owner 2's pile")
	assert_eq(_count("removed", 2), removed2 + 1)
	assert_eq(_count("removed", 1), removed1)


# --- what a death does --------------------------------------------------------------------------------------

func test_slot_is_freed_stats_cleared_and_destruction_events_fire_once():
	var kw: FateKeyword = TestKeyword.make("Watcher")
	game.keywords.register(kw)
	var card := await put_creature(1, 3, 3, {"Untethered": 1, "Watcher": 1})
	var slot: BoardPlacementSlot = card._placement_slot
	assert_not_null(slot)
	game.stats.add_modifier(card, "Strike", 2, "permanent")
	game.stats.apply_damage(card, "Guard", 1)
	var events := []
	game.creature_destroyed.connect(func(c, cause): events.append([c, cause]))
	game.effects.destroy(card, null, FateEffects.CAUSE_EFFECT)
	assert_eq(card.get_parent(), _pile("removed", 1))
	assert_null(slot.occupying_card, "Slot freed")
	assert_eq(events.size(), 1, "creature_destroyed fired once")
	assert_eq(events[0], [card, FateEffects.CAUSE_EFFECT])
	assert_eq(kw.hooks_called("on_destroyed").size(), 1, "on_destroyed of another keyword ran once")
	assert_eq(game.stats.damage_on(card, "Guard"), 0, "Damage forgotten")
	assert_eq(game.stats.modifier_total(card, "Strike"), 0, "Modifiers forgotten")
	assert_eq(game.stats.current(card, "Strike"), 3, "Base stats shown")
	assert_eq(card.card_rotation, 0)
	# The slot is free for the next creature
	var next := await put_creature(1, 1, 1)
	assert_eq(next._placement_slot, slot, "The freed slot is reused")


func test_a_prevented_destruction_keeps_the_card_on_the_table():
	var kw: FateKeyword = TestKeyword.make("Shield")
	kw.allow_destroy = false
	game.keywords.register(kw)
	var card := await put_creature(1, 1, 1, {"Untethered": 1, "Shield": 1})
	var removed := _count("removed", 1)
	assert_false(game.effects.destroy(card))
	assert_true(FateZones.is_creature_in_play(card))
	assert_eq(_count("removed", 1), removed)


# --- granted Untethered ----------------------------------------------------------------------------------------

func test_granted_untethered_applies_while_present_and_not_after_it_expires():
	var a := await put_creature(1, 1, 1)
	var b := await put_creature(1, 1, 1)
	game.stats.grant_keyword(a, "Untethered", 1, "end_of_turn")
	game.stats.grant_keyword(b, "Untethered", 1, "end_of_turn")
	game.stats.expire("end_of_turn", b)
	assert_false(game.keywords.has(b, "Untethered"), "Test setup: b's grant expired")
	var removed := _count("removed", 1)
	var discard := _count("discard", 1)
	game.effects.destroy(a)
	assert_eq(a.get_parent(), _pile("removed", 1), "Granted: removed")
	game.effects.destroy(b)
	assert_eq(b.get_parent(), _pile("discard", 1), "Expired: discard")
	assert_eq(_count("removed", 1), removed + 1)
	assert_eq(_count("discard", 1), discard + 1)


func test_granted_untethered_ends_with_the_turn():
	var card := await put_creature(1, 1, 1)
	game.stats.grant_keyword(card, "Untethered", 1, "end_of_turn")
	assert_true(game.keywords.has(card, "Untethered"))
	game.stats.expire("end_of_turn")
	assert_false(game.keywords.has(card, "Untethered"))
	game.effects.destroy(card)
	assert_eq(card.get_parent(), _pile("discard", 1))


# --- priority -------------------------------------------------------------------------------------------------------

func test_untethered_wins_against_a_keyword_wanting_another_destination():
	var kw: FateKeyword = TestKeyword.make("Returner", 0)
	kw.destination = "hand"
	game.keywords.register(kw)
	var card := await put_creature(1, 1, 1, {"Untethered": 1, "Returner": 1})
	var removed := _count("removed", 1)
	var hand := _count("hand", 1)
	game.effects.destroy(card)
	assert_eq(card.get_parent(), _pile("removed", 1), "Untethered (priority -100) answers first")
	assert_eq(_count("removed", 1), removed + 1)
	assert_eq(_count("hand", 1), hand)
	assert_eq(kw.hooks_called("death_destination").size(), 0, "The registry stopped at the first answer")
	assert_eq(kw.hooks_called("on_destroyed").size(), 1, "...but its on_destroyed still ran")


func test_a_keyword_with_an_even_lower_priority_can_override_it():
	var kw: FateKeyword = TestKeyword.make("Override", -200)
	kw.destination = "deck"
	game.keywords.register(kw)
	var card := await put_creature(1, 1, 1, {"Untethered": 1, "Override": 1})
	var deck := _count("deck", 1)
	game.effects.destroy(card)
	assert_eq(card.get_parent(), _pile("deck", 1))
	assert_eq(_count("deck", 1), deck + 1)


func test_a_keyword_with_no_opinion_does_not_block_untethered():
	var kw: FateKeyword = TestKeyword.make("Quiet", -300)
	game.keywords.register(kw)
	var card := await put_creature(1, 1, 1, {"Untethered": 1, "Quiet": 1})
	game.effects.destroy(card)
	assert_eq(card.get_parent(), _pile("removed", 1))


# --- with Indomitable (test keyword, or the real one if it exists) -------------------------------------------------------

func test_untethered_and_indomitable_survives_combat_damage_and_is_not_removed():
	if game.keywords.get_keyword("Indomitable") == null:
		var hold: FateKeyword = TestKeyword.make("Indomitable")
		hold.hold_at_one = true
		game.keywords.register(hold)
	var attacker := await put_creature(1, 5, 1)
	var defender := await put_creature(2, 2, 2, {"Untethered": 1, "Indomitable": 1})
	var removed := _count("removed", 2)
	var discard := _count("discard", 2)
	start_combat()
	_fight(attacker, defender)
	assert_true(FateZones.is_creature_in_play(defender), "Held at 1")
	assert_eq(game.stats.current(defender, "Strike"), 1)
	assert_eq(_count("removed", 2), removed)
	assert_eq(_count("discard", 2), discard)


func test_the_ordinary_untethered_creature_dies_to_the_same_attack():
	var attacker := await put_creature(1, 5, 1)
	var defender := await put_creature(2, 2, 2, UNTETHERED)
	var removed := _count("removed", 2)
	var discard := _count("discard", 2)
	start_combat()
	_fight(attacker, defender)
	_assert_removed(defender, 2, removed, discard)
