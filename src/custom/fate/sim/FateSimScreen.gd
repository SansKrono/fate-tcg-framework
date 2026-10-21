# The AI Simulation Lab: pick two decks (or every domain against every other), say how many games and how
# many processes, and watch the report fill up while the AI plays them. Reached from the main menu.
#
# The screen only drives a FateSimCoordinator (src/custom/fate/sim/) and shows what its report says; the
# games are played by separate Godot processes, so this window stays responsive.
#
# Built in code like the debug tools (FateDebug). No class_name (see FateAIEval.gd).
extends Control

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Coordinator := preload("res://src/custom/fate/sim/FateSimCoordinator.gd")
const Report := preload("res://src/custom/fate/sim/FateSimReport.gd")
const MENU_SCENE := "res://src/custom/MainMenu.tscn"
const CUSTOM_DECK := "Deck file..."
# Seconds between two rebuilds of the tables while a run is going on
const REFRESH := 1.0

# Columns of the tables: [title, row key, kind, width]. Kinds: str, int, pct, delta, num
const DECK_COLUMNS := [
	["Deck", "label", "str", 110], ["Games", "games", "int", 55], ["Win rate", "wr", "pct", 70],
	["+-", "wr_ci", "pct", 55], ["On play", "wr_on_play", "pct", 65], ["On draw", "wr_on_draw", "pct", 65],
	["End life", "life_end", "num", 65], ["Lost/game", "creatures_lost", "num", 70],
	["Mana used", "mana_eff", "pct", 75], ["Board", "board", "num", 55], ["Casts/turn", "casts_per_turn", "num", 75],
	["Dmg taken/game", "dmg_taken_per_game", "num", 100], ["Flag", "flag", "str", 110],
]
const CARD_COLUMNS := [
	["Deck", "label", "str", 80], ["Card", "card", "str", 190], ["Type", "type", "str", 70], ["MV", "mv", "int", 35],
	["x", "copies", "int", 30], ["Seen", "seen_pct", "pct", 55], ["WR seen", "wr_seen", "pct", 65],
	["WR unseen", "wr_unseen", "pct", 70], ["Delta", "delta", "delta", 60], ["Casts", "plays_per_seen", "num", 50],
	["Energy", "energy_pct", "pct", 55], ["Unused", "unused_pct", "pct", 60], ["Turn", "avg_turn", "num", 45],
	["Dmg C", "dmg_c", "num", 50], ["Dmg P", "dmg_p", "num", 50], ["Kills", "kills", "num", 45],
	["Deaths", "deaths", "num", 50], ["Flags", "flags", "str", 150],
]
const MATCHUP_COLUMNS := [
	["Deck A", "a", "str", 110], ["Deck B", "b", "str", 110], ["Games", "games", "int", 55], ["A wins", "a_wins", "int", 60],
	["B wins", "b_wins", "int", 60], ["Draws", "draws", "int", 55], ["A win rate", "wr_a", "pct", 75],
	["+-", "wr_ci", "pct", 55], ["Avg turns", "avg_turns", "num", 70],
]

var _run
var _report
var _config: Dictionary = {}
var _clock := 0.0
var _dirty := false

var _deck_choice := [null, null]
var _deck_file := [null, null]
var _level_choice := [null, null]
# Optional profile specs (FateAIProfile): "hard+aggro;caution=0.3" or a profile file; replaces the grade when filled in
var _profile_text := [null, null]
var _round_robin: CheckBox
# One deck picker per domain, shown in round robin mode: {domain: OptionButton}
var _robin_choice := {}
var _robin_box: VBoxContainer
var _games: SpinBox
var _workers: SpinBox
var _seed: LineEdit
var _turn_cap: SpinBox
var _swap: CheckBox
var _doctrines: CheckBox
var _start: Button
var _stop: Button
var _open: Button
var _past: OptionButton
var _progress: ProgressBar
var _status: Label
var _message: Label
var _tabs: TabContainer
var _report_text: RichTextLabel
var _decks_tree: Tree
var _cards_tree: Tree
var _cards_filter: OptionButton
var _matchups_tree: Tree
var _sort := {}


func _ready() -> void:
	FateGame.register_cards()
	theme = FateTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = FateTheme.BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	root.add_child(_build_header())
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	root.add_child(split)
	split.add_child(_build_setup())
	split.add_child(_build_results())
	_run = Coordinator.new()
	add_child(_run)
	_run.progress.connect(_on_progress)
	_run.finished.connect(_on_finished)
	_refresh_past_runs()
	_set_running(false)
	_show_report(null)


func _exit_tree() -> void:
	if _run != null and is_instance_valid(_run) and _run.running:
		_run.stop()


func _process(delta: float) -> void:
	if _run == null or not _run.running:
		return
	_clock += delta
	if _clock >= REFRESH:
		_clock = 0.0
		_update_status()
		if _dirty:
			_dirty = false
			_show_report(_run.report)


