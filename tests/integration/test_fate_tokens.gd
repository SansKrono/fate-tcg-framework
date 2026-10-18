extends "res://tests/FateCommon.gd"
# Tokens and counters (src/custom/fate/FateTokens.gd, game.tokens): scrap / ingot counters, token cards,
# replacement effects, ingots as mana, the HUD readout and board states.


class Recorder:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var log: Array = []

	func _init(name_of_card := "") -> void:
		card_name = name_of_card

	func on_enter(card: Card) -> void:
		log.append(["enter", card.canonical_name])


func _pile_size(zone: String, pid: int) -> int:
	return FateZones.container(zone, pid).get_card_count()


# A creature with the given cost, for the payment tests (it only has to be a card with Cost and Pips)
func _costed(generic: int, pips := "") -> Card:
	var card_name := "Costed %d%s" % [generic, pips]
	var def: Dictionary = FateData.CARDS["Moral Captain"].duplicate(true)
	def["Cost"] = generic
	def["Pips"] = pips
	cfc.card_definitions[card_name] = def
	var card := game.place_card_on_table(card_name, 1, "creatures")
	await get_tree().process_frame
	return card


func _tapped(energy: Array) -> int:
	return energy.filter(func(c): return c.card_rotation == 90).size()


# --- counters --------------------------------------------------------------------------------------------

func test_counters_add_spend_and_signal() -> void:
	var seen := []
	game.tokens.counter_changed.connect(func(pid, name, value): seen.append([pid, name, value]))
	assert_eq(game.tokens.counter(1, "scrap"), 0)
	assert_eq(game.tokens.add(1, "scrap", 2), 2, "add returns what was added")
	assert_eq(game.tokens.counter(1, "scrap"), 2)
	assert_eq(game.tokens.counter(2, "scrap"), 0, "per player")
	assert_eq(game.tokens.counter(1, "ingot"), 0, "per counter")
	assert_true(game.tokens.spend(1, "scrap", 1))
	assert_false(game.tokens.spend(1, "scrap", 2), "cannot spend more than there is")
	assert_eq(game.tokens.counter(1, "scrap"), 1, "a failed spend takes nothing")
	assert_eq(seen, [[1, "scrap", 2], [1, "scrap", 1]])
	assert_eq(game.tokens.add(1, "scrap", 0), 0)
	game.tokens.reset()
	assert_eq(game.tokens.counter(1, "scrap"), 0)
	assert_eq(seen.back(), [1, "scrap", 0], "reset tells the HUD")


func test_counters_work_as_an_ability_cost() -> void:
	var cost: Dictionary = game.costs.counter("scrap", 2)
	var card := await put_on_table(1, "Moral Captain", "creatures")
	assert_ne(cost.problem.call(card), "", "no scrap yet")
	game.tokens.add(1, "scrap", 2)
	assert_eq(cost.problem.call(card), "")
	assert_true(await game.costs.pay(card, [cost]))
	assert_eq(game.tokens.counter(1, "scrap"), 0)


func test_replacement_effects_change_the_amount() -> void:
	var plus_one := func(_pid: int, kind: String, amount: int) -> int:
		return amount + 1 if kind == "scrap" else amount
	game.tokens.add_replacement(plus_one)
	assert_eq(game.tokens.add(1, "scrap", 2), 3, "an additional one")
	assert_eq(game.tokens.counter(1, "scrap"), 3)
	assert_eq(game.tokens.add(1, "ingot", 1), 1, "other kinds are left alone")
	game.tokens.remove_replacement(plus_one)
	assert_eq(game.tokens.add(1, "scrap", 2), 2, "removed again")
	var zero := func(_pid: int, _kind: String, _amount: int) -> int:
		return -4
	game.tokens.add_replacement(zero)
	assert_eq(game.tokens.add(1, "scrap", 2), 0, "never below 0")
	game.tokens.clear_replacements()
	assert_eq(game.tokens.add(1, "scrap", 2), 2)


