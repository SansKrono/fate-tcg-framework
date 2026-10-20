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
		total += REWARD * (1.0 if gives >= need else 0.35 * frac)
	return total * profile.doctrine_pursuit


# How much a card played from the hand adds to the number a goal counts
static func contribution(game: FateGame, card: Card, goal: Dictionary) -> int:
	var type := str(card.properties.get("Type", ""))
	match goal.get("kind", ""):
		"devotion":
			if type == "Creature" or type == "Relic" or str(card.properties.get("_spell_kind", "")) == "Field":
				var letter := ""
				for initial in FateGame.DOMAIN_BY_INITIAL:
					if FateGame.DOMAIN_BY_INITIAL[initial] == str(goal.domain):
						letter = initial
				return str(card.properties.get("Pips", "")).count(letter) if letter != "" else 0
		"count":
			match str(goal.get("what", "")):
				"creature":
					return 1 if type == "Creature" else 0
				"relic":
					return 1 if type == "Relic" else 0
				"energy":
					return 0
		"power":
			if type == "Creature":
				var best := maxi(game.stats.base(card, "Strike"), game.stats.base(card, "Guard"))
				# One creature of that power completes the goal
				return 99 if best >= int(goal.n) else 0
	return 0
