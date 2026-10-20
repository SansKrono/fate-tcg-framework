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

const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Profile := preload("res://src/custom/fate/ai/FateAIProfile.gd")

# The weights every evaluation reads when it is not given a profile's: the defaults of FateAIProfile. A state
# carries the weights of the seat that searches (state.w, set by FateAISnapshot), so two AI seats with
# different profiles do not share numbers.
static var DEFAULT_W: Dictionary = Profile.new().eval_weights()

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
	"Double Agent": 5.0,
}
const REACTION_DEFAULT_VALUE := 2.0
# Cards that take control of a creature: scaled by the steal_value weight
const STEAL_CARDS := ["Unseen Manipulator", "Claimed by the Abyss", "Double Agent", "Harbinger of Krelgar", "Repurpose"]

# Cards that are not creatures or reaction spells but whose effect the engine really runs.
# name -> value of having the card (as a hand card). Empty today: as of docs/FATE_TCG_DESIGN.md
# Section 17 regular spells, relics, field and world spells only cost mana and do nothing, so the AI
# treats them as "dead" and uses them as energy. Add an entry the day a card's effect is
# implemented (and teach FateAIMain how to use it if it needs a target).
# A card the AI cannot read from its script but knows is worth its mana: Scrap Cannon turns every scrap into a point of
# damage to the opponent's life (FateAIAbilities.plan_burn)
const LIVE_EFFECTS := {"Scrap Cannon": 5.0}


# --- life ---------------------------------------------------------------------------------------

# What a life total is worth. Convex: the last points of life matter most. 0 or less is a loss.
static func life_value(life: int, w: Dictionary = DEFAULT_W) -> float:
	if life <= 0:
		return -LOSS
	var v: float = w.life_slope * float(life)
	var danger: int = int(w.life_danger_at)
	if life < danger:
		v -= w.life_danger_curve * float((danger - life) * (danger - life))
	return v


# --- creatures ----------------------------------------------------------------------------------

# What a creature (a unit of the snapshot) is worth. `cur_strike` / `cur_guard` are the stats it has
# in the position being scored (after damage); damage heals at its owner's maintenance, so the value
# leans on the undamaged stats.
static func unit_value(u: Dictionary, cur_strike := -1, cur_guard := -1, w: Dictionary = DEFAULT_W) -> float:
	var cs: int = u.strike if cur_strike < 0 else cur_strike
	var cg: int = u.guard if cur_guard < 0 else cur_guard
	var s: float = 0.7 * float(u.get("full_strike", u.strike)) + 0.3 * float(cs)
	var g: float = 0.7 * float(u.get("full_guard", u.guard)) + 0.3 * float(cg)
	var kw: Dictionary = u.kw
	var v: float = w.w_strike * s + w.w_guard * g + w.w_mv * float(u.mv)
	if kw.has("Savage"):
		v += w.w_savage * float(kw["Savage"])
	if kw.has("Indomitable"):
		v += w.w_indomitable + 0.2 * (s + g)
	if kw.has("Untethered"):
		v += w.w_untethered
	if kw.has("Unblockable"):
		v += w.w_unblockable * minf(s, w.evasion_cap)
	if kw.has("Cannot block"):
		v -= w.w_cannot_block * g
	if kw.has("Charge"):
		v += w.w_charge
	if kw.has("Productive"):
		v += w.w_productive
	if u.get("unique", false):
		v += w.w_unique
	if u.get("ability", false):
		v += w.w_ability
	if u.get("token", false):
		v *= w.w_token
	return maxf(v, 0.2)


# --- positions ----------------------------------------------------------------------------------

# The score of a position for player `me`: the value of their creatures minus the opponent's, plus
# the value of their life minus the opponent's (the latter scaled by state.face_weight, the
# aggression of the profile). `result` is a FateAISim result (stats after damage, who is dead, life);
# pass null to score the snapshot as it is.
static func score(state: Dictionary, result, me: int) -> float:
	var s := 0.0
	var w: Dictionary = state.get("w", DEFAULT_W)
	var overlay: Dictionary = {} if result == null else result.units
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		var o = overlay.get(uid)
		if o != null and o.dead:
			continue
		var v: float = unit_value(u, u.strike if o == null else o.strike, u.guard if o == null else o.guard, w)
		if u.ctrl == me:
			s += v * w.preserve_value
		else:
			s -= v * w.kill_value
	var life: Dictionary = state.life if result == null else result.life
	var opp := 3 - me
	var face: float = state.get("face_weight", 1.0)
	s += life_value(life[me], w) * (w.life_weight if life[me] > 0 else 1.0)
	var opp_term: float = life_value(life[opp], w)
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
		"death_destination", "spell_destination", "spell_destination_for", "on_damage_dealt", "on_card_to_pile",
		"on_card_left", "on_card_dying", "can_attack_card", "energy_alternative", "use_energy_alternative",
		"can_be_targeted_by", "creatures_in_energy", "can_block_as_relic", "token_amount"]


