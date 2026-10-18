# The two-player Fate table. Design document: Sections 4 and 6.
#
# The zones are built in code from the framework scenes (Pile, Hand and
# BoardPlacementGrid) so that both players get an identical, mirrored set of zones with
# predictable names (see FateZones). Where everything goes is decided by FateLayout: the active
# player sits at the bottom, the other player at the top. The look (colours, fonts, panels) comes
# from FateTheme. Cards on the table are drawn small (the scale of their zone, see FateLayout);
# hover a card to see it in the card detail dock on the left.
class_name FateBoard
extends Board

const PILE_SCENE := preload("res://src/core/Pile.tscn")
const DECK_SCENE := preload("res://src/custom/fate/FateDeck.tscn")
const HAND_SCENE := preload("res://src/custom/fate/FateHand.tscn")
const GRID_SCENE := preload("res://src/core/BoardPlacementGrid.tscn")

# Scale of the cards on the table, and the size of one grid slot at that scale
const TABLE_SCALE := 0.45
const SCREEN := Vector2(1280, 720)
# The words written in the corner of each empty zone
const ZONE_CAPTIONS := {
	"creatures": "CREATURES", "occupied": "OCCUPIED", "relics": "RELICS", "energy": "ENERGY",
	"field": "FIELD", "doctrines": "DOCTRINES", "world": "WORLD",
}
const PILE_CAPTIONS := {"deck": "DECK", "discard": "DISCARD", "removed": "REMOVED"}
# The label of the debug button, closed and open
const DEBUG_BUTTON_TEXT := {false: "Debug tools  (F3)", true: "Close debug tools  (F3)"}
const MENU_SCENE := "res://src/custom/MainMenu.tscn"
const MENU_BUTTON_SIZE := Vector2(220, 44)

var game: FateGame
# The table surface (vignette, seat tints, rails)
var background: FateTableBackground
# The ready/tapped counter beside each player's energy row, by player id
var energy_counters := {}
# The player sitting at the bottom of the screen (the active player, see apply_seats)
var bottom_id := 1
# The window scaling before this table changed it, restored when the table closes
var _previous_scaling := {}
# The status bar on the midline (turn text, phase strip) and the action panel (prompt and the
# buttons), see _build_hud
var status_label: Label
var phase_strip: FatePhaseStrip
var action_panel: FateActionPanel
var prompt_label: Label
var draw_button: Button
var next_button: Button
var end_turn_button: Button
var debug_button: Button
# The combat overlay (clicks, arrows, player plates, log), the "Player N's turn" and the
# "Player N wins" banners
var combat_ui: FateCombatUI
# The choice UI of the human players (targets, "you may" questions of card effects), see FateChoiceUI
var choice_ui: Control
var turn_banner: FateTurnBanner
var winner_banner: FateTurnBanner
# Shown under the winner banner when the game is over, leads back to the main menu
var menu_button: Button
var _curtain: ColorRect
# The debug tools (F3 or the Debug button), see FateDebug
var debug: FateDebug
# Seconds between two attacks resolving in play (tests resolve at once, see FateCombat)
const RESOLVE_DELAY := 0.9


func _ready() -> void:
	_fit_window()
	FateGame.register_cards()
	game = FateGame.new()
	game.name = "FateGame"
	add_child(game)
	theme = FateTheme.build()
	background = FateTableBackground.new()
	add_child(background)
	_build_zones()
	_build_hud()
	_build_combat_ui()
	_build_choice_ui()
	_build_debug()
	# Godot 4 does not call the parent _ready() automatically
	super._ready()
	cfc.map_node(self)
	counters = null
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	# The hand is drawn flat, the oval fan only makes sense at the bottom of the screen
	cfc.game_settings.hand_use_oval_shape = false
	game.turn_started.connect(_refresh_hud)
	game.turn_started.connect(_on_turn_started)
	game.card_played.connect(func(_card): _refresh_hud())
	game.phase_begins.connect(_refresh_hud)
	game.energy_phase_choice_made.connect(_refresh_hud)
	game.energy_played.connect(func(_card): _refresh_hud())
	game.mana_changed.connect(_refresh_hud)
	game.game_ended.connect(_on_game_ended)
	combat_ui.changed.connect(_refresh_hud)
	game.combat.reaction_window_requested.connect(_on_reaction_window)
	for pid in game.players:
		game.players[pid].life_changed.connect(_refresh_hud)
	for pid in game.players:
		var deck: Pile = FateZones.container("deck", pid)
		deck.draw_requested.connect(_on_deck_clicked)
	await get_tree().process_frame
	_apply_ai_args()
	await _start_game()
	_refresh_hud()


