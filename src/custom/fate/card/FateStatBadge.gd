# A stat on a Fate card (Strike or Guard): the stat's icon and its number, drawn on the parchment
# box of the card frame (the badge is the size of that box).
#
# The number reacts to play: shown above its printed value (`base_text`) it turns green, below it
# red, and every change makes the badge pop. Works in the editor (@tool) so the card scenes preview
# with real values.
@tool
class_name FateStatBadge
extends Control

# Darker than usual: the number sits on parchment
const UP_COLOR := Color(0.1, 0.5, 0.12)
const DOWN_COLOR := Color(0.78, 0.12, 0.1)
const BASE_COLOR := Color(0.17, 0.1, 0.05)
const POP_SCALE := 1.3

@export var icon: Texture2D:
	set(value):
		icon = value
		_refresh()
# The number shown. Text, so that values like "X" work; compared as numbers when they are numbers
@export var text := "0":
	set(value):
		var changed := text != value
		text = value
		_refresh()
		# The first value is the card being set up, not a change in play
		if changed and _has_value and is_visible_in_tree() and not Engine.is_editor_hint():
			pop()
		_has_value = is_node_ready()
# The printed value: the number is coloured when it differs. Empty: never coloured
@export var base_text := "":
	set(value):
		base_text = value
		_refresh()

@onready var _icon: TextureRect = $Icon
@onready var _value: Label = $Value
var _pop: Tween
var _has_value := false


func _ready() -> void:
	_refresh()


# The label holding the number (the card front registers it in card_labels)
func value_label() -> Label:
	return $Value


func _refresh() -> void:
	if not is_node_ready():
		return
	_icon.texture = icon
	_icon.visible = icon != null
	_value.text = text
	_value.add_theme_color_override("font_color", _value_color())


func _value_color() -> Color:
	if base_text == "" or not text.is_valid_int() or not base_text.is_valid_int():
		return BASE_COLOR
	var delta := text.to_int() - base_text.to_int()
	return UP_COLOR if delta > 0 else DOWN_COLOR if delta < 0 else BASE_COLOR


# A quick swell and settle of the number, to draw the eye to a change (the badge itself keeps the
# scale its card face gives it)
func pop() -> void:
	if _pop:
		_pop.kill()
	_value.pivot_offset = _value.size / 2.0
	_value.scale = Vector2.ONE * POP_SCALE
	_pop = create_tween()
	_pop.tween_property(_value, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
