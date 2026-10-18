# Goblin Scout Leader (Primal, 2/1): "When it attacks, create a 1/1 goblin in strike position".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Goblin Scout Leader"


func on_attack_declared(card: Card, _attack: FateAttack) -> void:
	game.tokens.create("Goblin Token", card.controller_id)
