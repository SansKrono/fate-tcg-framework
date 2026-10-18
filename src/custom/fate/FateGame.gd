# The rules layer of the Fate proof of concept, and its public entry point.
#
# Design document: Section 4 (SYS-PLAYER, SYS-TURN) and Section 7 (SYS-ENERGY).
# Rules: docs/FATE_RULES_SPEC.md. The details live in two helpers owned by this node:
#   turn (FateTurn)  the ten-step turn and its phases, see the comment block in FateTurn.gd
#   mana (FateMana)  energy as mana and cost payment
# Implemented here: two players, the turn flow, the energy choice, playing cards from the
# hand in the main phase (with payment), the mana count and the end of the game. Combat and
# the layers under it are helpers owned by this node:
#   stats (FateStats)        base and current Strike / Guard, damage, modifiers, keyword grants
#   keywords (FateKeywords)  the keyword registry and its hooks (src/custom/fate/keywords/)
#   effects (FateEffects)    destroy() and deal_damage()
#   actions (FateActions)    activated card actions (hover buttons) offered by keywords
#   combat (FateCombat)      declare, intercept, resolve
# Not implemented yet: card scripts.
# See src/custom/fate/README.md for an overview.
class_name FateGame
extends Node

signal game_started
# Step 1 of a turn, before maintenance
signal turn_started(player_id: int, turn_number: int)
# The turn is over, the next player's turn has not started yet
signal turn_ended(player_id: int)
# Every phase start. The same event reaches card scripts as the "phase_begins" trigger
signal phase_begins(player_id: int, phase: int)
# A phase is left. `phase` still holds the phase that ended while this is emitted
signal phase_ended
# Start of MAINTENANCE, before anything untaps (the stats layer resets current stats here)
signal maintenance_started(player_id: int)
# Start of END, followed by end_of_turn_expiry: "until end of turn" effects expire
signal end_phase_begins(player_id: int)
signal end_of_turn_expiry(player_id: int)
# The player made the choice of the ENERGY phase, see `energy_choice`
signal energy_phase_choice_made
signal energy_played(card: Card)
# A card was played from the hand in the main phase and paid for (spells: when they
# resolve into the discard pile)
signal card_played(card: Card)
# Energy of a player was tapped or untapped
signal mana_changed(player_id: int)
# The deck of a player was empty when a card had to be drawn (win/loss: not in scope yet)
signal deck_empty(player_id: int)
# End of MAINTENANCE: everything untapped, damage reset (keywords' on_maintenance runs now)
signal maintenance_finished(player_id: int)
# A card on the table was destroyed (FateEffects.destroy). `cause` is a FateEffects.CAUSE_* value
signal creature_destroyed(card: Card, cause: String)
# Damage was really dealt to a creature (Card) or a player (FatePlayer); `source` may be null
signal damage_dealt(source, target, amount: int, cause: String)
# A player's life reached 0 or less
signal player_defeated(player_id: int)
# The game is over; the other player won. No further turn actions are possible
signal game_ended(winner_id: int)
# A board state was loaded into the table (see load_board_state)
signal board_state_loaded(state_name: String)

const Phase := FateTurn.Phase

const STARTING_HAND := 7
# D1: does the first player skip the draw phase of turn 1? No: every turn draws
const FIRST_PLAYER_SKIPS_FIRST_DRAW := false
# The domains of each player's deck. The deck designs are meant to be played as a single colour:
# player 1 plays Order, player 2 plays Primal
const PLAYER_DOMAINS := {1: ["Order"], 2: ["Primal"]}
# Replaces PLAYER_DOMAINS for the games started after it is set (player id -> domains). Tests and the AI
# tournament use it for mirror matches; leave it empty otherwise.
static var domain_override := {}
# Replaces the deck list of a player for the games started after it is set (player id -> {card name: copies}).
# The AI simulation (src/custom/fate/sim/) plays custom decks with it; leave it empty otherwise.
static var decklist_override := {}
const DOMAIN_BY_INITIAL := {"I": "Innovation", "C": "Chaos", "O": "Order", "P": "Primal"}
# What the ENERGY phase choice was this turn (`energy_choice`)
const CHOICE_ENERGY := "energy"
const CHOICE_DRAW := "draw"

