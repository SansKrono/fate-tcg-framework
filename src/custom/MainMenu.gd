extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

@onready var v_buttons := $MainMenu/VBox/Center/VButtons
@onready var main_menu := $MainMenu
#onready var settings_menu := $SettingsMenu
@onready var deck_builder := $DeckBuilder
@onready var card_library := $CardLibrary

# Called when the node enters the scene tree for the first time.
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
#	settings_menu.rect_position.x = get_viewport().size.x
	deck_builder.position.x = -get_viewport().get_visible_rect().size.x
	card_library.position.x = -get_viewport().get_visible_rect().size.x
#	settings_menu.back_button.connect("pressed", self, "_on_Setings_Back_pressed")
#	settings_menu.recover_prebuilts.connect("pressed", self, "_on_PreBuilts_pressed")
	deck_builder.back_button.connect("pressed", Callable(self, "_on_DeckBuilder_Back_pressed"))
	card_library.back_button.connect("pressed", Callable(self, "_on_CardLibrary_Back_pressed"))
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", Callable(self, '_on_Menu_resized'))


func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"SinglePlayerDemo":
			# warning-ignore:return_value_discarded
			get_tree().change_scene_to_file(CFConst.PATH_CUSTOM + 'CGFMain.tscn')
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
		"Deckbuilder":
			switch_to_tab(deck_builder)
		"CardLibrary":
			switch_to_tab(card_library)
		"Exit":
			get_tree().quit()

func switch_to_tab(tab: Control) -> void:
	var main_position_x : float
	match tab:
#		settings_menu:
#			main_position_x = -get_viewport().size.x
		deck_builder, card_library:
			main_position_x = get_viewport().get_visible_rect().size.x
	$MenuTween.interpolate_property(main_menu,'position:x',
			main_menu.position.x, main_position_x, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.interpolate_property(tab,'position:x',
			tab.position.x, 0.0, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.start()


func switch_to_main_menu(tab: Control) -> void:
	var tab_position_x : float
	match tab:
#		settings_menu:
#			tab_position_x = get_viewport().size.x
		deck_builder, card_library:
			tab_position_x = -get_viewport().get_visible_rect().size.x
	$MenuTween.interpolate_property(tab,'position:x',
			tab.position.x, tab_position_x, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.interpolate_property(main_menu,'position:x',
			main_menu.position.x, 0.0, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.start()

func _on_DeckBuilder_Back_pressed() -> void:
	switch_to_main_menu(deck_builder)
	
func _on_CardLibrary_Back_pressed() -> void:
	switch_to_main_menu(card_library)
	
func _on_Menu_resized() -> void:
	for tab in [main_menu, deck_builder, card_library]:
		if is_instance_valid(tab):
			tab.size = get_viewport().get_visible_rect().size
			if tab.position.x < 0.0:
					tab.position.x = -get_viewport().get_visible_rect().size.x
			elif tab.position.x > 0.0:
					tab.position.x = get_viewport().get_visible_rect().size.x
