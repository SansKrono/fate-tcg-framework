# Vanquish Thine Foes (doctrine O3): when your creatures attack, any creature that interacts with them is destroyed.
# FateCombat asks game.doctrines.attack_about_to_resolve(attack) before each attack's damage; the destruction is
# there because the doctrine is not a participant of the attack, so no keyword hook reaches it.
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Vanquish Thine Foes"
