# Thrang, Perpetual Innovation (Innovation, 6/6): "Consume a scrap: unoccupy target permanent you control.
# Cannot be targeted by spells".
# "Permanent" here: an occupied creature (back to the creature zone) or a tilted relic (Ancient Tree style).
# Spells must not target it: game.choices.legal_targets / targetable ask can_be_targeted_by below, and
# game.choices.pick ("target ..." kinds) and pick_for_card apply it automatically. Abilities and attacks
# may still target it.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Thrang, Perpetual Innovation"


func can_be_targeted_by(_target: Card, source) -> bool:
	return not (source is Card and is_instance_valid(source) and source.properties.get("Type") == "Spell")


func actions(card: Card) -> Array:
	return [make_action(card, "unoccupy", "Unoccupy", "Consume a scrap: unoccupy target permanent you control",
			[game.costs.counter("scrap", 1)],
			func(c):
				var options := _tired(c.controller_id)
				var target = await choose(c, c.controller_id, "target permanent to unoccupy", options)
				if target != null:
					_unoccupy(target),
			func(c): return "" if not _tired(c.controller_id).is_empty() else "Nothing is occupied")]


func ai_intent(_request: Dictionary) -> String:
	return "help"


func _tired(pid: int) -> Array:
	var found: Array = game.player(pid).cards_in_grid("occupied").duplicate()
	for relic in game.player(pid).cards_in_grid("relics"):
		if relic.card_rotation != 0:
			found.append(relic)
	return found


func _unoccupy(card: Card) -> void:
	if FateZones.zone_of(card) == "occupied":
		game.keywords.get_keyword("Occupy").unoccupy(card)
	else:
		card.set_card_rotation(0)
