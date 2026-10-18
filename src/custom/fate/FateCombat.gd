# The combat manager: declare attackers, intercept, resolve. Assigned to `game.combat`.
# Rules: docs/FATE_RULES_SPEC.md, Section 3. Design document: Section 8 (SYS-COMBAT).
#
# The turn machine (FateTurn) calls begin_declaration(), begin_intercept(), begin_resolution(),
# next_requested() and cancel_combat(); this object calls game.advance_phase() when a step is done.
# Everything the UI does goes through the same public methods, so combat can be driven without a
# screen (tests, AI, effects).
#
#   DECLARE    declare_attack() / cancel_attack() ... confirm_attackers()
#              -> keyword hook on_attack_declared for each attack
#              -> reaction window "declare_end" -> INTERCEPT
#   INTERCEPT  declare_block() / cancel_block() ... confirm_blocks()
#              -> keyword hooks on_blocked / on_blocking
#              -> reaction window "intercept_end" -> RESOLVE
#   RESOLVE    the attacks resolve one at a time in declaration order (resolve_delay between them),
#              then the turn moves on to END. Skipped steps (nobody attacked) are passed at once.
#
# Calling game.advance_phase() directly in a combat phase also works: the steps that were not
# confirmed are confirmed implicitly (without a reaction window).
#
# Damage: see resolve_attack(). Destruction goes through FateEffects.destroy with cause "combat".
#
# Reaction windows: reaction_window_requested(window) fires with a FateCombat.ReactionWindow at
# the end of the declare step and at the end of the intercept step. By default combat continues
# at once. A handler that needs time (a player choosing a reaction spell) calls window.hold() while
# the signal is emitted, and window.release(token) when it is done; combat waits in between.
class_name FateCombat
extends RefCounted

enum Step { IDLE, DECLARE, INTERCEPT, RESOLVE }

# The reaction windows (ReactionWindow.step)
const WINDOW_DECLARE_END := "declare_end"
const WINDOW_INTERCEPT_END := "intercept_end"
# How many log lines are kept
const LOG_SIZE := 12
# Life an unblocked attack takes from a player, whatever its Strike (an attacker with 0 Strike deals none)
const PLAYER_HIT_DAMAGE := 1
# Life a player loses for each of their creatures destroyed by combat damage (not by effects)
const CREATURE_LOSS_DAMAGE := 1

# The step changed (also back to IDLE when combat ends)
signal step_changed(step: int)
# An attacker was picked (it can still be cancelled until the attackers are confirmed)
signal attack_declared(attack: FateAttack)
signal attack_cancelled(attack: FateAttack)
# The declare step ended: the attacks are locked in
signal attackers_confirmed
signal blocker_declared(attack: FateAttack, blocker: Card)
signal blocker_cancelled(attack: FateAttack, blocker: Card)
signal blocks_confirmed
signal attack_negated(attack: FateAttack)
signal attack_removed(attack: FateAttack)
# An attack was resolved. `result` is described in resolve_attack()
signal attack_resolved(attack: FateAttack, result: Dictionary)
# All attacks resolved; the turn is about to move on
signal combat_finished
# The turn ended in the middle of combat
signal combat_cancelled
signal reaction_window_requested(window: ReactionWindow)
# One line of the combat log, also kept in `log_lines`
signal log_entry(text: String)


# A pause point of the combat flow, see the header comment.
class ReactionWindow:
	extends RefCounted
	signal closed
	# FateCombat.WINDOW_DECLARE_END or WINDOW_INTERCEPT_END
	var step := ""
	# The player who gets to react: the defending player
	var player_id := 0
	var is_open := true
	var _holds := {}
	var _next_token := 1

	# Makes combat wait. Returns a token for release(). Call it while the signal is emitted.
	func hold() -> int:
		var token := _next_token
		_next_token += 1
		_holds[token] = true
		return token

	# The handler is done. Combat continues when no hold is left.
	func release(token: int) -> void:
		_holds.erase(token)
		if _holds.is_empty():
			close()

	# Lets combat continue regardless of holds (the "Next phase" button does this)
	func close() -> void:
		if is_open:
			is_open = false
			closed.emit()

	func is_held() -> bool:
		return is_open and not _holds.is_empty()


