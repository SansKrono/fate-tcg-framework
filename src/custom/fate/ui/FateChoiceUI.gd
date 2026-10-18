# The choice UI of the human players: answers the questions card effects ask through game.choices
# (FateChoices.gd: pick targets or cards, "you may ..." confirmations). No class_name (FateBoard loads
# it by path). It is an overlay over the whole table, created by FateBoard when the game is played
# (not in tests, which keep the deterministic defaults of FateChoices or plug their own chooser in).
#
# It holds NO rules: it only turns a request into clicks and returns the answer. Four kinds of question:
#   "table"    every option is a card on the table or a player: the candidates get an outline, a click
#              picks one; with count > 1 the clicks toggle and a Confirm button sends the pick.
#              A bar over the status bar says whose choice it is and what is asked.
#   "list"     some option is not on the table (a card in a hand, deck or discard pile, a number, a name):
#              a modal panel lists them; same count / confirm / skip logic.
#   "confirm"  yes / no, in the same bar.
# An optional pick has a "None" button (and Escape). While a question is open a full-screen layer eats every
# mouse click, so combat clicks, dragging, double-clicks and the phase buttons cannot break the flow.
#
# The question is asked of the player the request names, which is not always the active player (hotseat:
# "target opponent chooses"). In a game of two people a list that shows cards from the hidden zones
# (hand, deck) of a player who is not the active one starts behind a "Reveal" button, so the active
# player can look away first. A seat played by an AI (game.ai_controllers) never gets a window: it
# takes the default. The same safety answers with the default if the game ends while a question is open,
# or this node leaves the tree: the game never stays stuck on a question.
#
# Entry points (a click on a card, a plate or a button reaches the same ones, so tests and a debug
# console can answer without a screen):
#   option_clicked(option) / card_clicked(card) / player_clicked(player_id)   pick (or toggle) an option
#   confirm_pressed()   send the pick (count > 1); "Yes" of a confirmation
#   none_pressed()      "None" of an optional pick; "No" of a confirmation
#   cancel_pressed()    Escape: skip an optional pick, the default of a confirmation, ignored otherwise
#   reveal_pressed()    show the list behind the hotseat gate
#   answer(value)       send a complete answer at once (an option, an Array of options, a bool or null)
extends Control

# The open question, its selection or its prompt changed
signal changed
signal opened(request: Dictionary)
signal closed(request: Dictionary, answer)
# What _run waits for
signal answered(answer)
signal _released

const Z := 80
const MODAL_RECT := Rect2(190, 60, 900, 500)
const OUTLINE_COLOR := Color(0.3, 0.9, 0.4, 0.9)
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const SELECT_COLOR := Color(1.0, 0.9, 0.2)
const SHIELD_DIM := Color(0.0, 0.0, 0.0, 0.6)
const ENTRY_SIZE := Vector2(172, 132)

var game: FateGame
# The open question as FateChoices made it ({} when there is none)
var request := {}
# "", "table", "list" or "confirm"
var mode := ""
# The options picked so far (count > 1)
var selected: Array = []
# A hint for the player, set when a click was refused
var message := ""
# The list is hidden until the player at the screen presses Reveal (see the header)
var gated := false

var shield: ColorRect
var bar: PanelContainer
var prompt_label: Label
var ok_button: Button
var none_button: Button
var modal: PanelContainer
var modal_title: Label
var modal_hint: Label
var modal_list: HFlowContainer
var modal_ok: Button
var modal_none: Button
var modal_reveal: Button

var _busy := false
var _dead := false
var _hover = null
var _entries: Array = []


func setup(owner_game: FateGame) -> void:
	game = owner_game
	name = "ChoiceUI"
	z_index = Z
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = FateBoard.SCREEN
	visible = false
	_build()
	game.choices.chooser = _choose
	game.choices.confirmer = _confirm
	set_process(false)


func _exit_tree() -> void:
	_dead = true
	if game != null and is_instance_valid(game) and game.choices != null:
		if game.choices.chooser == _choose:
			game.choices.chooser = Callable()
		if game.choices.confirmer == _confirm:
			game.choices.confirmer = Callable()
	if is_open():
		_finish(request.get("default"))
	_busy = false
	_released.emit()