# --- building the screen ----------------------------------------------------------------------------------

func _build_header() -> Control:
	var row := HBoxContainer.new()
	var title := FateTheme.label("AI Simulation Lab", 22, FateTheme.GOLD, "Bold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(_on_back)
	row.add_child(back)
	return row


func _build_setup() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_heading("Decks"))
	for side in 2:
		var row := HBoxContainer.new()
		row.add_child(_small("Deck %s" % ["A", "B"][side], 50))
		var choice := OptionButton.new()
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for domain in Config.DOMAINS:
			choice.add_item(domain)
		for preset in FateDecks.presets():
			choice.add_item("%s (%s)" % [preset.name, preset.tier.to_lower()])
			choice.set_item_metadata(choice.item_count - 1, preset.id)
		choice.add_item(CUSTOM_DECK)
		choice.select(side)
		_deck_choice[side] = choice
		row.add_child(choice)
		box.add_child(row)
		var file := LineEdit.new()
		file.placeholder_text = "path of a deck .json file"
		file.visible = false
		_deck_file[side] = file
		box.add_child(file)
		choice.item_selected.connect(func(i): file.visible = choice.get_item_text(i) == CUSTOM_DECK)
	_round_robin = CheckBox.new()
	_round_robin.text = "Round robin: every domain against every other"
	_round_robin.tooltip_text = "Plays all pairs of the four domains, with the deck picked for each below. Use it to see how the domains stand against each other."
	_round_robin.toggled.connect(_on_round_robin)
	box.add_child(_round_robin)
	_robin_box = VBoxContainer.new()
	_robin_box.visible = false
	for domain in Config.DOMAINS:
		var robin_row := HBoxContainer.new()
		robin_row.add_child(_small(domain, 60))
		var robin := OptionButton.new()
		robin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		robin.add_item("%s (default)" % domain)
		for preset in FateDecks.presets():
			if preset.domain == domain:
				robin.add_item("%s (%s)" % [preset.name, preset.tier.to_lower()])
				robin.set_item_metadata(robin.item_count - 1, preset.id)
		_robin_choice[domain] = robin
		robin_row.add_child(robin)
		_robin_box.add_child(robin_row)
	box.add_child(_robin_box)
	box.add_child(_heading("Games"))
	_games = _spin(box, "Games per matchup", 1, 5000, 20)
	_workers = _spin(box, "Processes in parallel", 1, 32, Config.default_workers())
	_turn_cap = _spin(box, "Turn cap (draw after)", 10, 300, 60)
	for side in 2:
		var row := HBoxContainer.new()
		row.add_child(_small("AI level %s" % ["A", "B"][side], 110))
		var level := OptionButton.new()
		for level_name in Config.LEVEL_NAMES:
			level.add_item(level_name)
		level.select(1)
		_level_choice[side] = level
		row.add_child(level)
		var spec := LineEdit.new()
		spec.placeholder_text = "or profile: hard+aggro;caution=0.3"
		spec.tooltip_text = "A profile spec (grade, style, parameters or a profile file, see src/custom/fate/ai/README.md). Replaces the grade when filled in."
		spec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_profile_text[side] = spec
		row.add_child(spec)
		box.add_child(row)
	var seed_row := HBoxContainer.new()
	seed_row.add_child(_small("Seed", 110))
	_seed = LineEdit.new()
	_seed.text = "fate sim"
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed)
	box.add_child(seed_row)
	_swap = CheckBox.new()
	_swap.text = "Alternate who goes first"
	_swap.button_pressed = true
	box.add_child(_swap)
	_doctrines = CheckBox.new()
	_doctrines.text = "Start with the doctrine cards"
	_doctrines.button_pressed = true
	box.add_child(_doctrines)
	var buttons := HBoxContainer.new()
	_start = Button.new()
	_start.text = "Start"
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	_stop = Button.new()
	_stop.text = "Stop"
	_stop.pressed.connect(_on_stop)
	buttons.add_child(_stop)
	_open = Button.new()
	_open.text = "Open folder"
	_open.pressed.connect(_on_open_folder)
	buttons.add_child(_open)
	box.add_child(buttons)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 18)
	box.add_child(_progress)
	_status = FateTheme.label("", 12, FateTheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_message = FateTheme.label("", 12, FateTheme.DANGER)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)
	box.add_child(_heading("Earlier runs"))
	_past = OptionButton.new()
	_past.item_selected.connect(_on_past_selected)
	box.add_child(_past)
	return panel