var game: FateGame
var step: int = Step.IDLE
# The attacks of the current (or last) combat phase in declaration order
var attacks: Array = []
# Seconds to wait after each resolved attack. 0 resolves everything at once, without waiting
# (what tests want). The board sets it for players.
var resolve_delay := 0.0
# true: begin_resolution() resolves all attacks by itself. false: call resolve_next() yourself and
# finish_resolution() after the last one.
var auto_resolve := true
# Why the last declare_attack() / declare_block() was refused (for the UI)
var last_error := ""
var log_lines: Array = []
# The reaction window that is open now, or null
var current_window: ReactionWindow = null

var _declare_confirmed := false
var _blocks_confirmed := false
# Counts combats; a pending coroutine that finds a different number stops (the turn moved on)
var _epoch := 0
var _fast_forward := false
signal _pause_over


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.creature_destroyed.connect(_on_creature_destroyed)


# --- the turn machine's interface (see FateTurn.gd) --------------------------------------------------

func begin_declaration() -> void:
	_epoch += 1
	attacks.clear()
	_declare_confirmed = false
	_blocks_confirmed = false
	_fast_forward = false
	last_error = ""
	_set_step(Step.DECLARE)


func begin_intercept() -> void:
	_set_step(Step.INTERCEPT)
	# Somebody advanced the phase without confirming the attackers
	if not _declare_confirmed:
		_confirm_declaration()
	_blocks_confirmed = false
	if game.is_over:
		return
	if not _has_live_attacks():
		# Nothing to intercept
		game.advance_phase()


func begin_resolution() -> void:
	_set_step(Step.RESOLVE)
	if not _declare_confirmed:
		_confirm_declaration()
	if not _blocks_confirmed:
		_confirm_blocks()
	if auto_resolve:
		_run_resolution()


# The "Next phase" button: confirm the current step, close a reaction window, or skip the pauses
# between the attacks of the resolve step.
func next_requested() -> void:
	if current_window != null and current_window.is_open:
		current_window.close()
		return
	match step:
		Step.DECLARE:
			confirm_attackers()
		Step.INTERCEPT:
			confirm_blocks()
		Step.RESOLVE:
			_fast_forward = true
			_pause_over.emit()
			if not auto_resolve:
				while resolve_next() != null:
					pass
				finish_resolution()


# The turn ended (game.end_turn()) in the middle of combat: nothing more happens
func cancel_combat() -> void:
	if step == Step.IDLE:
		return
	_epoch += 1
	if current_window != null:
		current_window.close()
		current_window = null
	_set_step(Step.IDLE)
	combat_cancelled.emit()


# --- queries -----------------------------------------------------------------------------------------------

# The player who defends: the one whose turn it is not
func defending_player() -> int:
	return FateZones.opponent_of(game.active_id)


# The attack this creature is the attacker of, or null
func attack_of(attacker: Card) -> FateAttack:
	for attack in attacks:
		if attack.attacker == attacker:
			return attack
	return null


# The attack this creature is blocking, or null
func block_of(blocker: Card) -> FateAttack:
	for attack in attacks:
		if blocker in attack.blockers:
			return attack
	return null


# Creatures of the active player that may still be declared as attackers
func eligible_attackers() -> Array:
	var found := []
	for card in game.creatures_in_play(game.active_id):
		if attack_problem(card) == "":
			found.append(card)
	return found


# Creatures of the defending player that could block `attack` (any attack if null)
func eligible_blockers(attack: FateAttack = null) -> Array:
	var found := []
	for card in game.creatures_in_play(defending_player()):
		if _blocker_problem(card, attack) == "":
			found.append(card)
	# Relics that may guard like a creature (Spiked Barricade, can_block_as_relic)
	for card in game.player(defending_player()).cards_in_grid("relics"):
		if _blocker_problem(card, attack) == "":
			found.append(card)
	return found