var players := {}
var active_id := 1
var turn_number := 0
var is_started := false
# Starts as FIRST_PLAYER_SKIPS_FIRST_DRAW; a variable so that tests can try both rules
var first_player_skips_first_draw := FIRST_PLAYER_SKIPS_FIRST_DRAW
# "" until the active player chooses in the ENERGY phase, then CHOICE_ENERGY or CHOICE_DRAW.
# Reset when a turn starts
var energy_choice := ""
# The combat manager (FateCombat), or any object with the interface of FateTurn.gd, or null.
# The turn machine calls its begin_declaration(), begin_intercept() and begin_resolution() methods
var combat = null
# Set by the board: the combat UI (FateCombatUI), which turns clicks on cards into combat calls
var combat_ui = null
var turn: FateTurn
var mana: FateMana
var stats: FateStats
var keywords: FateKeywords
var effects: FateEffects
var actions: FateActions
# Reactions: the reaction spell manager (src/custom/fate/FateReactions.gd, no class_name, so untyped)
var reactions
# True once a player was defeated; `winner_id` is the other player
var is_over := false
# Why the last capture_board_state() returned null
var board_state_errors: Array[String] = []
# Debug mode (see FateDebug): the rules for moving and tilting cards are not enforced and
# playing a card from the hand is free
var debug_mode := false
var winner_id := 0

# The card-logic layer (docs: src/custom/fate/cards/README.md). Path-loaded helpers, no class_name:
#   card_effects  FateCardEffects  the Fx*.gd card scripts and the events that reach them
#   choices       FateChoices      targets and "you may" questions (an AI or UI answers through it)
#   costs         FateCosts        costs of activated abilities
#   tokens        FateTokens       scrap / ingot counters and token cards
#   control       FateControl      taking control of cards
#   casting       FateCasting      flip cast, cast from the discard pile, temporary creatures
#   library       FateLibrary      draw, search, shuffle, move cards between zones
#   equip         FateEquip        relics on creatures, field and world slots
#   limiter       FateLimiter      once-per-turn abilities
var card_effects
var choices
var costs
var tokens
var control
var casting
var library
var equip
var limiter

# The AI players, seat -> FateAIController (src/custom/fate/ai/). A seat without an entry is played by a
# person. See set_ai().
var ai_controllers := {}

# The current phase (FateGame.Phase), the turn machine owns it
var phase: int:
	get:
		return turn.phase


# Adds the Fate cards to the framework's card definitions. The framework loads only
# the demo sets by itself, see FateData.
static func register_cards() -> void:
	# The framework loads the card scripts in a worker thread that iterates over
	# cfc.card_definitions (started by cfc._setup()). Changing the dictionary while it runs
	# crashes the engine, which happens when tests set the framework up again right before
	# the board is built. The thread is short-lived, so we simply wait for it.
	if cfc.script_load_thread and cfc.script_load_thread.is_started():
		cfc.script_load_thread.wait_to_finish()
	cfc.card_definitions.merge(FateData.CARDS, true)
	cfc.card_definitions.merge(FateData.TOKENS, true)
	cfc.card_definitions.merge(FateData.DOCTRINES, true)


func _init() -> void:
	turn = FateTurn.new(self)
	mana = FateMana.new(self)
	# The order matters: the stats layer connects to the turn signals before the keyword registry
	stats = FateStats.new(self)
	keywords = FateKeywords.new(self)
	effects = FateEffects.new(self)
	actions = FateActions.new(self)
	combat = FateCombat.new(self)
	# Reactions: listens to combat's reaction windows (loaded by path to keep it out of the class cache)
	reactions = load("res://src/custom/fate/FateReactions.gd").new(self)
	# The card-logic layer. The systems first, the script registry last: it listens to combat
	choices = load("res://src/custom/fate/FateChoices.gd").new(self)
	costs = load("res://src/custom/fate/FateCosts.gd").new(self)
	tokens = load("res://src/custom/fate/FateTokens.gd").new(self)
	control = load("res://src/custom/fate/FateControl.gd").new(self)
	casting = load("res://src/custom/fate/FateCasting.gd").new(self)
	library = load("res://src/custom/fate/FateLibrary.gd").new(self)
	equip = load("res://src/custom/fate/FateEquip.gd").new(self)
	limiter = load("res://src/custom/fate/FateLimiter.gd").new(self)
	card_effects = load("res://src/custom/fate/FateCardEffects.gd").new(self)


