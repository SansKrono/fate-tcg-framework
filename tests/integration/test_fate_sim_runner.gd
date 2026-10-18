extends GutTest
# The AI simulation runner (src/custom/fate/sim/FateSimRunner.gd) plays real games on the real engine and
# turns them into records. Short games (a low turn cap) keep this test quick; the numbers of the report
# are tested in tests/unit/test_fate_sim_report.gd.

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Runner := preload("res://src/custom/fate/sim/FateSimRunner.gd")
const Report := preload("res://src/custom/fate/sim/FateSimReport.gd")

var _runner


func before_each() -> void:
	_runner = Runner.new()


func after_each() -> void:
	await _runner.teardown()
	_runner.close()
	cfc.game_settings.fancy_movement = true


func _config(a: Dictionary, b: Dictionary, games := 2, turn_cap := 8) -> Dictionary:
	var config := Config.new_config([Config.matchup(a, b)], games, 1)
	config.turn_cap = turn_cap
	return config


func test_a_game_gives_a_record_with_both_seats_and_every_card_of_the_decks() -> void:
	var config := _config(Config.domain_deck("Order"), Config.domain_deck("Primal"))
	var record: Dictionary = await _runner.play_game(config, 0)
	assert_eq(record.type, "game")
	assert_true(record.reason in ["turn_cap", "life", "deck_out"], record.reason)
	assert_true(record.turns >= 1)
	assert_eq(record.seats["1"].label, "Order", "deck a goes first in game 0")
	assert_eq(record.seats["2"].label, "Primal")
	var copies := 0
	for card_name in record.seats["1"].cards:
		copies += record.seats["1"].cards[card_name].copies
	assert_eq(copies, FateDecks.DECK_SIZE, "all 40 cards are accounted for")
	var seen := 0
	for card_name in record.seats["1"].cards:
		seen += record.seats["1"].cards[card_name].seen
	assert_gte(seen, FateGame.STARTING_HAND, "at least the starting hand left the deck")
	assert_eq(record.seats["1"].life_by_turn.size() > 0, true)
	assert_eq(record.problems, [], "the AI asked for nothing illegal")


func test_the_seats_swap_between_games() -> void:
	var config := _config(Config.domain_deck("Order"), Config.domain_deck("Primal"))
	var second: Dictionary = await _runner.play_game(config, 1)
	assert_eq(second.seats["1"].label, "Primal", "deck b goes first in the next game")
	assert_eq(second.seats["1"].deck, 1)


func test_the_same_seed_plays_the_same_game() -> void:
	var config := _config(Config.domain_deck("Order"), Config.domain_deck("Order"), 1, 10)
	var first: Dictionary = await _runner.play_game(config, 0)
	var again: Dictionary = await _runner.play_game(config, 0)
	assert_eq(again.winner_seat, first.winner_seat)
	assert_eq(again.turns, first.turns)
	assert_eq(again.seats["1"].life_end, first.seats["1"].life_end)
	assert_eq(again.seats["2"].cards_played, first.seats["2"].cards_played)


func test_a_custom_deck_list_is_the_deck_that_is_played() -> void:
	var list: Dictionary = FateDecks.DECKLISTS["Order"].duplicate()
	list["Righteous Guard"] = 1
	list["Faithful Worshiper"] = 3
	list["Holy Healer"] = 3
	var custom := Config.deck(["Order"], "Custom", list)
	assert_eq(FateDecks.problems(list, ["Order"]), [], "test setup: a legal list")
	var record: Dictionary = await _runner.play_game(_config(custom, Config.domain_deck("Primal"), 1, 4), 0)
	assert_eq(record.seats["1"].label, "Custom")
	assert_eq(record.seats["1"].cards["Righteous Guard"].copies, 1)


func test_records_make_a_report() -> void:
	var config := _config(Config.domain_deck("Order"), Config.domain_deck("Primal"), 2, 6)
	var report := Report.new()
	for g in 2:
		report.add_record(await _runner.play_game(config, g))
	assert_eq(report.games, 2)
	assert_eq(report.decks.size(), 2)
	assert_ne(report.format_text(), "")


func test_script_errors_printed_during_a_game_are_counted_in_its_record() -> void:
	_runner._errors.take()
	push_error("sim test error")
	push_error("sim test error")
	var found: Dictionary = _runner._errors.take()
	assert_eq(found.size(), 1, "the same error counts up")
	assert_eq(found.values()[0], 2)
	assert_true("sim test error" in found.keys()[0], str(found))
	assert_eq(_runner._errors.take(), {}, "taking starts the count again")
