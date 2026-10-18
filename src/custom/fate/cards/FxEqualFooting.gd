# Equal Footing (Order world spell): "At end of each player's turn, if they do not have the most energy, they may move
# a card from their discard to their energy zone". "Do not have the most" = strictly fewer energy cards than an
# opponent (a tie counts as having the most). The player whose turn ends chooses from their discard pile (most
# recent card first); declining is allowed.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Equal Footing"


func on_phase(card: Card, active_id: int, phase: int) -> void:
	if phase != FateGame.Phase.END or not game.players.has(active_id):
		return
	var mine: int = game.player(active_id).cards_in_grid("energy").size()
	var theirs: int = game.player(opponent_of(active_id)).cards_in_grid("energy").size()
	if mine >= theirs:
		return
	var options: Array = game.library.search(active_id, Callable(), "discard")
	if options.is_empty() or FateZones.grid("energy", active_id).find_available_slot() == null:
		return
	if not await confirm(card, active_id, "Move a card from your discard pile to your energy zone?"):
		return
	var picked = await choose(card, active_id, "card from your discard pile to your energy zone", options)
	if picked != null:
		game.library.to_energy(picked, active_id)