func _ready() -> void:
	add_to_group("fate_game")
	for pid in range(1, FateZones.PLAYER_COUNT + 1):
		players[pid] = FatePlayer.new(pid, "Player %d" % pid, domain_override.get(pid, PLAYER_DOMAINS[pid]))


func player(player_id: int) -> FatePlayer:
	return players.get(player_id)


func active_player() -> FatePlayer:
	return players[active_id]


# Instances the decks and doctrine cards of both players, draws the starting hands
# and starts the first turn. The zones must already exist.
func start_game() -> void:
	if is_started:
		return
	register_cards()
	for pid in players:
		_build_deck(players[pid])
		_place_doctrines(players[pid])
	# Let the cards finish setting up before moving them (tests do not need to watch)
	await get_tree().create_timer(0.1 if cfc.is_testing else 0.3).timeout
	for pid in players:
		for _i in range(STARTING_HAND):
			players[pid].draw_card()
			await get_tree().create_timer(0.01 if cfc.is_testing else 0.04).timeout
	is_started = true
	active_id = 1
	turn_number = 0
	energy_choice = ""
	game_started.emit()
	start_turn()


func _build_deck(p: FatePlayer) -> void:
	var names := FateDecks.build(p.domains, cfc.game_rng, decklist_override.get(p.id, {}))
	var pile := p.deck()
	for card_name in names:
		var card: Card = cfc.instance_card(card_name)
		pile.add_child(card)
		if card is FateCardTemplate:
			card.assign_owner(p.id)
		card._determine_idle_state()


func _place_doctrines(p: FatePlayer) -> void:
	for card_name in FateDecks.doctrines_for(p.domains):
		if not place_card_on_table(card_name, p.id, "doctrines"):
			break


# Creates a card straight on a zone of the table, owned by the player (setup and tests).
# Returns null if the zone is full.
func place_card_on_table(card_name: String, player_id: int, zone: String) -> Card:
	return place_card_at(card_name, player_id, zone)


# Creates a card straight on a slot of a table grid, owned by the player. No move, no signals, no
# rules: the slot and the state are set directly and entered_turn stays 0. The zone look (energy
# face-down, occupied tilted) is not applied, see FateCardTemplate.apply_zone_look.
# `zone` is a grid zone ("creatures", "occupied", "relics", "field", "doctrines", "energy") or
# "world" (the shared slot, `player_id` only decides the owner). `slot_index` -1 takes the first free
# slot; an energy grid grows until the slot exists.
# Returns null if the slot is taken, the index is out of range for a zone that does not grow, the
# zone is not a grid, or the card name is unknown.
func place_card_at(card_name: String, player_id: int, zone: String, slot_index := -1) -> Card:
	if not cfc.card_definitions.has(card_name) or not players.has(player_id):
		return null
	var grid: BoardPlacementGrid = FateZones.grid(zone, player_id)
	if grid == null:
		return null
	var slot: BoardPlacementSlot
	if slot_index < 0:
		slot = grid.find_available_slot()
	else:
		while grid.auto_extend and grid.get_slot_count() <= slot_index:
			grid.add_slot()
		if slot_index < grid.get_slot_count():
			slot = grid.get_slot(slot_index)
	if slot == null or slot.occupying_card:
		return null
	var card: Card = cfc.instance_card(card_name)
	cfc.NMAP.board.add_child(card)
	if card is FateCardTemplate:
		card.assign_owner(player_id)
	card.position = slot.global_position
	card._placement_slot = slot
	slot.occupying_card = card
	card.state = Card.CardState.ON_PLAY_BOARD
	return card


# Creates a card owned by the player and puts it on TOP of the hand, deck, discard or removed
# pile (the last child; for the hand: to the right of the others). A coroutine: await it, one call
# after the other keeps the call order. The deck is filled like _build_deck does; the other zones
# are reached by a scripted move from the owner's deck.
# Returns the card, or null if the card name is unknown or the zone is not one of these four.
func place_in_container(card_name: String, player_id: int, zone: String) -> Card:
	if not zone in ["hand", "deck", "discard", "removed"] or not players.has(player_id) \
			or not cfc.card_definitions.has(card_name):
		return null
	var deck: Pile = players[player_id].deck()
	var target = FateZones.container(zone, player_id)
	if deck == null or target == null:
		return null
	var card: Card = cfc.instance_card(card_name)
	deck.add_child(card)
	if card is FateCardTemplate:
		card.assign_owner(player_id)
	card._determine_idle_state()
	if zone == "deck":
		return card
	# The new card has to finish setting up before it moves
	if cfc.is_testing:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(card):
		return null
	if cfc.is_testing:
		# The card is in its new container as soon as move_to starts; what it waits for after that
		# is the end of its slide animation
		card.move_to(target, -1, null, ["Scripted"])
		await get_tree().process_frame
	else:
		await card.move_to(target, -1, null, ["Scripted"])
	return card if is_instance_valid(card) else null


