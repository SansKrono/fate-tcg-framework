# Return to Nature (Primal spell): "Target relic or spell is placed in its owner's energy zone". The targets are the
# relics and the field / world spells on the table (both players). An equipped relic is released first. A token
# ceases to exist (game.library.to_energy). The default target is the opponent's.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Return to Nature"
	has_choice = true


func play_problem(card: Card, caster_id: int) -> String:
	return "" if not game.choices.legal_targets(card, targets(caster_id)).is_empty() else "No relic or spell to target"


func candidates(_card: Card, caster_id: int) -> Array:
	return targets(caster_id)


func default_choice(card: Card, caster_id: int):
	var options: Array = game.choices.legal_targets(card, targets(caster_id))
	return options[0] if not options.is_empty() else null


func choice_problem(_card: Card, caster_id: int, choice) -> String:
	return "" if choice in targets(caster_id) else "Not a relic or spell on the table"


func resolve(_card: Card, _caster_id: int, choice) -> void:
	if not choice is Card or not is_instance_valid(choice) or choice not in targets(0):
		return
	game.equip.release(choice)
	game.library.to_energy(choice, choice.owner_id)


func ai_intent(_request: Dictionary) -> String:
	return "harm"


# Relics and persisting spells on the table; the opponent's first (`caster_id` 0: just everything)
func targets(caster_id: int) -> Array:
	var found := []
	var order := [1, 2] if caster_id == 0 else [opponent_of(caster_id), caster_id]
	for pid in order:
		for zone in ["relics", "field"]:
			found.append_array(game.player(pid).cards_in_grid(zone))
	var world: Card = game.equip.world_spell()
	if world != null:
		found.append(world)
	return found
