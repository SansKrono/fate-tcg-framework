# Front of a Fate card.
#
# Maps the Fate card properties to their labels. Creatures show Strike and
# Guard; relics, spells and doctrines hide them (has_combat_stats = false).
#
# Layout: the name along the top, the mana cost running down the top left (one pip per domain
# pip, then a grey pip with the colourless amount), artwork, the type (sideways) and effect
# text under it, Guard on the right edge and Strike at the bottom. The card background takes the
# colour of the card's domain.
extends CardFront

const BG_DARKEN := 0.55
const PIP_COLORLESS := Color(0.6, 0.62, 0.68)
const PIP_SIZE := 18

# Set on the per-type front scenes (CreatureFront, RelicFront etc.)
@export var has_combat_stats := true


func _ready() -> void:
	card_labels["Name"] = find_child("Name")
	card_labels["Type"] = find_child("Type")
	card_labels["Tags"] = find_child("Tags")
	card_labels["Domain"] = find_child("Domain")
	card_labels["Abilities"] = find_child("Abilities")
	card_labels["Cost"] = find_child("Cost")
	card_labels["Pips"] = find_child("Pips")
	card_labels["Strike"] = find_child("Strike")
	card_labels["Guard"] = find_child("Guard")

	card_label_min_sizes["Name"] = Vector2(102, 16)
	card_label_min_sizes["Type"] = Vector2(90, 12)
	card_label_min_sizes["Tags"] = Vector2(109, 10)
	card_label_min_sizes["Domain"] = Vector2(100, 11)
	card_label_min_sizes["Abilities"] = Vector2(109, 77)
	card_label_min_sizes["Cost"] = Vector2(16, 16)
	card_label_min_sizes["Pips"] = Vector2(16, 16)
	card_label_min_sizes["Strike"] = Vector2(16, 16)
	card_label_min_sizes["Guard"] = Vector2(16, 20)

	for l in card_label_min_sizes:
		card_labels[l].custom_minimum_size = card_label_min_sizes[l]

	for label in card_labels:
		match label:
			"Cost", "Pips", "Strike", "Guard":
				original_font_sizes[label] = 13
			"Domain":
				original_font_sizes[label] = 11
			"Abilities":
				original_font_sizes[label] = 25
			"Tags", "Type":
				original_font_sizes[label] = 9
			_:
				original_font_sizes[label] = 16

	_style_layout()
	if not has_combat_stats:
		for node_name in ["StrikePlate", "GuardPlate"]:
			find_child(node_name).visible = false


# The parts of the layout that depend on the domain colour or need code to set up
func _style_layout() -> void:
	find_child("NameBar").add_theme_stylebox_override("panel",
			FateTheme.box(Color(0.27, 0.27, 0.27), Color.TRANSPARENT, 2, 0, 0.0))
	_set_pip_style(find_child("CostPip"), PIP_COLORLESS)
	# The type reads bottom to top along the left strip
	var type_label: Label = card_labels["Type"]
	type_label.pivot_offset = Vector2.ZERO
	type_label.rotation = -PI / 2.0
	type_label.position = Vector2(8, 222)
	_set_background(FateTheme.NEUTRAL_DOMAIN)
	_rebuild_pips("")


func _set_background(domain_color: Color) -> void:
	var style := FateTheme.box(domain_color.darkened(BG_DARKEN), Color.TRANSPARENT, 10, 0, 0.0)
	add_theme_stylebox_override("panel", style)


func _set_pip_style(pip: Panel, color: Color) -> void:
	pip.add_theme_stylebox_override("panel",
			FateTheme.box(color, Color(0, 0, 0, 0.8), PIP_SIZE / 2, 1, 0.0))


# One domain pip per letter of the Pips text, above the colourless pip
func _rebuild_pips(pips: String) -> void:
	var column: VBoxContainer = find_child("PipColumn")
	for pip in column.get_children():
		if pip.name != "CostPip":
			column.remove_child(pip)
			pip.queue_free()
	var index := 0
	for letter in pips:
		var pip := Panel.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		_set_pip_style(pip, FateTheme.domain_color(FateGame.DOMAIN_BY_INITIAL.get(letter, "")))
		column.add_child(pip)
		column.move_child(pip, index)
		index += 1


# Domain pips, the colourless pip and the background follow the text the card sets on the labels
func set_label_text(node: Label, value, scale: float = 1):
	if node == card_labels["Pips"]:
		_rebuild_pips(str(value))
	elif node == card_labels["Cost"]:
		find_child("CostPip").visible = str(value) not in ["", "0"]
	elif node == card_labels["Domain"]:
		_set_background(FateTheme.domain_color(str(value)))
	super.set_label_text(node, value, scale)


# The rarity gem in the bottom right corner (FateRarity; FateCardFx sets it)
func set_rarity(rarity: int) -> void:
	var gem: Panel = find_child("RarityGem", true, false)
	if gem == null:
		gem = Panel.new()
		gem.name = "RarityGem"
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gem.custom_minimum_size = Vector2(8, 8)
		gem.size = gem.custom_minimum_size
		gem.pivot_offset = gem.size / 2.0
		gem.rotation = PI / 4.0
		gem.position = Vector2(137, 227)
		$Margin.add_child(gem)
	var color := FateRarity.color_of(rarity)
	gem.add_theme_stylebox_override("panel", FateTheme.box(color, color.darkened(0.6), 1, 1, 0.0))


# --- table mode -----------------------------------------------------------------------------
#
# On the table cards are drawn at less than half size, where the full layout is unreadable.
# In table mode the front shows only what matters there, big: the name, the cost and its domain
# pips, the type, and for creatures Strike and Guard. The frame takes the card's domain colour.
# The full card is still shown in the card detail dock on hover. The regular labels are only
# hidden, so they keep their text (tests and scripts read card_labels).

