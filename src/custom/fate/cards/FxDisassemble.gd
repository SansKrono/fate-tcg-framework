# Disassemble (Innovation regular spell): "Destroy target non-unique creature an opponent controls with 3 or less in
# the stat of its current position (Strike upright, Guard guarding or occupied). Create 2 scrap tokens". Default:
# the opponent's strongest creature it can take apart.
extends "res://src/custom/fate/cards/FateCardEffect.gd"

const MAX_STAT := 3


func _init() -> void:
	card_name = "Disassemble"
	has_choice = true


func play_problem(card: Card, caster_id: int) -> String:
	return "" if not candidates(card, caster_id).is_empty() else "No creature to take apart"


func candidates(_card: Card, caster_id: int) -> Array:
	var foe := opponent_of(caster_id)
	var found := creatures_of(foe).filter(func(c): return c.controller_id == foe \
			and not c.properties.get("_unique", false) \
			and game.stats.current(c, game.effects.used_stat(c)) <= MAX_STAT)
	found.sort_custom(func(a, b): return game.stats.current(a, "Strike") + game.stats.current(a, "Guard") \
			> game.stats.current(b, "Strike") + game.stats.current(b, "Guard"))
	return found


func default_choice(card: Card, caster_id: int):
	var options := candidates(card, caster_id)
	return options[0] if not options.is_empty() else null


func choice_problem(card: Card, caster_id: int, choice) -> String:
	return "" if choice in candidates(card, caster_id) else "Not a legal target"


func resolve(card: Card, caster_id: int, choice) -> void:
	if choice is Card and is_instance_valid(choice):
		game.effects.destroy(choice, card, FateEffects.CAUSE_EFFECT)
	game.tokens.add(caster_id, "scrap", 2)


func ai_intent(_request: Dictionary) -> String:
	return "harm"


# The two scrap; the creature it takes apart is added by the AI's target scoring (FateAIChoices.cast_worth)
func ai_value(_card: Card, _caster_id: int) -> float:
	return 3.0
