# Runs a simulation run (FateSimConfig) on several processes at once and collects what they find.
#
# Why processes: a Fate table is a scene tree with global lookups (cfc.NMAP), so one process can only play
# one game at a time. The coordinator starts N copies of the game (FateSimWorker.tscn, no window), gives each
# a share of the games, and reads their result files while they work. The report fills up live.
#
#   var run := Coordinator.new()
#   add_child(run)                      # it polls in _process
#   run.progress.connect(...)           # (done, total) after every finished game
#   run.finished.connect(...)           # (report) all games played, a worker died, or stop() was called
#   run.start(config)
#
# Everything of a run is kept in user://fate_sim/<run_id>/ : config.json, worker_<k>.jsonl (one JSON line per
# game, the raw data), and when the run ends report.txt, report.json and cards.csv. Games can be replayed:
# the seed of every game is in its record.
#
# No class_name (see FateAIEval.gd).
extends Node

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Report := preload("res://src/custom/fate/sim/FateSimReport.gd")
const WORKER_SCENE := "res://src/custom/fate/sim/FateSimWorker.tscn"
# Seconds between two reads of the result files
const POLL := 0.4
# A worker that has not said hello after this long is given up on
const HELLO_TIMEOUT := 90.0

signal progress(done: int, total: int)
signal game_finished(record: Dictionary)
signal finished(report)

var config: Dictionary = {}
var report
var run_dir := ""
var running := false
var stopped := false
var started_msec := 0

var _pids: Array = []
var _offsets: Array = []
var _partial: Array = []
var _hello: Array = []
var _done: Array = []
var _dead: Array = []
var _played: Array = []
var _clock := 0.0


# Starts the run. Returns "" or the reason it could not start.
func start(new_config: Dictionary) -> String:
	if running:
		return "a run is going on"
	var found := Config.problems(new_config)
	if not found.is_empty():
		return "; ".join(found)
	config = new_config.duplicate(true)
	var total := Config.total_games(config)
	config.workers = clampi(int(config.workers), 1, total)
	run_dir = Config.run_dir(config)
	DirAccess.make_dir_recursive_absolute(run_dir)
	var config_file := FileAccess.open(run_dir + "/config.json", FileAccess.WRITE)
	if config_file == null:
		return "cannot write %s" % run_dir
	config_file.store_string(JSON.stringify(config, "\t"))
	config_file.close()
	report = Report.new()
	stopped = false
	_pids.clear()
	_offsets.clear()
	_partial.clear()
	_hello.clear()
	_done.clear()
	_dead.clear()
	_played.clear()
	for k in int(config.workers):
		var pid := OS.create_process(OS.get_executable_path(), _worker_args(k))
		if pid <= 0:
			stop()
			return "could not start worker process %d" % k
		_pids.append(pid)
		_offsets.append(0)
		_partial.append("")
		_hello.append(false)
		_done.append(false)
		_dead.append(false)
		_played.append(0)
	running = true
	started_msec = Time.get_ticks_msec()
	_clock = 0.0
	return ""


func _worker_args(k: int) -> PackedStringArray:
	var args := PackedStringArray(["--headless"])
	# An exported game carries its project; the editor binary needs to be told which one
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append(WORKER_SCENE)
	args.append_array(["--", "--sim-config=" + ProjectSettings.globalize_path(run_dir + "/config.json"),
			"--sim-worker=%d" % k, "--sim-out=" + ProjectSettings.globalize_path(_result_file(k))])
	return args


func _result_file(k: int) -> String:
	return "%s/worker_%d.jsonl" % [run_dir, k]


func games_done() -> int:
	return report.games if report != null else 0


func games_total() -> int:
	return Config.total_games(config) if not config.is_empty() else 0


func elapsed() -> float:
	return (Time.get_ticks_msec() - started_msec) / 1000.0


# Stops the workers. The report keeps the games played so far; `finished` is emitted.
func stop() -> void:
	stopped = true
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	if running:
		_poll()
		_finish()


