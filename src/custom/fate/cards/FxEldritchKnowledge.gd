# Eldritch Knowledge (Chaos field spell): "Whenever you flip cast, draw a card".
# Decision: it does not hear its own flip cast (it was not on the table when the cast happened).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Eldritch Knowledge"


func on_flip_cast(host: Card, cast_card: Card, caster_id: int) -> void:
	if cast_card == host or caster_id != host.controller_id:
		return
	game.library.draw(caster_id, 1)
