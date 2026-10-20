extends FateKeyword
# Occupy (docs/FATE_RULES_SPEC.md, Section 4): as the cost of an activated ability the creature is tilted
# and moved to the occupied zone behind the creature zone. An occupied creature cannot attack and
# cannot return to strike until maintenance (FateTurn._maintenance moves it back, untapped), but it
# can intercept attacks with its Guard and can be targeted. Those combat rules live in FateCombat;
# this script only provides the ACTION (the hover button) and helpers other cards can call.
#
# Universal on purpose: the cards list "Occupy" in their `_keywords` display list, not in
# `_innate_keywords`, so the registry would never call this keyword's hooks for them. A universal
# keyword is asked about every card, so actions() leaves at once for cards without the ability.
#
# The other keywords' `can_occupy` hooks (Productive's summoning rule, a test veto, ...) are asked
# through `game.keywords.can_occupy(card)`. This script keeps the default `can_occupy` (true), so
# asking the registry from here cannot recurse into itself.

const NAME := "Occupy"
const ACTION_ID := "occupy"
# "Tap" as the cost of an ability (capitalised: the spell text "tap abilities" is lower case)
static var TAP_PATTERN := RegEx.create_from_string("\\bTap\\b")


func _init() -> void:
	keyword_name = NAME
	universal = true


# --- helpers other cards can use -----------------------------------------------------------------

# Does this card have an Occupy ability? Its display list names it, it has the keyword (innate
# or granted, for example by an equipment that "gains Occupy"), or its ability says "Tap" (the older name
# of Occupy, design doc Section 12 item 5: Acquisition Fabricator, Battle Smith, Factory Crafter, Devote
# Paladin; those cards list "Consume" in their display list, not "Occupy")
func has_ability(card: Card) -> bool:
	if not is_instance_valid(card):
		return false
	var listed = card.properties.get("_keywords", [])
	return (listed is Array and NAME in listed) or game.keywords.has(card, NAME) or has_tap_ability(card)


# Does the ability text of this creature use "Tap" as its cost? ("Tap, consume a scrap: ...") Also what
# Invigorated Workforce ("creatures with tap abilities can tap as soon as they enter") asks.
func has_tap_ability(card: Card) -> bool:
	if not is_instance_valid(card) or card.properties.get("Type") != "Creature":
		return false
	return TAP_PATTERN.search(str(card.properties.get("Abilities", ""))) != null


# Why this creature cannot occupy right now: "" if it can. Checks the core rules, not whether the
# card has an Occupy ability (see has_ability()). `ignore_timing` skips the phase and controller
# checks, for effects that occupy a creature outside its controller's main phase.
func occupy_problem(card: Card, ignore_timing := false) -> String:
	if game.is_over or not game.is_started:
		return "The game is not going on"
	if not is_instance_valid(card) or not card is FateCardTemplate \
			or card.properties.get("Type") != "Creature":
		return "Not a creature"
	var zone := FateZones.zone_of(card)
	if zone == "occupied":
		return "It is already occupied"
	if zone != "creatures":
		return "Only a creature in the creature zone can occupy"
	if not ignore_timing:
		if card.controller_id != game.active_id:
			return "It is not your creature"
		if game.phase != FateGame.Phase.MAIN:
			return "You can only occupy in your main phase"
	if _occupied_grid(card).find_available_slot() == null:
		return "The occupied zone is full"
	if not game.keywords.can_occupy(card):
		return "It cannot occupy now"
	return ""


func can_occupy_now(card: Card, ignore_timing := false) -> bool:
	return occupy_problem(card, ignore_timing) == ""


# Tilts the creature and moves it to its controller's occupied zone. Returns false (and changes
# nothing) if the rules do not allow it. The caller pays whatever else the ability costs.
func occupy(card: Card, ignore_timing := false) -> bool:
	if occupy_problem(card, ignore_timing) != "":
		return false
	var slot := _occupied_grid(card).find_available_slot()
	# Rotate first: a board-to-board move keeps the rotation it finds. "Scripted" moves are never
	# refused by the play rules (FateCardTemplate.common_pre_move_scripts)
	card.set_card_rotation(90)
	card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	return FateZones.zone_of(card) == "occupied"


# The reverse, for effects that make an occupied creature ready early: back to the creature zone,
# upright (strike position). Maintenance does the same by itself for every occupied card.
# Returns false if the card is not occupied or the creature zone is full.
func unoccupy(card: Card) -> bool:
	if not is_instance_valid(card) or FateZones.zone_of(card) != "occupied":
		return false
	var slot := game.player(card.controller_id).grid("creatures").find_available_slot()
	if slot == null:
		return false
	card.set_card_rotation(0)
	card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	return FateZones.zone_of(card) == "creatures"


func _occupied_grid(card: Card) -> BoardPlacementGrid:
	return game.player(card.controller_id).grid("occupied")


# --- the hover button ----------------------------------------------------------------------------

# Offered only when it is legal now (the buttons are rebuilt whenever they appear), and only to a creature whose
# Occupy ability is not a card script of its own: Goblin Ledgerkeeper's "Occupy: create a scrap token" is the button
# "Scrap", and a second plain "Occupy" next to it would tilt the creature and do nothing
func actions(card: Card) -> Array:
	if not has_ability(card) or not can_occupy_now(card) or script_occupies(card):
		return []
	return [{
		"id": ACTION_ID,
		"label": "Occupy",
		"tooltip": "Tilt this creature and move it to the occupied zone",
		"enabled": true,
		"run": _run_occupy,
	}]


# card name -> does its script offer an action that costs Occupy? (the answer depends on the card, not on the game)
static var _scripted := {}


# Does the script of this card offer an ability that costs Occupy (or Tap)? Then that ability is the card's Occupy
# button, and the plain one stays away. A creature that was only granted the keyword (an equipment) has no script
# ability and keeps the plain button.
func script_occupies(card: Card) -> bool:
	var card_name: String = card.canonical_name
	if _scripted.has(card_name):
		return _scripted[card_name]
	var found := false
	var effect = game.card_effects.effect_of(card_name) if game.card_effects != null else null
	if effect != null:
		for action in effect.actions(card):
			if action is Dictionary and action.get("costs", []).any(func(c): return c.get("id") == "occupy"):
				found = true
	_scripted[card_name] = found
	return found


func _run_occupy(card: Card) -> bool:
	return occupy(card)
