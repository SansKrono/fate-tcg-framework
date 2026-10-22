# Tilt, lift, shadow and rarity foil of a Fate card.
#
# The movement of the card prototype (reference_card_scenes/card.gd) on top of the regular card:
# - the card tilts towards the mouse while it is hovered, and leans into its motion while it moves
# - it rises (grows a little, its shadow drifts off and fades) while it is dragged or focused
# - a soft shadow lies under it
# - its rarity (FateRarity) adds the BinbunVFX foil / holo / shimmer, which follows the tilt
#
# The card itself is not changed. Three nodes are added to its $Control: a shadow sprite drawn first,
# and after the front a BackBufferCopy of the card's area followed by this node, whose shader re-draws
# that copy tilted in perspective with the rarity effects (fate_card_fx.gdshader). All three are
# Node2D, so they take no mouse input and the card's resize_recursively() leaves them alone. While the
# card lies flat and has no foil, the overlay is hidden and costs nothing.
class_name FateCardFx
extends Node2D

const NODE_NAME := "CardFx"
const COPY_NAME := "CardFxCopy"
const SHADOW_NAME := "CardFxShadow"
const SHADER := preload("res://src/custom/fate/ui/fate_card_fx.gdshader")

const MAX_TILT := deg_to_rad(10.0)
const TILT_SPEED := 10.0
const MAX_SPEED := 1500.0      # px/s that gives full velocity tilt
const VELOCITY_SMOOTH := 12.0  # higher = snappier, lower = floatier
const TELEPORT_SPEED := 20000.0  # faster than this, the card was moved, not animated: no tilt
const LIFT_SPEED := 14.0
const LIFT_GROW := 0.06        # the card's growth when fully lifted
const FOCUS_LIFT := 0.4        # lift of a card under the mouse
const CAM_DIST := 2.2          # distance of the eye, in card heights
const MARGIN := 0.25           # room around the card for the tilted, lifted card, in card sizes
const PREVIEW_SWAY := 0.45     # idle sway of the card in the detail dock, in MAX_TILT
const PREVIEW_PAD := 0.07      # room around the card in the detail dock for its tilt, in card sizes
const GLOW_SPEED := 10.0

const SHADOW_MARGIN := 40      # px of soft falloff around the card
const SHADOW_BLUR := 24.0
const SHADOW_REST_OFFSET := Vector2(2, 4)
const SHADOW_LIFT_OFFSET := Vector2(10, 22)   # extra offset when fully lifted
const SHADOW_REST_ALPHA := 0.35
const SHADOW_LIFT_ALPHA := 0.25
const SHADOW_LIFT_GROW := 0.08
const SHADOW_TILT_SHIFT := 10.0   # px shadow slides at full tilt

# Parts of the card where the colour effects are toned down, as (x, y, x2, y2) in 0..1 card space.
# Full card: pips, rules text, Strike, Guard. Table face: pips, name, Strike and Guard badges.
const PROTECT_FULL := [Vector4(0.0, 0.0, 0.13, 0.42), Vector4(0.07, 0.63, 0.93, 0.88),
		Vector4(0.03, 0.88, 0.27, 0.97), Vector4(0.73, 0.88, 0.97, 0.97)]
const PROTECT_TABLE := [Vector4(0.0, 0.0, 0.2, 0.5), Vector4(0.09, 0.22, 0.91, 0.53),
		Vector4(0.05, 0.69, 0.95, 0.9), Vector4.ZERO]
# Corner radius of the card art, and the widths of the gold rim and the playable glow, in card pixels
const CORNER_RADIUS := 6.0
const RIM_WIDTH := 9.0
const GLOW_WIDTH := 3.5
const GLOW_HALO := 10.0

static var _shadow_texture: ImageTexture

var card: Card
var rarity := FateRarity.COMMON
var tilt := Vector2.ZERO
var lift := 0.0
# The playable glow (FateCardTemplate.set_playable): `glowing` is asked for, `glow` fades towards it
var glowing := false
var glow := 0.0

