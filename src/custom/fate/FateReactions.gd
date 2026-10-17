# The reaction manager: casting reaction spells in the reaction windows of combat. Assigned to
# `game.reactions` (created by FateGame). Rules: docs/FATE_RULES_SPEC.md, Section 4 ("Reaction
# windows") and decision D8 (reaction spells cannot be cast in the main phase; FateGame and the turn
# system already deny that). No class_name on purpose (FateGame loads this script by path).
#
# How it works
#   * FateCombat opens a window at the end of the declare step ("declare_end") and of the intercept
#     step ("intercept_end") and emits reaction_window_requested(window). The window carries
#     `player_id`, the defending player, the only one who may react.
#   * If that player has a reaction spell they could cast right now, the manager hold()s the window
#     (combat waits), marks the castable spells in their hand (a tint) and keeps the window open for
#     further reactions until the player passes: the "Next phase" button (or window.close()) ends it
#     and combat goes on with the effects applied. Nothing castable: the window is left alone and
#     combat continues at once.
#   * cast(card) validates (cast_problem), pays through game.pay(), resolves the spell's effect,
#     and moves the card to its owner's discard pile. Double-clicking a reaction spell in the hand
#     does the same (FateCardTemplate.execute_scripts routes it here).
#
# Holding is switched off while the framework's tests run (`hold_windows` defaults to
# `not cfc.is_testing`), so other tests, which may deal their players random hands with mana, never
# stop at a window; a test of reactions sets `game.reactions.hold_windows = true`. cast() itself
# works in any open window, held by this manager or by somebody else.
#
# The effects: one small script per spell in src/custom/fate/reactions/ (React<Name>.gd, extending
# FateReactionEffect.gd, registered by their `card_name`). Add a script there to add a spell; Double
# Agent has none yet (it needs take-control) so it can never be cast.
#
# Choosing targets: spells with a choice (Safety Measure, Wave of Fear, Hold the Line) use, in this
# order, the explicit `choice` of cast(card, choice), then the `chooser` Callable, then the
# deterministic default of the effect. `chooser` has the signature
#   chooser(card: Card, candidates: Array) -> Variant      (return null to use the default)
# where `candidates` are the cards the effect allows, and the result is a Card (Safety Measure) or an
# array of cards (Wave of Fear, Hold the Line). A later UI plugs its picker in there.
extends RefCounted

# Emitted after a reaction spell resolved and went to the discard pile
signal reaction_cast(card: Card, window)

const EFFECT_DIR := "res://src/custom/fate/reactions/"
const EFFECT_PREFIX := "React"
# The tint of castable reaction spells in the hand while a window is open for their owner
const MARK_COLOR := Color(1.0, 0.9, 0.35)

var game: FateGame
# Hold windows in which the defender has something castable, see the header comment
var hold_windows := true
# Picks the targets for the spells with a choice, see the header comment. Unset: the defaults.
var chooser := Callable()
# Why the last cast() was refused
var last_error := ""

# card name -> effect (FateReactionEffect.gd instance)
var _effects := {}
var _combat = null
var _marked: Array = []
var _marked_window = null


func _init(owner_game: FateGame) -> void:
	game = owner_game
	hold_windows = not cfc.is_testing
	discover()
	attach(game.combat)
	game.mana_changed.connect(_on_mana_changed)


# --- registration ---------------------------------------------------------------------------------

# Scans EFFECT_DIR and registers every React*.gd effect. Returns how many were registered.
func discover(folder := EFFECT_DIR) -> int:
	var found := 0
	var dir := DirAccess.open(folder)
	if dir == null:
		return 0
	var seen := {}
	for file_name in dir.get_files():
		var script_name := script_file_name(file_name)
		if script_name == "" or seen.has(script_name):
			continue
		seen[script_name] = true
		var script = load(folder + script_name)
		if script == null or not script is GDScript or not script.can_instantiate():
			push_warning("FateReactions: cannot load reaction script " + script_name)
			continue
		var effect = script.new()
		if effect.get("card_name") == null or effect.card_name == "":
			push_warning("FateReactions: %s has no card_name" % script_name)
			continue
		register(effect)
		found += 1
	return found


# Maps a directory listing entry to the `React*.gd` script it stands for, or "" if it is not one
# ("ReactWaveOfFear.gd.remap" and "ReactWaveOfFear.gdc" in an export -> "ReactWaveOfFear.gd")
static func script_file_name(file_name: String) -> String:
	var n := file_name
	if n.ends_with(".remap"):
		n = n.trim_suffix(".remap")
	if n.ends_with(".gdc"):
		n = n.trim_suffix(".gdc") + ".gd"
	if n.begins_with(EFFECT_PREFIX) and n.ends_with(".gd"):
		return n
	return ""