# The perpetual spells (field / world zone) of the opponents that this creature may attack (a keyword says
# so: can_attack_card, Zelith). Empty for creatures that cannot.
func attackable_spells(attacker: Card) -> Array:
	var found := []
	if not is_instance_valid(attacker):
		return found
	var candidates: Array = []
	for pid in game.players:
		if pid != attacker.controller_id:
			candidates.append_array(game.player(pid).cards_in_grid("field"))
	var world: Card = game.equip.world_spell() if game.equip != null else null
	if world != null:
		candidates.append(world)
	for spell in candidates:
		if attack_problem(attacker, spell) == "":
			found.append(spell)
	return found


# Why this creature cannot attack (the target too, if one is given): "" if it can.
# `target` is a creature Card, a FatePlayer or a player id.
func attack_problem(attacker: Card, target = null) -> String:
	if step != Step.DECLARE:
		return "It is not the declare step"
	if game.is_over:
		return "The game is over"
	if not FateZones.is_creature_in_play(attacker):
		return "Not a creature in play"
	if attacker.controller_id != game.active_id:
		return "It is not your creature"
	if FateZones.zone_of(attacker) != "creatures":
		return "An occupied creature cannot attack"
	if attacker.card_rotation != 0:
		return "Only a creature in the strike position can attack"
	if attack_of(attacker) != null:
		return "It already attacks"
	if not game.keywords.can_attack(attacker):
		return "It cannot attack"
	if target == null:
		return ""
	if target is Card:
		if is_perpetual_spell(target) or is_relic_on_table(target):
			if target.controller_id == attacker.controller_id:
				return "That is your own card"
			if not game.keywords.can_attack_card(attacker, target):
				return "It cannot attack that"
		elif not FateZones.is_creature_in_play(target):
			return "The target is not a creature in play"
		elif target.controller_id == attacker.controller_id:
			return "That is your own creature"
		if not game.keywords.can_be_attacked(target, attacker):
			return "That creature cannot be attacked" if FateZones.is_creature_in_play(target) \
					else "That card cannot be attacked"
	else:
		var player_id: int = target.id if target is FatePlayer else int(target)
		if player_id == attacker.controller_id or not game.players.has(player_id):
			return "That is not an opposing player"
	return ""


# Is this card a perpetual spell (a field or world spell) on the table? A keyword may let a creature attack it.
# Is this card a relic on the table? A keyword may let a creature attack it (Battering Ram)
func is_relic_on_table(card: Card) -> bool:
	return is_instance_valid(card) and card.properties.get("Type") == "Relic" \
			and FateZones.zone_of(card) == "relics"


func is_perpetual_spell(card: Card) -> bool:
	return is_instance_valid(card) and card.properties.get("Type") == "Spell" \
			and FateZones.zone_of(card) in ["field", "world"]


# Why this creature cannot block this attack: "" if it can
func block_problem(blocker: Card, attack: FateAttack) -> String:
	if step != Step.INTERCEPT:
		return "It is not the intercept step"
	if game.is_over:
		return "The game is over"
	if attack == null or not attack in attacks or attack.removed or attack.resolved:
		return "There is no such attack"
	if attack.negated:
		return "That attack was negated"
	return _blocker_problem(blocker, attack)


# --- declare step ----------------------------------------------------------------------------------------------

# Picks an attacker and its target (a creature Card, a FatePlayer or a player id). Returns false
# (see last_error) if the rules do not allow it.
func declare_attack(attacker: Card, target) -> bool:
	last_error = attack_problem(attacker, target)
	if last_error != "":
		return false
	var attack := FateAttack.new(attacker, target, attacks.size())
	attacks.append(attack)
	attack_declared.emit(attack)
	return true


