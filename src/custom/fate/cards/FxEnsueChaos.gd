# Ensue Chaos (doctrine C2): instead of playing a card from hand as energy, take the top card of an opponent's deck into your energy zone.
# The reward is a choice of the ENERGY phase, offered by FateDoctrines (can_take_opponent_card /
# take_opponent_card_as_energy); the board lets the player click the opponent's deck.
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Ensue Chaos"
