extends "res://tests/FateCommon.gd"
# Tests of Embody X (src/custom/fate/keywords/KwEmbody.gd). Rules: docs/FATE_RULES_SPEC.md, Section 4.
# The creature is Spirit Wielder (Strike 1, Guard 1, "Pay 3: Embody", listed in `_keywords` only).
# Energy cards are real cards put face-down in the energy zone; their mana values (Cost + Pips):
#   Garbage Heap 2, Dragon's Tooth 2, Scrap Cannon 3, Ancient Tree 3, Teshra's War Gauntlets 4,
#   Thrang's Crafting Table 5.
# Player 1 is the active player; the tests go to the MAIN phase first (go_to_main()).

const KwEmbodyScript := preload("res://src/custom/fate/keywords/KwEmbody.gd")

var kw


func before_each():
	await super.before_each()
	kw = game.keywords.get_keyword("Embody")
	KwEmbodyScript.chooser = Callable()


func after_each():
	KwEmbodyScript.chooser = Callable()


func _label_text(card: Card, stat: String) -> String:
	return card.card_front.card_labels[stat].text


func _discard(pid: int) -> Node:
	return FateZones.container("discard", pid)


# A Spirit Wielder on the table and 3 cheap untapped energy cards to pay with, plus `target`
# (a card name) untapped. Returns [wielder, target card]. The MAIN phase has been reached.
func _setup(target_name := "Thrang's Crafting Table") -> Array:
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	var target := await put_energy(1, target_name)
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	return [wielder, target]


func _untapped(pid: int) -> int:
	return game.mana.untapped_energy(pid).size()


# --- the keyword is registered ------------------------------------------------------------------------

func test_the_keyword_is_registered_and_found_on_spirit_wielder():
	assert_not_null(kw)
	assert_true(kw.universal, "Spirit Wielder only lists Embody in _keywords")
	var wielder := await put_creature(1, "Spirit Wielder")
	assert_true(kw.has_ability(wielder))
	assert_eq(kw.cost_of(wielder), 3, "X from the ability text")
	assert_false(kw.has_ability(await put_creature(1, 2, 2)), "A plain creature has no Embody")


# --- embodying: the card beneath the creature -------------------------------------------------------------

func test_embody_moves_the_energy_card_beneath_the_creature_face_down():
	var s := await _setup()
	var wielder: Card = s[0]
	var target: Card = s[1]
	var slot: BoardPlacementSlot = target._placement_slot
	assert_true(target.is_energy)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 4)
	assert_true(kw.embody(wielder, target))
	assert_eq(wielder.attachments, [target], "It is a card attachment of the creature")
	assert_eq(target.current_host_card, wielder)
	assert_eq(target.attachment_mode, Card.AttachmentMode.ATTACH_BEHIND, "Behind the creature")
	assert_false(target.is_faceup, "Face-down")
	assert_eq(target.get_parent(), board, "Still on the table")
	assert_eq(target.card_rotation, 0)
	assert_false(target.is_energy, "No longer an energy card")
	assert_eq(kw.embodied_card(wielder), target)
	assert_null(slot.occupying_card, "The energy slot is free again")
	assert_null(target._placement_slot)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 3, "Only the three payers are left")
	assert_eq(game.mana.mana_pool(1).values().reduce(func(a, b): return a + b, 0), 0,
			"X = 3 other energy cards were tapped")
	assert_eq(_untapped(1), 0)


func test_the_slot_can_be_reused_by_a_new_energy_card():
	var s := await _setup()
	var slot: BoardPlacementSlot = s[1]._placement_slot
	kw.embody(s[0], s[1])
	var again := await put_energy(1, "Garbage Heap")
	assert_eq(again._placement_slot, slot, "The next energy card takes the free slot")


func test_the_bonus_is_the_mana_value_of_the_card_for_strike_and_guard():
	var s := await _setup("Thrang's Crafting Table")
	var wielder: Card = s[0]
	assert_eq(s[1].mana_value(), 5)
	kw.embody(wielder, s[1])
	assert_eq(game.stats.base(wielder, "Strike"), 1, "The base does not change")
	assert_eq(game.stats.current(wielder, "Strike"), 6, "1 + 5")
	assert_eq(game.stats.current(wielder, "Guard"), 6)
	assert_eq(wielder.properties["Strike"], 6)
	assert_eq(_label_text(wielder, "Strike"), "6", "Shown on the card")
	assert_eq(_label_text(wielder, "Guard"), "6")


