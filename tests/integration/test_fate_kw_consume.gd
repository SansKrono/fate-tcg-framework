extends "res://tests/FateCommon.gd"
# Tests of the ability costs in src/custom/fate/FateCosts.gd: Consume (self, a card, other cards, X permanents),
# the filters, tokens, owner semantics (Section 12 item 12), pay_domain, return_self_to_hand, discard_hand_card,
# either, and the Occupy / Tap agreement.

var costs


func before_each():
	await super.before_each()
	costs = game.costs
	game.choices.chooser = Callable()


func _discard(pid: int) -> Array:
	return FateZones.container("discard", pid).get_all_cards()


func _in_discard(card: Card, pid: int) -> bool:
	return card in _discard(pid)


# The picker answers with the cards named in `names` (in the order of the options), recording the requests
func _pick_names(names: Array, requests := []) -> void:
	game.choices.chooser = func(request):
		requests.append(request)
		var found := []
		for o in request.options:
			if o.canonical_name in names:
				found.append(o)
		found = found.slice(0, request.count)
		return found[0] if request.count == 1 else found


# --- consume this card ---------------------------------------------------------------------------------

func test_consume_self_moves_the_card_to_its_owners_discard_pile():
	var card := await put_on_table(1, "Garbage Heap", "relics")
	var cost: Dictionary = costs.consume_self()
	assert_eq(costs.problem(card, [cost]), "")
	assert_true(await costs.pay(card, [cost]))
	await wait_seconds(0.2)
	assert_true(_in_discard(card, 1))
	assert_eq(FateZones.zone_of(card), "")


func test_a_consumed_card_goes_to_the_owner_not_the_controller():
	var card := await put_creature(1, "Righteous Guard")
	card.controller_id = 2
	assert_true(costs.consume(card))
	await wait_seconds(0.2)
	assert_true(_in_discard(card, 1), "owner's discard")
	assert_false(_in_discard(card, 2))


func test_consume_self_is_not_a_destruction():
	var card := await put_creature(1, "Righteous Guard")
	var died := []
	game.creature_destroyed.connect(func(c, _cause): died.append(c))
	costs.consume(card)
	await wait_seconds(0.2)
	assert_eq(died, [], "no death triggers")


func test_a_consumed_token_ceases_to_exist():
	var token := await put_creature(1, "Soldier Token")
	assert_true(costs.is_token(token))
	assert_true(costs.consume(token))
	await wait_seconds(0.2)
	assert_false(is_instance_valid(token) and not token.is_queued_for_deletion())
	assert_eq(_discard(1).filter(func(c): return c.canonical_name == "Soldier Token").size(), 0, "not in the discard pile")


# --- consume a card: zones and filters --------------------------------------------------------------------

func test_consume_a_card_from_each_zone():
	var creature := await put_creature(1, 2, 2)
	var relic := await put_on_table(1, "Dragon's Tooth", "relics")
	var energy := await put_energy(1, "Garbage Heap")
	var hand_card := await put_in_hand(1, "Deep Thought")
	for pair in [["creatures", creature], ["relics", relic], ["energy", energy], ["hand", hand_card]]:
		var cost: Dictionary = costs.consume_card([pair[0]])
		var source := await put_creature(1, 1, 1)
		assert_eq(costs.problem(source, [cost]), "", pair[0])
		_pick_names([pair[1].canonical_name])
		assert_true(await costs.pay(source, [cost]), pair[0])
		await wait_seconds(0.2)
		assert_true(_in_discard(pair[1], 1), pair[0])
	assert_eq(game.player(1).cards_in_grid("energy").size(), 0, "the energy slot is empty again")


func test_the_filter_limits_the_candidates_and_the_count_is_checked():
	var source := await put_creature(1, "Righteous Guard")
	await put_creature(1, 2, 2)
	await put_on_table(1, "Dragon's Tooth", "relics")
	var only_creatures: Dictionary = costs.consume_card(["creatures", "relics"], costs.filter_creature(), 2)
	# the source is a creature too (not excluded by default): 2 candidates
	assert_eq(costs.problem(source, [only_creatures]), "")
	var three: Dictionary = costs.consume_card(["creatures", "relics"], costs.filter_creature(), 3)
	assert_eq(costs.problem(source, [three]), "Nothing to consume")
	var relics: Dictionary = costs.consume_card(["creatures", "relics"], costs.filter_type("Relic"), 1)
	_pick_names(["Dragon's Tooth"])
	assert_true(await costs.pay(source, [relics]))


