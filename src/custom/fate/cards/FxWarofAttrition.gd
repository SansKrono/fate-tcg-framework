# War of Attrition (Order field spell): "At the beginning of your turn, switch of your creatures to occupied (guard but
# cannot defend)". The text is incomplete: all of the controller's creatures (design doc Section 12 item 8). Done
# when the Energy step begins (after maintenance untapped everything); a creature that cannot occupy (occupied zone
# full) stays where it is. It hurts the player whose field it is in, so it is meant to be cast on the opponent's
# field (a field spell can be cast on either player's, FateCardTemplate.field_seat).
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


func harms_holder(_card: Card) -> bool:
	return true


# Cast on the opponent: their creatures cannot attack or use Occupy abilities while it stands
func ai_value(_card: Card, caster_id: int) -> float:
	return 2.0 + 0.8 * float(creatures_of(opponent_of(caster_id)).size())