func test_generic_cost_and_pips_both_count_towards_the_mana_value():
	var s := await _setup("Scrap Cannon")
	assert_eq(s[1].mana_value(), 3, "Cost 2 + one pip")
	kw.embody(s[0], s[1])
	assert_eq(game.stats.current(s[0], "Strike"), 4)


func test_a_tapped_energy_card_can_be_embodied_and_ends_upright():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	var spent := await put_energy(1, "Teshra's War Gauntlets", true)
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	assert_eq(spent.card_rotation, 90)
	assert_true(kw.embody(wielder, spent))
	assert_eq(game.stats.current(wielder, "Strike"), 5, "1 + 4")
	assert_eq(spent.card_rotation, 0)
	assert_eq(_untapped(1), 0, "The three untapped ones paid")


func test_the_embodied_card_is_not_used_for_payment_when_others_can_pay():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	var target := await put_energy(1, "Scrap Cannon")
	for _i in range(4):
		await put_energy(1, "Garbage Heap")
	assert_true(kw.embody(wielder, target))
	assert_eq(_untapped(1), 1, "5 untapped before, 3 paid by the others: 1 left")
	assert_eq(target.get_parent(), board)


func test_the_embodied_card_pays_too_when_nothing_else_can():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	var target := await put_energy(1, "Scrap Cannon")
	for _i in range(2):
		await put_energy(1, "Garbage Heap")
	assert_true(kw.embody(wielder, target), "3 untapped energy cards in total, one of them is embodied")
	assert_eq(_untapped(1), 0)
	assert_eq(game.stats.current(wielder, "Strike"), 4)


func test_the_bonus_stays_through_maintenance_and_turns():
	var s := await _setup("Scrap Cannon")
	kw.embody(s[0], s[1])
	game.end_turn()
	game.end_turn()
	assert_eq(game.active_id, 1)
	assert_eq(game.stats.current(s[0], "Strike"), 4, "Not an until-end-of-turn effect")
	assert_eq(_label_text(s[0], "Guard"), "4")
	assert_eq(kw.embodied_card(s[0]), s[1])


func test_damage_is_taken_off_the_boosted_stat_and_the_bonus_stays():
	var s := await _setup("Scrap Cannon")
	kw.embody(s[0], s[1])
	game.effects.deal_damage(s[0], 2, null, "effect")
	assert_eq(game.stats.current(s[0], "Strike"), 2, "4 - 2")
	assert_eq(game.stats.current(s[0], "Guard"), 4)


# --- one at a time ------------------------------------------------------------------------------------------------

func test_a_second_embody_discards_the_first_card_and_replaces_the_bonus():
	var s := await _setup("Thrang's Crafting Table")
	var wielder: Card = s[0]
	var first: Card = s[1]
	kw.embody(wielder, first)
	assert_eq(game.stats.current(wielder, "Strike"), 6)
	var second := await put_energy(1, "Scrap Cannon")
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	assert_true(kw.embody(wielder, second))
	assert_eq(first.get_parent(), _discard(1), "The old card is in its owner's discard pile")
	assert_null(first.current_host_card)
	assert_eq(wielder.attachments, [second], "Only one card beneath the creature")
	assert_eq(game.stats.current(wielder, "Strike"), 4, "The bonus was replaced, not added: 1 + 3")
	assert_eq(game.stats.current(wielder, "Guard"), 4)
	assert_eq(_label_text(wielder, "Strike"), "4")
	assert_eq(kw.embodied_card(wielder), second)
	assert_false(first.has_meta(KwEmbodyScript.META_HOST))


func test_a_replaced_card_goes_to_its_owners_discard_pile():
	var s := await _setup("Garbage Heap")
	s[1].owner_id = 2
	kw.embody(s[0], s[1])
	var second := await put_energy(1, "Scrap Cannon")
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	kw.embody(s[0], second)
	assert_eq(s[1].get_parent(), _discard(2))


# --- the creature leaves play ----------------------------------------------------------------------------------------

func test_when_the_creature_is_destroyed_the_embodied_card_goes_to_the_discard_pile():
	var s := await _setup("Scrap Cannon")
	var wielder: Card = s[0]
	var embodied: Card = s[1]
	kw.embody(wielder, embodied)
	var creature_slot: BoardPlacementSlot = wielder._placement_slot
	assert_true(game.effects.destroy(wielder, null, "effect"))
	await wait_seconds(0.3)
	assert_eq(wielder.get_parent(), _discard(1))
	assert_eq(embodied.get_parent(), _discard(1), "Not left on the table")
	assert_null(embodied._placement_slot, "No slot bookkeeping left")
	assert_null(embodied.current_host_card)
	assert_true(wielder.attachments.is_empty())
	assert_null(creature_slot.occupying_card)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 3, "Energy zone: only the payers")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 0)
	for card in board.get_all_cards():
		assert_ne(card, embodied, "The embodied card is no longer a card on the table")
	assert_eq(game.stats.current(wielder, "Strike"), 1, "The creature forgot the bonus")


