# Battle Smith (Innovation, 3/3): "Tap, consume an ingot: create a Battle Hammer token attached to a creature
# you control (+2 Strike)". The +2 Strike is FxBattleHammerToken.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Battle Smith"


func actions(card: Card) -> Array:
	return [make_action(card, "hammer", "Hammer", "Occupy, consume an ingot: create a Battle Hammer on a creature you control",
			[game.costs.occupy(), game.costs.counter("ingot", 1)],
			func(c):
				var options := creatures_of(c.controller_id).filter(
						func(x): return x.controller_id == c.controller_id)
				var target = await choose(c, c.controller_id, "creature to equip", options)
				if target != null:
					game.tokens.create("Battle Hammer Token", c.controller_id, {"attach_to": target}),
			func(c):
				var grid := game.player(c.controller_id).grid("relics")
				return "" if grid.count_available_slots() > 0 or grid.auto_extend else "No room for the hammer")]


func ai_intent(_request: Dictionary) -> String:
	return "help"
