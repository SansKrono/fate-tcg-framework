extends GutTest
# The pure-data side of the AI simulation lab (src/custom/fate/sim/): game numbering, the report that is
# built from game records, the win-rate statistics and the flags that point at cards worth a look.

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Report := preload("res://src/custom/fate/sim/FateSimReport.gd")


func before_all() -> void:
	FateGame.register_cards()


# A game record in the shape FateSimRecorder makes. `winner` is the seat that won (0: nobody); deck A
# ("Order") sits in seat 1 when `a_first`.
func _record(game: int, winner: int, a_first := true, a_cards := {}, b_cards := {}, turns := 12, errors := {}) -> Dictionary:
	var seat_a := 1 if a_first else 2
	var seats := {}
	seats[str(seat_a)] = _seat("Order", 0, winner == seat_a, a_cards)
	seats[str(3 - seat_a)] = _seat("Primal", 1, winner == 3 - seat_a, b_cards)
	return {"type": "game", "game": game, "matchup": 0, "seed": "s", "winner_seat": winner,
			"reason": "life" if winner != 0 else "turn_cap", "turns": turns, "frames": 100, "ms": 1000,
			"seats": seats, "problems": [], "errors": errors}


func _seat(label: String, deck: int, won: bool, cards: Dictionary) -> Dictionary:
	return {"label": label, "deck": deck, "won": won, "life_end": 5 if won else 0,
			"life_by_turn": [10, 9, 8], "creatures_lost": 2, "dmg_taken": {"combat": 3, "death_loss": 2},
			"attacks": 4, "player_hits": 2, "blocked_attacks": 1, "mana_spent": 8, "mana_available": 10,
			"board_sum": 6, "board_turns": 6, "energy_plays": 3, "draw_choices": 1, "cards_played": 5,
			"turns": 6, "cards": cards}


func _card(copies := 3, seen := 1, played := 1, energy := 0) -> Dictionary:
	return {"copies": copies, "seen": seen, "played": played, "energy": energy, "turn_sum": 3 * played,
			"dmg_c": 2, "dmg_p": 1, "kills": 1, "deaths": 0, "attacks": 0, "hits": 0}


# --- game numbering ---------------------------------------------------------------------------------------

func test_games_are_interleaved_over_the_matchups_and_seats_alternate() -> void:
	var order := Config.domain_deck("Order")
	var primal := Config.domain_deck("Primal")
	var chaos := Config.domain_deck("Chaos")
	var config := Config.new_config([Config.matchup(order, primal), Config.matchup(order, chaos)], 4, 2)
	assert_eq(Config.total_games(config), 8)
	assert_eq(Config.matchup_of_game(config, 0), 0)
	assert_eq(Config.matchup_of_game(config, 1), 1)
	assert_eq(Config.matchup_of_game(config, 2), 0)
	assert_eq(Config.game_in_matchup(config, 2), 1)
	assert_eq(Config.deck_in_seat_1(config, 0), 0, "deck a goes first in the first game of a matchup")
	assert_eq(Config.deck_in_seat_1(config, 2), 1, "and second in the next one")
	config.swap_seats = false
	assert_eq(Config.deck_in_seat_1(config, 2), 0)
	assert_ne(Config.game_seed(config, 0), Config.game_seed(config, 1), "every game has a seed of its own")


func test_a_round_robin_has_every_pair_once() -> void:
	var decks: Array = Config.DOMAINS.map(func(d): return Config.domain_deck(d))
	assert_eq(Config.round_robin(decks).size(), 6)
	assert_eq(Config.round_robin(decks, true).size(), 10, "with the mirror matches")


func test_a_config_without_games_or_decks_is_refused() -> void:
	var config := Config.new_config([], 0, 1)
	var found := Config.problems(config)
	assert_true(found.size() >= 2, str(found))
	var good := Config.new_config([Config.matchup(Config.domain_deck("Order"), Config.domain_deck("Primal"))], 4, 1)
	assert_eq(Config.problems(good), [])


func test_a_deck_list_that_breaks_the_deck_rules_is_refused() -> void:
	var bad := Config.deck(["Order"], "Bad", {"Righteous Guard": 3})
	var config := Config.new_config([Config.matchup(bad, Config.domain_deck("Primal"))], 2, 1)
	assert_false(Config.problems(config).is_empty(), "3 cards are not a deck")
	var ok := Config.deck(["Order"], "Same", FateDecks.DECKLISTS["Order"].duplicate())
	assert_eq(Config.problems(Config.new_config([Config.matchup(ok, Config.domain_deck("Primal"))], 2, 1)), [])


# --- statistics ------------------------------------------------------------------------------------------

func test_wilson_interval_shrinks_with_more_games() -> void:
	assert_gt(Report.wilson_half_width(5, 10), Report.wilson_half_width(50, 100))
	assert_lt(Report.wilson_half_width(500, 1000), 0.04)
	assert_eq(Report.wilson_half_width(0, 0), 0.5, "no games: anything is possible")


func test_z_scores_point_in_the_right_direction() -> void:
	assert_gt(Report.z_vs(70, 100), 3.0)
	assert_lt(Report.z_vs(30, 100), -3.0)
	assert_almost_eq(Report.z_vs(50, 100), 0.0, 0.001)
	assert_gt(Report.z_diff(80, 100, 50, 100), 2.0)
	assert_eq(Report.z_diff(0, 0, 5, 10), 0.0)


