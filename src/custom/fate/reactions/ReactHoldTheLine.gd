# Hold the Line: "Cast when your field is the target of an attack. Switch any number of your
# creatures into guard position, they gain +1 to their guard until the end of turn."
# Only in the declare_end window: after that the blockers are already chosen, so switching to guard
# would be too late to matter. Choice: the creatures to switch (an array of the caster's upright
# creatures in the creature zone). Default: all of them. Only the creatures that were switched get
# +1 Guard ("they"): one that already guarded is not "switched".
extends "res://src/custom/fate/reactions/FateReactionEffect.gd"


func _init() -> void:
	card_name = "Hold the Line"
	has_choice = true
	windows = [FateCombat.WINDOW_DECLARE_END]


func problem(caster_id: int) -> String:
	if attacks_on(caster_id).is_empty():
		return "Nothing attacks your field"
	return ""


# The upright creatures in the creature zone
func candidates(caster_id: int) -> Array:
	return game.creatures_in_play(caster_id).filter(func(c):
		return FateZones.zone_of(c) == "creatures" and c.card_rotation == 0)


func default_choice(caster_id: int):
	return candidates(caster_id)


func choice_problem(caster_id: int, choice) -> String:
	var allowed := candidates(caster_id)
	for c in as_cards(choice):
		if not c in allowed:
			return "Only your upright creatures in the creature zone can be switched"
	return ""


func resolve(card: Card, _caster_id: int, choice) -> void:
	for creature in as_cards(choice):
		creature.set_card_rotation(90)
		game.stats.add_modifier(creature, "Guard", 1, FateStats.EXPIRY_END_OF_TURN, card)