const TABLE_NAME_SIZE := 30
const STRIKE_COLOR := Color(0.85, 0.3, 0.28)
const GUARD_COLOR := Color(0.32, 0.55, 0.9)

var table_mode := false
var _table_face: Control
var _table_name: Label
var _table_cost: Label
var _table_pips: HBoxContainer
var _table_type: Label
var _table_strike: Label
var _table_guard: Label
var _table_stats: Control
var _table_shown := ""


# Always applies the mode, even when it did not change: the card detail dock shows a duplicate
# of the card, which starts with whatever the original showed.
func set_table_mode(on: bool) -> void:
	table_mode = on
	if _table_face == null:
		_table_face = get_node_or_null("TableFace")
	if on and (_table_face == null or _table_name == null):
		if _table_face:
			remove_child(_table_face)
			_table_face.queue_free()
		_build_table_face()
	$Margin.visible = not on
	if _table_face:
		_table_face.visible = on
	if on:
		_table_shown = ""
		_refresh_table_face()


func _process(_delta: float) -> void:
	if table_mode:
		_refresh_table_face()


func _card() -> Card:
	var node: Node = get_parent()
	while node != null and not node is Card:
		node = node.get_parent()
	return node


# Follows the card's properties (Strike and Guard change during play)
func _refresh_table_face() -> void:
	var card := _card()
	if card == null:
		return
	var props: Dictionary = card.properties
	var shown := "%s|%s|%s|%s|%s" % [card.canonical_name, props.get("Cost", ""),
			props.get("Pips", ""), props.get("Strike", ""), props.get("Guard", "")]
	if shown == _table_shown:
		return
	_table_shown = shown
	_table_name.text = card.canonical_name
	_table_cost.text = str(props.get("Cost", 0))
	_table_type.text = str(props.get("Type", "")).to_upper()
	for pip in _table_pips.get_children():
		_table_pips.remove_child(pip)
		pip.queue_free()
	for letter in str(props.get("Pips", "")):
		var pip := Panel.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.custom_minimum_size = Vector2(18, 18)
		var color := FateTheme.domain_color(FateGame.DOMAIN_BY_INITIAL.get(letter, ""))
		pip.add_theme_stylebox_override("panel", FateTheme.box(color, Color(0, 0, 0, 0.8), 9, 2, 0.0))
		_table_pips.add_child(pip)
	_table_stats.visible = has_combat_stats
	_table_strike.text = str(props.get("Strike", ""))
	_table_guard.text = str(props.get("Guard", ""))


func _build_table_face() -> void:
	var card_size: Vector2 = CFConst.CARD_SIZE
	_table_face = Control.new()
	_table_face.name = "TableFace"
	_table_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_face.size = card_size
	add_child(_table_face)
	# The frame in the card's domain colour
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = card_size
	var color := FateTheme.card_color(_card())
	frame.add_theme_stylebox_override("panel", FateTheme.box(Color.TRANSPARENT, color, 10, 7, 0.0))
	_table_face.add_child(frame)
	# Cost badge and domain pips along the top
	var cost_badge := Panel.new()
	cost_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_badge.position = Vector2(10, 10)
	cost_badge.size = Vector2(42, 42)
	cost_badge.add_theme_stylebox_override("panel",
			FateTheme.box(FateTheme.GOLD, Color(0.25, 0.16, 0.0), 21, 3, 0.0))
	_table_face.add_child(cost_badge)
	_table_cost = _big_label(30, Color(0.15, 0.09, 0.0), 0)
	_table_cost.size = cost_badge.size
	cost_badge.add_child(_table_cost)
	_table_pips = HBoxContainer.new()
	_table_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_pips.add_theme_constant_override("separation", 3)
	_table_pips.position = Vector2(58, 22)
	_table_face.add_child(_table_pips)
	# Name in the middle
	_table_name = _big_label(TABLE_NAME_SIZE, Color.WHITE, 7)
	_table_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_table_name.max_lines_visible = 3
	_table_name.clip_text = true
	_table_name.position = Vector2(8, 58)
	_table_name.size = Vector2(card_size.x - 16, 104)
	_table_face.add_child(_table_name)
	_table_type = _big_label(17, Color(1, 1, 1, 0.55), 4)
	_table_type.position = Vector2(0, 160)
	_table_type.size = Vector2(card_size.x, 24)
	_table_face.add_child(_table_type)
	# Strike and Guard badges along the bottom
	_table_stats = Control.new()
	_table_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_face.add_child(_table_stats)
	_table_strike = _stat_badge(Vector2(8, 186), STRIKE_COLOR, "res://assets/icons/fist.png")
	_table_guard = _stat_badge(Vector2(card_size.x / 2.0 + 3, 186), GUARD_COLOR,
			"res://assets/icons/broadsword.png")


func _stat_badge(at: Vector2, color: Color, icon_path: String) -> Label:
	var badge := Panel.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = at
	badge.size = Vector2(CFConst.CARD_SIZE.x / 2.0 - 11, 46)
	badge.add_theme_stylebox_override("panel", FateTheme.box(Color(color, 0.85), color.lightened(0.4), 10, 2, 0.0))
	_table_stats.add_child(badge)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(4, 9)
	icon.size = Vector2(26, 26)
	badge.add_child(icon)
	var value := _big_label(32, Color.WHITE, 6)
	value.position = Vector2(26, 0)
	value.size = Vector2(badge.size.x - 28, badge.size.y)
	badge.add_child(value)
	return value


func _big_label(font_size: int, color: Color, outline: int) -> Label:
	var label := FateTheme.label("", font_size, color, "Bold")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", outline)
	return label
