# Factory Refinery (Innovation relic): "Pay 1, consume a scrap: create an ingot token".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Factory Refinery"


func actions(card: Card) -> Array:
	return [make_action(card, "refine", "Refine", "Pay 1, consume a scrap: create an ingot token",
			[game.costs.mana(1), game.costs.counter("scrap", 1)],
			func(c): game.tokens.add(c.controller_id, "ingot", 1))]