# Deletes every card of the table: both hands, piles, all grids (the world slot too) and the cards
# attached to them, then frees the slots and shrinks the energy grids to their first size. Cancels
# the combat and clears the combat UI, forgets all stats, ends the "game over" state and the energy
# choice, and refreshes the mana. A coroutine: await it (the cards are gone from the tree after it).
# Does not touch the turn number, the active player, the phase, the life or the rng.
func reset_table() -> void:
	if combat != null:
		if combat.has_method("cancel_combat"):
			combat.cancel_combat()
		combat.attacks.clear()
	if combat_ui != null:
		combat_ui.clear_selection()
	cfc.card_drag_ongoing = null
	var doomed := []
	for pid in players:
		for zone in ["hand", "deck", "discard", "removed"]:
			var container = FateZones.container(zone, pid)
			if container:
				doomed.append_array(container.get_all_cards())
		for zone in FateZones.GRIDS:
			doomed.append_array(players[pid].cards_in_grid(zone))
	doomed.append_array(FateZones.grid("world", 0).get_all_slots().filter(
			func(slot): return slot.occupying_card).map(func(slot): return slot.occupying_card))
	# Cards attached to a host, floating cards and anything else left on the board
	for node in cfc.NMAP.board.get_children():
		if node is Card and not node in doomed:
			doomed.append(node)
	for card in doomed:
		_delete_table_card(card)
	for pid in players:
		var energy: BoardPlacementGrid = players[pid].grid("energy")
		while energy.get_slot_count() > FateLayout.ENERGY_START_SLOTS:
			var extra: Node = energy.get_all_slots().back()
			extra.get_parent().remove_child(extra)
			extra.queue_free()
		energy.size = Vector2.ZERO
	if stats != null and stats.has_method("clear_all"):
		stats.clear_all()
	if tokens != null:
		tokens.reset()
	is_over = false
	winner_id = 0
	energy_choice = ""
	cfc.flush_cache()
	# The deleted cards leave the tree at the end of the frame
	await get_tree().process_frame
	for pid in players:
		mana_changed.emit(pid)


func _delete_table_card(card: Card) -> void:
	if not is_instance_valid(card) or card.is_queued_for_deletion():
		return
	var slot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	card._placement_slot = null
	if stats != null:
		stats.clear_card(card)
	var parent := card.get_parent()
	if parent:
		parent.remove_child(card)
	card.remove_from_group("cards")
	card.queue_free()


# All creatures in play (the creature and the occupied zones) of one player, or of both players
# (player_id 0), as an array of cards
func creatures_in_play(player_id := 0) -> Array:
	var found := []
	for pid in players:
		if player_id != 0 and pid != player_id:
			continue
		for zone in FateZones.CREATURE_ZONES:
			found.append_array(players[pid].cards_in_grid(zone))
	return found


# A player's life reached 0 or less (FateEffects calls this): they lose, the other player wins.
# Emits player_defeated and game_ended, and stops all turn actions.
func defeat_player(player_id: int) -> void:
	if is_over:
		return
	is_over = true
	winner_id = FateZones.opponent_of(player_id)
	player_defeated.emit(player_id)
	game_ended.emit(winner_id)


# --- board states (src/custom/fate/state/, docs/FATE_BOARD_STATE.md) ------------------------------

# Captures the whole table as a FateBoardState (zones in order, stats, mana, life, turn, phase, rng).
# Returns null if the table is in a step that cannot be stored; `board_state_errors` says why.
func capture_board_state(opts := {}) -> FateBoardState:
	return FateBoardStateCapture.capture(self, opts)


