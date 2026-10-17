# Wave of Fear: "When another player declares attacks, remove any number of target attacking
# creatures from combat". Choice: an array of attacking creatures of an opponent (at least one).
# Default: all of them. The creatures stay in play (FateCombat.remove_from_combat).
extends "res://src/custom/fate/reactions/FateReactionEffect.gd"


func _init() -> void:
	card_name = "Wave of Fear"
	has_choice = true


func problem(caster_id: int) -> String:
	if candidates(caster_id).is_empty():
		return "No opponent has declared an attack"
	return ""


func candidates(caster_id: int) -> Array:
	return opposing_attackers(caster_id)


func default_choice(caster_id: int):
	return candidates(caster_id)


func choice_problem(caster_id: int, choice) -> String:
	var cards := as_cards(choice)
	if cards.is_empty():
		return "Pick at least one attacking creature"
	var allowed := candidates(caster_id)
	for c in cards:
		if not c in allowed:
			return "Only attacking creatures of an opponent can be removed from combat"
	return ""


func resolve(_card: Card, _caster_id: int, choice) -> void:
	for creature in as_cards(choice):
		game.combat.remove_from_combat(creature)