func test_non_token_and_name_filters():
	var source := await put_creature(1, "Righteous Guard")
	var token := await put_creature(1, "Soldier Token")
	var candidates: Array = costs.consume_candidates(source, ["creatures"], costs.filter_non_token())
	assert_eq(candidates, [source])
	assert_eq(costs.consume_candidates(source, ["creatures"], costs.filter_token()), [token])
	assert_eq(costs.consume_candidates(source, ["creatures"], costs.filter_name("Soldier Token")), [token])
	assert_eq(costs.consume_candidates(source, ["creatures"],
			costs.filter_all([costs.filter_creature(), costs.filter_non_token()])), [source])


func test_exclude_self():
	var source := await put_creature(1, "Righteous Guard")
	assert_eq(costs.consume_candidates(source, ["creatures"]), [source])
	assert_eq(costs.consume_candidates(source, ["creatures"], Callable(), {"exclude_self": true}), [])
	var other: Dictionary = costs.consume_other_cards(["creatures"])
	assert_eq(costs.problem(source, [other]), "Nothing to consume")


func test_controller_option_you_opponent_any():
	# Ikthar: "consume a creature you do not control" (control, not ownership: Section 12 item 12)
	var ikthar := await put_creature(1, "Ikthar, The Great Summoner")
	var mine := await put_creature(1, 2, 2)
	var theirs := await put_creature(2, 3, 3)
	var yours: Array = costs.consume_candidates(ikthar, ["creatures"])
	assert_true(mine in yours and not theirs in yours)
	var foreign: Array = costs.consume_candidates(ikthar, ["creatures"], costs.filter_creature(),
			{"controller": "opponent"})
	assert_eq(foreign, [theirs])
	var anyone: Array = costs.consume_candidates(ikthar, ["creatures"], Callable(), {"controller": "any"})
	assert_true(mine in anyone and theirs in anyone and ikthar in anyone)
	# a creature I own but the opponent controls counts as the opponent's
	mine.controller_id = 2
	assert_false(mine in costs.consume_candidates(ikthar, ["creatures"], Callable(), {"controller": "opponent"}),
			"candidates come from the grid it stands in; control follows the grid")


func test_consuming_an_opponents_creature_pays_into_their_discard_pile():
	var ikthar := await put_creature(1, "Ikthar, The Great Summoner")
	var theirs := await put_creature(2, 3, 3)
	var cost: Dictionary = costs.consume_card(["creatures"], costs.filter_creature(), 1, {"controller": "opponent"})
	assert_eq(costs.problem(ikthar, [cost]), "")
	assert_true(await costs.pay(ikthar, [cost]))
	await wait_seconds(0.2)
	assert_true(_in_discard(theirs, 2))


func test_the_picker_chooses_and_the_default_is_the_first_option():
	var source := await put_creature(1, 1, 1)
	var a := await put_creature(1, 2, 2)
	var b := await put_creature(1, 3, 3)
	var cost: Dictionary = costs.consume_card(["creatures"], func(c, s): return c != s)
	assert_true(await costs.pay(source, [cost]))
	await wait_seconds(0.2)
	assert_true(_in_discard(a, 1), "no chooser: the first option")
	assert_false(_in_discard(b, 1))


# --- other cards the caller picked -----------------------------------------------------------------------------

func test_consume_other_cards_with_chosen_cards():
	var source := await put_creature(1, 1, 1)
	var a := await put_creature(1, 2, 2)
	var b := await put_creature(1, 3, 3)
	var cost: Dictionary = costs.consume_other_cards(["creatures"], Callable(), 1, [b])
	assert_eq(costs.problem(source, [cost]), "")
	var asked := []
	_pick_names([], asked)
	assert_true(await costs.pay(source, [cost]))
	await wait_seconds(0.2)
	assert_true(_in_discard(b, 1))
	assert_false(_in_discard(a, 1))
	assert_eq(asked, [], "the picker was not asked")


