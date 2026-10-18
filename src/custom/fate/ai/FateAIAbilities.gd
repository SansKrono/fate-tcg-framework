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
const Sim := preload("res://src/custom/fate/ai/FateAISim.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")

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
		var v := Eval.unit_value(u)
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

# Action ids handled by their own planners above (keyword actions)
const HANDLED_IDS := ["occupy", "embody", "force_block", "evolve"]
# Cost ids that are safe to pay for an ability whose effect the AI cannot read
const SAFE_COSTS := ["occupy", "tilt_self", "mana", "pay_domain", "counter", "limiter"]
# card name -> Callable(game, card, action) -> bool: card-specific permission, wins over the generic rule
# (return true to use an ability with unsafe costs, false to never use it)
static var CARD_RULES := {}


# The abilities of the AI's cards worth using this turn: [{"card": Card, "id": String}]. `attacking` is a set
# {uid: true} of the creatures that attack this turn; `spare` the mana the turn leaves.
static func plan_generic(game: FateGame, state: Dictionary, profile, spare: int, attacking: Dictionary) -> Array:
	var out: Array = []
	if game.card_effects == null:
		return out
	var left := spare
	for card in game.card_effects.table_cards():
		if not card is FateCardTemplate or card.controller_id != state.me:
			continue
		for action in game.actions.list(card):
			if action.id in HANDLED_IDS or not action.get("enabled", true) or not action.has("costs"):
				continue
			var verdict := _permission(game, card, action, attacking, left)
			if verdict < 0:
				continue
			left -= verdict
			out.append({"card": card, "id": action.id})
	return out


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