# Adds (or replaces) the effect of a spell
func register(effect) -> void:
	effect.game = game
	_effects[effect.card_name] = effect


func effect_of(card_name: String):
	return _effects.get(card_name)


func registered_names() -> Array:
	var names := _effects.keys()
	names.sort()
	return names


# Listens to the reaction windows of this combat object (FateGame calls it for game.combat; call it
# again if game.combat is replaced)
func attach(combat) -> void:
	if _combat != null and is_instance_valid(_combat) \
			and _combat.reaction_window_requested.is_connected(_on_window_requested):
		_combat.reaction_window_requested.disconnect(_on_window_requested)
	_combat = combat
	if combat != null and is_instance_valid(combat) and combat.has_signal("reaction_window_requested"):
		combat.reaction_window_requested.connect(_on_window_requested)


# --- queries ------------------------------------------------------------------------------------------

# The reaction window that is open now (FateCombat.ReactionWindow), or null
func open_window():
	if game.combat == null or not is_instance_valid(game.combat):
		return null
	var window = game.combat.get("current_window")
	return window if window != null and window.is_open else null


# Is a window open that gives priority to this player?
func window_open_for(player_id: int) -> bool:
	var window = open_window()
	return window != null and window.player_id == player_id


# Why this card cannot be cast now, or "" if it can
func cast_problem(card: Card) -> String:
	if not card is FateCardTemplate or not card.is_reaction_spell():
		return "Not a reaction spell"
	if game.is_over:
		return "The game is over"
	var window = open_window()
	if window == null:
		return "No reaction window is open"
	if card.owner_id != window.player_id:
		return "It is not your reaction window (Player %d reacts)" % window.player_id
	if card.get_parent() != FateZones.container("hand", card.owner_id):
		return "The card is not in your hand"
	var effect = _effects.get(card.canonical_name)
	if effect == null:
		return "%s cannot be cast yet" % card.canonical_name
	if not effect.windows.is_empty() and not window.step in effect.windows:
		return "%s can only be cast at: %s" % [card.canonical_name, ", ".join(effect.windows)]
	var why: String = effect.problem(card.owner_id)
	if why != "":
		return why
	if not game.can_pay(card):
		return "Not enough mana"
	return ""


func can_cast(card: Card) -> bool:
	return cast_problem(card) == ""


# The reaction spells in a player's hand that can be cast now
func castable_in_hand(player_id: int) -> Array:
	var found := []
	var hand = game.player(player_id).hand()
	if hand == null:
		return found
	for card in hand.get_all_cards():
		if can_cast(card):
			found.append(card)
	return found


# --- casting --------------------------------------------------------------------------------------------

# Casts a reaction spell: checks it (cast_problem, see last_error), pays, resolves the effect and
# moves the card to its owner's discard pile. `choice` picks the targets for a spell with a choice
# (see the header comment); null means chooser, then default. Returns whether it was cast.
func cast(card: Card, choice = null) -> bool:
	last_error = cast_problem(card)
	if last_error != "":
		return false
	var effect = _effects[card.canonical_name]
	var caster: int = card.owner_id
	var chosen = choice
	if chosen == null and effect.has_choice and chooser.is_valid():
		chosen = chooser.call(card, effect.candidates(caster))
	if chosen == null:
		chosen = effect.default_choice(caster)
	if effect.has_choice:
		last_error = effect.choice_problem(caster, chosen)
		if last_error != "":
			return false
	if not game.pay(card):
		last_error = "Not enough mana"
		return false
	var window = open_window()
	effect.resolve(card, caster, chosen)
	# "Scripted" moves are never refused by the play rules of FateCardTemplate
	card.move_to(FateZones.container("discard", caster), -1, null, ["Scripted"])
	game.card_played.emit(card)
	reaction_cast.emit(card, window)
	refresh_marks()
	return true


# --- the windows and the hand marks ---------------------------------------------------------------

func _on_window_requested(window) -> void:
	if hold_windows and not castable_in_hand(window.player_id).is_empty():
		# Never released: the player passing ("Next phase") closes the window, which ends the hold
		window.hold()
	if window.is_held():
		window.closed.connect(clear_marks, CONNECT_ONE_SHOT)
		refresh_marks()


func _on_mana_changed(_player_id: int) -> void:
	if _marked_window != null:
		refresh_marks()


# Tints the castable reaction spells in the hand of the player the open window is for
func refresh_marks() -> void:
	clear_marks()
	var window = open_window()
	if window == null or not window.is_held():
		return
	_marked_window = window
	for card in castable_in_hand(window.player_id):
		card.modulate = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, card.modulate.a)
		_marked.append(card)


func clear_marks() -> void:
	for card in _marked:
		if is_instance_valid(card):
			card.modulate = Color(1.0, 1.0, 1.0, card.modulate.a)
	_marked.clear()
	_marked_window = null