func test_a_card_script_can_replace_token_amounts() -> void:
	# A script with a token_amount method
	var script := GDScript.new()
	script.source_code = "extends \"res://src/custom/fate/cards/FateCardEffect.gd\"\n" \
			+ "func _init(): card_name = \"Moral Captain\"\n" \
			+ "func token_amount(host, pid, _kind, amount): return amount + 1 if pid == host.controller_id else amount\n"
	script.reload()
	var boosted = script.new()
	game.card_effects.register(boosted)
	assert_eq(game.tokens.add(1, "scrap", 1), 1, "the card is not on the table yet")
	var captain := await put_on_table(1, "Moral Captain", "creatures")
	assert_eq(game.tokens.add(1, "scrap", 1), 2, "while it is on the table")
	assert_eq(game.tokens.add(2, "scrap", 1), 1, "only for its controller")
	captain.queue_free()


# --- token cards -------------------------------------------------------------------------------------------

func test_create_a_creature_token() -> void:
	var created := []
	game.tokens.token_created.connect(func(card): created.append(card))
	var token: Card = game.tokens.create("Soldier Token", 1)
	await get_tree().process_frame
	assert_not_null(token)
	assert_eq(created, [token])
	assert_eq(FateZones.zone_of(token), "creatures")
	assert_eq(token.owner_id, 1)
	assert_eq(token.controller_id, 1)
	assert_eq(token.entered_turn, game.turn_number, "enters like a played card (Charge, summoning sickness)")
	assert_true(game.tokens.is_token(token))
	assert_eq(game.stats.current(token, "Strike"), 1)
	assert_eq(game.stats.current(token, "Guard"), 1)
	assert_eq(token.card_rotation, 0)
	assert_true(game.creatures_in_play(1).has(token))


func test_create_for_the_other_player_and_other_tokens() -> void:
	var goblin: Card = game.tokens.create("Goblin Token", 2)
	assert_eq(goblin.owner_id, 2)
	assert_eq(FateZones.zone_of(goblin), "creatures")
	assert_true(game.player(2).cards_in_grid("creatures").has(goblin))
	var automaton: Card = game.tokens.create("Iron Automaton Token", 1, {"tilted": true})
	assert_eq(game.stats.current(automaton, "Strike"), 3)
	assert_eq(automaton.card_rotation, 90, "guard position")
	var occupied: Card = game.tokens.create("Soldier Token", 1, {"zone": "occupied"})
	assert_eq(FateZones.zone_of(occupied), "occupied")
	assert_eq(occupied.card_rotation, 90, "occupied creatures are tilted")
	assert_null(game.tokens.create("Moral Captain", 1), "only tokens")
	assert_null(game.tokens.create("Nope Token", 1))


func test_create_a_relic_token_and_attach_it() -> void:
	var host := await put_creature(1, 2, 2)
	var hammer: Card = game.tokens.create("Battle Hammer Token", 1, {"attach_to": host})
	assert_not_null(hammer)
	assert_true(FateZones.zone_of(hammer) in ["relics"] or hammer.current_host_card == host)
	assert_eq(hammer.owner_id, 1)
	assert_true(game.tokens.is_token(hammer))
	if game.equip.host_of(hammer) != null:
		assert_eq(game.equip.host_of(hammer), host, "equipped through game.equip")
	var spear: Card = game.tokens.create("Soul Spear Token", 1)
	assert_eq(FateZones.zone_of(spear), "relics")
	assert_null(game.tokens.create("Battle Hammer Token", 1, {"attach_to": spear}), "attach to a creature only")


func test_a_full_zone_gives_null() -> void:
	for _i in range(6):
		assert_not_null(game.tokens.create("Soldier Token", 1))
	assert_null(game.tokens.create("Soldier Token", 1), "six creature slots")
	assert_not_null(game.tokens.create("Soldier Token", 2), "the other player has room")
	assert_eq(game.tokens.create_many("Soldier Token", 1, 3), [], "none fit")


