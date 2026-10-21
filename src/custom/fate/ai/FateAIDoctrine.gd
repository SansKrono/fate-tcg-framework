# Doctrines for the Fate AI: how much a card of the hand helps its owner reach the goal of a doctrine that is not
# achieved yet (docs/FATE_TCG_DESIGN.md Section 10, FateDoctrines.gd). The reward of a doctrine is large (a free
# soldier every turn, +1/+1 for everybody, Charge, ...), so a play that completes a goal is worth a lot and a play
# that gets closer a little.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

# What a completed goal is worth, in points (profile.doctrine_pursuit scales it)
const REWARD := 3.0


# The bonus of playing `card` for player `pid`: 0 when the profile does not pursue doctrines
static func bonus(game: FateGame, pid: int, card: Card, profile) -> float:
	if profile.doctrine_pursuit <= 0.0 or game.doctrines == null or not game.doctrines.enabled:
		return 0.0
	var total := 0.0
	for doctrine in game.doctrines.doctrine_cards(pid):
		if game.doctrines.achieved(doctrine):
			continue
		var goal: Dictionary = game.doctrines.goal_of(doctrine)
		if goal.is_empty():
			continue
		var need: int = int(goal.n) - game.doctrines.progress(pid, goal)
		if need <= 0:
			continue
		var gives := contribution(game, card, goal)
		if gives <= 0:
			continue
		var frac := minf(1.0, float(gives) / float(need))
		total += reward_value(game, doctrine, pid) * (1.0 if gives >= need else 0.35 * frac)
	return total * profile.doctrine_pursuit


# What achieving this doctrine is worth to the AI: the doctrine script may say (ai_reward_value), else REWARD
static func reward_value(game: FateGame, doctrine: Card, pid: int) -> float:
	var effect = game.card_effects.effect_of(doctrine.canonical_name) if game.card_effects != null else null
	if effect != null and effect.has_method("ai_reward_value"):
		var stated: float = effect.ai_reward_value(doctrine, pid)
		if stated >= 0.0:
			return stated
	return REWARD


# How much a card played from the hand adds to the number a goal counts (the goal kind says: FateDoctrines)
static func contribution(game: FateGame, card: Card, goal: Dictionary) -> int:
	return game.doctrines.contribution(card, goal)
