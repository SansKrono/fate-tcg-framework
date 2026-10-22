# Front of a Fate card.
#
# The look lives in FateCardFront.tscn, laid out at FateLayout.CARD_SIZE (195x284), the size of the
# frames in assets/fate/cards (their opaque part, cropped by an atlas): the frame, the art window,
# the title banner, the type banner, the parchment with the rules text, and the stat badges
# (FateStatBadge) for Strike (bottom left) and Guard (bottom right). The cost pips flow down from the
# top left corner. This script only binds the card's properties to those nodes:
# - the framework sets each property's text on its label (card_labels); the labels of the badges and
#   the hidden Domain / PipText labels keep the plain values, which tests and scripts read
# - the domain picks the frame (one per domain) and recolours the art icon (fate_hue_tint.gdshader)
# - the Pips text becomes one FateCostPip per letter, the domain pips first; the generic cost is the
#   last pip
# - the rules text shrinks until it fits the parchment
# - Strike and Guard are compared with the printed values: a buffed or damaged stat changes colour
#
# On the table cards are drawn at about a third of their size, where the full layout is unreadable:
# the table face (set_table_mode) hides the details and shows the name, the cost and the stats big.
extends CardFront

const PIP_SCENE := preload("res://src/custom/fate/card/FateCostPip.tscn")
const FRAME_PATH := "res://assets/fate/cards/%s Card Frame.png"
# The opaque part of the frames: the art has a transparent margin around the card
const FRAME_REGION := Rect2(145, 145, 1360, 1960)
# A card of no domain (debug cards) gets the Order frame, greyed
const NEUTRAL_FRAME := "Order"
const NEUTRAL_MODULATE := Color(0.6, 0.62, 0.7)
# On the table the pips are drawn bigger, to read at the zone's scale
const TABLE_PIPS_SCALE := 1.5
const ART_DIR := "res://assets/fantasy-tcg-cards-pixel-art/PNG/"
# Placeholder art per card type until cards have their own ("_art" property, a texture path): a
# backdrop and the type's emblem, in the domain's colour
const TYPE_ART := {
	"Creature": ["Illustrations/Illustration2_background.png", "Cards_color1/Objects/sword_no_shadow.png"],
	"Relic": ["Illustrations/Illustration1_background.png", "Cards_color1/Objects/crystal_no_shadow.png"],
	"Spell": ["Illustrations/Illustration1_background.png", "Cards_color1/Objects/magic_no_shadow.png"],
	"Doctrine": ["Illustrations/Illustration2_background.png", "Cards_color1/Objects/star2_no_shadow.png"],
}
const NAME_FONT_SIZES := Vector2i(8, 12)
const RULES_FONT_SIZES := Vector2i(6, 10)
const TABLE_NAME_FONT_SIZES := Vector2i(16, 26)

# Set on the per-type front scenes (CreatureFront, RelicFront etc.)
@export var has_combat_stats := true

var table_mode := false

@onready var _frame: TextureRect = %Frame
@onready var _art_background: TextureRect = %ArtBackground
@onready var _art_icon: TextureRect = %ArtIcon
@onready var _rarity_gem: TextureRect = %RarityGem
@onready var _details: Control = %Details
@onready var _table_face: Control = %TableFace
@onready var _name: Label = %Name
@onready var _type: Label = %Type
@onready var _separator: Label = %Separator
@onready var _tags: Label = %Tags
@onready var _abilities: Label = %Abilities
@onready var _pips: VBoxContainer = %Pips
@onready var _cost: FateCostPip = %CostPip
@onready var _strike: FateStatBadge = %StrikeBadge
@onready var _guard: FateStatBadge = %GuardBadge
@onready var _table_name: Label = %TableName
@onready var _table_type: Label = %TableType
@onready var _table_strike: FateStatBadge = %TableStrike
@onready var _table_guard: FateStatBadge = %TableGuard


func _ready() -> void:
	card_labels["Name"] = _name
	card_labels["Type"] = _type
	card_labels["Tags"] = _tags
	card_labels["Domain"] = %Domain
	card_labels["Abilities"] = _abilities
	card_labels["Cost"] = _cost.value_label()
	card_labels["Pips"] = %PipText
	card_labels["Strike"] = _strike.value_label()
	card_labels["Guard"] = _guard.value_label()
	# The fitted font sizes are per card
	_name.label_settings = _name.label_settings.duplicate()
	_table_name.label_settings = _table_name.label_settings.duplicate()
	for badge in [_strike, _guard, _table_strike, _table_guard]:
		badge.visible = has_combat_stats
	_place_table_type()
	_set_domain("")
	_set_pips("")


# The framework's text fitting (fonts measured over several frames, cached on disk) is not used:
# the scene sets the fonts, and set_label_text fits the few texts that can overflow at once.
func set_label_text(node: Label, value, _scale: float = 1) -> void:
	var text := str(_check_for_replacements(node, value))
	node.text = text
	match node:
		_name:
			_table_name.text = text
			_fit_label_settings(_name, NAME_FONT_SIZES)
			_fit_label_settings(_table_name, TABLE_NAME_FONT_SIZES)
		_type:
			_table_type.text = text
			_set_art(text)
		_tags:
			_separator.visible = text != ""
			_tags.visible = text != ""
		_abilities:
			_fit_font(_abilities, RULES_FONT_SIZES)
		_:
			if node == card_labels["Domain"]:
				_set_domain(text)
			elif node == card_labels["Pips"]:
				_set_pips(text)
			elif node == card_labels["Cost"]:
				_set_cost(text)
			elif node == card_labels["Strike"]:
				_set_stat(_strike, _table_strike, "Strike", text)
			elif node == card_labels["Guard"]:
				_set_stat(_guard, _table_guard, "Guard", text)


