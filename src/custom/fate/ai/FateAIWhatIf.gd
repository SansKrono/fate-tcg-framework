# "What if" for the spells and abilities whose effect changes the next combat: apply the effect to a copy of the
# snapshot, plan the attack again and compare. The gain is what the effect is worth this turn, in the same points
# as every other evaluation (FateAIEval), and replaces the flat value of the card (hand_value).
#
# Modelled (FateAIReactions does the same for reaction spells in combat windows):
#   Battle Ready     up to 3 own creatures switch to strike position and gain +1 Strike
#   Primal Wraith    own creatures gain Savage 1
#   Smite            an opposing creature that is not unique is destroyed
#   Devote Paladin   (ability "devote") own creatures gain +1 Strike and Savage 1; the Paladin is occupied
#   Faithful Worshiper (ability "worship") own creatures gain Indomitable
#
# The creature(s) the effect would pick are returned as `focus`: the AI's chooser (FateAIChoices) is told to
# take them (profile.focus), so the card does what the model assumed.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")

const SPELLS := ["Battle Ready", "Primal Wraith", "Smite"]
const ABILITIES := {"Devote Paladin": "devote", "Faithful Worshiper": "worship"}


static func models_spell(card_name: String) -> bool:
	return card_name in SPELLS


# What the spell would gain this turn: {"gain": float, "focus": Array of unit uids (may be empty), "attackers":
# int (creatures that attack because of it)}. An empty dictionary when the card has no model.
static func spell(state: Dictionary, profile, card_name: String) -> Dictionary:
	if not card_name in SPELLS:
		return {}
	return _gain(state, profile, card_name)


# The same for an ability of a card on the table: `card_name` of the card, `uid` of its unit
static func ability(state: Dictionary, profile, card_name: String, uid: int) -> Dictionary:
	if not ABILITIES.has(card_name):
		return {}
	var r := _gain(state, profile, ABILITIES[card_name], uid)
	if r.is_empty():
		return r
	# The price: an energy card out of the mana base
	r["gain"] = float(r.gain) - profile.energy_card_value
	return r


static func _gain(state: Dictionary, profile, effect_name: String, source_uid := -1) -> Dictionary:
	var me: int = state.me
	var base: Dictionary = state["_wb"] if state.has("_wb") else Combat.plan_attack(Snapshot.copy_of(state), profile)
	state["_wb"] = base
	var s2 := Snapshot.copy_of(state)
	s2.erase("_wb")
	var focus: Array = []
	match effect_name:
		"Battle Ready":
			focus = _battle_ready(s2, me)
			if focus.is_empty():
				return {"gain": 0.0, "focus": [], "attackers": 0}
		"Primal Wraith":
			for u in Snapshot.units_of(s2, me):
				u.kw["Savage"] = int(u.kw.get("Savage", 0)) + 1
		"Smite":
			# Smite is not about the biggest creature but about the one that stands in the way: try each
			var best_gain := -INF
			var best_plan: Dictionary = {}
			for u in Snapshot.units_of(s2, s2.opp):
				if u.unique:
					continue
				var s3 := Snapshot.copy_of(state)
				s3.erase("_wb")
				s3.units.erase(u.uid)
				var plan := Combat.plan_attack(s3, profile)
				var g: float = plan.score - base.score
				if g > best_gain:
					best_gain = g
					best_plan = {"gain": g, "focus": [u.uid], "attackers": plan.attacks.size()}
			return best_plan
		"devote", "worship":
			for u in Snapshot.units_of(s2, me):
				if effect_name == "devote":
					u.strike += 1
					u.full_strike += 1
					u.kw["Savage"] = maxi(1, int(u.kw.get("Savage", 0)))
				else:
					u.kw["Indomitable"] = 1
			# The Paladin occupies: it cannot attack, but it still blocks
			if effect_name == "devote" and s2.units.has(source_uid):
				s2.units[source_uid].pos = "occupied"
				s2.units[source_uid].can_attack = false
	var plan2 := Combat.plan_attack(s2, profile)
	return {"gain": plan2.score - base.score, "focus": focus, "attackers": plan2.attacks.size()}


# Battle Ready on the snapshot. The spell takes min(3, number of eligible creatures) of both players' creatures that
# are not occupied (FxBattleReady), so with few creatures of my own it also switches enemy guards upright, which
# keeps them from intercepting. Picks my creatures that can attack first (a guard turned upright becomes an
# attacker), then the most valuable enemy guards. Returns the uids; they get +1 Strike and stand upright.
static func _battle_ready(state: Dictionary, me: int) -> Array:
	var w: Dictionary = state.get("w", Eval.DEFAULT_W)
	var mine: Array = []
	var theirs: Array = []
	for u in state.units.values():
		if u.pos == "occupied":
			continue
		if u.ctrl == me:
			var useful: bool = u.can_attack and u.full_strike > 0
			mine.append([(float(u.full_strike) + (2.0 if u.pos == "guard" else 0.0)) if useful else -1.0, u])
		else:
			theirs.append([(10.0 if u.pos == "guard" else 0.0) + Eval.unit_value(u, -1, -1, w), u])
	var wanted := mini(3, mine.size() + theirs.size())
	if wanted <= 0:
		return []
	mine.sort_custom(func(a, b): return a[0] > b[0])
	theirs.sort_custom(func(a, b): return a[0] > b[0])
	var picked: Array = []
	for e in mine:
		if picked.size() >= wanted:
			break
		var u: Dictionary = e[1]
		if e[0] >= 0.0:
			u.strike += 1
			u.full_strike += 1
		u.pos = "strike"
		picked.append(u.uid)
	for e in theirs:
		if picked.size() >= wanted:
			break
		var u: Dictionary = e[1]
		u.strike += 1
		u.full_strike += 1
		u.pos = "strike"
		picked.append(u.uid)
	return picked
