# Holy Amulet (Order relic): "Equips to a creature of your choice. Creature gains Occupy: add one Order energy".
# Enters equipped to a creature of the controller's choice (game.choices, the first creature by default). The
# equipped creature's Occupy ability is offered on the amulet's own hover button: it occupies the creature and
# adds 1 floating Order mana until the end of the turn (game.mana.add_floating). The amulet does nothing unequipped.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Holy Amulet"


func on_enter(card: Card) -> void:
	if game.equip.host_of(card) != null:
		return
	var options: Array = creatures_of(card.controller_id).filter(func(c): return c.controller_id == card.controller_id)
	if options.is_empty():
		return
	var picked = await choose(card, card.controller_id, "creature to equip", options)
	if picked != null:
		game.equip.equip(card, picked)


func actions(card: Card) -> Array:
	var occupy_host := {
		"id": "occupy_host", "label": "Occupy",
		"problem": _host_problem, "pay": _host_occupy,
	}
	return [make_action(card, "amulet", "Occupy", "Occupy the equipped creature: add one Order energy for the turn",
			[occupy_host],
			func(c): game.mana.add_floating(c.controller_id, "Order", 1))]


func _host_problem(relic: Card) -> String:
	var host = game.equip.host_of(relic)
	if host == null:
		return "Not equipped"
	return game.keywords.get_keyword("Occupy").occupy_problem(host)


func _host_occupy(relic: Card) -> bool:
	var host = game.equip.host_of(relic)
	return host != null and game.keywords.get_keyword("Occupy").occupy(host)