var _fx: Dictionary = FateRarity.fx_of(FateRarity.COMMON)
var _rarity_for := ""
var _copy: BackBufferCopy
var _shadow: Sprite2D
var _material: ShaderMaterial
var _size := Vector2.ZERO
var _prev_pos := Vector2.ZERO
var _velocity := Vector2.ZERO
var _table_mode := false
var _time := 0.0
var _phase := 0.0


# Adds the effects to a card, or takes over the ones a duplicated card brought along
static func attach(to_card: Card) -> FateCardFx:
	var control: Control = to_card.get_node("Control")
	var fx := control.get_node_or_null(NODE_NAME) as FateCardFx
	if fx == null:
		fx = FateCardFx.new()
		fx.name = NODE_NAME
		control.add_child(fx)
	fx.card = to_card
	fx._setup()
	return fx


func _setup() -> void:
	var control := get_parent() as Control
	_copy = control.get_node_or_null(COPY_NAME)
	if _copy == null:
		_copy = BackBufferCopy.new()
		_copy.name = COPY_NAME
		_copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
		control.add_child(_copy)
	_shadow = control.get_node_or_null(SHADOW_NAME)
	if _shadow == null:
		_shadow = Sprite2D.new()
		_shadow.name = SHADOW_NAME
		control.add_child(_shadow)
	if _shadow_texture == null:
		_shadow_texture = _make_shadow_texture()
	_shadow.texture = _shadow_texture
	control.move_child(_shadow, 0)
	# Right over the front (and the back): the tokens and buttons stay flat on top
	var front: Node = control.get_node_or_null("Front")
	var at := front.get_index() + 1 if front else control.get_child_count() - 1
	control.move_child(_copy, at)
	control.move_child(self, _copy.get_index() + 1)
	# Always a material of its own: a duplicated card shares the original's
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	_material.set_shader_parameter("glow_color", FateCardTemplate.PLAYABLE_COLOR)
	_phase = randf() * TAU
	_prev_pos = card.global_position
	_size = Vector2.ZERO
	_rarity_for = ""
	_refresh()
	_update(0.0)


func _refresh() -> void:
	# The card's own size: an enlarged card (the detail dock) is scaled as a whole
	if card.canonical_size != _size:
		_size = card.canonical_size
		var ratio := _size.y / FateLayout.CARD_SIZE.y
		_material.set_shader_parameter("card_size", _size)
		_material.set_shader_parameter("corner_radius", CORNER_RADIUS * ratio)
		_material.set_shader_parameter("rim_width", RIM_WIDTH * ratio)
		_material.set_shader_parameter("glow_width", GLOW_WIDTH * ratio)
		_material.set_shader_parameter("glow_halo", GLOW_HALO * ratio)
		_material.set_shader_parameter("cam_dist", _size.y * CAM_DIST)
		queue_redraw()
	if card.canonical_name != _rarity_for:
		_rarity_for = card.canonical_name
		set_rarity(FateRarity.of_card(card))
	var front = card.card_front
	var table_mode: bool = front != null and front.get("table_mode") == true
	if table_mode != _table_mode:
		_table_mode = table_mode
		_apply_protect()


func set_rarity(value: int) -> void:
	rarity = value
	_fx = FateRarity.fx_of(value)
	for param in ["holo_amount", "shimmer_strength", "effect_steps", "effect_size", "view_affect",
			"glare", "rim_amount", "protect_amount"]:
		_material.set_shader_parameter(param, _fx[param])
	_material.set_shader_parameter("rim_color", _fx.get("rim_color", Color.WHITE))
	_apply_protect()
	if card.card_front and card.card_front.has_method("set_rarity"):
		card.card_front.set_rarity(value)


func _apply_protect() -> void:
	var rects: Array = PROTECT_TABLE if _table_mode else PROTECT_FULL
	for i in rects.size():
		_material.set_shader_parameter("protect_%d" % i, rects[i])


func _draw() -> void:
	draw_rect(Rect2(-_size * MARGIN, _size * (1.0 + MARGIN * 2.0)), Color.WHITE)


func _process(delta: float) -> void:
	if card == null or not is_instance_valid(card):
		return
	_refresh()
	_update(delta)


