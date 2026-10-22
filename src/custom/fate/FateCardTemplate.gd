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
# True while the card glows as playable (FateBoard decides, FateCardFx draws the glow)
var playable := false
# True while the card is face-down in the opponent's hand (FateHand): it ignores the mouse
var concealed := false
# Set when the card left a concealed hand (the AI's): it was face-down there, and turns face-up as it
# reaches the table (an energy card stays face-down)
var reveal_on_table := false
var fx: FateCardFx
const PLAYABLE_COLOR := Color(0.35, 0.72, 1.0)


func _ready() -> void:
	super._ready()
	state_changed.connect(_on_state_changed)
	# New cards, and the duplicates the card detail dock makes of table cards, show the full card
	# and no playable glow
	if card_front and card_front.has_method("set_table_mode"):
		card_front.set_table_mode(false)
	# Tilt, lift, shadow, the playable glow and the foil of the card's rarity (FateRarity)
	fx = FateCardFx.attach(self)
	set_playable(false)


# Hotkeys for the card under the mouse (the hover buttons are small and hard to hit):
# T tilts it (strike / guard), A runs its action or ability, F flips it face up / down
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo \
			or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var board = cfc.NMAP.get("board")
	if board == null or get_parent() != board or concealed or cfc.card_drag_ongoing != null:
		return
	if board.mouse_pointer.current_focused_card != self:
		return
	match event.keycode:
		KEY_T:
			buttons.tilt()
		KEY_A:
			buttons.run_first_action()
		KEY_F:
			buttons.flip()
		_:
			return
	get_viewport().set_input_as_handled()


# A concealed card never takes the mouse, whatever its state asks for
func set_control_mouse_filters(value = true) -> void:
	super.set_control_mouse_filters(value and not concealed)


# The blue glow of a card in the hand that can be played right now (FateBoard decides). FateCardFx
# draws it around the card's tilted shape.
func set_playable(on: bool) -> void:
	playable = on
	if fx:
		fx.glowing = on


# Cards on the table take the scale of the zone they stand in (FateLayout.ZONE_SCALES) and show
# their compact table face (FateCardFront.set_table_mode); everywhere else the full card.
func _on_state_changed(_card, _old_state: int, new_state: int) -> void:
	if reveal_on_table and new_state in [CardState.DROPPING_TO_BOARD, CardState.ON_PLAY_BOARD]:
		reveal_on_table = false
		if not is_energy and not is_faceup:
			set_is_faceup(true, true)
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


# A field spell can be cast on either player's field (it replaces the spell there): the player whose field
# slot it takes controls it ("you" in its text), its caster stays the owner. `mandatory_grid_name` names the
# field slot it is aimed at.
func field_seat() -> int:
	if board_zone() != "field":
		return controller_id
	for pid in [1, 2]:
		if mandatory_grid_name == FateZones.grid_name("field", pid):
			return pid
	return owner_id


# Aims a field spell at a player's field slot (no effect on other cards)
func aim_field(player_id: int) -> void:
	if board_zone() == "field":
		mandatory_grid_name = FateZones.grid_name("field", player_id)


# A field spell in the hand may be dropped on either player's field slot
func allows_grid(grid_name: String) -> bool:
	if board_zone() == "field" and not _is_board_parent():
		return grid_name in [FateZones.grid_name("field", 1), FateZones.grid_name("field", 2)]
	return super.allows_grid(grid_name)


