# Spiked Barricade (Order relic): "Can be used to guard an attacking creature; when it does, destroy that creature
# and discard the barricade". A legal blocker for its controller (FateKeyword.can_block_as_relic). When the block
# is confirmed (on_blocking) the attacker is destroyed and the barricade goes to the discard pile; the attack
# is removed with its attacker.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Spiked Barricade"


func can_block_as_relic(_relic: Card, _attack: FateAttack) -> bool:
	return true


func on_blocking(card: Card, attack: FateAttack) -> void:
	game.effects.destroy(attack.attacker, card, FateEffects.CAUSE_EFFECT)
	game.costs.consume(card)
