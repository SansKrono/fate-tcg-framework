# Plays one AI-against-AI game of a simulation run on a fresh Fate table and returns its record
# (FateSimRecorder). This is the real engine with the real cards: the table is built exactly like the
# tests build it, the games just run without anybody watching (cfc.is_testing, no animations, no pauses).
#
# One runner plays its games one after the other, because the table is a scene tree with global lookups
# (cfc.NMAP): two tables cannot live in one process. Games in parallel are separate processes, see
# FateSimWorker and FateSimCoordinator.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Recorder := preload("res://src/custom/fate/sim/FateSimRecorder.gd")
const ErrorLog := preload("res://src/custom/fate/sim/FateSimErrorLog.gd")
const FATE_MAIN := preload("res://src/custom/fate/FateMain.tscn")
const VIEWPORT := Vector2i(1280, 720)

var tree: SceneTree
var _main: Node
var _errors := ErrorLog.new()


func _init() -> void:
	tree = Engine.get_main_loop() as SceneTree
	OS.add_logger(_errors)


# Stops listening for errors. A runner that is thrown away without it keeps its logger in the engine.
func close() -> void:
	OS.remove_logger(_errors)


# Plays game number `g` of the run `config` (see FateSimConfig). Returns the record of the game.
func play_game(config: Dictionary, g: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var mu: Dictionary = config.matchups[Config.matchup_of_game(config, g)]
	var decks := [mu.a, mu.b]
	var seat1: int = Config.deck_in_seat_1(config, g)
	var deck_of_seat := {1: seat1, 2: 1 - seat1}
	await teardown()
	_errors.take()
	FateGame.domain_override = {1: decks[seat1].domains, 2: decks[1 - seat1].domains}
	FateGame.decklist_override = {}
	for seat in deck_of_seat:
		var list: Dictionary = decks[deck_of_seat[seat]].get("list", {})
		if not list.is_empty():
			FateGame.decklist_override[seat] = list
	cfc.game_rng_seed = Config.game_seed(config, g)
	var game: FateGame = await _build_table()
	var labels := {}
	for seat in deck_of_seat:
		labels[seat] = decks[deck_of_seat[seat]].label
	var recorder := Recorder.new(game, labels, deck_of_seat)
	var levels: Array = config.get("levels", [1, 1])
	for seat in deck_of_seat:
		game.set_ai(seat, true, int(levels[deck_of_seat[seat]]))
	game.doctrines.enabled = config.get("doctrines", true)
	var turn_cap: int = int(config.get("turn_cap", 60))
	var deadline := Time.get_ticks_msec() + int(config.get("game_seconds", 120)) * 1000
	var frames := 0
	while not game.is_over and game.turn_number < turn_cap and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		frames += 1
	var reason := ""
	if not game.is_over:
		reason = "turn_cap" if game.turn_number >= turn_cap else "stall"
	var record := recorder.finish({
		"game": g, "matchup": Config.matchup_of_game(config, g), "seed": Config.game_seed(config, g),
		"frames": frames, "ms": Time.get_ticks_msec() - started,
	}, reason)
	recorder.disconnect_all()
	record["errors"] = _errors.take()
	return record


# Removes the table of the last game
func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		await tree.process_frame
	_main = null
	FateGame.domain_override = {}
	FateGame.decklist_override = {}


# The same table the tests use (tests/FateCommon.gd before_each), but the game is not waited for: the
# caller connects its recorder first. Returns the FateGame, not started yet.
func _build_table() -> FateGame:
	var root := tree.root
	root.size = VIEWPORT
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = VIEWPORT
	cfc.is_testing = true
	cfc._setup()
	cfc.game_settings.fancy_movement = false
	_main = FATE_MAIN.instantiate()
	root.add_child(_main)
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	var board = cfc.NMAP.board
	var game: FateGame = board.game
	if game.is_started:
		push_warning("FateSimRunner: the game started before the recorder was connected")
	return game
