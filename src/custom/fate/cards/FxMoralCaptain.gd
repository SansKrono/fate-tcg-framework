# Moral Captain (Order, 2/2): "When you attack, two target creatures gain +1 Strike until EOT".
# Triggers once per combat in which its controller declared at least one attack (when the attackers are
# confirmed, at the start of the intercept step), whichever creature attacks. Targets go through game.choices:
# any two creatures in play, the controller's attackers first (the default), then the rest of their creatures.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Moral Captain"


func on_phase(card: Card, active_id: int, phase: int) -> void:
	if phase != FateGame.Phase.COMBAT_INTERCEPT or active_id != card.controller_id:
		return
	var attackers := []
	for attack in game.combat.attacks:
		if not attack.removed and FateZones.is_creature_in_play(attack.attacker):
			attackers.append(attack.attacker)
	if attackers.is_empty():
		return
	var options: Array = attackers.duplicate()
	for creature in creatures_of(card.controller_id):
		if not creature in options:
			options.append(creature)
	for creature in creatures_of(opponent_of(card.controller_id)):
		options.append(creature)
	var picked = await choose(card, card.controller_id, "two creatures to gain +1 Strike", options, 2)
	var targets: Array = picked if picked is Array else [picked]
	for target in targets:
		if target is Card and FateZones.is_creature_in_play(target):
			game.stats.add_modifier(target, "Strike", 1, FateStats.EXPIRY_END_OF_TURN, null)


func ai_intent(_request: Dictionary) -> String:
	return "help"
