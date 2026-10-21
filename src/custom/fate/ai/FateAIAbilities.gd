# Activated abilities for the Fate AI: the actions the engine offers on cards in play
# (FateActions: Occupy, Embody, Force block) and when each is worth using.
#
# This is the one place where the AI learns what a card's ability is FOR. Today the engine runs only
# the three keyword actions above (card scripts do not exist yet, docs/FATE_TCG_DESIGN.md Section 17),
# so that is all that is scored here:
#   * Embody (Primal, the ramp-to-big-things plan): pay X, put an energy card under a creature for +Strike
#     and +Guard equal to its mana value. Worth it with mana to spare and an energy card of value 3 or more,
#     because the card is gone from the mana base for good.
#   * Force block: pay 2 so that, this turn, the attack can only be blocked by one named creature of the
#     opponent. Naming a creature that cannot block (it is upright, or has Cannot block) makes the attack
#     unblockable. Scored by simulating the attack with and without.
#   * Occupy: tilts the creature into the occupied zone. Its effect is not implemented, and an occupied
#     creature does nothing a guarding one does not, so the AI leaves it alone.
# Abilities written in card scripts (cards/Fx*.gd, built with make_action) are used by `plan_generic`
# without knowing what they do, when they are cheap and safe: the costs are only Occupy / tilt (and the
# creature is not attacking this turn: an occupied creature still blocks), mana the turn leaves spare,
# counters (scrap, ingot) and once-per-turn limits. Abilities that give up cards (consume, discard, return to
# hand) are left alone unless a scorer for that card is added to CARD_RULES. A card script can also set the
# hint `ai_value`/`ai_intent` (cards/FateCardEffect.gd).
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Choices := preload("res://src/custom/fate/ai/FateAIChoices.gd")
const Sim := preload("res://src/custom/fate/ai/FateAISim.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")
const WhatIf := preload("res://src/custom/fate/ai/FateAIWhatIf.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")

const FORCE_BLOCK_COST := 2
# A forced block must be worth more than this many points (two mana is two mana)
const FORCE_BLOCK_MARGIN := 1.0


# --- Embody ----------------------------------------------------------------------------------------

# Returns {"card": creature, "energy": energy card} if Embody is worth using now, else {}.
# `spare` is the mana left after everything else this turn.
static func plan_embody(game: FateGame, state: Dictionary, profile, spare: int) -> Dictionary:
	if not profile.use_embody:
		return {}
	var kw = game.keywords.get_keyword("Embody")
	if kw == null:
		return {}
	var me: int = state.me
	var energy_cards: Array = game.player(me).cards_in_grid("energy")
	if energy_cards.size() - 1 < profile.embody_keep_energy:
		return {}
	var best_creature: Card = null
	var best_value := -INF
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		if u.ctrl != me or not kw.has_ability(u.card):
			continue
		var cost: int = kw.cost_of(u.card)
		if cost > spare:
			continue
		var v := Eval.unit_value(u, -1, -1, profile.eval_weights())
		if v > best_value:
			best_value = v
			best_creature = u.card
	if best_creature == null:
		return {}
	var best_energy: Card = null
	for e in kw.candidates(best_creature):
		if best_energy == null or e.mana_value() > best_energy.mana_value():
			best_energy = e
	if best_energy == null or best_energy.mana_value() < profile.embody_min_value:
		return {}
	var held = kw.embodied_card(best_creature)
	if held != null and held.mana_value() >= best_energy.mana_value():
		return {}
	if not kw.can_embody(best_creature, best_energy):
		return {}
	return {"card": best_creature, "energy": best_energy}


# --- Force block -----------------------------------------------------------------------------------

# For the planned attacks (list of sim attacks), finds the attackers that have the Force block ability
# and a creature to name that makes it worth the mana. Returns [{"card": attacker, "target": Card,
# "attack": the changed sim attack}]; the caller pays and updates the plan. `spare` is mana to spend.
static func plan_force_blocks(game: FateGame, state: Dictionary, attacks: Array, profile, spare: int) -> Array:
	var kw = game.keywords.get_keyword("Forced blocker")
	var out: Array = []
	if kw == null or spare < FORCE_BLOCK_COST:
		return out
	var left := spare
	for i in attacks.size():
		if left < FORCE_BLOCK_COST:
			break
		var a: Dictionary = attacks[i]
		var attacker: Dictionary = state.units.get(a.uid, {})
		if attacker.is_empty() or not kw.has_ability(attacker.card) or kw.problem(attacker.card) != "":
			continue
		var base := Combat.score_plan(state, attacks, profile)
		var best_target: Dictionary = {}
		var best_gain := FORCE_BLOCK_MARGIN
		for t in kw.candidates(attacker.card):
			var trial := attacks.duplicate()
			var changed: Dictionary = a.duplicate()
			changed.only = t.get_instance_id()
			trial[i] = changed
			var gain := Combat.score_plan(state, trial, profile) - base
			if gain > best_gain:
				best_gain = gain
				best_target = {"card": attacker.card, "target": t, "attack": changed}
		if not best_target.is_empty():
			out.append(best_target)
			attacks[i] = best_target.attack
			left -= FORCE_BLOCK_COST
	return out


