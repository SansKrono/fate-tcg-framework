# The phase strip on the midline: one pill per phase of the turn, the current one lit in gold
# (red for the combat steps). It pulses briefly when the phase changes.
class_name FatePhaseStrip
extends HBoxContainer

const PHASES := [
	[FateTurn.Phase.MAINTENANCE, "Untap"],
	[FateTurn.Phase.DRAW, "Draw"],
	[FateTurn.Phase.ENERGY, "Energy"],
	[FateTurn.Phase.MAIN, "Main"],
	[FateTurn.Phase.COMBAT_DECLARE, "Attack"],
	[FateTurn.Phase.COMBAT_INTERCEPT, "Block"],
	[FateTurn.Phase.COMBAT_RESOLVE, "Resolve"],
	[FateTurn.Phase.END, "End"],
]
const COMBAT_COLOR := Color(0.78, 0.25, 0.25)

var current := -1
var _pills := {}


func _init() -> void:
	name = "PhaseStrip"
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in PHASES:
		var pill := Label.new()
		pill.text = entry[1]
		pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.custom_minimum_size = Vector2(52, 20)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_theme_font_override("font", FateTheme.font("SemiBold"))
		pill.add_theme_font_size_override("font_size", 11)
		pill.pivot_offset = pill.custom_minimum_size / 2.0
		add_child(pill)
		_pills[entry[0]] = pill
	set_phase(-1)


func set_phase(phase: int) -> void:
	var changed := phase != current
	current = phase
	for p in _pills:
		var pill: Label = _pills[p]
		var lit: bool = p == phase
		var accent: Color = COMBAT_COLOR if p in FateTurn.COMBAT_HOOKS else FateTheme.GOLD
		if lit:
			pill.add_theme_stylebox_override("normal", FateTheme.pill_box(Color(accent, 0.9), accent.lightened(0.3)))
			pill.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
		else:
			pill.add_theme_stylebox_override("normal", FateTheme.pill_box(Color(1, 1, 1, 0.1),
					Color(FateTheme.PANEL_BORDER, 0.5)))
			pill.add_theme_color_override("font_color", FateTheme.MUTED)
		if lit and changed and is_inside_tree():
			pill.scale = Vector2(1.18, 1.18)
			create_tween().tween_property(pill, "scale", Vector2.ONE, 0.25) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
