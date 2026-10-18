extends "res://tests/FateCommon.gd"
# Primal cards (docs/FATE_TCG_DESIGN.md Section 14.4): the card scripts in cards/Fx*.gd and the mana additions
# (cost reductions, floating mana) they use.

const PRIMAL_ENERGY := "Ancient Tree"


func _to_main(primal := 3) -> void:
	await empty_hand(1)
	await fill_mana(1, 3)
	for _i in range(primal):
		await put_energy(1, PRIMAL_ENERGY)
	go_to_main()


func _energy_count(pid: int) -> int:
	return game.player(pid).cards_in_grid("energy").size()


func _in_energy(card: Card, pid: int) -> bool:
	return card in game.player(pid).cards_in_grid("energy")


# --- keyword-only cards ------------------------------------------------------------------------------------

func test_keyword_cards_need_no_script() -> void:
	var names: Array = game.card_effects.registered_names()
	for n in ["Beetle Brawler", "Ironside Beetle", "Feracious Beast", "Spirit Wielder", "Wraithful Treespirits"]:
		assert_false(n in names, n)
	var beast := await put_creature(1, "Feracious Beast")
	assert_eq(game.keywords.value(beast, "Savage"), 2)
	var ironside := await put_creature(1, "Ironside Beetle")
	assert_eq(game.keywords.value(ironside, "Savage"), 1)
	var brawler := await put_creature(1, "Beetle Brawler")
	assert_eq(game.keywords.get_keyword("Forced blocker").has_ability(brawler), true)
	assert_eq(game.keywords.get_keyword("Evolution").evolves_into(brawler), "Ironside Beetle")


# --- Meek Minion ---------------------------------------------------------------------------------------------------

func test_meek_minion_reduces_the_next_creature_by_two() -> void:
	await _to_main()
	var minion := await put_creature(1, "Meek Minion")
	assert_true(await game.actions.run(minion, "meek_consume"))
	assert_eq(FateZones.zone_of(minion), "", "consumed")
	var beast := await put_in_hand(1, "Feracious Beast")
	assert_eq(game.mana.cost_of(beast).generic, 3, "printed cost untouched")
	assert_eq(game.mana.effective_cost(beast).generic, 1)
	var before := total_mana(game.mana_pool(1))
	assert_true(game.play_from_hand(beast))
	await wait_seconds(0.2)
	assert_eq(total_mana(game.mana_pool(1)), before - 2, "1 generic + 1 Primal pip")
	var second := await put_in_hand(1, "Feracious Beast")
	assert_eq(game.mana.effective_cost(second).generic, 3, "one-shot: used up")


func test_meek_minion_reduction_ignores_spells_and_keeps_waiting() -> void:
	await _to_main()
	var minion := await put_creature(1, "Meek Minion")
	assert_true(await game.actions.run(minion, "meek_consume"))
	var spell := await put_in_hand(1, "Primal Wraith")
	assert_eq(game.mana.effective_cost(spell).generic, 3, "not a creature")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.2)
	var beast := await put_in_hand(1, "Feracious Beast")
	assert_eq(game.mana.effective_cost(beast).generic, 1, "still there after a spell")
	game.end_turn()
	assert_eq(game.mana.effective_cost(beast).generic, 1, "no time limit")


func test_cost_reduction_never_goes_below_zero_and_can_expire() -> void:
	await _to_main()
	game.mana.add_cost_reduction(1, 5, Callable(), "end_of_turn")
	var cheap := await put_in_hand(1, "Beetle Brawler")
	assert_eq(game.mana.effective_cost(cheap), {"generic": 0, "pips": {"Primal": 1}})
	game.end_turn()
	assert_eq(game.mana.effective_cost(cheap).generic, 1, "expired")


# --- Ancient Tree and floating mana ------------------------------------------------------------------------

func test_ancient_tree_produces_floating_primal_mana() -> void:
	await _to_main(0)
	var tree := await put_on_table(1, "Ancient Tree", "relics")
	var before := total_mana(game.mana_pool(1))
	assert_true(await game.actions.run(tree, "ancient_tree"))
	assert_eq(tree.card_rotation, 90, "tilted")
	assert_eq(game.mana_pool(1)["Primal"], 1)
	assert_eq(total_mana(game.mana_pool(1)), before + 1)
	assert_false(await game.actions.run(tree, "ancient_tree"), "already tilted")
	assert_eq(game.mana.floating_total(1), 1)
	# floating mana pays first and leaves the energy cards alone
	assert_true(game.mana.pay_generic(1, 1))
	assert_eq(game.mana.floating_total(1), 0)
	assert_eq(total_mana(game.mana_pool(1)), before)


func test_floating_mana_pays_a_pip_and_goes_at_end_of_turn() -> void:
	await _to_main(0)
	game.mana.add_floating(1, "Primal", 1)
	var brawler := await put_in_hand(1, "Beetle Brawler")
	var plan := game.mana.plan_payment(brawler)
	assert_true(plan.ok)
	assert_eq(plan.floating, {"Primal": 1}, "the Primal pip")
	assert_eq(plan.cards.size(), 1, "the generic 1 from energy")
	game.end_turn()
	assert_eq(game.mana.floating_total(1), 0, "gone")


