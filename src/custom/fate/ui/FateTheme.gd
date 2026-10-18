# The look of the Fate table: palette, fonts and style boxes, in one place.
#
# "Dark arcane": a deep navy table, charcoal panels, gold for whatever the player can act on,
# and one accent colour per domain. FateBoard sets build() as the theme of the table, so every
# Control on it (status bar, panels, buttons, the debug tools) inherits the same look; the
# helpers below are for the few nodes that need a variation (gold buttons, pills, badges).
class_name FateTheme
extends RefCounted

const BG := Color(0.13, 0.15, 0.22)
const BG_LIGHT := Color(0.25, 0.29, 0.42)
const PANEL := Color(0.16, 0.185, 0.27, 0.95)
const PANEL_BORDER := Color(0.5, 0.55, 0.74, 0.8)
const RAIL := Color(0.06, 0.07, 0.13, 0.35)
const TEXT := Color(0.97, 0.98, 1.0)
const MUTED := Color(0.74, 0.78, 0.89)
const GOLD := Color(0.95, 0.76, 0.3)
const GOLD_DARK := Color(0.55, 0.4, 0.12)
const DANGER := Color(0.85, 0.3, 0.3)
const LIFE := Color(0.92, 0.36, 0.4)
const DOMAIN_COLORS := {
	"Innovation": Color(0.9, 0.3, 0.32),
	"Primal": Color(0.36, 0.81, 0.42),
	"Order": Color(0.91, 0.82, 0.48),
	"Chaos": Color(0.62, 0.38, 0.92),
}
const NEUTRAL_DOMAIN := Color(0.6, 0.62, 0.7)

const FONT_PATH := "res://themes/darktheme/fonts/Oxanium/static/Oxanium-%s.ttf"
const FONT_SIZE := 13

static var _theme: Theme


static func font(weight := "Medium") -> Font:
	return load(FONT_PATH % weight)


static func domain_color(domain: String) -> Color:
	return DOMAIN_COLORS.get(domain, NEUTRAL_DOMAIN)


# The colour of a card: the colour of its first domain
static func card_color(card: Card) -> Color:
	var domains: Array = card.properties.get("_domains", [])
	return domain_color(domains[0]) if not domains.is_empty() else NEUTRAL_DOMAIN


# The theme of the table. Built once and shared.
static func build() -> Theme:
	if _theme:
		return _theme
	var theme := Theme.new()
	theme.default_font = font("Medium")
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color(MUTED, 0.8))
	theme.set_color("font_focus_color", "Button", TEXT)
	var normal := box(Color(0.22, 0.25, 0.37), PANEL_BORDER, 6, 1)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", box(Color(0.29, 0.33, 0.48), Color(GOLD, 0.8), 6, 1))
	theme.set_stylebox("pressed", "Button", box(Color(0.17, 0.19, 0.29), GOLD, 6, 1))
	theme.set_stylebox("hover_pressed", "Button", box(Color(0.19, 0.21, 0.32), GOLD, 6, 1))
	theme.set_stylebox("disabled", "Button", box(Color(0.15, 0.17, 0.24), Color(PANEL_BORDER, 0.4), 6, 1))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_stylebox("normal", "LineEdit", box(Color(0.09, 0.105, 0.16), PANEL_BORDER, 4, 1))
	theme.set_stylebox("focus", "LineEdit", box(Color(0.09, 0.105, 0.16), Color(GOLD, 0.7), 4, 1))
	theme.set_stylebox("panel", "ItemList", box(Color(0.09, 0.105, 0.16), PANEL_BORDER, 4, 1))
	theme.set_stylebox("selected", "ItemList", box(Color(GOLD_DARK, 0.7), Color.TRANSPARENT, 3, 0))
	theme.set_stylebox("selected_focus", "ItemList", box(Color(GOLD_DARK, 0.85), Color.TRANSPARENT, 3, 0))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_stylebox("panel", "TooltipPanel", panel_box())
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	_theme = theme
	return theme


# A rounded box with an optional border
static func box(bg: Color, border := Color.TRANSPARENT, radius := 6, border_width := 1,
		margin := 6.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin + 2
	style.content_margin_right = margin + 2
	style.content_margin_top = margin * 0.5
	style.content_margin_bottom = margin * 0.5
	style.anti_aliasing = true
	return style


# The background of the HUD panels (player plates, the action panel, the log)
static func panel_box() -> StyleBoxFlat:
	var style := box(PANEL, PANEL_BORDER, 10, 1, 8.0)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 6
	return style


# A small rounded label background ("pills" of the phase strip, mana chips, counters)
static func pill_box(bg: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := box(bg, border, 9, 1, 4.0)
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


# The outline of a zone on the table: barely there, so the cards stand out
static func zone_box() -> StyleBoxFlat:
	var style := box(Color(1, 1, 1, 0.07), Color(0.7, 0.76, 0.92, 0.4), 8, 1, 0.0)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


# Gives a button the gold "this is the thing to do" look of the main action
static func make_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(Color(0.62, 0.45, 0.13), GOLD, 8, 1))
	button.add_theme_stylebox_override("hover", box(Color(0.75, 0.56, 0.18), Color(1, 0.9, 0.6), 8, 1))
	button.add_theme_stylebox_override("pressed", box(Color(0.5, 0.36, 0.1), GOLD, 8, 1))
	button.add_theme_stylebox_override("disabled", box(Color(0.16, 0.15, 0.13), Color(GOLD_DARK, 0.4), 8, 1))
	button.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.0, 0.8))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_font_override("font", font("Bold"))


# A label with the table font
static func label(text := "", size := FONT_SIZE, color := TEXT, weight := "Medium") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
