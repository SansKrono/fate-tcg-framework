# Cultist Fanatic (Chaos, 3/1): "When it deals damage to a player or creature, you may sacrifice it to flip
# cast a card from your energy zone without paying". Sacrifice = consume (no death trigger). Runs during the
# damage step, so the Fanatic escapes the destruction that follows.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Cultist Fanatic"


func on_damage_dealt(card: Card, _target, amount: int, _cause: String) -> void:
	if amount <= 0 or FateZones.zone_of(card) == "":
		return
	var pid: int = card.controller_id
	var options: Array = game.casting.flip_castable(pid, Callable(), false)
	if options.is_empty():
		return
	if not await confirm(card, pid, "Sacrifice Cultist Fanatic to flip cast a card from your energy zone for free?"):
		return
	game.costs.consume(card)
	var pick = await choose(card, pid, "energy card to flip cast", options)
	if pick != null:
		await game.casting.flip_cast_card(pick, pid, false)
