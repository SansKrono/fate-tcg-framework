# Dockside Ambusher (Chaos, 3/3): "When you flip cast it from your energy zone, target opponent chooses a
# non-token permanent of mana value 4 or less to give you, placed in your energy zone". The OPPONENT picks
# (game.choices request.player = the opponent) among the permanents they control.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Dockside Ambusher"


func on_flip_cast(host: Card, cast_card: Card, caster_id: int) -> void:
	if cast_card != host or caster_id != host.controller_id:
		return
	var opp := opponent_of(caster_id)
	var options: Array = game.costs.consume_candidates(host, game.costs.PERMANENT_ZONES,
			func(c, _s): return c.mana_value() <= 4 and not game.costs.is_token(c), {"player": opp, "controller": "you"})
	if options.is_empty():
		return
	var pick = await choose(host, opp, "permanent to give", options)
	if pick == null:
		return
	if FateZones.zone_of(pick) in ["creatures", "occupied", "relics"]:
		game.control.take_control(pick, caster_id, {"zone": "energy"})
	else:
		game.library.to_energy(pick, caster_id)


func ai_intent(_request: Dictionary) -> String:
	return "give"
