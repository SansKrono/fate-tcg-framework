# Rarink, Crafty Opportunist (Innovation, 2/2): "Whenever a non-token relic leaves the battlefield, create 2 scrap
# tokens". Any relic, whoever's; it leaves when it goes anywhere off the table (destroyed, consumed, returned, turned
# into energy). Rarink's controller gets the scrap.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Rarink, Crafty Opportunist"


func on_card_left(card: Card, left: Card, _destination: String) -> void:
	if left.properties.get("Type") == "Relic" and not game.tokens.is_token(left):
		game.tokens.add(card.controller_id, "scrap", 2)
