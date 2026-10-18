# Unforgotten Sacrifice (Chaos regular spell): "Flip play a card from your energy zone without paying. Then
# place the top card of your deck face-down in your energy zone". Works without a castable card too.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Unforgotten Sacrifice"
	has_choice = true


func candidates(_card: Card, caster_id: int) -> Array:
	return game.casting.flip_castable(caster_id, Callable(), false)


func default_choice(card: Card, caster_id: int):
	var options := candidates(card, caster_id)
	return options[0] if not options.is_empty() else null


func resolve(_card: Card, caster_id: int, choice) -> void:
	if choice != null and is_instance_valid(choice):
		await game.casting.flip_cast_card(choice, caster_id, false)
	var top: Array = game.library.look_top(caster_id, 1)
	if not top.is_empty():
		game.library.to_energy(top[0], caster_id)
