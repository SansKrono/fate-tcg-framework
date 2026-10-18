# Teshra's War Gauntlets (Primal unique relic): "Enters equipped to a creature of your choice; it gains Savage 1 and Indomitable when attacking".
# Enters equipped to a creature of your choice (game.equip.equip; the pick goes through game.choices, your own
# creatures, the first one by default; with no creature it stays unequipped and does nothing). The keywords apply only while the creature is an attacker of a declared attack (game.combat.attack_of).
extends "res://src/custom/fate/cards/FateCardEffect.gd"



func _init() -> void:
	card_name = "Teshra's War Gauntlets"


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
	if game.equip.host_of(host) != target or game.combat.attack_of(target) == null:
		return {}
	return {"Savage": 1, "Indomitable": 1}


func ai_intent(_request: Dictionary) -> String:
	return "help"