# --- the callables of game.choices ---------------------------------------------------------------------------

func _choose(req: Dictionary):
	return await _run(req, _mode_for(req))


func _confirm(req: Dictionary):
	return await _run(req, "confirm")


# One question at a time: the others wait for their turn
func _run(req: Dictionary, kind: String):
	while _busy:
		await _released
	if _resolves_itself(req):
		return req.get("default")
	_busy = true
	_open(req, kind)
	var value = await answered
	_busy = false
	_released.emit()
	return value


# Does nobody need to answer this one? The game is over, the seat is played by an AI that gave no
# chooser, or there is nothing to choose from
func _resolves_itself(req: Dictionary) -> bool:
	if _dead or game == null or not is_instance_valid(game) or game.is_over:
		return true
	if game.ai_controllers.has(int(req.get("player", 0))):
		return true
	return req.has("options") and req.options.is_empty()


# "table" if every option can be clicked on the table, else "list"
func _mode_for(req: Dictionary) -> String:
	var options: Array = req.get("options", [])
	if options.is_empty():
		return "list"
	for option in options:
		if option is FatePlayer:
			continue
		if option is Card and is_instance_valid(option) and FateZones.zone_of(option) != "":
			continue
		return "list"
	return "table"


# --- opening and closing --------------------------------------------------------------------------------------

func is_open() -> bool:
	return mode != ""


func wanted() -> int:
	if request.is_empty():
		return 0
	return mini(int(request.get("count", 1)), request.get("options", []).size())


func is_optional() -> bool:
	return bool(request.get("optional", false))


# The options that can be picked now
func candidates() -> Array:
	return request.get("options", []).duplicate()


func _open(req: Dictionary, kind: String) -> void:
	request = req
	mode = kind
	selected = []
	message = ""
	_hover = null
	gated = _needs_gate()
	visible = true
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.color = SHIELD_DIM if kind == "list" else Color(0, 0, 0, 0)
	set_process(true)
	_populate()
	opened.emit(req)
	_changed()


func _finish(value) -> void:
	if not is_open():
		return
	var req := request
	request = {}
	mode = ""
	selected = []
	message = ""
	gated = false
	_hover = null
	visible = false
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	modal.visible = false
	_clear_entries()
	set_process(false)
	queue_redraw()
	closed.emit(req, value)
	answered.emit(value)


# A list that shows hidden cards of a player who is not at the screen waits behind a gate
func _needs_gate() -> bool:
	if mode != "list" or not game.ai_controllers.is_empty():
		return false
	if int(request.get("player", 0)) == game.active_id:
		return false
	for option in request.get("options", []):
		if option is Card and is_instance_valid(option) and _in_hidden_zone(option):
			return true
	return false


func _in_hidden_zone(card: Card) -> bool:
	var parent := card.get_parent()
	for pid in game.players:
		if parent == FateZones.container("hand", pid) or parent == FateZones.container("deck", pid):
			return true
	return false


func _process(_delta: float) -> void:
	if not is_open():
		set_process(false)
		return
	if _resolves_itself(request):
		_finish(request.get("default"))
		return
	if mode == "table":
		queue_redraw()


# --- entry points -------------------------------------------------------------------------------------------------

# Picks the option (count 1: that is the answer) or toggles it (count > 1). Returns whether it was accepted.
func option_clicked(option) -> bool:
	if not is_open() or gated or mode == "confirm":
		return false
	if not option in request.options:
		message = "That is not one of the choices"
		_changed()
		return false
	message = ""
	if wanted() == 1:
		_finish(option)
		return true
	if option in selected:
		selected.erase(option)
	elif selected.size() >= wanted():
		message = "Already picked %d: click one to take it back" % wanted()
		_changed()
		return false
	else:
		selected.append(option)
	_changed()
	return true


func card_clicked(card: Card) -> bool:
	return option_clicked(card)


