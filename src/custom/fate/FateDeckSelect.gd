# The deck selection screen of the two-player game: each player picks one of the decks of the catalogue
# (FateDecks.presets(): an optimised deck and a starter deck per domain), then "Start game" opens the table
# with those decks. Reached from the main menu.
#
# The choice reaches the table through FateGame.domain_override and FateGame.decklist_override (what the
# tests and the AI simulation use too), set by FateDecks.select(). A table opened without this screen
# (the scene run on its own) plays the default decks, Order against Primal.
#
# Built in code like the debug tools (FateDebug).
# No class_name (see FateAIEval.gd).
extends Control

const MENU_SCENE := "res://src/custom/MainMenu.tscn"
const TABLE_SCENE := "res://src/custom/fate/FateMain.tscn"
# The decks chosen when the screen opens (preset ids): the optimised decks of the original pairing
const DEFAULT_CHOICE := {1: "order_optimised", 2: "primal_optimised"}
const PLAYER_NAMES := {1: "Player 1", 2: "Player 2"}

var presets: Array = []
# Player id -> the id of the chosen preset
var choice := {}

var _buttons := {}
var _details := {}
var _start_button: Button
var _group := {}


func _ready() -> void:
	FateGame.register_cards()
	presets = FateDecks.presets()
	theme = FateTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = FateTheme.BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(_build_header())
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	root.add_child(columns)
	for pid in PLAYER_NAMES:
		var column := _build_column(pid)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		select(pid, _default_for(pid))
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	var swap := Button.new()
	swap.text = "Swap decks"
	swap.pressed.connect(swap_decks)
	footer.add_child(swap)
	_start_button = Button.new()
	_start_button.text = "Start game"
	_start_button.custom_minimum_size = Vector2(160, 36)
	_start_button.pressed.connect(start_game)
	footer.add_child(_start_button)


func _default_for(pid: int) -> String:
	var wanted: String = DEFAULT_CHOICE[pid]
	for preset in presets:
		if preset.id == wanted:
			return wanted
	return presets[0].id


# --- choosing -------------------------------------------------------------------------------------------------

# Chooses the deck of a player (a preset id). Returns false for an unknown id.
func select(pid: int, preset_id: String) -> bool:
	if FateDecks.preset(preset_id).is_empty():
		return false
	choice[pid] = preset_id
	if _buttons.has(pid):
		# set_pressed_no_signal() does not release the other buttons of the group
		for id in _buttons[pid]:
			_buttons[pid][id].set_pressed_no_signal(id == preset_id)
	_show_details(pid)
	return true


func swap_decks() -> void:
	var first: String = choice[1]
	select(1, choice[2])
	select(2, first)


# Applies the choice and opens the table
func start_game() -> void:
	for pid in choice:
		FateDecks.select(pid, choice[pid])
	get_tree().change_scene_to_file(TABLE_SCENE)


func _on_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# --- building the screen ----------------------------------------------------------------------------------

func _build_header() -> Control:
	var row := HBoxContainer.new()
	var title := FateTheme.label("Choose your decks", 22, FateTheme.GOLD, "Bold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(_on_back)
	row.add_child(back)
	return row


func _build_column(pid: int) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(FateTheme.label(PLAYER_NAMES[pid], 16, FateTheme.GOLD, "SemiBold"))
	var group := ButtonGroup.new()
	_group[pid] = group
	_buttons[pid] = {}
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for preset in presets:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = "%s\n%s" % [preset.name, preset.tier]
		button.custom_minimum_size = Vector2(0, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_color_override("font_color", FateTheme.domain_color(preset.domain))
		button.add_theme_color_override("font_pressed_color", FateTheme.domain_color(preset.domain).lightened(0.4))
		button.pressed.connect(select.bind(pid, preset.id))
		grid.add_child(button)
		_buttons[pid][preset.id] = button
	var details := RichTextLabel.new()
	details.bbcode_enabled = true
	details.fit_content = false
	details.scroll_active = true
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.custom_minimum_size = Vector2(0, 300)
	_details[pid] = details
	box.add_child(details)
	return panel


func _show_details(pid: int) -> void:
	if not _details.has(pid):
		return
	var preset := FateDecks.preset(choice[pid])
	var color := FateTheme.domain_color(preset.domain).to_html(false)
	var text := "[color=#%s][b]%s[/b][/color]  (%s, %s)\n%s\n\n" % [
			color, preset.name, preset.domain, preset.tier, preset.blurb]
	var curve := FateDecks.mana_curve(preset.list)
	var bars := []
	for mv in range(0, 8):
		bars.append("%d: %s %d" % [mv, "#".repeat(curve.get(mv, 0)), curve.get(mv, 0)] if curve.get(mv, 0) > 0 \
				else "%d: -" % mv)
	text += "[b]Mana curve[/b]\n[code]%s[/code]\n\n" % "\n".join(bars)
	var types := FateDecks.type_counts(preset.list)
	text += "[b]Cards[/b]  %s\n" % ", ".join(types.keys().map(func(t): return "%d %s" % [types[t], t.to_lower()]))
	var names: Array = preset.list.keys()
	names.sort_custom(func(a, b): return [FateDecks.mana_value(a), a] < [FateDecks.mana_value(b), b])
	var lines := []
	for card_name in names:
		lines.append("%dx %s (%d)" % [preset.list[card_name], card_name, FateDecks.mana_value(card_name)])
	text += "[code]%s[/code]" % "\n".join(lines)
	_details[pid].text = text
