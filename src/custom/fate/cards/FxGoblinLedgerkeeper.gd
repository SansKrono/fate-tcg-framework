# Goblin Ledgerkeeper (Innovation, 0/1 placeholder stats): "Occupy: create a scrap token".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Goblin Ledgerkeeper"


func actions(card: Card) -> Array:
	return [make_action(card, "scrap", "Scrap", "Occupy: create a scrap token",
			[game.costs.occupy()],
			func(c): game.tokens.add(c.controller_id, "scrap", 1))]
