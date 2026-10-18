# A small, pure-data copy of the combat rules, so the AI can ask "what happens if" thousands of times
# without moving a single card. It mirrors FateCombat.resolve_attack (docs/FATE_RULES_SPEC.md
# Section 3) and the keyword hooks that change damage:
#
#   * an attacker uses its Strike; a blocker, or a guarding / occupied target, uses its Guard; an
#     upright target uses its Strike
#   * both sides lose min(A, D); the creature whose USED stat reaches 0 dies (a 0 stat dies even when
#     nothing was dealt); several blockers: the attacker spends its Strike on them in order
#   * a creature with Strike and Guard both 0 dies
#   * a creature that dies in combat costs its controller FateCombat.CREATURE_LOSS_DAMAGE (1) life
#   * Indomitable: combat damage never takes the used stat below 1, and it does not die in combat
#   * Savage X: when blocked, X damage to the blocking player (the engine default) before combat
#   * an unblocked attack on a player takes 1 life (FateCombat.PLAYER_HIT_DAMAGE) if its Strike is above 0
# Parity with the engine is checked by tests/integration/test_fate_ai_sim_parity.gd: change both or
# neither.
#
# Vocabulary (all dictionaries, see FateAISnapshot for units and the state):
#   attack  {"uid": attacker uid, "kind": "player" | "unit", "target": player id | unit uid,
#            "only": uid of the only creature allowed to block (-1 = no restriction),
#            "none": nobody may block, "removed": bool, "negated": bool,
#            "savage_done": the engine already dealt this attack's Savage damage}
#   blocks  {attack index: Array of blocker uids in damage order}
#   result  {"units": {uid: {"strike", "guard", "dead"}}, "life": {pid: int}}  what changed
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")


static func new_result(state: Dictionary) -> Dictionary:
	return {"units": {}, "life": state.life.duplicate()}


static func make_attack(attacker_uid: int, kind: String, target: int) -> Dictionary:
	return {"uid": attacker_uid, "kind": kind, "target": target, "only": -1, "none": false,
			"removed": false, "negated": false}


# The stat key a creature uses when it is attacked or damaged: strike when upright, else guard
static func used_key(u: Dictionary) -> String:
	return "strike" if u.pos == "strike" else "guard"


static func _o(res: Dictionary, u: Dictionary) -> Dictionary:
	var o = res.units.get(u.uid)
	if o == null:
		o = {"strike": u.strike, "guard": u.guard, "dead": false}
		res.units[u.uid] = o
	return o


static func is_alive(res: Dictionary, u: Dictionary) -> bool:
	var o = res.units.get(u.uid)
	return o == null or not o.dead


static func stat(res: Dictionary, u: Dictionary, key: String) -> int:
	var o = res.units.get(u.uid)
	return u[key] if o == null else o[key]


# Combat damage to a creature on a stat; returns what was really taken off
static func _hurt(res: Dictionary, u: Dictionary, key: String, amount: int, combat: bool) -> int:
	var o := _o(res, u)
	var dealt := amount
	if combat and u.kw.has("Indomitable"):
		dealt = mini(dealt, maxi(0, o[key] - 1))
	dealt = clampi(dealt, 0, o[key])
	o[key] -= dealt
	return dealt


# The death checks after damage: the used stat reached 0 (combat only; Indomitable holds), or both
# stats are 0 (any cause). Returns whether the creature died.
static func _settle(res: Dictionary, u: Dictionary, key: String, combat: bool) -> bool:
	var o := _o(res, u)
	if o.dead:
		return false
	if combat and o[key] <= 0 and not u.kw.has("Indomitable"):
		o.dead = true
		# A creature lost in combat costs its controller life (FateEffects.destroy, FateCombat.CREATURE_LOSS_DAMAGE);
		# creatures destroyed by effects (Savage, the both-stats-zero rule) do not
		res.life[u.ctrl] -= FateCombat.CREATURE_LOSS_DAMAGE
		return true
	if o.strike <= 0 and o.guard <= 0:
		o.dead = true
		return true
	return false


# --- running attacks ----------------------------------------------------------------------------

