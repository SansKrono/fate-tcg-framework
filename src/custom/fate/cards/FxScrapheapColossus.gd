# Scrapheap Colossus (Innovation, 2/2): "Gets +1 Strike and +1 Guard for each relic you control". Relic tokens
# (a Battle Hammer) count: the heap is built from whatever is lying in the relic zone.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Scrapheap Colossus"


func static_stat_bonus(host: Card, target: Card, _stat: String) -> int:
	if host != target:
		return 0
	return game.player(host.controller_id).cards_in_grid("relics").size()
