# The personality and strength of one AI seat: every number the planners read lives here.
#
# A profile is a bag of named PARAMS (see the table below: default, range, group, what it does). The table is
# the single source of truth: the fields of this object are created from it, `set_param` clamps to it, the
# simulation lab sweeps it and a designer can read it as documentation.
#
# A profile is built in layers, each one overriding the previous (resolve()):
#   1. the defaults of PARAMS
#   2. the GRADE (how well it plays): novice, easy, normal, hard, expert, or any `skill` between 0 and 1.
#      A grade sets the "foresight" group (noise, search width, look-ahead, slips) and nothing else.
#   3. the STYLE (how it likes to play): the style of the deck's domain unless one is named; "aggro",
#      "control", "ramp", "engine", "thief", "balanced" ... Styles change the "strategy", "value", "mana"
#      groups.
#   4. explicit overrides, a Dictionary {param: value} (a JSON file, a command line option, a test)
#
# A SPEC is any way of asking for a profile (resolve() takes all of them):
#   int        a Level (0 easy, 1 normal, 2 hard, 3 expert, 4 novice), what set_ai(seat, true, level) passes
#   String     "hard", "hard+aggro", "0.7+ramp", "hard+aggro;aggression=1.4;caution=0.3", or the name of
#              a profile file (res://ai_profiles/<name>.json, user://ai_profiles/<name>.json, or a path)
#   Dictionary {"grade": "hard", "skill": 0.7, "style": "ramp", "params": {...}, "label": "..."}
#
# No class_name (see FateAIEval.gd).
extends RefCounted

enum Level { EASY, NORMAL, HARD, EXPERT, NOVICE }

const PROFILE_DIRS := ["res://ai_profiles", "user://ai_profiles"]

