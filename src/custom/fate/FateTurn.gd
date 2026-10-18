# The turn state machine of the Fate proof of concept.
# Rules: docs/FATE_RULES_SPEC.md, Section 1 (turn structure) and decisions D1 to D3.
#
# Owned by FateGame (`game.turn`); FateGame stays the public entry point, so callers use
# `game.phase`, `game.advance_phase()`, `game.end_turn()` and `game.start_turn()`.
#
# A turn is ten steps. The first three phases run by themselves, the others wait:
#
#   start         active player changes, turn counter increments, flags reset, `turn_started`
#   MAINTENANCE   automatic. `maintenance_started`, untap everything, occupied -> creatures
#   DRAW          automatic. Draw one card (FateGame.first_player_skips_first_draw, D1)
#   ENERGY        waits. ONE of: play a card face-down as energy, or draw an extra card (D3)
#   MAIN          waits. Play cards from the hand (FateMana pays), tilt creatures
#   COMBAT_DECLARE, COMBAT_INTERCEPT, COMBAT_RESOLVE   see the combat interface below
#   END           `end_phase_begins`, `end_of_turn_expiry`, then the next player's turn starts
#
# --- Signals (all declared on FateGame) -------------------------------------------------
#
#   turn_started(player_id, turn_number)   step 1, before maintenance
#   phase_begins(player_id, phase)         every phase start (see "Card scripts" below)
#   phase_ended                            a phase is left; `game.phase` still holds it
#   maintenance_started(player_id)         start of MAINTENANCE, BEFORE anything untaps. The
#                                          stats layer resets current stats here
#   maintenance_finished(player_id)        end of MAINTENANCE, everything untapped (keywords'
#                                          on_maintenance runs here)
#   end_phase_begins(player_id)            start of END
#   end_of_turn_expiry(player_id)          END: "until end of turn" effects expire here
#   turn_ended(player_id)                  the turn is over, the next one has not started
#   energy_phase_choice_made               the ENERGY choice was made (`game.energy_choice`)
#   mana_changed(player_id)                energy was tapped or untapped
#
# --- Card scripts -----------------------------------------------------------------------
#
# Every phase start is also pushed through the framework's signal propagator as the
# trigger "phase_begins" with details {"player_id", "phase", "phase_name"}, so a card script
# can use `"phase_begins": {...}` as a trigger key. The trigger card is the FateGame node.
# This calls `cfc.signal_propagator._on_signal_received()` directly, the way Counters and
# SelectionWindow already do, so "phase_begins" is NOT added to `known_card_signals`
# (that list is only for signals that cards themselves emit) and no core file is touched.
#
# --- Combat interface ---------------------------------------------------------------------
#
# `game.combat` is the combat manager (FateCombat); tests may put a stand-in or null there. The
# turn machine calls these methods on it when the phase begins (each one is optional: a phase
# whose method is missing is skipped):
#
#   combat.begin_declaration()   COMBAT_DECLARE began: the active player declares attackers
#   combat.begin_intercept()     COMBAT_INTERCEPT began: the defender assigns blockers
#   combat.begin_resolution()    COMBAT_RESOLVE began: resolve the attacks in order
#   combat.next_requested()      optional: the player pressed "Next phase" in a combat phase
#                                (FateGame.request_next_phase). Without it, the press calls
#                                `game.advance_phase()`
#   combat.cancel_combat()       optional: `game.end_turn()` jumped out of the combat phases
#
# The turn waits in a combat phase until the combat object calls `game.advance_phase()`
# when it is done with that step (it may do so synchronously from the begin_* method).
# After COMBAT_RESOLVE, advancing goes to END. Without a combat object (or without the
# method for a step) the three phases are entered one after the other at once, with their
# `phase_begins` signals, so the turn still flows.
#
# --- end_turn() -------------------------------------------------------------------------
#
# `game.end_turn()` jumps from the current phase straight to END (the phases in between are
# not entered, so no `phase_begins` for them; combat is cancelled) and starts the next turn.
# It does not enforce the ENERGY choice; the UI only offers the button when it is legal.
class_name FateTurn
extends RefCounted

enum Phase {
	NONE,
	MAINTENANCE,
	DRAW,
	ENERGY,
	MAIN,
	COMBAT_DECLARE,
	COMBAT_INTERCEPT,
	COMBAT_RESOLVE,
	END,
}

const PHASE_NAMES := {
	Phase.NONE: "Not started",
	Phase.MAINTENANCE: "Maintenance",
	Phase.DRAW: "Draw",
	Phase.ENERGY: "Energy",
	Phase.MAIN: "Main",
	Phase.COMBAT_DECLARE: "Combat: declare attackers",
	Phase.COMBAT_INTERCEPT: "Combat: intercept",
	Phase.COMBAT_RESOLVE: "Combat: resolve",
	Phase.END: "End",
}

# The hook the combat object gets for each combat phase, see the interface above
const COMBAT_HOOKS := {
	Phase.COMBAT_DECLARE: "begin_declaration",
	Phase.COMBAT_INTERCEPT: "begin_intercept",
	Phase.COMBAT_RESOLVE: "begin_resolution",
}

# Step 10 of the spec says the player declares the end of the turn. The END phase has no
# choices, so by default the turn ends as soon as the expiry is done. Set this to true to
# make END wait until advance_phase() or end_turn() is called.
var end_phase_waits_for_player := false

