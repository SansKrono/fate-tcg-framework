extends "res://tests/FateCommon.gd"
# The library verbs (src/custom/fate/FateLibrary.gd, game.library): draw, look, search, shuffle, the zone moves,
# to_energy, discard_from_hand, the empty-deck loss and a spell redirected to the energy zone.


# Logs what a card script hears about a card (for the "card left the table" bookkeeping)
class Recorder:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var log: Array = []
	var destination := ""

	func _init(name_of_card := "") -> void:
		card_name = name_of_card

	func on_leave(_card: Card, dest: String) -> void:
		log.append(["leave", dest])

	func on_enter(_card: Card) -> void:
		log.append(["enter"])

	func spell_destination(_card: Card, _caster_id: int) -> String:
		return destination


func _deck(pid: int) -> Pile:
	return FateZones.container("deck", pid)


func _hand(pid: int) -> Hand:
	return FateZones.container("hand", pid)


func _pile(zone: String, pid: int) -> Pile:
	return FateZones.container(zone, pid)


func _in_energy(card: Card, pid: int) -> bool:
	return FateZones.zone_of(card) == "energy" and card._placement_slot.owner_grid == FateZones.grid("energy", pid)


# Every card of a player's deck moved to the removed pile (an empty deck)
func _empty_deck(pid: int) -> void:
	for c in _deck(pid).get_all_cards():
		c.move_to(_pile("removed", pid), -1, null, ["Scripted"])
	await wait_seconds(0.3)


func _names(cards: Array) -> Array:
	return cards.map(func(c): return c.canonical_name)


# --- draw ----------------------------------------------------------------------------------------

func test_draw_moves_the_top_cards_to_the_hand() -> void:
	await empty_hand(1)
	var top := _deck(1).get_all_cards().slice(-2)
	var before := _deck(1).get_card_count()
	var drawn: Array = game.library.draw(1, 2)
	await wait_seconds(0.3)
	assert_eq(drawn, [top[1], top[0]], "top card first")
	assert_eq(_deck(1).get_card_count(), before - 2)
	assert_eq(_hand(1).get_card_count(), 2)
	for c in drawn:
		assert_eq(c.get_parent(), _hand(1))


func test_draw_defaults_to_one_card_and_zero_draws_nothing() -> void:
	await empty_hand(2)
	assert_eq(game.library.draw(2).size(), 1)
	assert_eq(game.library.draw(2, 0), [])
	await wait_seconds(0.2)
	assert_eq(_hand(2).get_card_count(), 1)


func test_the_hand_limit_discards_the_drawn_card() -> void:
	await empty_hand(1)
	for _i in range(10):
		await put_in_hand(1, "Moral Captain")
	assert_eq(_hand(1).get_card_count(), 10)
	var discard_before := _pile("discard", 1).get_card_count()
	var drawn: Array = game.library.draw(1)
	await wait_seconds(0.3)
	assert_eq(drawn.size(), 1)
	assert_eq(_hand(1).get_card_count(), 10, "the hand stays at the limit")
	assert_eq(_pile("discard", 1).get_card_count(), discard_before + 1)
	assert_eq(drawn[0].get_parent(), _pile("discard", 1))
	assert_false(game.is_over, "a full hand is not a loss")


func test_drawing_from_an_empty_deck_loses_the_game() -> void:
	await _empty_deck(1)
	watch_signals(game)
	var drawn: Array = game.library.draw(1)
	assert_eq(drawn, [])
	assert_signal_emitted_with_parameters(game, "deck_empty", [1])
	assert_true(game.is_over)
	assert_eq(game.winner_id, 2)
	assert_signal_emitted_with_parameters(game, "player_defeated", [1])


func test_drawing_more_than_the_deck_holds_draws_what_is_there_then_loses() -> void:
	var pile := _deck(2)
	var keep := pile.get_all_cards().slice(-2)
	for c in pile.get_all_cards():
		if c not in keep:
			c.move_to(_pile("removed", 2), -1, null, ["Scripted"])
	await wait_seconds(0.3)
	await empty_hand(2)
	var drawn: Array = game.library.draw(2, 5)
	assert_eq(drawn.size(), 2)
	assert_true(game.is_over)
	assert_eq(game.winner_id, 1)