func set_rich_label_text(node: RichTextLabel, value: String, _is_resize := false, _scale: float = 1) -> void:
	node.text = _check_for_replacements(node, value)


# The card is scaled as a whole (FateCardTemplate.resize_recursively): the fonts need no resizing
func scale_to(_scale_multiplier: float) -> void:
	pass


# The rarity gem in the frame's centre jewel (FateRarity; FateCardFx sets it)
func set_rarity(rarity: int) -> void:
	(_rarity_gem.material as ShaderMaterial).set_shader_parameter("tint", FateRarity.color_of(rarity))


# Always applies the mode, even when it did not change: the card detail dock shows a duplicate
# of the card, which starts with whatever the original showed.
func set_table_mode(on: bool) -> void:
	table_mode = on
	_pips.scale = Vector2.ONE * (TABLE_PIPS_SCALE if on else 1.0)
	_details.visible = not on
	_table_face.visible = on


# --- binding ---------------------------------------------------------------------------------

func _set_domain(domain: String) -> void:
	_frame.texture = _frame_texture(domain if domain in FateTheme.DOMAIN_COLORS else NEUTRAL_FRAME)
	_frame.modulate = Color.WHITE if domain in FateTheme.DOMAIN_COLORS else NEUTRAL_MODULATE
	var color := FateTheme.domain_color(domain)
	(_art_icon.material as ShaderMaterial).set_shader_parameter("tint", color.lightened(0.15))


# The frame of a domain, cropped to the card. Shared by all cards
static var _frames := {}

static func _frame_texture(domain: String) -> AtlasTexture:
	if not _frames.has(domain):
		var frame := AtlasTexture.new()
		frame.atlas = load(FRAME_PATH % domain)
		frame.region = FRAME_REGION
		_frames[domain] = frame
	return _frames[domain]


# One pip per letter, showing the emblem of the domain the letter stands for, then the generic cost
func _set_pips(pips: String) -> void:
	for pip in _pips.get_children():
		if pip != _cost:
			_pips.remove_child(pip)
			pip.queue_free()
	for letter in pips:
		var pip: FateCostPip = PIP_SCENE.instantiate()
		pip.domain = FateGame.DOMAIN_BY_INITIAL.get(letter, "")
		_pips.add_child(pip)
		_pips.move_child(pip, _cost.get_index())
	# Whether the colourless cost shows depends on the pips
	_set_cost(_cost.text)


# A card that costs only pips shows no colourless cost
func _set_cost(text: String) -> void:
	_cost.text = text
	_cost.visible = not (text in ["", "0"] and card_labels["Pips"].text != "")


func _set_stat(badge: FateStatBadge, table_badge: FateStatBadge, stat: String, text: String) -> void:
	var printed := _printed(stat)
	for b in [badge, table_badge]:
		b.base_text = printed
		b.text = text


# A stat as printed on the card (its definition), before damage and modifiers
func _printed(stat: String) -> String:
	var card := _card()
	if card == null or not cfc.card_definitions.has(card.canonical_name):
		return ""
	var printed = cfc.card_definitions[card.canonical_name].get(stat)
	return "" if printed == null else str(printed)


func _set_art(card_type: String) -> void:
	var card := _card()
	var art_path: String = card.properties.get("_art", "") if card else ""
	if art_path != "" and ResourceLoader.exists(art_path):
		_art_background.texture = load(art_path)
		_art_background.modulate = Color.WHITE
		_art_icon.visible = false
		return
	var art: Array = TYPE_ART.get(card_type, TYPE_ART["Creature"])
	_art_background.texture = load(ART_DIR + art[0])
	_art_icon.texture = load(ART_DIR + art[1])
	_art_icon.visible = true


# Creatures show their stats big on the parchment of the table face, so their type stays in the type
# banner; the other cards have the parchment to themselves and show their type there, big
func _place_table_type() -> void:
	if has_combat_stats:
		return
	_table_type.position = Vector2(20, 195)
	_table_type.size = Vector2(155, 60)
	var settings: LabelSettings = _table_type.label_settings.duplicate()
	settings.font_size = 20
	_table_type.label_settings = settings


# --- text fitting ------------------------------------------------------------------------------

# The largest font size (within `sizes`, min and max) at which the label's text fits its box
func _fit_font(label: Label, sizes: Vector2i) -> void:
	var font: Font = label.get_theme_font("font")
	label.add_theme_font_size_override("font_size", _fitting_size(font, label, sizes))


func _fit_label_settings(label: Label, sizes: Vector2i) -> void:
	label.label_settings.font_size = _fitting_size(label.label_settings.font, label, sizes)


func _fitting_size(font: Font, label: Label, sizes: Vector2i) -> int:
	var box := label.size if label.size != Vector2.ZERO else label.custom_minimum_size
	var wraps := label.autowrap_mode != TextServer.AUTOWRAP_OFF
	for font_size in range(sizes.y, sizes.x - 1, -1):
		var needed: Vector2
		if wraps:
			# The label breaks lines a little earlier than the font measures, and adds line spacing
			var lines := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER,
					box.x - 6.0, font_size, label.max_lines_visible)
			var line_count := roundi(lines.y / font.get_height(font_size))
			needed = Vector2(lines.x, lines.y + line_count * 3.0)
		else:
			needed = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		if needed.x <= box.x and needed.y <= box.y:
			return font_size
	return sizes.x


func _card() -> Card:
	var node: Node = get_parent()
	while node != null and not node is Card:
		node = node.get_parent()
	return node
