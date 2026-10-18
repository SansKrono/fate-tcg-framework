extends "res://tests/FateCommon.gd"
# Extra cards: Holy Healer, Toll of War, No Where to Hide.


func _to_main() -> void:
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()


func test_toll_of_war_destroys_only_upright_creatures() -> void:
	await _to_main()
	var up1 := await put_creature(1, "Moral Captain")
	var up2 := await put_creature(2, "Righteous Guard")
	var guard := await put_creature(2, "Righteous Guard", 1, {}, true)
	var occupied := await put_creature(2, "Righteous Guard", 1, {}, false, "occupied")
	var spell := await put_in_hand(1, "Toll of War")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(up1), "", "own upright creature destroyed too")
	assert_eq(FateZones.zone_of(up2), "")
	assert_eq(FateZones.zone_of(guard), "creatures", "guarding creature survives")
	assert_eq(FateZones.zone_of(occupied), "occupied", "occupied creature survives")


func test_no_where_to_hide_destroys_only_guarding_creatures() -> void:
	await _to_main()
	var up := await put_creature(2, "Righteous Guard")
	var guard := await put_creature(2, "Righteous Guard", 1, {}, true)
	var occupied := await put_creature(2, "Righteous Guard", 1, {}, false, "occupied")
	var spell := await put_in_hand(1, "No Where to Hide")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(guard), "")
	assert_eq(FateZones.zone_of(up), "creatures")
	assert_eq(FateZones.zone_of(occupied), "occupied")


func test_holy_healer_returns_a_creature_from_the_discard_pile() -> void:
	await _to_main()
	var dead := await game.place_in_container("Moral Captain", 1, "discard")
	var healer := await put_in_hand(1, "Holy Healer")
	assert_true(game.play_from_hand(healer))
	await wait_seconds(0.3)
	assert_eq(dead.get_parent(), FateZones.container("hand", 1))


func test_holy_healer_with_no_creature_in_the_discard_pile_does_nothing() -> void:
	await _to_main()
	var healer := await put_in_hand(1, "Holy Healer")
	var before: int = FateZones.container("hand", 1).get_all_cards().size() - 1
	assert_true(game.play_from_hand(healer))
	await wait_seconds(0.3)
	assert_eq(FateZones.zone_of(healer), "creatures")
	assert_eq(FateZones.container("hand", 1).get_all_cards().size(), before)


# --- helpers ---------------------------------------------------------------------------------------

func _action(card: Card, id: String) -> Dictionary:
	for a in game.keywords.actions(card):
		if a.id == id:
			return a
	return {}


func _relics_named(pid: int, card_name: String) -> Array:
	return game.player(pid).cards_in_grid("relics").filter(func(c): return c.canonical_name == card_name)


# --- Brogir ----------------------------------------------------------------------------------------

func test_brogir_turns_scrap_into_an_ingot() -> void:
	await _to_main()
	var brogir := await put_creature(1, "Brogir, Master Artificer")
	game.tokens.set_counter(1, "scrap", 1)
	var action := _action(brogir, "scrap_to_ingot")
	assert_true(action.enabled)
	assert_true(await action.run.call(brogir))
	assert_eq(game.tokens.counter(1, "scrap"), 0)
	assert_eq(game.tokens.counter(1, "ingot"), 1)
	assert_eq(FateZones.zone_of(brogir), "occupied", "the ability occupies")


func test_brogir_needs_the_counter_to_use_a_mode() -> void:
	await _to_main()
	var brogir := await put_creature(1, "Brogir, Master Artificer")
	assert_false(_action(brogir, "scrap_to_ingot").enabled, "no scrap")
	assert_false(_action(brogir, "ingot_to_hammer").enabled, "no ingot")


func test_brogir_turns_an_ingot_into_a_battle_hammer() -> void:
	await _to_main()
	var brogir := await put_creature(1, "Brogir, Master Artificer")
	var other := await put_creature(1, "Righteous Guard")
	game.tokens.set_counter(1, "ingot", 1)
	game.choices.chooser = func(r): return other if other in r.options else null
	assert_true(await _action(brogir, "ingot_to_hammer").run.call(brogir))
	game.choices.chooser = Callable()
	var hammers := _relics_named(1, "Battle Hammer Token")
	assert_eq(hammers.size(), 1)
	assert_eq(game.equip.host_of(hammers[0]), other)
	assert_eq(game.tokens.counter(1, "ingot"), 0)


