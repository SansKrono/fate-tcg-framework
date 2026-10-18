# Delve into the Beyond (Chaos regular spell): "Put a card from your hand on the bottom of your deck. Draw two".
# Order as written (Section 12 item 20): bottom first, then draw. With an empty hand only the draw happens.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Delve into the Beyond"
	has_choice = true


func candidates(card: Card, caster_id: int) -> Array:
	return game.player(caster_id).hand().get_all_cards().filter(func(c): return c != card)


func default_choice(card: Card, caster_id: int):
	var options := candidates(card, caster_id)
	return options[0] if not options.is_empty() else null


func resolve(_card: Card, caster_id: int, choice) -> void:
	if choice != null and is_instance_valid(choice):
		game.library.to_deck_bottom(choice, caster_id)
	game.library.draw(caster_id, 2)
