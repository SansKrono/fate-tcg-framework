# Reinforcements (Order spell): "Create 2 soldier tokens (1/1)". Fewer if the creature zone is full.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Reinforcements"


func resolve(_card: Card, caster_id: int, _choice) -> void:
	game.tokens.create_many("Soldier Token", caster_id, 2)
