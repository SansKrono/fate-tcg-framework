# Thrang's Crafting Table (Innovation unique relic), modal: "Consume 1 ingot: create a Battle Hammer token,
# attach to a creature. Consume 2: create a 3/3 guard automaton. Consume 3: search for Thrang into hand".
# Three hover actions, one per mode.
extends "res://src/custom/fate/cards/FateCardEffect.gd"

const THRANG := "Thrang, Perpetual Innovation"


func _init() -> void:
	card_name = "Thrang's Crafting Table"


func actions(card: Card) -> Array:
	return [
		make_action(card, "hammer", "Hammer", "Consume 1 ingot: create a Battle Hammer attached to a creature",
				[game.costs.counter("ingot", 1)],
				func(c):
					var options := creatures_of(c.controller_id).filter(
							func(x): return x.controller_id == c.controller_id)
					var target = await choose(c, c.controller_id, "creature to equip", options)
					if target != null:
						game.tokens.create("Battle Hammer Token", c.controller_id, {"attach_to": target}),
				func(c): return _room(c, "relics", "No room for the hammer")),
		make_action(card, "automaton", "Automaton", "Consume 2 ingots: create a 3/3 iron automaton in guard position",
				[game.costs.counter("ingot", 2)],
				func(c): game.tokens.create("Iron Automaton Token", c.controller_id, {"tilted": true}),
				func(c): return _room(c, "creatures", "No room for the automaton")),
		make_action(card, "thrang", "Thrang", "Consume 3 ingots: search your deck for Thrang and put it into your hand",
				[game.costs.counter("ingot", 3)],
				func(c):
					var pid: int = c.controller_id
					var found: Array = game.library.search(pid, func(x): return x.canonical_name == THRANG)
					if not found.is_empty():
						game.library.to_hand(found[0], pid)
					game.library.shuffle(pid),
				func(c): return "" if not game.library.search(c.controller_id,
						func(x): return x.canonical_name == THRANG).is_empty() else "Thrang is not in your deck"),
	]


func _room(card: Card, zone: String, why: String) -> String:
	var grid := game.player(card.controller_id).grid(zone)
	return "" if grid.count_available_slots() > 0 or grid.auto_extend else why


func ai_intent(_request: Dictionary) -> String:
	return "help"
