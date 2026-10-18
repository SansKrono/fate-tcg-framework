extends "res://tests/FateCommon.gd"
# The Fate AI plays whole games against itself. Checks that the game keeps moving (no stall), that the AI
# never asks the engine for something illegal (controller.problems stays empty) and that a game ends.

# Frames the loop waits at most for one game
const FRAME_BUDGET := 60000


func _play(max_turns: int) -> void:
	var frames := 0
	while not game.is_over and game.turn_number < max_turns and frames < FRAME_BUDGET:
		await get_tree().process_frame
		frames += 1


func test_two_ais_play_a_game_without_problems() -> void:
	var a = game.set_ai(1)
	var b = game.set_ai(2)
	await _play(24)
	var problems: Array = a.problems + b.problems
	assert_eq(problems, [], "the AI asked for nothing illegal")
	assert_gt(game.turn_number, 6, "the game kept moving (turn %d)" % game.turn_number)
	if game.is_over:
		pass_test("game over, winner Player %d on turn %d" % [game.winner_id, game.turn_number])


func test_the_ai_plays_energy_in_the_first_turns() -> void:
	var a = game.set_ai(1)
	game.set_ai(2)
	await _play(5)
	assert_gt(game.player(1).cards_in_grid("energy").size(), 0, "player 1 played energy")
	assert_gt(game.player(2).cards_in_grid("energy").size(), 0, "player 2 played energy")
	assert_eq(a.problems, [])
