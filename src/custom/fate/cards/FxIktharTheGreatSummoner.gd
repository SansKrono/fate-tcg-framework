# Ikthar, The Great Summoner (Chaos, 3/3 unique): "Occupy, consume a creature you do not control: search your
# deck for a unique creature, reveal, put in hand, shuffle". "Do not control" = control (Section 12 item 12).
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Ikthar, The Great Summoner"


func actions(card: Card) -> Array:
	return [make_action(card, "summon", "Summon", "Occupy, consume a creature you do not control: tutor a unique creature",
			[game.costs.occupy(), game.costs.consume_card(["creatures", "occupied"], game.costs.filter_creature(), 1,
					{"controller": "opponent"})],
			func(c): await _search(c))]


func _search(card: Card) -> void:
	var pid: int = card.controller_id
	var found: Array = game.library.search(pid, func(c):
			return c.properties.get("Type") == "Creature" and bool(c.properties.get("_unique", false)))
	if not found.is_empty():
		var pick = await choose(card, pid, "unique creature to reveal and take", found)
		if pick != null:
			game.library.to_hand(pick, pid)
	game.library.shuffle(pid)
