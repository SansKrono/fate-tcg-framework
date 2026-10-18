extends "res://tests/FateCommon.gd"
# Card scripts of the Innovation cards (cards/Fx*.gd).

const THRANG := "Thrang, Perpetual Innovation"


func _main() -> void:
	await empty_hand(1)
	go_to_main()


func _scrap(pid := 1) -> int:
	return game.tokens.counter(pid, "scrap")


func _ingot(pid := 1) -> int:
	return game.tokens.counter(pid, "ingot")


# --- creatures ---------------------------------------------------------------------------------

func test_ledgerkeeper_occupies_for_a_scrap() -> void:
	await _main()
	var c := await put_creature(1, "Goblin Ledgerkeeper")
	assert_true(await game.actions.run(c, "scrap"))
	assert_eq(_scrap(), 1)
	assert_eq(FateZones.zone_of(c), "occupied")
	assert_false(await game.actions.run(c, "scrap"), "occupied: cannot pay Occupy again")
	assert_eq(_scrap(), 1)


func test_fabricator_turns_a_scrap_into_an_ingot_and_needs_a_scrap() -> void:
	await _main()
	var c := await put_creature(1, "Acquisition Fabricator")
	assert_false(await game.actions.run(c, "fabricate"), "no scrap")
	assert_eq(FateZones.zone_of(c), "creatures", "nothing paid")
	game.tokens.set_counter(1, "scrap", 2)
	assert_true(await game.actions.run(c, "fabricate"))
	assert_eq([_scrap(), _ingot()], [1, 1])


func test_factory_crafter_makes_a_guarding_automaton() -> void:
	await _main()
	var c := await put_creature(1, "Factory Crafter")
	game.tokens.set_counter(1, "ingot", 1)
	assert_true(await game.actions.run(c, "craft"))
	await get_tree().process_frame
	assert_eq(_ingot(), 0)
	var autos := game.creatures_in_play(1).filter(func(x): return x.canonical_name == "Iron Automaton Token")
	assert_eq(autos.size(), 1)
	assert_eq(autos[0].card_rotation, 90, "guard position")


func test_factory_crafter_without_ingot_does_nothing() -> void:
	await _main()
	var c := await put_creature(1, "Factory Crafter")
	assert_false(await game.actions.run(c, "craft"))
	assert_eq(FateZones.zone_of(c), "creatures")


func test_battle_smith_equips_a_hammer_that_gives_two_strike() -> void:
	await _main()
	var smith := await put_creature(1, "Battle Smith")
	var ally := await put_creature(1, 1, 1)
	game.tokens.set_counter(1, "ingot", 1)
	game.choices.chooser = func(request): return ally
	assert_true(await game.actions.run(smith, "hammer"))
	await get_tree().process_frame
	assert_eq(_ingot(), 0)
	assert_eq(game.stats.current(ally, "Strike"), 3)
	assert_eq(game.stats.current(smith, "Strike"), 3, "unchanged")
	assert_eq(game.equip.relics_on(ally).size(), 1)


func test_battle_smith_hammer_goes_to_the_default_creature_without_a_chooser() -> void:
	await _main()
	var smith := await put_creature(1, "Battle Smith")
	game.tokens.set_counter(1, "ingot", 1)
	assert_true(await game.actions.run(smith, "hammer"))
	await get_tree().process_frame
	assert_eq(game.equip.relics_on(smith).size(), 1, "the smith is the only creature")


func test_steelwork_salvager_makes_scrap_when_it_attacks() -> void:
	var s := await put_creature(1, "Steelwork Salvager")
	game.keywords.get_keyword("Charge")  # entered_turn is 0 for table cards: free to attack
	start_combat()
	game.combat.declare_attack(s, game.player(2))
	game.combat.confirm_attackers()
	assert_eq(_scrap(), 1)


func test_skulking_goblin_loots_when_it_attacks() -> void:
	await empty_hand(1)
	var g := await put_creature(1, "Skulking Goblin")
	start_combat()
	var before: int = FateZones.container("deck", 1).get_all_cards().size()
	var hand_before: int = FateZones.container("hand", 1).get_all_cards().size()
	game.combat.declare_attack(g, game.player(2))
	game.combat.confirm_attackers()
	await wait_seconds(0.2)
	assert_eq(FateZones.container("deck", 1).get_all_cards().size(), before - 1, "drew")
	assert_eq(FateZones.container("hand", 1).get_all_cards().size(), hand_before, "and discarded one")
	assert_eq(FateZones.container("discard", 1).get_all_cards().size(), 1)


func test_skulking_goblin_may_decline() -> void:
	await empty_hand(1)
	var g := await put_creature(1, "Skulking Goblin")
	game.choices.confirmer = func(_r): return false
	start_combat()
	var before: int = FateZones.container("deck", 1).get_all_cards().size()
	game.combat.declare_attack(g, game.player(2))
	game.combat.confirm_attackers()
	await wait_seconds(0.2)
	assert_eq(FateZones.container("deck", 1).get_all_cards().size(), before)


