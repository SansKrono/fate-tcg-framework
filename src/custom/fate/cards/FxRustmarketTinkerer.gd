# Rustmarket Tinkerer (Innovation, 1/3): "Occupy: cast 1 relic from your discard by paying its cost".
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Rustmarket Tinkerer"


func actions(card: Card) -> Array:
	return [make_action(card, "recast", "Recast", "Occupy: cast a relic from your discard pile by paying its cost",
			[game.costs.occupy()],
			func(c):
				var pid: int = c.controller_id
				var relic = await choose(c, pid, "relic to cast", _castable(pid))
				if relic != null:
					await game.casting.cast_from_discard(relic, pid, true),
			func(c): return "" if not _castable(c.controller_id).is_empty() else "No relic can be cast from the discard pile")]


func _castable(pid: int) -> Array:
	return game.library.search(pid, func(r): return _can_cast(r, pid), "discard")


func _can_cast(relic: Card, pid: int) -> bool:
	return relic.properties.get("Type") == "Relic" \
			and game.casting.cast_from_discard_problem(relic, pid, true) == ""


func ai_intent(_request: Dictionary) -> String:
	return "help"
