# Primal Wraith (Primal spell): "Creatures you control gain Savage 1 until EOT". Every creature the caster controls
# when it resolves gets Savage 1 until end of turn (granted values add up with innate Savage).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Primal Wraith"


func resolve(_card: Card, caster_id: int, _choice) -> void:
	for creature in creatures_of(caster_id):
		if creature.controller_id == caster_id:
			game.stats.grant_keyword(creature, "Savage", 1, FateStats.EXPIRY_END_OF_TURN, creature)