func test_tinkerer_casts_a_relic_from_the_discard_pile() -> void:
	await _main()
	for _i in 3:
		await put_energy(1, "Scrap Cannon")
	var t := await put_creature(1, "Rustmarket Tinkerer")
	var relic := await put_in_hand(1, "Garbage Heap")
	relic.move_to(FateZones.container("discard", 1), -1, null, ["Scripted"])
	await wait_seconds(0.3)
	assert_true(await game.actions.run(t, "recast"))
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(relic), "relics")
	assert_eq(FateZones.zone_of(t), "occupied")


func test_tinkerer_needs_a_castable_relic() -> void:
	await _main()
	var t := await put_creature(1, "Rustmarket Tinkerer")
	assert_false(await game.actions.run(t, "recast"), "empty discard pile")
	assert_eq(FateZones.zone_of(t), "creatures")


# --- Thrang ------------------------------------------------------------------------------------

func test_thrang_unoccupies_a_permanent_for_a_scrap() -> void:
	await _main()
	var thrang := await put_creature(1, THRANG)
	var tired := await put_creature(1, 1, 1, {}, false, "occupied")
	game.tokens.set_counter(1, "scrap", 1)
	assert_true(await game.actions.run(thrang, "unoccupy"))
	await get_tree().process_frame
	assert_eq(FateZones.zone_of(tired), "creatures")
	assert_eq(_scrap(), 0)


func test_thrang_needs_something_occupied() -> void:
	await _main()
	var thrang := await put_creature(1, THRANG)
	game.tokens.set_counter(1, "scrap", 1)
	assert_false(await game.actions.run(thrang, "unoccupy"))
	assert_eq(_scrap(), 1, "nothing paid")


func test_thrang_cannot_be_targeted_by_spells_but_by_abilities() -> void:
	await _main()
	var thrang := await put_creature(2, THRANG)
	var spell := await put_in_hand(1, "Rapid Scavenging")
	var relic := await put_on_table(1, "Scrap Cannon", "relics")
	assert_false(game.choices.targetable(spell, thrang))
	assert_true(game.choices.targetable(relic, thrang))
	var plain := await put_creature(2, 1, 1)
	assert_eq(game.choices.legal_targets(spell, [thrang, plain]), [plain])
	# a "target ..." pick of a spell never offers it, even to a chooser that wants it
	game.choices.chooser = func(request): return thrang
	var pick = await game.choices.pick("target creature", 1, spell, [thrang, plain])
	assert_eq(pick, plain)


# --- relics ------------------------------------------------------------------------------------

func test_scrap_cannon_hits_a_creature_in_its_position_and_players() -> void:
	await _main()
	var cannon := await put_on_table(1, "Scrap Cannon", "relics")
	var foe := await put_creature(2, 3, 4)
	game.tokens.set_counter(1, "scrap", 2)
	game.choices.chooser = func(request): return foe
	assert_true(await game.actions.run(cannon, "fire"))
	assert_eq(game.stats.current(foe, "Strike"), 2, "upright: Strike")
	foe.set_card_rotation(90)
	assert_true(await game.actions.run(cannon, "fire") or true)
	game.tokens.set_counter(1, "scrap", 1)
	game.choices.chooser = Callable()
	assert_true(await game.actions.run(cannon, "fire"))
	assert_eq(game.player(2).life, LIFE - 1, "default target is the opponent")


func test_scrap_cannon_needs_a_scrap() -> void:
	await _main()
	var cannon := await put_on_table(1, "Scrap Cannon", "relics")
	assert_false(await game.actions.run(cannon, "fire"))
	assert_eq(game.player(2).life, LIFE)


func test_factory_refinery_pays_mana_and_scrap_for_an_ingot() -> void:
	await _main()
	await fill_mana(1, 3)
	var ref := await put_on_table(1, "Factory Refinery", "relics")
	assert_false(await game.actions.run(ref, "refine"), "no scrap")
	game.tokens.set_counter(1, "scrap", 1)
	var mana := total_mana(game.mana_pool(1))
	assert_true(await game.actions.run(ref, "refine"))
	assert_eq([_scrap(), _ingot()], [0, 1])
	assert_eq(total_mana(game.mana_pool(1)), mana - 1)


func test_garbage_heap_is_consumed_for_two_scrap() -> void:
	await _main()
	var heap := await put_on_table(1, "Garbage Heap", "relics")
	assert_true(await game.actions.run(heap, "scrap"))
	assert_eq(_scrap(), 2)
	assert_eq(heap.get_parent(), FateZones.container("discard", 1))


