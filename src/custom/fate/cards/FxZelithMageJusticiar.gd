# Zelith, Mage Justiciar (Order, 3/4): "May attack perpetual spells as if creatures; spells hit are destroyed".
# can_attack_card lets Zelith declare an attack on an opposing field or world spell (FateCombat.attack_problem);
# an attack that is not intercepted destroys the spell (FateCombat._deal_combat_damage). The spell has no stats,
# so Zelith takes no damage. Creatures may still intercept such an attack.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Zelith, Mage Justiciar"


func can_attack_card(_attacker: Card, target: Card) -> bool:
	return game.combat.is_perpetual_spell(target)