# Rebuilds the table from a FateBoardState, replacing everything on it, without running any rules
# (see FateBoardStateApply). A coroutine: await it.
# Returns {ok: bool, errors: Array[String], warnings: Array[String]}. When `ok` is false the table is
# the one it was before. `opts`: "verify", "rollback", "reset_hooks" (see FateBoardStateApply.apply).
func load_board_state(state: FateBoardState, opts := {}) -> Dictionary:
	return await FateBoardStateApply.apply(self, state, opts)


# Starts the game in a stored position instead of dealing a new game (what `--board=<name>` does).
# Same result as load_board_state; on success the game counts as started (game_started is emitted).
func start_from_state(state: FateBoardState, opts := {}) -> Dictionary:
	var was_started := is_started
	var result: Dictionary = await load_board_state(state, opts)
	if result["ok"] and not was_started:
		game_started.emit()
	return result


# --- turn flow (FateTurn) -----------------------------------------------------------

# Starts the next turn: player 1 the first time, then the players alternate. Runs the
# automatic phases (maintenance, draw) and waits in the ENERGY phase.
func start_turn() -> void:
	turn.start_turn()


# Moves to the next phase if that is legal now (not in ENERGY before the choice, not in the
# automatic phases). Returns whether it moved. Stage 2's combat object calls this when it is
# done with a combat step.
func advance_phase() -> bool:
	return turn.advance()


# Ends the active player's turn at any point and starts the other player's.
func end_turn() -> void:
	turn.end_turn()


# What the "Next phase" control does: in a combat phase with a combat object that has a
# next_requested() method it asks the combat object, otherwise it advances.
func request_next_phase() -> bool:
	if phase in FateTurn.COMBAT_HOOKS and combat != null and is_instance_valid(combat) \
			and combat.has_method("next_requested"):
		combat.next_requested()
		return true
	return advance_phase()


# Can the "Next phase" control be used now?
func can_request_next_phase() -> bool:
	if is_over or ai_has_the_turn():
		return false
	if phase in FateTurn.COMBAT_HOOKS:
		return combat != null
	return turn.can_advance()


# Can the "End turn" control be used now? Not before the ENERGY choice (D3).
func can_end_turn() -> bool:
	if not is_started or is_over or ai_has_the_turn():
		return false
	match phase:
		Phase.NONE, Phase.MAINTENANCE, Phase.DRAW:
			return false
		Phase.ENERGY:
			return energy_choice != ""
	return true


# Is an AI player in the middle of its own turn, so that the controls of a person must stay out of
# the way? Not while a person defends: they need "Next phase" to pass a reaction window, and in the
# intercept and resolve steps.
func ai_has_the_turn() -> bool:
	if not ai_controllers.has(active_id):
		return false
	var window = combat.current_window if combat != null and is_instance_valid(combat) else null
	if window != null and window.is_open and not ai_controllers.has(window.player_id):
		return false
	return phase in [Phase.ENERGY, Phase.MAIN, Phase.COMBAT_DECLARE]


# --- energy phase -------------------------------------------------------------------

# Can this card be played as an energy card right now? Only its owner, from the hand,
# in their ENERGY phase, and only if the choice of the phase was not made yet.
func can_play_as_energy(card: Card) -> bool:
	if not is_started or is_over or not card is FateCardTemplate:
		return false
	return phase == Phase.ENERGY \
			and energy_choice == "" \
			and card.owner_id == active_id \
			and card.get_state_exec() == "hand"


# Plays a card from the hand face-down into the player's energy zone and moves on to the
# main phase. Rule (Section 1, step 4): in the energy phase, instead of drawing an extra card.
func play_as_energy(card: Card) -> bool:
	if not can_play_as_energy(card):
		return false
	var g: BoardPlacementGrid = players[card.owner_id].grid("energy")
	var slot := g.find_available_slot()
	if not slot:
		return false
	card.is_energy = true
	card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	card.set_is_faceup(false, true)
	energy_played.emit(card)
	mana_changed.emit(card.owner_id)
	_make_energy_choice(CHOICE_ENERGY)
	return true


func can_draw_extra_card() -> bool:
	return is_started and not is_over and phase == Phase.ENERGY and energy_choice == ""


# The other choice of the energy phase: draw an additional card instead of playing energy
func draw_extra_card() -> bool:
	if not can_draw_extra_card():
		return false
	# An empty deck loses the game (FateLibrary.draw)
	library.draw(active_id)
	_make_energy_choice(CHOICE_DRAW)
	return true


