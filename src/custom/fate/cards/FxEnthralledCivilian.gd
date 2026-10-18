# Enthralled Civilian (Chaos, 1/1): "Main phase: consume it to cast one of your mana cards (it stops being
# mana)". Flip cast from the energy zone, paying the cost with the OTHER energy cards.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Enthralled Civilian"


func actions(card: Card) -> Array:
	return [make_action(card, "cast_mana", "Cast", "Consume: flip cast one of your mana cards",
			[game.costs.consume_self()],
			func(c): await _cast_one(c),
			func(c): return "" if not game.casting.flip_castable(c.controller_id, Callable(), true).is_empty() \
					else "No mana card can be cast")]


func _cast_one(card: Card) -> void:
	var pid: int = card.controller_id
	var options: Array = game.casting.flip_castable(pid, Callable(), true)
	if options.is_empty():
		return
	var pick = await choose(card, pid, "mana card to cast", options)
	if pick != null:
		await game.casting.flip_cast_card(pick, pid, true)
