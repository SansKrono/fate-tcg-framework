# Battering Ram (Primal, 3/2): "May target relics as if creatures; relics hit are destroyed". Allows attacks on
# opposing relics (FateCombat.attack_problem / can_attack_card); an unintercepted attack on a relic destroys it
# (FateCombat._deal_combat_damage). The relic has no stats, so the Ram takes no damage.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Battering Ram"


func can_attack_card(_attacker: Card, target: Card) -> bool:
	return game.combat.is_relic_on_table(target)