# --- Elder Spirit ------------------------------------------------------------------------------------------------

func test_elder_spirit_puts_the_top_card_into_energy() -> void:
	await _to_main()
	var spirit := await put_creature(1, "Elder Spirit")
	var top: Card = game.library.look_top(1, 1)[0]
	var energy := _energy_count(1)
	assert_true(await game.actions.run(spirit, "elder_spirit"))
	assert_eq(FateZones.zone_of(spirit), "occupied")
	assert_eq(_energy_count(1), energy + 1)
	assert_true(_in_energy(top, 1))


func test_elder_spirit_needs_a_card_in_the_deck() -> void:
	await _to_main()
	var spirit := await put_creature(1, "Elder Spirit")
	for c in game.library.look_top(1, 200):
		game.library.to_discard(c)
	await wait_seconds(0.3)
	assert_false(await game.actions.run(spirit, "elder_spirit"))
	assert_eq(FateZones.zone_of(spirit), "creatures", "not occupied")


# --- Teshra and Guardian Spirits ---------------------------------------------------------------------------

func test_teshra_flips_a_creature_from_energy_until_end_of_turn() -> void:
	await _to_main()
	var teshra := await put_creature(1, "Teshra, Primal Mother")
	var borrowed := await put_energy(1, "Righteous Guard")
	var before := total_mana(game.mana_pool(1))
	assert_true(await game.actions.run(teshra, "teshra_flip"))
	assert_eq(FateZones.zone_of(borrowed), "creatures")
	assert_eq(total_mana(game.mana_pool(1)), before - 3 - 1, "paid 3; the card left the energy zone")
	assert_true(game.keywords.has(borrowed, "Charge"), "may attack this turn")
	game.end_turn()
	await wait_seconds(0.3)
	assert_true(_in_energy(borrowed, 1), "back in the energy zone")


func test_teshra_needs_a_creature_in_energy_and_charges_nothing_otherwise() -> void:
	await _to_main()
	var teshra := await put_creature(1, "Teshra, Primal Mother")
	var before := total_mana(game.mana_pool(1))
	assert_false(await game.actions.run(teshra, "teshra_flip"))
	assert_eq(total_mana(game.mana_pool(1)), before)


func test_teshra_creature_destroyed_does_not_return() -> void:
	await _to_main()
	var teshra := await put_creature(1, "Teshra, Primal Mother")
	var borrowed := await put_energy(1, "Righteous Guard")
	assert_true(await game.actions.run(teshra, "teshra_flip"))
	game.effects.destroy(borrowed, null, "effect")
	await wait_seconds(0.2)
	game.end_turn()
	await wait_seconds(0.3)
	assert_false(_in_energy(borrowed, 1))


func test_guardian_spirits_flips_a_creature_at_the_start_of_the_turn() -> void:
	await _to_main()
	await put_on_table(1, "Guardian Spirits", "field")
	var borrowed := await put_energy(1, "Righteous Guard")
	game.end_turn()
	await wait_seconds(0.3)
	game.end_turn()
	await wait_seconds(0.5)
	assert_eq(game.active_id, 1)
	assert_eq(FateZones.zone_of(borrowed), "creatures", "flipped at the beginning of my turn")
	assert_true(game.keywords.has(borrowed, "Charge"))


func test_guardian_spirits_does_nothing_without_a_creature_in_energy() -> void:
	await _to_main()
	await put_on_table(1, "Guardian Spirits", "field")
	var energy := _energy_count(1)
	game.end_turn()
	await wait_seconds(0.3)
	game.end_turn()
	await wait_seconds(0.5)
	assert_gte(_energy_count(1), energy, "nothing left the energy zone")


# --- relics ----------------------------------------------------------------------------------------------------------

func test_dragons_tooth_enters_equipped_and_gives_savage() -> void:
	await _to_main()
	var host := await put_creature(1, "Righteous Guard")
	var tooth := await put_in_hand(1, "Dragon's Tooth")
	assert_true(game.play_from_hand(tooth))
	await wait_seconds(0.3)
	assert_eq(game.equip.host_of(tooth), host)
	assert_eq(game.keywords.value(host, "Savage"), 1)
	var other := await put_creature(1, "Righteous Guard")
	assert_eq(game.keywords.value(other, "Savage"), 0)


func test_dragons_tooth_without_a_creature_stays_unequipped() -> void:
	await _to_main()
	var tooth := await put_in_hand(1, "Dragon's Tooth")
	assert_true(game.play_from_hand(tooth))
	await wait_seconds(0.3)
	assert_eq(FateZones.zone_of(tooth), "relics")
	assert_null(game.equip.host_of(tooth))


