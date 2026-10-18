# Insightful Investigator (Order, 1/2): "Enters: look at the top two cards of target player's library; you may
# put one or both on the bottom". The player is picked through game.choices (yourself first: the default), then
# each of the two cards gets a yes/no ("put it on the bottom?", default no).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Insightful Investigator"


func on_enter(card: Card) -> void:
	var pid: int = card.controller_id
	var players: Array = [game.player(pid), game.player(opponent_of(pid))]
	var target: FatePlayer = await choose(card, pid, "target player", players)
	if target == null:
		return
	for top in game.library.look_top(target.id, 2):
		if await confirm(card, pid, "Put %s on the bottom of Player %d's library?" % [top.canonical_name, target.id], false):
			game.library.to_deck_bottom(top, target.id)


func ai_intent(_request: Dictionary) -> String:
	return "help"
