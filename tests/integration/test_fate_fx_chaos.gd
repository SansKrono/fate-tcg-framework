extends "res://tests/FateCommon.gd"
# Chaos card scripts (cards/Fx*.gd). Spells are cast from the discard pile without paying so that the test
# does not depend on the mana domains of the players.

const ENERGY_CARD := "Holy Amulet"


func _hand(pid := 1) -> int:
	return FateZones.container("hand", pid).get_all_cards().size()


func _discard(card_name: String, pid := 1) -> Card:
	return await game.place_in_container(card_name, pid, "discard")


# The default pick is the first castable energy card (a relic): make the next picks take `card`
func _prefer(card: Card) -> void:
	game.choices.chooser = func(request): return card if card in request.options else null


func _cast_free(card: Card, pid := 1) -> bool:
	var ok: bool = await game.casting.cast_from_discard(card, pid, false)
	await wait_seconds(0.1)
	return ok


func test_harbinger_takes_a_cheap_creature_when_it_dies() -> void:
	var harbinger := await put_creature(1, "Harbinger of Krelgar")
	var cheap := await put_creature(2, "Enthralled Civilian")
	var dear := await put_creature(2, "Ikthar, The Great Summoner")
	var cheap_value: int = cheap.mana_value()
	assert_lt(cheap_value, 3, "Test setup: Moral Captain is cheap")
	game.effects.destroy(harbinger)
	await wait_seconds(0.2)
	assert_eq(cheap.controller_id, 1)
	assert_eq(dear.controller_id, 2, "mana value 3+ stays")


func test_harbinger_with_no_legal_target_does_nothing() -> void:
	var harbinger := await put_creature(1, "Harbinger of Krelgar")
	var dear := await put_creature(2, "Ikthar, The Great Summoner")
	game.effects.destroy(harbinger)
	await wait_seconds(0.2)
	assert_eq(dear.controller_id, 2)


func test_unseen_manipulator_converts_or_draws() -> void:
	await empty_hand(1)
	var victim := await put_creature(2, "Moral Captain")
	var unique := await put_creature(2, "Ikthar, The Great Summoner")
	var mani := await put_creature(1, "Unseen Manipulator")
	game.card_effects.card_entered(mani)
	await wait_seconds(0.2)
	assert_eq(victim.controller_id, 1, "default mode: convert the first non-unique creature")
	assert_eq(unique.controller_id, 2)
	# Intel when asked, and when there is nothing to convert
	await empty_hand(1)
	game.choices.chooser = func(request): return "Intel" if "Intel" in request.options else null
	var mani2 := await put_creature(1, "Unseen Manipulator")
	game.card_effects.card_entered(mani2)
	await wait_seconds(0.2)
	game.choices.chooser = Callable()
	assert_eq(_hand(1), 2)


func test_eldritch_knowledge_draws_on_a_flip_cast() -> void:
	await empty_hand(1)
	await put_on_table(1, "Eldritch Knowledge", "field")
	var energy := await put_energy(1, ENERGY_CARD)
	await put_energy(1, ENERGY_CARD)
	var echo := await put_energy(1, "Unending Echo")
	var ok: bool = await game.casting.flip_cast_card(echo, 1, false)
	await wait_seconds(0.2)
	assert_true(ok)
	assert_eq(_hand(1), 1)
	assert_not_null(energy)


func test_delve_puts_a_card_on_the_bottom_and_draws_two() -> void:
	await empty_hand(1)
	var keep := await put_in_hand(1, "Moral Captain")
	var spell := await _discard("Delve into the Beyond")
	var deck_before: int = FateZones.container("deck", 1).get_all_cards().size()
	assert_true(await _cast_free(spell))
	assert_eq(keep.get_parent(), FateZones.container("deck", 1))
	assert_eq(FateZones.container("deck", 1).get_all_cards()[0], keep, "bottom of the deck")
	assert_eq(_hand(1), 2)
	assert_eq(FateZones.container("deck", 1).get_all_cards().size(), deck_before - 1)


func test_deep_thought_takes_one_of_the_top_two() -> void:
	await empty_hand(1)
	var top: Array = game.library.look_top(1, 2)
	var spell := await _discard("Deep Thought")
	assert_true(await _cast_free(spell))
	assert_eq(_hand(1), 1)
	assert_eq(top[0].get_parent(), FateZones.container("hand", 1))
	assert_eq(FateZones.container("deck", 1).get_all_cards()[0], top[1], "the other is on the bottom")


func test_claimed_by_the_abyss_puts_a_creature_in_my_energy_zone() -> void:
	var victim := await put_creature(2, "Moral Captain")
	var spell := await _discard("Claimed by the Abyss")
	assert_true(await _cast_free(spell))
	assert_eq(FateZones.zone_of(victim), "energy")
	assert_eq(victim.controller_id, 1)
	assert_eq(victim.owner_id, 2)


func test_claimed_by_the_abyss_needs_a_creature() -> void:
	var spell := await _discard("Claimed by the Abyss")
	assert_false(await _cast_free(spell), "no creature, no cast")


func test_repurpose_moves_a_discard_card_to_my_energy_zone() -> void:
	var target := await _discard("Moral Captain", 2)
	var spell := await _discard("Repurpose")
	assert_true(await _cast_free(spell))
	assert_eq(FateZones.zone_of(target), "energy")
	assert_eq(target.controller_id, 1)


