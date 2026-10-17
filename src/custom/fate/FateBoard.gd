# The two-player Fate table. Design document: Sections 4 and 6.
#
# The zones are built in code from the framework scenes (Pile, Hand and
# BoardPlacementGrid) so that both players get an identical, mirrored set of zones with
# predictable names (see FateZones). Cards are drawn at a smaller scale on the table
# (FateCardTemplate.play_area_scale); hover a card to see it magnified.
#
# Layout (1280x720): player 1 at the bottom, player 2 at the top, a status bar between.
#   left column:  decks, removed piles      right column: discards, world spell slot
#   front row:    creatures, relics, field spell, doctrines
#   back row:     occupied creatures, energy
class_name FateBoard
extends Board

const PILE_SCENE := preload("res://src/core/Pile.tscn")
const DECK_SCENE := preload("res://src/custom/fate/FateDeck.tscn")
const HAND_SCENE := preload("res://src/custom/fate/FateHand.tscn")
const GRID_SCENE := preload("res://src/core/BoardPlacementGrid.tscn")

# Scale of the cards on the table, and the size of one grid slot at that scale
const TABLE_SCALE := 0.4
const SCREEN := Vector2(1280, 720)
const GRID_HEIGHT := 100.0
const FRONT_ROW_Y := 388.0
const BACK_ROW_Y := 494.0

var game: FateGame
# The window scaling before this table changed it, restored when the table closes
var _previous_scaling := {}
# The status bar controls (see _build_hud)
var status_label: Label
var prompt_label: Label
var mana_label: Label
var draw_button: Button
var next_button: Button
var end_turn_button: Button
# The combat overlay (clicks, arrows, avatars, log) and the "Player N wins" banner
var combat_ui: FateCombatUI
var winner_banner: Label
# Seconds between two attacks resolving in play (tests resolve at once, see FateCombat)
const RESOLVE_DELAY := 0.9


func _ready() -> void:
	_fit_window()
	FateGame.register_cards()
	game = FateGame.new()
	game.name = "FateGame"
	add_child(game)
	_build_zones()
	_build_hud()
	_build_combat_ui()
	# Godot 4 does not call the parent _ready() automatically
	super._ready()
	cfc.map_node(self)
	counters = null
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	# The hand is drawn flat, the oval fan only makes sense at the bottom of the screen
	cfc.game_settings.hand_use_oval_shape = false
	game.turn_started.connect(_refresh_hud)
	game.phase_begins.connect(_refresh_hud)
	game.energy_phase_choice_made.connect(_refresh_hud)
	game.energy_played.connect(func(_card): _refresh_hud())
	game.mana_changed.connect(_refresh_hud)
	game.game_ended.connect(_on_game_ended)
	combat_ui.changed.connect(_refresh_hud)
	for pid in game.players:
		game.players[pid].life_changed.connect(_refresh_hud)
	for pid in game.players:
		var deck: Pile = FateZones.container("deck", pid)
		deck.draw_requested.connect(_on_deck_clicked)
	await get_tree().process_frame
	await game.start_game()
	_refresh_hud()


# --- window scaling ------------------------------------------------------------

# The table is laid out in a fixed 1280x720 space. Scaling the window content to that
# design size makes the whole table (including the card magnifier) grow and shrink with
# the window, with bars at the sides if the window is not 16:9. The previous settings are
# restored in _exit_tree() so the main menu and the demo board are unaffected.
func _fit_window() -> void:
	var window := get_tree().root
	_previous_scaling = {
		"mode": window.content_scale_mode,
		"aspect": window.content_scale_aspect,
		"size": window.content_scale_size,
	}
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = Vector2i(SCREEN)


func _exit_tree() -> void:
	if _previous_scaling.is_empty():
		return
	var window := get_tree().root
	window.content_scale_mode = _previous_scaling.mode
	window.content_scale_aspect = _previous_scaling.aspect
	window.content_scale_size = _previous_scaling.size


# --- zones -----------------------------------------------------------------

