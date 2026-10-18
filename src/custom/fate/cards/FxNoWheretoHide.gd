# No Where to Hide (Primal spell): "Destroy all creatures in guard position" (both players, tilted in the
# creature zone; occupied creatures are not in guard position).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "No Where to Hide"


func resolve(card: Card, _caster_id: int, _choice) -> void:
	var doomed := game.creatures_in_play().filter(
			func(c): return FateZones.zone_of(c) == "creatures" and c.card_rotation == 90)
	for creature in doomed:
		game.effects.destroy(creature, card, FateEffects.CAUSE_EFFECT)