func test_an_untethered_creature_is_removed_but_the_embodied_card_still_goes_to_the_discard():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	game.stats.grant_keyword(wielder, "Untethered", 1, "permanent")
	var target := await put_energy(1, "Scrap Cannon")
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	kw.embody(wielder, target)
	game.effects.destroy(wielder, null, "effect")
	await wait_seconds(0.3)
	assert_eq(wielder.get_parent(), FateZones.container("removed", 1))
	assert_eq(target.get_parent(), _discard(1))


func test_combat_death_also_releases_the_card():
	var s := await _setup("Garbage Heap")
	kw.embody(s[0], s[1])
	var enemy := await put_creature(2, 9, 9)
	start_combat()
	game.combat.declare_attack(s[0], enemy)
	run_combat()
	await wait_seconds(0.3)
	assert_eq(s[0].get_parent(), _discard(1), "3/3 attacking a 9/9 dies")
	assert_eq(s[1].get_parent(), _discard(1))


func test_a_card_taken_from_beneath_the_creature_takes_the_bonus_with_it():
	var s := await _setup("Scrap Cannon")
	kw.embody(s[0], s[1])
	s[1].move_to(_discard(1), -1, null, ["Scripted"])
	await wait_seconds(0.4)
	assert_true(s[0].attachments.is_empty())
	assert_eq(game.stats.current(s[0], "Strike"), 1)
	assert_eq(_label_text(s[0], "Strike"), "1", "The card face follows")


# --- denied: nothing is charged ------------------------------------------------------------------------------------------

func _assert_denied(wielder: Card, energy: Card, message: String) -> void:
	var before_pool := game.mana.mana_pool(wielder.controller_id).duplicate()
	var before_energy := game.player(wielder.controller_id).cards_in_grid("energy").size()
	assert_false(kw.can_embody(wielder, energy), message)
	assert_false(kw.embody(wielder, energy), message)
	assert_true(wielder.attachments.is_empty(), message + ": nothing beneath")
	assert_eq(game.mana.mana_pool(wielder.controller_id), before_pool, message + ": nothing charged")
	assert_eq(game.player(wielder.controller_id).cards_in_grid("energy").size(), before_energy)
	assert_eq(game.stats.current(wielder, "Strike"), 1)
	assert_eq(game.actions.list(wielder).size(), 0, message + ": no button")


func test_denied_outside_the_main_phase():
	var wielder := await put_creature(1, "Spirit Wielder")
	var target := await put_energy(1, "Scrap Cannon")
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	_assert_denied(wielder, target, "Energy phase")
	go_to_main()
	game.advance_phase()
	assert_eq(game.phase, FateGame.Phase.COMBAT_DECLARE)
	_assert_denied(wielder, target, "Combat phase")


func test_denied_for_the_other_player_and_for_their_energy():
	go_to_main()
	var theirs := await put_creature(2, "Spirit Wielder")
	var their_energy := await put_energy(2, "Scrap Cannon")
	for _i in range(3):
		await put_energy(2, "Garbage Heap")
	_assert_denied(theirs, their_energy, "Not their turn")
	var mine := await put_creature(1, "Spirit Wielder")
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	assert_false(kw.can_embody(mine, their_energy), "Not one of my energy cards")
	assert_false(kw.embody(mine, their_energy))
	assert_true(their_energy.is_energy)
	assert_eq(_untapped(1), 3, "Nothing charged")


func test_denied_without_enough_mana():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	var target := await put_energy(1, "Scrap Cannon")
	await put_energy(1, "Garbage Heap")
	await put_energy(1, "Garbage Heap", true)
	assert_eq(_untapped(1), 2)
	_assert_denied(wielder, target, "Only 2 untapped energy cards, X is 3")
	assert_eq(_untapped(1), 2)


func test_denied_without_an_energy_card():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	assert_false(kw.can_embody(wielder))
	assert_false(kw.embody(wielder, null))
	assert_eq(game.actions.list(wielder).size(), 0)
	assert_true(wielder.attachments.is_empty())


func test_denied_for_a_creature_without_the_ability_and_for_a_card_out_of_play():
	var s := await _setup()
	var plain := await put_creature(1, 2, 2)
	assert_false(kw.embody(plain, s[1]))
	assert_true(plain.attachments.is_empty())
	assert_eq(_untapped(1), 4, "Nothing charged")
	var relic := await put_on_table(1, "Holy Amulet", "relics")
	assert_false(kw.embody(relic, s[1]), "Not a creature")


