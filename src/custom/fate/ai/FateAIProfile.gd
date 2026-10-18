# The personality and strength of one AI seat: weights the planners read. Create one with
# `profile.configure(domains, level)` (the presets) and change any field afterwards.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

enum Level { EASY, NORMAL, HARD }

var level: int = Level.NORMAL
var label := "normal"

# --- strategy ------------------------------------------------------------------------------------
# How much damage to the opponent's life is worth next to creatures (1 = even, more = aggro)
var aggression := 1.0
# How much of the opponent's counter-attack is held against an attack plan (0 = ignore it)
var caution := 0.6
# The number of energy cards the deck wants before it draws extra cards instead
var energy_target := 5
# Never play energy beyond this many (cards are better in hand)
var max_energy := 8
# Keep mana open for reaction spells in hand during the main phase
var hold_reactions := true
# Scales the value of holding and casting reactions
var reaction_weight := 1.0
# Use Embody when there is spare mana (needs `embody_min_value` mana value on the energy card)
var use_embody := true
var embody_min_value := 3
# Do not embody below this many energy cards
var embody_keep_energy := 4

# --- strength ------------------------------------------------------------------------------------
# Random jitter added to the scores of the choices (0 = always the best one)
var noise := 0.0
# How many creature targets (besides the player) each attacker is tried against
var think_width := 3
# The AI may look at the opponent's hand (never in a real game)
var cheat := false

# --- presentation --------------------------------------------------------------------------------
# Seconds between two visible actions (0 = as fast as possible, what tests use)
var pace := 0.45
var rng := RandomNumberGenerator.new()


# Fills the fields from the deck's domains and the strength level. The idea of each deck is in
# docs/FATE_TCG_DESIGN.md Section 17.4: Order is a wide, aggressive army with a low curve, Primal ramps
# to big beasts and Embody.
func configure(domains: Array, new_level: int = Level.NORMAL, seed_value := 0) -> void:
	level = new_level
	if "Order" in domains:
		aggression = 1.2
		caution = 0.5
		energy_target = 5
		use_embody = false
	elif "Primal" in domains:
		aggression = 0.9
		caution = 0.7
		energy_target = 6
	elif "Chaos" in domains:
		aggression = 1.0
		energy_target = 5
	elif "Innovation" in domains:
		aggression = 0.9
		energy_target = 6
	match level:
		Level.EASY:
			label = "easy"
			noise = 2.5
			think_width = 1
			caution *= 0.4
			hold_reactions = false
		Level.HARD:
			label = "hard"
			noise = 0.0
			think_width = 4
		_:
			label = "normal"
			noise = 0.0
			think_width = 3
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
