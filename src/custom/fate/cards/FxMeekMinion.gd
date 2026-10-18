# Meek Minion (Primal, 1/1): "Consume: reduce the cost of the next creature you play by 2".
# Consume this card (main phase); the reduction (game.mana.add_cost_reduction) lowers the generic cost of the
# controller's next creature, never below 0, and stays until that creature is paid for (no time limit in the text).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Meek Minion"


func actions(card: Card) -> Array:
	return [make_action(card, "meek_consume", "Consume", "Consume: the next creature you play costs 2 less",
			[game.costs.consume_self()],
			func(c): game.mana.add_cost_reduction(c.controller_id, 2,
					func(played): return played.properties.get("Type") == "Creature", "", c))]


func ai_intent(_request: Dictionary) -> String:
	return "help"
