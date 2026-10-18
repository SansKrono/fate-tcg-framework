# Harbinger of Krelgar (Chaos, 1/1): "When it dies, take control of target creature with mana value 2 or less".
# Candidates: creatures in play the controller does not control yet (and can take: free zone).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Harbinger of Krelgar"


func on_destroyed(card: Card, _cause: String, _source) -> void:
	var pid: int = card.controller_id
	var options: Array = []
	for pl in game.players:
		for c in creatures_of(pl):
			if c != card and c.controller_id != pid and c.mana_value() <= 2 \
					and game.control.take_problem(c, pid) == "":
				options.append(c)
	if options.is_empty():
		return
	var target = await choose(card, pid, "target creature (mana value 2 or less)", options)
	if target != null:
		game.control.take_control(target, pid)


func ai_intent(_request: Dictionary) -> String:
	return "harm"
