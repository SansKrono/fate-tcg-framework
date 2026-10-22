# The title screen: the Fate table (after both players chose a deck), the AI simulation lab, the
# test runner.
extends Panel

@onready var v_buttons := $MainMenu/VBox/Center/VButtons


func _ready() -> void:
	# The AI simulation lab sits under the Fate button (a copy of it, so it looks the same)
	var fate_button: Button = v_buttons.get_node_or_null("Multiplayer")
	if fate_button != null:
		var lab_button: Button = fate_button.duplicate()
		lab_button.name = "FateSimLab"
		lab_button.text = "Fate AI Simulation Lab"
		v_buttons.add_child(lab_button)
		v_buttons.move_child(lab_button, fate_button.get_index() + 1)
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', Callable(self, 'on_button_pressed').bind(option_button.name))


func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"Multiplayer":
			# The Fate proof of concept: a hotseat two-player table, after both players chose a deck
			# warning-ignore:return_value_discarded
			get_tree().change_scene_to_file(CFConst.PATH_CUSTOM + 'fate/FateDeckSelect.tscn')
		"FateSimLab":
			# warning-ignore:return_value_discarded
			get_tree().change_scene_to_file(CFConst.PATH_CUSTOM + 'fate/sim/FateSimScreen.tscn')
		"GUT":
			# warning-ignore:return_value_discarded
			get_tree().change_scene_to_file("res://tests/tests.tscn")
		"Exit":
			get_tree().quit()
