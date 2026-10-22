# One pip of a card's cost, in the pip art of the prototype (assets/fate/cards): a domain pip (the
# domain's emblem) or the generic pip, which carries the colourless cost as its number.
#
# The art has a margin around the pip, so the control is a little larger than the pip it draws.
# FateCardFront stacks them from the top left corner: the domain pips first, the generic one last.
@tool
class_name FateCostPip
extends Control

const PIP_DIR := "res://assets/fate/cards/%s Cost Pip.png"
const GENERIC := ""

# The domain whose emblem the pip shows; empty: the generic pip
@export var domain := GENERIC:
	set(value):
		domain = value
		_refresh()
# The number on the generic pip
@export var text := "0":
	set(value):
		text = value
		_refresh()

@onready var _art: TextureRect = $Art
@onready var _value: Label = $Value


func _ready() -> void:
	_refresh()


# The label holding the number (the card front registers it in card_labels)
func value_label() -> Label:
	return $Value


func _refresh() -> void:
	if not is_node_ready():
		return
	_art.texture = load(PIP_DIR % (domain if domain != GENERIC else "Generic"))
	_value.visible = domain == GENERIC
	_value.text = text
