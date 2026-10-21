# Clockwork Sentinel (Innovation, 2/2): "When it is destroyed, create 2 scrap tokens".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Clockwork Sentinel"


func on_destroyed(card: Card, _cause: String, _source) -> void:
	game.tokens.add(card.controller_id, "scrap", 2)
