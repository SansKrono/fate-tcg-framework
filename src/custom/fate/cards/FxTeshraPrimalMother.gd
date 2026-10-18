# Teshra, Primal Mother (Primal, 6/6, Indomitable): "Pay 3: flip a creature from your energy zone; it may attack this
# turn; at EOT return it to the energy zone". Indomitable is the innate keyword. Pay 3 is generic mana.
# The flipped creature comes through game.casting.borrow_creature (Charge until end of turn, returns at end of turn).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Teshra, Primal Mother"


func actions(card: Card) -> Array:
	return [make_action(card, "teshra_flip", "Flip (pay 3)", "Pay 3: flip a creature from your energy zone; it may attack this turn",
			[game.costs.mana(3)],
			func(c):
				var picked = await choose(c, c.controller_id, "creature from your energy zone",
						creatures_in_energy(c.controller_id))
				if picked != null:
					game.casting.borrow_creature(picked, c.controller_id),
			func(c):
				if creatures_in_energy(c.controller_id).is_empty():
					return "No creature in your energy zone"
				var grid := FateZones.grid("creatures", c.controller_id)
				if grid == null or grid.find_available_slot() == null:
					return "Your creature zone is full"
				return "")]


# The creature cards in a player's energy zone, in slot order
func creatures_in_energy(player_id: int) -> Array:
	return game.player(player_id).cards_in_grid("energy").filter(
			func(c): return c.properties.get("Type") == "Creature")
