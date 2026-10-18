# Maintain Your Presence (doctrine O1): create a 1/1 soldier at the beginning of your turn.
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Maintain Your Presence"

func on_phase(card: Card, active_id: int, phase: int) -> void:
	if is_my_turn_start(card, active_id, phase) and active(card):
		game.tokens.create("Soldier Token", card.controller_id)
