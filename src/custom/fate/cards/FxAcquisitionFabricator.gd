# Acquisition Fabricator (Innovation, 2/3): "Tap, consume a scrap: create an ingot token (consume for 1 mana
# of any colour)". Tap = Occupy. The ingot-as-mana part is FateMana (game.tokens.ingot_mana).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Acquisition Fabricator"


func actions(card: Card) -> Array:
	return [make_action(card, "fabricate", "Ingot", "Occupy, consume a scrap: create an ingot token",
			[game.costs.occupy(), game.costs.counter("scrap", 1)],
			func(c): game.tokens.add(c.controller_id, "ingot", 1))]
