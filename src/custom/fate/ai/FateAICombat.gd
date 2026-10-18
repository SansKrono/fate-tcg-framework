# Combat decisions of the Fate AI: which creatures attack and what they attack (plan_attack), how to
# block (plan_blocks) and how to order several blockers (order_my_blockers).
#
# The method, for the attack: build the attack plan one pair (attacker, target) at a time, always
# adding the pair that raises the score most; every candidate plan is scored by
#   1. playing it out against the defender's BEST blocks (FateAISim.best_blocks), then
#   2. a penalty for the opponent's counter-attack next turn against what is left: creatures that
#      attacked stay upright and cannot block, the others are tilted to guard (docs/FATE_RULES_SPEC.md
#      D6), so "who attacks" and "who defends" are one decision.
# A plan that wins the game on the spot is taken at once. Blocks are the mirror problem: the defender
# looks at the attacks that were declared and picks the assignment with the best score.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Sim := preload("res://src/custom/fate/ai/FateAISim.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")

# A plan must beat "do nothing" by this much to be worth attacking
const ATTACK_MARGIN := 0.05


# --- attacking -------------------------------------------------------------------------------------

# The creatures that could attack this turn: upright in the creature zone and allowed by their keywords
static func attackers_of(state: Dictionary, pid: int) -> Array:
	var found: Array = []
	for u in Snapshot.units_of(state, pid):
		if u.pos == "strike" and u.can_attack and u.strike > 0:
			found.append(u)
	return found


# Plans the attacks of player state.me. Returns
#   {"attacks": [{"uid", "kind": "player" | "unit", "target"}], "score": float, "lethal": bool}
# `profile` is a FateAIProfile (caution, think_width, noise, rng).
static func plan_attack(state: Dictionary, profile) -> Dictionary:
	var me: int = state.me
	var opp: int = state.opp
	var attackers := attackers_of(state, me)
	if attackers.is_empty():
		return {"attacks": [], "score": Eval.score(state, null, me), "lethal": false}
	# The whole army at the player: if that wins, do it
	var all_in: Array = []
	for u in attackers:
		all_in.append(Sim.make_attack(u.uid, "player", opp))
	var lethal_res := _play_out(state, all_in, profile)
	if lethal_res.life[opp] <= 0:
		return {"attacks": all_in, "score": Eval.LOSS, "lethal": true}
	# Candidate targets for each attacker, the best few
	var options := {}
	for u in attackers:
		var opts: Array = [Sim.make_attack(u.uid, "player", opp)]
		for t in Snapshot.units_of(state, opp):
			opts.append(Sim.make_attack(u.uid, "unit", t.uid))
		var scored: Array = []
		for o in opts:
			scored.append([score_plan(state, [o], profile), o])
		scored.sort_custom(func(x, y): return x[0] > y[0])
		var keep: Array = []
		for i in mini(scored.size(), maxi(1, profile.think_width) + 1):
			keep.append(scored[i][1])
		options[u.uid] = keep
	var plan: Array = []
	var current := score_plan(state, plan, profile)
	var remaining := attackers.duplicate()
	while not remaining.is_empty():
		var best_score := current + ATTACK_MARGIN
		var pick = null
		for u in remaining:
			for o in options[u.uid]:
				var s := score_plan(state, plan + [o], profile)
				if s > best_score:
					best_score = s
					pick = o
		if pick == null:
			break
		plan.append(pick)
		current = best_score
		remaining = remaining.filter(func(u): return u.uid != pick.uid)
	# One refinement sweep: does dropping an attack make the plan better?
	var i := 0
	while i < plan.size():
		var smaller := plan.duplicate()
		smaller.remove_at(i)
		var s := score_plan(state, smaller, profile)
		if s > current + ATTACK_MARGIN:
			plan = smaller
			current = s
		else:
			i += 1
	return {"attacks": order_attacks(plan), "score": current, "lethal": false}


# Attacks on creatures first (they can kill blockers), the rest after; stable otherwise
static func order_attacks(plan: Array) -> Array:
	var first: Array = []
	var second: Array = []
	for a in plan:
		if a.kind == "unit":
			first.append(a)
		else:
			second.append(a)
	return first + second


# Plays a plan out against the defender's best blocks. Returns the result.
static func _play_out(state: Dictionary, attacks: Array, profile) -> Dictionary:
	var blocks := Sim.best_blocks(state, attacks, state.opp, null, profile.noise, profile.rng)
	return Sim.run(state, attacks, Sim.order_blocks(state, attacks, blocks))


# The score of an attack plan for state.me: the result against the best blocks, minus the damage of
# the counter-attack that follows (scaled by profile.caution)
static func score_plan(state: Dictionary, attacks: Array, profile) -> float:
	var me: int = state.me
	var res := _play_out(state, attacks, profile)
	var s1 := Eval.score(state, res, me)
	if s1 >= Eval.LOSS * 0.5:
		return s1
	var attacking := {}
	for a in attacks:
		attacking[a.uid] = true
	var counter := counter_score(state, res, attacking, profile)
	var s: float = s1 + profile.caution * minf(0.0, counter - s1)
	if counter <= -Eval.LOSS * 0.5:
		# Losing to the counter-attack: never worth it
		s -= 500.0
	return s


