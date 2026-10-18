# Repurpose (Chaos regular spell): "Move target card in a player's discard into your energy zone"
# (face-down, owner unchanged). Candidates: both discard piles, dearest first.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Repurpose"
	has_choice = true


func candidates(card: Card, _caster_id: int) -> Array:
	var found := []
	for pid in game.players:
		for c in FateZones.container("discard", pid).get_all_cards():
			if c != card:
				found.append(c)
	found.sort_custom(func(a, b): return a.mana_value() > b.mana_value())
	return found


func default_choice(card: Card, caster_id: int):
	var options := candidates(card, caster_id)
	return options[0] if not options.is_empty() else null


func play_problem(card: Card, caster_id: int) -> String:
	if candidates(card, caster_id).is_empty():
		return "No card in a discard pile"
	return "" if FateZones.grid("energy", caster_id).find_available_slot() != null else "Your energy zone is full"


func resolve(_card: Card, caster_id: int, choice) -> void:
	if choice != null and is_instance_valid(choice):
		game.library.to_energy(choice, caster_id)


func ai_intent(_request: Dictionary) -> String:
	return "help"