# Deals a new game, or starts in the position named by `--board=<name or path>` (given after `--` on
# the command line: godot ... FateMain.tscn -- --board=goblin_attack_ready). A position that cannot
# be loaded is reported and a new game is dealt instead.
func _start_game() -> void:
	var wanted := board_from_args(OS.get_cmdline_user_args()) if not cfc.is_testing else ""
	if wanted != "":
		var result: Dictionary = await game.start_from_state(FateBoardStateFiles.load_state(wanted))
		if result["ok"]:
			print("Fate: started from the board state \"%s\"" % wanted)
			return
		push_error("Board state \"%s\" was not loaded: %s" % [wanted, "; ".join(result["errors"])])
	await game.start_game()


# Gives the seats named by `--ai=` an AI player: `--ai=1`, `--ai=2`, `--ai=both` (or `--ai=1,2`), and
# `--ai-level=easy|normal|hard` for the strength (normal by default). Not in tests, which switch the AI
# on themselves (FateGame.set_ai). Example:
#   godot --path . src/custom/fate/FateMain.tscn -- --ai=2 --ai-level=hard
func _apply_ai_args() -> void:
	if cfc.is_testing:
		return
	var args := OS.get_cmdline_user_args()
	var level := ai_level_from_args(args)
	for seat in ai_seats_from_args(args):
		game.set_ai(seat, true, level)


# The seats after `--ai=` in the arguments: [] when there is no such argument
static func ai_seats_from_args(args: Array) -> Array:
	var seats: Array = []
	for arg in args:
		if not str(arg).begins_with("--ai="):
			continue
		for part in str(arg).substr("--ai=".length()).split(","):
			match part.strip_edges().to_lower():
				"both", "all":
					seats = [1, 2]
				"1", "2":
					if not int(part) in seats:
						seats.append(int(part))
	return seats


# The strength after `--ai-level=`: FateAIProfile.Level (0 easy, 1 normal, 2 hard); normal if missing
static func ai_level_from_args(args: Array) -> int:
	for arg in args:
		if str(arg).begins_with("--ai-level="):
			match str(arg).substr("--ai-level=".length()).to_lower():
				"easy":
					return 0
				"hard":
					return 2
	return 1


# The name or path after `--board=` in the arguments, or ""
static func board_from_args(args: Array) -> String:
	for arg in args:
		if str(arg).begins_with("--board="):
			return str(arg).substr("--board=".length())
	return ""


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
		_add_pile("deck", pid, DECK_SCENE, false)
		_add_pile("discard", pid, PILE_SCENE, true)
		_add_pile("removed", pid, PILE_SCENE, true)
		_add_hand(pid)
		for zone in FateLayout.BOTTOM_GRIDS:
			_add_grid(zone, pid)
	_add_grid("world", 0)
	FateLayout.apply_seats(self, 1)
	_color_seats(1)


# Tints each half of the table with the domain of the player sitting there
func _color_seats(bottom_id: int) -> void:
	var colors := {}
	for pid in game.players:
		colors[pid] = FateTheme.domain_color(game.players[pid].domains[0])
	background.set_seat_colors(colors[bottom_id], colors[FateZones.opponent_of(bottom_id)])


func _add_pile(zone: String, pid: int, scene: PackedScene, faceup: bool) -> void:
	var wrapper := Control.new()
	wrapper.name = "%sWrapper" % FateZones.node_name(zone, pid)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrapper)
	var pile: Pile = scene.instantiate()
	pile.name = FateZones.node_name(zone, pid)
	pile.placement = CardContainer.Anchors.CONTROL
	pile.faceup_cards = faceup
	pile.pile_name = "P%d %s" % [pid, zone.capitalize()]
	pile.scale = Vector2(FateLayout.PILE_SCALE, FateLayout.PILE_SCALE)
	wrapper.add_child(pile)
	_style_pile(pile, PILE_CAPTIONS[zone])


