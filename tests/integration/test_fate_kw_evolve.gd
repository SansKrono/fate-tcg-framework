extends "res://tests/FateCommon.gd"
# Tests of Evolve / Evolution X (src/custom/fate/keywords/KwEvolve.gd). Rules: docs/FATE_TCG_DESIGN.md Section 9.1
# and Section 12 item 6. The creature is Beetle Brawler ("Evolution 2 (Ironside Beetle)", listed in `_keywords` only).
# Player 1 is the active player; the tests go to the MAIN phase first.

const BRAWLER := "Beetle Brawler"
const BEETLE := "Ironside Beetle"

var kw


func before_each():
	await super.before_each()
	kw = game.keywords.get_keyword("Evolution")


func _count_in_deck(pid: int, card_name: String) -> int:
	var n := 0
	for c in FateZones.container("deck", pid).get_all_cards():
		if c.canonical_name == card_name:
			n += 1
	return n


# Removes every copy of a card from a deck (to the removed pile), then puts `copies` back
func _set_copies(pid: int, card_name: String, copies: int) -> void:
	for c in FateZones.container("deck", pid).get_all_cards():
		if c.canonical_name == card_name:
			c.move_to(FateZones.container("removed", pid), -1, null, ["Scripted"])
	await wait_seconds(0.2)
	for _i in range(copies):
		await game.place_in_container(card_name, pid, "deck")


func _setup(copies := 1, mana := 3) -> Card:
	go_to_main()
	await _set_copies(1, BEETLE, copies)
	await fill_mana(1, mana)
	return await put_creature(1, BRAWLER)


func _ids(card: Card) -> Array:
	return game.actions.list(card).map(func(a): return a.id)


# --- the ability --------------------------------------------------------------------------------------

func test_the_keyword_is_registered_and_reads_the_text():
	assert_not_null(kw)
	assert_true(kw.universal)
	var brawler := await put_creature(1, BRAWLER)
	assert_true(kw.has_ability(brawler))
	assert_eq(kw.evolves_into(brawler), BEETLE)
	assert_eq(kw.cost_of(brawler), 2, "X from 'Evolution 2'")
	var plain := await put_creature(1, 2, 2)
	assert_false(kw.has_ability(plain))
	assert_eq(kw.evolves_into(plain), "")
	assert_false(kw.has_ability(await put_creature(1, BEETLE)), "Ironside Beetle does not evolve")


func test_text_without_a_cost_is_free_and_the_keyword_value_wins():
	var brawler := await put_creature(1, BRAWLER)
	brawler.properties["Abilities"] = "Evolve (Ironside Beetle)"
	assert_eq(kw.cost_of(brawler), 0)
	assert_eq(kw.evolves_into(brawler), BEETLE)
	game.stats.grant_keyword(brawler, "Evolution", 4, "permanent")
	assert_eq(kw.cost_of(brawler), 4, "A keyword value is X")


# --- evolving -----------------------------------------------------------------------------------------

func test_evolve_pays_discards_fetches_and_gives_charge():
	var brawler := await _setup()
	var before := _count_in_deck(1, BEETLE)
	assert_eq(before, 1)
	var deck_size: int = FateZones.container("deck", 1).get_all_cards().size()
	var mana_before := total_mana(game.mana_pool(1))
	var fetched = kw.evolve(brawler)
	await get_tree().process_frame
	assert_not_null(fetched)
	assert_eq(fetched.canonical_name, BEETLE)
	assert_eq(FateZones.zone_of(fetched), "creatures", "On the creature zone")
	assert_eq(fetched.card_rotation, 0, "Upright")
	assert_true(fetched.is_faceup, "Face-up on the table")
	assert_eq(fetched.entered_turn, game.turn_number)
	assert_eq(FateZones.container("discard", 1).get_all_cards().count(brawler), 1, "The brawler is in the discard pile")
	assert_eq(_count_in_deck(1, BEETLE), 0, "The beetle left the deck")
	assert_eq(FateZones.container("deck", 1).get_all_cards().size(), deck_size - 1)
	assert_eq(total_mana(game.mana_pool(1)), mana_before - 2, "X = 2 mana paid")
	assert_true(game.keywords.has(fetched, "Charge"), "Charge until end of turn")
	assert_true(game.keywords.can_attack(fetched), "...so it may attack at once")


func test_the_new_creature_can_attack_the_turn_it_evolves_and_charge_ends_with_the_turn():
	var brawler := await _setup()
	var fetched: Card = kw.evolve(brawler)
	await get_tree().process_frame
	assert_true(game.keywords.can_attack(fetched))
	game.stats.expire("end_of_turn")
	assert_false(game.keywords.has(fetched, "Charge"), "Charge is gone at the end of the turn")
	assert_false(game.keywords.can_attack(fetched), "Summoning sick again")


func test_the_hover_action_evolves():
	var brawler := await _setup()
	assert_true("evolve" in _ids(brawler))
	assert_true(await game.actions.run(brawler, "evolve"))
	await get_tree().process_frame
	var found := false
	for c in game.player(1).cards_in_grid("creatures"):
		found = found or c.canonical_name == BEETLE
	assert_true(found)


