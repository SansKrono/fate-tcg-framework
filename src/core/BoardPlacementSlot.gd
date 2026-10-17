# Represents a spot on the placement grid that is used to organize
# cards on the board.
class_name BoardPlacementSlot
extends Control

# If a card is placed on this spot, this variable will hold a reference
# to the Card object
# and no other card can be placed in this slot
var occupying_card = null

# Stores a reference to the owning BoardPlacementGrid object
@onready var owner_grid = get_parent().get_parent()

func _ready() -> void:
	# We set the initial size of our highlight and area, to 
	# fit the size of the cards on the board.
	custom_minimum_size = owner_grid.card_size * owner_grid.card_play_scale
	size = custom_minimum_size
	# The highlight is a container whose child panels have their own minimum size
	# in the scene (the size of a card at the default play scale). The container can
	# never be smaller than its children, so they all have to follow the slot size
	# or the highlight would stay oversized when the grid uses another card scale.
	$Highlight.custom_minimum_size = custom_minimum_size
	for panel in $Highlight.get_children():
		panel.custom_minimum_size = custom_minimum_size
	$Highlight.size = custom_minimum_size
	# The shape resource is shared by all slot instances, so we give each slot its own
	# copy, otherwise grids using different card scales would overwrite each other.
	$Area2D/CollisionShape2D.shape = $Area2D/CollisionShape2D.shape.duplicate()
	$Area2D/CollisionShape2D.shape.size = custom_minimum_size
	$Area2D/CollisionShape2D.position = custom_minimum_size / 2


# Returns true if this slot is highlighted, else false
func is_highlighted() -> bool:
	return($Highlight.visible)


# Changes card highlight colour.
func set_highlight(requested: bool,
		hoverColour = owner_grid.highlight) -> void:
	$Highlight.visible = requested
	if requested:
		$Highlight.modulate = hoverColour


# Returns the name of the grid which is hosting this slot.
# This is typically used with CFConst.BoardDropPlacement.SPECIFIC_GRID
func get_grid_name() -> String:
	return(owner_grid.name_label.text)
