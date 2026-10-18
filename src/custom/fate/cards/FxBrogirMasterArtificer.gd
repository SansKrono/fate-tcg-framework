# Brogir, Master Artificer (Innovation, 3/4): "Productive. Occupy, choose 1: consume scrap -> ingot; or consume
# ingot -> Battle Hammer". Productive is innate (data). The two modes are two hover actions, each paying Occupy
# and its counter. The hammer goes on a creature its controller chooses (as Battle Smith does).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Brogir, Master Artificer"


func actions(card: Card) -> Array:
	return [
		make_action(card, "scrap_to_ingot", "Scrap>Ingot", "Occupy, consume a scrap: create an ingot",
				[game.costs.occupy(), game.costs.counter("scrap", 1)],
				func(c): game.tokens.add(c.controller_id, "ingot", 1)),
		make_action(card, "ingot_to_hammer", "Hammer", "Occupy, consume an ingot: create a Battle Hammer attached to a creature",
				[game.costs.occupy(), game.costs.counter("ingot", 1)],
				func(c):
					var target = await choose(c, c.controller_id, "creature to carry the Battle Hammer",
							creatures_of(c.controller_id))
					if target != null:
						game.tokens.create("Battle Hammer Token", c.controller_id, {"attach_to": target}),
				func(c): return "" if not creatures_of(c.controller_id).is_empty() else "No creature"),
	]


func ai_intent(_request: Dictionary) -> String:
	return "help"
