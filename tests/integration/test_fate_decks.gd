extends "res://tests/FateCommon.gd"
# Tests of the mono-domain decks: player 1 plays Order and player 2 plays Primal, 40 cards each
# with at most 3 copies of a card, one copy of a legendary card and a smooth mana curve.
# See docs/FATE_TCG_DESIGN.md, Section 11.2, and FateDecks.DECKLISTS.

const LISTS := FateDecks.DECKLISTS


func _total(list: Dictionary) -> int:
	var total := 0
	for n in list:
		total += list[n]
	return total


func _count(list: Dictionary, predicate: Callable) -> int:
	var total := 0
	for n in list:
		if predicate.call(cfc.card_definitions[n]):
			total += list[n]
	return total


# --- who plays what ------------------------------------------------------------------------------

func test_player_one_plays_order_and_player_two_plays_primal():
	assert_eq(game.player(1).domains, ["Order"])
	assert_eq(game.player(2).domains, ["Primal"])


func test_dealt_decks_are_the_deck_lists():
	for pid in [1, 2]:
		var dealt := {}
		for zone in ["deck", "hand"]:
			for c in FateZones.container(zone, pid).get_all_cards():
				dealt[c.canonical_name] = dealt.get(c.canonical_name, 0) + 1
		assert_eq(dealt, FateDecks.decklist(game.player(pid).domains), "Player %d holds their whole deck list" % pid)


# --- the rules ------------------------------------------------------------------------------------

func test_deck_lists_are_legal():
	for domain in LISTS:
		assert_eq(FateDecks.problems(LISTS[domain], [domain]), [], "%s deck breaks no deck rule" % domain)
		assert_eq(_total(LISTS[domain]), 40, "%s deck has 40 cards" % domain)


func test_no_more_than_three_copies_and_one_legendary():
	for domain in LISTS:
		for n in LISTS[domain]:
			var props: Dictionary = cfc.card_definitions[n]
			assert_true(LISTS[domain][n] <= FateDecks.MAX_COPIES, "%s: at most 3 copies" % n)
			if FateDecks.is_legendary(props):
				assert_eq(LISTS[domain][n], 1, "%s is legendary: a single copy" % n)


func test_every_god_is_a_single_copy():
	for domain in LISTS:
		var gods := 0
		for n in LISTS[domain]:
			if "God" in cfc.card_definitions[n].Tags:
				gods += LISTS[domain][n]
		assert_eq(gods, 1, "%s plays its God once" % domain)


func test_card_data_copy_limits():
	for n in FateData.CARDS:
		var limit: int = FateData.CARDS[n]._max_allowed
		assert_true(limit == 1 if FateData.CARDS[n]._unique else limit == 3, "%s: copy limit %d" % [n, limit])


func test_problems_reports_broken_rules():
	assert_ne(FateDecks.problems({"Righteous Guard": 4}, ["Order"]), [], "4 copies, and not 40 cards")
	var list: Dictionary = LISTS["Order"].duplicate()
	list["Lucran, Divine Saviour"] = 2
	list["Righteous Guard"] = 2
	assert_true(FateDecks.problems(list, ["Order"]).any(func(p): return "Lucran" in p), "Two Gods")
	list = LISTS["Order"].duplicate()
	list["Righteous Guard"] = 2
	list["Meek Minion"] = 1
	assert_true(FateDecks.problems(list, ["Order"]).any(func(p): return "Meek Minion" in p), "A card of another domain")


func test_generated_deck_for_other_domains_follows_the_rules():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for domains in [["Chaos"], ["Innovation"], ["Innovation", "Primal"]]:
		var names := FateDecks.build(domains, rng)
		var list := {}
		for n in names:
			list[n] = list.get(n, 0) + 1
		assert_eq(FateDecks.problems(list, domains), [], "Generated %s deck is legal" % [domains])


# --- the mana curve -------------------------------------------------------------------------------

func test_curve_has_early_plays_and_few_expensive_cards():
	for domain in LISTS:
		var curve := FateDecks.mana_curve(LISTS[domain])
		var early := 0
		var expensive := 0
		var total_mv := 0
		for mv in curve:
			total_mv += mv * curve[mv]
			if mv <= 2:
				early += curve[mv]
			if mv >= 5:
				expensive += curve[mv]
		assert_between(early, 12, 20, "%s: 12-20 cards to play by turn 2" % domain)
		assert_true(expensive <= 6, "%s: at most 6 cards of 5+ mana" % domain)
		assert_between(total_mv / 40.0, 2.3, 3.2, "%s: average mana value" % domain)
		var cheapest_three: int = curve.get(1, 0) + curve.get(2, 0) + curve.get(3, 0)
		assert_gte(cheapest_three, 26, "%s: at least 26 cards cost 3 or less" % domain)


func test_curve_has_a_playable_hand_on_most_turns():
	# 40 card deck, 7 card hand, one energy a turn: the chance that an opening hand holds a
	# play costing at most 2 must be high. Hypergeometric draw of 7 from 40.
	for domain in LISTS:
		var curve := FateDecks.mana_curve(LISTS[domain])
		var cheap: int = curve.get(1, 0) + curve.get(2, 0)
		var none := 1.0
		for i in range(7):
			none *= float(40 - cheap - i) / float(40 - i)
		assert_lt(none, 0.02, "%s: under 2%% of opening hands have no play by turn 2" % domain)


func test_decks_are_a_mix_of_creatures_and_spells():
	for domain in LISTS:
		var creatures := _count(LISTS[domain], func(p): return p.Type == "Creature")
		assert_between(creatures, 20, 30, "%s: 20-30 creatures" % domain)
		assert_gte(_count(LISTS[domain], func(p): return p.Type == "Spell"), 5, "%s: some spells" % domain)
