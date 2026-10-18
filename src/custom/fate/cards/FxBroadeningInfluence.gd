# Broadening Influence (Chaos world spell): "Instead of playing a card from hand into your energy zone, you may take
# the top card of an opponent's library into your energy zone". An extra option of the ENERGY phase for every player
# (game.energy_alternatives / use_energy_alternative); it counts as playing energy. The card keeps its owner.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Broadening Influence"


func energy_alternative(_host: Card, player_id: int) -> String:
	if _top(player_id) == null or FateZones.grid("energy", player_id).find_available_slot() == null:
		return ""
	return "Take the top card of an opponent's library"


func use_energy_alternative(_host: Card, player_id: int) -> bool:
	var top: Card = _top(player_id)
	return top != null and game.library.to_energy(top, player_id)


func _top(player_id: int) -> Card:
	var cards: Array = game.library.look_top(opponent_of(player_id), 1)
	return cards[0] if not cards.is_empty() else null