func _build_results() -> Control:
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report_text = RichTextLabel.new()
	_report_text.name = "Report"
	_report_text.selection_enabled = true
	_report_text.scroll_active = true
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	_report_text.add_theme_font_override("normal_font", mono)
	_report_text.add_theme_font_size_override("normal_font_size", 12)
	_tabs.add_child(_report_text)
	_decks_tree = _tree("Decks", DECK_COLUMNS)
	var cards_box := VBoxContainer.new()
	cards_box.name = "Cards"
	var filter_row := HBoxContainer.new()
	filter_row.add_child(_small("Deck", 40))
	_cards_filter = OptionButton.new()
	_cards_filter.add_item("All")
	_cards_filter.item_selected.connect(func(_i): _fill_cards())
	filter_row.add_child(_cards_filter)
	cards_box.add_child(filter_row)
	_cards_tree = _make_tree(CARD_COLUMNS)
	cards_box.add_child(_cards_tree)
	_tabs.add_child(cards_box)
	_matchups_tree = _tree("Matchups", MATCHUP_COLUMNS)
	return _tabs


func _heading(text: String) -> Label:
	return FateTheme.label(text, 14, FateTheme.GOLD, "SemiBold")


func _small(text: String, width: float) -> Label:
	var label := FateTheme.label(text, 12, FateTheme.MUTED)
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _spin(parent: Control, text: String, low: int, high: int, value: int) -> SpinBox:
	var row := HBoxContainer.new()
	var label := _small(text, 170)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _tree(tab_name: String, columns: Array) -> Tree:
	var tree := _make_tree(columns)
	tree.name = tab_name
	_tabs.add_child(tree)
	return tree


func _make_tree(columns: Array) -> Tree:
	var tree := Tree.new()
	tree.columns = columns.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in columns.size():
		tree.set_column_title(i, columns[i][0])
		tree.set_column_custom_minimum_width(i, columns[i][3])
		tree.set_column_expand(i, columns[i][2] == "str" and i >= columns.size() - 1)
	tree.column_title_clicked.connect(_on_title_clicked.bind(tree, columns))
	return tree


# --- starting and stopping --------------------------------------------------------------------------------

func _on_start() -> void:
	_message.text = ""
	var matchups: Array = []
	if _round_robin.button_pressed:
		matchups = Config.round_robin(Config.DOMAINS.map(_robin_deck))
	else:
		var decks: Array = []
		for side in 2:
			var found := _chosen_deck(side)
			if found.has("error"):
				_message.text = "Deck %s: %s" % ["AB"[side], found.error]
				return
			decks.append(found)
		matchups = [Config.matchup(decks[0], decks[1])]
	var config := Config.new_config(matchups, int(_games.value), int(_workers.value))
	config.seed = _seed.text
	config.turn_cap = int(_turn_cap.value)
	config.swap_seats = _swap.button_pressed
	config.doctrines = _doctrines.button_pressed
	config.levels = []
	for side in 2:
		var text: String = _profile_text[side].text.strip_edges()
		config.levels.append(text if text != "" else _level_choice[side].selected)
	var problem: String = _run.start(config)
	if problem != "":
		_message.text = problem
		return
	_config = _run.config
	_dirty = true
	_report = _run.report
	_set_running(true)
	_update_status()
	_show_report(_report)


func _chosen_deck(side: int) -> Dictionary:
	var choice: OptionButton = _deck_choice[side]
	var text := choice.get_item_text(choice.selected)
	if text == CUSTOM_DECK:
		return Config.deck_from_file(_deck_file[side].text.strip_edges())
	var preset_id = choice.get_item_metadata(choice.selected)
	if preset_id is String:
		return Config.preset_deck(preset_id)
	return Config.domain_deck(text)


func _on_stop() -> void:
	_run.stop()


# The deck picked for a domain in the round robin
func _robin_deck(domain: String) -> Dictionary:
	var choice: OptionButton = _robin_choice[domain]
	var preset_id = choice.get_item_metadata(choice.selected)
	if preset_id is String:
		return Config.preset_deck(preset_id)
	return Config.domain_deck(domain)


func _on_round_robin(on: bool) -> void:
	_robin_box.visible = on
	for side in 2:
		_deck_choice[side].disabled = on
		_deck_file[side].editable = not on


func _set_running(on: bool) -> void:
	_start.disabled = on
	_stop.disabled = not on
	_open.disabled = _run == null or _run.run_dir == ""
	_past.disabled = on


func _on_progress(_done: int, _total: int) -> void:
	_dirty = true


func _on_finished(report) -> void:
	_set_running(false)
	_update_status()
	_show_report(report)
	_refresh_past_runs()