static func script_methods(effect) -> Array:
	return Snapshot.script_methods(effect)


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
# `w` is the weights of the profile (creature_value, spell_value, reaction_value, engine_value).
static func hand_value(game: FateGame, card: Card, w: Dictionary = DEFAULT_W) -> float:
	var effect = game.card_effects.effect_of(card.canonical_name) if game.card_effects != null else null
	var steal: float = w.steal_value if card.canonical_name in STEAL_CARDS else 1.0
	match role(game, card):
		"creature":
			var v := unit_value(pseudo_unit(game, card), -1, -1, w) + 0.3
			if _has_hooks(effect):
				v += 0.6
			return (v * w.creature_value + (w.engine_value if has_engine(effect) else 0.0)) * steal
		"reaction":
			return float(REACTION_VALUE.get(card.canonical_name, REACTION_DEFAULT_VALUE)) * w.reaction_value * steal
		"live":
			var base := _live_value(game, card, effect)
			return (base * w.spell_value + (w.engine_value if has_engine(effect) else 0.0)) * steal
	return 0.0


static func _live_value(game: FateGame, card: Card, effect) -> float:
	if LIVE_EFFECTS.has(card.canonical_name):
		return float(LIVE_EFFECTS[card.canonical_name])
	var hint := spell_hint(game, card)
	if hint >= 0.0:
		return hint
	if effect != null:
		var stated: float = effect.ai_value(card, card.owner_id)
		if stated >= 0.0:
			return stated
	var kind := str(card.properties.get("_spell_kind", ""))
	return 1.5 + (0.8 if kind == "Regular" else 0.5) * float(card.mana_value())


static func has_engine(effect) -> bool:
	return Snapshot.has_engine(effect)


# What a card whose effect hurts its caster as well is worth right now, or -1 when the AI has no special
# knowledge of the card. The AI cannot read an effect, so the known sweepers and self-harming cards are listed
# here (a card script can say better with ai_value): Toll of War / No Where to Hide destroy every creature in
# strike / guard position, theirs AND the AI's; War of Attrition occupies the AI's own creatures; Self-destruction
# makes the caster consume permanents. 0 = never cast.
static func spell_hint(game: FateGame, card: Card) -> float:
	match card.canonical_name:
		"Toll of War", "No Where to Hide":
			var tilted: bool = card.canonical_name == "No Where to Hide"
			var net := 0.0
			for c in game.creatures_in_play():
				var u := Snapshot.unit_of(game, c)
				var hit: bool = (u.pos != "strike") if tilted else (u.pos == "strike")
				if not hit:
					continue
				net += unit_value(u) if u.ctrl != card.owner_id else -unit_value(u)
			return maxf(0.0, 0.9 * net - 0.5)
		"War of Attrition", "Self-destruction":
			return 0.0
	return -1.0


# Does a script define a hook beyond the keyword defaults? (creatures: an enters or activated effect)
static func _has_hooks(effect) -> bool:
	if effect == null:
		return false
	var methods := script_methods(effect)
	for hook in ["on_enter", "on_play", "actions", "on_attack_declared", "on_destroyed", "on_phase",
			"on_attack_resolved", "on_card_destroyed", "on_card_played", "on_flip_cast", "on_leave",
			"on_damage_dealt", "on_blocking", "can_attack_card"]:
		if hook in methods:
			return true
	return false


# How much the player would miss this card if it became an energy card: the lowest is energized
# first. Dead cards are free; expensive cards that are far out of reach lose some of their value.
static func keep_value(game: FateGame, card: Card, energy_count: int, w: Dictionary = DEFAULT_W) -> float:
	var v := hand_value(game, card, w)
	if v <= 0.0:
		return -1.0
	if card.mana_value() > energy_count + 3:
		v *= 0.6
	return v
