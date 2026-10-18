# Lucran, Divine Saviour (Order, 6/6): "When a creature you control dies choose 1: place the card in your energy
# zone (not tokens); or remove it from the game and create a Soul Spear relic".
# Watches every destruction (Lucran's own death does not count). The first option is the default and is left out
# for tokens or when the energy zone is full; the second removes the card from the game (its owner's removed
# pile) and creates a Soul Spear token relic for Lucran's controller (nothing to remove for a token).
extends "res://src/custom/fate/cards/FateCardEffect.gd"

const ENERGY := "Place it in your energy zone"
const SPEAR := "Remove it from the game and create a Soul Spear"


func _init() -> void:
	card_name = "Lucran, Divine Saviour"


func on_card_destroyed(card: Card, destroyed: Card, _cause: String, _source) -> void:
	if not is_instance_valid(destroyed) or destroyed.properties.get("Type") != "Creature" \
			or destroyed.controller_id != card.controller_id:
		return
	var pid: int = card.controller_id
	var is_token: bool = game.tokens.is_token(destroyed)
	var options := []
	if not is_token and FateZones.grid("energy", pid).find_available_slot() != null:
		options.append(ENERGY)
	options.append(SPEAR)
	var answer = await choose(card, pid, "Lucran: choose 1", options)
	if not is_token:
		# The dead creature is still sliding into its pile; it can only be moved on once it has arrived
		var frames := 0
		while is_instance_valid(destroyed) and destroyed.state == Card.CardState.MOVING_TO_CONTAINER \
				and frames < 180:
			await game.get_tree().process_frame
			frames += 1
		if not is_instance_valid(destroyed):
			return
		if answer == ENERGY:
			game.library.to_energy(destroyed, pid)
			return
		game.library.to_removed(destroyed)
	game.tokens.create("Soul Spear Token", pid)