func _is_board_parent() -> bool:
	return cfc.NMAP.has("board") and get_parent() == cfc.NMAP.board


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
	# A card leaving the table: its script hears about it (cards/FateCardEffect.on_leave). Reported from
	# here, one frame later, because the move into a pile finishes after an animation (the post-move
	# scripts run only then). Moves inside the table (into or out of the energy zone) are reported
	# by the code that makes them.
	if game.card_effects and old_host == cfc.NMAP.get("board") and new_host != old_host \
			and not is_energy:
		game.card_effects.card_left.call_deferred(self, _zone_name_of(new_host.name))
		# A field spell off the table is its owner's again, aimed at their field
		if board_zone() == "field":
			aim_field(owner_id)
			controller_id = owner_id
	if "Scripted" in move_tags or not old_host is Hand or new_host == old_host:
		_make_room(game, new_host, old_host)
		return new_host
	if game.debug_mode:
		# Debug mode: any player can play any card, at any time, for free
		if new_host == cfc.NMAP.board:
			if is_instant_spell():
				game.card_played.emit(self)
				return FateZones.container("discard", owner_id)
			_make_room(game, new_host, old_host)
			_play_pending = true
		return new_host
	# Cards in hand can only be played by their owner, on their turn
	if owner_id != game.active_id:
		return old_host
	if new_host != cfc.NMAP.board:
		return new_host
	if not game.can_play_from_hand(self):
		return old_host
	# A field spell dropped on a field slot is aimed at that player's field
	var hovered: BoardPlacementSlot = get_potential_placement_slot()
	if hovered != null and board_zone() == "field":
		for pid in [1, 2]:
			if hovered.get_grid_name() == FateZones.grid_name("field", pid):
				aim_field(pid)
	if is_instant_spell():
		# A regular spell resolves into the discard pile. The move to the pile cannot fail
		# from here, so it is paid for now
		if not game.pay(self):
			return old_host
		var destination := _spell_destination(game)
		game.card_played.emit(self)
		return destination
	# The board may still refuse the drop (no free slot, wrong zone), so the payment waits
	# for the post-move script
	_make_room(game, new_host, old_host)
	_play_pending = true
	return new_host


func common_post_move_scripts(new_host: String, old_host: String, _move_tags: Array) -> void:
	var was_energy := is_energy
	# A card leaving the energy zone is no longer energy. Judged by where the card is now: a move into a
	# pile finishes late, and a later move (a spell sent on to the energy zone) may have put it back
	if is_energy and not _is_board(new_host) and get_parent() != cfc.NMAP.board:
		is_energy = false
	# A card that leaves the table forgets damage, modifiers and keyword grants
	if get_parent() != cfc.NMAP.board:
		var left_game := _game()
		if left_game and left_game.stats:
			left_game.stats.clear_card(self)
	# A card placed in a pile: the cards on the table that watch the piles hear it (Cycle of Life)
	if new_host != old_host and _zone_name_of(new_host) in FateZones.PILES:
		var pile_game := _game()
		if pile_game and pile_game.is_started and pile_game.card_effects:
			pile_game.card_effects.card_placed_in_pile.call_deferred(self, _zone_name_of(new_host))
	var entering := _is_board(new_host) and not _is_board(old_host)
	if not _play_pending:
		# Entered the table without being played from the hand: returned, created, taken ...
		var other_game := _game()
		if entering and not is_energy and other_game and other_game.card_effects:
			other_game.card_effects.card_entered(self)
		return
	_play_pending = false
	var game := _game()
	if not game or get_parent() != cfc.NMAP.board:
		# The board refused the drop, the card is back in the hand
		return
	if game.debug_mode or game.pay(self):
		entered_turn = game.turn_number
		controller_id = field_seat()
		game.card_played.emit(self)
		if game.card_effects:
			game.card_effects.card_entered(self, true)
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


# A field or world spell landing on the table sends the card in its slot to the discard pile first
# (FateEquip.make_room): the board has one slot per grid and would refuse the drop
func _make_room(game: FateGame, new_host: Node, old_host: Node) -> void:
	if game.equip and new_host == cfc.NMAP.get("board") and old_host != new_host:
		game.equip.make_room(self)


# Is this the node name of the board (the post-move scripts get container names, not nodes)?
static func _is_board(container_name: String) -> bool:
	return cfc.NMAP.has("board") and is_instance_valid(cfc.NMAP.board) and container_name == cfc.NMAP.board.name


# "Discard_P1" -> "discard", "Hand_P2" -> "hand"
static func _zone_name_of(container_name: String) -> String:
	return container_name.to_lower().rsplit("_p", true, 1)[0]


# Where a resolving regular spell goes: its owner's discard pile unless a card script says otherwise
# (FateCardEffects.spell_destination). Zones that are not piles (energy) are reached through the
# library after the spell resolved.
func _spell_destination(game: FateGame) -> Node:
	var zone: String = game.card_effects.spell_destination(self) if game.card_effects else "discard"
	var container = FateZones.container(zone, owner_id)
	if container != null:
		return container
	if zone == "energy" and game.library:
		game.library.to_energy.call_deferred(self, owner_id)
	return FateZones.container("discard", owner_id)


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
