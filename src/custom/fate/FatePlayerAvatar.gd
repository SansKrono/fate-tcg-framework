# The plate of a player in the right rail: an emblem in their domain colour, their name, a big
# life total, one mana chip per domain (untapped / total energy) and their hand and deck counts.
# It is a button: in the declare step the active player clicks it to attack the player directly
# (see FateCombatUI). The plate of the player whose turn it is has a gold frame.
class_name FatePlayerAvatar
extends Button

const SIZE := Vector2(212, 88)

var player: FatePlayer
# Set by FateCombatUI; the plate reads mana and card counts from it
var game: FateGame
var is_active_player := false
var is_target := false
var life_label: Label
var counts_label: Label
# "Scrap 2   Ingot 1", only shown while the player has some (FateTokens)
var counters_label: Label
var _emblem: Panel
var _chips: HBoxContainer
var _mana_text := "-"


func _init(avatar_player: FatePlayer) -> void:
	player = avatar_player
	name = "PlayerAvatar_P%d" % player.id
	custom_minimum_size = SIZE
	size = SIZE
	focus_mode = Control.FOCUS_NONE
	tooltip_text = player.display_name
	_build()
	_restyle()
	player.life_changed.connect(func(_p): refresh())
	refresh()


func _build() -> void:
	var color := FateTheme.domain_color(player.domains[0])
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(10, 8)
	row.size = SIZE - Vector2(20, 16)
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_emblem = Panel.new()
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.custom_minimum_size = Vector2(46, 46)
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var emblem_box := FateTheme.box(Color(color, 0.18), color, 23, 2, 0.0)
	_emblem.add_theme_stylebox_override("panel", emblem_box)
	var initials := FateTheme.label("P%d" % player.id, 16, color.lightened(0.25), "Bold")
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials.size = Vector2(46, 46)
	_emblem.add_child(initials)
	row.add_child(_emblem)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	row.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var name_label := FateTheme.label(player.display_name, 13, FateTheme.TEXT, "SemiBold")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var heart := FateTheme.label("♥", 14, FateTheme.LIFE, "Bold")
	top.add_child(heart)
	life_label = FateTheme.label("", 22, Color.WHITE, "Bold")
	life_label.add_theme_color_override("font_outline_color", Color(0.3, 0.02, 0.05))
	life_label.add_theme_constant_override("outline_size", 4)
	top.add_child(life_label)
	_chips = HBoxContainer.new()
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.add_theme_constant_override("separation", 4)
	column.add_child(_chips)
	counts_label = FateTheme.label("", 11, FateTheme.MUTED, "Regular")
	column.add_child(counts_label)
	counters_label = FateTheme.label("", 11, FateTheme.GOLD, "SemiBold")
	counters_label.visible = false
	column.add_child(counters_label)


# Updates the life total, the mana chips and the counts
func refresh() -> void:
	life_label.text = str(player.life)
	if game == null:
		return
	var pool := game.mana_pool(player.id)
	var totals := {}
	for card in player.cards_in_grid("energy"):
		var d: String = game.mana.energy_domain(card)
		totals[d] = totals.get(d, 0) + 1
	for chip in _chips.get_children():
		_chips.remove_child(chip)
		chip.queue_free()
	var parts := []
	for domain in FateMana.DOMAINS:
		var untapped: int = pool.get(domain, 0)
		var total: int = totals.get(domain, 0)
		if untapped > 0:
			parts.append("%s %d" % [domain.substr(0, 3), untapped])
		if total == 0 and not domain in player.domains:
			continue
		_chips.add_child(_chip(domain, untapped, total))
	_mana_text = ", ".join(parts) if not parts.is_empty() else "-"


# Cards come and go without a signal for each move, so the counts follow every frame
func _process(_delta: float) -> void:
	var hand = player.hand()
	var deck = player.deck()
	counts_label.text = "Hand %d   Deck %d" % [
			hand.get_card_count() if hand else 0, deck.get_card_count() if deck else 0]
	var counters := counters_text()
	counters_label.text = counters
	counters_label.visible = counters != ""


func _chip(domain: String, untapped: int, total: int) -> Label:
	var color := FateTheme.domain_color(domain)
	var chip := FateTheme.label("%s %d/%d" % [domain.substr(0, 3), untapped, total], 11,
			color.lightened(0.35) if untapped > 0 else Color(color, 0.9), "Bold")
	chip.tooltip_text = "%s mana: %d untapped of %d" % [domain, untapped, total]
	chip.add_theme_stylebox_override("normal",
			FateTheme.pill_box(Color(color, 0.2 if untapped > 0 else 0.12), Color(color, 0.5)))
	return chip


# The scrap and ingot counters of the player, "Scrap 2   Ingot 1" ("" when there are none)
func counters_text() -> String:
	if game == null or game.tokens == null:
		return ""
	var parts := []
	for counter_name in game.tokens.COUNTERS:
		var amount: int = game.tokens.counter(player.id, counter_name)
		if amount > 0:
			parts.append("%s %d" % [counter_name.capitalize(), amount])
	return "   ".join(parts)


# The life total, as shown
func life_text() -> String:
	return life_label.text


# The untapped mana, "Inn 1, Pri 1" (or "-" when there is none)
func mana_text() -> String:
	return _mana_text


# Marks the plate as something the current click can target
func set_highlight(on: bool) -> void:
	is_target = on
	_restyle()


# The plate of the player whose turn it is
func set_active(on: bool) -> void:
	if on == is_active_player:
		return
	is_active_player = on
	_restyle()


func _restyle() -> void:
	var border := FateTheme.PANEL_BORDER
	var width := 1
	if is_target:
		border = FateTheme.DANGER
		width = 2
	elif is_active_player:
		border = FateTheme.GOLD
		width = 2
	var bg := Color(0.3, 0.06, 0.08, 0.92) if is_target else FateTheme.PANEL
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		var panel := FateTheme.box(bg.lightened(0.08) if style == "hover" else bg, border, 12, width, 0.0)
		panel.shadow_color = Color(FateTheme.GOLD, 0.25) if is_active_player and not is_target \
				else Color(0, 0, 0, 0.45)
		panel.shadow_size = 8
		add_theme_stylebox_override(style, panel)
