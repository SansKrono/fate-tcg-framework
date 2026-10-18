# Recovering Resources (Order field spell): "Once during end of each turn, if a creature you own died, you may draw a
# card". Remembers the turn a creature owned by its controller was destroyed while it was on the table; in the End
# step of that turn (either player's) its controller may draw a card, once per turn. Creatures that died before
# the spell came to the table do not count.
extends "res://src/custom/fate/cards/FateCardEffect.gd"

const META := "recovering_resources_died_turn"


func _init() -> void:
	card_name = "Recovering Resources"


func on_card_destroyed(card: Card, destroyed: Card, _cause: String, _source) -> void:
	if is_instance_valid(destroyed) and destroyed.properties.get("Type") == "Creature" \
			and destroyed.owner_id == card.controller_id:
		card.set_meta(META, game.turn_number)


func on_phase(card: Card, _active_id: int, phase: int) -> void:
	if phase != FateGame.Phase.END or int(card.get_meta(META, -1)) != game.turn_number \
			or not game.limiter.can_use(card, "recovering_resources"):
		return
	if await confirm(card, card.controller_id, "Draw a card?"):
		game.limiter.use(card, "recovering_resources")
		game.library.draw(card.controller_id, 1)
