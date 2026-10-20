# The main script of one simulation process (FateSimWorker.tscn). It reads the run's config file, plays its
# share of the games one after the other and appends each finished game to its own result file as one JSON
# line, so the coordinator can follow the run while it goes on:
#
#   {"type": "hello", "worker": k, "pid": n}          the process is up
#   {"type": "game", ...}                             a finished game (FateSimRecorder)
#   {"type": "done", "worker": k, "games": n}         the share is played
#   {"type": "error", "worker": k, "text": "..."}     the worker gives up
#
# Started by FateSimCoordinator as
#   godot --headless --path <project> res://src/custom/fate/sim/FateSimWorker.tscn -- \
#       --sim-config=<file> --sim-worker=<k> --sim-out=<file>
# Worker k plays the games g of the run with g % workers == k.
#
# No class_name (see FateAIEval.gd).
extends Node

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Runner := preload("res://src/custom/fate/sim/FateSimRunner.gd")

var _out: FileAccess


func _ready() -> void:
	# The table is added to the root, which is still setting up its children: wait a frame
	await get_tree().process_frame
	# As fast as the machine allows: nobody watches
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := _args()
	var worker := int(args.get("sim-worker", "0"))
	_out = FileAccess.open(args.get("sim-out", ""), FileAccess.WRITE)
	if _out == null:
		push_error("FateSimWorker: cannot write %s" % args.get("sim-out", ""))
		get_tree().quit(2)
		return
	_write({"type": "hello", "worker": worker, "pid": OS.get_process_id()})
	var config = JSON.parse_string(FileAccess.get_file_as_string(args.get("sim-config", "")))
	if not config is Dictionary:
		_write({"type": "error", "worker": worker, "text": "cannot read the config %s" % args.get("sim-config", "")})
		get_tree().quit(2)
		return
	config = _fix_numbers(config)
	var runner := Runner.new()
	var played := 0
	var total := Config.total_games(config)
	var workers := int(config.workers)
	for g in range(worker, total, workers):
		var record: Dictionary = await runner.play_game(config, g)
		record["worker"] = worker
		_write(record)
		played += 1
	await runner.teardown()
	runner.close()
	_write({"type": "done", "worker": worker, "games": played})
	_out.close()
	get_tree().quit(0)


func _write(data: Dictionary) -> void:
	_out.store_line(JSON.stringify(data))
	_out.flush()


# `--name=value` user arguments as {name: value}
func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--") and "=" in text:
			var at := text.find("=")
			found[text.substr(2, at - 2)] = text.substr(at + 1)
	return found


# JSON turns every number into a float; the config wants whole numbers where it says so
static func _fix_numbers(config: Dictionary) -> Dictionary:
	for key in ["games", "workers", "turn_cap", "game_seconds"]:
		if config.has(key):
			config[key] = int(config[key])
	config["levels"] = config.get("levels", [1, 1]).map(func(v): return v if v is String or v is Dictionary else int(v))
	for mu in config.matchups:
		for side in ["a", "b"]:
			var list: Dictionary = mu[side].get("list", {})
			for card_name in list:
				list[card_name] = int(list[card_name])
	return config