# Plays out the attacks in declaration order with the given blocks. Returns a result (nothing in
# `state` is changed).
static func run(state: Dictionary, attacks: Array, blocks: Dictionary) -> Dictionary:
	var res := new_result(state)
	# Savage fires when the blocks are confirmed, before any combat damage
	for i in attacks.size():
		var a: Dictionary = attacks[i]
		var blockers: Array = blocks.get(i, [])
		if blockers.is_empty() or a.removed or a.negated or a.get("savage_done", false):
			continue
		var attacker: Dictionary = state.units.get(a.uid, {})
		if attacker.is_empty() or not is_alive(res, attacker):
			continue
		var x: int = int(attacker.kw.get("Savage", 0))
		if x > 0:
			_savage(state, res, attacker, blockers, x)
	for i in attacks.size():
		var a: Dictionary = attacks[i]
		if a.removed:
			continue
		var attacker: Dictionary = state.units.get(a.uid, {})
		if attacker.is_empty() or not is_alive(res, attacker):
			continue
		_resolve(state, res, a, attacker, blocks.get(i, []))
	return res


# Savage: the engine's default target is the blocking player; the creatures of an AI seat
# (state.ai_seats, see FateAIChoices.savage_target) pick better: a creature of the blocker that the damage
# destroys and that is worth more than the life it would cost
static func _savage(state: Dictionary, res: Dictionary, attacker: Dictionary, blockers: Array, x: int) -> void:
	var first: Dictionary = state.units.get(blockers[0], {})
	if first.is_empty():
		return
	var pid: int = first.ctrl
	if attacker.ctrl in state.get("ai_seats", []) and res.life[pid] > x:
		var best: Dictionary = {}
		var best_value := 1.4 * float(x)
		for uid in state.units:
			var u: Dictionary = state.units[uid]
			if u.ctrl == pid and is_alive(res, u) and stat(res, u, used_key(u)) <= x:
				var v := Eval.unit_value(u)
				if v > best_value:
					best_value = v
					best = u
		if not best.is_empty():
			var o := _o(res, best)
			o[used_key(best)] = 0
			o.dead = true
			return
	res.life[pid] -= x


static func _resolve(state: Dictionary, res: Dictionary, a: Dictionary, attacker: Dictionary, blocker_uids: Array) -> void:
	if a.negated:
		return
	if not blocker_uids.is_empty():
		var blockers: Array = []
		for uid in blocker_uids:
			var b: Dictionary = state.units.get(uid, {})
			if not b.is_empty() and is_alive(res, b):
				blockers.append(b)
		if blockers.is_empty():
			# They were blocked, but everybody who blocked is gone: no damage reaches the target
			return
		_blocked(res, attacker, blockers)
		return
	if a.kind == "player":
		res.life[a.target] -= mini(FateCombat.PLAYER_HIT_DAMAGE, stat(res, attacker, "strike"))
		return
	var target: Dictionary = state.units.get(a.target, {})
	if target.is_empty() or not is_alive(res, target):
		return
	var key := used_key(target)
	var atk := stat(res, attacker, "strike")
	var dealt := mini(atk, stat(res, target, key))
	_hurt(res, target, key, dealt, true)
	_hurt(res, attacker, "strike", dealt, true)
	_settle(res, attacker, "strike", true)
	_settle(res, target, key, true)


static func _blocked(res: Dictionary, attacker: Dictionary, blockers: Array) -> void:
	var strike := stat(res, attacker, "strike")
	var guards: Array = blockers.map(func(b): return stat(res, b, "guard"))
	var remaining := strike
	for i in blockers.size():
		var spent := mini(remaining, guards[i])
		remaining -= spent
		_hurt(res, blockers[i], "guard", spent, true)
	var to_lose := strike
	for i in blockers.size():
		var part := mini(to_lose, guards[i])
		to_lose -= part
		_hurt(res, attacker, "strike", part, true)
	_settle(res, attacker, "strike", true)
	for b in blockers:
		_settle(res, b, "guard", true)


# --- who can block ------------------------------------------------------------------------------

# Can this creature (a unit of the defender) block this attack, by the rules the AI can see:
# guarding or occupied, able to block, the attacker blockable, the restrictions of the attack.
# The engine has the last word (FateCombat.block_problem); the AI asks it before declaring.
static func can_block(blocker: Dictionary, attacker: Dictionary, attack: Dictionary) -> bool:
	if blocker.pos == "strike" or blocker.kw.has("Cannot block") or attacker.kw.has("Unblockable"):
		return false
	if attack.none:
		return false
	if attack.only >= 0 and attack.only != blocker.uid:
		return false
	return true