# Either choice ends the energy phase
func _make_energy_choice(choice: String) -> void:
	energy_choice = choice
	energy_phase_choice_made.emit()
	advance_phase()


# --- main phase: playing cards, mana --------------------------------------------------

# Can this card be played from the hand right now? Only the owner, in their main phase,
# and only if it can be paid for. Reaction spells cannot be cast in the main phase (D8).
func can_play_from_hand(card: Card) -> bool:
	if not is_started or is_over or not card is FateCardTemplate:
		return false
	if phase != Phase.MAIN or card.owner_id != active_id:
		return false
	if not card.get_parent() is Hand or card.is_reaction_spell():
		return false
	# The card's own script may forbid it: no legal target, an additional cost that cannot be paid
	if card_effects != null and card_effects.play_problem(card) != "":
		return false
	return can_pay(card)


# Can this creature be tilted (strike / guard) by the player right now? Only the controller's
# creatures on the table, in their main phase.
func can_tilt(card: Card) -> bool:
	if not is_started or is_over or not card is FateCardTemplate:
		return false
	# The zone the card is in now, not the zone its type goes to: an occupied creature has to
	# stay tilted and cannot be repositioned (design doc Section 5.3)
	if debug_mode:
		return FateZones.zone_of(card) != ""
	return phase == Phase.MAIN and card.controller_id == active_id \
			and FateZones.zone_of(card) == "creatures"


# Plays a card from the hand the way dropping it on the table does: the owner, in their main phase,
# paying its cost. Creatures, relics and field / world spells go to a free slot of their zone, regular
# spells resolve into the discard pile. Reaction spells cannot be played here (D8, see FateReactions).
# Returns whether the card was played. For the AI and tests; the UI uses the drag and drop of the
# framework, which ends in the same hooks (FateCardTemplate.common_pre_move_scripts).
func play_from_hand(card: Card) -> bool:
	if not can_play_from_hand(card):
		return false
	var fate_card: FateCardTemplate = card
	if fate_card.is_instant_spell():
		fate_card.move_to(cfc.NMAP.board)
		return not fate_card.get_parent() is Hand
	var grid: BoardPlacementGrid = FateZones.grid(fate_card.board_zone(), fate_card.owner_id)
	if grid == null:
		return false
	# A field or world spell replaces the card in its slot (the old one goes to the discard pile)
	if equip != null:
		equip.make_room(fate_card)
	var slot := grid.find_available_slot()
	if slot == null:
		return false
	# With the slot given the move needs no waiting: the rules hooks have run when it returns
	fate_card.move_to(cfc.NMAP.board, -1, slot)
	return fate_card.get_parent() == cfc.NMAP.board


# Gives a seat an AI player (src/custom/fate/ai/FateAIController.gd) or takes it away. `level` is
# FateAIProfile.Level: 0 easy, 1 normal, 2 hard. Returns the controller, or null when switched off.
# An AI already on that seat is kept (use its `profile` to change it).
func set_ai(seat: int, on := true, level := 1):
	if not players.has(seat):
		return null
	if not on:
		var old = ai_controllers.get(seat)
		if old != null and is_instance_valid(old):
			old.set_enabled(false)
			old.queue_free()
		ai_controllers.erase(seat)
		return null
	var existing = ai_controllers.get(seat)
	if existing != null and is_instance_valid(existing):
		existing.set_enabled(true)
		return existing
	var controller = load("res://src/custom/fate/ai/FateAIController.gd").new()
	controller.name = "AI_P%d" % seat
	add_child(controller)
	controller.setup(self, seat, level)
	ai_controllers[seat] = controller
	# FATE_AI_LOG=1 prints what the AI decides and why (see FateAIController.log_lines)
	if OS.get_environment("FATE_AI_LOG") != "":
		controller.noted.connect(func(line): print(line))
	# Switched on in the middle of a game: take over wherever it is
	controller.resume()
	return controller


# The mana available to a player, as a dictionary domain -> amount.
# Each untapped energy card gives 1 mana of one of its domains (the first, for now:
# the choice for dual-domain cards is not implemented). See FateMana.
func mana_pool(player_id: int) -> Dictionary:
	return mana.mana_pool(player_id)


func can_pay(card: Card) -> bool:
	return mana.can_pay(card)


# Taps the energy that pays for a card (D4). Returns false if it cannot be paid.
func pay(card: Card) -> bool:
	return mana.pay(card)