func test_chosen_cards_are_validated():
	var source := await put_creature(1, 1, 1)
	var a := await put_creature(1, 2, 2)
	var foreign := await put_creature(2, 2, 2)
	assert_ne(costs.problem(source, [costs.consume_other_cards(["creatures"], Callable(), 1, [source])]), "",
			"never the card itself")
	assert_ne(costs.problem(source, [costs.consume_other_cards(["creatures"], Callable(), 1, [foreign])]), "",
			"not the opponent's")
	assert_ne(costs.problem(source, [costs.consume_other_cards(["creatures"], Callable(), 2, [a])]), "", "wrong count")
	assert_ne(costs.problem(source, [costs.consume_other_cards(["creatures"], Callable(), 2, [a, a])]), "", "repeat")
	assert_false(await costs.pay(source, [costs.consume_other_cards(["creatures"], Callable(), 1, [foreign])]))
	assert_false(_in_discard(foreign, 2))


func test_chosen_can_be_a_callable_supplied_at_pay_time():
	var source := await put_creature(1, 1, 1)
	var a := await put_creature(1, 2, 2)
	var cost: Dictionary = costs.consume_other_cards(["creatures"], Callable(), 1,
			func(_card): return [a])
	assert_true(await costs.pay(source, [cost]))
	await wait_seconds(0.2)
	assert_true(_in_discard(a, 1))


# --- additional cost: consume X permanents -----------------------------------------------------------------------

func test_cost_pay_extra_consumes_x_permanents():
	var spell := await put_in_hand(1, "Self-destruction")
	var a := await put_creature(1, 2, 2)
	var b := await put_on_table(1, "Dragon's Tooth", "relics")
	var c := await put_energy(1, "Garbage Heap")
	assert_eq(costs.extra_problem(spell, 1, costs.PERMANENT_ZONES, Callable(), 3), "")
	assert_ne(costs.extra_problem(spell, 1, costs.PERMANENT_ZONES, Callable(), 4), "")
	assert_false(await costs.cost_pay_extra(spell, 1, costs.PERMANENT_ZONES, Callable(), 4), "cannot pay")
	assert_eq(FateZones.zone_of(a), "creatures", "nothing was consumed")
	assert_true(await costs.cost_pay_extra(spell, 1, costs.PERMANENT_ZONES, Callable(), 3))
	await wait_seconds(0.2)
	assert_true(_in_discard(a, 1) and _in_discard(b, 1) and _in_discard(c, 1))


func test_cost_pay_extra_with_chosen_cards_and_a_picker():
	var spell := await put_in_hand(1, "Self-destruction")
	var a := await put_creature(1, 2, 2)
	var b := await put_creature(1, 3, 3)
	_pick_names(["Test 3/3"])
	assert_true(await costs.cost_pay_extra(spell, 1, ["creatures"], Callable(), 1))
	await wait_seconds(0.2)
	assert_true(_in_discard(b, 1))
	assert_eq(FateZones.zone_of(a), "creatures")
	assert_true(await costs.cost_pay_extra(spell, 1, ["creatures"], Callable(), 1, {"chosen": [a]}))
	await wait_seconds(0.2)
	assert_true(_in_discard(a, 1))


func test_force_consume_the_opponent_chooses():
	var spell := await put_in_hand(1, "Self-destruction")
	await put_creature(2, 2, 2)
	await put_creature(2, 3, 3)
	await put_creature(2, 4, 4)
	var consumed: Array = await costs.force_consume(spell, 2, costs.PERMANENT_ZONES, Callable(), 2)
	await wait_seconds(0.2)
	assert_eq(consumed.size(), 2)
	for c in consumed:
		assert_true(_in_discard(c, 2))
	var rest: Array = await costs.force_consume(spell, 2, costs.PERMANENT_ZONES, Callable(), 5)
	assert_eq(rest.size(), 1, "as many as they have")
	assert_eq((await costs.force_consume(spell, 2, costs.PERMANENT_ZONES, Callable(), 1)).size(), 0)


# --- new generic costs -------------------------------------------------------------------------------------------