func _update(delta: float) -> void:
	_time += delta
	var control := get_parent() as Control
	var hidden: bool = not card.is_visible_in_tree() or card.state == Card.CardState.IN_PILE
	# Velocity from the actual movement, smoothed
	var pos := card.global_position
	if delta > 0.0:
		var raw := (pos - _prev_pos) / delta
		if raw.length() > TELEPORT_SPEED:
			raw = Vector2.ZERO
		_velocity = _velocity.lerp(raw, clampf(delta * VELOCITY_SMOOTH, 0.0, 1.0))
	_prev_pos = pos
	var rotation_on_screen := control.get_global_transform().get_rotation()
	var vel_tilt := (_velocity.rotated(-rotation_on_screen) / MAX_SPEED).limit_length(1.0) * MAX_TILT
	# The hovered (or dragged) card leans towards the mouse; the card in the detail dock sways
	var hover_tilt := Vector2.ZERO
	if not hidden and _may_hover():
		var local := control.get_local_mouse_position()
		if Rect2(Vector2.ZERO, _size).has_point(local):
			hover_tilt = (local - _size * 0.5) / (_size * 0.5) * MAX_TILT
	if card.state in [Card.CardState.VIEWPORT_FOCUS, Card.CardState.PREVIEW]:
		hover_tilt += Vector2(sin(_time * 0.9 + _phase), cos(_time * 0.7 + _phase)) \
				* MAX_TILT * PREVIEW_SWAY
	var target := (hover_tilt + vel_tilt).limit_length(MAX_TILT)
	tilt = tilt.lerp(target, clampf(delta * TILT_SPEED, 0.0, 1.0))
	var lift_target := 0.0
	match card.state:
		Card.CardState.DRAGGED:
			lift_target = 1.0
		Card.CardState.FOCUSED_IN_HAND, Card.CardState.FOCUSED_ON_BOARD, \
				Card.CardState.FOCUSED_IN_POPUP:
			lift_target = FOCUS_LIFT
	lift = lerpf(lift, lift_target, clampf(delta * LIFT_SPEED, 0.0, 1.0))
	glow = move_toward(glow, 1.0 if glowing else 0.0, delta * GLOW_SPEED) if delta > 0.0 \
			else (1.0 if glowing else 0.0)

	var foil: bool = _fx.fx and card.is_faceup
	var moving := tilt.length() > 0.002 or lift > 0.01
	visible = not hidden and (foil or moving or glow > 0.0)
	_copy.visible = visible
	_update_highlight()
	_shadow.visible = not hidden
	_update_shadow(rotation_on_screen)
	if not visible:
		return
	if card.state == Card.CardState.VIEWPORT_FOCUS:
		_frame_preview()
	_place_copy()
	var fit := fit_scale(tilt, _size, _size.y * CAM_DIST) * (1.0 + LIFT_GROW * lift)
	_material.set_shader_parameter("tilt", tilt)
	_material.set_shader_parameter("fit_scale", fit)
	_material.set_shader_parameter("fx_amount", 1.0 if foil else 0.0)
	_material.set_shader_parameter("glow_amount", glow)
	var sweep := Vector2(sin(_time * 0.6 + _phase), cos(_time * 0.45 + _phase * 1.3))
	_material.set_shader_parameter("sweep", sweep * float(_fx.idle_sweep))


# While the overlay is shown it draws the card's highlight border around the tilted card, and the
# framework's flat border is hidden (its parts only: Highlight.visible still says whether it is on).
func _update_highlight() -> void:
	var highlight: Control = card.get("highlight")
	if highlight == null:
		return
	for part in highlight.get_children():
		if part is CanvasItem:
			part.visible = not visible
	var on := visible and highlight.visible
	_material.set_shader_parameter("highlight_amount", 1.0 if on else 0.0)
	if on:
		_material.set_shader_parameter("highlight_color", highlight.modulate)


