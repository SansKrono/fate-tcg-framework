# Devote Yourself to Progress (doctrine I2): your creatures can occupy the turn they are played (Productive).
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Devote Yourself to Progress"

func static_keywords(host: Card, target: Card) -> Dictionary:
	return {"Productive": 1} if active(host) and is_my_creature(host, target) else {}