# Takes an attacker out again, before the attackers are confirmed
func cancel_attack(attacker: Card) -> bool:
	if step != Step.DECLARE or _declare_confirmed:
		return false
	var attack := attack_of(attacker)
	if attack == null:
		return false
	attacks.erase(attack)
	for i in attacks.size():
		attacks[i].order = i
	attack_cancelled.emit(attack)
	return true


# Ends the declare step: the attacks are locked in, keywords react, the reaction window opens and
# the turn moves on to the intercept step. May take time (it waits for a held reaction window), so
# `await` it if you need to know when it is done.
func confirm_attackers() -> void:
	if step != Step.DECLARE or _declare_confirmed:
		return
	var epoch := _epoch
	_confirm_declaration()
	await _open_window(WINDOW_DECLARE_END)
	if epoch != _epoch or game.is_over or step != Step.DECLARE:
		return
	game.advance_phase()


# --- intercept step ---------------------------------------------------------------------------------------------------

# Assigns a blocker to an attack. One blocker blocks one attack, several may block the same
# attack. Returns false (see last_error) if the rules do not allow it.
func declare_block(blocker: Card, attack: FateAttack) -> bool:
	last_error = block_problem(blocker, attack)
	if last_error != "":
		return false
	attack.blockers.append(blocker)
	attack.was_blocked = true
	blocker_declared.emit(attack, blocker)
	return true


# Takes a blocker off its attack, before the blocks are confirmed
func cancel_block(blocker: Card) -> bool:
	if step != Step.INTERCEPT or _blocks_confirmed:
		return false
	var attack := block_of(blocker)
	if attack == null:
		return false
	attack.blockers.erase(blocker)
	attack.was_blocked = not attack.blockers.is_empty()
	blocker_cancelled.emit(attack, blocker)
	return true


# Ends the intercept step: keywords react to the blocks, the reaction window opens and the turn
# moves on to the resolve step (which resolves the attacks). Like confirm_attackers(), awaitable.
func confirm_blocks() -> void:
	if step != Step.INTERCEPT or _blocks_confirmed:
		return
	var epoch := _epoch
	_confirm_blocks()
	await _open_window(WINDOW_INTERCEPT_END)
	if epoch != _epoch or game.is_over or step != Step.INTERCEPT:
		return
	game.advance_phase()


# Sets the damage order of the blockers of an attack (the attacker spends its Strike on them in
# this order). `ordered` must hold exactly the blockers of the attack. Allowed until the attack
# resolves.
func order_blockers(attack: FateAttack, ordered: Array) -> bool:
	if attack.resolved or ordered.size() != attack.blockers.size():
		return false
	for blocker in ordered:
		if not blocker in attack.blockers:
			return false
	attack.blockers = ordered.duplicate()
	return true


# --- effects on attacks ------------------------------------------------------------------------------------------------

# The attack stays but deals no damage when its turn comes
func negate_attack(attack: FateAttack) -> bool:
	if attack.resolved or attack.negated or attack.removed:
		return false
	attack.negated = true
	attack_negated.emit(attack)
	_log("%s is negated" % attack.describe())
	return true


# Takes a creature out of combat: an attacker's attack is removed (it resolves as nothing), a
# blocker stops blocking. Works in any combat step; the creature stays in play.
func remove_from_combat(card: Card) -> bool:
	var changed := false
	for attack in attacks:
		if attack.resolved:
			continue
		if attack.attacker == card and not attack.removed:
			attack.removed = true
			attack.blockers.clear()
			attack_removed.emit(attack)
			_log("%s is removed from combat" % card.canonical_name)
			changed = true
		elif card in attack.blockers:
			attack.blockers.erase(card)
			blocker_cancelled.emit(attack, card)
			changed = true
	return changed


# --- resolve step -------------------------------------------------------------------------------------------------------------

# The first attack that has not been resolved yet, or null
func next_unresolved() -> FateAttack:
	for attack in attacks:
		if not attack.resolved:
			return attack
	return null