# --- the parameters --------------------------------------------------------------------------------------
# name -> {"def": default, "min", "max", "group", "doc"}. Booleans have no range.
#
# Groups:  foresight  how well it sees (set by the grade)
#          strategy   how it trades life, creatures and risk
#          value      what things are worth (creatures, keywords, life, hand cards)
#          mana       energy, curve, spending, holding mana
#          combat     attack, guard and block habits
#          ability    activated abilities, embody, forced blocks
#          domain     knobs for the mechanics of one domain
const PARAMS := {
	# --- foresight -------------------------------------------------------------------------------------
	"noise": {"def": 0.0, "min": 0.0, "max": 8.0, "group": "foresight",
			"doc": "Random jitter (in points) added to the scores of blocks, choices and energy picks. 0 = always the best option"},
	"think_width": {"def": 3, "min": 1, "max": 8, "group": "foresight",
			"doc": "How many creature targets (besides the player) each attacker is tried against"},
	"lookahead": {"def": 1, "min": 0, "max": 2, "group": "foresight",
			"doc": "Turns the attack plan looks ahead: 0 = only this combat, 1 = also the opponent's counter-attack, 2 = also its own follow-up attack"},
	"mistake_rate": {"def": 0.0, "min": 0.0, "max": 1.0, "group": "foresight",
			"doc": "Chance per decision point of a slip: missing lethal, forgetting a reaction, leaving an attack unblocked, dropping the best play"},
	"search_items": {"def": 12, "min": 3, "max": 12, "group": "foresight",
			"doc": "Cards of the hand the main phase subset search looks at (the best by value; 2^n subsets)"},
	"search_sweeps": {"def": 2, "min": 1, "max": 3, "group": "foresight",
			"doc": "Passes of the block search (and refinement passes of the attack plan)"},
	"reaction_fear": {"def": 0.0, "min": 0.0, "max": 1.0, "group": "foresight",
			"doc": "How much of an attack's gain is discounted for tricks the opponent may hold (needs open mana and cards in its hand)"},
	"cheat": {"def": false, "group": "foresight",
			"doc": "The AI may look at the opponent's hand (testing only, never in a real game)"},
	# --- strategy --------------------------------------------------------------------------------------
	"aggression": {"def": 1.0, "min": 0.2, "max": 3.0, "group": "strategy",
			"doc": "How much damage to the opponent's life is worth next to creatures (1 = even, more = aggro)"},
	"caution": {"def": 0.6, "min": 0.0, "max": 2.0, "group": "strategy",
			"doc": "How much of the opponent's counter-attack is held against an attack plan (0 = ignore it)"},
	"life_weight": {"def": 1.0, "min": 0.3, "max": 3.0, "group": "strategy",
			"doc": "Multiplier on the value of the AI's own life (self-preservation)"},
	"preserve_value": {"def": 1.0, "min": 0.3, "max": 3.0, "group": "strategy",
			"doc": "Multiplier on the value of the AI's own creatures: high = avoids trades and losses"},
	"kill_value": {"def": 1.0, "min": 0.3, "max": 3.0, "group": "strategy",
			"doc": "Multiplier on the value of the opponent's creatures: high = seeks trades and removal"},
	"attack_margin": {"def": 0.05, "min": 0.0, "max": 3.0, "group": "strategy",
			"doc": "An attack plan must beat staying home by this many points (high = passive)"},
	"guard_reserve": {"def": 0, "min": 0, "max": 6, "group": "strategy",
			"doc": "Creatures that always stay home to guard, unless the attack is lethal"},
	# --- value -----------------------------------------------------------------------------------------
	"w_strike": {"def": 1.0, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of a point of Strike"},
	"w_guard": {"def": 0.85, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of a point of Guard"},
	"w_mv": {"def": 0.45, "min": 0.0, "max": 2.0, "group": "value", "doc": "Worth of a point of mana value of a creature (what it cost)"},
	"w_savage": {"def": 1.1, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of a point of Savage"},
	"w_indomitable": {"def": 1.5, "min": 0.0, "max": 4.0, "group": "value", "doc": "Worth of Indomitable"},
	"w_untethered": {"def": 0.4, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of Untethered"},
	"w_unblockable": {"def": 0.9, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of Unblockable (times the creature's Strike)"},
	"w_cannot_block": {"def": 0.25, "min": 0.0, "max": 2.0, "group": "value", "doc": "Penalty of Cannot block (times the creature's Guard)"},
	"w_charge": {"def": 0.4, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of Charge"},
	"w_productive": {"def": 0.2, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of Productive"},
	"w_unique": {"def": 0.8, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of a unique (legendary) creature"},
	"w_ability": {"def": 0.0, "min": 0.0, "max": 3.0, "group": "value",
			"doc": "Extra worth of a creature in play that has an activated ability (an engine)"},
	"w_token": {"def": 1.0, "min": 0.2, "max": 2.0, "group": "value", "doc": "Multiplier on the worth of token creatures"},
	"life_slope": {"def": 1.4, "min": 0.2, "max": 4.0, "group": "value", "doc": "Worth of a point of life"},
	"life_danger_at": {"def": 7, "min": 2, "max": 10, "group": "value", "doc": "Below this life total each point is worth more"},
	"life_danger_curve": {"def": 0.12, "min": 0.0, "max": 0.5, "group": "value", "doc": "How steeply the worth of life rises below the danger line"},
	"doctrine_pursuit": {"def": 0.0, "min": 0.0, "max": 3.0, "group": "value",
			"doc": "Bonus for plays that advance or complete the goal of a doctrine that is not achieved yet"},
	"effect_gain_weight": {"def": 1.0, "min": 0.0, "max": 2.0, "group": "value",
			"doc": "Weight of the simulated gain of a pump, removal or buff spell (what-if on the attack plan) next to its flat value"},
	"pump_min_attackers": {"def": 1, "min": 0, "max": 3, "group": "value",
			"doc": "A buff spell is only cast with at least this many creatures that attack because of it"},
	"removal_min_target": {"def": 3.0, "min": 0.0, "max": 8.0, "group": "value",
			"doc": "A removal spell is only cast on a creature worth at least this much (otherwise it is kept for a better one)"},
	"steal_value": {"def": 1.0, "min": 0.3, "max": 3.0, "group": "domain",
			"doc": "Chaos: multiplier on the worth of taking control of a creature (Unseen Manipulator, Claimed by the Abyss, Double Agent)"},
	"evasion_cap": {"def": 99.0, "min": 1.0, "max": 99.0, "group": "domain",
			"doc": "Unblockable is worth this much Strike at most (an unblocked hit takes 1 life whatever the Strike, so 1-2 suits Chaos)"},
	"sacrifice_willingness": {"def": 0.5, "min": 0.0, "max": 1.0, "group": "domain",
			"doc": "Chaos / Order: how readily it consumes or sacrifices its own creatures and energy cards for an effect"},
	"flip_cast_bias": {"def": 1.0, "min": 0.0, "max": 3.0, "group": "domain",
			"doc": "Chaos: worth of the energy zone as a second hand (flip casts, keeping expensive creatures as energy)"},
	"creature_value": {"def": 1.0, "min": 0.2, "max": 3.0, "group": "value", "doc": "Worth of creature cards in hand"},
	"spell_value": {"def": 1.0, "min": 0.2, "max": 3.0, "group": "value", "doc": "Worth of spells, relics and field / world spells in hand"},
	"reaction_value": {"def": 1.0, "min": 0.0, "max": 3.0, "group": "value", "doc": "Worth of reaction spells in hand"},
	"engine_value": {"def": 0.0, "min": 0.0, "max": 4.0, "group": "value",
			"doc": "Extra worth of a creature or relic card in hand whose script has an activated ability or a trigger (an engine piece)"},
	# --- mana ------------------------------------------------------------------------------------------
	"energy_target": {"def": 5, "min": 2, "max": 12, "group": "mana", "doc": "Energy cards the deck wants before it draws extra cards instead"},
	"max_energy": {"def": 8, "min": 3, "max": 14, "group": "mana", "doc": "Never play energy beyond this many"},
	"ramp_bias": {"def": 0.0, "min": 0.0, "max": 3.0, "group": "mana",
			"doc": "Extra energy wanted per card in hand that costs more than the energy in play"},
	"mana_use_weight": {"def": 0.03, "min": 0.0, "max": 1.0, "group": "mana",
			"doc": "Bonus per mana spent when choosing plays (high = spends all its mana every turn)"},
	"draw_bias": {"def": 0.0, "min": -3.0, "max": 3.0, "group": "mana",
			"doc": "Positive = prefers drawing over playing energy (lowers the energy target), negative = prefers energy"},
	"energy_lookahead": {"def": 1, "min": 1, "max": 4, "group": "mana",
			"doc": "Wants another energy card while a card of the hand costs at most this many more than the energy in play (1 = only when it makes a card castable now; higher = ramps toward bombs)"},
	"deck_safety": {"def": 4, "min": 0, "max": 10, "group": "mana",
			"doc": "Never draws extra (or lets effects draw) with fewer cards than this left in the deck"},
	"deck_race": {"def": true, "group": "mana",
			"doc": "In a stall, does not draw extra cards when its deck is about to run out first (an empty deck loses)"},
	"produce_mana_first": {"def": true, "group": "mana",
			"doc": "Uses abilities that make mana or energy (Elder Spirit, Ancient Tree) before casting cards"},
	"hold_reactions": {"def": true, "group": "mana", "doc": "Keep mana open for reaction spells in hand during the main phase"},
	"reaction_weight": {"def": 1.0, "min": 0.0, "max": 3.0, "group": "mana", "doc": "Scales the value of holding and casting reactions"},
	"opp_attack_prior": {"def": 0.3, "min": 0.0, "max": 0.6, "group": "mana",
			"doc": "Chance, per opposing creature, that the opponent attacks next turn (how much mana is held for reactions)"},
	"max_held_per_name": {"def": 1, "min": 1, "max": 3, "group": "mana",
			"doc": "Copies of the same reaction spell mana is held for at the same time"},
	"reaction_price": {"def": 1.0, "min": 0.0, "max": 3.0, "group": "mana",
			"doc": "Scales what a reaction spell must gain before it is cast (high = saves it for a big moment)"},
	# --- combat ----------------------------------------------------------------------------------------
	"chump_block": {"def": 1.0, "min": 0.0, "max": 3.0, "group": "combat",
			"doc": "Willingness to give up creatures to save life when defending (scales the worth of own life when blocking)"},
	# --- ability ---------------------------------------------------------------------------------------
	"ability_margin": {"def": 0.5, "min": 0.0, "max": 3.0, "group": "ability",
			"doc": "An ability whose effect the AI can simulate (a pump, a removal) must gain this many points to be used"},
	"energy_card_value": {"def": 2.0, "min": 0.0, "max": 5.0, "group": "ability",
			"doc": "Price of one energy card consumed to pay an ability (Devote Paladin, Faithful Worshiper)"},
	"spare_energy_floor": {"def": 4, "min": 0, "max": 10, "group": "ability",
			"doc": "Energy cards kept back before any is consumed for an ability"},
	"ability_rounds": {"def": 3, "min": 1, "max": 6, "group": "ability",
			"doc": "Passes over the abilities of the table per turn (each pass sees the counters the last one made: scrap, then ingot, then payoff)"},
	"scrap_burn": {"def": true, "group": "ability",
			"doc": "Fire a Scrap Cannon with every scrap that is not needed (all of it for lethal) instead of one shot per cannon and round"},
	"burn_reserve": {"def": 2, "min": 0, "max": 12, "group": "ability",
			"doc": "Scrap kept back for the engine (ingots) when burning the rest at the opponent's life; lethal ignores it"},
	"use_evolve": {"def": true, "group": "ability", "doc": "Use Evolve (Beetle Brawler into Ironside Beetle) when it gains"},
	"flip_before_attack": {"def": true, "group": "ability",
			"doc": "Flips energy-zone creatures (Teshra, Guardian Spirits) before the attack plan so they can attack"},
	"use_embody": {"def": true, "group": "ability", "doc": "Use Embody when there is spare mana"},
	"embody_min_value": {"def": 3, "min": 1, "max": 8, "group": "ability", "doc": "Embody needs an energy card of at least this mana value"},
	"embody_keep_energy": {"def": 4, "min": 0, "max": 10, "group": "ability", "doc": "Do not embody below this many energy cards"},
	"ability_use": {"def": true, "group": "ability", "doc": "Use the activated abilities of card scripts that are cheap and safe"},
	"ability_risk": {"def": true, "group": "ability",
			"doc": "Also use abilities that give up cards or creatures as a cost (consume, discard, return to hand)"},
	# --- presentation ----------------------------------------------------------------------------------
	"pace": {"def": 0.45, "min": 0.0, "max": 5.0, "group": "presentation",
			"doc": "Seconds between two visible actions (0 = as fast as possible, what tests use)"},
}

# --- grades ------------------------------------------------------------------------------------------
# The foresight group at each grade, and the "knowledge" switches (does it value effects by simulation, chain
# abilities in rounds, evolve, flip, pursue doctrines, ramp toward bombs, race decks). A skill between two grades interpolates (numbers) or takes the lower one
# (booleans). Skill of a Level: GRADE_SKILL.
const GRADE_NAMES := ["novice", "easy", "normal", "hard", "expert"]
const GRADE_SKILL := {"novice": 0.0, "easy": 0.25, "normal": 0.5, "hard": 0.75, "expert": 1.0}
const GRADES := {
	"novice": {"noise": 4.0, "think_width": 1, "lookahead": 0, "mistake_rate": 0.30, "search_items": 6,
			"search_sweeps": 1, "reaction_fear": 0.0, "hold_reactions": false, "caution_scale": 0.2,
			"effect_gain_weight": 0.0, "ability_rounds": 1, "doctrine_pursuit": 0.0, "produce_mana_first": false, "use_evolve": false, "flip_before_attack": false, "ability_risk": false, "energy_lookahead": 1, "deck_race": false, "scrap_burn": false},
	"easy": {"noise": 2.5, "think_width": 1, "lookahead": 0, "mistake_rate": 0.12, "search_items": 8,
			"search_sweeps": 1, "reaction_fear": 0.0, "hold_reactions": false, "caution_scale": 0.4,
			"effect_gain_weight": 0.0, "ability_rounds": 1, "doctrine_pursuit": 0.0, "produce_mana_first": false, "use_evolve": false, "flip_before_attack": false, "ability_risk": false, "energy_lookahead": 1, "deck_race": false, "scrap_burn": false},
	"normal": {"noise": 0.0, "think_width": 3, "lookahead": 1, "mistake_rate": 0.0, "search_items": 12,
			"search_sweeps": 2, "reaction_fear": 0.0, "hold_reactions": true, "caution_scale": 1.0,
			"effect_gain_weight": 1.0, "ability_rounds": 3, "doctrine_pursuit": 1.0, "produce_mana_first": true, "use_evolve": true, "flip_before_attack": true, "ability_risk": true, "energy_lookahead": 1, "deck_race": true},
	"hard": {"noise": 0.0, "think_width": 4, "lookahead": 1, "mistake_rate": 0.0, "search_items": 12,
			"search_sweeps": 2, "reaction_fear": 0.25, "hold_reactions": true, "caution_scale": 1.0,
			"effect_gain_weight": 1.0, "ability_rounds": 4, "doctrine_pursuit": 1.0, "produce_mana_first": true, "use_evolve": true, "flip_before_attack": true, "ability_risk": true, "energy_lookahead": 2, "deck_race": true},
	"expert": {"noise": 0.0, "think_width": 5, "lookahead": 2, "mistake_rate": 0.0, "search_items": 12,
			"search_sweeps": 3, "reaction_fear": 0.5, "hold_reactions": true, "caution_scale": 1.0,
			"effect_gain_weight": 1.0, "ability_rounds": 5, "doctrine_pursuit": 1.0, "produce_mana_first": true, "use_evolve": true, "flip_before_attack": true, "ability_risk": true, "energy_lookahead": 2, "deck_race": true},
}

# --- styles ------------------------------------------------------------------------------------------
# name -> {param: value}. The style of a deck's domain is applied unless the spec names another one.
const STYLES := {
	"balanced": {},
	"aggro": {"aggression": 1.3, "caution": 0.4, "attack_margin": 0.0, "kill_value": 1.1, "mana_use_weight": 0.08},
	"control": {"aggression": 0.8, "caution": 0.9, "life_weight": 1.2, "preserve_value": 1.2, "attack_margin": 0.4,
			"guard_reserve": 1, "reaction_weight": 1.3, "energy_target": 6},
	"ramp": {"aggression": 0.9, "caution": 0.7, "energy_target": 6, "ramp_bias": 0.6, "max_energy": 9},
	"engine": {"aggression": 0.9, "caution": 0.7, "energy_target": 6, "engine_value": 1.2, "w_ability": 0.6,
			"ability_risk": true},
	"thief": {"aggression": 1.0, "caution": 0.6, "kill_value": 1.15},
	# The AI as it was before the card-knowledge features: flat card values, abilities only when their costs are
	# safe and used once after the attack plan, no mana makers / Evolve / flips first. For A/B tests.
	"legacy": {"effect_gain_weight": 0.0, "produce_mana_first": false, "ability_rounds": 1, "use_evolve": false,
			"flip_before_attack": false, "ability_risk": false, "doctrine_pursuit": 0.0, "energy_lookahead": 1,
			"ramp_bias": 0.0, "engine_value": 0.0, "w_ability": 0.0, "opp_attack_prior": 0.3, "mana_use_weight": 0.03,
			"deck_race": false, "scrap_burn": false, "max_held_per_name": 3},
}
# The style each domain plays when none is named
const DOMAIN_STYLE := {"Order": "aggro", "Primal": "ramp", "Chaos": "thief", "Innovation": "engine"}
# Fixed per-domain adjustments applied with the domain style (the oldest hand-tuned values)
const DOMAIN_FIXED := {
	"Order": {"aggression": 1.2, "caution": 0.5, "energy_target": 5, "use_embody": false},
	"Primal": {"aggression": 0.9, "caution": 0.7, "energy_target": 6},
	"Chaos": {"aggression": 1.0, "energy_target": 5},
	"Innovation": {"aggression": 0.9, "energy_target": 7, "max_energy": 10},
}

# --- the fields --------------------------------------------------------------------------------------
# Declared by hand (typed, fast to read in the planners); _init() fills them from PARAMS and
# test_fate_ai_profile.gd checks both lists agree.
var noise: float
var think_width: int
var lookahead: int
var mistake_rate: float
var search_items: int
var search_sweeps: int
var reaction_fear: float
var cheat: bool
var aggression: float
var caution: float
var life_weight: float
var preserve_value: float
var kill_value: float
var attack_margin: float
var guard_reserve: int
var w_strike: float
var w_guard: float
var w_mv: float
var w_savage: float
var w_indomitable: float
var w_untethered: float
var w_unblockable: float
var w_cannot_block: float
var w_charge: float
var w_productive: float
var w_unique: float
var w_ability: float
var w_token: float
var life_slope: float
var life_danger_at: int
var life_danger_curve: float
var creature_value: float
var spell_value: float
var reaction_value: float
var engine_value: float
var energy_target: int
var max_energy: int
var ramp_bias: float
var mana_use_weight: float
var hold_reactions: bool
var reaction_weight: float
var reaction_price: float
var opp_attack_prior: float
var max_held_per_name: int
var chump_block: float
var use_embody: bool
var embody_min_value: int
var embody_keep_energy: int
var ability_use: bool
var ability_risk: bool
var pace: float
var draw_bias: float
var energy_lookahead: int
var deck_safety: int
var produce_mana_first: bool
var deck_race: bool
var doctrine_pursuit: float
var effect_gain_weight: float
var pump_min_attackers: int
var removal_min_target: float
var steal_value: float
var evasion_cap: float
var sacrifice_willingness: float
var flip_cast_bias: float
var ability_margin: float
var energy_card_value: float
var spare_energy_floor: int
var ability_rounds: int
var scrap_burn: bool
var burn_reserve: int
var use_evolve: bool
var flip_before_attack: bool

# What this profile is, for logs and reports: "hard+aggro"
var level: int = Level.NORMAL
var label := "normal"
var grade := "normal"
var skill := 0.5
var style := "balanced"
var domains: Array = []
# Every parameter that was set away from the layers below (explicit overrides), for to_dict()
var overrides := {}
var rng := RandomNumberGenerator.new()
# Set by the planners while a card resolves: the unit uids (creatures) its effect should pick, so the chooser does
# what the what-if assumed (FateAIWhatIf). Empty = no opinion.
var focus: Array = []

# The valuation weights the evaluation reads (FateAIEval): rebuilt by eval_weights() when a param changed
var _eval_w: Dictionary = {}


func _init() -> void:
	reset()


# Every field back to its default
func reset() -> void:
	for key in PARAMS:
		set(key, PARAMS[key].def)
	overrides = {}
	_eval_w = {}


# --- reading and writing params ---------------------------------------------------------------------

static func has_param(key: String) -> bool:
	return PARAMS.has(key)


# The value clamped to the range of the parameter and made the right type. Unknown names return null.
static func clean(key: String, value):
	if not PARAMS.has(key):
		return null
	var spec: Dictionary = PARAMS[key]
	var def = spec.def
	if def is bool:
		if value is String:
			return value.strip_edges().to_lower() in ["true", "1", "yes", "on"]
		return bool(value)
	var n: float = float(value)
	n = clampf(n, float(spec.min), float(spec.max))
	return int(round(n)) if def is int else n


# Sets one parameter (clamped). Returns false for an unknown name.
func set_param(key: String, value) -> bool:
	if not PARAMS.has(key):
		return false
	set(key, clean(key, value))
	overrides[key] = get(key)
	_eval_w = {}
	return true


func get_param(key: String):
	return get(key) if PARAMS.has(key) else null


# Sets many parameters; returns the names that were not parameters
func apply(values: Dictionary) -> Array:
	var unknown: Array = []
	for key in values:
		if not set_param(str(key), values[key]):
			unknown.append(str(key))
	return unknown


# The parameters that differ from their defaults, and everything when `all`
func to_dict(all := false) -> Dictionary:
	var out := {}
	for key in PARAMS:
		if all or get(key) != PARAMS[key].def:
			out[key] = get(key)
	return out


# The evaluation weights (FateAIEval.DEFAULT_W has the same keys): creature, keyword and life worth, and the
# strategy multipliers that scale them
func eval_weights() -> Dictionary:
	if _eval_w.is_empty():
		_eval_w = {
			"w_strike": w_strike, "w_guard": w_guard, "w_mv": w_mv, "w_savage": w_savage,
			"w_indomitable": w_indomitable, "w_untethered": w_untethered, "w_unblockable": w_unblockable,
			"w_cannot_block": w_cannot_block, "w_charge": w_charge, "w_productive": w_productive,
			"w_unique": w_unique, "w_ability": w_ability, "w_token": w_token,
			"life_slope": life_slope, "life_danger_at": float(life_danger_at), "life_danger_curve": life_danger_curve,
			"life_weight": life_weight, "preserve_value": preserve_value, "kill_value": kill_value,
			"creature_value": creature_value, "spell_value": spell_value, "reaction_value": reaction_value,
			"engine_value": engine_value, "steal_value": steal_value, "evasion_cap": evasion_cap,
		}
	return _eval_w


# True with the probability `mistake_rate`: this decision point is a slip
func slips() -> bool:
	return mistake_rate > 0.0 and rng.randf() < mistake_rate


# --- building a profile -----------------------------------------------------------------------------

# The classic call: the strength level and the personality of the deck's domains. Tests and the older
# callers use it; resolve() is the general one.
func configure(new_domains: Array, new_level: int = Level.NORMAL, seed_value := 0) -> void:
	resolve(new_level, new_domains, seed_value)


# Builds this profile from a spec (see the top of the file) for a deck of `new_domains`. `seed_value` seeds the
# profile's random numbers (0 = random).
func resolve(spec, new_domains: Array = [], seed_value := 0) -> void:
	reset()
	domains = new_domains.duplicate()
	var parsed := parse_spec(spec)
	level = parsed.level
	# 2. the grade
	apply_skill(parsed.skill)
	grade = parsed.grade
	# 3. the style
	var style_name: String = parsed.style
	var base_caution_scale: float = float(_grade_value(parsed.skill, "caution_scale"))
	var from_domain := style_name == ""
	if from_domain:
		style_name = domain_style(domains)
	apply_style(style_name)
	if from_domain:
		# The hand-tuned numbers of the deck's domain win over the generic style
		var fixed := domain_fixed(domains)
		for key in fixed:
			set(key, clean(key, fixed[key]))
	style = style_name
	caution *= base_caution_scale
	# 4. explicit overrides
	var unknown := apply(parsed.params)
	if not unknown.is_empty():
		push_warning("FateAIProfile: unknown parameters %s" % str(unknown))
	label = parsed.label if parsed.label != "" else _make_label(parsed)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_eval_w = {}


# The style of a domain list: the first domain that has one
static func domain_style(for_domains: Array) -> String:
	for d in for_domains:
		if DOMAIN_STYLE.has(d):
			return DOMAIN_STYLE[d]
	return "balanced"


static func domain_fixed(for_domains: Array) -> Dictionary:
	for d in for_domains:
		if DOMAIN_FIXED.has(d):
			return DOMAIN_FIXED[d]
	return {}


func apply_style(style_name: String) -> void:
	var values: Dictionary = STYLES.get(style_name, {})
	for key in values:
		if PARAMS.has(key):
			set(key, clean(key, values[key]))
	_eval_w = {}


# Sets the foresight group for a skill between 0 (novice) and 1 (expert)
func apply_skill(new_skill: float) -> void:
	skill = clampf(new_skill, 0.0, 1.0)
	for key in GRADES["normal"]:
		if PARAMS.has(key):
			set(key, clean(key, _grade_value(skill, key)))
	_eval_w = {}


# The value of a grade key at a skill: linear between the two neighbouring grades; booleans take the lower grade
static func _grade_value(at_skill: float, key: String):
	var names: Array = GRADE_NAMES
	var s := clampf(at_skill, 0.0, 1.0)
	var lo := 0
	for i in range(names.size() - 1):
		if s >= float(GRADE_SKILL[names[i]]):
			lo = i
	var hi := mini(lo + 1, names.size() - 1)
	var a = GRADES[names[lo]][key]
	var b = GRADES[names[hi]][key]
	if a is bool:
		return a if s < float(GRADE_SKILL[names[hi]]) else b
	var span: float = float(GRADE_SKILL[names[hi]]) - float(GRADE_SKILL[names[lo]])
	var t: float = 0.0 if span <= 0.0 else (s - float(GRADE_SKILL[names[lo]])) / span
	return lerpf(float(a), float(b), t)


# The grade name nearest to a skill
static func grade_name(at_skill: float) -> String:
	var best := "normal"
	var best_d := INF
	for g in GRADE_NAMES:
		var d := absf(float(GRADE_SKILL[g]) - at_skill)
		if d < best_d:
			best_d = d
			best = g
	return best


static func level_of_grade(grade_text: String) -> int:
	match grade_text:
		"easy":
			return Level.EASY
		"hard":
			return Level.HARD
		"expert":
			return Level.EXPERT
		"novice":
			return Level.NOVICE
	return Level.NORMAL


static func grade_of_level(lv: int) -> String:
	match lv:
		Level.EASY:
			return "easy"
		Level.HARD:
			return "hard"
		Level.EXPERT:
			return "expert"
		Level.NOVICE:
			return "novice"
	return "normal"


func _make_label(parsed: Dictionary) -> String:
	var text: String = parsed.grade if parsed.skill_text == "" else parsed.skill_text
	if parsed.style != "":
		text += "+" + parsed.style
	if not parsed.params.is_empty():
		text += "*"
	return text


# --- specs ------------------------------------------------------------------------------------------

# Turns any spec into {"level", "grade", "skill", "skill_text", "style", "params", "label"}
static func parse_spec(spec) -> Dictionary:
	var out := {"level": Level.NORMAL, "grade": "normal", "skill": 0.5, "skill_text": "", "style": "",
			"params": {}, "label": ""}
	if spec == null:
		return out
	if spec is int or spec is float:
		var lv := clampi(int(spec), 0, 4)
		out.level = lv
		out.grade = grade_of_level(lv)
		out.skill = GRADE_SKILL[out.grade]
		return out
	if spec is Dictionary:
		var d: Dictionary = spec
		if d.has("grade"):
			_set_grade(out, str(d.grade))
		if d.has("level"):
			out = _merge_spec(out, parse_spec(int(d.level)))
		if d.has("skill"):
			_set_skill(out, float(d.skill))
		out.style = str(d.get("style", ""))
		out.label = str(d.get("label", ""))
		var p = d.get("params", {})
		if p is Dictionary:
			out.params = p.duplicate()
		return out
	var text := str(spec).strip_edges()
	if text == "":
		return out
	# A file of profiles
	if text.ends_with(".json") or _file_for(text) != "":
		var loaded := load_file(text)
		if not loaded.is_empty():
			return parse_spec(loaded)
	var parts := text.split(";")
	var head := parts[0].strip_edges()
	for token in head.split("+"):
		var t := token.strip_edges().to_lower()
		if t == "":
			continue
		if t in GRADE_NAMES:
			_set_grade(out, t)
		elif t.is_valid_float():
			_set_skill(out, float(t))
		elif STYLES.has(t):
			out.style = t
		else:
			var loaded := load_file(t)
			if not loaded.is_empty():
				out = _merge_spec(out, parse_spec(loaded))
			else:
				push_warning("FateAIProfile: unknown part '%s' of the profile '%s'" % [t, text])
	for i in range(1, parts.size()):
		var kv := parts[i].split("=")
		if kv.size() == 2:
			var key := kv[0].strip_edges()
			var raw := kv[1].strip_edges()
			out.params[key] = raw if (PARAMS.has(key) and PARAMS[key].def is bool) else float(raw)
	return out


static func _set_grade(out: Dictionary, grade_text: String) -> void:
	out.grade = grade_text
	out.level = level_of_grade(grade_text)
	out.skill = GRADE_SKILL.get(grade_text, 0.5)
	out.skill_text = ""


static func _set_skill(out: Dictionary, value: float) -> void:
	out.skill = clampf(value, 0.0, 1.0)
	out.grade = grade_name(out.skill)
	out.level = level_of_grade(out.grade)
	out.skill_text = "skill %.2f" % out.skill


static func _merge_spec(base: Dictionary, other: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in ["level", "grade", "skill", "skill_text"]:
		out[key] = other[key]
	if other.style != "":
		out.style = other.style
	if other.label != "":
		out.label = other.label
	out.params.merge(other.params, true)
	return out


# --- profile files ----------------------------------------------------------------------------------

static func _file_for(name_or_path: String) -> String:
	if name_or_path.ends_with(".json") and FileAccess.file_exists(name_or_path):
		return name_or_path
	for dir in PROFILE_DIRS:
		var path := "%s/%s.json" % [dir, name_or_path]
		if FileAccess.file_exists(path):
			return path
	return ""


# A profile spec Dictionary read from `<dir>/<name>.json` or a path; {} when there is no such file
static func load_file(name_or_path: String) -> Dictionary:
	var path := _file_for(name_or_path)
	if path == "":
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("FateAIProfile: %s is not a JSON object" % path)
		return {}
	if not parsed.has("label"):
		parsed["label"] = path.get_file().get_basename()
	return parsed


# The names of the profile files (both folders)
static func file_names() -> Array:
	var found: Array = []
	for dir in PROFILE_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json") and not f.get_basename() in found:
				found.append(f.get_basename())
	found.sort()
	return found


# --- documentation ----------------------------------------------------------------------------------

# A readable table of every parameter (docs and the --ai-params option of the lab)
static func describe() -> String:
	var lines: Array[String] = []
	var groups: Array = []
	for key in PARAMS:
		if not PARAMS[key].group in groups:
			groups.append(PARAMS[key].group)
	for group in groups:
		lines.append("[%s]" % group)
		for key in PARAMS:
			var spec: Dictionary = PARAMS[key]
			if spec.group != group:
				continue
			var range_text := "" if spec.def is bool else " (%s..%s)" % [str(spec.min), str(spec.max)]
			lines.append("  %-20s %s%s  %s" % [key, str(spec.def), range_text, spec.doc])
	return "\n".join(lines)
