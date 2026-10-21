# Debug Card (Debug, 1/1): "Occupy: create a Debug Token".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Debug Card"


func actions(card: Card) -> Array:
	return [make_action(card, "debug", "Debug", "Occupy: create a Debug Token",
			[game.costs.occupy()],
			func(c): game.tokens.create("Debug Token", c.controller_id, {"tilted": true}))]