func test_the_draw_phase_of_an_empty_deck_loses_the_game() -> void:
	await _empty_deck(1)
	watch_signals(game)
	game.turn._draw()
	assert_signal_emitted(game, "deck_empty")
	assert_true(game.is_over)
	assert_eq(game.winner_id, 2)


func test_the_extra_draw_of_the_energy_phase_from_an_empty_deck_loses_the_game() -> void:
	await _empty_deck(1)
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	watch_signals(game)
	game.draw_extra_card()
	assert_signal_emitted_with_parameters(game, "deck_empty", [1])
	assert_true(game.is_over)
	assert_eq(game.winner_id, 2)


func test_the_extra_draw_still_draws_a_card_normally() -> void:
	var before := _hand(1).get_card_count()
	assert_true(game.draw_extra_card())
	await wait_seconds(0.3)
	assert_eq(_hand(1).get_card_count(), before + 1)
	assert_false(game.is_over)


# --- look, search, shuffle ---------------------------------------------------------------------------

func test_look_top_shows_the_top_cards_without_moving_them() -> void:
	var cards := _deck(1).get_all_cards()
	var seen: Array = game.library.look_top(1, 3)
	assert_eq(seen, [cards[-1], cards[-2], cards[-3]])
	assert_eq(_deck(1).get_all_cards(), cards, "the order is unchanged")
	assert_eq(game.library.look_top(1, 0), [])
	assert_eq(game.library.look_top(1, 1000).size(), cards.size(), "more than the deck holds")
	# Any player's deck
	assert_eq(game.library.look_top(2, 1)[0], _deck(2).get_top_card())


func test_search_returns_the_matches_top_first_and_moves_nothing() -> void:
	var creatures: Array = game.library.search(1, func(c): return c.properties.get("Type") == "Creature")
	assert_gt(creatures.size(), 0)
	for c in creatures:
		assert_eq(c.properties.get("Type"), "Creature")
		assert_eq(c.get_parent(), _deck(1))
	var all: Array = game.library.search(1)
	assert_eq(all.size(), _deck(1).get_card_count(), "no filter matches everything")
	assert_eq(all[0], _deck(1).get_top_card())
	assert_eq(game.library.search(1, func(c): return false), [])


func test_search_can_look_in_the_discard_pile_and_the_hand() -> void:
	var card := await put_in_hand(1, "Moral Captain")
	var in_hand: Array = game.library.search(1, func(c): return c == card, "hand")
	assert_eq(in_hand, [card])
	game.library.to_discard(card)
	await wait_seconds(0.3)
	assert_eq(game.library.search(1, func(c): return c == card, "discard"), [card])
	assert_eq(game.library.search(1, func(c): return c == card, "deck"), [])


func test_shuffle_changes_the_order_and_a_seed_repeats_it() -> void:
	var pile := _deck(1)
	var original := pile.get_all_cards()
	cfc.game_rng.seed = 4242
	game.library.shuffle(1)
	var first := pile.get_all_cards()
	assert_ne(first, original, "the order changed")
	assert_eq(first.size(), original.size(), "no card was lost")
	# Back to the original order, same seed: the same shuffle
	for c in original:
		pile.move_child(c, pile.get_child_count() - 1)
	assert_eq(pile.get_all_cards(), original)
	cfc.game_rng.seed = 4242
	game.library.shuffle(1)
	assert_eq(pile.get_all_cards(), first, "a seeded shuffle repeats")


# --- moves -----------------------------------------------------------------------------------------

func test_to_hand_from_the_deck_the_discard_pile_and_the_table() -> void:
	await empty_hand(1)
	var from_deck: Card = _deck(1).get_top_card()
	assert_true(game.library.to_hand(from_deck))
	var creature := await put_creature(1, "Moral Captain")
	assert_true(game.library.to_hand(creature))
	var dead := await put_in_hand(1, "Righteous Guard")
	game.library.to_discard(dead)
	await wait_seconds(0.3)
	assert_true(game.library.to_hand(dead))
	await wait_seconds(0.3)
	for c in [from_deck, creature, dead]:
		assert_eq(c.get_parent(), _hand(1))
		assert_true(c.is_faceup, "face-up in the hand")
	assert_null(creature._placement_slot, "the slot is free")


