extends "res://tests/FateCommon.gd"
# Tests of the stats layer (FateStats) and of the destroy / deal_damage pipeline (FateEffects).
# Rules: docs/FATE_RULES_SPEC.md, Section 3 (damage lasts until the owner's next maintenance, D7).
# Creatures come from put_creature(pid, strike, guard): player 1 acts first (turn 1, ENERGY phase).

const TestKeyword := preload("res://tests/FateTestKeyword.gd")


func _label_text(card: Card, stat: String) -> String:
	return card.card_front.card_labels[stat].text


# --- reading and damage -----------------------------------------------------------------------------

func test_base_and_current_come_from_the_card_definition():
	var card := await put_creature(1, "Tactical Combatant")
	assert_eq(game.stats.base(card, "Strike"), 3)
	assert_eq(game.stats.base(card, "Guard"), 3)
	assert_eq(game.stats.current(card, "Strike"), 3)
	assert_eq(card.properties["Strike"], 3, "The card shows the current value")
	assert_eq(_label_text(card, "Strike"), "3")


func test_damage_lowers_the_current_stat_and_the_card_face_but_not_the_base():
	var card := await put_creature(1, 3, 2)
	assert_eq(game.stats.apply_damage(card, "Strike", 1), 1)
	assert_eq(game.stats.current(card, "Strike"), 2)
	assert_eq(game.stats.base(card, "Strike"), 3, "The base never changes")
	assert_eq(game.stats.current(card, "Guard"), 2, "Only the stat that was used")
	assert_eq(card.properties["Strike"], 2)
	assert_eq(_label_text(card, "Strike"), "2", "The label follows")
	assert_eq(_label_text(card, "Guard"), "2")
	assert_eq(game.stats.damage_on(card, "Strike"), 1)


func test_damage_never_takes_a_stat_below_zero():
	var card := await put_creature(1, 3, 2)
	assert_eq(game.stats.apply_damage(card, "Guard", 5), 2, "Only what was there is taken")
	assert_eq(game.stats.current(card, "Guard"), 0)
	assert_eq(_label_text(card, "Guard"), "0")
	assert_eq(game.stats.apply_damage(card, "Guard", 3), 0, "Nothing left to take")
	assert_true(FateZones.is_creature_in_play(card), "Strike 3 is left: not destroyed")


func test_a_creature_with_strike_and_guard_at_zero_is_destroyed():
	var card := await put_creature(1, 2, 1)
	var seen := []
	game.creature_destroyed.connect(func(c, cause): seen.append([c, cause]))
	game.stats.apply_damage(card, "Strike", 2)
	assert_true(FateZones.is_creature_in_play(card), "Guard 1 is left")
	game.stats.apply_damage(card, "Guard", 1)
	assert_eq(card.get_parent(), FateZones.container("discard", 1), "Both stats at 0: destroyed")
	assert_eq(seen, [[card, "stats"]])


func test_both_zero_check_runs_after_modifiers_too():
	var card := await put_creature(1, 1, 1)
	game.stats.add_modifier(card, "Strike", -1, "permanent")
	assert_true(FateZones.is_creature_in_play(card))
	game.stats.add_modifier(card, "Guard", -3, "permanent")
	assert_eq(card.get_parent(), FateZones.container("discard", 1))


func test_a_buff_ending_can_destroy_a_damaged_creature():
	# 0/1 with Guard +1 until end of turn, 1 damage: Guard 1 now, 0 when the buff ends
	var card := await put_creature(1, "Goblin Ledgerkeeper")
	game.stats.add_modifier(card, "Guard", 1, "end_of_turn")
	game.stats.apply_damage(card, "Guard", 1)
	assert_eq(game.stats.current(card, "Guard"), 1)
	game.end_turn()
	assert_eq(card.get_parent(), FateZones.container("discard", 1), "Damage outlasted the buff")


