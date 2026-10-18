# Convert the Masses (doctrine C3): at the beginning of each turn, take the weakest creature (lowest Strike + Guard) on a target player's field.
# The target player is the opponent (two players). Ties: the first in slot order. Every turn, also the opponent's.
extends "res://src/custom/fate/cards/FateDoctrineEffect.gd"


func _init() -> void:
	card_name = "Convert the Masses"

func on_phase(card: Card, _active_id: int, phase: int) -> void:
	if phase != FateGame.Phase.MAINTENANCE or not active(card):
		return
	var weakest: Card = null
	var weakest_total := 0
	for creature in creatures_of(opponent_of(card.controller_id)):
		var total: int = game.stats.current(creature, "Strike") + game.stats.current(creature, "Guard")
		if weakest == null or total < weakest_total:
			weakest = creature
			weakest_total = total
	if weakest != null:
		game.control.take_control(weakest, card.controller_id)
