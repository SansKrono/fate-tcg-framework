# Base script of all Fate cards (creatures, relics, spells, doctrines).
#
# Adds ownership, the choice of the board zone a card goes to, the rules for playing a card
# from the hand (turn phase and mana, see FateGame) and the "play as energy" action.
# Design document: Sections 4.1, 5 and 6.
class_name FateCardTemplate
extends Card

# Who put the card in their deck, and who controls it now (they differ after
# "take control" effects, which are not implemented yet).
var owner_id := 0
var controller_id := 0
# True while the card is face-down in an energy zone
var is_energy := false
# The turn number in which the card was played from the hand onto the table (0 if it
# did not enter play that way). Keywords like Charge and Productive compare it to the
# current turn (docs/FATE_RULES_SPEC.md, Section 4)
var entered_turn := 0
# True between the pre- and the post-move script of a move from the hand to the table that
# the rules allowed, so that the payment happens only if the card really lands there
var _play_pending := false
var _playable_glow: Control
# True while the card is face-down in the opponent's hand (FateHand): it ignores the mouse
var concealed := false
const PLAYABLE_COLOR := Color(0.35, 0.72, 1.0)


func _ready() -> void:
	super._ready()
	state_changed.connect(_on_state_changed)
	# New cards, and the duplicates the card detail dock makes of table cards, show the full card
	# and no playable glow
	if card_front and card_front.has_method("set_table_mode"):
		card_front.set_table_mode(false)
	_playable_glow = $Control.get_node_or_null("PlayableGlow")
	set_playable(false)


# A concealed card never takes the mouse, whatever its state asks for
func set_control_mouse_filters(value = true) -> void:
	super.set_control_mouse_filters(value and not concealed)


# The blue glow of a card in the hand that can be played right now (FateBoard decides)
func set_playable(on: bool) -> void:
	if on and _playable_glow == null:
		# A crisp border with a soft halo around it (two border-only frames: a StyleBox shadow
		# would also show through the transparent middle)
		_playable_glow = Control.new()
		_playable_glow.name = "PlayableGlow"
		_playable_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for ring in [[7, 6, 0.3], [3, 3, 1.0]]:
			var frame := Panel.new()
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.position = -Vector2(ring[0], ring[0])
			frame.size = card_size + Vector2(ring[0], ring[0]) * 2
			frame.add_theme_stylebox_override("panel", FateTheme.box(Color.TRANSPARENT,
					Color(PLAYABLE_COLOR, ring[2]), 10 + ring[0], ring[1], 0.0))
			_playable_glow.add_child(frame)
		$Control.add_child(_playable_glow)
	if _playable_glow:
		_playable_glow.visible = on


# Cards on the table take the scale of the zone they stand in (FateLayout.ZONE_SCALES) and show
# their compact table face (FateCardFront.set_table_mode); everywhere else the full card.
func _on_state_changed(_card, _old_state: int, new_state: int) -> void:
	if new_state in [CardState.DROPPING_TO_BOARD, CardState.ON_PLAY_BOARD] \
			and _placement_slot != null and is_instance_valid(_placement_slot):
		play_area_scale = _placement_slot.owner_grid.card_play_scale
	if new_state in [CardState.DRAGGED, CardState.DROPPING_TO_BOARD, CardState.ON_PLAY_BOARD,
			CardState.IN_PILE, CardState.MOVING_TO_CONTAINER, CardState.VIEWPORT_FOCUS]:
		set_playable(false)
	if new_state == CardState.DRAGGED or card_front == null \
			or not card_front.has_method("set_table_mode"):
		return
	card_front.set_table_mode(new_state in [CardState.DROPPING_TO_BOARD,
			CardState.ON_PLAY_BOARD, CardState.FOCUSED_ON_BOARD])


# Sets the owner, and the board zone this card goes to when it is dropped on the table.
func assign_owner(player_id: int) -> void:
	owner_id = player_id
	controller_id = player_id
	var zone := board_zone()
	if zone.is_empty():
		# Regular and reaction spells have no zone, see common_pre_move_scripts()
		board_placement = BoardPlacement.ANYWHERE
	else:
		board_placement = BoardPlacement.GRID_AUTOPLACEMENT
		mandatory_grid_name = FateZones.grid_name(zone, player_id)


# Gives the card the look of the zone it stands in, at once (no animation): `is_energy` follows
# the "energy" zone, `face` is "up" or "down" and `tapped` tilts the card by 90 degrees. The
# defaults are FateBoardState.default_face / default_tapped: energy lies face-down, occupied
# creatures are tilted, everything else stands up.
func apply_zone_look(zone: String, face := "", tapped = null) -> void:
	is_energy = zone == "energy"
	if face == "":
		face = FateBoardState.default_face(zone)
	if tapped == null:
		tapped = FateBoardState.default_tapped(zone)
	set_is_faceup(face == "up", true)
	set_card_rotation(90 if tapped else 0)


# The zone grid this card type occupies on the table (Section 6)
func board_zone() -> String:
	match properties.get("Type"):
		"Creature":
			return "creatures"
		"Relic":
			return "relics"
		"Doctrine":
			return "doctrines"
		"Spell":
			match properties.get("_spell_kind"):
				"Field":
					return "field"
				"World":
					return "world"
	return ""


# Spells that are not persisting are resolved and go to the discard pile
func is_instant_spell() -> bool:
	return properties.get("Type") == "Spell" \
			and properties.get("_spell_kind") in ["Regular", "Reaction"]