# --- Rarink ----------------------------------------------------------------------------------------

func test_rarink_makes_scrap_when_a_non_token_relic_leaves() -> void:
	await _to_main()
	await put_creature(1, "Rarink, Crafty Opportunist")
	var relic := await put_on_table(2, "Garbage Heap", "relics")
	game.effects.destroy(relic)
	await wait_seconds(0.2)
	assert_eq(game.tokens.counter(1, "scrap"), 2, "any relic, whoever's")


func test_rarink_ignores_token_relics_and_creatures() -> void:
	await _to_main()
	await put_creature(1, "Rarink, Crafty Opportunist")
	var token = game.tokens.create("Battle Hammer Token", 1)
	var other := await put_creature(2, "Righteous Guard")
	game.effects.destroy(token)
	game.effects.destroy(other)
	await wait_seconds(0.2)
	assert_eq(game.tokens.counter(1, "scrap"), 0)


# --- Self-destruction ------------------------------------------------------------------------------

func test_self_destruction_consumes_x_of_each_side() -> void:
	await _to_main()
	for _i in 3:
		await put_creature(2, "Righteous Guard")
	var mine := await put_creature(1, "Moral Captain")
	var before = game.costs.consume_candidates(mine, game.costs.PERMANENT_ZONES, Callable(), {}).size()
	game.choices.chooser = func(r): return 2 if str(r.kind).begins_with("X") else null
	var spell := await put_in_hand(1, "Self-destruction")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.4)
	game.choices.chooser = Callable()
	assert_eq(game.creatures_in_play(2).size(), 1, "the opponent consumed 2 of 3")
	var after = game.costs.consume_candidates(mine, game.costs.PERMANENT_ZONES, Callable(), {}).size()
	assert_eq(after, before - 2, "the caster consumed 2 too")


func test_self_destruction_with_fewer_opposing_permanents_takes_what_they_have() -> void:
	await _to_main()
	await put_creature(2, "Righteous Guard")
	await put_creature(1, "Moral Captain")
	game.choices.chooser = func(r): return 3 if str(r.kind).begins_with("X") else null
	var spell := await put_in_hand(1, "Self-destruction")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.4)
	game.choices.chooser = Callable()
	assert_eq(game.creatures_in_play(2).size(), 0)


# --- Sigil Mage ------------------------------------------------------------------------------------

func test_sigil_mage_sends_only_the_first_spell_to_the_energy_zone() -> void:
	await _to_main()
	await put_creature(1, "Sigil Mage")
	var first := await put_in_hand(1, "Rapid Scavenging")
	var second := await put_in_hand(1, "Rapid Scavenging")
	assert_true(game.play_from_hand(first))
	await wait_seconds(0.3)
	assert_eq(FateZones.zone_of(first), "energy")
	assert_true(game.play_from_hand(second))
	await wait_seconds(0.3)
	assert_eq(second.get_parent(), FateZones.container("discard", 1))


func test_the_opponents_sigil_mage_does_not_redirect_my_spell() -> void:
	await _to_main()
	await put_creature(2, "Sigil Mage")
	var spell := await put_in_hand(1, "Rapid Scavenging")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))


# --- Insightful Investigator -----------------------------------------------------------------------

func test_investigator_can_bottom_the_top_cards_of_a_library() -> void:
	await _to_main()
	var deck = FateZones.container("deck", 2)
	var top_before = game.library.look_top(2, 2)
	game.choices.chooser = func(r): return game.player(2) if r.kind == "target player" else null
	game.choices.confirmer = func(_r): return true
	var card := await put_in_hand(1, "Insightful Investigator")
	assert_true(game.play_from_hand(card))
	await wait_seconds(0.4)
	game.choices.chooser = Callable()
	game.choices.confirmer = Callable()
	var bottom: Array = deck.get_all_cards().slice(0, 2)
	assert_true(top_before[0] in bottom and top_before[1] in bottom, "both went to the bottom")


func test_investigator_keeps_the_cards_by_default() -> void:
	await _to_main()
	var top_before = game.library.look_top(1, 2)
	game.choices.confirmer = func(_r): return false
	var card := await put_in_hand(1, "Insightful Investigator")
	assert_true(game.play_from_hand(card))
	await wait_seconds(0.4)
	game.choices.confirmer = Callable()
	assert_eq(game.library.look_top(1, 2), top_before)


