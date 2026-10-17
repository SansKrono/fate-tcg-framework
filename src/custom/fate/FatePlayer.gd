# State of one player. Design document: Section 4.1 (SYS-PLAYER).
#
# This is the proof-of-concept version of PlayerContext: it owns the id,
# the life total and the chosen domains, and gives access to the player's zones.
class_name FatePlayer
extends RefCounted

const STARTING_LIFE := 20

signal life_changed(player)

var id: int
var display_name: String
# The two domains the player's deck is built from
var domains: Array
var life := STARTING_LIFE:
	set(value):
		life = value
		life_changed.emit(self)


func _init(_id: int, _name: String, _domains: Array) -> void:
	id = _id
	display_name = _name
	domains = _domains


func deck() -> Pile:
	return FateZones.container("deck", id)


func hand() -> Hand:
	return FateZones.container("hand", id)


func discard() -> Pile:
	return FateZones.container("discard", id)


func removed() -> Pile:
	return FateZones.container("removed", id)


func grid(zone: String) -> BoardPlacementGrid:
	return FateZones.grid(zone, id)


# Moves the top card of the deck to the hand. Returns the card, or null if the deck is empty.
func draw_card() -> Card:
	var pile := deck()
	if not pile or not hand():
		return null
	var card: Card = pile.get_top_card()
	if card:
		card.move_to(hand(), -1, null, ["Scripted"])
	return card


# All cards a player currently has in a board grid
func cards_in_grid(zone: String) -> Array:
	var found := []
	var g := grid(zone)
	if not g:
		return found
	for slot in g.get_all_slots():
		if slot.occupying_card:
			found.append(slot.occupying_card)
	return found