func player_clicked(player_id: int) -> bool:
	for option in request.get("options", []):
		if option is FatePlayer and option.id == player_id:
			return option_clicked(option)
	if is_open():
		message = "Player %d is not a choice" % player_id
		_changed()
	return false


# The Confirm button of a pick with count > 1 (sends the selection), the Yes of a confirmation
func confirm_pressed() -> bool:
	if not is_open() or gated:
		return false
	if mode == "confirm":
		_finish(true)
		return true
	if wanted() > 1 and selected.size() == wanted():
		_finish(selected.duplicate())
		return true
	message = "Pick %d (%d picked)" % [wanted(), selected.size()]
	_changed()
	return false


# The None button of an optional pick, the No of a confirmation
func none_pressed() -> bool:
	if not is_open() or gated:
		return false
	if mode == "confirm":
		_finish(false)
		return true
	if not is_optional():
		message = "You must choose"
		_changed()
		return false
	_finish(null)
	return true


# Escape: skips an optional pick, takes the default of a confirmation, does nothing else
func cancel_pressed() -> bool:
	if not is_open():
		return false
	if mode == "confirm":
		_finish(request.get("default", true))
		return true
	if gated or not is_optional():
		message = "You must choose"
		_changed()
		return false
	_finish(null)
	return true


func reveal_pressed() -> void:
	if is_open() and gated:
		gated = false
		_populate()
		_changed()


# Sends a whole answer: an option, an Array of options, a bool (confirmation) or null (skip). Returns
# whether it was accepted; a wrong one leaves the question open.
func answer(value) -> bool:
	if not is_open():
		return false
	if gated:
		reveal_pressed()
	if mode == "confirm":
		if not value is bool:
			return false
		_finish(value)
		return true
	if value == null:
		return none_pressed()
	if value is Array:
		if value.size() == 1 and wanted() == 1:
			return option_clicked(value[0])
		if value.size() != wanted() or not value.all(func(o): return o in request.options) \
				or not _distinct(value):
			message = "That is not a valid pick"
			_changed()
			return false
		_finish(value.duplicate())
		return true
	if wanted() == 1:
		return option_clicked(value)
	message = "Pick %d" % wanted()
	_changed()
	return false


static func _distinct(items: Array) -> bool:
	for i in items.size():
		for j in range(i + 1, items.size()):
			if items[i] == items[j]:
				return false
	return true


func _input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		cancel_pressed()
		get_viewport().set_input_as_handled()


# --- texts ------------------------------------------------------------------------------------------------------------

# Who is asked and what, e.g. "Player 2: choose 2 target creature (Reinforcements)"
func prompt_text() -> String:
	if request.is_empty():
		return ""
	var source = request.get("source")
	var from := " (%s)" % source.canonical_name if source is Card and is_instance_valid(source) else ""
	var who := "Player %d" % int(request.get("player", 0))
	var text: String
	if mode == "confirm":
		text = "%s: %s%s" % [who, request.get("prompt", ""), from]
	else:
		var amount := "%d " % wanted() if wanted() > 1 else ""
		text = "%s: choose %s%s%s" % [who, amount, request.get("kind", ""), from]
		if is_optional():
			text += " (optional)"
	if message != "":
		text += "  [%s]" % message
	return text


# How an option reads in the list
static func describe(option) -> String:
	if option is Card and is_instance_valid(option):
		var props: Dictionary = option.properties
		var kind: String = str(props.get("Type", ""))
		var line := kind
		if props.has("Strike") or props.has("Guard"):
			line += " %s/%s" % [props.get("Strike", "-"), props.get("Guard", "-")]
		var head := "%s - cost %s" % [props.get("Domain", ""), props.get("Cost", 0)] \
				if props.has("Cost") else str(props.get("Domain", ""))
		return "%s\n%s\n%s\n%s" % [option.canonical_name, head, line, props.get("Abilities", "")]
	if option is FatePlayer:
		return "%s\nLife %d" % [option.display_name, option.life]
	return str(option)


static func tooltip_of(option) -> String:
	if option is Card and is_instance_valid(option):
		return "%s\n%s" % [option.canonical_name, option.properties.get("Abilities", "")]
	return describe(option)


