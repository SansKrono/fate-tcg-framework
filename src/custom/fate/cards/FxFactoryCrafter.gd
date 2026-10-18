# Factory Crafter (Innovation, 2/4): "Tap, consume an ingot: create a 3/3 iron automaton token in guard position".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Factory Crafter"


func actions(card: Card) -> Array:
	return [make_action(card, "craft", "Automaton", "Occupy, consume an ingot: create a 3/3 iron automaton in guard position",
			[game.costs.occupy(), game.costs.counter("ingot", 1)],
			func(c): game.tokens.create("Iron Automaton Token", c.controller_id, {"tilted": true}),
			func(c):
				var grid := game.player(c.controller_id).grid("creatures")
				return "" if grid.count_available_slots() > 0 or grid.auto_extend else "No room for the automaton")]
