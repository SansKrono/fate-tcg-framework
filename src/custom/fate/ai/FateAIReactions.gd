# Reaction spells for the Fate AI: when to hold mana for them (main phase) and when to cast them (in
# the reaction windows of combat, see FateReactions).
#
# Casting is decided by simulation: score the combat as it would go without the spell, score it with
# the spell's effect applied to the simulated position, cast when the difference beats the price of
# the card. The effects mirrored here are the ones in src/custom/fate/reactions/ (Safety Measure,
# Factory Shutdown, Wave of Fear, Hold the Line, Forests Protection); a reaction spell without a
# model in `_gain()` is never cast by the AI (it still counts for holding mana).
#
# The defender is the only player who gets a window, so the AI only ever casts for its own seat when
# it defends.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Sim := preload("res://src/custom/fate/ai/FateAISim.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")

# The reaction spells this file can score. Mana is only held for these: a reaction the AI cannot cast would
# reserve mana for nothing.
const MODELLED := ["Safety Measure", "Factory Shutdown", "Wave of Fear", "Hold the Line", "Forests Protection",
		"Double Agent"]
const DECLARE_END := "declare_end"
const INTERCEPT_END := "intercept_end"
# At most this many reaction spells in one window
const MAX_CASTS := 3


# --- holding mana (main phase) --------------------------------------------------------------------

# What keeping mana open for this reaction spell is worth during the main phase: its value times the
# chance the opponent attacks (more creatures on their side, more likely)
static func hold_value(state: Dictionary, profile, card: Card) -> float:
	if not profile.hold_reactions or not card.canonical_name in MODELLED:
		return 0.0
	var attackers := 0
	for u in Snapshot.units_of(state, state.opp):
		if u.strike > 0:
			attackers += 1
	var p := clampf(profile.opp_attack_prior * float(attackers), 0.0, 0.85)
	var v: float = Eval.REACTION_VALUE.get(card.canonical_name, Eval.REACTION_DEFAULT_VALUE)
	return v * p * profile.reaction_weight


# --- casting (combat windows) ---------------------------------------------------------------------

# Called when a reaction window opens for the AI's seat. Casts what is worth casting, returns the
# names of the spells cast (for the log).
static func respond(game: FateGame, seat: int, window, profile) -> Array:
	var cast_names: Array = []
	# A slip of the player: the window passes without a cast
	if profile.slips():
		return cast_names
	for _n in range(MAX_CASTS):
		if not window.is_open:
			break
		var castable: Array = game.reactions.castable_in_hand(seat)
		if castable.is_empty():
			break
		var state := Snapshot.for_profile(game, seat, profile)
		var info := Combat.sim_attacks(game)
		var attacks: Array = info.attacks
		var base := _score_after(state, attacks, window.step, game, seat, profile)
		var best: Card = null
		var best_gain := 0.0
		var best_choice = null
		for card in castable:
			var o := _gain(game, state, attacks, window.step, card, seat, profile, base)
			if o.is_empty():
				continue
			var worth: float = Eval.REACTION_VALUE.get(card.canonical_name, Eval.REACTION_DEFAULT_VALUE)
			# Losing the game is the case where the card is worth nothing in hand
			var price: float = 0.0 if base <= -Eval.LOSS * 0.5 else (0.4 * worth + 0.5) * profile.reaction_price
			var net: float = o.gain - price
			if net > best_gain:
				best_gain = net
				best = card
				best_choice = o.choice
		if best == null:
			break
		var name := best.canonical_name
		if not game.reactions.cast(best, best_choice):
			break
		cast_names.append(name)
	return cast_names


# The score for `seat` of the combat as it stands: before blocks (declare_end) the defender will
# still pick its best blocks, after them (intercept_end) the declared blocks stand
static func _score_after(state: Dictionary, attacks: Array, step: String, game: FateGame, seat: int,
		profile) -> float:
	var blocks := {}
	if step == DECLARE_END:
		blocks = Sim.best_blocks(state, attacks, seat, null, 0.0, null)
	else:
		blocks = _declared_blocks(game)
	return Eval.score(state, Sim.run(state, attacks, Sim.order_blocks(state, attacks, blocks)), seat)


static func _declared_blocks(game: FateGame) -> Dictionary:
	var blocks := {}
	var engine: Array = game.combat.attacks
	for i in engine.size():
		var group: Array = []
		for b in engine[i].blockers:
			group.append(b.get_instance_id())
		if not group.is_empty():
			blocks[i] = group
	return blocks


