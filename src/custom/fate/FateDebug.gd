# Debug tools for testing game states and mechanics by hand.
#
# Toggle with F3 or the "Debug tools" button in the left rail. While it is on (game.debug_mode):
#   * the rules for moving cards are not enforced: any card can be dragged from either hand
#     onto the table at any time, for free (see FateCardTemplate), and any card on the table
#     can be tilted (see FateGame.can_tilt)
#   * the panel can put any card of the game in any zone of either player, draw cards, change
#     life, untap and clear zones, and jump to the main phase
#   * a middle click on a card opens a menu to move it to any zone of either player, tilt,
#     flip or delete it
#
# Cards that the panel puts on the table do not pay for anything and do not trigger "played"
# effects: they simply appear (entered_turn stays 0, so they are not summoning sick).
class_name FateDebug
extends Control

const PANEL_WIDTH := 340.0
const MENU_WIDTH := 300.0
# Label, zone key. "hand" and the piles are containers, the rest are table grids
const ZONES := [
	["Hand", "hand"], ["Deck", "deck"], ["Discard", "discard"], ["Removed", "removed"],
	["Creatures", "creatures"], ["Occupied", "occupied"], ["Relics", "relics"],
	["Energy", "energy"], ["Field", "field"], ["Doctrines", "doctrines"], ["World", "world"],
]
const CONTAINER_ZONES := ["hand", "deck", "discard", "removed"]

var game: FateGame
var enabled := false

var _panel: PanelContainer
var _body: VBoxContainer
var _player_buttons := {}
var _zone_buttons := {}
var _search: LineEdit
var _list: ItemList
var _copies: SpinBox
var _status: Label
var _menu: PanelContainer
var _menu_card: Card
var _menu_player_buttons := {}
var _menu_title: Label
var _target_player := 1
var _target_zone := "hand"
var _menu_player := 1
var _dragging_panel := false
# Board states section (see _build_board_states)
# Replace to intercept the table calls (tests); empty = use the game's
var board_capture := Callable()
var board_loader := Callable()
# Replace to read / write the clipboard (tests; the headless display server has none)
var board_clipboard_read := Callable()
var board_clipboard_write := Callable()
var _bs_toggle: Button
var _bs_body: VBoxContainer
var _bs_list: ItemList
var _bs_name: LineEdit
var _bs_repo_check: CheckBox
var _bs_buttons := {}
var _bs_status: Label
var _bs_busy := false