func _build_zones() -> void:
	for pid in range(1, FateZones.PLAYER_COUNT + 1):
		var bottom := pid == 1
		# Mirrors a y position for the top player
		var y := func(bottom_y: float, height: float) -> float:
			return bottom_y if bottom else SCREEN.y - bottom_y - height
		var rows := {
			"front": y.call(FRONT_ROW_Y, GRID_HEIGHT),
			"back": y.call(BACK_ROW_Y, GRID_HEIGHT),
		}
		_add_pile("deck", pid, Vector2(0, y.call(480.0, 240.0)), DECK_SCENE, false)
		_add_pile("discard", pid, Vector2(SCREEN.x - 150.0, y.call(480.0, 240.0)), PILE_SCENE, true)
		_add_pile("removed", pid, Vector2(0, 360.0 if bottom else 240.0), PILE_SCENE, true, 0.5)
		_add_hand(pid, Vector2(160, 480.0 if bottom else 0.0))
		_add_grid(FateZones.grid_name("creatures", pid), Vector2(170, rows.front), 6, 6)
		_add_grid(FateZones.grid_name("relics", pid), Vector2(600, rows.front), 3, 3)
		_add_grid(FateZones.grid_name("field", pid), Vector2(815, rows.front), 1, 1)
		_add_grid(FateZones.grid_name("doctrines", pid), Vector2(890, rows.front), 3, 3)
		_add_grid(FateZones.grid_name("occupied", pid), Vector2(170, rows.back), 6, 6)
		_add_grid(FateZones.grid_name("energy", pid), Vector2(600, rows.back), 6, 6, true)
	_add_grid(FateZones.WORLD_GRID, Vector2(SCREEN.x - 150.0 + 45.0, 310), 1, 1)


func _add_pile(zone: String, pid: int, pos: Vector2, scene: PackedScene,
		faceup: bool, pile_scale := 1.0) -> void:
	var wrapper := Control.new()
	wrapper.name = "%sWrapper" % FateZones.node_name(zone, pid)
	wrapper.position = pos
	add_child(wrapper)
	var pile: Pile = scene.instantiate()
	pile.name = FateZones.node_name(zone, pid)
	pile.placement = CardContainer.Anchors.CONTROL
	pile.faceup_cards = faceup
	pile.pile_name = "P%d %s" % [pid, zone.capitalize()]
	pile.scale = Vector2(pile_scale, pile_scale)
	wrapper.add_child(pile)


func _add_hand(pid: int, pos: Vector2) -> void:
	var wrapper := Control.new()
	wrapper.name = "%sWrapper" % FateZones.node_name("hand", pid)
	wrapper.position = pos
	wrapper.custom_minimum_size = Vector2(960, 240)
	wrapper.size = Vector2(960, 240)
	# Expanding wrappers keep the size we give them (see CardContainer._init_control_size)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(wrapper)
	var hand: Hand = HAND_SCENE.instantiate()
	hand.name = FateZones.node_name("hand", pid)
	hand.mirrored = pid == 2
	hand.hand_size = 10
	hand.excess_cards = Hand.ExcessCardsBehaviour.DISCARD_DRAWN
	hand.excess_discard_pile_name = FateZones.node_name("discard", pid)
	wrapper.add_child(hand)


func _add_grid(grid_name: String, pos: Vector2, columns: int, slots: int,
		auto_extend := false) -> void:
	var grid: BoardPlacementGrid = GRID_SCENE.instantiate()
	grid.name = grid_name.replace(" ", "")
	grid.position = pos
	grid.card_play_scale = TABLE_SCALE
	grid.auto_extend = auto_extend
	grid.get_node("GridContainer").columns = columns
	grid.get_node("Control/Label").text = grid_name
	add_child(grid)
	# The scene comes with one slot
	for _i in range(slots - 1):
		grid.add_slot()


# --- status bar ----------------------------------------------------------------

# The band between the two front rows is only 32 pixels high (the grid labels of the bottom
# player start at y = 368), so the bar is two compact rows:
#   "Turn N - Player P - <phase>"                          [Draw extra card] [Next phase] [End turn]
#   <what to do now>                                       P1 life 20 mana ... | P2 ...
const BAR_POSITION := Vector2(170, 334)
const BAR_SIZE := Vector2(940, 32)
const BAR_FONT_SIZE := 11

