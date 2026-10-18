# Tactical Combatant (Order, 3/3): "After it attacks, switch it to guard position". When its attack has resolved
# and it is still in the creature zone it tilts to the guard position (it stays a legal blocker on the
# opponent's turn).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Tactical Combatant"


func on_attack_resolved(card: Card, attack: FateAttack, _result: Dictionary) -> void:
	if attack.attacker == card and FateZones.zone_of(card) == "creatures":
		card.set_card_rotation(90)