func _process(delta: float) -> void:
	if not running:
		return
	_clock += delta
	if _clock < POLL:
		return
	_clock = 0.0
	_poll()
	_check_workers()
	if not _any_alive():
		_poll()
		_finish()


func _any_alive() -> bool:
	for k in _pids.size():
		if not _done[k] and not _dead[k]:
			return true
	return false


# Reads the new lines of every result file
func _poll() -> void:
	for k in _pids.size():
		var file := FileAccess.open(_result_file(k), FileAccess.READ)
		if file == null:
			continue
		# get_as_text() would read the whole file again: read the new bytes only
		var new_bytes := int(file.get_length()) - int(_offsets[k])
		var text: String = _partial[k]
		if new_bytes > 0:
			file.seek(_offsets[k])
			text += file.get_buffer(new_bytes).get_string_from_utf8()
			_offsets[k] += new_bytes
		file.close()
		var lines := text.split("\n")
		# The last piece is a half-written line unless the text ended with a newline
		_partial[k] = lines[lines.size() - 1]
		for i in range(lines.size() - 1):
			if lines[i].strip_edges() != "":
				_handle_line(k, lines[i])


func _handle_line(k: int, line: String) -> void:
	var data = JSON.parse_string(line)
	if not data is Dictionary:
		return
	match data.get("type", ""):
		"hello":
			_hello[k] = true
		"game":
			report.add_record(data)
			_played[k] += 1
			game_finished.emit(data)
			progress.emit(report.games, games_total())
		"done":
			_done[k] = true
		"error":
			_dead[k] = true
			report.add_failure(k, str(data.get("text", "error")))


func _check_workers() -> void:
	for k in _pids.size():
		if _done[k] or _dead[k]:
			continue
		if not _hello[k] and elapsed() > HELLO_TIMEOUT:
			_dead[k] = true
			report.add_failure(k, "did not start within %d seconds" % int(HELLO_TIMEOUT))
			OS.kill(_pids[k])
		elif not OS.is_process_running(_pids[k]):
			# It may have said its last words just before it ended: read them first
			_poll()
			if not _done[k] and not _dead[k]:
				_dead[k] = true
				report.add_failure(k, ("stopped after %d games without finishing (crashed? run the worker by "
						+ "hand to see its output)") % _played[k])


func _finish() -> void:
	if not running:
		return
	running = false
	_save_report()
	finished.emit(report)


func _save_report() -> void:
	var text: String = report.format_text(0)
	_write("report.txt", text)
	_write("report.json", JSON.stringify(report.to_dict(), "\t"))
	_write("cards.csv", report.cards_csv())


func _write(file_name: String, text: String) -> void:
	var file := FileAccess.open("%s/%s" % [run_dir, file_name], FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


# The folder of the run on disk, for showing to the person
func global_run_dir() -> String:
	return ProjectSettings.globalize_path(run_dir)


# --- past runs -------------------------------------------------------------------------------------------

# The run folders in user://fate_sim, newest first
static func past_runs() -> Array:
	var found: Array = []
	var dir := DirAccess.open(Config.ROOT_DIR)
	if dir == null:
		return found
	for run_id in dir.get_directories():
		if FileAccess.file_exists("%s/%s/config.json" % [Config.ROOT_DIR, run_id]):
			found.append(run_id)
	found.sort()
	found.reverse()
	return found


# Rebuilds the report of a past run from the result files of its workers. Returns {"config": ..., "report": ...}
# or {} when the folder holds no run.
static func load_run(run_id: String) -> Dictionary:
	var run_path := "%s/%s" % [Config.ROOT_DIR, run_id]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(run_path + "/config.json"))
	if not parsed is Dictionary:
		return {}
	var rebuilt = Report.new()
	for file_name in DirAccess.get_files_at(run_path):
		if file_name.begins_with("worker_") and file_name.ends_with(".jsonl"):
			for line in FileAccess.get_file_as_string("%s/%s" % [run_path, file_name]).split("\n"):
				if line.strip_edges() == "":
					continue
				var record = JSON.parse_string(line)
				if record is Dictionary:
					rebuilt.add_record(record)
	return {"config": parsed, "report": rebuilt}
