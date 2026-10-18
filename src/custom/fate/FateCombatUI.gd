# The combat user interface: selecting attackers and blockers with clicks, the attack markers and
# arrows, the clickable player avatars and the combat log. Design document: Section 8.
#
# It is an overlay over the whole table (it ignores the mouse itself; its buttons do not) that is
# added by FateBoard. It holds NO rules: every click ends up in a FateCombat call
# (declare_attack, cancel_attack, declare_block, cancel_block), so the same flows run without a
# screen. Tests click through the entry points below (card_clicked, avatar_clicked,
# marker_clicked), the same ones the real mouse reaches:
#   FateCardTemplate._on_Card_gui_input -> card_clicked(card)      (in the combat steps)
#   FatePlayerAvatar.pressed            -> avatar_clicked(player_id)
#   attack marker button                -> marker_clicked(attack)
#
# Declare step (active player): click one of your eligible creatures (green outline) to select it,
# then click an opposing creature or the opposing player's avatar. Clicking a creature that attacks
# (or its marker) cancels that attack. "Next phase" confirms.
# Intercept step (defending player): click a guarding or occupied creature, then the attacker it
# blocks. Clicking a blocker again cancels its block. "Next phase" confirms.
class_name FateCombatUI
extends Control

# The user-visible state changed (selection, prompt): the HUD refreshes its prompt
signal changed

# The avatars are the player plates in the right rail (FateLayout.plate_rect), the log sits at
# the bottom of the left rail (FateLayout.LOG_RECT)
const LOG_LINES := 7
const LOG_FONT_SIZE := 10
const Z := 50

const SELECT_COLOR := Color(1.0, 0.9, 0.2)
const ATTACK_COLOR := Color(0.95, 0.25, 0.2)
const NEGATED_COLOR := Color(0.55, 0.55, 0.55)
const BLOCK_COLOR := Color(0.3, 0.6, 1.0)
const ELIGIBLE_COLOR := Color(0.3, 0.9, 0.4, 0.8)

var game: FateGame
var combat: FateCombat
var avatars := {}
var log_label: Label
var log_panel: PanelContainer
# The creature picked by the first click (an attacker in the declare step, a blocker in the
# intercept step), or null
var selected: Card = null
# A hint for the player, set when a click was refused
var message := ""
var _markers := {}


func setup(owner_game: FateGame) -> void:
	game = owner_game
	combat = game.combat
	game.combat_ui = self
	name = "CombatUI"
	z_index = Z
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = FateBoard.SCREEN
	for pid in game.players:
		var avatar := FatePlayerAvatar.new(game.players[pid])
		avatar.game = game
		avatar.position = FateLayout.plate_rect(FateLayout.seat_of(pid, 1)).position
		avatar.pressed.connect(avatar_clicked.bind(pid))
		add_child(avatar)
		avatars[pid] = avatar
	_build_log()
	combat.step_changed.connect(_on_step_changed)
	combat.attack_declared.connect(_on_attack_declared)
	combat.attack_cancelled.connect(_on_attack_gone)
	combat.attack_removed.connect(_on_attack_gone)
	combat.blocker_declared.connect(func(_a, _b): _changed())
	combat.blocker_cancelled.connect(func(_a, _b): _changed())
	combat.attack_negated.connect(func(_a): _changed())
	combat.attack_resolved.connect(func(_a, _r): _changed())
	combat.log_entry.connect(func(_t): _refresh_log())
	combat.combat_cancelled.connect(_clear_all)
	# Arrows, markers and the selection only live as long as the combat; the log keeps the story
	combat.combat_finished.connect(_clear_all)
	game.creature_destroyed.connect(func(card, _c):
		if card == selected:
			clear_selection())
	_refresh_log()


