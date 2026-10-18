# Garbage Heap (Innovation relic): "Consume this relic: create 2 scrap tokens".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Garbage Heap"


func actions(card: Card) -> Array:
	return [make_action(card, "scrap", "Scrap", "Consume this relic: create 2 scrap tokens",
			[game.costs.consume_self()],
			func(c): game.tokens.add(c.controller_id, "scrap", 2))]
