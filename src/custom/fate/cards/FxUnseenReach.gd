# Unseen Reach (Chaos field spell, cost 2): "At the beginning of combat on your turn, choose a creature you control;
# it cannot be blocked this turn". Grants Unblockable until end of turn when the declare step begins.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Unseen Reach"


func on_phase(card: Card, active_id: int, phase: int) -> void:
	if phase != FateGame.Phase.COMBAT_DECLARE or active_id != card.controller_id:
		return
	var options := creatures_of(card.controller_id)
	if options.is_empty():
		return
	var pick = await choose(card, card.controller_id, "creature that cannot be blocked", options)
	if pick != null:
		game.stats.grant_keyword(pick, "Unblockable", 1, FateStats.EXPIRY_END_OF_TURN, card)


func ai_intent(_request: Dictionary) -> String:
	return "help"