func test_unforgotten_sacrifice_casts_free_then_adds_the_top_card() -> void:
	await put_energy(1, ENERGY_CARD)
	var echo := await put_energy(1, "Unending Echo")
	var top: Card = game.library.look_top(1, 1)[0]
	var spell := await _discard("Unforgotten Sacrifice")
	_prefer(echo)
	assert_true(await _cast_free(spell))
	game.choices.chooser = Callable()
	assert_eq(FateZones.zone_of(echo), "creatures", "flip cast for free")
	assert_eq(FateZones.zone_of(top), "energy")


func test_unending_echo_offers_a_cast_from_the_discard_pile() -> void:
	go_to_main()
	await put_energy(1, "Murkmist Gemstone")
	await put_energy(1, "Murkmist Gemstone")
	var echo := await _discard("Unending Echo")
	var action := game.actions.find(echo, "cast_from_discard")
	assert_false(action.is_empty())
	assert_true(await game.actions.run(echo, "cast_from_discard"))
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(echo), "creatures")


func test_ikthar_consumes_an_enemy_creature_and_tutors_a_unique() -> void:
	await empty_hand(1)
	go_to_main()
	var ikthar := await put_creature(1, "Ikthar, The Great Summoner")
	ikthar.entered_turn = 0
	var enemy := await put_creature(2, "Moral Captain")
	var unique := await game.place_in_container("Thrang, Perpetual Innovation", 1, "deck")
	var action := game.actions.find(ikthar, "summon")
	assert_false(action.is_empty())
	assert_true(await game.actions.run(ikthar, "summon"))
	await wait_seconds(0.2)
	assert_eq(enemy.get_parent(), FateZones.container("discard", 2))
	assert_eq(unique.get_parent(), FateZones.container("hand", 1))


func test_krelga_returns_what_it_destroys_and_goes_to_energy_when_destroyed() -> void:
	var krelga := await put_creature(1, "Krelga, Abyssal Nightmare")
	var victim := await put_creature(2, "Moral Captain")
	game.effects.destroy(victim, krelga)
	await wait_seconds(0.2)
	assert_eq(victim.controller_id, 1)
	assert_eq(FateZones.zone_of(victim), "creatures")
	var other := await put_creature(2, "Righteous Guard")
	game.effects.destroy(other, null)
	await wait_seconds(0.2)
	assert_eq(other.get_parent(), FateZones.container("discard", 2), "only Krelga's kills return")
	game.effects.destroy(krelga)
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(krelga), "energy")


func test_dockside_alter_consumes_a_creature_and_flip_casts() -> void:
	go_to_main()
	for _i in range(3):
		await put_energy(1, "Murkmist Gemstone")
	var alter := await put_on_table(1, "Dockside Alter", "relics")
	var fodder := await put_creature(1, "Righteous Guard")
	var echo := await put_energy(1, "Unending Echo")
	_prefer(echo)
	assert_true(await game.actions.run(alter, "alter"))
	game.choices.chooser = Callable()
	await wait_seconds(0.2)
	assert_eq(fodder.get_parent(), FateZones.container("discard", 1))
	assert_eq(FateZones.zone_of(echo), "creatures")
	assert_false(game.actions.find(alter, "alter").get("enabled", false), "once per turn")


func test_enthralled_civilian_casts_a_mana_card() -> void:
	go_to_main()
	for _i in range(3):
		await put_energy(1, "Murkmist Gemstone")
	var civ := await put_creature(1, "Enthralled Civilian")
	civ.entered_turn = 0
	var echo := await put_energy(1, "Unending Echo")
	_prefer(echo)
	assert_true(await game.actions.run(civ, "cast_mana"))
	game.choices.chooser = Callable()
	await wait_seconds(0.2)
	assert_eq(civ.get_parent(), FateZones.container("discard", 1))
	assert_eq(FateZones.zone_of(echo), "creatures")


func test_dockside_ambusher_makes_the_opponent_give_a_permanent() -> void:
	await put_energy(1, ENERGY_CARD)
	await put_energy(1, ENERGY_CARD)
	await put_energy(1, ENERGY_CARD)
	var cheap := await put_creature(2, "Moral Captain")
	var dear := await put_creature(2, "Krelga, Abyssal Nightmare")
	var seen := []
	game.choices.choosers[2] = func(request):
		seen.append(request.player)
		return cheap
	var amb := await put_energy(1, "Dockside Ambusher")
	assert_true(await game.casting.flip_cast_card(amb, 1, false))
	await wait_seconds(0.2)
	game.choices.choosers.erase(2)
	assert_eq(seen, [2], "the opponent chose")
	assert_eq(FateZones.zone_of(cheap), "energy")
	assert_eq(cheap.controller_id, 1)
	assert_eq(dear.controller_id, 2)


func test_cultist_fanatic_sacrifices_itself_to_flip_cast_free() -> void:
	await put_energy(1, ENERGY_CARD)
	var echo := await put_energy(1, "Unending Echo")
	var fanatic := await put_creature(1, "Cultist Fanatic")
	_prefer(echo)
	game.effects.deal_damage(game.player(2), 1, fanatic)
	await wait_seconds(0.2)
	game.choices.chooser = Callable()
	assert_eq(fanatic.get_parent(), FateZones.container("discard", 1))
	assert_eq(FateZones.zone_of(echo), "creatures")


func test_murkmist_gemstone_takes_the_killer() -> void:
	var host := await put_creature(1, "Righteous Guard")
	var killer := await put_creature(2, "Moral Captain")
	var gem := await put_on_table(1, "Murkmist Gemstone", "relics")
	game.equip.equip(gem, host)
	game.effects.destroy(host, killer)
	await wait_seconds(0.3)
	assert_eq(killer.controller_id, 1)
