# Rapid Scavenging (Innovation regular spell): "Create 2 scrap tokens".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Rapid Scavenging"


func resolve(_card: Card, caster_id: int, _choice) -> void:
	game.tokens.add(caster_id, "scrap", 2)


func ai_value(_card: Card, _caster_id: int) -> float:
	return 2.0