# Resolves the next attack in declaration order. Returns it (its `result` is filled in), or null
# if all are resolved.
func resolve_next() -> FateAttack:
	var attack := next_unresolved()
	if attack == null:
		return null
	resolve_attack(attack)
	return attack


# After the last attack: the turn moves on to END. begin_resolution() calls this by itself when
# `auto_resolve` is on.
func finish_resolution() -> void:
	if step != Step.RESOLVE:
		return
	_set_step(Step.IDLE)
	combat_finished.emit()
	game.advance_phase()


func _run_resolution() -> void:
	var epoch := _epoch
	while true:
		if epoch != _epoch or game.is_over:
			return
		var attack := resolve_next()
		if attack == null:
			break
		if resolve_delay > 0.0 and not _fast_forward:
			await _pause()
	if epoch == _epoch and not game.is_over:
		finish_resolution()


# Waits resolve_delay seconds between two attacks, or until the "Next phase" button skips it
func _pause() -> void:
	game.get_tree().create_timer(resolve_delay).timeout.connect(_pause_over.emit)
	await _pause_over


# Resolves one attack with the damage algorithm of the spec (Section 3), fills in `attack.result`
# and emits attack_resolved. The result dictionary has:
#   kind              "player" | "creature" | "spell" | "blocked" | "negated" | "removed" | "attacker_gone"
#                     | "target_gone" | "blockers_gone"
#   attacker, target (a Card or null), target_player (0 for a creature)
#   blockers          the blockers that took part, in damage order
#   damage_to_target  damage dealt to the target creature / the blockers (sum)
#   damage_to_attacker  damage the attacker took
#   life_lost         life the defending player lost
#   life_left         their life afterwards (only set for "player")
#   destroyed         the cards destroyed during this resolution
#
# Damage, for an attacker with Strike A and one defender with the stat D it uses (a blocker or a
# guarding / occupied target: Guard; an upright target: Strike): both lose min(A, D); the one whose
# used stat reaches 0 is destroyed. With several blockers the attacker spends its Strike on them in
# order, each absorbing at most its own stat, and loses the sum of their stats (at most A).
# All damage of the attack is dealt first, destruction follows (so it is simultaneous).
func resolve_attack(attack: FateAttack) -> Dictionary:
	var attacker := attack.attacker
	var result := {
		"kind": "", "attacker": attacker, "target": attack.target_card,
		"target_player": attack.target_player, "blockers": [], "damage_to_target": 0,
		"damage_to_attacker": 0, "life_lost": 0, "life_left": 0, "destroyed": [],
	}
	var destroyed: Array = result.destroyed
	var track := func(card, _cause): destroyed.append(card)
	game.creature_destroyed.connect(track)
	if attack.removed:
		result.kind = "removed"
	elif attack.negated:
		result.kind = "negated"
	elif not FateZones.is_creature_in_play(attacker):
		result.kind = "attacker_gone"
	else:
		# Doctrines (Vanquish Thine Foes) act on the attack before the damage
		if game.doctrines != null:
			game.doctrines.attack_about_to_resolve(attack)
		game.keywords.before_combat_damage(attack)
		if not FateZones.is_creature_in_play(attacker):
			result.kind = "attacker_gone"
		else:
			_deal_combat_damage(attack, result)
	game.creature_destroyed.disconnect(track)
	attack.resolved = true
	attack.result = result
	_log_result(attack, result)
	attack_resolved.emit(attack, result)
	return result


