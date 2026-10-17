# Factory Shutdown: "All attacks against you and your field are negated".
# Every attack of this combat aimed at the caster's player or one of the caster's creatures is
# negated (it stays in combat and resolves as nothing, FateCombat.negate_attack).
extends "res://src/custom/fate/reactions/FateReactionEffect.gd"


func _init() -> void:
	card_name = "Factory Shutdown"


func problem(caster_id: int) -> String:
	if attacks_on(caster_id, true).is_empty():
		return "No attack to negate: nothing attacks you or your creatures"
	return ""


func resolve(_card: Card, caster_id: int, _choice) -> void:
	for attack in attacks_on(caster_id, true):
		game.combat.negate_attack(attack)
