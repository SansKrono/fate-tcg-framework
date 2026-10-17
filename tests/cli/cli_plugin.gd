extends "res://tests/tests_runner.gd"
# run this scene for cli --> scene is set to auto run on load & will quit the game
# on test completion
# Alternatively, run GUT's own command line runner:
# godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit

func _init() -> void:
	quit_on_finish = true
