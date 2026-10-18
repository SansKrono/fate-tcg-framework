# The big centred messages of the table: "Player 2's turn" fades in and out when a turn starts,
# "Player 1 wins" stays when the game ends.
class_name FateTurnBanner
extends Label

const SIZE := Vector2(560, 84)
const SHOW_TIME := 0.9

var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	size = SIZE
	custom_minimum_size = SIZE
	position = Vector2((FateLayout.LEFT_RAIL_WIDTH + FateLayout.RIGHT_RAIL_X) / 2.0 - SIZE.x / 2.0,
			FateLayout.TABLE_MIDLINE - SIZE.y / 2.0)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_override("font", FateTheme.font("Bold"))
	add_theme_font_size_override("font_size", 40)
	add_theme_color_override("font_color", FateTheme.GOLD)
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0))
	add_theme_constant_override("outline_size", 10)
	var backdrop := FateTheme.box(Color(0.02, 0.025, 0.05, 0.88), Color(FateTheme.GOLD, 0.7), 14, 2)
	backdrop.shadow_color = Color(0, 0, 0, 0.6)
	backdrop.shadow_size = 18
	add_theme_stylebox_override("normal", backdrop)
	visible = false


# Shows the text for a moment (or for good with stay = true)
func flash(message: String, stay := false) -> void:
	text = message
	visible = true
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	scale = Vector2(0.92, 0.92)
	pivot_offset = SIZE / 2.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if stay:
		return
	_tween.tween_interval(SHOW_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(func(): visible = false)
