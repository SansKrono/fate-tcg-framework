# Defend the Innocent (doctrine O2): your creatures gain +1 Strike and +1 Guard.
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Defend the Innocent"

func static_stat_bonus(host: Card, target: Card, _stat: String) -> int:
	return 1 if active(host) and is_my_creature(host, target) else 0
