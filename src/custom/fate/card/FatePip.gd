# One domain pip of a card's cost: a small orb in the domain's colour (FateCardFront adds one per
# letter of the card's Pips).
@tool
class_name FatePip
extends TextureRect

@export var color := Color(0.38, 0.62, 0.83):
	set(value):
		color = value
		if material:
			(material as ShaderMaterial).set_shader_parameter("tint", color)


func _ready() -> void:
	color = color