func _build_log() -> void:
	log_panel = PanelContainer.new()
	log_panel.name = "CombatLogPanel"
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.position = FateLayout.LOG_RECT.position
	log_panel.custom_minimum_size = FateLayout.LOG_RECT.size
	log_panel.size = FateLayout.LOG_RECT.size
	log_panel.add_theme_stylebox_override("panel", FateTheme.panel_box())
	add_child(log_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	log_panel.add_child(column)
	column.add_child(FateTheme.label("COMBAT LOG", 9, Color(FateTheme.GOLD, 0.8), "Bold"))
	log_label = FateTheme.label("", LOG_FONT_SIZE, Color(0.85, 0.88, 0.95), "Regular")
	log_label.name = "CombatLog"
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.clip_text = true
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	log_label.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(log_label)


# Puts the plates in the corners of their seats (FateLayout.apply_seats moves everything else)
func place_avatars(bottom_id: int) -> void:
	for pid in avatars:
		avatars[pid].position = FateLayout.plate_rect(FateLayout.seat_of(pid, bottom_id)).position


# --- entry points -----------------------------------------------------------------------------------------

# Do clicks on cards on the table mean something now? (FateCardTemplate asks before it starts a
# drag or a double-click action.)
func wants_card_clicks() -> bool:
	return game != null and game.is_started and not game.is_over \
			and combat.step in [FateCombat.Step.DECLARE, FateCombat.Step.INTERCEPT]


func card_clicked(card: Card) -> void:
	if not wants_card_clicks():
		return
	message = ""
	match combat.step:
		FateCombat.Step.DECLARE:
			_declare_click(card)
		FateCombat.Step.INTERCEPT:
			_intercept_click(card)
	_changed()


func avatar_clicked(player_id: int) -> void:
	if not wants_card_clicks() or combat.step != FateCombat.Step.DECLARE:
		return
	message = ""
	if selected == null:
		message = "Select one of your creatures first"
	elif combat.declare_attack(selected, player_id):
		selected = null
	else:
		message = combat.last_error
	_changed()


# A click on the marker of an attack: cancels it in the declare step; in the intercept step it
# blocks that attack with the selected creature
func marker_clicked(attack: FateAttack) -> void:
	if not wants_card_clicks():
		return
	message = ""
	if combat.step == FateCombat.Step.DECLARE:
		combat.cancel_attack(attack.attacker)
	elif selected != null:
		_block_with_selected(attack)
	else:
		message = "Select one of your guarding or occupied creatures first"
	_changed()


func clear_selection() -> void:
	selected = null
	_changed()


# What the player should do now (shown in the status bar during the combat steps)
func prompt() -> String:
	var text := ""
	match combat.step:
		FateCombat.Step.DECLARE:
			if combat.current_window != null:
				text = "Reaction window: the defender may react"
			elif selected != null:
				text = "Click an opposing creature or Player %d to attack with %s (click it again to deselect)" \
						% [FateZones.opponent_of(game.active_id), selected.canonical_name]
			else:
				text = "Click a creature of yours to attack with (%d can), then Next phase" \
						% combat.eligible_attackers().size()
		FateCombat.Step.INTERCEPT:
			if combat.current_window != null:
				text = "Reaction window: the defender may react"
			elif selected != null:
				text = "Player %d: click the attacker %s blocks, then Next phase" \
						% [combat.defending_player(), selected.canonical_name]
			else:
				text = "Player %d: click a guarding or occupied creature to block with, then Next phase" \
						% combat.defending_player()
		FateCombat.Step.RESOLVE:
			text = "Attacks resolve in the order they were declared"
	if message != "":
		text += "  [%s]" % message
	return text


# --- click logic -----------------------------------------------------------------------------------------------

func _declare_click(card: Card) -> void:
	var player_id := game.active_id
	if card.controller_id == player_id:
		if combat.attack_of(card) != null:
			combat.cancel_attack(card)
			return
		if selected == card:
			selected = null
		elif combat.attack_problem(card) == "":
			selected = card
		else:
			selected = null
			message = combat.attack_problem(card)
	elif selected != null:
		if combat.declare_attack(selected, card):
			selected = null
		else:
			message = combat.last_error
	else:
		message = "Select one of your creatures first"


func _intercept_click(card: Card) -> void:
	if card.controller_id == combat.defending_player():
		if combat.block_of(card) != null:
			combat.cancel_block(card)
			return
		if selected == card:
			selected = null
		elif combat.eligible_blockers().has(card):
			selected = card
		else:
			selected = null
			message = "Only guarding or occupied creatures can block"
	elif selected != null:
		var attack := combat.attack_of(card)
		if attack == null:
			message = "That creature is not attacking"
		else:
			_block_with_selected(attack)
	else:
		message = "Select one of your guarding or occupied creatures first"


func _block_with_selected(attack: FateAttack) -> void:
	if combat.declare_block(selected, attack):
		selected = null
	else:
		message = combat.last_error


# --- markers, drawing --------------------------------------------------------------------------------------------

func _on_step_changed(_step: int) -> void:
	selected = null
	message = ""
	_changed()


func _on_attack_declared(attack: FateAttack) -> void:
	var marker := Button.new()
	marker.text = str(attack.order + 1)
	marker.focus_mode = Control.FOCUS_NONE
	marker.size = Vector2(18, 16)
	marker.custom_minimum_size = marker.size
	marker.add_theme_font_size_override("font_size", 10)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.6, 0.12, 0.1)
	box.set_corner_radius_all(8)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		marker.add_theme_stylebox_override(style, box)
	marker.tooltip_text = attack.describe()
	marker.pressed.connect(marker_clicked.bind(attack))
	add_child(marker)
	_markers[attack] = marker
	_changed()


func _on_attack_gone(attack: FateAttack) -> void:
	# A removed attack in the declare step keeps its marker but greyed out; a cancelled one is gone
	if attack in combat.attacks:
		_changed()
		return
	_drop_marker(attack)
	if selected == attack.attacker:
		selected = null
	_changed()