# --- the report ------------------------------------------------------------------------------------------

func test_win_rates_count_decided_games_per_deck() -> void:
	var report := Report.new()
	report.add_record(_record(0, 1, true))
	report.add_record(_record(1, 2, false))
	report.add_record(_record(2, 1, true))
	report.add_record(_record(3, 0, false))
	assert_eq(report.games, 4)
	assert_eq(report.decided, 3)
	assert_eq(report.reasons.get("turn_cap"), 1)
	var rows := report.deck_rows()
	var order: Dictionary = rows.filter(func(r): return r.label == "Order")[0]
	assert_eq(order.wins, 3, "deck a won games 0 and 2 in seat 1 and game 1 in seat 2")
	assert_eq(order.losses, 0)
	assert_eq(order.draws, 1)
	var matchup: Dictionary = report.matchup_rows()[0]
	assert_eq(matchup.a_wins, 3)
	assert_eq(matchup.b_wins, 0)
	assert_eq(matchup.draws, 1)


func test_seat_advantage_is_counted() -> void:
	var report := Report.new()
	for i in 6:
		report.add_record(_record(i, 1, i % 2 == 0))
	assert_eq(report.wins_by_seat[1], 6)
	assert_eq(report.wins_by_seat[2], 0)


func test_a_card_that_wins_games_is_flagged_strong() -> void:
	var report := Report.new()
	for i in 80:
		# "Righteous Guard" seen (even games): deck a wins 3 of 4. Unseen (odd games): deck a wins 1 of 4
		var seen := i % 2 == 0
		var a_wins := (i / 2) % 4 != 0 if seen else (i / 2) % 4 == 0
		var cards := {"Righteous Guard": _card(3, 1 if seen else 0, 1 if seen else 0)}
		report.add_record(_record(i, 1 if a_wins else 2, true, cards))
	var rows := report.card_rows().filter(func(r): return r.card == "Righteous Guard")
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].seen_games, 40)
	assert_almost_eq(rows[0].delta, 0.5, 0.001)
	assert_true("STRONG" in rows[0].flags, rows[0].flags)


func test_a_card_that_loses_games_is_flagged_weak() -> void:
	var report := Report.new()
	for i in 80:
		var seen := i % 2 == 0
		var a_wins := (i / 2) % 4 == 0 if seen else (i / 2) % 4 != 0
		report.add_record(_record(i, 1 if a_wins else 2, true,
				{"Righteous Guard": _card(3, 1 if seen else 0, 1 if seen else 0)}))
	var rows := report.card_rows().filter(func(r): return r.card == "Righteous Guard")
	assert_true("WEAK" in rows[0].flags, rows[0].flags)


func test_a_small_sample_is_never_flagged() -> void:
	var report := Report.new()
	for i in 6:
		report.add_record(_record(i, 1 if i % 2 == 0 else 2, true,
				{"Righteous Guard": _card(3, 1 if i % 2 == 0 else 0)}))
	for row in report.card_rows():
		assert_eq(row.flags, "", "6 games say nothing")


func test_a_card_mostly_played_as_energy_is_flagged() -> void:
	var report := Report.new()
	for i in 40:
		report.add_record(_record(i, 1 + i % 2, true, {"Smite": _card(2, 1, 0, 1)}))
	var row: Dictionary = report.card_rows().filter(func(r): return r.card == "Smite")[0]
	assert_true("MOSTLY-ENERGY" in row.flags, row.flags)
	assert_eq(row.energy_pct, 1.0)


func test_cards_that_were_never_in_the_deck_are_left_out() -> void:
	var report := Report.new()
	report.add_record(_record(0, 1, true, {"Smite": _card(0, 0, 1)}))
	assert_eq(report.card_rows().size(), 0, "a token has no copies in the deck")


func test_script_errors_are_added_up_over_games() -> void:
	var report := Report.new()
	report.add_record(_record(0, 1, true, {}, {}, 12, {"FxX.gd:12  boom": 3}))
	report.add_record(_record(1, 2, true, {}, {}, 12, {"FxX.gd:12  boom": 2, "FxY.gd:4  bang": 1}))
	assert_eq(report.errors["FxX.gd:12  boom"].count, 5)
	assert_eq(report.errors["FxX.gd:12  boom"].games, 2)
	assert_true("FxX.gd:12  boom" in report.format_text())


func test_the_text_and_csv_reports_work_on_an_empty_and_a_full_report() -> void:
	var report := Report.new()
	assert_ne(report.format_text(), "")
	report.add_record(_record(0, 1, true, {"Smite": _card()}, {"Meek Minion": _card()}))
	var text := report.format_text()
	assert_true("Order" in text and "Primal" in text and "Smite" in text, text)
	var csv := report.cards_csv()
	assert_eq(csv.split("\n", false).size(), 3, "the header and one line per card")
	assert_true(JSON.stringify(report.to_dict()) != "")


func test_records_survive_a_trip_through_json() -> void:
	# The records come from files: every number is a float there
	var report := Report.new()
	var record = JSON.parse_string(JSON.stringify(_record(0, 1, true, {"Smite": _card()})))
	report.add_record(record)
	assert_eq(report.games, 1)
	assert_eq(report.card_rows().size(), 1)