# A pile is a small stack: a dark rounded floor, its card count as a gold badge in the middle
# and its name along the bottom edge (everything is drawn at the pile's scale)
func _style_pile(pile: Pile, caption_text: String) -> void:
	var floor_panel: Panel = pile.get_node("Control")
	floor_panel.self_modulate = Color(1, 1, 1, 0.9)
	floor_panel.add_theme_stylebox_override("panel",
			FateTheme.box(Color(0.08, 0.09, 0.15, 0.6), Color(FateTheme.GOLD, 0.45), 16, 3, 0.0))
	floor_panel.tooltip_text = pile.pile_name
	# Above the cards of the pile, so the count and the name stay readable
	floor_panel.z_index = 1
	pile.pile_name_label.visible = false
	var count: Label = pile.card_count_label
	count.add_theme_font_override("font", FateTheme.font("Bold"))
	count.add_theme_font_size_override("font_size", 38)
	count.add_theme_color_override("font_color", FateTheme.GOLD)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 10)
	var badge: PanelContainer = count.get_parent().get_parent()
	var badge_box := FateTheme.box(Color(0.1, 0.115, 0.19, 0.9), Color(FateTheme.GOLD, 0.7), 30, 3, 10.0)
	badge.add_theme_stylebox_override("panel", badge_box)
	var caption := FateTheme.label(caption_text, 26, Color(FateTheme.TEXT, 0.85), "Bold")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 10)
	caption.position = Vector2(0, CFConst.CARD_SIZE.y - 44)
	caption.size = Vector2(CFConst.CARD_SIZE.x, 40)
	floor_panel.add_child(caption)


func _add_hand(pid: int) -> void:
	var wrapper := Control.new()
	wrapper.name = "%sWrapper" % FateZones.node_name("hand", pid)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := FateLayout.hand_rect("bottom" if pid == 1 else "top")
	wrapper.position = rect.position
	wrapper.custom_minimum_size = rect.size
	wrapper.size = rect.size
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


# Adds the placement grid of a zone of a player (pid 0: the shared world zone). It is placed by
# FateLayout. The framework label keeps the full grid name ("Creatures P1": FateZones and the
# cards look grids up by it) but is hidden; a small caption shows the zone instead.
func _add_grid(zone: String, pid: int) -> void:
	var grid_name := FateZones.grid_name(zone, pid)
	var grid: BoardPlacementGrid = GRID_SCENE.instantiate()
	grid.name = grid_name.replace(" ", "")
	grid.card_play_scale = FateLayout.zone_scale(zone)
	grid.auto_extend = zone == "energy"
	grid.get_node("GridContainer").columns = FateLayout.COLUMNS.get(zone, 1)
	grid.get_node("Control/Label").text = grid_name
	grid.get_node("Control/Label").visible = false
	grid.self_modulate = Color.WHITE
	grid.add_theme_stylebox_override("panel", FateTheme.zone_box())
	grid.highlight = Color(FateTheme.GOLD, 1.0) * 1.2
	if zone == "world":
		grid.position = FateLayout.WORLD_POSITION
	var caption := FateTheme.label(ZONE_CAPTIONS[zone], 9, Color(FateTheme.MUTED, 0.95), "SemiBold")
	caption.name = "Caption"
	caption.position = Vector2(4, 1)
	grid.get_node("Control").add_child(caption)
	add_child(grid)
	if FateLayout.SLOT_GAPS.has(zone):
		grid.get_node("GridContainer").add_theme_constant_override("h_separation",
				FateLayout.SLOT_GAPS[zone])
	if zone == "energy":
		_add_energy_counter(grid, pid)
	var slots: int = FateLayout.COLUMNS.get(zone, 1)
	if zone in ["field", "world"]:
		slots = 1
	elif zone == "energy":
		slots = FateLayout.ENERGY_START_SLOTS
	# The scene comes with one slot
	for _i in range(slots - 1):
		grid.add_slot()