# The creatures of player `pid` that could block this attack
static func blockers_for(state: Dictionary, pid: int, attack: Dictionary) -> Array:
	var found: Array = []
	var attacker: Dictionary = state.units.get(attack.uid, {})
	if attacker.is_empty():
		return found
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		if u.ctrl == pid and can_block(u, attacker, attack):
			found.append(u)
	return found


# --- the defender's best answer --------------------------------------------------------------------

# Chooses blocks for the defender `def` that give them the best score, assuming the attacker orders
# several blockers as well as it can. `allowed` (optional) maps an attack index to the uids that may
# really block it (what the engine says); without it can_block() decides. `fixed` blocks (index ->
# uids) are kept as they are. Greedy local search: for every attack, try no block, every single
# free blocker and (when one blocker cannot stop the attacker) every pair, keep what raises the
# score; two sweeps. Returns blocks.
static func best_blocks(state: Dictionary, attacks: Array, def: int, allowed = null, noise := 0.0,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var blocks := {}
	var options: Array = []
	for i in attacks.size():
		var a: Dictionary = attacks[i]
		var cands: Array = []
		if not (a.removed or a.negated):
			for u in blockers_for(state, def, a):
				if allowed == null or u.uid in allowed.get(i, []):
					cands.append(u.uid)
		options.append(cands)
	var best := _score(state, attacks, blocks, def, noise, rng)
	# Biggest attackers first
	var order: Array = range(attacks.size())
	order.sort_custom(func(x, y): return _strike_of(state, attacks[x]) > _strike_of(state, attacks[y]))
	for _sweep in range(2):
		var improved := false
		for i in order:
			if options[i].is_empty():
				continue
			var used := {}
			for j in blocks:
				if j != i:
					for uid in blocks[j]:
						used[uid] = true
			var free: Array = options[i].filter(func(uid): return not used.has(uid))
			var groups: Array = [[]]
			for uid in free:
				groups.append([uid])
			if free.size() >= 2 and not _single_stops(state, attacks[i], free):
				for x in free.size():
					for y in range(x + 1, free.size()):
						groups.append([free[x], free[y]])
			var current: Array = blocks.get(i, [])
			for g in groups:
				if g == current or (g.is_empty() and current.is_empty()):
					continue
				var trial := blocks.duplicate()
				if g.is_empty():
					trial.erase(i)
				else:
					trial[i] = g
				var s := _score(state, attacks, trial, def, noise, rng)
				if s > best + 0.001:
					best = s
					blocks = trial
					current = g
					improved = true
		if not improved:
			break
	return blocks


static func _strike_of(state: Dictionary, attack: Dictionary) -> int:
	var u: Dictionary = state.units.get(attack.uid, {})
	return 0 if u.is_empty() else u.strike


# Can one of these blockers kill the attacker on its own?
static func _single_stops(state: Dictionary, attack: Dictionary, free: Array) -> bool:
	var attacker: Dictionary = state.units.get(attack.uid, {})
	if attacker.is_empty():
		return true
	for uid in free:
		var b: Dictionary = state.units[uid]
		if b.guard >= attacker.strike:
			return true
	return false


# The score of a block assignment for `def`, with the attacker ordering multiple blockers its way
static func _score(state: Dictionary, attacks: Array, blocks: Dictionary, def: int, noise: float,
		rng: RandomNumberGenerator) -> float:
	var ordered := order_blocks(state, attacks, blocks)
	var s := Eval.score(state, run(state, attacks, ordered), def)
	if noise > 0.0 and rng != null:
		s += rng.randf_range(-noise, noise)
	return s


# For every attack with more than one blocker, the damage order the attacker would pick: the one
# that leaves the attacker the best off
static func order_blocks(state: Dictionary, attacks: Array, blocks: Dictionary) -> Dictionary:
	var out := {}
	for i in blocks:
		var group: Array = blocks[i]
		if group.size() < 2:
			out[i] = group
			continue
		var a: Dictionary = attacks[i]
		var attacker: Dictionary = state.units.get(a.uid, {})
		var att_player: int = 0 if attacker.is_empty() else attacker.ctrl
		var best_order: Array = group
		var best_score := -INF
		for perm in _permutations(group):
			var one := {0: perm}
			var s := Eval.score(state, run(state, [a], one), att_player)
			if s > best_score:
				best_score = s
				best_order = perm
		out[i] = best_order
	return out


static func _permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest := items.duplicate()
		var head = rest[i]
		rest.remove_at(i)
		for tail in _permutations(rest):
			out.append([head] + tail)
	return out
