extends CardBackGlow

var font_scaled : float = 1

func _ready() -> void:
	# Godot 4 no longer calls the parent _ready() automatically
	super._ready()
	viewed_node = $Viewed
	
# Since we have a label on top of our image, we use this to scale the label
# as well
# We don't care about the viewed icon, since it will never be visible
# in the viewport focus.
func scale_to(scale_multiplier: float) -> void:	
	if font_scaled != scale_multiplier:
		var label : Label = $Label
		label.custom_minimum_size *= scale_multiplier
		# We need to adjust the Viewed Container
		# a bit more to make the text land in the middle
#		$"VBoxContainer/CenterContainer".rect_min_size *= scale_multiplier * 1.5
		# In Godot 4 the font size is a theme property, separate from the font
		var label_font_size : int = label.get_theme_font_size("font_size")
		label_font_size = int(label_font_size * scale_multiplier)
		label.add_theme_font_size_override("font_size", label_font_size)
		font_scaled = scale_multiplier
	
