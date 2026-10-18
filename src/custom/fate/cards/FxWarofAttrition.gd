# War of Attrition (Order field spell): "At the beginning of your turn, switch of your creatures to occupied (guard but
# cannot defend)". The text is incomplete: all of the controller's creatures (design doc Section 12 item 8). Done
# when the Energy step begins (after maintenance untapped everything); a creature that cannot occupy (occupied zone
# full) stays where it is.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "War of Attrition"


func on_phase(card: Card, active_id: int, phase: int) -> void:
	if phase != FateGame.Phase.ENERGY or active_id != card.controller_id:
		return
	var occupy = game.keywords.get_keyword("Occupy")
	for creature in creatures_of(active_id):
		if creature.controller_id == active_id and FateZones.zone_of(creature) == "creatures":
			occupy.occupy(creature, true)