# --- Unseen Reach ----------------------------------------------------------------------------------

func test_unseen_reach_makes_a_creature_unblockable_for_the_turn() -> void:
	await _to_main()
	var runner := await put_creature(1, "Moral Captain")
	await put_on_table(1, "Unseen Reach", "field")
	var blocker := await put_creature(2, "Righteous Guard", 1, {}, true)
	game.advance_phase()
	await wait_seconds(0.2)
	assert_eq(game.phase, FateGame.Phase.COMBAT_DECLARE)
	assert_true(game.keywords.has(runner, "Unblockable"))
	assert_true(game.combat.declare_attack(runner, game.player(2)))
	game.combat.confirm_attackers()
	await wait_seconds(0.1)
	assert_false(blocker in game.combat.eligible_blockers(game.combat.attacks[0]), "cannot be blocked")


func test_unseen_reach_does_nothing_on_the_opponents_turn_setup() -> void:
	await _to_main()
	var theirs := await put_creature(2, "Moral Captain")
	await put_on_table(1, "Unseen Reach", "field")
	game.advance_phase()
	await wait_seconds(0.2)
	assert_false(game.keywords.has(theirs, "Unblockable"))


# --- Goblin Scout Leader ---------------------------------------------------------------------------

func test_goblin_scout_leader_creates_a_goblin_when_it_attacks() -> void:
	await _to_main()
	var leader := await put_creature(1, "Goblin Scout Leader")
	game.advance_phase()
	await wait_seconds(0.1)
	assert_true(game.combat.declare_attack(leader, game.player(2)))
	game.combat.confirm_attackers()
	await wait_seconds(0.2)
	var goblins := game.creatures_in_play(1).filter(func(c): return c.canonical_name == "Goblin Token")
	assert_eq(goblins.size(), 1)
	assert_eq(goblins[0].card_rotation, 0, "strike position")


# --- Battering Ram ---------------------------------------------------------------------------------

func test_battering_ram_destroys_an_unblocked_relic() -> void:
	await _to_main()
	var ram := await put_creature(1, "Battering Ram")
	var relic := await put_on_table(2, "Garbage Heap", "relics")
	game.advance_phase()
	await wait_seconds(0.1)
	assert_true(game.combat.declare_attack(ram, relic), game.combat.last_error)
	run_combat()
	await wait_seconds(0.3)
	assert_eq(FateZones.zone_of(relic), "", "the relic was destroyed")
	assert_eq(game.stats.current(ram, "Strike"), 3, "the ram took no damage")


func test_other_creatures_cannot_attack_relics() -> void:
	await _to_main()
	var other := await put_creature(1, "Moral Captain")
	var relic := await put_on_table(2, "Garbage Heap", "relics")
	game.advance_phase()
	await wait_seconds(0.1)
	assert_false(game.combat.declare_attack(other, relic))
	var own := await put_on_table(1, "Garbage Heap", "relics")
	var ram := await put_creature(1, "Battering Ram")
	assert_false(game.combat.declare_attack(ram, own), "not your own relic")


# --- Broadening Influence --------------------------------------------------------------------------

func test_broadening_influence_offers_the_top_of_an_opponents_library_as_energy() -> void:
	await put_on_table(2, "Broadening Influence", "world")
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	var offers: Array = game.energy_alternatives()
	assert_eq(offers.size(), 1)
	var top: Card = game.library.look_top(2, 1)[0]
	var energy_before: int = game.player(1).cards_in_grid("energy").size()
	assert_true(game.use_energy_alternative(offers[0].host))
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(top), "energy")
	assert_eq(top.controller_id, 1)
	assert_eq(top.owner_id, 2)
	assert_eq(game.player(1).cards_in_grid("energy").size(), energy_before + 1)
	assert_eq(game.energy_choice, FateGame.CHOICE_ENERGY)
	assert_eq(game.phase, FateGame.Phase.MAIN, "the energy phase is over")


func test_broadening_influence_is_not_offered_once_the_choice_is_made() -> void:
	await put_on_table(2, "Broadening Influence", "world")
	game.draw_extra_card()
	assert_eq(game.energy_alternatives().size(), 0)
	assert_false(game.use_energy_alternative(game.card_effects.table_cards()[0]))


func test_there_is_no_offer_without_the_world_spell() -> void:
	assert_eq(game.energy_alternatives().size(), 0)
