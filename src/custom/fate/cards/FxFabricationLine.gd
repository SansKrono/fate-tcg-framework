# Fabrication Line (Innovation regular spell): "Create 2 copies of target token you control". The target is a token
# card on your table or a counter kind ("scrap" / "ingot", a String) that you have.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Fabrication Line"
	has_choice = true


func candidates(_card: Card, caster_id: int) -> Array:
	var found: Array = []
	for zone in game.tokens.TOKEN_ZONES:
		for c in game.player(caster_id).cards_in_grid(zone):
			if game.tokens.is_token(c):
				found.append(c)
	for counter_name in game.tokens.COUNTERS:
		if game.tokens.counter(caster_id, counter_name) > 0:
			found.append(counter_name)
	return found


func play_problem(card: Card, caster_id: int) -> String:
	return "" if not candidates(card, caster_id).is_empty() else "You control no token"


func default_choice(card: Card, caster_id: int):
	var all := candidates(card, caster_id)
	return all[0] if not all.is_empty() else null


func choice_problem(card: Card, caster_id: int, choice) -> String:
	return "" if choice in candidates(card, caster_id) else "Not a token you control"


func resolve(_card: Card, caster_id: int, choice) -> void:
	if choice != null:
		game.tokens.copy(choice, caster_id, 2)


func ai_value(_card: Card, _caster_id: int) -> float:
	return 3.0