func test_to_hand_of_another_player_and_of_a_stolen_card() -> void:
	await empty_hand(1)
	await empty_hand(2)
	var theirs := await put_creature(2, "Moral Captain")
	# Default: the OWNER's hand, even when the other player controls it
	theirs.controller_id = 1
	assert_true(game.library.to_hand(theirs))
	await wait_seconds(0.3)
	assert_eq(theirs.get_parent(), _hand(2))
	# `player_id` overrides it
	assert_true(game.library.to_hand(theirs, 1))
	await wait_seconds(0.3)
	assert_eq(theirs.get_parent(), _hand(1))
	assert_eq(theirs.owner_id, 2, "ownership does not change")


func test_to_hand_with_a_full_hand_discards_the_card() -> void:
	await empty_hand(1)
	for _i in range(10):
		await put_in_hand(1, "Moral Captain")
	var card: Card = _deck(1).get_top_card()
	assert_false(game.library.to_hand(card))
	await wait_seconds(0.3)
	assert_eq(card.get_parent(), _pile("discard", 1))
	assert_eq(_hand(1).get_card_count(), 10)


func test_to_deck_bottom_and_top() -> void:
	var card := await put_in_hand(1, "Moral Captain")
	assert_true(game.library.to_deck_bottom(card))
	await wait_seconds(0.3)
	assert_eq(card.get_parent(), _deck(1))
	assert_eq(_deck(1).get_bottom_card(), card, "at the bottom")
	assert_false(card.is_faceup, "decks are face-down")
	var other := await put_creature(1, "Righteous Guard")
	assert_true(game.library.to_deck_top(other))
	await wait_seconds(0.3)
	assert_eq(_deck(1).get_top_card(), other, "on top")
	assert_false(other.is_faceup)
	assert_null(other._placement_slot)
	# A card already in the deck changes its place
	assert_true(game.library.to_deck_top(card))
	assert_eq(_deck(1).get_top_card(), card)
	assert_true(game.library.to_deck_bottom(card))
	assert_eq(_deck(1).get_bottom_card(), card)
	# Another player's deck
	var mine := await put_in_hand(1, "Moral Captain")
	assert_true(game.library.to_deck_bottom(mine, 2))
	await wait_seconds(0.3)
	assert_eq(mine.get_parent(), _deck(2))
	assert_eq(mine.owner_id, 1)


func test_to_discard_and_to_removed_go_to_the_owners_pile() -> void:
	var card := await put_creature(2, "Moral Captain")
	card.controller_id = 1
	assert_true(game.library.to_discard(card))
	await wait_seconds(0.3)
	assert_eq(card.get_parent(), _pile("discard", 2), "the owner's discard pile")
	assert_true(card.is_faceup)
	var in_hand := await put_in_hand(2, "Righteous Guard")
	assert_true(game.library.to_removed(in_hand))
	await wait_seconds(0.3)
	assert_eq(in_hand.get_parent(), _pile("removed", 2))
	assert_true(game.library.to_removed(card), "from the discard pile")
	await wait_seconds(0.3)
	assert_eq(card.get_parent(), _pile("removed", 2))


func test_a_card_leaving_the_table_through_the_library_tells_its_script() -> void:
	var fx := Recorder.new("Moral Captain")
	game.card_effects.register(fx)
	var card := await put_creature(1, "Moral Captain")
	game.library.to_discard(card)
	await wait_seconds(0.3)
	assert_eq(fx.log, [["leave", "discard"]])


func test_a_token_that_leaves_the_table_ceases_to_exist() -> void:
	var token := await put_creature(1, "Soldier Token")
	assert_true(game.tokens.is_token(token))
	assert_false(game.library.to_discard(token))
	await wait_seconds(0.2)
	assert_true(not is_instance_valid(token) or token.is_queued_for_deletion(), "gone")
	var other := await put_creature(1, "Soldier Token")
	assert_false(game.library.to_hand(other))
	await wait_seconds(0.2)
	assert_true(not is_instance_valid(other) or other.is_queued_for_deletion())


func test_the_moves_refuse_invalid_cards() -> void:
	assert_false(game.library.to_hand(null))
	assert_false(game.library.to_discard(null))
	assert_false(game.library.to_energy(null, 1))


# --- to_energy ---------------------------------------------------------------------------------------