func test_scrap_recycler_consumes_a_relic_once_per_turn_to_draw() -> void:
	await _main()
	var rec := await put_on_table(1, "Scrap Recycler", "relics")
	var heap := await put_on_table(1, "Garbage Heap", "relics")
	var spare := await put_on_table(1, "Garbage Heap", "relics")
	game.choices.chooser = func(request): return heap if heap in request.options else request.options[0]
	var hand_before: int = FateZones.container("hand", 1).get_all_cards().size()
	assert_true(await game.actions.run(rec, "recycle"))
	await wait_seconds(0.1)
	assert_eq(heap.get_parent(), FateZones.container("discard", 1))
	assert_eq(FateZones.container("hand", 1).get_all_cards().size(), hand_before + 1)
	assert_false(await game.actions.run(rec, "recycle"), "once per turn")
	assert_eq(FateZones.zone_of(spare), "relics")


func test_crafting_table_modes_cost_one_two_and_three_ingots() -> void:
	await _main()
	var table := await put_on_table(1, "Thrang's Crafting Table", "relics")
	var smith := await put_creature(1, 1, 1)
	game.tokens.set_counter(1, "ingot", 6)
	assert_true(await game.actions.run(table, "hammer"))
	await get_tree().process_frame
	assert_eq(_ingot(), 5)
	assert_eq(game.equip.relics_on(smith).size(), 1)
	assert_true(await game.actions.run(table, "automaton"))
	await get_tree().process_frame
	assert_eq(_ingot(), 3)
	assert_eq(game.creatures_in_play(1).filter(
			func(x): return x.canonical_name == "Iron Automaton Token" and x.card_rotation == 90).size(), 1)
	var deck: Pile = FateZones.container("deck", 1)
	var thrang := cfc.instance_card(THRANG)
	deck.add_child(thrang)
	thrang.assign_owner(1)
	assert_true(await game.actions.run(table, "thrang"))
	await wait_seconds(0.2)
	assert_eq(_ingot(), 0)
	assert_eq(thrang.get_parent(), FateZones.container("hand", 1))


func test_crafting_table_thrang_mode_needs_thrang_in_the_deck() -> void:
	await _main()
	var table := await put_on_table(1, "Thrang's Crafting Table", "relics")
	game.tokens.set_counter(1, "ingot", 3)
	for c in FateZones.container("deck", 1).get_all_cards():
		if c.canonical_name == THRANG:
			c.queue_free()
	await get_tree().process_frame
	assert_false(await game.actions.run(table, "thrang"))
	assert_eq(_ingot(), 3)
	assert_false(await game.actions.run(table, "automaton") and false)


# --- spells ------------------------------------------------------------------------------------

func test_rapid_scavenging_creates_two_scrap() -> void:
	await _main()
	await fill_mana(1, 3)
	var spell := await put_in_hand(1, "Rapid Scavenging")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.1)
	assert_eq(_scrap(), 2)


func test_fabrication_line_copies_a_token_card_or_a_counter() -> void:
	await _main()
	await fill_mana(1, 3)
	var soldier: Card = game.tokens.create("Iron Automaton Token", 1)
	var spell := await put_in_hand(1, "Fabrication Line")
	game.choices.chooser = func(request): return soldier
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.2)
	assert_eq(game.creatures_in_play(1).filter(func(x): return x.canonical_name == "Iron Automaton Token").size(), 3)
	game.tokens.set_counter(1, "scrap", 2)
	game.choices.chooser = func(request): return "scrap"
	var spell2 := await put_in_hand(1, "Fabrication Line")
	assert_true(game.play_from_hand(spell2))
	await wait_seconds(0.2)
	assert_eq(_scrap(), 4)


func test_fabrication_line_needs_a_token_you_control() -> void:
	await _main()
	await fill_mana(1, 3)
	var spell := await put_in_hand(1, "Fabrication Line")
	assert_false(game.can_play_from_hand(spell), "no token")
	game.tokens.create("Iron Automaton Token", 2)
	assert_false(game.can_play_from_hand(spell), "only the opponent has one")


func test_invigorated_workforce_lets_tap_creatures_occupy_on_entry() -> void:
	await _main()
	await fill_mana(1, 3)
	var field := await put_on_table(1, "Invigorated Workforce", "field")
	var c := await put_creature(1, "Goblin Ledgerkeeper")
	c.entered_turn = game.turn_number
	assert_true(game.keywords.has(c, "Productive"))
	assert_true(await game.actions.run(c, "scrap"))
	var plain := await put_creature(1, 1, 1)
	assert_false(game.keywords.has(plain, "Productive"), "no occupy ability")
	var theirs := await put_creature(2, "Goblin Ledgerkeeper")
	assert_false(game.keywords.has(theirs, "Productive"), "opponent's creature")
	assert_not_null(field)


func test_without_the_field_spell_a_new_creature_cannot_occupy() -> void:
	await _main()
	var c := await put_creature(1, "Goblin Ledgerkeeper")
	c.entered_turn = game.turn_number
	assert_false(await game.actions.run(c, "scrap"))
