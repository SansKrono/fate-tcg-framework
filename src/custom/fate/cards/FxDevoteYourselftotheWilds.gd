# Devote Yourself to the Wilds (doctrine P2): your creatures can attack the turn they are played (Charge).
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Devote Yourself to the Wilds"

func static_keywords(host: Card, target: Card) -> Dictionary:
	return {"Charge": 1} if active(host) and is_my_creature(host, target) else {}
