# Scrap Cannon (Innovation relic): "Consume a scrap: 1 damage to any target (to a creature, reduces the stat for
# its current position)". Any target = any creature in play or either player. Not a spell: Thrang may be hit.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Scrap Cannon"


func actions(card: Card) -> Array:
	return [make_action(card, "fire", "Fire", "Consume a scrap: 1 damage to any target",
			[game.costs.counter("scrap", 1)],
			func(c):
				var target = await choose(c, c.controller_id, "target for 1 damage", _targets(c.controller_id))
				if target != null:
					game.effects.deal_damage(target, 1, c, FateEffects.CAUSE_EFFECT))]


# The default (first) target is the opponent, then their creatures, then yours
func _targets(pid: int) -> Array:
	var foe := opponent_of(pid)
	var found: Array = [game.player(foe)]
	found.append_array(creatures_of(foe))
	found.append_array(creatures_of(pid))
	found.append(game.player(pid))
	return found


func ai_intent(_request: Dictionary) -> String:
	return "harm"
