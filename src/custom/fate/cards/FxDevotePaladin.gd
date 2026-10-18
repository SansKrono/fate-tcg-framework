# Devote Paladin (Order, 4/3): "Tap, consume an energy card: your creatures gain +1 Strike and Savage (1)".
# Until end of turn, for the creatures its controller has when the ability resolves (the Paladin itself too).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Devote Paladin"


func actions(card: Card) -> Array:
	return [make_action(card, "devote", "Devote", "Occupy, consume an energy card: your creatures gain +1 Strike and Savage 1 until end of turn",
			[game.costs.occupy(), game.costs.consume_card(["energy"], Callable(), 1, {"label": "Consume an energy card"})],
			func(c):
				for creature in creatures_of(c.controller_id):
					if creature.controller_id == c.controller_id:
						game.stats.add_modifier(creature, "Strike", 1, FateStats.EXPIRY_END_OF_TURN, null)
						game.stats.grant_keyword(creature, "Savage", 1, FateStats.EXPIRY_END_OF_TURN, null))]

