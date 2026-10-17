# The clickable stand-in of a player on the table: "Player 1, life 20". In the declare step the
# active player clicks it to attack the player directly (see FateCombatUI). One per player.
class_name FatePlayerAvatar
extends Button

const SIZE := Vector2(140, 30)
const FONT_SIZE := 12

var player: FatePlayer
var _style_color := Color(0.17, 0.2, 0.28)


func _init(avatar_player: FatePlayer) -> void:
	player = avatar_player
	name = "PlayerAvatar_P%d" % player.id
	custom_minimum_size = SIZE
	size = SIZE
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("font_size", FONT_SIZE)
	set_highlight(false)
	player.life_changed.connect(func(_p): refresh())
	refresh()


func refresh() -> void:
	text = "Player %d, life %d" % [player.id, player.life]


# Marks the avatar as something the current click can target
func set_highlight(on: bool) -> void:
	_style_color = Color(0.55, 0.15, 0.15) if on else Color(0.17, 0.2, 0.28)
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = _style_color.lightened(0.15) if style == "hover" else _style_color
		box.set_border_width_all(2 if on else 1)
		box.border_color = Color(1.0, 0.8, 0.3) if on else Color(0.4, 0.45, 0.55)
		box.set_corner_radius_all(4)
		add_theme_stylebox_override(style, box)
