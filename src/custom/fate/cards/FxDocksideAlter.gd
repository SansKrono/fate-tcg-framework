# Dockside Alter (Chaos relic): "Once during your turn, consume a creature; when you do you may flip cast from
# your energy zone" (paying the cost).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Dockside Alter"


func actions(card: Card) -> Array:
	return [make_action(card, "alter", "Alter", "Consume a creature: you may flip cast from your energy zone",
			[game.costs.consume_card(["creatures", "occupied"], game.costs.filter_creature()),
			game.costs.once_per_turn("alter")],
			func(c): await _cast(c))]


func _cast(card: Card) -> void:
	var pid: int = card.controller_id
	var options: Array = game.casting.flip_castable(pid, Callable(), true)
	if options.is_empty() or not await confirm(card, pid, "Flip cast a card from your energy zone?"):
		return
	var pick = await choose(card, pid, "energy card to flip cast", options)
	if pick != null:
		await game.casting.flip_cast_card(pick, pid, true)
