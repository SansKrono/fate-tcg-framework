# Holy Healer (Order, 1/1): "Enters: take a creature from your discard and put it in your hand".
# The pick goes through game.choices; the first creature of the pile (top first) is the default.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Holy Healer"


func on_enter(card: Card) -> void:
	var pid: int = card.controller_id
	var options: Array = game.library.search(pid,
			func(c): return c.properties.get("Type") == "Creature", "discard")
	if options.is_empty():
		return
	var picked = await choose(card, pid, "creature from your discard pile", options)
	if picked != null:
		game.library.to_hand(picked, pid)


func ai_intent(_request: Dictionary) -> String:
	return "help"
