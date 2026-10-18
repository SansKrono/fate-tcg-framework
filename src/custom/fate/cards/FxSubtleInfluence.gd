# Subtle Influence (doctrine C1): once per turn, flip cast a card by paying its cost (a standing flip cast permission).
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Subtle Influence"

# Key of the permission in game.casting
const KEY := "doctrine:Subtle Influence"


func on_reward_start(card: Card) -> void:
	game.casting.grant_permission(card.controller_id, KEY, 1, true)


func on_reward_end(card: Card) -> void:
	game.casting.revoke_permission(card.controller_id, KEY)


func on_enter(card: Card) -> void:
	if active(card):
		on_reward_start(card)


func on_leave(card: Card, _destination: String) -> void:
	game.casting.revoke_permission(card.controller_id, KEY)
