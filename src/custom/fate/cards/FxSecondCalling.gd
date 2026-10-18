# Second Calling (Primal spell): "Return target creature from your discard to the field; it is also a Ghost".
# The creature comes back through game.casting.return_to_table (no cast: on_enter runs, summoning sick), then "Ghost"
# is added to its Tags for as long as the card keeps this copy of its properties (a later trip through a pile
# does not remove it: known limitation). Needs a creature in your discard and a free creature slot.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Second Calling"
	has_choice = true


func play_problem(card: Card, caster_id: int) -> String:
	if game.choices.legal_targets(card, candidates(card, caster_id)).is_empty():
		return "No creature in your discard pile"
	var grid := FateZones.grid("creatures", caster_id)
	return "" if grid != null and grid.find_available_slot() != null else "Your creature zone is full"


func candidates(_card: Card, caster_id: int) -> Array:
	return game.library.search(caster_id, func(c): return c.properties.get("Type") == "Creature", "discard")


func default_choice(card: Card, caster_id: int):
	var options: Array = game.choices.legal_targets(card, candidates(card, caster_id))
	return options[0] if not options.is_empty() else null


func choice_problem(card: Card, caster_id: int, choice) -> String:
	return "" if choice in candidates(card, caster_id) else "Not a creature in your discard pile"


func resolve(card: Card, caster_id: int, choice) -> void:
	if not choice is Card or choice not in candidates(card, caster_id):
		return
	if game.casting.return_to_table(choice, caster_id):
		var tags: Array = choice.properties.get("Tags", []).duplicate()
		if not "Ghost" in tags:
			tags.append("Ghost")
			choice.properties["Tags"] = tags


func ai_intent(_request: Dictionary) -> String:
	return "help"
