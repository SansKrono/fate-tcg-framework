# The surface of the Fate table: a dark vignette, a faint tint of each seat's domain colour,
# a glowing midline and the two side rails. Drawn behind everything, ignores the mouse.
class_name FateTableBackground
extends Control

const TINT_ALPHA := 0.1

# The domain colour of the player at the bottom and at the top
var bottom_color := FateTheme.NEUTRAL_DOMAIN
var top_color := FateTheme.NEUTRAL_DOMAIN
var _vignette: TextureRect


func _init() -> void:
	name = "TableBackground"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = FateLayout.SCREEN
	z_index = -10
	_vignette = TextureRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.size = FateLayout.SCREEN
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.set_color(0, FateTheme.BG_LIGHT)
	gradient.set_color(1, Color(0.1, 0.115, 0.18))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.45)
	texture.fill_to = Vector2(1.05, 1.05)
	texture.width = 256
	texture.height = 144
	_vignette.texture = texture
	add_child(_vignette)


func set_seat_colors(bottom: Color, top: Color) -> void:
	bottom_color = bottom
	top_color = top
	queue_redraw()


func _draw() -> void:
	var table_left := FateLayout.LEFT_RAIL_WIDTH
	var table_right := FateLayout.RIGHT_RAIL_X
	var mid := FateLayout.TABLE_MIDLINE
	# Each half of the table carries a hint of its player's domain
	draw_rect(Rect2(table_left, 0, table_right - table_left, mid), Color(top_color, TINT_ALPHA))
	draw_rect(Rect2(table_left, mid, table_right - table_left, FateLayout.SCREEN.y - mid),
			Color(bottom_color, TINT_ALPHA))
	# Rails
	draw_rect(Rect2(0, 0, table_left, FateLayout.SCREEN.y), FateTheme.RAIL)
	draw_rect(Rect2(table_right, 0, FateLayout.SCREEN.x - table_right, FateLayout.SCREEN.y),
			FateTheme.RAIL)
	var edge := Color(FateTheme.PANEL_BORDER, 0.5)
	draw_line(Vector2(table_left, 0), Vector2(table_left, FateLayout.SCREEN.y), edge, 1.0)
	draw_line(Vector2(table_right, 0), Vector2(table_right, FateLayout.SCREEN.y), edge, 1.0)
	# The midline: a soft gold glow under a thin line
	for i in range(4, 0, -1):
		draw_line(Vector2(table_left, mid), Vector2(table_right, mid),
				Color(FateTheme.GOLD, 0.025 * (5 - i)), float(i * 4))
	draw_line(Vector2(table_left + 20, mid), Vector2(table_right - 20, mid),
			Color(FateTheme.GOLD, 0.35), 1.0)