func setup(fate_game: FateGame) -> void:
	game = fate_game
	name = "FateDebug"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	_build_panel()
	_build_menu()
	set_enabled(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func set_enabled(value: bool) -> void:
	enabled = value
	game.debug_mode = value
	_panel.visible = value
	if not value:
		_close_menu()
	else:
		_refresh_list()
		if _bs_body.visible:
			_bs_refresh_list()
	var board = get_parent()
	if board.get("debug_button") != null:
		board.debug_button.text = board.DEBUG_BUTTON_TEXT[value]


# --- card operations ---------------------------------------------------------------------

# Puts a new copy of a card in a zone of a player. Returns the card, or null if there is no
# such card or the zone is full.
func spawn(card_name: String, player_id: int, zone: String) -> Card:
	if not cfc.card_definitions.has(card_name):
		return null
	if zone in CONTAINER_ZONES:
		return await game.place_in_container(card_name, player_id, zone)
	var placed: Card = game.place_card_on_table(card_name, player_id, zone)
	if placed:
		if placed is FateCardTemplate:
			placed.apply_zone_look(zone)
		# Energy is mana: the plates and the playable glow follow
		game.mana_changed.emit(player_id)
	return placed


# Moves a card to a zone of a player (it becomes theirs). Returns false if the zone is full.
func move_card(card: Card, player_id: int, zone: String) -> bool:
	if not is_instance_valid(card):
		return false
	if card is FateCardTemplate:
		card.assign_owner(player_id)
	if zone in CONTAINER_ZONES:
		await card.move_to(FateZones.container(zone, player_id), -1, null, ["Scripted"])
		# The card may have left an energy zone
		game.mana_changed.emit(player_id)
		game.mana_changed.emit(FateZones.opponent_of(player_id))
		return true
	var grid := FateZones.grid(zone, player_id)
	if grid == null:
		return false
	var slot := grid.find_available_slot()
	if slot == null:
		return false
	await card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	if is_instance_valid(card):
		if card is FateCardTemplate:
			card.apply_zone_look(zone)
	game.mana_changed.emit(player_id)
	game.mana_changed.emit(FateZones.opponent_of(player_id))
	return true


func delete_card(card: Card) -> void:
	if not is_instance_valid(card):
		return
	var slot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	if game.stats:
		game.stats.clear_card(card)
	card.get_parent().remove_child(card)
	card.queue_free()
	cfc.flush_cache()


func _cards_in_zone(player_id: int, zone: String) -> Array:
	var player := game.player(player_id)
	if zone in CONTAINER_ZONES:
		var container = FateZones.container(zone, player_id)
		return container.get_all_cards() if container else []
	return player.cards_in_grid(zone)


func _say(text: String) -> void:
	_status.text = text


# --- panel actions -----------------------------------------------------------------------

func _add_selected() -> void:
	var picked := _list.get_selected_items()
	if picked.is_empty():
		_say("Pick a card in the list first")
		return
	var card_name: String = _list.get_item_metadata(picked[0])
	var added := 0
	for _i in int(_copies.value):
		if await spawn(card_name, _target_player, _target_zone) == null:
			_say("%s: no room in %s of P%d" % [card_name, _target_zone, _target_player])
			return
		added += 1
	_say("Added %d x %s to P%d %s" % [added, card_name, _target_player, _target_zone])


func _draw_card() -> void:
	var card := game.player(_target_player).draw_card()
	_say("P%d drew %s" % [_target_player, card.canonical_name if card else "nothing (deck empty)"])


func _change_life(amount: int) -> void:
	var player := game.player(_target_player)
	player.life += amount
	_say("P%d life is %d" % [_target_player, player.life])


func _untap_all() -> void:
	var count := 0
	for zone in ["energy", "creatures", "relics"]:
		for card in game.player(_target_player).cards_in_grid(zone):
			if card.card_rotation != 0:
				card.set_card_rotation(0)
				count += 1
	game.mana_changed.emit(_target_player)
	_say("Untapped %d cards of P%d" % [count, _target_player])


func _clear_zone() -> void:
	var cards := _cards_in_zone(_target_player, _target_zone)
	for card in cards:
		delete_card(card)
	game.mana_changed.emit(_target_player)
	_say("Deleted %d cards from P%d %s" % [cards.size(), _target_player, _target_zone])


# Skips the rest of the draw/energy choice of the turn and stops in the main phase
func _go_to_main() -> void:
	if game.is_over or game.phase > FateTurn.Phase.MAIN:
		_say("Only works before the main phase")
		return
	if game.phase == FateTurn.Phase.ENERGY and game.energy_choice == "":
		game.energy_choice = "debug"
		game.energy_phase_choice_made.emit()
	while game.phase != FateTurn.Phase.MAIN and game.advance_phase():
		pass
	_say("Main phase of player %d" % game.active_id)


func _refresh_list(_text := "") -> void:
	var filter := _search.text.strip_edges().to_lower()
	_list.clear()
	var names: Array = cfc.card_definitions.keys()
	names.sort()
	for card_name in names:
		var props: Dictionary = cfc.card_definitions[card_name]
		var kind := str(props.get("Type", ""))
		if props.get("_token", false):
			kind += " token"
		var label := "%s  [%s %s]" % [card_name, kind, str(props.get("Pips", ""))]
		if filter != "" and not (filter in card_name.to_lower() or filter in kind.to_lower()
				or filter in str(props.get("_domains", "")).to_lower()):
			continue
		var index := _list.add_item(label)
		_list.set_item_metadata(index, card_name)


# --- card menu (middle click) -----------------------------------------------------------

func open_card_menu(card: Card) -> void:
	if not enabled or not is_instance_valid(card):
		return
	_menu_card = card
	_menu_title.text = "%s (%s)" % [card.canonical_name, FateZones.zone_of(card) \
			if FateZones.zone_of(card) != "" else card.get_parent().name]
	_set_menu_player(card.owner_id if card is FateCardTemplate and card.owner_id > 0 else 1)
	_menu.visible = true
	var shown_at: Vector2 = card.global_position + Vector2(card.card_size.x * 0.5, 0)
	_menu.position = Vector2(
			clampf(shown_at.x, 0.0, FateBoard.SCREEN.x - MENU_WIDTH),
			clampf(shown_at.y - 200.0, 0.0, FateBoard.SCREEN.y - 230.0))


func _close_menu() -> void:
	if _menu:
		_menu.visible = false
	_menu_card = null


func _set_menu_player(player_id: int) -> void:
	_menu_player = player_id
	_menu_player_buttons[player_id].button_pressed = true


func _menu_move(zone: String) -> void:
	var card := _menu_card
	var player_id := _menu_player
	_close_menu()
	if card and not await move_card(card, player_id, zone):
		_say("No room in %s of P%d" % [zone, player_id])


func _menu_tilt() -> void:
	if is_instance_valid(_menu_card):
		_menu_card.set_card_rotation(90, true)
	game.mana_changed.emit(_menu_player)
	_close_menu()


func _menu_flip() -> void:
	if is_instance_valid(_menu_card):
		_menu_card.set_is_faceup(not _menu_card.is_faceup)
	_close_menu()


func _menu_delete() -> void:
	var card := _menu_card
	_close_menu()
	delete_card(card)
	game.mana_changed.emit(1)
	game.mana_changed.emit(2)


# --- building the UI --------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DebugPanel"
	# Over the middle of the table; drag the header to move it, "-" folds it
	_panel.position = Vector2(474, 44)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", _backdrop())
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_panel.add_child(column)

	# The header drags the panel around
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("DEBUG MODE (drag to move, F3 closes)", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_on_header_input)
	header.add_child(title)
	header.add_child(_button("-", func(): _body.visible = not _body.visible))
	header.add_child(_button("x", func(): set_enabled(false)))

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	column.add_child(_body)

	_body.add_child(_label("Player and zone to act on", 10))
	var players_row := HBoxContainer.new()
	_body.add_child(players_row)
	var player_group := ButtonGroup.new()
	for pid in [1, 2]:
		var b := _toggle("Player %d" % pid, player_group)
		b.pressed.connect(func(): _target_player = pid)
		b.button_pressed = pid == _target_player
		players_row.add_child(b)
		_player_buttons[pid] = b
	var grid := GridContainer.new()
	grid.columns = 4
	_body.add_child(grid)
	var zone_group := ButtonGroup.new()
	for entry in ZONES:
		var b := _toggle(entry[0], zone_group)
		var zone: String = entry[1]
		b.pressed.connect(func(): _target_zone = zone)
		b.button_pressed = zone == _target_zone
		grid.add_child(b)
		_zone_buttons[zone] = b

	_search = LineEdit.new()
	_search.placeholder_text = "Search by name, type or domain..."
	_search.add_theme_font_size_override("font_size", 11)
	_search.text_changed.connect(_refresh_list)
	_body.add_child(_search)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 120)
	_list.add_theme_font_size_override("font_size", 11)
	_list.item_activated.connect(func(_i): _add_selected())
	_body.add_child(_list)

	var add_row := HBoxContainer.new()
	_body.add_child(add_row)
	add_row.add_child(_label("Copies", 11))
	_copies = SpinBox.new()
	_copies.min_value = 1
	_copies.max_value = 10
	_copies.value = 1
	add_row.add_child(_copies)
	var add := _button("Add selected card (or double-click)", func(): _add_selected())
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add)

	var tools := HBoxContainer.new()
	_body.add_child(tools)
	tools.add_child(_button("Draw", func(): _draw_card()))
	for amount in [-5, -1, 1, 5]:
		tools.add_child(_button("Life %+d" % amount, func(): _change_life(amount)))
	var tools2 := HBoxContainer.new()
	_body.add_child(tools2)
	tools2.add_child(_button("Untap all", func(): _untap_all()))
	tools2.add_child(_button("Clear zone", func(): _clear_zone()))
	tools2.add_child(_button("Skip to Main phase", func(): _go_to_main()))

	_build_board_states(_body)

	_status = _label("", 10)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_WIDTH - 16, 26)
	_body.add_child(_status)
	var hint := _label("Middle-click any card: move, tilt, flip or delete it.\n"
			+ "Drag cards from either hand at any time: no costs, no turn limits.", 10)
	hint.modulate = Color(1, 1, 1, 0.6)
	_body.add_child(hint)


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.name = "DebugCardMenu"
	_menu.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	_menu.add_theme_stylebox_override("panel", _backdrop())
	_menu.visible = false
	add_child(_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_menu.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_menu_title = _label("", 11)
	_menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_title.clip_text = true
	header.add_child(_menu_title)
	header.add_child(_button("x", func(): _close_menu()))
	column.add_child(_label("Move to the zone of", 10))
	var players_row := HBoxContainer.new()
	column.add_child(players_row)
	var group := ButtonGroup.new()
	for pid in [1, 2]:
		var b := _toggle("Player %d" % pid, group)
		b.pressed.connect(func(): _menu_player = pid)
		b.button_pressed = pid == 1
		players_row.add_child(b)
		_menu_player_buttons[pid] = b
	var grid := GridContainer.new()
	grid.columns = 4
	column.add_child(grid)
	for entry in ZONES:
		var zone: String = entry[1]
		grid.add_child(_button(entry[0], func(): _menu_move(zone)))
	var actions := HBoxContainer.new()
	column.add_child(actions)
	actions.add_child(_button("Tilt / untilt", func(): _menu_tilt()))
	actions.add_child(_button("Flip", func(): _menu_flip()))
	actions.add_child(_button("Delete", func(): _menu_delete()))


# --- board states (docs/FATE_BOARD_STATE.md) -----------------------------------------------

const BS_MAX_ERRORS := 5
const BS_OK_COLOR := Color(0.75, 1.0, 0.75)
const BS_ERROR_COLOR := Color(1.0, 0.65, 0.6)


# A collapsible section (starts collapsed) to save, load, copy and paste whole tables. Plain
# Controls only: this panel lives in a SubViewport, so no OptionButton / PopupMenu.
func _build_board_states(parent: Control) -> void:
	_bs_toggle = _button("", func(): _bs_set_open(not _bs_body.visible))
	_bs_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(_bs_toggle)
	_bs_body = VBoxContainer.new()
	_bs_body.add_theme_constant_override("separation", 3)
	parent.add_child(_bs_body)

	_bs_list = ItemList.new()
	_bs_list.custom_minimum_size = Vector2(0, 90)
	_bs_list.add_theme_font_size_override("font_size", 11)
	_bs_list.item_selected.connect(_bs_on_selected)
	_bs_list.item_activated.connect(func(_i): _bs_load_selected())
	_bs_body.add_child(_bs_list)

	_bs_name = LineEdit.new()
	_bs_name.placeholder_text = "Name of the board state..."
	_bs_name.add_theme_font_size_override("font_size", 11)
	_bs_body.add_child(_bs_name)

	var save_row := HBoxContainer.new()
	_bs_body.add_child(save_row)
	_bs_buttons["save"] = _button("Save", func(): _bs_save())
	_bs_buttons["save"].tooltip_text = "Capture the table into a personal file with this name"
	save_row.add_child(_bs_buttons["save"])
	_bs_repo_check = CheckBox.new()
	_bs_repo_check.text = "into repo folder"
	_bs_repo_check.add_theme_font_size_override("font_size", 11)
	_bs_repo_check.focus_mode = Control.FOCUS_NONE
	# The table theme has no check mark icons: draw a plain box
	for icon_name in ["unchecked", "checked", "unchecked_disabled", "checked_disabled"]:
		_bs_repo_check.add_theme_icon_override(icon_name, _check_icon(icon_name.begins_with("checked"),
				icon_name.ends_with("disabled")))
	if OS.has_feature("editor"):
		_bs_repo_check.tooltip_text = "Save into res://boards (shared, checked into git) instead of the personal folder"
	else:
		_bs_repo_check.disabled = true
		_bs_repo_check.tooltip_text = "The repo folder can only be written when the game runs from the editor"
	save_row.add_child(_bs_repo_check)

	var file_row := HBoxContainer.new()
	_bs_body.add_child(file_row)
	_bs_buttons["load"] = _button("Load", func(): _bs_load_selected())
	_bs_buttons["delete"] = _button("Delete", func(): _bs_delete())
	_bs_buttons["delete"].tooltip_text = "Deletes a personal file (shared repo files are managed in the repo)"
	_bs_buttons["refresh"] = _button("Refresh list", func(): _bs_refresh_list())
	for key in ["load", "delete", "refresh"]:
		file_row.add_child(_bs_buttons[key])

	var clip_row := HBoxContainer.new()
	_bs_body.add_child(clip_row)
	_bs_buttons["copy"] = _button("Copy JSON", func(): _bs_copy_json())
	_bs_buttons["copy"].tooltip_text = "Capture the table and put its JSON on the clipboard"
	_bs_buttons["paste"] = _button("Paste JSON and load", func(): _bs_paste_and_load())
	for key in ["copy", "paste"]:
		clip_row.add_child(_bs_buttons[key])

	_bs_status = _label("", 10)
	_bs_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bs_status.custom_minimum_size = Vector2(PANEL_WIDTH - 16, 0)
	_bs_body.add_child(_bs_status)
	_bs_set_open(false)


func _check_icon(checked: bool, dimmed: bool) -> ImageTexture:
	var size := 14
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var color := Color(1, 1, 1, 0.35 if dimmed else 0.9)
	for x in size:
		for y in size:
			var edge := x < 1 or y < 1 or x >= size - 1 or y >= size - 1
			if edge or (checked and x >= 4 and y >= 4 and x < size - 4 and y < size - 4):
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _bs_set_open(open: bool) -> void:
	_bs_body.visible = open
	_bs_toggle.text = "Board states  [%s]" % ("-" if open else "+")
	if open:
		_bs_refresh_list()


# Files of both folders, tagged [repo] / [personal]. Keeps `select_name` selected if it is there
func _bs_refresh_list(select_name := "") -> void:
	_bs_list.clear()
	var keep := select_name if select_name != "" else _bs_name.text.strip_edges()
	for entry in FateBoardStateFiles.list():
		var index := _bs_list.add_item("[%s] %s" % [entry["source"], entry["name"]])
		_bs_list.set_item_metadata(index, entry)
		if select_name != "" and entry["name"] == keep and entry["source"] == FateBoardStateFiles.SOURCE_USER:
			_bs_list.select(index)
	_bs_update_buttons()


func _bs_on_selected(index: int) -> void:
	_bs_name.text = _bs_list.get_item_metadata(index)["name"]
	_bs_update_buttons()


# Shared files cannot be deleted from here
func _bs_update_buttons() -> void:
	var picked := _bs_list.get_selected_items()
	var repo_file: bool = not picked.is_empty() \
			and _bs_list.get_item_metadata(picked[0])["source"] == FateBoardStateFiles.SOURCE_SHARED
	_bs_buttons["delete"].disabled = repo_file


# The selected entry if it is the one the name box names
func _bs_picked_entry() -> Dictionary:
	var picked := _bs_list.get_selected_items()
	if picked.is_empty():
		return {}
	var entry: Dictionary = _bs_list.get_item_metadata(picked[0])
	return entry if entry["name"] == _bs_name.text.strip_edges() else {}


# Shows errors (first few, one per line), the warning count, then a success text
func _bs_show(errors: Array, warnings: Array, ok_text := "") -> void:
	var lines: Array[String] = []
	for i in mini(errors.size(), BS_MAX_ERRORS):
		lines.append(str(errors[i]))
	if errors.size() > BS_MAX_ERRORS:
		lines.append("(+%d more)" % (errors.size() - BS_MAX_ERRORS))
	if not warnings.is_empty():
		lines.append("%d warning%s" % [warnings.size(), "" if warnings.size() == 1 else "s"])
	if ok_text != "":
		lines.append(ok_text)
	_bs_status.text = "\n".join(lines)
	_bs_status.modulate = BS_ERROR_COLOR if not errors.is_empty() else BS_OK_COLOR


func _bs_capture() -> FateBoardState:
	var state: FateBoardState = board_capture.call() if board_capture.is_valid() \
			else game.capture_board_state()
	if state == null:
		var why: Array = game.board_state_errors
		_bs_show(why if not why.is_empty() else ["The table cannot be captured right now"], [])
	return state


func _bs_save() -> void:
	var typed := _bs_name.text.strip_edges()
	if FateBoardStateFiles.sanitize(typed) == "":
		_bs_show(["Give the board state a name first"], [])
		return
	var state := _bs_capture()
	if state == null:
		return
	state.set_state_name(typed)
	var to_repo := _bs_repo_check.button_pressed and not _bs_repo_check.disabled
	var saved := FateBoardStateFiles.save_state(state, typed, to_repo)
	if not saved.get("ok", false):
		_bs_show([str(saved.get("error", "Cannot save"))], [])
		return
	_bs_refresh_list(typed)
	_bs_show([], state.warnings, "Saved %s" % saved.get("path", ""))


func _bs_load_selected() -> void:
	var typed := _bs_name.text.strip_edges()
	if typed == "":
		_bs_show(["Pick a board state in the list or type its name"], [])
		return
	var entry := _bs_picked_entry()
	await _bs_apply(FateBoardStateFiles.load_state(entry["path"] if not entry.is_empty() else typed))


func _bs_paste_and_load() -> void:
	if board_clipboard_read.is_valid():
		await _bs_apply(FateBoardState.from_json(board_clipboard_read.call()))
	else:
		await _bs_apply(FateBoardStateFiles.from_clipboard())


func _bs_copy_json() -> void:
	var state := _bs_capture()
	if state == null:
		return
	if board_clipboard_write.is_valid():
		board_clipboard_write.call(state.to_json(true))
	else:
		FateBoardStateFiles.copy_to_clipboard(state)
	_bs_show([], state.warnings, "Copied to the clipboard: %s" % state.describe())


func _bs_delete() -> void:
	var typed := _bs_name.text.strip_edges()
	var entry := _bs_picked_entry()
	if typed == "":
		_bs_show(["Pick a personal board state first"], [])
	elif not entry.is_empty() and entry["source"] == FateBoardStateFiles.SOURCE_SHARED:
		_bs_show(["\"%s\" is a shared repo file: delete it in the repo" % typed], [])
	else:
		var error := FateBoardStateFiles.delete_state(typed)
		if error != "":
			_bs_show([error], [])
		else:
			_bs_name.text = ""
			_bs_refresh_list()
			_bs_show([], [], "Deleted the personal board state \"%s\"" % typed)


# Validates a state and, only if it is clean, rebuilds the table from it
func _bs_apply(state: FateBoardState) -> void:
	if _bs_busy:
		return
	var errors: Array = state.validate()
	for message in state.load_errors:
		if not message in errors:
			errors.append(message)
	if not errors.is_empty():
		_bs_show(errors, state.warnings)
		return
	_bs_busy = true
	_bs_show([], state.warnings, "Loading %s..." % state.describe())
	var result
	if board_loader.is_valid():
		result = await board_loader.call(state)
	else:
		result = await game.load_board_state(state)
	_bs_busy = false
	if not result is Dictionary:
		result = {"ok": false, "errors": ["The loader returned no result"], "warnings": []}
	var warnings: Array = state.warnings + result.get("warnings", [])
	if result.get("ok", false):
		_bs_show([], warnings, "Loaded %s" % state.describe())
	else:
		var failed: Array = result.get("errors", [])
		_bs_show(failed if not failed.is_empty() else ["Loading failed"], warnings)


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_panel = event.pressed
	elif event is InputEventMouseMotion and _dragging_panel:
		_panel.position += event.relative


# The debug panels share the table's panel look, with an orange frame so they never pass for
# part of the game
func _backdrop() -> StyleBoxFlat:
	var box := FateTheme.panel_box()
	box.bg_color = Color(0.04, 0.045, 0.07, 0.96)
	box.border_color = Color(1.0, 0.55, 0.1, 0.85)
	return box


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	return button


func _toggle(text: String, group: ButtonGroup) -> Button:
	var button := _button(text, func(): pass)
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The selected button stands out
	for style in ["pressed", "hover_pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(FateTheme.GOLD_DARK, 0.95)
		box.set_corner_radius_all(3)
		box.set_content_margin_all(4)
		button.add_theme_stylebox_override(style, box)
	return button
