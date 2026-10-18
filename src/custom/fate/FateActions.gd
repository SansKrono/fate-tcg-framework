# Activated actions of cards (Occupy, Embody, ...), shown as extra hover buttons on the card.
# Owned by FateGame (`game.actions`).
#
# A keyword offers actions by overriding FateKeyword.actions(card); this class gathers them from
# all keywords of a card, decides who may see them and runs them. FateManipulationButtons asks
# for `list(card)` whenever the hover buttons of a card appear, so a keyword never needs to touch
# the button code. Tests and the AI use the same `list()` and `run()`.
#
# An action is a dictionary {"id": String, "label": String, "tooltip": String, "enabled": bool,
# "run": Callable}; `run` takes the card, may be a coroutine, and returns true when it acted.
class_name FateActions
extends RefCounted

# A card action was run (after it returned)
signal action_performed(card: Card, action_id: String)

var game: FateGame


func _init(owner_game: FateGame) -> void:
	game = owner_game


# The actions the controller of a card can use on it now: only for cards standing on the table,
# only for their controller, only while the game goes on. Each has "enabled" set by its keyword.
func list(card: Card) -> Array:
	if game.is_over or not game.is_started or not card is FateCardTemplate:
		return []
	# A card in its owner's discard pile may offer actions too (Unending Echo: cast from the discard pile)
	if FateZones.zone_of(card) == "":
		if card.owner_id != game.active_id or card.get_parent() != FateZones.container("discard", card.owner_id):
			return []
	elif card.controller_id != game.active_id:
		return []
	return game.keywords.actions(card)


# Finds an action by id, or an empty dictionary
func find(card: Card, action_id: String) -> Dictionary:
	for action in list(card):
		if action.id == action_id:
			return action
	return {}


# Runs an action. Returns whether it acted. Awaitable (an action may wait for a choice).
func run(card: Card, action_id: String) -> bool:
	var action := find(card, action_id)
	if action.is_empty() or not action.get("enabled", true):
		return false
	var result = await action.run.call(card)
	var acted: bool = result == null or result == true
	if acted:
		action_performed.emit(card, action_id)
	return acted
