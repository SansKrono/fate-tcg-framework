# Krelga, Abyssal Nightmare (Chaos, 6/6 unique): "Creatures destroyed by Krelga return under your control.
# When Krelga is destroyed, place it in your energy zone". Needs the destroy source (game.effects.last_source).
# Limitation: if Krelga is destroyed first in a simultaneous destruction, it no longer hears the others.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Krelga, Abyssal Nightmare"


func on_card_destroyed(host: Card, destroyed: Card, _cause: String, source) -> void:
	if source != host or destroyed == host or destroyed.properties.get("Type") != "Creature":
		return
	if destroyed.get_parent() != FateZones.container("discard", destroyed.owner_id):
		return
	game.casting.return_to_table(destroyed, host.controller_id)


func on_destroyed(card: Card, _cause: String, _source) -> void:
	game.library.to_energy(card, card.controller_id)
