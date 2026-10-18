# Claimed by the Abyss (Chaos regular spell): "Take target creature on any field and place it face-down in
# your energy zone" (a token ceases to exist). Needs a free energy slot.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Claimed by the Abyss"
	has_choice = true


func candidates(_card: Card, caster_id: int) -> Array:
	var found := []
	for pid in game.players:
		for c in creatures_of(pid):
			if game.control.take_problem(c, caster_id, {"zone": "energy"}) == "":
				found.append(c)
	return found


func default_choice(card: Card, caster_id: int):
	var options := candidates(card, caster_id)
	return options[0] if not options.is_empty() else null


func play_problem(card: Card, caster_id: int) -> String:
	return "" if not candidates(card, caster_id).is_empty() else "No creature to claim"


func resolve(_card: Card, caster_id: int, choice) -> void:
	if choice != null and is_instance_valid(choice):
		game.control.take_control(choice, caster_id, {"zone": "energy"})


func ai_intent(_request: Dictionary) -> String:
	return "harm"
