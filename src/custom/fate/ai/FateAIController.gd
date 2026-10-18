# The AI player of one seat. Add one per seat with `game.set_ai(seat, true)` (or `--ai=1`, `--ai=2`,
# `--ai=both` on the command line, see FateBoard); a seat without one is played by a person.
#
# The controller is the only part of the AI that touches the game. It listens to the game's signals
# and drives the same public API a person's clicks end up in (docs/FATE_RULES_SPEC.md; tests drive the
# game the same way):
#
#   my turn starts (ENERGY)  -> energy or draw (FateAIEnergy), then the main phase (FateAIMain), then the
#                               declare step: declare the planned attacks and confirm
#   my creatures attacked    -> the intercept step: choose and confirm blocks (FateAICombat.plan_blocks)
#   a reaction window for me -> cast reactions worth casting (FateAIReactions)
#   blocks confirmed         -> order the blockers of my attacks (the attacker's choice)
#
# What it decides with: a snapshot of the table as plain data (FateAISnapshot), a simulator of the
# combat rules (FateAISim), evaluation numbers (FateAIEval) and the profile of the seat (FateAIProfile).
# It only looks at what the player may see: the opponent's hand is not read unless profile.cheat is set.
#
# Everything is deferred (`call_deferred`) out of the signal handlers, because the game runs its
# phases synchronously inside them. Pauses between actions (profile.pace) are for people watching;
# 0 runs as fast as the engine allows. Nothing here waits for a human: if the other seat is a
# person, the game waits for them in the usual places.
#
# Debugging: `log_lines` keeps what the AI decided and why, `problems` what it tried that the
# engine refused (should stay empty), `noted` is emitted for each line.
#
# No class_name (see FateAIEval.gd).
extends Node

