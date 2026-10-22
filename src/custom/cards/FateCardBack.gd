# The back of every Fate card: the pixel-art card back (FateCardBack.tscn), with an eye shown on
# face-down cards the player has looked at.
extends CardBack


func _ready() -> void:
	viewed_node = %Viewed