func test_on_enter_runs_for_a_token() -> void:
	var fx := Recorder.new("Soldier Token")
	game.card_effects.register(fx)
	game.tokens.create("Soldier Token", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(fx.log, [["enter", "Soldier Token"]])


func test_a_token_that_leaves_the_table_ceases_to_exist() -> void:
	var discard_before := _pile_size("discard", 1)
	var hand_before := _pile_size("hand", 1)
	var token: Card = game.tokens.create("Soldier Token", 1)
	await get_tree().process_frame
	assert_true(game.effects.destroy(token))
	await wait_seconds(0.1)
	assert_false(is_instance_valid(token) and not token.is_queued_for_deletion(), "gone")
	assert_eq(_pile_size("discard", 1), discard_before, "never in the discard pile")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 0, "slot free")
	assert_not_null(game.tokens.create("Soldier Token", 1), "and reusable")
	# Back to the hand: the same
	var other: Card = game.tokens.create("Goblin Token", 1)
	await get_tree().process_frame
	other.move_to(FateZones.container("hand", 1), -1, null, ["Scripted"])
	await wait_seconds(0.2)
	assert_false(is_instance_valid(other) and not other.is_queued_for_deletion())
	assert_eq(_pile_size("hand", 1), hand_before, "a token is never put in a hand")


func test_a_normal_card_still_goes_to_the_discard_pile() -> void:
	var discard_before := _pile_size("discard", 1)
	var card := await put_on_table(1, "Moral Captain", "creatures")
	assert_true(game.effects.destroy(card))
	await wait_seconds(0.1)
	assert_true(is_instance_valid(card))
	assert_eq(_pile_size("discard", 1), discard_before + 1)


func test_token_count_includes_counters_and_cards() -> void:
	assert_eq(game.tokens.token_count(1), 0)
	game.tokens.add(1, "scrap", 2)
	game.tokens.add(1, "ingot", 1)
	game.tokens.create("Soldier Token", 1)
	game.tokens.create("Iron Automaton Token", 1, {"zone": "occupied"})
	game.tokens.create("Soul Spear Token", 1)
	await put_on_table(1, "Moral Captain", "creatures")
	assert_eq(game.tokens.token_count(1), 6, "2 scrap + 1 ingot + 3 token cards, not the Captain")
	assert_eq(game.tokens.token_count(2), 0)


func test_copy_a_token_card_or_a_counter() -> void:
	var source: Card = game.tokens.create("Goblin Token", 1)
	var copies: Array = game.tokens.copy(source, 1, 2)
	assert_eq(copies.size(), 2)
	for c in copies:
		assert_eq(c.canonical_name, "Goblin Token")
		assert_eq(c.controller_id, 1)
		assert_true(game.tokens.is_token(c))
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 3)
	assert_eq(game.tokens.copy("scrap", 1, 2), [], "counters give no cards")
	assert_eq(game.tokens.counter(1, "scrap"), 2)
	assert_eq(game.tokens.copy(await put_on_table(1, "Moral Captain", "creatures"), 1, 1), [], "not a token")
	assert_eq(game.tokens.copy("nonsense", 1, 1), [])


func test_replacement_creates_additional_tokens() -> void:
	game.tokens.add_replacement(func(_pid: int, _kind: String, amount: int) -> int: return amount + 1)
	var first: Card = game.tokens.create("Soldier Token", 1)
	assert_not_null(first)
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 2, "one additional token")
	var copies: Array = game.tokens.copy(first, 1, 2)
	assert_eq(copies.size(), 3, "a copy event of 2 becomes 3")
	assert_eq(game.tokens.create_many("Soldier Token", 1, 5).size(), 1, "only one slot was left")


# --- ingots as mana --------------------------------------------------------------------------------------

