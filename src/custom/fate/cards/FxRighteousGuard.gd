# Righteous Guard (Order, 1/1): "Enters: create 1/1 soldiers equal to the number of cards named Righteous Guard
# on your field". The count includes this card.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Righteous Guard"


func on_enter(card: Card) -> void:
	var guards := creatures_of(card.controller_id).filter(
			func(c): return c.canonical_name == card_name and c.controller_id == card.controller_id)
	game.tokens.create_many("Soldier Token", card.controller_id, guards.size())
