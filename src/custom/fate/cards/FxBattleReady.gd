# Battle Ready (Order spell): "Switch up to 3 target creatures to strike position; +1 Strike until EOT".
# Targets: creatures in the creature zone (guarding ones first, the caster's before the opponent's). With the
# default answer the first three are taken. Occupied creatures cannot be switched (they are not targets).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Battle Ready"


func play_problem(_card: Card, caster_id: int) -> String:
	return "" if not _options(caster_id).is_empty() else "No creature to target"


func resolve(card: Card, caster_id: int, _choice) -> void:
	var options := _options(caster_id)
	if options.is_empty():
		return
	var picked = await choose(card, caster_id, "up to 3 creatures to switch to strike", options, mini(3, options.size()))
	var targets: Array = picked if picked is Array else [picked]
	for target in targets:
		if target is Card and FateZones.zone_of(target) == "creatures":
			target.set_card_rotation(0)
			game.stats.add_modifier(target, "Strike", 1, FateStats.EXPIRY_END_OF_TURN, null)


func _options(caster_id: int) -> Array:
	var found := []
	for pid in [caster_id, opponent_of(caster_id)]:
		var guarding := []
		var upright := []
		for creature in creatures_of(pid):
			if FateZones.zone_of(creature) != "creatures":
				continue
			(guarding if creature.card_rotation != 0 else upright).append(creature)
		found.append_array(guarding)
		found.append_array(upright)
	return found


func ai_intent(_request: Dictionary) -> String:
	return "help"