func _build_hud() -> void:
	var bar := VBoxContainer.new()
	bar.name = "StatusBar"
	bar.position = BAR_POSITION
	bar.size = BAR_SIZE
	bar.add_theme_constant_override("separation", 0)
	add_child(bar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	bar.add_child(top)
	status_label = _small_label(13)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(status_label)
	draw_button = _bar_button("Draw extra card", func(): game.draw_extra_card())
	next_button = _bar_button("Next phase", func(): game.request_next_phase())
	end_turn_button = _bar_button("End turn", func(): game.end_turn())
	for b in [draw_button, next_button, end_turn_button]:
		top.add_child(b)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	bar.add_child(bottom)
	prompt_label = _small_label(BAR_FONT_SIZE)
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_label.size_flags_stretch_ratio = 1.0
	bottom.add_child(prompt_label)
	mana_label = _small_label(BAR_FONT_SIZE)
	mana_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mana_label.size_flags_stretch_ratio = 1.2
	mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(mana_label)


# The combat overlay needs the players, which exist once the game node is in the tree
func _build_combat_ui() -> void:
	combat_ui = FateCombatUI.new()
	add_child(combat_ui)
	combat_ui.setup(game)
	game.combat.resolve_delay = 0.0 if cfc.is_testing else RESOLVE_DELAY
	winner_banner = Label.new()
	winner_banner.name = "WinnerBanner"
	winner_banner.visible = false
	winner_banner.z_index = 100
	winner_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	winner_banner.position = Vector2(290, 300)
	winner_banner.size = Vector2(700, 120)
	winner_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	winner_banner.add_theme_font_size_override("font_size", 56)
	winner_banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	winner_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	winner_banner.add_theme_constant_override("outline_size", 10)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0, 0, 0, 0.75)
	backdrop.set_corner_radius_all(12)
	winner_banner.add_theme_stylebox_override("normal", backdrop)
	add_child(winner_banner)


func _on_game_ended(winner_id: int) -> void:
	winner_banner.text = "Player %d wins" % winner_id
	winner_banner.visible = true
	_refresh_hud()


func _small_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.clip_text = true
	label.custom_minimum_size = Vector2(0, font_size + 3)
	return label


func _bar_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", BAR_FONT_SIZE)
	# The default button margins would make the bar taller than its band
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 0
		box.content_margin_bottom = 0
		box.corner_radius_top_left = 3
		box.corner_radius_top_right = 3
		box.corner_radius_bottom_left = 3
		box.corner_radius_bottom_right = 3
		box.bg_color = {
			"normal": Color(0.17, 0.2, 0.28), "hover": Color(0.24, 0.3, 0.42),
			"pressed": Color(0.1, 0.13, 0.2), "disabled": Color(0.12, 0.12, 0.14),
			"focus": Color(0.17, 0.2, 0.28),
		}[style]
		button.add_theme_stylebox_override(style, box)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.5))
	button.custom_minimum_size = Vector2(0, 17)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	return button


# What the active player should do in each phase
const PROMPTS := {
	FateTurn.Phase.MAINTENANCE: "Untapping...",
	FateTurn.Phase.DRAW: "Drawing a card...",
	FateTurn.Phase.ENERGY: "Double-click a hand card to play it as energy, OR draw an extra card",
	FateTurn.Phase.MAIN: "Drag cards from your hand onto the table to play them. T tilts a creature",
	FateTurn.Phase.COMBAT_DECLARE: "Declare your attackers, then Next phase",
	FateTurn.Phase.COMBAT_INTERCEPT: "The defender assigns blockers",
	FateTurn.Phase.COMBAT_RESOLVE: "Attacks resolve in the order they were declared",
	FateTurn.Phase.END: "End of the turn",
}


func _refresh_hud(_a = null, _b = null) -> void:
	if not game.is_started:
		status_label.text = "Setting up..."
		prompt_label.text = ""
		for b in [draw_button, next_button, end_turn_button]:
			b.disabled = true
		draw_button.visible = false
		return
	status_label.text = "Turn %d - Player %d - %s" % [game.turn_number, game.active_id,
			FateTurn.phase_name(game.phase)]
	prompt_label.text = PROMPTS.get(game.phase, "")
	if game.phase in FateTurn.COMBAT_HOOKS and game.combat == combat_ui.combat:
		prompt_label.text = combat_ui.prompt()
	if game.is_over:
		status_label.text = "Game over - Player %d wins" % game.winner_id
		prompt_label.text = ""
	draw_button.visible = game.phase == FateTurn.Phase.ENERGY
	draw_button.disabled = not game.can_draw_extra_card()
	next_button.disabled = not game.can_request_next_phase()
	end_turn_button.disabled = not game.can_end_turn()
	var parts := []
	for pid in game.players:
		var pool := game.mana_pool(pid)
		var mana := []
		for domain in pool:
			if pool[domain] > 0:
				mana.append("%s %d" % [domain.substr(0, 3), pool[domain]])
		parts.append("P%d life %d mana %s" % [pid, game.players[pid].life,
				", ".join(mana) if not mana.is_empty() else "-"])
	mana_label.text = "   |   ".join(parts)


func _on_deck_clicked(deck: Pile) -> void:
	# Clicking the deck is a shortcut for "Draw extra card" in the energy phase (the draw
	# of the turn itself is automatic)
	var pid := int(str(deck.name).right(1))
	if pid == game.active_id:
		game.draw_extra_card()