func test_war_gauntlets_give_savage_and_indomitable_only_when_attacking() -> void:
	await _to_main()
	var host := await put_creature(1, "Righteous Guard")
	var gauntlets := await put_in_hand(1, "Teshra's War Gauntlets")
	assert_true(game.play_from_hand(gauntlets))
	await wait_seconds(0.3)
	assert_eq(game.equip.host_of(gauntlets), host)
	assert_eq(game.keywords.value(host, "Savage"), 0, "not attacking")
	assert_false(game.keywords.has(host, "Indomitable"))
	host.entered_turn = 0
	await start_combat()
	game.combat.declare_attack(host, game.player(2))
	assert_eq(game.keywords.value(host, "Savage"), 1, "attacking")
	assert_true(game.keywords.has(host, "Indomitable"))


# --- Primal Wraith -------------------------------------------------------------------------------------------------

func test_primal_wraith_gives_my_creatures_savage_until_end_of_turn() -> void:
	await _to_main()
	var mine := await put_creature(1, "Righteous Guard")
	var beast := await put_creature(1, "Feracious Beast")
	var theirs := await put_creature(2, "Righteous Guard")
	var spell := await put_in_hand(1, "Primal Wraith")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.2)
	assert_eq(game.keywords.value(mine, "Savage"), 1)
	assert_eq(game.keywords.value(beast, "Savage"), 3, "adds to Savage 2")
	assert_eq(game.keywords.value(theirs, "Savage"), 0)
	game.end_turn()
	assert_eq(game.keywords.value(mine, "Savage"), 0, "until end of turn")


# --- Cycle of Life --------------------------------------------------------------------------------------------------

func test_cycle_of_life_moves_the_first_discarded_card_to_energy() -> void:
	await _to_main()
	await put_on_table(1, "Cycle of Life", "field")
	var first := await put_in_hand(1, "Primal Wraith")
	assert_true(game.play_from_hand(first))
	await wait_seconds(0.4)
	assert_true(_in_energy(first, 1), "the resolved spell went to the energy zone")
	# once during the turn: the second card stays in the discard pile
	var victim := await put_creature(1, "Righteous Guard")
	game.effects.destroy(victim, null, "effect")
	await wait_seconds(0.4)
	assert_eq(victim.get_parent(), FateZones.container("discard", 1))


func test_cycle_of_life_ignores_the_opponents_discard_and_other_turns() -> void:
	await _to_main()
	await put_on_table(1, "Cycle of Life", "field")
	var theirs := await put_creature(2, "Righteous Guard")
	game.effects.destroy(theirs, null, "effect")
	await wait_seconds(0.4)
	assert_eq(theirs.get_parent(), FateZones.container("discard", 2), "not my discard pile")
	game.end_turn()
	await wait_seconds(0.3)
	var mine := await put_creature(1, "Righteous Guard")
	game.effects.destroy(mine, null, "effect")
	await wait_seconds(0.4)
	assert_eq(mine.get_parent(), FateZones.container("discard", 1), "not my turn")


# --- Return to Nature ----------------------------------------------------------------------------------------------

func test_return_to_nature_puts_a_relic_into_its_owners_energy() -> void:
	await _to_main()
	var relic := await put_on_table(2, "Dragon's Tooth", "relics")
	var spell := await put_in_hand(1, "Return to Nature")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	assert_true(_in_energy(relic, 2), "the owner's energy zone")
	assert_true(relic.is_energy)


func test_return_to_nature_releases_an_equipped_relic() -> void:
	await _to_main()
	var host := await put_creature(2, "Righteous Guard")
	var relic := await put_on_table(2, "Dragon's Tooth", "relics")
	assert_true(game.equip.equip(relic, host))
	var spell := await put_in_hand(1, "Return to Nature")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	assert_true(_in_energy(relic, 2))
	assert_eq(game.equip.relics_on(host).size(), 0)
	assert_eq(FateZones.zone_of(host), "creatures", "the creature stays")


func test_return_to_nature_takes_a_field_spell_and_needs_a_target() -> void:
	await _to_main()
	var spell := await put_in_hand(1, "Return to Nature")
	assert_false(game.play_from_hand(spell), "nothing to target")
	assert_eq(spell.get_parent(), FateZones.container("hand", 1))
	var field := await put_on_table(2, "Cycle of Life", "field")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	assert_true(_in_energy(field, 2))


# --- Second Calling -----------------------------------------------------------------------------------------------

func test_second_calling_returns_a_creature_as_a_ghost() -> void:
	await _to_main()
	var creature := await put_creature(1, "Righteous Guard")
	game.effects.destroy(creature, null, "effect")
	await wait_seconds(0.3)
	assert_eq(FateZones.zone_of(creature), "")
	var spell := await put_in_hand(1, "Second Calling")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.4)
	assert_eq(FateZones.zone_of(creature), "creatures")
	assert_true("Ghost" in creature.properties.get("Tags", []))


func test_second_calling_needs_a_creature_in_my_discard_pile() -> void:
	await _to_main()
	var theirs := await put_creature(2, "Righteous Guard")
	game.effects.destroy(theirs, null, "effect")
	await wait_seconds(0.3)
	var spell := await put_in_hand(1, "Second Calling")
	assert_false(game.play_from_hand(spell), "only my own discard pile counts")
	assert_eq(spell.get_parent(), FateZones.container("hand", 1))