# --- building the widgets -------------------------------------------------------------------------------------------

func _build() -> void:
	shield = ColorRect.new()
	shield.name = "ChoiceShield"
	shield.color = Color(0, 0, 0, 0)
	shield.position = Vector2.ZERO
	shield.size = FateBoard.SCREEN
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.gui_input.connect(_on_shield_input)
	add_child(shield)
	_build_bar()
	_build_modal()


func _build_bar() -> void:
	bar = PanelContainer.new()
	bar.name = "ChoiceBar"
	bar.position = FateLayout.STATUS_RECT.position
	bar.size = FateLayout.STATUS_RECT.size
	bar.custom_minimum_size = FateLayout.STATUS_RECT.size
	var box := FateTheme.box(Color(0.06, 0.05, 0.02, 0.97), FateTheme.GOLD, 20, 2, 6.0)
	box.content_margin_left = 14
	box.content_margin_right = 8
	bar.add_theme_stylebox_override("panel", box)
	bar.visible = false
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	prompt_label = FateTheme.label("", 13, FateTheme.TEXT, "SemiBold")
	prompt_label.name = "ChoicePrompt"
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.clip_text = true
	row.add_child(prompt_label)
	ok_button = _button("ChoiceOk", "Confirm", confirm_pressed, true)
	none_button = _button("ChoiceNone", "None", none_pressed, false)
	row.add_child(ok_button)
	row.add_child(none_button)


