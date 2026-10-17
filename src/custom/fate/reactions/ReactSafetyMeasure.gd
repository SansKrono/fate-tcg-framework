# Safety Measure: "Destroy target attacking creature".
# Choice: one attacking creature of an opponent (a Card, or its FateAttack). Default: the declared
# attacker with the highest current Strike, ties by declaration order.
extends "res://src/custom/fate/reactions/FateReactionEffect.gd"


func _init() -> void:
	card_name = "Safety Measure"
	has_choice = true


func problem(caster_id: int) -> String:
	if candidates(caster_id).is_empty():
		return "There is no attacking creature to destroy"
	return ""


func candidates(caster_id: int) -> Array:
	return opposing_attackers(caster_id)


func default_choice(caster_id: int):
	var best: Card = null
	var best_strike := -1
	# Declaration order, and only a strictly higher Strike replaces the pick: ties keep the first
	for attacker in candidates(caster_id):
		var strike: int = game.stats.current(attacker, "Strike")
		if strike > best_strike:
			best = attacker
			best_strike = strike
	return best


func choice_problem(caster_id: int, choice) -> String:
	var cards := as_cards(choice)
	if cards.size() != 1 or not cards[0] in candidates(caster_id):
		return "The target must be one attacking creature of an opponent"
	return ""


func resolve(card: Card, _caster_id: int, choice) -> void:
	game.effects.destroy(as_cards(choice)[0], card, FateEffects.CAUSE_EFFECT)