const Profile := preload("res://src/custom/fate/ai/FateAIProfile.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Energy := preload("res://src/custom/fate/ai/FateAIEnergy.gd")
const MainPhase := preload("res://src/custom/fate/ai/FateAIMain.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")
const Reactions := preload("res://src/custom/fate/ai/FateAIReactions.gd")
const AIChoices := preload("res://src/custom/fate/ai/FateAIChoices.gd")

signal noted(text: String)
# The AI is done with its turn script (the turn may still be running: combat resolves by itself)
signal turn_finished(turn_number: int)

const LOG_SIZE := 400

var game: FateGame
var seat := 0
var profile
var enabled := true
# The attacks planned in the main phase: Array of sim attacks, see FateAISim. Read by _declare_attacks()
var attack_plan: Array = []
var log_lines: Array[String] = []
var problems: Array[String] = []

var _token := 0
var _blocked_turn := -1
# The turn whose script already ran (the start of a turn reaches the controller by two signals)
var _scripted_turn := -1


func setup(owner_game: FateGame, player_id: int, level: int = Profile.Level.NORMAL) -> void:
	game = owner_game
	seat = player_id
	profile = Profile.new()
	set_level(level)
	game.phase_begins.connect(_on_phase_begins)
	game.combat.step_changed.connect(_on_step_changed)
	game.combat.reaction_window_requested.connect(_on_reaction_window)
	game.combat.blocks_confirmed.connect(_on_blocks_confirmed)
	game.game_started.connect(resume)
	game.board_state_loaded.connect(func(_n): resume())
	game.game_ended.connect(func(_w): _token += 1)
	_install_choosers()


# The seat answers the questions card effects ask (targets, picks, "you may") itself: the entries for the
# seat win over a general chooser such as the one of the human choice UI (FateChoices)
func _install_choosers() -> void:
	# KwSavage asks for the target of its damage through a static callable (board-state loads clear it)
	var savage = load("res://src/custom/fate/keywords/KwSavage.gd")
	savage.target_chooser = AIChoices.savage_target.bind(game)
	game.choices.choosers[seat] = func(request): return AIChoices.choose(game, seat, profile, request)
	game.choices.confirmers[seat] = func(request): return AIChoices.confirm(game, seat, profile, request)


func _remove_choosers() -> void:
	if game != null and is_instance_valid(game):
		game.choices.choosers.erase(seat)
		game.choices.confirmers.erase(seat)
		# The Savage hook stays while another AI seat needs it
		for other in game.ai_controllers.values():
			if other != self and is_instance_valid(other) and other.enabled:
				return
	var savage = load("res://src/custom/fate/keywords/KwSavage.gd")
	savage.target_chooser = Callable()


func _exit_tree() -> void:
	_remove_choosers()


# Changes the strength (FateAIProfile.Level) and the personality that goes with the deck
func set_level(level: int) -> void:
	# Seeded from the game's seed: the same game plays out the same way
	profile.configure(game.player(seat).domains, level, hash(str(cfc.game_rng_seed) + str(seat)))
	if cfc.is_testing:
		profile.pace = 0.0


# Switches the AI off or on for this seat
func set_enabled(on: bool) -> void:
	enabled = on
	_token += 1
	_scripted_turn = -1
	if on:
		_install_choosers()
	else:
		_remove_choosers()
	if on:
		resume()


# Picks up the game wherever it is: the start of my turn, the middle of it, or an intercept step
# where I defend. Used when the AI is switched on mid-game and after a board state was loaded.
func resume() -> void:
	if enabled and game != null and game.is_started and not game.is_over:
		call_deferred("_resume_deferred")


func _resume_deferred() -> void:
	if not enabled or game.is_over or not game.is_started:
		return
	_install_choosers()
	if game.active_id == seat and game.phase in [FateGame.Phase.ENERGY, FateGame.Phase.MAIN]:
		_run_turn(game.turn_number)
	elif game.combat.step == FateCombat.Step.INTERCEPT and game.combat.defending_player() == seat:
		_run_blocks()


# --- helpers the planners call -----------------------------------------------------------------------

func note(text: String) -> void:
	var line := "[P%d t%d] %s" % [seat, game.turn_number, text]
	log_lines.append(line)
	if log_lines.size() > LOG_SIZE:
		log_lines.pop_front()
	noted.emit(line)


func problem(text: String) -> void:
	problems.append("[P%d t%d] %s" % [seat, game.turn_number, text])
	note("PROBLEM: " + text)


# Waits between two visible actions
func pause(seconds := -1.0) -> void:
	var t: float = profile.pace if seconds < 0.0 else seconds
	if t <= 0.0:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(t).timeout


# Is the turn script with this token still the one that should run?
func alive(token: int) -> bool:
	return enabled and token == _token and is_instance_valid(game) and not game.is_over \
			and game.active_id == seat


func snapshot() -> Dictionary:
	return Snapshot.build(game, seat, profile.aggression, profile.cheat)


# --- my turn -------------------------------------------------------------------------------------------

func _on_phase_begins(player_id: int, phase: int) -> void:
	if enabled and player_id == seat and phase == FateGame.Phase.ENERGY and not game.is_over:
		call_deferred("_run_turn", game.turn_number)


func _run_turn(turn_number: int) -> void:
	if turn_number == _scripted_turn:
		return
	_scripted_turn = turn_number
	_token += 1
	var token := _token
	if not alive(token) or game.turn_number != turn_number:
		return
	attack_plan = []
	await pause()
	if not alive(token):
		return
	# Energy phase: the "land drop" decision
	if game.phase == FateGame.Phase.ENERGY:
		var choice := Energy.decide(game, snapshot(), profile)
		var done := false
		if choice.kind == "alternative":
			note("energy: %s" % choice.why)
			done = game.use_energy_alternative(choice.host)
		elif choice.kind == "doctrine":
			note("energy: %s" % choice.why)
			done = game.doctrines.take_opponent_card_as_energy(seat) != null
		elif choice.kind == "energy" and choice.card != null:
			note("energy: %s (%s)" % [choice.card.canonical_name, choice.why])
			done = game.play_as_energy(choice.card)
			if not done:
				problem("could not play %s as energy" % choice.card.canonical_name)
		if not done:
			note("draws an extra card (%s)" % choice.why)
			if not game.draw_extra_card():
				problem("could not draw an extra card")
		await pause()
		if not alive(token):
			return
	# Main phase
	if game.phase == FateGame.Phase.MAIN:
		await MainPhase.run(self, token)
		if not alive(token):
			return
		await pause()
		if not alive(token):
			return
		game.advance_phase()
	# Declare step
	if game.phase == FateGame.Phase.COMBAT_DECLARE and game.combat.step == FateCombat.Step.DECLARE:
		_declare_attacks()
		await pause()
		if not alive(token):
			return
		turn_finished.emit(game.turn_number)
		await game.combat.confirm_attackers()
		return
	_recover(token)
	turn_finished.emit(turn_number)


# The planned attacks, checked against the engine's rules one more time
func _declare_attacks() -> void:
	var combat: FateCombat = game.combat
	for a in attack_plan:
		var attacker = instance_from_id(a.uid)
		if attacker == null or not is_instance_valid(attacker):
			continue
		var target = a.target
		if a.kind == "unit":
			target = instance_from_id(a.target)
			if target == null or not is_instance_valid(target):
				continue
		var why := combat.attack_problem(attacker, target)
		if why != "":
			note("skips the attack of %s: %s" % [attacker.canonical_name, why])
			continue
		if combat.declare_attack(attacker, target):
			note("attacks: %s" % combat.attack_of(attacker).describe())
		else:
			problem("declare_attack refused: %s" % combat.last_error)


# The turn script ended in a phase it should not stop in: finish the turn the plain way
func _recover(token: int) -> void:
	if not alive(token):
		return
	problem("turn script ended in phase %s, finishing the turn" % FateTurn.phase_name(game.phase))
	if game.phase == FateGame.Phase.ENERGY:
		game.draw_extra_card()
	game.end_turn()


# --- defending -------------------------------------------------------------------------------------------

func _on_step_changed(step: int) -> void:
	if enabled and step == FateCombat.Step.INTERCEPT and game.combat.defending_player() == seat \
			and not game.is_over:
		call_deferred("_run_blocks")


func _run_blocks() -> void:
	var combat: FateCombat = game.combat
	if not enabled or combat.step != FateCombat.Step.INTERCEPT or combat.defending_player() != seat \
			or game.is_over or _blocked_turn == game.turn_number:
		return
	_blocked_turn = game.turn_number
	var turn_number := game.turn_number
	await pause()
	if not enabled or game.is_over or game.turn_number != turn_number \
			or combat.step != FateCombat.Step.INTERCEPT:
		return
	var plan := Combat.plan_blocks(game, snapshot(), profile)
	for i in plan.size():
		var attack: FateAttack = combat.attacks[i]
		for blocker in plan[i]:
			if combat.declare_block(blocker, attack):
				note("blocks %s with %s" % [attack.attacker.canonical_name, blocker.canonical_name])
			else:
				problem("declare_block refused: %s" % combat.last_error)
	await combat.confirm_blocks()


# --- reactions -------------------------------------------------------------------------------------------------

func _on_reaction_window(window) -> void:
	if not enabled or game.is_over or window.player_id != seat:
		return
	for spell in Reactions.respond(game, seat, window, profile):
		note("casts %s (%s)" % [spell, window.step])
	# FateReactions holds the window while a person might still cast something: the AI is done
	if window.is_held():
		window.close()


# The blocks are in: the attacker chooses the damage order of several blockers
func _on_blocks_confirmed() -> void:
	if enabled and game.active_id == seat and not game.is_over:
		Combat.order_my_blockers(game, snapshot())