func _update_status() -> void:
	var done: int = _run.games_done()
	var total: int = _run.games_total()
	_progress.max_value = maxi(1, total)
	_progress.value = done
	var seconds: float = _run.elapsed()
	var text := "%d / %d games" % [done, total]
	if done > 0 and _run.running:
		var per_game := seconds / done
		text += "   %.1f games/min   about %d s left" % [60.0 / maxf(0.001, per_game), int(per_game * (total - done))]
	elif not _run.running and seconds > 0.0:
		text += "   %d s" % int(seconds)
	if _run.report != null and not _run.report.failures.is_empty():
		text += "\n%d worker(s) failed, see the report" % _run.report.failures.size()
	_status.text = text


func _on_open_folder() -> void:
	if _run != null and _run.run_dir != "":
		OS.shell_open(_run.global_run_dir())


func _on_back() -> void:
	if _run != null and _run.running:
		_run.stop()
	get_tree().change_scene_to_file(MENU_SCENE)


# --- earlier runs -----------------------------------------------------------------------------------------

func _refresh_past_runs() -> void:
	_past.clear()
	_past.add_item("(choose a run)")
	for run_id in Coordinator.past_runs():
		_past.add_item(run_id)


func _on_past_selected(index: int) -> void:
	if index <= 0:
		return
	var loaded := Coordinator.load_run(_past.get_item_text(index))
	if loaded.is_empty():
		_message.text = "That folder holds no run."
		return
	_message.text = ""
	_config = loaded.config
	_report = loaded.report
	_progress.max_value = maxi(1, Config.total_games(_config))
	_progress.value = _report.games
	_status.text = "%d games from an earlier run" % _report.games
	_show_report(_report)


# --- showing the report -----------------------------------------------------------------------------------

func _show_report(report) -> void:
	_report = report
	if report == null:
		_report_text.text = "Choose two decks and press Start.\n\nThe games are played by %d separate processes at the same time; this page fills up while they run." % int(_workers.value)
		for tree in [_decks_tree, _cards_tree, _matchups_tree]:
			tree.clear()
		return
	_report_text.text = report.format_text(8)
	_fill_tree(_decks_tree, DECK_COLUMNS, report.deck_rows())
	_fill_card_filter(report)
	_fill_cards()
	_fill_tree(_matchups_tree, MATCHUP_COLUMNS, report.matchup_rows())


func _fill_card_filter(report) -> void:
	var current := _cards_filter.get_item_text(_cards_filter.selected) if _cards_filter.item_count > 0 else "All"
	var labels: Array = ["All"] + report.decks.keys()
	var same := labels.size() == _cards_filter.item_count
	if same:
		for i in labels.size():
			same = same and _cards_filter.get_item_text(i) == labels[i]
	if same:
		return
	_cards_filter.clear()
	for label in labels:
		_cards_filter.add_item(label)
		if label == current:
			_cards_filter.select(_cards_filter.item_count - 1)


func _fill_cards() -> void:
	if _report == null:
		return
	var rows: Array = _report.card_rows()
	var wanted := _cards_filter.get_item_text(_cards_filter.selected) if _cards_filter.item_count > 0 else "All"
	if wanted != "All":
		rows = rows.filter(func(r): return r.label == wanted)
	_fill_tree(_cards_tree, CARD_COLUMNS, rows)


func _fill_tree(tree: Tree, columns: Array, rows: Array) -> void:
	var sort: Dictionary = _sort.get(tree.get_instance_id(), {})
	if not sort.is_empty():
		var key: String = sort.key
		var ascending: bool = sort.ascending
		rows = rows.duplicate()
		rows.sort_custom(func(a, b): return (a[key] < b[key]) if ascending else (a[key] > b[key]))
	tree.clear()
	var root := tree.create_item()
	for row in rows:
		var item := tree.create_item(root)
		for i in columns.size():
			item.set_text(i, _cell(row[columns[i][1]], columns[i][2]))
		var flag := str(row.get("flags", row.get("flag", "")))
		if flag != "":
			var color := FateTheme.MUTED
			if "STRONG" in flag or "FAVOURED" == flag:
				color = Color(0.45, 0.85, 0.5)
			elif "WEAK" in flag or "DISFAVOURED" == flag:
				color = FateTheme.DANGER
			else:
				color = FateTheme.GOLD
			for i in columns.size():
				item.set_custom_color(i, color)


func _cell(value, kind: String) -> String:
	match kind:
		"pct":
			return "%.1f%%" % (float(value) * 100.0)
		"delta":
			return "%+.1f" % (float(value) * 100.0)
		"num":
			return "%.2f" % float(value)
		"int":
			return str(int(value))
	return str(value)


func _on_title_clicked(column: int, _button: int, tree: Tree, columns: Array) -> void:
	var key: String = columns[column][1]
	var id := tree.get_instance_id()
	var previous: Dictionary = _sort.get(id, {})
	var ascending: bool = columns[column][2] == "str"
	if not previous.is_empty() and previous.key == key:
		ascending = not previous.ascending
	_sort[id] = {"key": key, "ascending": ascending}
	if _report != null:
		_show_report(_report)
