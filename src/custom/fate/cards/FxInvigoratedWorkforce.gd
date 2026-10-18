# Invigorated Workforce (Innovation unique field spell): "Creatures with tap abilities can tap as soon as they
# enter your field". Your creatures with an Occupy / Tap ability have Productive while it is on the table.
# Looks at card properties only (static_keywords must not call game.keywords on the target).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Invigorated Workforce"


func static_keywords(host: Card, target: Card) -> Dictionary:
	if target.controller_id != host.controller_id or target.properties.get("Type") != "Creature":
		return {}
	var listed = target.properties.get("_keywords", [])
	if (listed is Array and "Occupy" in listed) or game.keywords.get_keyword("Occupy").has_tap_ability(target):
		return {"Productive": 1}
	return {}