func test_batch_holds_the_both_zero_check_back_until_the_end():
	var card := await put_creature(1, 1, 1)
	game.stats.begin_batch()
	game.stats.apply_damage(card, "Strike", 1)
	game.stats.apply_damage(card, "Guard", 1)
	assert_true(FateZones.is_creature_in_play(card), "Still on the table during the batch")
	game.stats.end_batch()
	assert_eq(card.get_parent(), FateZones.container("discard", 1))


# --- reset (D7) ----------------------------------------------------------------------------------------

func test_damage_is_cleared_at_the_owners_next_maintenance_only():
	var mine := await put_creature(1, 3, 3)
	var theirs := await put_creature(2, 3, 3)
	game.stats.apply_damage(mine, "Strike", 2)
	game.stats.apply_damage(theirs, "Guard", 2)
	game.end_turn()
	assert_eq(game.active_id, 2)
	assert_eq(game.stats.current(theirs, "Guard"), 3, "Player 2's maintenance clears player 2's creatures")
	assert_eq(theirs.properties["Guard"], 3, "... and the card face")
	assert_eq(game.stats.current(mine, "Strike"), 1, "Player 1's creature stays damaged")
	game.end_turn()
	assert_eq(game.active_id, 1)
	assert_eq(game.stats.current(mine, "Strike"), 3, "Cleared at its owner's maintenance")
	assert_eq(_label_text(mine, "Strike"), "3")


func test_reset_card_clears_damage_and_short_modifiers_but_not_permanent_ones():
	var card := await put_creature(1, 2, 2)
	game.stats.apply_damage(card, "Strike", 1)
	game.stats.add_modifier(card, "Strike", 1, FateStats.EXPIRY_END_OF_TURN)
	game.stats.add_modifier(card, "Guard", 1, FateStats.EXPIRY_MAINTENANCE)
	game.stats.add_modifier(card, "Guard", 2, FateStats.EXPIRY_PERMANENT)
	game.stats.reset_card(card)
	assert_eq(game.stats.current(card, "Strike"), 2)
	assert_eq(game.stats.current(card, "Guard"), 4, "Only the permanent +2 is left")


# --- modifiers and expiry ---------------------------------------------------------------------------------

func test_modifiers_change_the_current_value_and_the_label():
	var card := await put_creature(1, 2, 2)
	game.stats.add_modifier(card, "Strike", 2, "permanent")
	assert_eq(game.stats.current(card, "Strike"), 4)
	assert_eq(card.properties["Strike"], 4)
	assert_eq(_label_text(card, "Strike"), "4")
	game.stats.add_modifier(card, "Strike", -9, "permanent")
	assert_eq(game.stats.current(card, "Strike"), 0, "Never below 0")


func test_end_of_turn_modifiers_expire_when_the_turn_ends():
	var card := await put_creature(1, 2, 2)
	game.stats.add_modifier(card, "Strike", 2, "end_of_turn")
	game.stats.add_modifier(card, "Guard", 1, "permanent")
	var other := await put_creature(2, 1, 1)
	game.stats.add_modifier(other, "Strike", 1, "end_of_turn")
	game.end_turn()
	assert_eq(game.stats.current(card, "Strike"), 2, "Gone at the end of the turn")
	assert_eq(game.stats.current(other, "Strike"), 1, "... of every creature")
	assert_eq(game.stats.current(card, "Guard"), 3, "Permanent stays")
	assert_eq(_label_text(card, "Strike"), "2")


func test_modifiers_can_be_removed_by_source_or_handle():
	var source := await put_creature(1, 1, 1)
	var card := await put_creature(1, 2, 2)
	var handle := game.stats.add_modifier(card, "Strike", 1, "permanent", source)
	game.stats.add_modifier(card, "Guard", 1, "permanent", source)
	game.stats.add_modifier(card, "Guard", 5, "permanent", null)
	game.stats.remove_modifier(card, handle)
	assert_eq(game.stats.current(card, "Strike"), 2)
	game.stats.remove_modifiers_from(source)
	assert_eq(game.stats.current(card, "Guard"), 7, "Only the other source's +5 is left")


