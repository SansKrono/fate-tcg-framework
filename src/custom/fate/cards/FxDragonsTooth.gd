# Dragon's Tooth (Primal relic): "Enters attached to a creature of your choice; it gains Savage 1".
# Enters equipped to a creature of your choice (game.equip.equip; the pick goes through game.choices, your own
# creatures, the first one by default; with no creature it stays unequipped and does nothing). The creature has Savage 1 as long as the relic is on it.
extends "res://src/custom/fate/cards/FateCardEffect.gd"



func _init() -> void:
	card_name = "Dragon's Tooth"


func on_enter(card: Card) -> void:
	if game.equip.host_of(card) != null:
		return
	var options: Array = creatures_of(card.controller_id).filter(func(c): return c.controller_id == card.controller_id)
	if options.is_empty():
		return
	var picked = await choose(card, card.controller_id, "creature to equip", options)
	if picked != null:
		game.equip.equip(card, picked)


func static_keywords(host: Card, target: Card) -> Dictionary:
	if game.equip.host_of(host) != target:
		return {}
	return {"Savage": 1}


func ai_intent(_request: Dictionary) -> String:
	return "help"