# What one reaction spell would do to the score: {"gain": float, "choice": Variant}, or an empty
# dictionary when the AI has no model of the spell
static func _gain(game: FateGame, state: Dictionary, attacks: Array, step: String, card: Card, seat: int,
		profile, base: float) -> Dictionary:
	var opp := 3 - seat
	match card.canonical_name:
		"Safety Measure":
			var best_g := -INF
			var pick: Card = null
			for i in attacks.size():
				var a: Dictionary = attacks[i]
				if a.removed or not state.units.has(a.uid) or state.units[a.uid].ctrl != opp:
					continue
				var s2 := _without_unit(state, a.uid)
				var g := _score_after(s2, attacks, step, game, seat, profile) - base
				if g > best_g:
					best_g = g
					pick = state.units[a.uid].card
			if pick == null:
				return {}
			return {"gain": best_g, "choice": pick}
		"Factory Shutdown":
			var negated := _copy_attacks(attacks)
			for a in negated:
				if _aims_at(state, a, seat):
					a.negated = true
			return {"gain": _score_after(state, negated, step, game, seat, profile) - base, "choice": null}
		"Wave of Fear":
			var removed := _copy_attacks(attacks)
			var chosen: Array = []
			var cur := base
			while true:
				var best_i := -1
				var best_s := cur + 0.01
				for i in removed.size():
					var a: Dictionary = removed[i]
					if a.removed or not state.units.has(a.uid) or state.units[a.uid].ctrl != opp:
						continue
					a.removed = true
					var s := _score_after(state, removed, step, game, seat, profile)
					a.removed = false
					if s > best_s:
						best_s = s
						best_i = i
				if best_i < 0:
					break
				removed[best_i].removed = true
				chosen.append(state.units[removed[best_i].uid].card)
				cur = best_s
			if chosen.is_empty():
				return {"gain": 0.0, "choice": null}
			return {"gain": cur - base, "choice": chosen}
		"Hold the Line":
			if step != DECLARE_END:
				return {}
			var s3 := Snapshot.copy_of(state)
			for uid in s3.units:
				var u: Dictionary = s3.units[uid]
				if u.ctrl == seat and u.pos == "strike":
					u.pos = "guard"
					u.guard += 1
			return {"gain": _score_after(s3, attacks, step, game, seat, profile) - base, "choice": null}
		"Double Agent":
			if step != DECLARE_END:
				return {}
			var effect = game.reactions.effect_of(card.canonical_name)
			if effect == null:
				return {}
			var best_t := -INF
			var pick_t: Card = null
			for target in effect.candidates(seat):
				var tid: int = target.get_instance_id()
				if not state.units.has(tid):
					continue
				var s5 := Snapshot.copy_of(state)
				var stolen: Dictionary = s5.units[tid]
				stolen.ctrl = seat
				stolen.pos = "guard"
				var removed5 := _copy_attacks(attacks)
				for a5 in removed5:
					if a5.uid == tid:
						a5.removed = true
				var g5 := _score_after(s5, removed5, step, game, seat, profile) - base
				if g5 > best_t:
					best_t = g5
					pick_t = target
			if pick_t == null:
				return {}
			return {"gain": best_t, "choice": pick_t}
		"Forests Protection":
			var s4 := Snapshot.copy_of(state)
			for uid in s4.units:
				var u: Dictionary = s4.units[uid]
				if u.ctrl == seat:
					u.kw["Indomitable"] = 1
			return {"gain": _score_after(s4, attacks, step, game, seat, profile) - base, "choice": null}
	return {}


static func _without_unit(state: Dictionary, uid: int) -> Dictionary:
	var s := state.duplicate()
	s.units = state.units.duplicate()
	s.units.erase(uid)
	return s


static func _copy_attacks(attacks: Array) -> Array:
	var out: Array = []
	for a in attacks:
		out.append(a.duplicate())
	return out


# Is this attack aimed at the player or at one of the player's creatures?
static func _aims_at(state: Dictionary, a: Dictionary, pid: int) -> bool:
	if a.kind == "player":
		return a.target == pid
	var t: Dictionary = state.units.get(a.target, {})
	return not t.is_empty() and t.ctrl == pid