func test_keyword_grants_expire_like_modifiers():
	var card := await put_creature(1, 2, 2)
	assert_false(game.keywords.has(card, "Indomitable"))
	game.stats.grant_keyword(card, "Indomitable", 1, "end_of_turn")
	game.stats.grant_keyword(card, "Savage", 2, "permanent")
	assert_true(game.keywords.has(card, "Indomitable"))
	assert_eq(game.keywords.value(card, "Savage"), 2)
	game.end_turn()
	assert_false(game.keywords.has(card, "Indomitable"), "Until end of turn")
	assert_true(game.keywords.has(card, "Savage"))


func test_keywords_can_add_to_stats_through_stat_bonus():
	var kw := TestKeyword.make("Bonus Test")
	kw.bonus = {"Strike": 2, "Guard": 1}
	game.keywords.register(kw)
	var card := await put_creature(1, 2, 2, {"Bonus Test": 1})
	assert_eq(game.stats.current(card, "Strike"), 4, "Base 2 plus the keyword's bonus")
	assert_eq(game.stats.base(card, "Strike"), 2)
	kw.bonus = {"Strike": 3}
	game.stats.refresh(card)
	assert_eq(card.properties["Strike"], 5, "refresh() updates the card")
	assert_eq(_label_text(card, "Strike"), "5")
	assert_eq(card.properties["Guard"], 2)


func test_a_card_leaving_the_table_forgets_its_state():
	var card := await put_creature(1, 3, 3)
	game.stats.apply_damage(card, "Strike", 2)
	game.stats.add_modifier(card, "Guard", 1, "permanent")
	game.stats.grant_keyword(card, "Indomitable", 1, "permanent")
	card.move_to(FateZones.container("hand", 1), -1, null, ["Scripted"])
	assert_eq(card.properties["Strike"], 3, "Back to the base stats")
	assert_eq(card.properties["Guard"], 3)
	assert_false(game.keywords.has(card, "Indomitable"))
	assert_eq(game.stats.damage_on(card, "Strike"), 0)


# --- destroy -------------------------------------------------------------------------------------------------

func test_destroy_moves_the_card_to_its_owners_discard_and_frees_the_slot():
	var card := await put_creature(1, 2, 2)
	var slot: BoardPlacementSlot = card._placement_slot
	var seen := []
	game.creature_destroyed.connect(func(c, cause): seen.append([c, cause]))
	assert_true(game.effects.destroy(card, null, "effect"))
	assert_eq(card.get_parent(), FateZones.container("discard", 1))
	assert_null(slot.occupying_card, "The slot is free at once")
	assert_null(card._placement_slot)
	assert_eq(seen, [[card, "effect"]])
	assert_false(game.effects.destroy(card), "Not on the table any more")


func test_destroy_works_in_any_creature_grid_and_for_the_owner_of_a_taken_card():
	var occupied := await put_creature(2, 1, 1, {}, true, "occupied")
	assert_true(game.effects.destroy(occupied))
	assert_eq(occupied.get_parent(), FateZones.container("discard", 2))
	# A card controlled by player 1 but owned by player 2 goes to player 2's discard pile
	var taken := await put_creature(1, 1, 1)
	taken.owner_id = 2
	game.effects.destroy(taken)
	assert_eq(taken.get_parent(), FateZones.container("discard", 2))


func test_destroy_obeys_would_be_destroyed_death_destination_and_on_destroyed():
	var guard_kw := TestKeyword.make("Prevent Test")
	guard_kw.allow_destroy = false
	var untethered := TestKeyword.make("Removal Test")
	untethered.destination = "removed"
	game.keywords.register(guard_kw)
	game.keywords.register(untethered)
	var protected := await put_creature(1, 1, 1, {"Prevent Test": 1})
	assert_false(game.effects.destroy(protected))
	assert_eq(protected.get_parent(), board, "Prevented: the card stays")
	var doomed := await put_creature(1, 1, 1, {"Removal Test": 1})
	assert_true(game.effects.destroy(doomed, protected, "effect"))
	assert_eq(doomed.get_parent(), FateZones.container("removed", 1), "To the removed pile")
	assert_eq(untethered.hooks_called("on_destroyed").size(), 1)
	assert_eq(untethered.hooks_called("on_destroyed")[0].slice(1), [doomed, "effect", protected])


