extends "res://tests/FateCommon.gd"
# AI against AI over many seeded games, to measure strength and to catch stalls and illegal moves that
# one game does not show. Both seats play the same deck (a mirror match, FateGame.domain_override), so
# the result says something about the levels and not about the decks; every pairing is played with the
# levels swapped between the seats, which cancels the advantage of going first.
#
# FATE_AI_GAMES=<n> (environment) sets the games per pairing; the default is small to keep the suite
# fast. The summary is printed; the assertions are loose on purpose.

const GAMES_DEFAULT := 2
const TURN_CAP := 60
const FRAME_BUDGET := 120000
const EASY := 0
const NORMAL := 1
const HARD := 2

var _problems: Array = []
var _stalled := 0


func after_each():
	FateGame.domain_override = {}


# Plays one game from a fresh table. Returns {"winner", "turns"}; winner 0 means the turn cap was hit.
func _game(domains: Array, level1: int, level2: int, seed_value: int) -> Dictionary:
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
	FateGame.domain_override = {1: domains, 2: domains}
	cfc.game_rng_seed = "tournament %d" % seed_value
	await before_each()
	var a = game.set_ai(1, true, level1)
	var b = game.set_ai(2, true, level2)
	var frames := 0
	while not game.is_over and game.turn_number < TURN_CAP and frames < FRAME_BUDGET:
		await get_tree().process_frame
		frames += 1
	if not game.is_over:
		_stalled += 1
	_problems.append_array(a.problems)
	_problems.append_array(b.problems)
	return {"winner": game.winner_id, "turns": game.turn_number}


# `strong` against `weak` on `domains`, seats swapped half of the games. Returns the strong side's wins,
# the weak side's wins and the average length.
func _match(domains: Array, strong: int, weak: int, games: int) -> Dictionary:
	var strong_wins := 0
	var weak_wins := 0
	var turns := 0
	for i in games:
		var strong_first: bool = i % 2 == 0
		var r: Dictionary = await _game(domains, strong if strong_first else weak,
				weak if strong_first else strong, i + 1)
		turns += r.turns
		if r.winner == 0:
			continue
		if (r.winner == 1) == strong_first:
			strong_wins += 1
		else:
			weak_wins += 1
	return {"strong": strong_wins, "weak": weak_wins, "turns": turns / maxi(1, games)}


func test_normal_beats_easy() -> void:
	# Opt-in: the AI is parked until the card logic exists (Order mirror games still stall at the turn
	# cap: most Order spells do nothing yet). Run with FATE_AI_GAMES=<n> to measure.
	if OS.get_environment("FATE_AI_GAMES") == "":
		pending("opt-in: set FATE_AI_GAMES=<games per pairing>")
		return
	var games := int(OS.get_environment("FATE_AI_GAMES")) if OS.get_environment("FATE_AI_GAMES") != "" \
			else GAMES_DEFAULT
	var strong := 0
	var weak := 0
	for domains in [["Order"], ["Primal"]]:
		var r: Dictionary = await _match(domains, NORMAL, EASY, games)
		print("TOURNAMENT %s: normal %d, easy %d, avg turns %d" % [domains[0], r.strong, r.weak, r.turns])
		strong += r.strong
		weak += r.weak
	print("TOURNAMENT total: normal %d, easy %d, stalled %d" % [strong, weak, _stalled])
	assert_eq(_problems, [], "no illegal moves")
	assert_eq(_stalled, 0, "every game ended before the turn cap")
	assert_gte(strong, weak, "normal does not lose to easy overall")
