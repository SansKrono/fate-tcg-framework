# Channel the Spirit's Will (doctrine P3): a creature that would die from combat damage stays and its controller takes 3 damage instead.
# Your creatures get the keyword "Spirit Ward" (keywords/KwSpiritWard.gd) while the doctrine is achieved.
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Channel the Spirit's Will"

func static_keywords(host: Card, target: Card) -> Dictionary:
	return {"Spirit Ward": 1} if active(host) and is_my_creature(host, target) else {}