func test_to_energy_from_the_hand_plays_it_face_down() -> void:
	var card := await put_in_hand(1, "Moral Captain")
	watch_signals(game)
	assert_true(game.library.to_energy(card, 1))
	await wait_seconds(0.3)
	assert_true(_in_energy(card, 1))
	assert_true(card.is_energy)
	assert_false(card.is_faceup)
	assert_eq(card.rotation_degrees, 0.0, "untapped")
	assert_eq(card.owner_id, 1)
	assert_eq(card.controller_id, 1)
	assert_signal_emitted_with_parameters(game, "energy_played", [card])
	assert_signal_emitted_with_parameters(game, "mana_changed", [1])


func test_to_energy_adds_mana() -> void:
	var before := total_mana(game.mana_pool(1))
	var card := await put_in_hand(1, "Moral Captain")
	game.library.to_energy(card, 1)
	await wait_seconds(0.2)
	assert_eq(total_mana(game.mana_pool(1)), before + 1)


func test_to_energy_from_the_deck_and_the_discard_pile_emits_no_energy_played() -> void:
	watch_signals(game)
	var from_deck: Card = _deck(1).get_top_card()
	assert_true(game.library.to_energy(from_deck, 1))
	await wait_seconds(0.3)
	assert_true(_in_energy(from_deck, 1))
	assert_false(from_deck.is_faceup)
	assert_true(from_deck.is_energy)
	var dead := await put_in_hand(1, "Righteous Guard")
	game.library.to_discard(dead)
	await wait_seconds(0.3)
	assert_true(game.library.to_energy(dead, 1))
	await wait_seconds(0.3)
	assert_true(_in_energy(dead, 1))
	assert_false(dead.is_faceup)
	assert_signal_not_emitted(game, "energy_played")
	assert_signal_emitted_with_parameters(game, "mana_changed", [1])


func test_to_energy_from_the_table_tells_the_script_and_resets_the_card() -> void:
	var fx := Recorder.new("Moral Captain")
	game.card_effects.register(fx)
	var card := await put_creature(1, "Moral Captain", 1, {}, true)
	watch_signals(game)
	assert_true(game.library.to_energy(card, 1))
	await wait_seconds(0.3)
	assert_true(_in_energy(card, 1))
	assert_true(card.is_energy)
	assert_false(card.is_faceup)
	assert_eq(card.rotation_degrees, 0.0, "a tilted card comes in untapped")
	assert_eq(fx.log, [["leave", "energy"]], "left the table, did not enter it")
	assert_signal_not_emitted(game, "energy_played")


func test_to_energy_from_the_other_players_zones() -> void:
	var enemy := await put_creature(2, "Moral Captain")
	assert_true(game.library.to_energy(enemy, 1))
	await wait_seconds(0.3)
	assert_true(_in_energy(enemy, 1), "in MY energy zone")
	assert_eq(enemy.owner_id, 2, "still owned by its owner")
	assert_eq(enemy.controller_id, 1, "controlled by the energy zone's player")
	# From the opponent's energy zone
	var their_energy := await put_energy(2, "Moral Captain")
	assert_true(game.library.to_energy(their_energy, 1))
	await wait_seconds(0.3)
	assert_true(_in_energy(their_energy, 1))
	assert_eq(their_energy.controller_id, 1)
	assert_true(their_energy.is_energy)
	# From the opponent's discard pile and hand
	var in_their_hand := await put_in_hand(2, "Righteous Guard")
	assert_true(game.library.to_energy(in_their_hand, 1))
	await wait_seconds(0.3)
	assert_true(_in_energy(in_their_hand, 1))
	assert_eq(in_their_hand.owner_id, 2)


func test_to_energy_from_the_same_energy_zone_does_nothing() -> void:
	var card := await put_energy(1, "Moral Captain")
	assert_false(game.library.to_energy(card, 1))
	assert_true(_in_energy(card, 1))


func test_a_token_does_not_go_to_energy() -> void:
	var token := await put_creature(1, "Soldier Token")
	assert_false(game.library.to_energy(token, 1))
	await wait_seconds(0.2)
	assert_true(not is_instance_valid(token) or token.is_queued_for_deletion())
	assert_eq(game.player(1).cards_in_grid("energy").size(), 0)