# The counter beside a player's energy row: "ready/total" and how many are tapped. It is a child
# of the grid, so it follows the seat.
func _add_energy_counter(grid: BoardPlacementGrid, pid: int) -> void:
	var counter := PanelContainer.new()
	counter.name = "EnergyCounter"
	counter.mouse_filter = Control.MOUSE_FILTER_PASS
	counter.position = Vector2(FateLayout.ENERGY_ROW_WIDTH + 12, 0)
	counter.size = FateLayout.ENERGY_COUNTER_SIZE
	counter.custom_minimum_size = FateLayout.ENERGY_COUNTER_SIZE
	counter.add_theme_stylebox_override("panel",
			FateTheme.box(Color(0.1, 0.115, 0.19, 0.85), Color(FateTheme.GOLD, 0.5), 8, 1, 2.0))
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	counter.add_child(column)
	for part in [["Ready", 16, FateTheme.GOLD, "Bold"], ["Caption", 9, FateTheme.MUTED, "SemiBold"],
			["Tapped", 10, FateTheme.TEXT, "Regular"]]:
		var label := FateTheme.label("", part[1], part[2], part[3])
		label.name = part[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	column.get_node("Caption").text = "READY"
	grid.get_node("Control").add_child(counter)
	energy_counters[pid] = counter


# Keeps each energy row on one line: squeezes the cards together when there are more than fit,
# moves the cards onto their (moved) slots once they stop moving, and updates the counters.
func _squeeze_energy() -> void:
	for pid in energy_counters:
		var grid := FateZones.grid("energy", pid)
		if grid == null:
			continue
		var slot_count := grid.get_slot_count()
		var card_width: float = CFConst.CARD_SIZE.x * grid.card_play_scale
		var gap := 5.0
		if slot_count > 1 and slot_count * card_width + (slot_count - 1) * gap > FateLayout.ENERGY_ROW_WIDTH:
			gap = floorf((FateLayout.ENERGY_ROW_WIDTH - slot_count * card_width) / (slot_count - 1))
			gap = maxf(gap, 8.0 - card_width)
		var container: GridContainer = grid.get_node("GridContainer")
		if container.get_theme_constant("h_separation") != int(gap):
			container.add_theme_constant_override("h_separation", int(gap))
			# Let the panel shrink back to its content
			grid.size = Vector2.ZERO
		for card in game.player(pid).cards_in_grid("energy"):
			var slot: BoardPlacementSlot = card._placement_slot
			if card.state == Card.CardState.ON_PLAY_BOARD and not card.get_node("Tween").is_active() \
					and card.position.distance_to(slot.global_position - global_position) > 0.5:
				card.position = slot.global_position - global_position
		var total: int = game.player(pid).cards_in_grid("energy").size()
		var ready: int = game.mana.untapped_energy(pid).size()
		var counter: Control = energy_counters[pid]
		counter.get_node("Column/Ready").text = "%d/%d" % [ready, total]
		counter.get_node("Column/Tapped").text = "%d tapped" % (total - ready)
		counter.tooltip_text = "Energy: %d ready, %d tapped" % [ready, total - ready]


func _process(delta: float) -> void:
	super._process(delta)
	if game != null and game.is_started:
		_squeeze_energy()


# --- status bar and action panel ----------------------------------------------------------

func _build_hud() -> void:
	var bar := PanelContainer.new()
	bar.name = "StatusBar"
	bar.position = FateLayout.STATUS_RECT.position
	bar.size = FateLayout.STATUS_RECT.size
	bar.custom_minimum_size = Vector2(0, FateLayout.STATUS_RECT.size.y)
	var bar_box := FateTheme.box(Color(0.12, 0.14, 0.22, 0.92), Color(FateTheme.GOLD, 0.5), 20, 1, 6.0)
	bar_box.content_margin_left = 14
	bar_box.content_margin_right = 8
	bar.add_theme_stylebox_override("panel", bar_box)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	status_label = FateTheme.label("", 13, FateTheme.TEXT, "SemiBold")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.clip_text = true
	row.add_child(status_label)
	phase_strip = FatePhaseStrip.new()
	phase_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(phase_strip)
	_build_detail_placeholder()
	action_panel = FateActionPanel.new()
	add_child(action_panel)
	prompt_label = action_panel.prompt_label
	draw_button = action_panel.draw_button
	next_button = action_panel.next_button
	end_turn_button = action_panel.end_turn_button
	draw_button.pressed.connect(func(): game.draw_extra_card())
	next_button.pressed.connect(func(): game.request_next_phase())
	end_turn_button.pressed.connect(func(): game.end_turn())


# The card detail dock (Main's magnifier, docked by FateMain.tscn) floats above this frame; when
# no card is hovered the frame says what goes there
func _build_detail_placeholder() -> void:
	var frame := PanelContainer.new()
	frame.name = "CardDetailFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = Vector2(6, 6)
	frame.size = Vector2(FateLayout.LEFT_RAIL_WIDTH - 10, 340)
	var frame_box := FateTheme.box(Color(0.1, 0.115, 0.19, 0.6), Color(FateTheme.PANEL_BORDER, 0.7), 12, 1)
	frame.add_theme_stylebox_override("panel", frame_box)
	add_child(frame)
	var hint := FateTheme.label("Hover a card\nto see it here", 12, FateTheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(hint)


func _build_debug() -> void:
	debug_button = Button.new()
	debug_button.name = "DebugButton"
	debug_button.text = DEBUG_BUTTON_TEXT[false]
	debug_button.focus_mode = Control.FOCUS_NONE
	debug_button.position = FateLayout.DEBUG_BUTTON_RECT.position
	debug_button.size = FateLayout.DEBUG_BUTTON_RECT.size
	debug_button.add_theme_font_size_override("font_size", 12)
	debug_button.tooltip_text = "Spawn, move and remove any card, change life, skip phases"
	var orange := Color(1.0, 0.55, 0.1)
	debug_button.add_theme_stylebox_override("normal", FateTheme.box(Color(orange, 0.12), Color(orange, 0.7), 8, 1))
	debug_button.add_theme_stylebox_override("hover", FateTheme.box(Color(orange, 0.25), orange, 8, 1))
	debug_button.add_theme_stylebox_override("pressed", FateTheme.box(Color(orange, 0.35), orange, 8, 2))
	debug_button.add_theme_color_override("font_color", orange.lightened(0.3))
	debug_button.pressed.connect(func(): debug.set_enabled(not debug.enabled))
	add_child(debug_button)
	debug = FateDebug.new()
	add_child(debug)
	debug.setup(game)


# The combat overlay needs the players, which exist once the game node is in the tree
func _build_combat_ui() -> void:
	combat_ui = FateCombatUI.new()
	add_child(combat_ui)
	combat_ui.setup(game)
	game.combat.resolve_delay = 0.0 if cfc.is_testing else RESOLVE_DELAY
	# Covers the table while the seats swap (the banners stay above it)
	_curtain = ColorRect.new()
	_curtain.name = "SeatCurtain"
	_curtain.color = FateTheme.BG
	_curtain.size = SCREEN
	_curtain.z_index = 95
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.visible = false
	add_child(_curtain)
	turn_banner = FateTurnBanner.new()
	turn_banner.name = "TurnBanner"
	add_child(turn_banner)
	winner_banner = FateTurnBanner.new()
	winner_banner.name = "WinnerBanner"
	add_child(winner_banner)
	_build_menu_button()


# The questions of card effects are answered by the people at the table. Tests keep the deterministic
# defaults of game.choices (or plug their own chooser in), so they get no choice UI from the board.
func _build_choice_ui() -> void:
	if cfc.is_testing:
		return
	choice_ui = load("res://src/custom/fate/ui/FateChoiceUI.gd").new()
	add_child(choice_ui)
	choice_ui.setup(game)


# Which player sits at the bottom while `active` has the turn. Hotseat: the active player. With one
# AI player the person stays at the bottom, so the AI's hand stays hidden and the table does not flip
# on every turn.
func seat_for_turn(active: int) -> int:
	if game.ai_controllers.size() == 1:
		return FateZones.opponent_of(game.ai_controllers.keys()[0])
	return active


# Hotseat: the player whose turn it is moves to the bottom seat, behind a short fade
func _on_turn_started(player_id: int, _turn_number: int) -> void:
	turn_banner.flash("Player %d's turn" % player_id)
	player_id = seat_for_turn(player_id)
	if bottom_id == player_id:
		return
	if cfc.is_testing or not is_inside_tree():
		apply_seats(player_id)
		return
	_curtain.visible = true
	_curtain.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(_curtain, "modulate:a", 1.0, 0.15)
	fade.tween_callback(apply_seats.bind(player_id))
	fade.tween_property(_curtain, "modulate:a", 0.0, 0.3)
	fade.tween_callback(func(): _curtain.visible = false)


# Puts bottom player's zones, hand and plate at the bottom of the screen
func apply_seats(bottom_player: int) -> void:
	bottom_id = bottom_player
	FateLayout.apply_seats(self, bottom_player)
	combat_ui.place_avatars(bottom_player)
	_color_seats(bottom_player)
	_refresh_hud()


func _on_reaction_window(window) -> void:
	window.closed.connect(func(): _refresh_hud.call_deferred(), CONNECT_ONE_SHOT)
	_refresh_hud.call_deferred()


# The top hand is shown face-up while a reaction window gives its player priority
func _reveal_reacting_hand() -> void:
	var top_id := FateZones.opponent_of(bottom_id)
	var top_hand = FateZones.container("hand", top_id)
	if top_hand == null or not top_hand.has_method("set_concealed"):
		return
	var reacting: bool = game.reactions != null and game.reactions.window_open_for(top_id) \
			and not game.ai_controllers.has(top_id)
	if top_hand.concealed == reacting:
		top_hand.set_concealed(not reacting)
	if reacting:
		prompt_label.text = "Player %d may react: double-click a glowing reaction spell, or pass" \
				% top_id


# The way out of a finished game, hidden until the game ends
func _build_menu_button() -> void:
	menu_button = Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = "Back to main menu"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.size = MENU_BUTTON_SIZE
	menu_button.position = Vector2(
			winner_banner.position.x + (FateTurnBanner.SIZE.x - MENU_BUTTON_SIZE.x) / 2.0,
			winner_banner.position.y + FateTurnBanner.SIZE.y + 14.0)
	menu_button.z_index = 100
	menu_button.add_theme_font_size_override("font_size", 16)
	FateTheme.make_primary(menu_button)
	menu_button.visible = false
	menu_button.pressed.connect(return_to_menu)
	add_child(menu_button)


func return_to_menu() -> void:
	# warning-ignore:return_value_discarded
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_game_ended(winner_id: int) -> void:
	turn_banner.visible = false
	winner_banner.flash("Player %d wins" % winner_id, true)
	menu_button.visible = true
	_refresh_hud()


# What the active player should do in each phase
const PROMPTS := {
	FateTurn.Phase.MAINTENANCE: "Untapping...",
	FateTurn.Phase.DRAW: "Drawing a card...",
	FateTurn.Phase.ENERGY: "Double-click a hand card to play it as energy, or draw an extra card",
	FateTurn.Phase.MAIN: "Drag cards from your hand onto the table. Hover a creature, T tilts it",
	FateTurn.Phase.COMBAT_DECLARE: "Declare your attackers, then confirm",
	FateTurn.Phase.COMBAT_INTERCEPT: "The defender assigns blockers",
	FateTurn.Phase.COMBAT_RESOLVE: "Attacks resolve in the order they were declared",
	FateTurn.Phase.END: "End of the turn",
}


func _refresh_hud(_a = null, _b = null) -> void:
	for pid in combat_ui.avatars:
		combat_ui.avatars[pid].refresh()
		combat_ui.avatars[pid].set_active(game.is_started and pid == game.active_id)
	if not game.is_started:
		status_label.text = "Setting up..."
		action_panel.set_phase(FateTurn.Phase.NONE)
		prompt_label.text = ""
		for b in [draw_button, next_button, end_turn_button]:
			b.disabled = true
		draw_button.visible = false
		return
	status_label.text = "Turn %d - Player %d - %s" % [game.turn_number, game.active_id,
			FateTurn.phase_name(game.phase)]
	phase_strip.set_phase(game.phase)
	action_panel.set_phase(game.phase)
	prompt_label.text = PROMPTS.get(game.phase, "")
	if game.phase in FateTurn.COMBAT_HOOKS and game.combat == combat_ui.combat:
		prompt_label.text = combat_ui.prompt()
	if game.is_over:
		status_label.text = "Game over - Player %d wins" % game.winner_id
		prompt_label.text = ""
	draw_button.disabled = not game.can_draw_extra_card()
	next_button.disabled = not game.can_request_next_phase()
	end_turn_button.disabled = not game.can_end_turn()
	_refresh_playable()
	_reveal_reacting_hand()


# Hand cards that can be played right now glow (Arena style): playable from the hand, playable
# as energy, or castable as a reaction
func _refresh_playable() -> void:
	for pid in game.players:
		var hand: Hand = FateZones.container("hand", pid)
		if hand == null:
			continue
		for card in hand.get_all_cards():
			if card.has_method("set_playable"):
				card.set_playable(game.is_started and not game.is_over
						and (game.can_play_from_hand(card) or game.can_play_as_energy(card)
						or (game.reactions != null and game.reactions.can_cast(card))))


func _on_deck_clicked(deck: Pile) -> void:
	# Clicking the deck is a shortcut for "Draw extra card" in the energy phase (the draw
	# of the turn itself is automatic)
	var pid := int(str(deck.name).right(1))
	if pid == game.active_id:
		game.draw_extra_card()
	elif game.doctrines != null and game.doctrines.can_take_opponent_card(game.active_id):
		# Ensue Chaos: the top card of the opponent's deck goes to the active player's energy zone
		game.doctrines.take_opponent_card_as_energy(game.active_id)