func test_ingots_do_nothing_when_the_energy_covers_the_cost() -> void:
	var energy := [await put_energy(1, _energy_card_of("Order")), await put_energy(1, _energy_card_of("Order"))]
	game.tokens.add(1, "ingot", 3)
	var card := await _costed(2)
	var plan := game.mana.plan_payment(card)
	assert_true(plan.ok)
	assert_eq(plan.ingots, 0)
	assert_eq(plan.cards.size(), 2)
	assert_true(game.mana.pay(card))
	assert_eq(_tapped(energy), 2)
	assert_eq(game.tokens.counter(1, "ingot"), 3, "no ingot spent")


func test_ingots_pay_what_the_energy_cannot() -> void:
	var energy := [await put_energy(1, _energy_card_of("Order"))]
	var card := await _costed(3)
	assert_false(game.mana.can_pay(card), "1 energy, no ingots")
	assert_false(game.mana.pay(card))
	assert_eq(_tapped(energy), 0, "a failed payment taps nothing")
	game.tokens.add(1, "ingot", 1)
	assert_false(game.mana.can_pay(card), "1 energy + 1 ingot is 2 mana")
	game.tokens.add(1, "ingot", 3)
	assert_true(game.mana.can_pay(card))
	var plan := game.mana.plan_payment(card)
	assert_eq(plan.cards.size(), 1)
	assert_eq(plan.ingots, 2)
	assert_true(game.mana.pay(card))
	assert_eq(_tapped(energy), 1)
	assert_eq(game.tokens.counter(1, "ingot"), 2, "4 - 2")


func test_an_ingot_pays_a_pip_of_any_colour() -> void:
	# Order energy only, the card needs a Primal pip
	await put_energy(1, _energy_card_of("Order"))
	await put_energy(1, _energy_card_of("Order"))
	var card := await _costed(1, "P")
	assert_false(game.mana.can_pay(card))
	game.tokens.add(1, "ingot", 1)
	assert_true(game.mana.can_pay(card))
	assert_true(game.mana.pay(card))
	assert_eq(game.tokens.counter(1, "ingot"), 0)
	assert_eq(game.mana.untapped_energy(1).size(), 1, "one Order energy paid the generic mana")


func test_a_card_with_only_ingots_to_pay_with() -> void:
	var card := await _costed(2)
	game.tokens.add(1, "ingot", 2)
	assert_true(game.mana.pay(card))
	assert_eq(game.tokens.counter(1, "ingot"), 0)


func test_pay_generic_falls_back_to_ingots() -> void:
	var energy := [await put_energy(1, _energy_card_of("Order")), await put_energy(1, _energy_card_of("Order"))]
	assert_false(game.mana.can_pay_generic(1, 3))
	assert_false(game.mana.pay_generic(1, 3))
	assert_eq(_tapped(energy), 0)
	game.tokens.add(1, "ingot", 1)
	assert_true(game.mana.can_pay_generic(1, 3))
	assert_true(game.mana.pay_generic(1, 3))
	assert_eq(_tapped(energy), 2, "the energy is used first")
	assert_eq(game.tokens.counter(1, "ingot"), 0)
	game.tokens.add(1, "ingot", 2)
	assert_true(game.mana.pay_generic(1, 2), "ingots alone")
	assert_false(game.mana.pay_generic(1, 1))
	assert_eq(game.mana.plan_generic(1, 1), [], "plan_generic stays about energy")


func test_ingots_pay_for_playing_a_card_from_the_hand() -> void:
	await empty_hand(1)
	go_to_main()
	var card := await put_in_hand(1, "Moral Captain")
	var cost: int = card.mana_value()
	assert_false(game.can_pay(card))
	game.tokens.add(1, "ingot", cost)
	assert_true(game.can_play_from_hand(card))
	assert_true(game.play_from_hand(card))
	assert_eq(game.tokens.counter(1, "ingot"), 0)
	assert_eq(FateZones.zone_of(card), "creatures")