# --- abilities of card scripts ----------------------------------------------------------------------------

# Action ids handled by their own planners above or below (keyword actions, mana makers, pumps)
const HANDLED_IDS := ["occupy", "embody", "force_block", "evolve", "elder_spirit", "ancient_tree", "devote",
		"worship", "teshra_flip"]
# Cost ids that are safe to pay for an ability whose effect the AI cannot read
const SAFE_COSTS := ["occupy", "tilt_self", "mana", "pay_domain", "counter", "limiter"]
# card name -> Callable(game, card, action) -> bool: card-specific permission, wins over the generic rule
# (return true to use an ability with unsafe costs, false to never use it)
static var CARD_RULES := {}
# Abilities that make mana: used before the cards are cast (profile.produce_mana_first)
const MANA_IDS := ["elder_spirit", "ancient_tree"]
# Cards whose abilities turn ingots into something (an ingot is worth more with one of them on the table)
const INGOT_SINKS := ["Battle Smith", "Factory Crafter", "Brogir, Master Artificer", "Thrang's Crafting Table"]
# Cards that turn scrap into ingots: with one of them and a sink on the table, scrap starts the whole chain
const SCRAP_CONVERTERS := ["Acquisition Fabricator", "Brogir, Master Artificer", "Factory Refinery"]
# What a scrap is worth on top when it feeds a converter and a sink (the ingot, then what the sink makes of it)
const CHAIN_BONUS := 1.5


# The abilities of the AI's cards worth using this turn: [{"card": Card, "id": String, "value": float}], best
# first. `attacking` is a set {uid: true} of the creatures that attack this turn; `spare` the mana the turn leaves.
# Abilities the AI can value (_value) are used when they are worth more than profile.ability_margin; the others
# when their costs are safe (SAFE_COSTS).
static func plan_generic(game: FateGame, state: Dictionary, profile, spare: int, attacking: Dictionary) -> Array:
	var out: Array = []
	if game.card_effects == null or not profile.ability_use:
		return out
	var cands: Array = []
	for card in game.card_effects.table_cards():
		if not card is FateCardTemplate or card.controller_id != state.me:
			continue
		for action in game.actions.list(card):
			if action.id in HANDLED_IDS or not action.get("enabled", true) or not action.has("costs"):
				continue
			var value := _value(game, state, profile, card, action)
			var mana := 0
			for cost in action.costs:
				mana += _mana_of(cost)
			if value.has("skip"):
				continue
			if value.has("value"):
				if value.value < profile.ability_margin or (value.get("risky", false) and not profile.ability_risk):
					continue
				if (value.get("occupies", false) or _tilts(action)) and attacking.has(card.get_instance_id()):
					continue
				cands.append({"card": card, "id": action.id, "value": value.value, "mana": mana})
				continue
			# No model of the effect: the old rule, safe costs only
			var verdict := _permission(game, card, action, attacking, spare)
			if verdict < 0:
				continue
			cands.append({"card": card, "id": action.id, "value": 0.6, "mana": verdict})
	cands.sort_custom(func(a, b): return a.value > b.value)
	var left := spare
	for c in cands:
		if c.mana > left:
			continue
		left -= c.mana
		out.append({"card": c.card, "id": c.id, "value": c.value})
	return out


# Scrap Cannon: how many shots at the opponent's life this turn, and the cannon that fires them. Every scrap the engine
# does not need goes (profile.burn_reserve stays back for ingots), all of it when the scrap is lethal. Returns
# {"card": Card, "shots": int, "lethal": bool}, or {} when there is nothing to fire.
static func plan_burn(game: FateGame, state: Dictionary, profile) -> Dictionary:
	if not profile.scrap_burn or profile.effect_gain_weight <= 0.0 or game.card_effects == null or game.tokens == null:
		return {}
	var me: int = state.me
	var scrap: int = game.tokens.counter(me, "scrap")
	if scrap < 1:
		return {}
	var cannon: Card = null
	for card in game.card_effects.table_cards():
		if not card is FateCardTemplate or card.controller_id != me or card.canonical_name != "Scrap Cannon":
			continue
		for action in game.actions.list(card):
			if action.id == "fire" and action.get("enabled", true):
				cannon = card
		if cannon != null:
			break
	if cannon == null:
		return {}
	var life: int = int(state.life[state.opp])
	var lethal := scrap >= life
	var shots := life if lethal else maxi(0, scrap - profile.burn_reserve)
	if shots < 1:
		return {}
	return {"card": cannon, "shots": shots, "lethal": lethal}