# Reaction spells can only be cast in reaction windows (declare and intercept steps), never
# played from the hand in the main phase (decision D8)
func is_reaction_spell() -> bool:
	return properties.get("Type") == "Spell" and properties.get("_spell_kind") == "Reaction"


# Mana value: the generic cost plus one for each domain pip (Section 12, item 18)
func mana_value() -> int:
	return int(properties.get("Cost", 0)) + str(properties.get("Pips", "")).length()


# The game rules hook into every move of the card.
#
# Playing a card means dragging it from the hand to the table (spec Section 2). That is
# allowed only for the owner, in their main phase, if the cost can be paid; otherwise the
# card stays in the hand and nothing is charged. Moves tagged "Scripted" (game code such as
# drawing and playing energy) are not player actions and are never checked.
func common_pre_move_scripts(new_host: Node, old_host: Node, move_tags: Array) -> Node:
	var game := _game()
	if not game or not game.is_started:
		return new_host
	if "Scripted" in move_tags or not old_host is Hand or new_host == old_host:
		return new_host
	if game.debug_mode:
		# Debug mode: any player can play any card, at any time, for free
		if new_host == cfc.NMAP.board:
			if is_instant_spell():
				game.card_played.emit(self)
				return FateZones.container("discard", owner_id)
			_play_pending = true
		return new_host
	# Cards in hand can only be played by their owner, on their turn
	if owner_id != game.active_id:
		return old_host
	if new_host != cfc.NMAP.board:
		return new_host
	if not game.can_play_from_hand(self):
		return old_host
	if is_instant_spell():
		# A regular spell resolves into the discard pile. The move to the pile cannot fail
		# from here, so it is paid for now
		if not game.pay(self):
			return old_host
		game.card_played.emit(self)
		return FateZones.container("discard", owner_id)
	# The board may still refuse the drop (no free slot, wrong zone), so the payment waits
	# for the post-move script
	_play_pending = true
	return new_host


func common_post_move_scripts(new_host: String, _old_host: String, _move_tags: Array) -> void:
	# A card leaving the energy zone is no longer energy
	if is_energy and new_host.to_lower() != "board":
		is_energy = false
	# A card that leaves the table forgets damage, modifiers and keyword grants
	if get_parent() != cfc.NMAP.board:
		var left_game := _game()
		if left_game and left_game.stats:
			left_game.stats.clear_card(self)
	if not _play_pending:
		return
	_play_pending = false
	var game := _game()
	if not game or get_parent() != cfc.NMAP.board:
		# The board refused the drop, the card is back in the hand
		return
	if game.debug_mode or game.pay(self):
		entered_turn = game.turn_number
		game.card_played.emit(self)
	else:
		# The mana changed while the card was moving: undo the play
		move_to(FateZones.container("hand", owner_id), -1, null, ["Scripted"])


# Double-clicking a card in the hand plays it as energy (the proof of concept has no
# card scripts or costs yet). Everything else is handled by the framework.
func execute_scripts(
		trigger_card: Node = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		only_cost_check := false):
	var game := _game()
	# Reactions: while a reaction window is open for the owner, double-clicking a reaction spell
	# in the hand casts it (FateReactions) instead of playing it as energy
	if game and trigger == "manual" and trigger_card == self and not only_cost_check \
			and get_state_exec() == "hand" and is_reaction_spell() \
			and game.reactions != null and game.reactions.window_open_for(owner_id):
		game.reactions.cast(self)
		return null
	if game and trigger == "manual" and trigger_card == self and not only_cost_check \
			and get_state_exec() == "hand":
		game.play_as_energy(self)
		return null
	return await super.execute_scripts(trigger_card, trigger, trigger_details, only_cost_check)


# Hands a left click to the combat UI if it wants it. Returns true if the click was used.
func _combat_click(event: InputEvent) -> bool:
	var game := _game()
	if game == null or game.combat_ui == null or not game.combat_ui.wants_card_clicks() \
			or get_parent() != cfc.NMAP.board or buttons.are_hovered() or tokens.are_hovered():
		return false
	# The framework gives the click to the card with the highest index under the mouse
	var focused: Card = cfc.NMAP.board.mouse_pointer.current_focused_card
	if focused != null and focused != self:
		focused._on_Card_gui_input(event)
		return true
	cfc.card_drag_ongoing = null
	game.combat_ui.card_clicked(self)
	return true


func _game() -> FateGame:
	var found := get_tree().get_nodes_in_group("fate_game")
	return found[0] if not found.is_empty() else null


func _on_Card_gui_input(event) -> void:
	# Debug mode: the middle button opens the menu to move, tilt, flip or delete the card
	if event is InputEventMouseButton and event.is_pressed() and event.get_button_index() == 3:
		var board = cfc.NMAP.get("board")
		if board and board.get("debug") != null and board.debug.enabled:
			board.debug.open_card_menu(self)
			return
	# In the combat phases a left click on a card on the table selects it (FateCombatUI) instead
	# of starting a drag or a double-click action
	if event is InputEventMouseButton and event.is_pressed() and event.get_button_index() == 1 \
			and _combat_click(event):
		return
	super._on_Card_gui_input(event)
	if event is InputEventMouseButton:
		if event.is_pressed() and event.get_button_index() == 2:
			targeting_arrow.initiate_targeting()
		elif not event.is_pressed() and event.get_button_index() == 2:
			targeting_arrow.complete_targeting()