var game: FateGame
var phase: int = Phase.NONE


func _init(owner_game: FateGame) -> void:
	game = owner_game


# --- public ---------------------------------------------------------------------

# Starts the next turn (player 1 on the first call, then the players alternate) and runs
# the automatic phases. Stops in ENERGY, where the player has to choose.
func start_turn() -> void:
	if not game.is_started or game.is_over:
		return
	if game.turn_number == 0:
		game.active_id = 1
	else:
		game.active_id = FateZones.opponent_of(game.active_id)
	game.turn_number += 1
	# Per-turn flags
	game.energy_choice = ""
	phase = Phase.NONE
	game.turn_started.emit(game.active_id, game.turn_number)
	_enter(Phase.MAINTENANCE)


# Can the turn move on to the next phase right now?
func can_advance() -> bool:
	if not game.is_started or game.is_over:
		return false
	match phase:
		Phase.ENERGY:
			# D3: no skipping, the choice has to be made
			return game.energy_choice != ""
		Phase.MAIN, Phase.COMBAT_DECLARE, Phase.COMBAT_INTERCEPT, Phase.COMBAT_RESOLVE:
			return true
		Phase.END:
			return end_phase_waits_for_player
	# NONE, MAINTENANCE and DRAW run by themselves
	return false


# Moves to the next phase. Returns false (and does nothing) when that is not legal.
func advance() -> bool:
	if not can_advance():
		return false
	if phase == Phase.END:
		_finish_turn()
	else:
		_go_to(phase + 1)
	return true


# Jumps to END and starts the next player's turn
func end_turn() -> void:
	if not game.is_started or game.is_over or phase in [Phase.NONE, Phase.MAINTENANCE, Phase.DRAW]:
		return
	if phase in COMBAT_HOOKS:
		_call_combat("cancel_combat")
	if phase != Phase.END:
		_go_to(Phase.END)
	# With END waiting for the player, _go_to() left us in END
	if phase == Phase.END and game.is_started:
		_finish_turn()


static func phase_name(p: int) -> String:
	return PHASE_NAMES.get(p, "?")


# --- internals ------------------------------------------------------------------

func _go_to(next_phase: int) -> void:
	game.phase_ended.emit()
	_enter(next_phase)


func _enter(p: int) -> void:
	phase = p
	var details := {
		"player_id": game.active_id,
		"phase": p,
		"phase_name": phase_name(p),
	}
	game.phase_begins.emit(game.active_id, p)
	# Card scripts. The trigger card is the game node, not a card.
	cfc.signal_propagator._on_signal_received(game, "phase_begins", details)
	# A listener may have moved the turn on already
	if phase != p:
		return
	match p:
		Phase.MAINTENANCE:
			_maintenance()
			_go_to(Phase.DRAW)
		Phase.DRAW:
			_draw()
			_go_to(Phase.ENERGY)
		Phase.ENERGY, Phase.MAIN:
			pass
		Phase.COMBAT_DECLARE, Phase.COMBAT_INTERCEPT, Phase.COMBAT_RESOLVE:
			# Must stay the last statement: the combat object may advance synchronously
			if not _call_combat(COMBAT_HOOKS[p]):
				_go_to(p + 1)
		Phase.END:
			game.end_phase_begins.emit(game.active_id)
			game.end_of_turn_expiry.emit(game.active_id)
			if not end_phase_waits_for_player:
				_finish_turn()


# Calls a method of the combat object. Returns false if there is no such object or method.
func _call_combat(method: String) -> bool:
	var combat = game.combat
	if combat == null or not is_instance_valid(combat) or not combat.has_method(method):
		return false
	combat.call(method)
	return true


func _finish_turn() -> void:
	game.phase_ended.emit()
	var finished := game.active_id
	phase = Phase.NONE
	game.turn_ended.emit(finished)
	start_turn()


# Step 2. D2: energy, relics and creatures untap, occupied cards return to the creature zone
# and every creature goes back to the strike position (rotation 0).
func _maintenance() -> void:
	var pid := game.active_id
	# Before anything untaps, so the stats layer can reset the current stats (D7)
	game.maintenance_started.emit(pid)
	var p := game.player(pid)
	for zone in ["energy", "relics", "creatures"]:
		for card in p.cards_in_grid(zone):
			card.set_card_rotation(0)
	# The framework's move path frees the occupied slot and takes the creature slot
	var creatures := p.grid("creatures")
	for card in p.cards_in_grid("occupied"):
		card.set_card_rotation(0)
		var slot := creatures.find_available_slot()
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
		# else: the creature zone is full (creatures played while this one was occupied);
		# the card stays in the occupied zone, untapped, and returns at a later maintenance
	game.mana_changed.emit(pid)
	# Keywords' on_maintenance hooks run now, everything is untapped and reset
	game.maintenance_finished.emit(pid)


# Step 3. D1: every turn draws, unless FateGame.first_player_skips_first_draw is set
func _draw() -> void:
	var pid := game.active_id
	if game.turn_number == 1 and pid == 1 and game.first_player_skips_first_draw:
		return
	# An empty deck loses the game (FateLibrary.draw)
	game.library.draw(pid)
