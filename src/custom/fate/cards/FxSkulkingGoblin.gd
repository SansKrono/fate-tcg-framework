# Skulking Goblin (Innovation, 2/1): "When it attacks you may draw a card then discard a card".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Skulking Goblin"


func on_attack_declared(card: Card, _attack: FateAttack) -> void:
	var pid: int = card.controller_id
	if not await confirm(card, pid, "Draw a card, then discard a card?"):
		return
	game.library.draw(pid, 1)
	await game.library.discard_from_hand(pid, 1)
