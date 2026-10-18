# Unending Echo (Chaos, 2/1): "Can be cast from your discard by paying its cost". Offers a "Cast" action while
# it lies in its owner's discard pile (FateCasting.discard_action, listed by game.actions for pile cards).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Unending Echo"


func actions(card: Card) -> Array:
	if card.get_parent() == FateZones.container("discard", card.owner_id):
		return [game.casting.discard_action(card)]
	return []
