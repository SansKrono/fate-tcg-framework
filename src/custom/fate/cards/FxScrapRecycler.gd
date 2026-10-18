# Scrap Recycler (Innovation relic): "Once per turn you may consume a relic. If you do, draw a card".
# Any relic you control, itself and relic tokens included.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Scrap Recycler"


func actions(card: Card) -> Array:
	return [make_action(card, "recycle", "Recycle", "Once per turn, consume a relic: draw a card",
			[game.costs.consume_card(["relics"], Callable(), 1, {"label": "Consume a relic"}),
					game.costs.once_per_turn("recycle")],
			func(c): game.library.draw(c.controller_id, 1))]