func test_free_embody_skips_the_phase_and_the_payment():
	var wielder := await put_creature(1, "Spirit Wielder")
	var target := await put_energy(1, "Scrap Cannon")
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	assert_false(kw.embody(wielder, target))
	assert_true(kw.embody(wielder, target, true), "An effect that embodies for free")
	assert_eq(game.stats.current(wielder, "Strike"), 4)


# --- the chooser --------------------------------------------------------------------------------------------------------------

func test_default_chooser_takes_the_highest_mana_value_then_a_tapped_card_then_slot_order():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	var low := await put_energy(1, "Garbage Heap")
	var mid_a := await put_energy(1, "Scrap Cannon")
	var mid_b := await put_energy(1, "Ancient Tree", true)
	var mid_c := await put_energy(1, "Scrap Cannon", true)
	var options: Array = kw.candidates(wielder)
	assert_eq(options, [low, mid_a, mid_b, mid_c], "Slot order")
	assert_eq(KwEmbodyScript.default_chooser(wielder, options), mid_b, "Tie of 3: the first TAPPED one")
	assert_eq(KwEmbodyScript.default_chooser(wielder, [low, mid_a, mid_c]), mid_c)
	assert_eq(KwEmbodyScript.default_chooser(wielder, [low, mid_a]), mid_a, "Tie, none tapped: slot order")
	assert_eq(KwEmbodyScript.default_chooser(wielder, [low]), low)
	assert_null(KwEmbodyScript.default_chooser(wielder, []))


func test_a_custom_chooser_decides_which_card_is_embodied():
	var s := await _setup("Thrang's Crafting Table")
	var cheap: Card = game.player(1).cards_in_grid("energy").back()
	var asked := []
	KwEmbodyScript.chooser = func(creature, options):
		asked.append([creature, options.size()])
		return cheap
	assert_true(await game.actions.run(s[0], "embody"))
	assert_eq(asked, [[s[0], 4]])
	assert_eq(kw.embodied_card(s[0]), cheap)
	assert_eq(game.stats.current(s[0], "Strike"), 3, "1 + the 2 of Garbage Heap")


func test_a_chooser_may_be_a_coroutine():
	var s := await _setup()
	KwEmbodyScript.chooser = func(_creature, options):
		await get_tree().process_frame
		return options[0]
	assert_true(await game.actions.run(s[0], "embody"))
	assert_eq(kw.embodied_card(s[0]), s[1], "The first in slot order")


func test_a_chooser_that_cancels_or_answers_nonsense_charges_nothing():
	var s := await _setup()
	var stranger := await put_energy(2, "Garbage Heap")
	KwEmbodyScript.chooser = func(_creature, _options): return null
	assert_false(await game.actions.run(s[0], "embody"))
	KwEmbodyScript.chooser = func(_creature, _options): return stranger
	assert_false(await game.actions.run(s[0], "embody"))
	assert_true(s[0].attachments.is_empty())
	assert_eq(_untapped(1), 4)


# --- the hover action ------------------------------------------------------------------------------------------------------------

func test_the_action_is_offered_for_spirit_wielder_when_legal():
	var s := await _setup()
	var list := game.actions.list(s[0])
	assert_eq(list.size(), 1)
	assert_eq(list[0].id, "embody")
	assert_eq(list[0].label, "Embody (pay 3)")
	assert_true(list[0].enabled)
	assert_string_contains(list[0].tooltip, "3")


func test_the_action_runs_with_the_default_chooser():
	var s := await _setup("Thrang's Crafting Table")
	var done := []
	game.actions.action_performed.connect(func(card, id): done.append([card, id]))
	assert_true(await game.actions.run(s[0], "embody"))
	assert_eq(done, [[s[0], "embody"]])
	assert_eq(kw.embodied_card(s[0]), s[1], "The highest mana value")
	assert_eq(game.stats.current(s[0], "Strike"), 6)
	assert_eq(game.actions.list(s[0]).size(), 0, "No mana left: no button")


func test_the_action_is_not_offered_when_it_is_not_legal_or_not_embody():
	var plain := await put_creature(1, 2, 2)
	var wielder := await put_creature(1, "Spirit Wielder")
	for _i in range(4):
		await put_energy(1, "Garbage Heap")
	assert_eq(game.actions.list(wielder).size(), 0, "Energy phase")
	go_to_main()
	assert_eq(game.actions.list(wielder).size(), 1)
	assert_eq(game.actions.list(plain).size(), 0, "A plain creature has no Embody")


