# The back of every Fate card: a navy panel with a gold double frame, a faint radial rune
# glow and the FATE wordmark. Built in code so it needs no art.
extends CardBack

const SIZE := Vector2(150, 240)
const WORDMARK_SIZE := 30

var font_scaled := 1.0
var _wordmark: Label


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer := FateTheme.box(Color(0.07, 0.08, 0.14), FateTheme.GOLD_DARK, 10, 3, 0.0)
	add_theme_stylebox_override("panel", outer)
	var glow := TextureRect.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = Vector2(8, 8)
	glow.size = SIZE - Vector2(16, 16)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.3, 0.26, 0.5, 0.75))
	gradient.set_color(1, Color(0.07, 0.08, 0.14, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.85)
	glow.texture = texture
	add_child(glow)
	var inner := Panel.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.position = Vector2(9, 9)
	inner.size = SIZE - Vector2(18, 18)
	inner.add_theme_stylebox_override("panel",
			FateTheme.box(Color.TRANSPARENT, Color(FateTheme.GOLD, 0.45), 6, 1, 0.0))
	add_child(inner)
	var diamond := Panel.new()
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diamond.size = Vector2(46, 46)
	diamond.pivot_offset = diamond.size / 2.0
	diamond.position = SIZE / 2.0 - diamond.size / 2.0
	diamond.rotation_degrees = 45
	diamond.add_theme_stylebox_override("panel",
			FateTheme.box(Color(0.1, 0.1, 0.18, 0.9), Color(FateTheme.GOLD, 0.7), 4, 2, 0.0))
	add_child(diamond)
	_wordmark = FateTheme.label("FATE", WORDMARK_SIZE, FateTheme.GOLD, "Bold")
	_wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wordmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wordmark.size = Vector2(SIZE.x, 40)
	_wordmark.position = Vector2(0, SIZE.y / 2.0 - 20)
	_wordmark.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.1))
	_wordmark.add_theme_constant_override("outline_size", 8)
	add_child(_wordmark)
	# The eye shown on face-down cards the player has looked at
	var viewed := TextureRect.new()
	viewed.name = "Viewed"
	viewed.visible = false
	viewed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewed.texture = load("res://assets/icons/view.svg")
	viewed.modulate = Color(1.5, 1.2, 0.4)
	viewed.position = Vector2(55, 30)
	viewed.size = Vector2(40, 40)
	viewed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(viewed)
	viewed_node = viewed


# The magnifier shows the back bigger: the frame, the emblem and the wordmark grow with it
func scale_to(scale_multiplier: float) -> void:
	if font_scaled == scale_multiplier or _wordmark == null:
		return
	var factor := scale_multiplier / font_scaled
	for child in get_children():
		if child is Control:
			child.position *= factor
			child.size *= factor
			child.pivot_offset *= factor
	_wordmark.add_theme_font_size_override("font_size", int(WORDMARK_SIZE * scale_multiplier))
	font_scaled = scale_multiplier
