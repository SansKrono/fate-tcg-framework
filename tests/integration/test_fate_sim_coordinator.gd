extends GutTest
# The simulation coordinator starts real Godot processes (FateSimWorker) and the Sim Lab screen shows what
# they find. These tests start two processes with a few short games each, so they take a while: a minute
# at most.

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Coordinator := preload("res://src/custom/fate/sim/FateSimCoordinator.gd")
const SCREEN := preload("res://src/custom/fate/sim/FateSimScreen.tscn")

var _run
var _dirs: Array = []


func after_each() -> void:
	if _run != null and is_instance_valid(_run):
		if _run.running:
			_run.stop()
		_run.queue_free()
	for run_dir in _dirs:
		_remove_dir(run_dir)
	_dirs.clear()
	await get_tree().process_frame


func _remove_dir(path: String) -> void:
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute("%s/%s" % [path, file_name])
	DirAccess.remove_absolute(path)


func _config(games := 4, workers := 2) -> Dictionary:
	var config := Config.new_config([Config.matchup(Config.domain_deck("Order"), Config.domain_deck("Primal"))],
			games, workers)
	config.turn_cap = 6
	return config


func test_two_processes_play_all_the_games_and_the_files_are_written() -> void:
	_run = Coordinator.new()
	add_child(_run)
	var config := _config(4, 2)
	_dirs.append(Config.run_dir(config))
	assert_eq(_run.start(config), "")
	await wait_for_signal(_run.finished, 150)
	assert_false(_run.running)
	assert_eq(_run.report.games, 4, "every game came back")
	assert_eq(_run.report.failures, [])
	assert_eq(_run.report.problems, [], "no illegal AI moves")
	for file_name in ["config.json", "report.txt", "report.json", "cards.csv", "worker_0.jsonl", "worker_1.jsonl"]:
		assert_true(FileAccess.file_exists("%s/%s" % [_run.run_dir, file_name]), file_name)
	var seen_workers := {}
	for k in 2:
		for line in FileAccess.get_file_as_string("%s/worker_%d.jsonl" % [_run.run_dir, k]).split("\n", false):
			var data = JSON.parse_string(line)
			if data.type == "game":
				seen_workers[int(data.worker)] = true
	assert_eq(seen_workers.size(), 2, "both processes played")


func test_a_past_run_can_be_loaded_again() -> void:
	_run = Coordinator.new()
	add_child(_run)
	var config := _config(2, 1)
	_dirs.append(Config.run_dir(config))
	assert_eq(_run.start(config), "")
	await wait_for_signal(_run.finished, 150)
	var loaded := Coordinator.load_run(config.run_id)
	assert_false(loaded.is_empty())
	assert_eq(loaded.report.games, 2)
	assert_true(config.run_id in Coordinator.past_runs())


func test_stopping_a_run_keeps_what_was_played() -> void:
	_run = Coordinator.new()
	add_child(_run)
	var config := _config(40, 2)
	config.turn_cap = 60
	_dirs.append(Config.run_dir(config))
	assert_eq(_run.start(config), "")
	await wait_for_signal(_run.progress, 150)
	_run.stop()
	assert_false(_run.running)
	assert_gte(_run.report.games, 1)
	assert_lt(_run.report.games, 40)
	assert_true(FileAccess.file_exists(_run.run_dir + "/report.txt"), "the partial report is saved")


func test_a_run_that_cannot_work_is_refused_before_anything_starts() -> void:
	_run = Coordinator.new()
	add_child(_run)
	var config := _config(0, 1)
	assert_ne(_run.start(config), "")
	assert_false(_run.running)


func test_the_sim_lab_screen_runs_a_simulation_and_fills_its_tables() -> void:
	var screen = SCREEN.instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen._games.value = 2
	screen._workers.value = 2
	screen._turn_cap.value = 10
	_dirs.append("")
	screen._on_start()
	assert_eq(screen._message.text, "")
	assert_true(screen._run.running)
	_dirs[0] = screen._run.run_dir
	await wait_for_signal(screen._run.finished, 150)
	await get_tree().process_frame
	assert_true("GAMES" in screen._report_text.text)
	assert_eq(screen._decks_tree.get_root().get_child_count(), 2, "one row per deck")
	assert_gt(screen._cards_tree.get_root().get_child_count(), 10, "the cards of both decks")
	assert_eq(screen._matchups_tree.get_root().get_child_count(), 1)
	assert_eq(screen._progress.value, 2.0)
	screen.queue_free()
