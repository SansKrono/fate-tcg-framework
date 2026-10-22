# The deck selection screen of the two-player game: each player picks one of the decks of the catalogue
# (FateDecks.presets(): an optimised deck and a starter deck per domain), then "Start game" opens the table
# with those decks. Reached from the main menu.
#
# The choice reaches the table through FateGame.domain_override and FateGame.decklist_override (what the
# tests and the AI simulation use too), set by FateDecks.select(). A table opened without this screen
# (the scene run on its own) plays the default decks, Order against Primal.
#
# The screen is laid out in FateDeckSelect.tscn (one FateDeckPanel per player, styled by
# ui/deck_select/deck_select_theme.tres); this script holds the choice.
# No class_name (see FateAIEval.gd).
extends Control

const MENU_SCENE := "res://src/custom/MainMenu.tscn"
const TABLE_SCENE := "res://src/custom/fate/FateMain.tscn"
# The decks chosen when the screen opens (preset ids): the optimised decks of the original pairing
const DEFAULT_CHOICE := {1: "order_optimised", 2: "primal_optimised"}

var presets: Array = []
# Player id -> the id of the chosen preset
var choice := {}

@onready var _panels := {1: %Player1, 2: %Player2}


func _ready() -> void:
	FateGame.register_cards()
	presets = FateDecks.presets()
	for pid in _panels:
		var side: FateDeckPanel = _panels[pid]
		side.setup(presets)
		side.deck_chosen.connect(func(preset_id: String): select(pid, preset_id))
		select(pid, _default_for(pid))


# The side of the screen of a player
func panel(pid: int) -> FateDeckPanel:
	return _panels[pid]


func _default_for(pid: int) -> String:
	var wanted: String = DEFAULT_CHOICE[pid]
	for preset in presets:
		if preset.id == wanted:
			return wanted
	return presets[0].id


# Chooses the deck of a player (a preset id). Returns false for an unknown id.
func select(pid: int, preset_id: String) -> bool:
	var preset := FateDecks.preset(preset_id)
	if preset.is_empty():
		return false
	choice[pid] = preset_id
	_panels[pid].show_deck(preset)
	return true


func swap_decks() -> void:
	var first: String = choice[1]
	select(1, choice[2])
	select(2, first)


# Applies the choice and opens the table
func start_game() -> void:
	for pid in choice:
		FateDecks.select(pid, choice[pid])
	get_tree().change_scene_to_file(TABLE_SCENE)


func _on_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
