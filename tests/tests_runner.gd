# Runs the unit tests in-game using GUT 9's GutRunner, which shows the
# classic full-window GUT log (with the Godot and GUT versions, the progress
# bars and the results as they come in).
# Replaces the GUT 7 "res://addons/gut/plugin_control.gd" runner,
# which no longer exists in GUT 9.
#
# Settings (directories, prefix etc) are read from res://.gutconfig.json
# The tests start running as soon as the scene is loaded.
#
# To run the tests from the command line instead, use:
# godot --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
extends Node

const CONFIG_FILE := "res://.gutconfig.json"
const GutRunnerScene := preload("res://addons/gut/gui/GutRunner.tscn")
const GutConfigScript := preload("res://addons/gut/gut_config.gd")

# If true, the game will quit once the tests are finished
@export var quit_on_finish := false

var runner: Node


func _ready() -> void:
	var config = GutConfigScript.new()
	config.load_options(CONFIG_FILE)
	if quit_on_finish:
		config.options.should_exit = true
	runner = GutRunnerScene.instantiate()
	runner.set_gut_config(config)
	add_child(runner)
	# The runner builds its GUI in its own _ready(), so we start after that.
	runner.call_deferred("run_tests")