# The position after the opponent's next attack, for state.me: the opponent's creatures have healed
# and stand upright; mine kept their damage, the ones that did not attack are tilted to guard. The
# opponent picks the worse of "no attack" and "everybody attacks the player".
static func counter_score(state: Dictionary, res: Dictionary, attacking: Dictionary, profile) -> float:
	var me: int = state.me
	var opp: int = state.opp
	var next := {"me": me, "opp": opp, "turn": state.turn + 1, "active": opp, "life": res.life.duplicate(),
			"units": {}, "face_weight": state.get("face_weight", 1.0)}
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		var o = res.units.get(uid)
		if o != null and o.dead:
			continue
		var c: Dictionary = u.duplicate()
		if u.ctrl == me:
			if o != null:
				c.strike = o.strike
				c.guard = o.guard
			if not attacking.has(uid) and c.pos == "strike":
				c.pos = "guard"
		else:
			c.strike = u.full_strike
			c.guard = u.full_guard
			c.pos = "strike"
		next.units[uid] = c
	var none_score := Eval.score(next, null, me)
	var theirs: Array = []
	for c in Snapshot.units_of(next, opp):
		if c.strike > 0:
			theirs.append(Sim.make_attack(c.uid, "player", me))
	if theirs.is_empty():
		return none_score
	var blocks := Sim.best_blocks(next, theirs, me)
	var res2 := Sim.run(next, theirs, Sim.order_blocks(next, theirs, blocks))
	return minf(none_score, Eval.score(next, res2, me))


# --- blocking ---------------------------------------------------------------------------------------

# Turns the attacks of the live combat into the simulator's attack list. Also returns, per attack
# index, the uids the engine allows to block it.
static func sim_attacks(game: FateGame) -> Dictionary:
	var attacks: Array = []
	var allowed := {}
	var engine: Array = game.combat.attacks
	for i in engine.size():
		var a: FateAttack = engine[i]
		var kind := "player" if a.targets_player() else "unit"
		var target: int = a.target_player if a.targets_player() else a.target_card.get_instance_id()
		var d := Sim.make_attack(a.attacker.get_instance_id(), kind, target)
		d.removed = a.removed or a.resolved or not is_instance_valid(a.attacker)
		d.negated = a.negated
		d.savage_done = a.metadata.has("savage")
		for r in a.restrictions:
			match r.get("kind", ""):
				"none":
					d.none = true
				"only":
					var cards: Array = r.get("cards", [])
					if cards.size() == 1:
						d.only = cards[0].get_instance_id()
		attacks.append(d)
		var ids: Array = []
		if game.combat.step == FateCombat.Step.INTERCEPT and not d.removed:
			for b in game.combat.eligible_blockers(a):
				ids.append(b.get_instance_id())
		allowed[i] = ids
	return {"attacks": attacks, "allowed": allowed}


# Chooses the blockers for the live attacks, for state.me as the defender. Returns an array with one
# entry per engine attack: the Array of blocker Cards in damage order (empty = no block).
static func plan_blocks(game: FateGame, state: Dictionary, profile) -> Array:
	var info := sim_attacks(game)
	var attacks: Array = info.attacks
	var blocks := Sim.best_blocks(state, attacks, state.me, info.allowed, profile.noise, profile.rng)
	blocks = Sim.order_blocks(state, attacks, blocks)
	var out: Array = []
	for i in attacks.size():
		var cards: Array = []
		for uid in blocks.get(i, []):
			var u: Dictionary = state.units.get(uid, {})
			if not u.is_empty():
				cards.append(u.card)
		out.append(cards)
	return out


# Re-orders the blockers of my own attacks (damage order is the attacker's choice) once the blocks
# are confirmed: the order that leaves the attack the best off
static func order_my_blockers(game: FateGame, state: Dictionary) -> void:
	var info := sim_attacks(game)
	var attacks: Array = info.attacks
	var blocks := {}
	var engine: Array = game.combat.attacks
	for i in engine.size():
		var a: FateAttack = engine[i]
		if a.attacker.controller_id != state.me or a.blockers.size() < 2:
			continue
		var ids: Array = []
		for b in a.blockers:
			ids.append(b.get_instance_id())
		blocks[i] = ids
	if blocks.is_empty():
		return
	var ordered := Sim.order_blocks(state, attacks, blocks)
	for i in ordered:
		var cards: Array = []
		for uid in ordered[i]:
			var u: Dictionary = state.units.get(uid, {})
			if not u.is_empty():
				cards.append(u.card)
		if cards.size() == engine[i].blockers.size():
			game.combat.order_blockers(engine[i], cards)
