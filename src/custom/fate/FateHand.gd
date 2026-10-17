# The hand of a Fate player. The second player's hand hangs from the top edge of the screen.
extends Hand

# True for the hand at the top of the screen
@export var mirrored := false


func re_place() -> void:
	await super.re_place()
	if mirrored:
		position.y = -bottom_margin
		for c in get_all_cards():
			c.position = c.recalculate_position()
