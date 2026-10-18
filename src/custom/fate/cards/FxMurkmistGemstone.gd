# Murkmist Gemstone (Chaos relic): "Enters attached to a creature. When that creature dies, take control of the
# creature that destroyed it, if any". The relic is released when its creature moves to the discard pile, so
# the killer is remembered in on_card_dying and taken in on_leave.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Murkmist Gemstone"


func on_enter(card: Card) -> void:
	if game.equip.host_of(card) != null:
		return
	var pid: int = card.controller_id
	var mine := creatures_of(pid)
	var options: Array = mine.duplicate()
	for c in creatures_of(opponent_of(pid)):
		options.append(c)
	var pick = await choose(card, pid, "creature to attach to", options)
	if pick != null:
		game.equip.equip(card, pick)


func on_card_dying(host: Card, dying: Card, _cause: String, source) -> void:
	if game.equip.host_of(host) == dying:
		host.set_meta("fate_murkmist_killer", source if source is Card else null)


# The creature died and the relic went to the discard pile: take its killer, if it is still in play
func on_leave(host: Card, _destination: String) -> void:
	if not host.has_meta("fate_murkmist_killer"):
		return
	var killer = host.get_meta("fate_murkmist_killer")
	host.remove_meta("fate_murkmist_killer")
	if killer is Card and is_instance_valid(killer) and FateZones.is_creature_in_play(killer):
		game.control.take_control(killer, host.controller_id)
