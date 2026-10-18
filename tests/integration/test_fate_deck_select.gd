extends "res://tests/FateCommon.gd"
# The deck catalogue (FateDecks.presets) and the deck selection of the two-player game: what a player can
# pick, that every deck is legal, that the choice reaches the table, and the selection screen itself.

const SELECT_SCENE := preload("res://src/custom/fate/FateDeckSelect.tscn")


func before_all() -> void:
	FateGame.register_cards()


func after_each() -> void:
	FateDecks.clear_selection()


# --- the catalogue ------------------------------------------------------------------------------------------------

func test_every_domain_has_an_optimised_and_a_starter_deck() -> void:
	var presets := FateDecks.presets()
	assert_eq(presets.size(), 8)
	var ids := presets.map(func(p): return p.id)
	for domain in FateDecks.DOMAIN_ORDER:
		assert_true(FateDecks.preset_id_of(domain, FateDecks.TIER_OPTIMISED) in ids, domain)
		assert_true(FateDecks.preset_id_of(domain, FateDecks.TIER_STARTER) in ids, domain)
	var unique := {}
	for id in ids:
		unique[id] = true
	assert_eq(unique.size(), ids.size(), "ids are unique")


func test_every_deck_of_the_catalogue_follows_the_deck_rules() -> void:
	for preset in FateDecks.presets():
		assert_eq(FateDecks.problems(preset.list, [preset.domain]), [], preset.id)
		var total := 0
		for card_name in preset.list:
			total += preset.list[card_name]
		assert_eq(total, FateDecks.DECK_SIZE, preset.id)


func test_the_optimised_decks_differ_from_the_starters_and_each_has_a_name_and_a_description() -> void:
	for domain in FateDecks.DOMAIN_ORDER:
		var optimised := FateDecks.preset(FateDecks.preset_id_of(domain, FateDecks.TIER_OPTIMISED))
		var starter := FateDecks.preset(FateDecks.preset_id_of(domain, FateDecks.TIER_STARTER))
		assert_ne(optimised.list, starter.list, domain)
		assert_ne(optimised.name, "")
		assert_gt(optimised.blurb.length(), 30, "%s has a description" % domain)
		assert_ne(optimised.blurb, "placeholder")


func test_an_unknown_preset_is_refused() -> void:
	assert_eq(FateDecks.preset("nope"), {})
	assert_false(FateDecks.select(1, "nope"))
	assert_eq(FateGame.domain_override, {})


func test_the_type_counts_add_up_to_the_deck() -> void:
	var counts := FateDecks.type_counts(FateDecks.preset("order_optimised").list)
	var total := 0
	for t in counts:
		total += counts[t]
	assert_eq(total, FateDecks.DECK_SIZE)
	assert_gt(counts.get("Creature", 0), 10, "an army")


# Replaces the table the base class built with one that plays the chosen decks
func _new_table_with(first: String, second: String) -> void:
	main.queue_free()
	await get_tree().process_frame
	FateDecks.select(1, first)
	FateDecks.select(2, second)
	await before_each()


# --- the selection reaches the table -----------------------------------------------------------------------------

func test_select_sets_the_domain_and_the_deck_list_of_a_player() -> void:
	assert_true(FateDecks.select(2, "chaos_optimised"))
	assert_eq(FateGame.domain_override[2], ["Chaos"])
	assert_eq(FateGame.decklist_override[2], FateDecks.preset("chaos_optimised").list)
	FateDecks.clear_selection()
	assert_eq(FateGame.domain_override, {})
	assert_eq(FateGame.decklist_override, {})


func test_a_table_plays_the_chosen_decks() -> void:
	await _new_table_with("chaos_optimised", "innovation_optimised")
	assert_eq(game.player(1).domains, ["Chaos"])
	assert_eq(game.player(2).domains, ["Innovation"])
	for pid in [1, 2]:
		var wanted: Dictionary = FateDecks.preset(["", "chaos_optimised", "innovation_optimised"][pid]).list
		var found := {}
		for zone in ["deck", "hand"]:
			for card in FateZones.container(zone, pid).get_all_cards():
				found[card.canonical_name] = found.get(card.canonical_name, 0) + 1
		assert_eq(found, wanted, "player %d holds the cards of the chosen list" % pid)


func test_without_a_selection_the_table_plays_order_against_primal() -> void:
	assert_eq(game.player(1).domains, ["Order"])
	assert_eq(game.player(2).domains, ["Primal"])


# --- the screen ---------------------------------------------------------------------------------------------------

func test_the_screen_starts_with_the_default_pairing_and_shows_the_decks() -> void:
	var screen = SELECT_SCENE.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	assert_eq(screen.choice, {1: "order_optimised", 2: "primal_optimised"})
	assert_eq(screen.presets.size(), 8)
	for pid in [1, 2]:
		var text: String = screen._details[pid].text
		assert_true("Mana curve" in text)
		assert_true(FateDecks.preset(screen.choice[pid]).name in text)


func test_choosing_and_swapping_decks_on_the_screen() -> void:
	var screen = SELECT_SCENE.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	assert_true(screen.select(1, "chaos_optimised"))
	assert_true(screen._buttons[1]["chaos_optimised"].button_pressed)
	assert_false(screen._buttons[1]["order_optimised"].button_pressed, "one deck per player")
	assert_false(screen.select(2, "nope"))
	assert_eq(screen.choice[2], "primal_optimised", "an unknown deck changes nothing")
	screen.swap_decks()
	assert_eq(screen.choice, {1: "primal_optimised", 2: "chaos_optimised"})
	assert_true("Abyssal" in screen._details[2].text or FateDecks.preset("chaos_optimised").name in screen._details[2].text)