# The best value of an ability of this card that costs it its turn (an occupy or a tilt); 0 when it has none
static func occupy_value(game: FateGame, state: Dictionary, profile, card: Card) -> float:
	var best := 0.0
	for action in game.actions.list(card):
		if action.id in HANDLED_IDS or not action.get("enabled", true) or not action.has("costs") or not _tilts(action):
			continue
		var v := _value(game, state, profile, card, action)
		if v.has("value") and not (v.get("risky", false) and not profile.ability_risk):
			best = maxf(best, float(v.value))
	return best


static func _tilts(action: Dictionary) -> bool:
	for cost in action.costs:
		if cost.id in ["occupy", "tilt_self"]:
			return true
	return false


# What an ability is worth this turn, in points: {"value": float, "risky": bool, "occupies": bool} or {"skip": true}
# for an ability not worth thinking about; {} when the AI has no model (the generic safe-cost rule decides).
static func _value(game: FateGame, state: Dictionary, profile, card: Card, action: Dictionary) -> Dictionary:
	# effect_gain_weight 0 is the old behaviour: no model of any ability
	if profile.effect_gain_weight <= 0.0:
		return {}
	var me: int = state.me
	var w: Dictionary = state.get("w", Eval.DEFAULT_W)
	var name: String = card.canonical_name
	var scrap: int = game.tokens.counter(me, "scrap") if game.tokens != null else 0
	var ingots: int = game.tokens.counter(me, "ingot") if game.tokens != null else 0
	var token33 := {"strike": 3, "guard": 3, "full_strike": 3, "full_guard": 3, "kw": {}, "mv": 0, "unique": false, "token": true}
	var token11 := {"strike": 1, "guard": 1, "full_strike": 1, "full_guard": 1, "kw": {}, "mv": 0, "unique": false, "token": true}
	match action.id:
		"scrap":
			if name == "Garbage Heap":
				# Two scrap for a relic that does nothing else
				return {"value": 1.8 + (2.0 if _has_card(game, me, "Rarink, Crafty Opportunist") else 0.0), "risky": true}
			var sink := _sink_present(game, me)
			var chain := CHAIN_BONUS if sink and scrap < 1 and _converter_present(game, me) else 0.0
			return {"value": 0.8 + (0.3 if sink else 0.0) + chain, "occupies": true}
		"fabricate", "scrap_to_ingot", "refine":
			if scrap < 1:
				return {"skip": true}
			return {"value": 0.6 + (2.0 if _sink_present(game, me) else 0.0), "occupies": true}
		"hammer", "ingot_to_hammer":
			if _free(game, me, "relics") == 0 or ingots < 1 or Snapshot.units_of(state, me).is_empty():
				return {"skip": true}
			return {"value": 2.2 * w.w_strike, "occupies": true}
		"craft":
			if _free(game, me, "creatures") == 0:
				return {"skip": true}
			return {"value": Eval.unit_value(token33, -1, -1, w), "occupies": true}
		"automaton":
			if _free(game, me, "creatures") == 0 or ingots < 2:
				return {"skip": true}
			return {"value": Eval.unit_value(token33, -1, -1, w) - 0.8}
		"thrang":
			return {"value": 9.0} if ingots >= 3 else {"skip": true}
		"recruit":
			if _free(game, me, "creatures") == 0:
				return {"skip": true}
			return {"value": Eval.unit_value(token11, -1, -1, w) * 1.05, "occupies": true}
		"fire":
			# 1 damage to the opponent's life: effect damage heals at the owner's maintenance, so a creature is no target
			var opp_life: int = state.life[state.opp]
			var gain: float = Eval.life_value(opp_life, w) - Eval.life_value(opp_life - 1, w)
			return {"value": gain * state.get("face_weight", 1.0) - 0.5 - 0.3 * float(maxi(0, 3 - scrap))}
		"cast_mana":
			# Enthralled Civilian: consume it to flip cast one of the mana cards (the other energy pays the cost); the
			# card stops being mana, so the AI wants a card that is worth much more than a mana and the Civilian
			var best_flip := 0.0
			for c in game.casting.flip_castable(me, Callable(), true):
				best_flip = maxf(best_flip, Eval.hand_value(game, c, w) * profile.flip_cast_bias)
			var own := Eval.unit_value(Snapshot.unit_of(game, card), -1, -1, w)
			return {"value": best_flip - own - 1.5, "risky": true}
		"summon":
			# Ikthar: consume an opposing creature, tutor a unique creature
			return {"value": 7.0, "risky": true, "occupies": true}
	return {}