func test_a_granted_embody_keyword_gives_the_ability_with_its_own_cost():
	go_to_main()
	var plain := await put_creature(1, 2, 2)
	var target := await put_energy(1, "Scrap Cannon")
	await put_energy(1, "Garbage Heap")
	await put_energy(1, "Garbage Heap")
	game.stats.grant_keyword(plain, "Embody", 2, "permanent")
	var list := game.actions.list(plain)
	assert_eq(list.size(), 1)
	assert_eq(list[0].label, "Embody (pay 2)")
	assert_true(kw.embody(plain, target))
	assert_eq(game.stats.current(plain, "Strike"), 5, "2 + 3")
	assert_eq(_untapped(1), 0)


# --- combat and zones ---------------------------------------------------------------------------------------------------------------

func test_combat_uses_the_boosted_stats():
	var s := await _setup("Thrang's Crafting Table")
	var wielder: Card = s[0]
	kw.embody(wielder, s[1])
	var enemy := await put_creature(2, 5, 1)
	start_combat()
	assert_true(game.combat.declare_attack(wielder, enemy))
	run_combat()
	assert_eq(enemy.get_parent(), _discard(2), "Strike 6 against Strike 5: the defender dies")
	assert_eq(game.stats.current(wielder, "Strike"), 1, "6 - 5 left")
	assert_eq(_label_text(wielder, "Strike"), "1")
	assert_eq(game.stats.current(wielder, "Guard"), 6, "Guard untouched")
	assert_eq(kw.embodied_card(wielder), s[1], "Still beneath the creature")


func test_an_unblocked_attack_on_the_player_hits_for_the_boosted_strike():
	var s := await _setup("Scrap Cannon")
	kw.embody(s[0], s[1])
	var life := game.player(2).life
	start_combat()
	game.combat.declare_attack(s[0], 2)
	run_combat()
	assert_eq(game.player(2).life, life - 1, "A hit takes 1 life whatever the boosted Strike")


func test_a_blocker_uses_the_boosted_guard():
	var s := await _setup("Scrap Cannon")
	var wielder: Card = s[0]
	kw.embody(wielder, s[1])
	wielder.set_card_rotation(90)
	game.end_turn()
	# Player 2 attacks with a Strike 3 creature and the Wielder (Guard 4) intercepts
	var attacker := await put_creature(2, 3, 1)
	game.turn.end_phase_waits_for_player = true
	game.draw_extra_card()
	game.advance_phase()
	assert_true(game.combat.declare_attack(attacker, 1))
	game.combat.confirm_attackers()
	assert_true(game.combat.declare_block(wielder, game.combat.attack_of(attacker)), game.combat.last_error)
	game.combat.confirm_blocks()
	assert_true(FateZones.is_creature_in_play(wielder), "Guard 4 absorbs Strike 3")
	assert_eq(game.stats.current(wielder, "Guard"), 1, "4 - 3")
	assert_eq(attacker.get_parent(), _discard(2), "The attacker used all its Strike")


func test_a_creature_in_the_occupied_zone_carries_the_bonus():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder", 1, {}, false, "occupied")
	var target := await put_energy(1, "Scrap Cannon")
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	assert_eq(FateZones.zone_of(wielder), "occupied")
	assert_true(kw.embody(wielder, target), "A creature in the occupied zone can embody")
	assert_eq(game.stats.current(wielder, "Guard"), 4)
	assert_eq(_label_text(wielder, "Guard"), "4")
	assert_eq(wielder.attachments, [target])


func test_occupying_after_embodying_keeps_the_card_and_the_bonus():
	var s := await _setup("Scrap Cannon")
	var wielder: Card = s[0]
	kw.embody(wielder, s[1])
	assert_true(game.keywords.get_keyword("Occupy").occupy(wielder))
	await wait_seconds(0.3)
	assert_eq(FateZones.zone_of(wielder), "occupied")
	assert_eq(wielder.attachments, [s[1]], "The card stays beneath the creature")
	assert_eq(s[1].current_host_card, wielder)
	assert_eq(game.stats.current(wielder, "Strike"), 4)
	assert_eq(game.stats.current(wielder, "Guard"), 4)
	game.end_turn()
	game.end_turn()
	assert_eq(FateZones.zone_of(wielder), "creatures", "Maintenance moved it back")
	assert_eq(game.stats.current(wielder, "Strike"), 4, "... still boosted")
	assert_eq(wielder.attachments, [s[1]])