func _build_modal() -> void:
	modal = PanelContainer.new()
	modal.name = "ChoiceModal"
	modal.position = MODAL_RECT.position
	modal.size = MODAL_RECT.size
	modal.custom_minimum_size = MODAL_RECT.size
	modal.add_theme_stylebox_override("panel", FateTheme.box(Color(0.05, 0.06, 0.09, 0.98),
			FateTheme.GOLD, 14, 2, 14.0))
	modal.visible = false
	add_child(modal)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	modal.add_child(column)
	modal_title = FateTheme.label("", 17, FateTheme.GOLD, "Bold")
	modal_title.name = "ChoiceModalTitle"
	modal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(modal_title)
	modal_hint = FateTheme.label("", 11, FateTheme.MUTED, "Regular")
	modal_hint.name = "ChoiceModalHint"
	column.add_child(modal_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	modal_list = HFlowContainer.new()
	modal_list.name = "ChoiceList"
	modal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_list.add_theme_constant_override("h_separation", 8)
	modal_list.add_theme_constant_override("v_separation", 8)
	scroll.add_child(modal_list)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	modal_reveal = _button("ChoiceReveal", "Reveal", reveal_pressed, true)
	modal_ok = _button("ChoiceModalOk", "Confirm", confirm_pressed, true)
	modal_none = _button("ChoiceModalNone", "None", none_pressed, false)
	footer.add_child(modal_reveal)
	footer.add_child(modal_ok)
	footer.add_child(modal_none)


func _button(button_name: String, text: String, callback: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(96, 28)
	button.pressed.connect(callback)
	if primary:
		FateTheme.make_primary(button)
	return button


# Fills the bar or the modal for the open question
func _populate() -> void:
	_clear_entries()
	bar.visible = mode in ["table", "confirm"]
	modal.visible = mode == "list"
	if mode != "list" or gated:
		return
	for i in request.options.size():
		var option = request.options[i]
		var entry := Button.new()
		entry.name = "Option_%d" % i
		entry.custom_minimum_size = ENTRY_SIZE
		entry.focus_mode = Control.FOCUS_NONE
		entry.text = describe(option)
		entry.tooltip_text = tooltip_of(option)
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.clip_text = true
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.add_theme_font_size_override("font_size", 11)
		entry.pressed.connect(option_clicked.bind(option))
		modal_list.add_child(entry)
		_entries.append(entry)


func _clear_entries() -> void:
	for entry in _entries:
		if is_instance_valid(entry):
			modal_list.remove_child(entry)
			entry.queue_free()
	_entries.clear()


func _style_entry(entry: Button, option, picked: bool) -> void:
	var color := FateTheme.card_color(option) if option is Card and is_instance_valid(option) \
			else FateTheme.NEUTRAL_DOMAIN
	var border := FateTheme.GOLD if picked else Color(color, 0.7)
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		var back := Color(color, 0.32 if picked else 0.14)
		entry.add_theme_stylebox_override(style, FateTheme.box(
				back.lightened(0.1) if style == "hover" else back, border, 8, 3 if picked else 1, 6.0))


func _changed() -> void:
	if is_open():
		prompt_label.text = prompt_text()
		modal_title.text = prompt_text()
		var count := wanted()
		var pick_text := "%d / %d picked" % [selected.size(), count] if count > 1 else "Click to choose"
		modal_hint.text = "Pass the screen to Player %d, then press Reveal" % int(request.get("player", 0)) \
				if gated else pick_text
		var optional := is_optional()
		match mode:
			"confirm":
				ok_button.text = "Yes"
				ok_button.visible = true
				ok_button.disabled = false
				none_button.text = "No"
				none_button.visible = true
			"table":
				ok_button.text = "Confirm (%d/%d)" % [selected.size(), count]
				ok_button.visible = count > 1
				ok_button.disabled = selected.size() != count
				none_button.text = "None"
				none_button.visible = optional
			"list":
				modal_ok.text = "Confirm (%d/%d)" % [selected.size(), count]
				modal_ok.visible = count > 1 and not gated
				modal_ok.disabled = selected.size() != count
				modal_none.text = "None"
				modal_none.visible = optional and not gated
				modal_reveal.visible = gated
		for i in _entries.size():
			var option = request.options[i]
			_style_entry(_entries[i], option, option in selected)
	queue_redraw()
	changed.emit()


# --- clicks on the table ----------------------------------------------------------------------------------------------

func _on_shield_input(event: InputEvent) -> void:
	if mode != "table":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit = option_at(event.position)
		if hit != null:
			option_clicked(hit)
	elif event is InputEventMouseMotion:
		var hit = option_at(event.position)
		if hit != _hover:
			_hover = hit
			queue_redraw()


# The option drawn at a point of the overlay, or null
func option_at(point: Vector2):
	for option in request.get("options", []):
		if option_rect(option).has_point(point):
			return option
	return null


# Where a candidate is on the screen: a card's slot, a player's plate (empty if it is nowhere)
func option_rect(option) -> Rect2:
	if option is Card:
		return _rect_of(option)
	if option is FatePlayer and game.combat_ui != null:
		var avatar: Control = game.combat_ui.avatars.get(option.id)
		if avatar != null and is_instance_valid(avatar):
			return Rect2(_local(avatar.global_position), avatar.size * avatar.get_global_transform().get_scale())
	return Rect2()


func _draw() -> void:
	if mode != "table":
		return
	for option in request.options:
		var rect := option_rect(option)
		if rect.size == Vector2.ZERO:
			continue
		if option in selected:
			draw_rect(rect.grow(3.0), SELECT_COLOR, false, 3.0)
		elif option == _hover:
			draw_rect(rect.grow(2.0), HOVER_COLOR, false, 3.0)
		else:
			draw_rect(rect.grow(1.0), OUTLINE_COLOR, false, 2.0)


func _center_of(card: Card):
	if not is_instance_valid(card):
		return null
	var slot = card._placement_slot
	if slot != null and is_instance_valid(slot):
		return _local(slot.global_position + slot.size / 2.0)
	if card.get_parent() == cfc.NMAP.board:
		return _local(card.global_position + card.card_size * card.scale / 2.0)
	return null


func _local(point: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * point


func _rect_of(card: Card) -> Rect2:
	var center = _center_of(card)
	if center == null:
		return Rect2()
	var slot = card._placement_slot
	var rect_size: Vector2 = slot.size if slot != null and is_instance_valid(slot) \
			else card.card_size * card.scale
	if card.card_rotation in [90, 270]:
		rect_size = Vector2(rect_size.y, rect_size.x)
	return Rect2(center - rect_size / 2.0, rect_size)