func _drop_marker(attack: FateAttack) -> void:
	var marker: Button = _markers.get(attack)
	if marker != null:
		_markers.erase(attack)
		marker.queue_free()


func _clear_all() -> void:
	selected = null
	message = ""
	for attack in _markers.keys():
		_drop_marker(attack)
	_changed()


func _changed() -> void:
	# Markers belong to the attacks of the current combat
	for attack in _markers.keys():
		if not attack in combat.attacks:
			_drop_marker(attack)
	var picking := wants_card_clicks() and combat.step == FateCombat.Step.DECLARE
	for pid in avatars:
		avatars[pid].set_highlight(picking and selected != null and pid != game.active_id)
	queue_redraw()
	changed.emit()


func _refresh_log() -> void:
	var lines: Array = combat.log_lines.slice(-LOG_LINES)
	log_label.text = "\n".join(lines)
	log_label.tooltip_text = "\n".join(combat.log_lines)


func _process(_delta: float) -> void:
	if combat == null:
		return
	# Cards move around, so arrows and markers follow them every frame while combat is on
	if combat.step != FateCombat.Step.IDLE or not _markers.is_empty() or selected != null:
		_place_markers()
		queue_redraw()


func _place_markers() -> void:
	for attack in _markers:
		var marker: Button = _markers[attack]
		var from = _center_of(attack.attacker)
		var to = _target_center(attack)
		if from == null or to == null:
			marker.visible = false
			continue
		marker.visible = not attack.removed or combat.step != FateCombat.Step.IDLE
		marker.position = from.lerp(to, 0.5) - marker.size / 2.0
		marker.modulate = Color(1, 1, 1, 0.45) if (attack.removed or attack.negated or attack.resolved) \
				else Color(1, 1, 1, 1)


# The attacks drawn as arrows: those of the combat going on. The attacks of a finished combat stay
# in combat.attacks until the next one starts, but the table is cleared when it ends.
func _drawn_attacks() -> Array:
	return combat.attacks if combat.step != FateCombat.Step.IDLE else []


func _drawn_attack_count() -> int:
	return _drawn_attacks().size()


func _draw() -> void:
	if combat == null:
		return
	if wants_card_clicks():
		_draw_hints()
	for attack in _drawn_attacks():
		var from = _center_of(attack.attacker)
		var to = _target_center(attack)
		if from == null or to == null:
			continue
		var color := ATTACK_COLOR
		if attack.removed or attack.negated or attack.resolved:
			color = NEGATED_COLOR
		_arrow(from, to, color, 3.0, 24.0)
		for blocker in attack.blockers:
			var b = _center_of(blocker)
			if b != null:
				_arrow(b, from, BLOCK_COLOR, 2.0, 24.0)
	if selected != null and is_instance_valid(selected):
		var rect := _rect_of(selected)
		if rect.size != Vector2.ZERO:
			draw_rect(rect.grow(3.0), SELECT_COLOR, false, 3.0)


# Outlines of the creatures that can be clicked now
func _draw_hints() -> void:
	var cards := []
	var color := ELIGIBLE_COLOR
	match combat.step:
		FateCombat.Step.DECLARE:
			if selected == null:
				cards = combat.eligible_attackers()
			else:
				cards = game.creatures_in_play(FateZones.opponent_of(game.active_id))
				color = ATTACK_COLOR
		FateCombat.Step.INTERCEPT:
			if selected == null:
				cards = combat.eligible_blockers()
				color = BLOCK_COLOR
			else:
				for attack in combat.attacks:
					if combat.block_problem(selected, attack) == "":
						cards.append(attack.attacker)
				color = BLOCK_COLOR
	for card in cards:
		if card == selected:
			continue
		var rect := _rect_of(card)
		if rect.size != Vector2.ZERO:
			draw_rect(rect.grow(1.0), color, false, 1.5)


func _arrow(from: Vector2, to: Vector2, color: Color, width: float, trim: float) -> void:
	var direction := (to - from)
	if direction.length() < 1.0:
		return
	direction = direction.normalized()
	var start := from + direction * trim * 0.5
	var tip := to - direction * trim
	draw_line(start, tip, color, width)
	var side := direction.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([tip + direction * 8.0, tip + side, tip - side]), color)


# The middle of a card on the table in this overlay's coordinates, or null
func _center_of(card: Card):
	if not is_instance_valid(card):
		return null
	var slot = card._placement_slot
	if slot != null and is_instance_valid(slot):
		return _local(slot.global_position + slot.size / 2.0)
	if card.get_parent() == cfc.NMAP.board:
		return _local(card.global_position + card.card_size * card.scale / 2.0)
	return null


# Table (canvas) coordinates to this overlay's coordinates
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


func _target_center(attack: FateAttack):
	if attack.target_card != null:
		return _center_of(attack.target_card)
	var avatar: FatePlayerAvatar = avatars.get(attack.target_player)
	return avatar.position + avatar.size / 2.0 if avatar != null else null
