# Double Agent: "When a player declares attacks, take control of another creature you do not control until EOT.
# It enters in guard position". Only in the declare_end window. Choice: one creature the caster does not control
# (control, not ownership, Section 12 item 12) and that the control system can take. Default: the strongest by
# Strike + Guard.
extends "res://src/custom/fate/reactions/FateReactionEffect.gd"


func _init() -> void:
	card_name = "Double Agent"
	has_choice = true
	windows = [FateCombat.WINDOW_DECLARE_END]


func problem(caster_id: int) -> String:
	if candidates(caster_id).is_empty():
		return "No creature to take control of"
	return ""


func candidates(caster_id: int) -> Array:
	var found := game.creatures_in_play().filter(func(c):
		return c.controller_id != caster_id and game.control.take_problem(c, caster_id, {"tilted": true}) == "")
	found.sort_custom(func(a, b):
		return game.stats.current(a, "Strike") + game.stats.current(a, "Guard") \
				> game.stats.current(b, "Strike") + game.stats.current(b, "Guard"))
	return found


func default_choice(caster_id: int):
	var found := candidates(caster_id)
	return found[0] if not found.is_empty() else null


func choice_problem(caster_id: int, choice) -> String:
	for c in as_cards(choice):
		if not c in candidates(caster_id):
			return "Pick a creature you do not control"
	return "" if choice != null else "Pick a creature"


func resolve(_card: Card, caster_id: int, choice) -> void:
	for creature in as_cards(choice):
		game.control.take_control(creature, caster_id, {"until": "end_of_turn", "tilted": true})
