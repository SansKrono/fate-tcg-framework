# Self-destruction (Chaos spell): "Additional cost: consume X permanents. Opponents consume X permanents".
# The caster chooses X (1 up to the permanents they can consume) when the cost is paid, through game.choices
# (kind "X, the number of permanents to consume", integer options, the default first: as many as the
# opponents have, at most what the caster has). The cards are picked by the caster, then each opponent picks
# and consumes X of theirs (as many as they have if fewer). X is kept on the card between cost and resolve.
extends "res://src/custom/fate/cards/FateCardEffect.gd"

const META_X := "self_destruction_x"


func _init() -> void:
	card_name = "Self-destruction"


func play_problem(card: Card, caster_id: int) -> String:
	return game.costs.extra_problem(card, caster_id, game.costs.PERMANENT_ZONES, Callable(), 1)


func pay_extra_cost(card: Card, caster_id: int) -> bool:
	var mine: int = game.costs.consume_candidates(card, game.costs.PERMANENT_ZONES, Callable(),
			{"player": caster_id, "exclude_self": true}).size()
	if mine < 1:
		return false
	var theirs: int = 0
	for pid in game.players:
		if pid != caster_id:
			theirs = maxi(theirs, game.costs.consume_candidates(card, game.costs.PERMANENT_ZONES, Callable(),
					{"player": pid, "exclude_self": true}).size())
	var best: int = clampi(theirs, 1, mine)
	var options: Array = [best]
	for x in range(1, mine + 1):
		if x != best:
			options.append(x)
	var x = await choose(card, caster_id, "X, the number of permanents to consume", options)
	if not x is int or x < 1 or x > mine:
		x = best
	if not await game.costs.cost_pay_extra(card, caster_id, game.costs.PERMANENT_ZONES, Callable(), x):
		return false
	card.set_meta(META_X, x)
	return true


func resolve(card: Card, caster_id: int, _choice) -> void:
	var x: int = int(card.get_meta(META_X, 0))
	for pid in game.players:
		if pid != caster_id:
			await game.costs.force_consume(card, pid, game.costs.PERMANENT_ZONES, Callable(), x)
