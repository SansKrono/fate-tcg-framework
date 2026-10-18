# Evaluation for the Fate AI: what a creature, a life total, a card in hand and a whole position
# are worth. Everything works on the plain-data snapshot of FateAISnapshot, never on live nodes.
#
# No class_name on purpose (the global class cache is shared by everybody working at once): the
# other AI scripts reach this one with `preload("res://src/custom/fate/ai/FateAIEval.gd")`.
#
# The numbers are "points": one point is roughly one point of Strike or Guard on a creature. They
# are tuned for the 10 life / 40 card game of docs/FATE_RULES_SPEC.md and live in constants so a
# designer can change them in one place.
extends RefCounted

# The score of a position in which the player lost (and minus that when the opponent lost)
const LOSS := 1000.0

# What a reaction spell is worth to its owner while it sits in the hand (the potential, not the gain
# of one cast). Used to decide whether to hold mana for it and whether a cast is worth the card.
const REACTION_VALUE := {
	"Safety Measure": 5.0,
	"Factory Shutdown": 4.0,
	"Wave of Fear": 4.0,
	"Hold the Line": 3.0,
	"Forests Protection": 3.0,
}
const REACTION_DEFAULT_VALUE := 2.0

# Cards that are not creatures or reaction spells but whose effect the engine really runs.
# name -> value of having the card (as a hand card). Empty today: as of docs/FATE_TCG_DESIGN.md
# Section 17 regular spells, relics, field and world spells only cost mana and do nothing, so the AI
# treats them as "dead" and uses them as energy. Add an entry the day a card's effect is
# implemented (and teach FateAIMain how to use it if it needs a target).
const LIVE_EFFECTS := {}


# --- life ---------------------------------------------------------------------------------------

# What a life total is worth. Convex: the last points of life matter most. 0 or less is a loss.
static func life_value(life: int) -> float:
	if life <= 0:
		return -LOSS
	var v := 1.4 * float(life)
	if life < 7:
		v -= 0.12 * float((7 - life) * (7 - life))
	return v


# --- creatures ----------------------------------------------------------------------------------

# What a creature (a unit of the snapshot) is worth. `cur_strike` / `cur_guard` are the stats it has
# in the position being scored (after damage); damage heals at its owner's maintenance, so the value
# leans on the undamaged stats.
static func unit_value(u: Dictionary, cur_strike := -1, cur_guard := -1) -> float:
	var cs: int = u.strike if cur_strike < 0 else cur_strike
	var cg: int = u.guard if cur_guard < 0 else cur_guard
	var s: float = 0.7 * float(u.get("full_strike", u.strike)) + 0.3 * float(cs)
	var g: float = 0.7 * float(u.get("full_guard", u.guard)) + 0.3 * float(cg)
	var kw: Dictionary = u.kw
	var v: float = s + 0.85 * g + 0.45 * float(u.mv)
	if kw.has("Savage"):
		v += 1.1 * float(kw["Savage"])
	if kw.has("Indomitable"):
		v += 1.5 + 0.2 * (s + g)
	if kw.has("Untethered"):
		v += 0.4
	if kw.has("Unblockable"):
		v += 0.9 * s
	if kw.has("Cannot block"):
		v -= 0.25 * g
	if kw.has("Charge"):
		v += 0.4
	if kw.has("Productive"):
		v += 0.2
	if u.get("unique", false):
		v += 0.8
	return maxf(v, 0.2)


# --- positions ----------------------------------------------------------------------------------

# The score of a position for player `me`: the value of their creatures minus the opponent's, plus
# the value of their life minus the opponent's (the latter scaled by state.face_weight, the
# aggression of the profile). `result` is a FateAISim result (stats after damage, who is dead, life);
# pass null to score the snapshot as it is.
static func score(state: Dictionary, result, me: int) -> float:
	var s := 0.0
	var overlay: Dictionary = {} if result == null else result.units
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		var o = overlay.get(uid)
		if o != null and o.dead:
			continue
		var v: float = unit_value(u, u.strike if o == null else o.strike, u.guard if o == null else o.guard)
		s += v if u.ctrl == me else -v
	var life: Dictionary = state.life if result == null else result.life
	var opp := 3 - me
	var face: float = state.get("face_weight", 1.0)
	s += life_value(life[me])
	var opp_term: float = life_value(life[opp])
	# The opponent's loss counts in full: it ends the game
	s -= opp_term * (face if opp_term > -LOSS else 1.0)
	return s


# --- hand cards -----------------------------------------------------------------------------------

