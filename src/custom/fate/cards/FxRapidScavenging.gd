# Rapid Scavenging (Innovation regular spell): "Create 2 scrap tokens. Draw a card".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Rapid Scavenging"


func resolve(_card: Card, caster_id: int, _choice) -> void:
	game.tokens.add(caster_id, "scrap", 2)
	game.library.draw(caster_id, 1)


func ai_value(_card: Card, _caster_id: int) -> float:
	return 3.5
