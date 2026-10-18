# Toll of War (Primal spell): "Destroy all creatures in strike position" (both players, upright in the
# creature zone; guarding and occupied creatures are not in strike position).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Toll of War"


func resolve(card: Card, _caster_id: int, _choice) -> void:
	var doomed := game.creatures_in_play().filter(
			func(c): return FateZones.zone_of(c) == "creatures" and c.card_rotation == 0)
	for creature in doomed:
		game.effects.destroy(creature, card, FateEffects.CAUSE_EFFECT)
