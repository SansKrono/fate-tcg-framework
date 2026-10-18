# Soul Spear token (Order relic token, made by Lucran): "Consume: deal 2 damage to any target". Any target is a
# creature in play or a player; the default is the opponent, then their creatures, then yours.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Soul Spear Token"


func actions(card: Card) -> Array:
	return [make_action(card, "spear", "Throw", "Consume: deal 2 damage to any target",
			[game.costs.consume_self()],
			func(c):
				var target = await choose(c, c.controller_id, "target for 2 damage", _targets(c.controller_id))
				if target != null:
					game.effects.deal_damage(target, 2, c, FateEffects.CAUSE_EFFECT))]


func _targets(pid: int) -> Array:
	var foe := opponent_of(pid)
	var found: Array = [game.player(foe)]
	found.append_array(creatures_of(foe))
	found.append_array(creatures_of(pid))
	found.append(game.player(pid))
	return found


func ai_intent(_request: Dictionary) -> String:
	return "harm"
