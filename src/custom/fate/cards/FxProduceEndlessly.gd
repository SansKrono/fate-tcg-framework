# Produce Endlessly (doctrine I3): whenever you create a token, create an additional one of that kind.
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Produce Endlessly"

# Asked by game.tokens for every creation event (FateTokens.replaced_amount)
func token_amount(host: Card, player_id: int, _kind: String, amount: int) -> int:
	return amount + 1 if amount > 0 and active(host) and player_id == host.controller_id else amount