func test_pay_domain_taps_energy_of_that_domain():
	var source := await put_creature(1, 1, 1)
	await put_energy(1, "Garbage Heap")       # Innovation
	await put_energy(1, "Dragon's Tooth")     # Primal
	var cost: Dictionary = costs.pay_domain("Primal")
	assert_eq(costs.problem(source, [cost]), "")
	assert_true(await costs.pay(source, [cost]))
	assert_eq(game.mana.mana_pool(1)["Primal"], 0)
	assert_eq(game.mana.mana_pool(1)["Innovation"], 1, "the other domain is untouched")
	assert_eq(costs.problem(source, [cost]), "Not enough Primal mana")
	assert_ne(costs.problem(source, [costs.pay_domain("Order")]), "")
	assert_ne(costs.problem(source, [costs.pay_domain("Innovation", 2)]), "")


func test_return_self_to_hand_goes_to_the_owners_hand():
	var card := await put_creature(1, "Righteous Guard")
	var cost: Dictionary = costs.return_self_to_hand()
	assert_eq(costs.problem(card, [cost]), "")
	assert_true(await costs.pay(card, [cost]))
	await wait_seconds(0.3)
	assert_eq(card.get_parent(), FateZones.container("hand", 1))
	assert_eq(costs.problem(card, [cost]), "Not on the table")


func test_discard_hand_card():
	var source := await put_creature(1, 1, 1)
	await empty_hand(1)
	var cost: Dictionary = costs.discard_hand_card()
	assert_eq(costs.problem(source, [cost]), "Nothing to consume")
	var card := await put_in_hand(1, "Deep Thought")
	assert_eq(costs.problem(source, [cost]), "")
	assert_true(await costs.pay(source, [cost]))
	await wait_seconds(0.3)
	assert_true(_in_discard(card, 1))


func test_either_pays_the_first_payable_alternative():
	var source := await put_creature(1, 1, 1)
	var both: Dictionary = costs.either(costs.counter("scrap", 1), costs.mana(1))
	assert_ne(costs.problem(source, [both]), "", "neither")
	await put_energy(1, "Garbage Heap")
	assert_eq(costs.problem(source, [both]), "", "the second alternative")
	assert_true(await costs.pay(source, [both]))
	assert_eq(total_mana(game.mana_pool(1)), 0, "paid with mana")
	assert_ne(costs.problem(source, [both]), "")


# --- Occupy and Tap agree ---------------------------------------------------------------------------------------

func test_tap_abilities_offer_the_occupy_action_and_the_cost_agrees():
	go_to_main()
	var kw = game.keywords.get_keyword("Occupy")
	for tap_card in ["Acquisition Fabricator", "Battle Smith", "Factory Crafter", "Devote Paladin"]:
		var card := await put_creature(1, tap_card)
		assert_true(kw.has_tap_ability(card), tap_card)
		assert_true(kw.has_ability(card), tap_card)
		assert_true(game.actions.list(card).any(func(a): return a.id == "occupy"), tap_card)
		var cost: Dictionary = costs.occupy()
		assert_eq(costs.problem(card, [cost]), "", tap_card)
		assert_eq(kw.occupy_problem(card), "")
	var fabricator: Card = game.player(1).cards_in_grid("creatures")[0]
	assert_true(await costs.pay(fabricator, [costs.occupy()]))
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(fabricator), "occupied")


func test_cards_without_tap_do_not_have_the_occupy_action():
	go_to_main()
	var kw = game.keywords.get_keyword("Occupy")
	var plain := await put_creature(1, "Righteous Guard")
	assert_false(kw.has_tap_ability(plain))
	assert_false(kw.has_ability(plain))
	var workforce := game.place_card_on_table("Invigorated Workforce", 1, "field")
	assert_false(kw.has_tap_ability(workforce), "a spell is not a creature with a tap ability")


func test_tilt_self_taps_a_relic_once():
	var tree := await put_on_table(1, "Ancient Tree", "relics")
	var cost: Dictionary = costs.tilt_self()
	assert_eq(costs.problem(tree, [cost]), "")
	assert_true(await costs.pay(tree, [cost]))
	assert_eq(tree.card_rotation, 90)
	assert_eq(costs.problem(tree, [cost]), "Already tilted")
	game.end_turn()
	game.end_turn()
	assert_eq(tree.card_rotation, 0, "untaps at its controller's maintenance")