func _deal_combat_damage(attack: FateAttack, result: Dictionary) -> void:
	var attacker := attack.attacker
	var effects := game.effects
	var stats := game.stats
	var cause := FateEffects.CAUSE_COMBAT
	# [card, stat, source] of everything damaged, checked for death after all damage is dealt
	var damaged: Array = []
	stats.begin_batch()
	if attack.was_blocked:
		var blockers: Array = attack.blockers.filter(func(b): return FateZones.is_creature_in_play(b))
		result.blockers = blockers
		if blockers.is_empty():
			# Everybody who blocked is gone: the attack was blocked, so it does not reach its target
			result.kind = "blockers_gone"
		else:
			result.kind = "blocked"
			var strike := stats.current(attacker, "Strike")
			var guards: Array = blockers.map(func(b): return stats.current(b, "Guard"))
			var remaining := strike
			for i in blockers.size():
				var spent := mini(remaining, guards[i])
				remaining -= spent
				result.damage_to_target += effects.deal_damage(blockers[i], spent, attacker, cause, "Guard", true)
				damaged.append([blockers[i], "Guard", attacker])
			# The attacker loses the sum of the blockers' stats, at most its whole Strike
			var to_lose := strike
			for i in blockers.size():
				var part := mini(to_lose, guards[i])
				to_lose -= part
				result.damage_to_attacker += effects.deal_damage(attacker, part, blockers[i], cause, "Strike", true)
			damaged.push_front([attacker, "Strike", blockers[0]])
	elif attack.targets_player():
		result.kind = "player"
		var damage := mini(PLAYER_HIT_DAMAGE, stats.current(attacker, "Strike"))
		var defender := game.player(attack.target_player)
		result.life_lost = effects.deal_damage(defender, damage, attacker, cause)
		# Read now: a lethal hit ends the game, and the players may be gone when the result is logged
		result.life_left = defender.life
	elif not is_instance_valid(attack.target_card):
		# The target was freed since the declaration (its typed-Card checks below would error on it)
		result.kind = "target_gone"
	elif is_perpetual_spell(attack.target_card) or is_relic_on_table(attack.target_card):
		# An attacked perpetual spell or relic that was not intercepted is destroyed (Zelith, Battering Ram)
		result.kind = "spell"
		effects.destroy(attack.target_card, attacker, cause)
	elif not FateZones.is_creature_in_play(attack.target_card):
		result.kind = "target_gone"
	else:
		result.kind = "creature"
		var target := attack.target_card
		var target_stat := effects.used_stat(target)
		var a := stats.current(attacker, "Strike")
		var d := stats.current(target, target_stat)
		var dealt := mini(a, d)
		result.damage_to_target = effects.deal_damage(target, dealt, attacker, cause, target_stat, true)
		result.damage_to_attacker = effects.deal_damage(attacker, dealt, target, cause, "Strike", true)
		damaged.append([attacker, "Strike", target])
		damaged.append([target, target_stat, attacker])
	# Used stat at 0 -> destroyed, all at once
	for entry in damaged:
		effects.destroy_if_depleted(entry[0], entry[1], entry[2], cause)
	stats.end_batch()


# --- internals ------------------------------------------------------------------------------------------------------------------

func _set_step(new_step: int) -> void:
	step = new_step
	step_changed.emit(new_step)


func _has_live_attacks() -> bool:
	for attack in attacks:
		if not attack.removed and not attack.resolved:
			return true
	return false


# The attackers are final: tell the keywords, in declaration order
func _confirm_declaration() -> void:
	_declare_confirmed = true
	attackers_confirmed.emit()
	for attack in attacks.duplicate():
		if attack.removed or not FateZones.is_creature_in_play(attack.attacker):
			continue
		_log("%s attacks" % attack.describe())
		game.keywords.attack_declared(attack)


func _confirm_blocks() -> void:
	_blocks_confirmed = true
	for attack in attacks.duplicate():
		if attack.removed or attack.blockers.is_empty():
			continue
		var names := ", ".join(attack.blockers.map(func(b): return b.canonical_name))
		_log("%s is blocked by %s" % [attack.attacker.canonical_name, names])
		game.keywords.blocked(attack, attack.blockers.duplicate())
		for blocker in attack.blockers.duplicate():
			game.keywords.blocking(blocker, attack)
	blocks_confirmed.emit()