static func _has_card(game: FateGame, pid: int, card_name: String) -> bool:
	for c in game.creatures_in_play(pid):
		if c.canonical_name == card_name:
			return true
	return false


static func _sink_present(game: FateGame, pid: int) -> bool:
	if game.card_effects == null:
		return false
	for c in game.card_effects.table_cards():
		if c is FateCardTemplate and c.controller_id == pid and c.canonical_name in INGOT_SINKS:
			return true
	return false


static func _converter_present(game: FateGame, pid: int) -> bool:
	if game.card_effects == null:
		return false
	for c in game.card_effects.table_cards():
		if c is FateCardTemplate and c.controller_id == pid and c.canonical_name in SCRAP_CONVERTERS:
			return true
	return false


static func _free(game: FateGame, pid: int, zone: String) -> int:
	var grid := game.player(pid).grid(zone)
	if grid == null:
		return 0
	# A zone without a limit (energy, relics) always has room
	if grid.auto_extend:
		return 99
	var n := 0
	for slot in grid.get_all_slots():
		if slot.occupying_card == null:
			n += 1
	return n


# -1: do not use it; otherwise the mana it spends
static func _permission(game: FateGame, card: Card, action: Dictionary, attacking: Dictionary, spare: int) -> int:
	var rule = CARD_RULES.get(card.canonical_name)
	var mana := 0
	for cost in action.costs:
		mana += _mana_of(cost)
	if mana > spare:
		return -1
	if rule is Callable:
		return mana if rule.call(game, card, action) else -1
	for cost in action.costs:
		if not _safe(cost, card, attacking):
			return -1
	return mana


static func _safe(cost: Dictionary, card: Card, attacking: Dictionary) -> bool:
	if cost.id == "either":
		return true
	if not cost.id in SAFE_COSTS:
		return false
	# An attacker must stay upright
	if cost.id in ["occupy", "tilt_self"] and attacking.has(card.get_instance_id()):
		return false
	return true


# The number of mana a cost takes ("Pay 2" / "Pay 1 Order" labels)
static func _mana_of(cost: Dictionary) -> int:
	if cost.id in ["mana", "pay_domain"]:
		var found := RegEx.create_from_string("\\d+").search(str(cost.get("label", "")))
		return int(found.get_string()) if found != null else 1
	return 0


# --- mana makers (before the cards are cast) --------------------------------------------------------------

# The abilities that make mana or energy and are free to use now: [{"card", "id"}]
static func plan_mana_makers(game: FateGame, state: Dictionary, profile) -> Array:
	var out: Array = []
	if not profile.produce_mana_first or game.card_effects == null or not profile.ability_use:
		return out
	var me: int = state.me
	for card in game.card_effects.table_cards():
		if not card is FateCardTemplate or card.controller_id != me:
			continue
		for action in game.actions.list(card):
			if not action.id in MANA_IDS or not action.get("enabled", true):
				continue
			if action.id == "elder_spirit":
				# The top card of the deck becomes energy: not with a thin deck, not past a full mana base
				if state.deck_count[me] < profile.deck_safety + 2 or state.mana[me].total >= profile.max_energy + 2:
					continue
			out.append({"card": card, "id": action.id})
	return out


# --- evolve ------------------------------------------------------------------------------------------------

