# Guardian Spirits (Primal field spell): "At the beginning of your turn you may flip a creature from your energy
# zone; it may attack this turn and returns to the energy zone at EOT". Runs when the DRAW phase of its controller's
# turn begins (after the maintenance reset). The creature comes from game.casting.borrow_creature. Optional: the
# controller is asked (game.choices.confirm), then picks the creature. Nothing happens without a creature in the
# energy zone or a free creature slot.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Guardian Spirits"


func on_phase(card: Card, active_id: int, phase: int) -> void:
	if phase != FateGame.Phase.DRAW or active_id != card.controller_id:
		return
	var options: Array = game.player(active_id).cards_in_grid("energy").filter(
			func(c): return c.properties.get("Type") == "Creature")
	var grid := FateZones.grid("creatures", active_id)
	if options.is_empty() or grid == null or grid.find_available_slot() == null:
		return
	if not await confirm(card, active_id, "Guardian Spirits: flip a creature from your energy zone?"):
		return
	var picked = await choose(card, active_id, "creature from your energy zone", options)
	if picked != null:
		game.casting.borrow_creature(picked, active_id)
