# The action panel in the right rail: what to do now, and the one big button that does it.
#
# In the energy phase the big button draws the extra card (playing energy is a double-click on a
# hand card); in every other phase it moves the turn on, with a label that says what that means
# ("To combat", "Confirm attacks"...). "End turn" is the smaller button below it.
class_name FateActionPanel
extends PanelContainer

const NEXT_LABELS := {
	FateTurn.Phase.MAIN: "To combat",
	FateTurn.Phase.COMBAT_DECLARE: "Confirm attacks",
	FateTurn.Phase.COMBAT_INTERCEPT: "Confirm blocks",
	FateTurn.Phase.COMBAT_RESOLVE: "Continue",
	FateTurn.Phase.END: "Continue",
}

var prompt_label: Label
var draw_button: Button
var next_button: Button
var end_turn_button: Button


func _init() -> void:
	name = "ActionPanel"
	position = FateLayout.ACTION_RECT.position
	custom_minimum_size = FateLayout.ACTION_RECT.size
	size = FateLayout.ACTION_RECT.size
	add_theme_stylebox_override("panel", FateTheme.panel_box())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	prompt_label = FateTheme.label("", 12, FateTheme.TEXT, "Medium")
	prompt_label.name = "Prompt"
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prompt_label.clip_text = true
	prompt_label.custom_minimum_size = Vector2(FateLayout.ACTION_RECT.size.x - 20, 40)
	column.add_child(prompt_label)
	draw_button = _button("Draw extra card", 36)
	next_button = _button("Next phase", 36)
	FateTheme.make_primary(draw_button)
	FateTheme.make_primary(next_button)
	end_turn_button = _button("End turn", 24)
	end_turn_button.add_theme_font_size_override("font_size", 12)
	for b in [draw_button, next_button, end_turn_button]:
		column.add_child(b)
	set_phase(FateTurn.Phase.NONE)


func _button(text: String, height: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	return button


# Shows the right big button for the phase, with the right label
func set_phase(phase: int) -> void:
	var energy := phase == FateTurn.Phase.ENERGY
	draw_button.visible = energy
	next_button.visible = not energy
	next_button.text = NEXT_LABELS.get(phase, "Next phase")
