# Elder Spirit (Primal, 2/2): "Occupy: put the top card of your deck into your energy zone".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Elder Spirit"


func actions(card: Card) -> Array:
	return [make_action(card, "elder_spirit", "Occupy", "Occupy: put the top card of your deck into your energy zone",
			[game.costs.occupy()],
			func(c):
				var top: Array = game.library.look_top(c.controller_id, 1)
				if not top.is_empty():
					game.library.to_energy(top[0], c.controller_id),
			func(c): return "Your deck is empty" if game.library.look_top(c.controller_id, 1).is_empty() else "")]
