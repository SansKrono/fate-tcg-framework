# Cycle of Life (Primal field spell): "Once during your turn, if a card is placed in your discard, move it to your
# energy zone". Watches the piles (on_card_to_pile): the first card of your own discard pile during your turn goes to
# your energy zone instead (game.library.to_energy). The use is only counted when the card really moved (a full energy
# zone leaves the card in the discard pile and the use unspent). Tokens never reach the pile.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Cycle of Life"


func on_card_to_pile(card: Card, placed: Card, zone: String) -> void:
	if zone != "discard" or placed.owner_id != card.controller_id or game.active_id != card.controller_id:
		return
	if not game.limiter.can_use(card, "cycle_of_life") or not placed.get_parent() is Pile \
			or placed.get_parent() != FateZones.container("discard", placed.owner_id):
		return
	if game.library.to_energy(placed, card.controller_id):
		game.limiter.use(card, "cycle_of_life")