# The card in the detail dock fills the dock's viewport, which would cut off its tilted edges: it is
# scaled down a little and the viewport's camera centres it, leaving PREVIEW_PAD around it.
func _frame_preview() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	# The camera zooms in: the viewport shows view / zoom of the world
	var zoom := (get_viewport().get_final_transform() * get_viewport().get_canvas_transform()).get_scale()
	var view := Vector2(get_viewport().get_visible_rect().size) / zoom
	var control := get_parent() as Control
	var room := _size * control.scale * (1.0 + PREVIEW_PAD * 2.0)
	var fit := minf(1.0, minf(view.x / room.x, view.y / room.y))
	card.scale = Vector2.ONE * fit
	var on_canvas: Rect2 = control.get_global_transform() * Rect2(Vector2.ZERO, _size)
	camera.position = on_canvas.get_center() - view * 0.5


# The renderer copies the BackBufferCopy rect as it is, in render target pixels: it applies neither
# the node's transform nor the window's stretch (stretch mode "canvas_items" draws the 1280x720
# design at the window's size). So the rect is the card's area (with room for the tilt) in pixels.
func _place_copy() -> void:
	var area := Rect2(-_size * MARGIN, _size * (1.0 + MARGIN * 2.0))
	var to_pixels := get_viewport().get_final_transform() * _copy.get_global_transform_with_canvas()
	_copy.rect = (to_pixels * area).grow(2.0)


# Only the dragged card, or else the card the board has focused, reacts to the mouse. Outside the
# table (deckbuilder, card viewer) the card under the mouse does.
func _may_hover() -> bool:
	if card.get("concealed") == true or card.state == Card.CardState.VIEWPORT_FOCUS:
		return false
	if card.state == Card.CardState.DRAGGED:
		return true
	var board = cfc.NMAP.get("board")
	if board == null or not is_instance_valid(board) or board.get("mouse_pointer") == null:
		return true
	if board.is_ancestor_of(card):
		return board.mouse_pointer.current_focused_card == card
	return true


# Shadow follows lift and tilt: it shifts away from the raised edge and foreshortens with the card.
# Its offset points down-right on the screen, whatever the card's rotation.
func _update_shadow(rotation_on_screen: float) -> void:
	var offset := SHADOW_REST_OFFSET + SHADOW_LIFT_OFFSET * lift
	_shadow.position = _size * 0.5 + offset.rotated(-rotation_on_screen) \
			- (tilt / MAX_TILT) * SHADOW_TILT_SHIFT
	_shadow.scale = Vector2(cos(tilt.x), cos(tilt.y)) * (1.0 + SHADOW_LIFT_GROW * lift) \
			* (_size / FateLayout.CARD_SIZE)
	_shadow.modulate.a = lerpf(SHADOW_REST_ALPHA, SHADOW_LIFT_ALPHA, clampf(lift, 0.0, 1.0))


# How much the tilted card must grow to cover the flat card under it: the corners of the tilted card
# (seen in perspective from `cam_dist`) must lie outside the flat card's corners.
static func fit_scale(card_tilt: Vector2, size: Vector2, cam_dist: float) -> float:
	if card_tilt.length() < 0.0001 or size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	var n := Vector3(tan(card_tilt.x), tan(card_tilt.y), 1.0).normalized()
	var u := (Vector3(1, 0, 0) - n * n.x).normalized()
	var v := n.cross(u)
	var worst := 1.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var flat: Vector2 = corner * size * 0.5
		var p: Vector3 = u * flat.x + v * flat.y
		var seen := Vector2(p.x, p.y) * cam_dist / (cam_dist - p.z)
		worst = minf(worst, minf(absf(seen.x / flat.x), absf(seen.y / flat.y)))
	return 1.0 / maxf(worst, 0.5)


static func _make_shadow_texture() -> ImageTexture:
	var half := FateLayout.CARD_SIZE * 0.5
	var size := Vector2i(int(half.x * 2.0) + SHADOW_MARGIN * 2, int(half.y * 2.0) + SHADOW_MARGIN * 2)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size) * 0.5
	var corner := CORNER_RADIUS
	var inner := half - Vector2(corner, corner)
	for y in size.y:
		for x in size.x:
			var q := (Vector2(x + 0.5, y + 0.5) - center).abs() - inner
			var d := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - corner
			var a := 1.0 - smoothstep(-SHADOW_BLUR * 0.3, SHADOW_BLUR, d)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return ImageTexture.create_from_image(img)
