# Deep Thought (Chaos regular spell): "Look at the top two cards of your deck, put one in your hand and the
# other on the bottom".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Deep Thought"
	has_choice = true


func candidates(_card: Card, caster_id: int) -> Array:
	return game.library.look_top(caster_id, 2)


func default_choice(card: Card, caster_id: int):
	var options := candidates(card, caster_id)
	return options[0] if not options.is_empty() else null


func resolve(card: Card, caster_id: int, choice) -> void:
	var seen := candidates(card, caster_id)
	if choice == null or not choice in seen:
		return
	for c in seen:
		if c != choice:
			game.library.to_deck_bottom(c, caster_id)
	game.library.to_hand(choice, caster_id)
