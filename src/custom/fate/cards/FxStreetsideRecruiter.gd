# Streetside Recruiter (Order, 1/2): "Occupy: create a 1/1 human soldier".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Streetside Recruiter"


func actions(card: Card) -> Array:
	return [make_action(card, "recruit", "Recruit", "Occupy: create a 1/1 human soldier",
			[game.costs.occupy()],
			func(c): game.tokens.create("Soldier Token", c.controller_id))]