# The shared part of block_problem(); `attack` may be null (is this creature able to block at all)
func _blocker_problem(blocker: Card, attack: FateAttack) -> String:
	if FateZones.zone_of(blocker) == "relics" and blocker.properties.get("Type") == "Relic":
		return _relic_blocker_problem(blocker, attack)
	if not FateZones.is_creature_in_play(blocker):
		return "Not a creature in play"
	if blocker.controller_id != defending_player():
		return "It is not the defending player's creature"
	var zone := FateZones.zone_of(blocker)
	var guarding: bool = zone == "creatures" and (blocker.card_rotation == 90 \
			or (game.doctrines != null and game.doctrines.guards_upright(blocker)))
	if not guarding and zone != "occupied":
		return "Only guarding or occupied creatures can intercept"
	if attack != null and blocker in attack.blockers:
		return "It already blocks that attack"
	if block_of(blocker) != null and block_of(blocker) != attack:
		return "It already blocks another attack"
	if attack == null:
		return ""
	if not game.keywords.can_block(blocker, attack):
		return "It cannot block"
	if not game.keywords.can_be_blocked_by(attack.attacker, blocker, attack):
		return "That attacker cannot be blocked by it"
	if not attack.restrictions_allow(blocker):
		return "That attack cannot be blocked by it"
	return ""


# A relic that guards like a creature (can_block_as_relic): no stance, no Guard, only the keyword says yes
func _relic_blocker_problem(relic: Card, attack: FateAttack) -> String:
	if relic.controller_id != defending_player():
		return "It is not the defending player's relic"
	if attack != null and relic in attack.blockers:
		return "It already blocks that attack"
	if block_of(relic) != null and block_of(relic) != attack:
		return "It already blocks another attack"
	if not game.keywords.can_block_as_relic(relic, attack):
		return "Only a creature in the guard position can intercept"
	if attack == null:
		return ""
	if not game.keywords.can_be_blocked_by(attack.attacker, relic, attack):
		return "That attacker cannot be blocked by it"
	if not attack.restrictions_allow(relic):
		return "That attack cannot be blocked by it"
	return ""


# Opens a reaction window and waits while a handler holds it
func _open_window(window_step: String) -> void:
	var window := ReactionWindow.new()
	window.step = window_step
	window.player_id = defending_player()
	current_window = window
	reaction_window_requested.emit(window)
	if window.is_held():
		await window.closed
	if current_window == window:
		current_window = null


func _on_creature_destroyed(card: Card, _cause: String) -> void:
	# A creature that dies leaves combat: its attack is removed, it stops blocking
	for attack in attacks:
		if attack.resolved:
			continue
		if attack.attacker == card and not attack.removed:
			attack.removed = true
			attack.blockers.clear()
			attack_removed.emit(attack)
		elif card in attack.blockers:
			attack.blockers.erase(card)
			blocker_cancelled.emit(attack, card)


func _log(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > LOG_SIZE:
		log_lines.pop_front()
	log_entry.emit(text)


func _log_result(attack: FateAttack, result: Dictionary) -> void:
	var attacker_name: String = attack.attacker.canonical_name if is_instance_valid(attack.attacker) else "?"
	match result.kind:
		"player":
			_log("%s hits Player %d for %d (life %d)" % [attacker_name, attack.target_player,
					result.life_lost, result.life_left])
		"spell":
			_log("%s destroys %s" % [attacker_name, attack.target_card.canonical_name])
		"creature":
			_log("%s fights %s: %d each" % [attacker_name, attack.target_card.canonical_name,
					result.damage_to_target])
		"blocked":
			_log("%s: %d dealt, %d taken" % [attacker_name, result.damage_to_target,
					result.damage_to_attacker])
		"negated":
			_log("%s: negated, no damage" % attacker_name)
		"removed", "attacker_gone":
			_log("%s: removed from combat" % attacker_name)
		"target_gone":
			_log("%s: its target is gone" % attacker_name)
		"blockers_gone":
			_log("%s: blocked, but the blockers are gone" % attacker_name)
	for card in result.destroyed:
		_log("%s is destroyed" % card.canonical_name)