func test_to_energy_grows_the_energy_zone() -> void:
	var grid := FateZones.grid("energy", 1)
	var slots_before := grid.get_slot_count()
	var count := slots_before + 3
	var moved := []
	for _i in range(count):
		var card: Card = _deck(1).get_top_card()
		assert_true(game.library.to_energy(card, 1))
		moved.append(card)
		await wait_seconds(0.05)
	await wait_seconds(0.3)
	assert_gte(grid.get_slot_count(), count)
	for c in moved:
		assert_true(_in_energy(c, 1))
	assert_eq(game.player(1).cards_in_grid("energy").size(), count)


func test_a_card_moved_to_energy_and_out_again_is_a_normal_card() -> void:
	var card := await put_in_hand(1, "Moral Captain")
	game.library.to_energy(card, 1)
	await wait_seconds(0.3)
	assert_true(game.library.to_hand(card))
	await wait_seconds(0.3)
	assert_eq(card.get_parent(), _hand(1))
	assert_false(card.is_energy)
	assert_true(card.is_faceup)


# --- a spell redirected to the energy zone -----------------------------------------------------------

func test_a_spell_with_the_energy_destination_lands_face_down_in_the_energy_zone() -> void:
	var fx := Recorder.new("Reinforcements")
	fx.destination = "energy"
	game.card_effects.register(fx)
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()
	var spell := await put_in_hand(1, "Reinforcements")
	var energy_before := game.player(1).cards_in_grid("energy").size()
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.5)
	assert_true(_in_energy(spell, 1), "in the energy zone")
	assert_true(spell.is_energy)
	assert_false(spell.is_faceup)
	assert_eq(game.player(1).cards_in_grid("energy").size(), energy_before + 1)
	assert_eq(_pile("discard", 1).get_card_count(), 0, "not in the discard pile")
	assert_eq(fx.log, [], "an energy card does not 'enter' the table")


# --- discard_from_hand --------------------------------------------------------------------------------

func test_discard_from_hand_takes_the_default_choice() -> void:
	await empty_hand(1)
	var a := await put_in_hand(1, "Moral Captain")
	var b := await put_in_hand(1, "Righteous Guard")
	var discarded: Array = await game.library.discard_from_hand(1)
	await wait_seconds(0.3)
	assert_eq(discarded.size(), 1)
	assert_eq(discarded[0].get_parent(), _pile("discard", 1))
	assert_eq(_hand(1).get_card_count(), 1)
	assert_true(a.get_parent() == _hand(1) or b.get_parent() == _hand(1))


func test_discard_from_hand_asks_the_player() -> void:
	await empty_hand(1)
	var a := await put_in_hand(1, "Moral Captain")
	var b := await put_in_hand(1, "Righteous Guard")
	var c := await put_in_hand(1, "Reinforcements")
	var asked := []
	game.choices.choosers[1] = func(request):
		asked.append([request.player, request.count])
		return [c, b] if request.count == 2 else c
	var discarded: Array = await game.library.discard_from_hand(1, 2)
	await wait_seconds(0.3)
	game.choices.choosers.erase(1)
	assert_eq(asked, [[1, 2]])
	assert_eq(discarded.size(), 2)
	assert_eq(c.get_parent(), _pile("discard", 1))
	assert_eq(b.get_parent(), _pile("discard", 1))
	assert_eq(a.get_parent(), _hand(1))


func test_discard_from_hand_with_fewer_cards_and_an_empty_hand() -> void:
	await empty_hand(1)
	assert_eq(await game.library.discard_from_hand(1, 2), [])
	var only := await put_in_hand(1, "Moral Captain")
	var discarded: Array = await game.library.discard_from_hand(1, 3)
	await wait_seconds(0.3)
	assert_eq(discarded, [only])
	assert_eq(only.get_parent(), _pile("discard", 1))


func test_discard_from_hand_of_given_cards() -> void:
	await empty_hand(1)
	var a := await put_in_hand(1, "Moral Captain")
	var b := await put_in_hand(1, "Righteous Guard")
	var discarded: Array = await game.library.discard_from_hand(1, 1, [b])
	await wait_seconds(0.3)
	assert_eq(discarded, [b])
	assert_eq(a.get_parent(), _hand(1))
