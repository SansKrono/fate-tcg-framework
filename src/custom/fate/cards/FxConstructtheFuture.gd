# Construct the Future (doctrine I1): create a scrap token at the beginning of your turn (upkeep = the maintenance phase).
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Construct the Future"

func on_phase(card: Card, active_id: int, phase: int) -> void:
	if is_my_turn_start(card, active_id, phase) and active(card):
		game.tokens.add(card.controller_id, "scrap", 1)
