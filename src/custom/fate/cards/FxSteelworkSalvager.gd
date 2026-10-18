# Steelwork Salvager (Innovation, 2/1): "When it attacks, create a scrap token".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Steelwork Salvager"


func on_attack_declared(card: Card, _attack: FateAttack) -> void:
	game.tokens.add(card.controller_id, "scrap", 1)
