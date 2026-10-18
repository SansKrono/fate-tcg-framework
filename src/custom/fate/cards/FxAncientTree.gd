# Ancient Tree (Primal relic): "Occupy: produce 1 Primal energy". Tilting the relic gives 1 floating Primal mana
# (game.mana.add_floating): spent before the energy cards, gone at the end of the turn. It untaps at maintenance.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Ancient Tree"


func actions(card: Card) -> Array:
	return [make_action(card, "ancient_tree", "Occupy", "Occupy: produce 1 Primal energy",
			[game.costs.tilt_self()],
			func(c): game.mana.add_floating(c.controller_id, "Primal", 1))]
