# Smite (Order spell): "Destroy target non-unique creature, or destroy target perpetual spell". Targets: any
# non-unique creature in play or any field / world spell on the table. Default: the opponent's strongest
# creature, then the opponent's perpetual spells, then the caster's own things.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Smite"
	has_choice = true


func play_problem(card: Card, caster_id: int) -> String:
	return "" if not candidates(card, caster_id).is_empty() else "No legal target"


func candidates(_card: Card, caster_id: int) -> Array:
	var found := []
	for pid in [opponent_of(caster_id), caster_id]:
		var creatures := creatures_of(pid).filter(func(c): return c.controller_id == pid and not c.properties.get("_unique", false))
		creatures.sort_custom(func(a, b): return game.stats.current(a, "Strike") + game.stats.current(a, "Guard") \
				> game.stats.current(b, "Strike") + game.stats.current(b, "Guard"))
		found.append_array(creatures)
		found.append_array(_perpetual_spells(pid))
	return found


func default_choice(card: Card, caster_id: int):
	var options := candidates(card, caster_id)
	return options[0] if not options.is_empty() else null


func choice_problem(card: Card, caster_id: int, choice) -> String:
	return "" if choice in candidates(card, caster_id) else "Not a legal target"


func resolve(card: Card, _caster_id: int, choice) -> void:
	if choice is Card and is_instance_valid(choice):
		game.effects.destroy(choice, card, FateEffects.CAUSE_EFFECT)


# Field spell of a player; the world spell counts for its controller
func _perpetual_spells(pid: int) -> Array:
	var found := []
	var field = game.equip.field_spell(pid)
	if field != null:
		found.append(field)
	var world = game.equip.world_spell()
	if world != null and world.controller_id == pid:
		found.append(world)
	return found


func ai_intent(_request: Dictionary) -> String:
	return "harm"