func test_on_enter_of_the_new_creature_runs_once():
	var brawler := await _setup()
	var script_class := GDScript.new()
	script_class.source_code = "extends \"res://src/custom/fate/cards/FateCardEffect.gd\"\nvar entered := []\nfunc on_enter(card):\n\tentered.append(card)\n"
	script_class.reload()
	var recorder = script_class.new()
	recorder.card_name = BEETLE
	game.card_effects.register(recorder)
	var fetched = kw.evolve(brawler)
	await wait_seconds(0.2)
	assert_eq(recorder.entered, [fetched], "on_enter ran exactly once for the new creature")


func test_the_deck_is_shuffled_with_the_game_rng():
	var brawler := await _setup()
	var pile = FateZones.container("deck", 1)
	var before: Array = pile.get_all_cards().duplicate()
	before.erase(before.filter(func(c): return c.canonical_name == BEETLE)[0])
	var order_before: Array = before.map(func(c): return c.get_instance_id())
	kw.evolve(brawler)
	await get_tree().process_frame
	var after: Array = pile.get_all_cards().map(func(c): return c.get_instance_id())
	assert_eq(after.size(), order_before.size())
	var same: Array = after.duplicate()
	same.sort()
	var sorted_before: Array = order_before.duplicate()
	sorted_before.sort()
	assert_eq(same, sorted_before, "The same cards are still in the deck")
	assert_ne(after, order_before, "In a different order")


# --- when it cannot ---------------------------------------------------------------------------------------

func test_nothing_happens_when_the_card_is_not_in_the_deck():
	var brawler := await _setup(0)
	assert_ne(kw.evolve_problem(brawler), "")
	assert_null(kw.evolve(brawler))
	assert_eq(FateZones.zone_of(brawler), "creatures", "The brawler stays")
	assert_eq(total_mana(game.mana_pool(1)), 6, "Nothing was charged")
	assert_false("evolve" in _ids(brawler))


func test_not_enough_mana_not_the_main_phase_not_your_turn():
	var brawler := await _setup(1, 0)
	assert_eq(kw.evolve_problem(brawler), "Not enough mana")
	assert_null(kw.evolve(brawler))
	await fill_mana(1, 1)
	assert_eq(kw.evolve_problem(brawler), "", "2 mana is enough")
	game.advance_phase()
	assert_ne(game.phase, FateGame.Phase.MAIN)
	assert_eq(kw.evolve_problem(brawler), "You can only evolve in your main phase")
	assert_eq(kw.evolve_problem(brawler, true), "", "free skips the phase")
	assert_not_null(kw.evolve(brawler, true))
	assert_eq(total_mana(game.mana_pool(1)), 2, "...and the payment")


func test_a_creature_you_do_not_own_cannot_evolve():
	var brawler := await _setup()
	brawler.controller_id = 2
	assert_ne(kw.evolve_problem(brawler, true), "")


func test_only_creatures_in_play_can_evolve():
	go_to_main()
	await _set_copies(1, BEETLE, 1)
	var in_hand := await put_in_hand(1, BRAWLER)
	assert_eq(kw.evolve_problem(in_hand, true), "Only a creature in play can evolve")


func test_an_occupied_creature_can_evolve_into_the_creature_zone():
	go_to_main()
	await _set_copies(1, BEETLE, 1)
	await fill_mana(1, 3)
	var brawler := await put_creature(1, BRAWLER, 1, {}, false, "occupied")
	assert_eq(FateZones.zone_of(brawler), "occupied")
	var fetched = kw.evolve(brawler)
	await get_tree().process_frame
	assert_not_null(fetched)
	assert_eq(FateZones.zone_of(fetched), "creatures")
	assert_eq(fetched.card_rotation, 0)


func test_the_creature_zone_full_blocks_an_occupied_evolution():
	go_to_main()
	await _set_copies(1, BEETLE, 1)
	await fill_mana(1, 3)
	var brawler := await put_creature(1, BRAWLER, 1, {}, false, "occupied")
	while game.player(1).grid("creatures").find_available_slot() != null:
		await put_creature(1, 1, 1)
	assert_eq(kw.evolve_problem(brawler), "The creature zone is full")
	assert_eq(FateZones.zone_of(brawler), "occupied")


func test_a_full_creature_zone_still_evolves_from_a_creature_in_it():
	go_to_main()
	await _set_copies(1, BEETLE, 1)
	await fill_mana(1, 3)
	var brawler := await put_creature(1, BRAWLER)
	while game.player(1).grid("creatures").find_available_slot() != null:
		await put_creature(1, 1, 1)
	var fetched = kw.evolve(brawler)
	await wait_seconds(0.3)
	assert_not_null(fetched, "the evolving creature's own slot is reused")
	assert_eq(FateZones.zone_of(fetched), "creatures")
	assert_eq(FateZones.zone_of(brawler), "")
	assert_eq(fetched._placement_slot.occupying_card, fetched, "the late cleanup did not wipe the new card")