# --- deal_damage -------------------------------------------------------------------------------------------------

func test_deal_damage_uses_strike_when_upright_and_guard_when_tilted_or_occupied():
	var upright := await put_creature(1, 3, 3)
	var tilted := await put_creature(1, 3, 3, {}, true)
	var occupied := await put_creature(1, 3, 3, {}, false, "occupied")
	assert_eq(game.effects.deal_damage(upright, 2), 2)
	assert_eq(game.stats.current(upright, "Strike"), 1)
	assert_eq(game.stats.current(upright, "Guard"), 3)
	game.effects.deal_damage(tilted, 2)
	assert_eq(game.stats.current(tilted, "Guard"), 1)
	assert_eq(game.stats.current(tilted, "Strike"), 3)
	game.effects.deal_damage(occupied, 1)
	assert_eq(game.stats.current(occupied, "Guard"), 2)


func test_deal_damage_to_a_creature_destroys_it_only_for_combat_or_both_zero():
	var card := await put_creature(1, 2, 3)
	game.effects.deal_damage(card, 5, null, "effect")
	assert_true(FateZones.is_creature_in_play(card), "An effect leaves Strike at 0, Guard 3 is left")
	assert_eq(game.stats.current(card, "Strike"), 0)
	var fighter := await put_creature(1, 2, 3)
	game.effects.deal_damage(fighter, 5, null, "combat")
	assert_eq(fighter.get_parent(), FateZones.container("discard", 1), "Combat: the used stat reached 0")


func test_deal_damage_goes_through_modify_damage_taken_and_tells_the_source():
	var shield := TestKeyword.make("Shield Test")
	shield.damage_reduction = 1
	game.keywords.register(shield)
	var watcher := TestKeyword.make("Watcher Test")
	game.keywords.register(watcher)
	var target := await put_creature(2, 3, 3, {"Shield Test": 1})
	var source := await put_creature(1, 1, 1, {"Watcher Test": 1})
	var dealt := game.effects.deal_damage(target, 3, source, "effect")
	assert_eq(dealt, 2, "The shield took one")
	assert_eq(game.stats.current(target, "Strike"), 1)
	assert_eq(watcher.hooks_called("on_damage_dealt")[0].slice(1), [source, target, 2, "effect"])
	assert_eq(shield.hooks_called("modify_damage_taken")[0].slice(1, 5), [target, "Strike", 3, "effect"])


func test_deal_damage_to_a_player_lowers_life():
	var p2 := game.player(2)
	var events := []
	game.damage_dealt.connect(func(source, target, amount, cause): events.append([target, amount, cause]))
	assert_eq(game.effects.deal_damage(p2, 3, null, "effect"), 3)
	assert_eq(p2.life, LIFE - 3)
	assert_eq(events, [[p2, 3, "effect"]])
	assert_eq(game.effects.deal_damage(p2, 0), 0, "Zero damage is nothing")
	assert_false(game.is_over)


func test_player_at_zero_life_is_defeated_and_the_game_is_over():
	var seen := []
	game.player_defeated.connect(func(pid): seen.append(pid))
	game.effects.deal_damage(game.player(2), 25, null, "effect")
	assert_eq(game.player(2).life, LIFE - 25)
	assert_eq(seen, [2])
	assert_true(game.is_over)
	assert_eq(game.winner_id, 1)
	assert_true(board.winner_banner.visible)
	assert_eq(board.winner_banner.text, "Player 1 wins")
	assert_false(game.can_draw_extra_card(), "No further turn actions")
	assert_false(game.can_end_turn())
	assert_false(game.can_request_next_phase())
	game.effects.deal_damage(game.player(1), 99)
	assert_eq(seen, [2], "Nothing more happens once the game is over")
