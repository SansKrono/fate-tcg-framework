# Sigil Mage (Order, 1/2): "The first spell you cast each turn is placed in your energy zone instead of your
# discard". Counted per player and turn (game.limiter, key below), over the spells cast while a Sigil Mage is on
# the table: a regular spell is asked where it goes once (spell_destination_for), a field or world spell counts
# as the first spell too (on_card_played). Reaction spells go straight to the discard pile and do not count.
extends "res://src/custom/fate/cards/FateCardEffect.gd"

const KEY := "sigil_mage_first_spell"


func _init() -> void:
	card_name = "Sigil Mage"


func spell_destination_for(host: Card, spell: Card) -> String:
	if spell.owner_id != host.controller_id:
		return ""
	return "energy" if game.limiter.use_player(host.controller_id, KEY) else ""


func on_card_played(host: Card, played: Card) -> void:
	if played.properties.get("Type") == "Spell" and played.owner_id == host.controller_id \
			and FateZones.zone_of(played) in ["field", "world"]:
		game.limiter.use_player(host.controller_id, KEY)
