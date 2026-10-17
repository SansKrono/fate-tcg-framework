# Forests Protection: "When your field is the target of an attack, your creatures gain indomitable
# until the end of turn." Every creature the caster has in play (also the occupied ones) gets the
# Indomitable keyword by name, so it works whether or not KwIndomitable.gd exists yet.
extends "res://src/custom/fate/reactions/FateReactionEffect.gd"


func _init() -> void:
	card_name = "Forests Protection"


func problem(caster_id: int) -> String:
	if attacks_on(caster_id).is_empty():
		return "Nothing attacks your field"
	return ""


func resolve(card: Card, caster_id: int, _choice) -> void:
	for creature in game.creatures_in_play(caster_id):
		game.stats.grant_keyword(creature, "Indomitable", 1, FateStats.EXPIRY_END_OF_TURN, card)