# Evolve a creature (Beetle Brawler into Ironside Beetle) when the card it fetches is worth the mana: it arrives
# with Charge, so it attacks this turn. Returns {"card": creature, "gain": float} or {}.
static func plan_evolve(game: FateGame, state: Dictionary, profile, mana_left: int) -> Dictionary:
	if not profile.use_evolve:
		return {}
	var kw = game.keywords.get_keyword("Evolution")
	if kw == null:
		return {}
	var me: int = state.me
	var w: Dictionary = state.get("w", Eval.DEFAULT_W)
	var best := {}
	var best_gain: float = profile.ability_margin
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		if u.ctrl != me or not kw.has_ability(u.card) or kw.cost_of(u.card) > mana_left:
			continue
		if not kw.can_evolve(u.card):
			continue
		var fetched: Card = kw.target_in_deck(u.card)
		if fetched == null:
			continue
		var pseudo := Eval.pseudo_unit(game, fetched)
		pseudo["uid"] = -1 - uid
		pseudo["card"] = fetched
		pseudo["name"] = fetched.canonical_name
		pseudo["owner"] = me
		pseudo["ctrl"] = me
		pseudo["pos"] = "strike"
		pseudo["sick"] = false
		pseudo["can_attack"] = true
		pseudo["ability"] = false
		pseudo["token"] = false
		var base: Dictionary = Combat.plan_attack(Snapshot.copy_of(state), profile)
		var s2 := Snapshot.copy_of(state)
		s2.units.erase(uid)
		s2.units[pseudo.uid] = pseudo
		var gain: float = Combat.plan_attack(s2, profile).score - base.score
		gain -= profile.mana_use_weight * float(kw.cost_of(u.card))
		if gain > best_gain:
			best_gain = gain
			best = {"card": u.card, "gain": gain}
	return best


# --- pump abilities (Devote Paladin, Faithful Worshiper) ---------------------------------------------------

# Abilities that strengthen the whole army for one combat, worth it when the re-planned attack gains more than the
# energy card they consume. Returns [{"card", "id", "gain", "focus"}]
static func plan_pumps(game: FateGame, state: Dictionary, profile) -> Array:
	var out: Array = []
	if game.card_effects == null or not profile.ability_use or profile.effect_gain_weight <= 0.0:
		return out
	var me: int = state.me
	if state.mana[me].total - 1 < profile.spare_energy_floor:
		return out
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		if u.ctrl != me or not WhatIf.ABILITIES.has(u.name):
			continue
		var action: Dictionary = game.actions.find(u.card, WhatIf.ABILITIES[u.name])
		if action.is_empty() or not action.get("enabled", true):
			continue
		var r := WhatIf.ability(state, profile, u.name, uid)
		if not r.is_empty() and float(r.gain) * profile.effect_gain_weight >= profile.ability_margin:
			out.append({"card": u.card, "id": WhatIf.ABILITIES[u.name], "gain": r.gain, "focus": r.focus})
	out.sort_custom(func(a, b): return a.gain > b.gain)
	# Only the best one of a kind per turn: the second Paladin adds Strike again, but the energy runs out
	return out.slice(0, 1)


# --- flipping a creature out of the energy zone before the attack -----------------------------------------------

# Teshra, Primal Mother: pay 3, a creature of the energy zone comes in with Charge for this turn. Worth it when the
# creature that comes (the best one by stats) adds more to the attack than 3 mana and a possible loss are worth.
# Returns the Card of Teshra to use, or null.
static func plan_flip(game: FateGame, state: Dictionary, profile, mana_left: int):
	if not profile.flip_before_attack or mana_left < 3 or game.card_effects == null:
		return null
	var me: int = state.me
	var cost_value: float = 3.0 * profile.mana_use_weight + 1.0
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		if u.ctrl != me or u.name != "Teshra, Primal Mother" or u.pos == "occupied":
			continue
		var action: Dictionary = game.actions.find(u.card, "teshra_flip")
		if action.is_empty() or not action.get("enabled", true):
			continue
		var best: Card = null
		var best_v := -INF
		for e in game.player(me).cards_in_grid("energy"):
			if e.properties.get("Type") != "Creature":
				continue
			var v := Eval.unit_value(Eval.pseudo_unit(game, e), -1, -1, state.get("w", Eval.DEFAULT_W))
			if v > best_v:
				best_v = v
				best = e
		if best == null:
			continue
		var pseudo := Eval.pseudo_unit(game, best)
		pseudo["uid"] = -1 - best.get_instance_id()
		pseudo["card"] = best
		pseudo["name"] = best.canonical_name
		pseudo["owner"] = me
		pseudo["ctrl"] = me
		pseudo["pos"] = "strike"
		pseudo["sick"] = false
		pseudo["can_attack"] = true
		pseudo["ability"] = false
		pseudo["token"] = false
		var base: Dictionary = Combat.plan_attack(Snapshot.copy_of(state), profile)
		var s2 := Snapshot.copy_of(state)
		s2.units[pseudo.uid] = pseudo
		var plan: Dictionary = Combat.plan_attack(s2, profile)
		# The borrowed creature must be among the attackers or the 3 mana buys nothing
		var attacks_with := false
		for a in plan.attacks:
			if a.uid == pseudo.uid:
				attacks_with = true
		if attacks_with and plan.score - base.score > cost_value:
			return u.card
	return null