# What the card is for: "creature", "reaction" (castable in a combat window), "live" (a spell, relic or field /
# world spell whose card script really does something, see script_does_something) or "dead" (it only costs
# mana: energy fodder). A name in LIVE_EFFECTS counts as live without a script.
static func role(game: FateGame, card: Card) -> String:
	var type: String = str(card.properties.get("Type", ""))
	if type == "Creature":
		return "creature"
	if type == "Spell" and card is FateCardTemplate and card.is_reaction_spell():
		return "reaction" if game.reactions != null and game.reactions.effect_of(card.canonical_name) != null \
				else "dead"
	if LIVE_EFFECTS.has(card.canonical_name):
		return "live"
	if script_does_something(game, card):
		return "live"
	return "dead"


# Hooks of a card script that make a card do something. A script that only defines play_problem or the
# AI hints does nothing.
const EFFECT_HOOKS := ["resolve", "on_enter", "on_play", "on_leave", "on_phase", "on_card_played",
		"on_card_destroyed", "on_damage", "on_energy_played", "on_flip_cast", "on_attack_resolved",
		"static_keywords", "static_stat_bonus", "actions", "stat_bonus", "on_maintenance", "on_turn_end",
		"on_attack_declared", "on_blocked", "on_blocking", "on_destroyed", "can_block", "can_attack",
		"can_be_attacked", "can_be_blocked_by", "modify_damage_taken", "would_be_destroyed",
		"death_destination", "spell_destination", "spell_destination_for", "on_damage_dealt"]


# The methods the card's own script file defines (not the inherited ones)
static func script_methods(effect) -> Array:
	var names: Array = []
	var script = effect.get_script()
	if script != null:
		for m in script.get_script_method_list():
			names.append(m.name)
	return names


# Does the card have a script (game.card_effects) whose hooks do something? A regular spell needs
# `resolve`; a relic, field or world spell any hook.
static func script_does_something(game: FateGame, card: Card) -> bool:
	if game.card_effects == null:
		return false
	var effect = game.card_effects.effect_of(card.canonical_name)
	if effect == null:
		return false
	var methods := script_methods(effect)
	if str(card.properties.get("_spell_kind", "")) == "Regular":
		return "resolve" in methods or "spell_destination" in methods
	for hook in EFFECT_HOOKS:
		if hook in methods:
			return true
	return false


# A snapshot-style unit made from a card that is not in play (hand, deck), at base stats
static func pseudo_unit(game: FateGame, card: Card) -> Dictionary:
	var s: int = game.stats.base(card, "Strike")
	var g: int = game.stats.base(card, "Guard")
	return {
		"strike": s, "guard": g, "full_strike": s, "full_guard": g,
		"kw": game.keywords.innate(card), "mv": card.mana_value() if card is FateCardTemplate else 0,
		"unique": bool(card.properties.get("_unique", false)),
	}


# What having this card in hand is worth (0 for dead cards). A card script may say (ai_value); creatures
# with an enters / activated effect are worth a bit more; other live cards are worth about what they cost.
static func hand_value(game: FateGame, card: Card) -> float:
	var effect = game.card_effects.effect_of(card.canonical_name) if game.card_effects != null else null
	match role(game, card):
		"creature":
			var v := unit_value(pseudo_unit(game, card)) + 0.3
			if _has_hooks(effect):
				v += 0.6
			return v
		"reaction":
			return float(REACTION_VALUE.get(card.canonical_name, REACTION_DEFAULT_VALUE))
		"live":
			if LIVE_EFFECTS.has(card.canonical_name):
				return float(LIVE_EFFECTS[card.canonical_name])
			if effect != null:
				var stated: float = effect.ai_value(card, card.owner_id)
				if stated >= 0.0:
					return stated
			var kind := str(card.properties.get("_spell_kind", ""))
			return 1.5 + (0.8 if kind == "Regular" else 0.5) * float(card.mana_value())
	return 0.0


# Does a script define a hook beyond the keyword defaults? (creatures: an enters or activated effect)
static func _has_hooks(effect) -> bool:
	if effect == null:
		return false
	var methods := script_methods(effect)
	for hook in ["on_enter", "on_play", "actions", "on_attack_declared", "on_destroyed", "on_phase"]:
		if hook in methods:
			return true
	return false


# How much the player would miss this card if it became an energy card: the lowest is energized
# first. Dead cards are free; expensive cards that are far out of reach lose some of their value.
static func keep_value(game: FateGame, card: Card, energy_count: int) -> float:
	var v := hand_value(game, card)
	if v <= 0.0:
		return -1.0
	if card.mana_value() > energy_count + 3:
		v *= 0.6
	return v
