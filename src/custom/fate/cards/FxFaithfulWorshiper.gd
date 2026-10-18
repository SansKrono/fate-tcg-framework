# Faithful Worshiper (Order, 1/1): "Consume a card in your energy zone: your creatures gain Indomitable until EOT".
# Usable in its controller's main phase (any number of times, each use costs an energy card). The creatures it
# affects are the ones its controller has when the ability resolves.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Faithful Worshiper"


func actions(card: Card) -> Array:
	return [make_action(card, "worship", "Worship", "Consume an energy card: your creatures gain Indomitable until end of turn",
			[game.costs.consume_card(["energy"], Callable(), 1, {"label": "Consume an energy card"})],
			func(c):
				for creature in creatures_of(c.controller_id):
					if creature.controller_id == c.controller_id:
						game.stats.grant_keyword(creature, "Indomitable", 1, FateStats.EXPIRY_END_OF_TURN, null))]
