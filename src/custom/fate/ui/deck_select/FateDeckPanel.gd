# One player's side of the deck selection screen (FateDeckPanel.tscn): a tile per deck of the catalogue,
# and the chosen deck shown as a deck box (the card back in the deck's domain colour, its card types) and a
# parchment page (name, description, mana curve, card list).
class_name FateDeckPanel
extends PanelContainer

signal deck_chosen(preset_id: String)

const TILE_SCENE := preload("res://src/custom/fate/ui/deck_select/FateDeckTile.tscn")
const TYPE_LABELS := {"Creature": ["%CreatureCount", "creature"], "Relic": ["%RelicCount", "relic"],
		"Spell": ["%SpellCount", "spell"]}

@export var player_name := "Player 1":
	set(value):
		player_name = value
		if is_node_ready():
			%PlayerName.text = value

var _tiles := {}
var _group := ButtonGroup.new()


func _ready() -> void:
	%PlayerName.text = player_name


# One tile per deck of the catalogue (FateDecks.presets())
func setup(presets: Array) -> void:
	for tile in %Tiles.get_children():
		%Tiles.remove_child(tile)
		tile.queue_free()
	_tiles.clear()
	for preset in presets:
		var tile: FateDeckTile = TILE_SCENE.instantiate()
		%Tiles.add_child(tile)
		tile.setup(preset, _group)
		tile.pressed.connect(func(): deck_chosen.emit(preset.id))
		_tiles[preset.id] = tile


func tile(preset_id: String) -> FateDeckTile:
	return _tiles.get(preset_id)


func show_deck(preset: Dictionary) -> void:
	# set_pressed_no_signal() does not release the other buttons of the group
	for id in _tiles:
		_tiles[id].set_pressed_no_signal(id == preset.id)
	var color := FateTheme.domain_color(preset.domain)
	(%DeckArt.material as ShaderMaterial).set_shader_parameter("tint", color)
	%DeckName.text = preset.name
	%DeckTier.text = "%s  ·  %s deck" % [preset.domain, preset.tier]
	%Blurb.text = preset.blurb
	%ManaCurve.set_curve(FateDecks.mana_curve(preset.list), color.darkened(0.45))
	var total := 0
	for card_name in preset.list:
		total += preset.list[card_name]
	%CardCount.text = "%d cards" % total
	var types := FateDecks.type_counts(preset.list)
	for type in TYPE_LABELS:
		var count: int = types.get(type, 0)
		var label: Label = get_node(TYPE_LABELS[type][0])
		label.text = "%d %s%s" % [count, TYPE_LABELS[type][1], "" if count == 1 else "s"]
	%CardList.text = _card_list(preset.list)


# "3x Card Name  (2)", cheapest first
func _card_list(list: Dictionary) -> String:
	var names: Array = list.keys()
	names.sort_custom(func(a, b): return [FateDecks.mana_value(a), a] < [FateDecks.mana_value(b), b])
	return "\n".join(names.map(func(n): return "%dx  %s  (%d)" % [list[n], n, FateDecks.mana_value(n)]))


# Everything the page says, as text (tests read it)
func summary_text() -> String:
	return "\n".join([%DeckName.text, %DeckTier.text, %Blurb.text, %ManaCurve.get_node("Title").text,
			%CardList.text])