# --- HUD ------------------------------------------------------------------------------------------------------

func test_the_player_plate_shows_the_counters() -> void:
	var plate = board.combat_ui.avatars[1]
	assert_eq(plate.counters_text(), "")
	game.tokens.add(1, "scrap", 2)
	game.tokens.add(1, "ingot", 1)
	assert_eq(plate.counters_text(), "Scrap 2   Ingot 1")
	assert_eq(board.combat_ui.avatars[2].counters_text(), "")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(plate.counters_label.visible)
	assert_eq(plate.counters_label.text, "Scrap 2   Ingot 1")
	game.tokens.reset()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(plate.counters_label.visible)


# --- board states ----------------------------------------------------------------------------------------

func test_counters_round_trip_through_a_board_state() -> void:
	game.tokens.add(1, "scrap", 3)
	game.tokens.add(2, "ingot", 2)
	var state := capture_board()
	assert_not_null(state)
	assert_eq(state.data["players"]["1"]["counters"], {"scrap": 3})
	assert_eq(state.data["players"]["2"]["counters"], {"ingot": 2})
	game.tokens.reset()
	game.tokens.add(1, "ingot", 9)
	await load_board(state)
	assert_eq(game.tokens.counter(1, "scrap"), 3)
	assert_eq(game.tokens.counter(1, "ingot"), 0, "the table's counters are replaced")
	assert_eq(game.tokens.counter(2, "ingot"), 2)
	var again := capture_board()
	assert_eq(again.data["players"], state.data["players"])


func test_a_table_without_counters_stores_none() -> void:
	var state := capture_board()
	assert_false(state.data["players"]["1"].has("counters"))
	game.tokens.add(1, "scrap", 1)
	game.tokens.spend(1, "scrap", 1)
	assert_false(capture_board().data["players"]["1"].has("counters"), "0 is not stored")


func test_counters_in_a_board_file() -> void:
	var state := FateBoardState.from_json(
			'{"format": "fate-board-state", "version": 1, "players": {"1": {"counters": {"scrap": 2, "ingot": 0}}}}')
	assert_eq(state.validate(), [])
	assert_eq(state.data["players"]["1"]["counters"], {"scrap": 2}, "zero counters are dropped")
	await load_board(state)
	assert_eq(game.tokens.counter(1, "scrap"), 2)
	assert_eq(game.tokens.counter(1, "ingot"), 0)
	assert_eq(game.tokens.counter(2, "scrap"), 0)


func test_bad_counters_are_refused() -> void:
	for counters in ['{"scrap": -1}', '{"scrap": "two"}', '[1]', '3']:
		var state := FateBoardState.from_json(
				'{"format": "fate-board-state", "version": 1, "players": {"1": {"counters": %s}}}' % counters)
		assert_false(state.validate().is_empty(), "refused: " + counters)
	var unknown := FateBoardState.from_json(
			'{"format": "fate-board-state", "version": 1, "players": {"1": {"counters": {"gold": 1}}}}')
	assert_eq(unknown.validate(), [], "an unknown counter is only a warning")
	assert_false(unknown.warnings.is_empty())


func test_token_cards_round_trip_through_a_board_state() -> void:
	game.tokens.create("Soldier Token", 1)
	game.tokens.create("Goblin Token", 2, {"tilted": true})
	game.tokens.create("Soul Spear Token", 1)
	await get_tree().process_frame
	var state := capture_board()
	assert_not_null(state)
	await load_board(state)
	assert_eq(game.tokens.token_count(1), 2)
	assert_eq(game.tokens.token_count(2), 1)
	var goblin: Card = game.player(2).cards_in_grid("creatures")[0]
	assert_eq(goblin.canonical_name, "Goblin Token")
	assert_eq(goblin.card_rotation, 90)
	assert_true(game.tokens.is_token(goblin))
	assert_eq(goblin.entered_turn, game.turn_number)
