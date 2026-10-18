# Unseen Manipulator (Chaos, 3/2): "Enters: choose 1: Convert (take control of target non-unique creature an
# opponent controls) / Intel (draw two)". Convert is only offered when there is a target.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Unseen Manipulator"


func _targets(card: Card) -> Array:
	var pid: int = card.controller_id
	return creatures_of(opponent_of(pid)).filter(func(c):
			return c.controller_id != pid and not bool(c.properties.get("_unique", false)) \
					and game.control.take_problem(c, pid) == "")


func on_enter(card: Card) -> void:
	var pid: int = card.controller_id
	var targets := _targets(card)
	var modes := ["Convert", "Intel"] if not targets.is_empty() else ["Intel"]
	var mode = await choose(card, pid, "mode", modes)
	if mode == "Convert":
		var target = await choose(card, pid, "target creature to convert", _targets(card))
		if target != null:
			game.control.take_control(target, pid)
	else:
		game.library.draw(pid, 2)
