# The keyword registry: finds the keyword scripts, answers "which keywords does this card have"
# and dispatches the hooks of FateKeyword with the right combination rules.
# Design document: Section 13 (SYS-KEYWORD). Hook API: src/custom/fate/keywords/README.md.
#
# Owned by FateGame (`game.keywords`).
#
# Where the keywords of a card come from:
#   innate   card.properties["_innate_keywords"], a dictionary name -> value ({"Savage": 2})
#   granted  FateStats.grant_keyword(), with an expiry (Indomitable until end of turn)
# `has()`, `value()` and `all_on()` merge both. Granted values ADD to innate ones (two Savage 1
# sources are Savage 2). A name nobody registered a script for is still reported by has() and
# value(): it simply has no hooks.
#
# Combination rules of the hooks (details in the README):
#   can_*            all keywords must allow it (any `false` wins)
#   would_be_destroyed  same
#   modify_damage_taken  chained: each keyword gets the amount the previous one returned
#   stat_bonus       summed
#   death_destination  the first keyword that answers wins
#   on_* events      every keyword is called, in priority order
# Keywords run in ascending `priority`, then by name, so results do not depend on file order.
class_name FateKeywords
extends RefCounted

# The folder that is scanned for keyword scripts (Kw*.gd)
const KEYWORD_DIR := "res://src/custom/fate/keywords/"
const SCRIPT_PREFIX := "Kw"

var game: FateGame
# keyword name -> FateKeyword
var _by_name := {}
# The registered keywords that apply to every card
var _universal: Array = []


func _init(owner_game: FateGame) -> void:
	game = owner_game
	discover()
	# The stats layer (created before the registry) connects to the same signals first, so its
	# resets and expiries have happened when these run
	game.maintenance_finished.connect(_on_maintenance_finished)
	game.end_of_turn_expiry.connect(_on_end_of_turn_expiry)


# --- registration -------------------------------------------------------------------------

# Scans a folder (default KEYWORD_DIR) and registers every Kw*.gd script. Called once at startup. Works in the
# editor and in exported builds: an export lists scripts as `Name.gd.remap` or `Name.gdc`, which
# are mapped back to the `.gd` path that `load()` understands. Returns how many were registered.
func discover(folder := KEYWORD_DIR) -> int:
	var found := 0
	var dir := DirAccess.open(folder)
	if dir == null:
		return 0
	var seen := {}
	for file_name in dir.get_files():
		var script_name := script_file_name(file_name)
		if script_name == "" or seen.has(script_name):
			continue
		seen[script_name] = true
		var script = load(folder + script_name)
		if script == null or not script is GDScript or not script.can_instantiate():
			push_warning("FateKeywords: cannot load keyword script " + script_name)
			continue
		var keyword = script.new()
		if not keyword is FateKeyword:
			push_warning("FateKeywords: %s does not extend FateKeyword" % script_name)
			continue
		if register(keyword):
			found += 1
	return found


# Maps a file name from a directory listing to the `Kw*.gd` script it stands for, or "" if the
# file is not a keyword script ("KwSavage.gd.remap" and "KwSavage.gdc" -> "KwSavage.gd")
static func script_file_name(file_name: String) -> String:
	var n := file_name
	if n.ends_with(".remap"):
		n = n.trim_suffix(".remap")
	if n.ends_with(".gdc"):
		n = n.trim_suffix(".gdc") + ".gd"
	if not n.begins_with(SCRIPT_PREFIX) or not n.ends_with(".gd"):
		return ""
	return n


# Registers a keyword (also used by tests for keywords that are not in KEYWORD_DIR). A second
# keyword with the same name replaces the first. Returns false if it has no name.
func register(keyword: FateKeyword) -> bool:
	if keyword.keyword_name == "":
		push_warning("FateKeywords: a keyword script sets no keyword_name")
		return false
	if _by_name.has(keyword.keyword_name):
		unregister(keyword.keyword_name)
	keyword.game = game
	_by_name[keyword.keyword_name] = keyword
	if keyword.universal:
		_universal.append(keyword)
	return true


func unregister(keyword_name: String) -> void:
	var keyword: FateKeyword = _by_name.get(keyword_name)
	if keyword == null:
		return
	_by_name.erase(keyword_name)
	_universal.erase(keyword)


# The registered FateKeyword with this name, or null
func get_keyword(keyword_name: String) -> FateKeyword:
	return _by_name.get(keyword_name)


# Names of all registered keywords, sorted
func registered_names() -> Array:
	var names := _by_name.keys()
	names.sort()
	return names


# --- what a card has -----------------------------------------------------------------------------

# The innate keywords of a card: a dictionary name -> value (a copy)
func innate(card: Card) -> Dictionary:
	var found = card.properties.get("_innate_keywords", {})
	return found.duplicate() if found is Dictionary else {}


# Every keyword on a card, innate and granted: a dictionary name -> value (values add up)
func all_on(card: Card) -> Dictionary:
	var found := innate(card)
	for grant in game.stats.grants_of(card):
		found[grant.keyword] = int(found.get(grant.keyword, 0)) + int(grant.value)
	# Keywords that cards on the table give to this one ("your creatures have Productive")
	if game.card_effects != null and card is FateCardTemplate and card.properties.get("Type") == "Creature":
		var given: Dictionary = game.card_effects.static_keywords(card)
		for k in given:
			found[k] = int(found.get(k, 0)) + int(given[k])
	return found


func has(card: Card, keyword_name: String) -> bool:
	if not is_instance_valid(card):
		return false
	return all_on(card).has(keyword_name)


# The value of a keyword on a card (Savage 2 -> 2). 0 if the card does not have it.
func value(card: Card, keyword_name: String) -> int:
	if not is_instance_valid(card):
		return 0
	return int(all_on(card).get(keyword_name, 0))


# The keyword objects whose hooks run for this card: the ones it has plus the universal ones,
# in priority order. Names without a script are skipped.
func hooks_for(card: Card) -> Array:
	var list: Array = []
	if not is_instance_valid(card):
		return list
	var names := all_on(card)
	for keyword_name in names:
		var keyword: FateKeyword = _by_name.get(keyword_name)
		if keyword != null and not keyword.universal:
			list.append(keyword)
	list.append_array(_universal)
	# The card's own script is a keyword for this card (cards/FateCardEffect.gd)
	if game.card_effects != null:
		var script = game.card_effects.effect_of(card.canonical_name)
		if script != null:
			list.append(script)
	list.sort_custom(_before)
	return list


static func _before(a: FateKeyword, b: FateKeyword) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	return a.keyword_name < b.keyword_name


# --- eligibility: every keyword must allow it ----------------------------------------------------------

func can_attack(card: Card) -> bool:
	for keyword in hooks_for(card):
		if not keyword.can_attack(card):
			return false
	return true


func can_occupy(card: Card) -> bool:
	for keyword in hooks_for(card):
		if not keyword.can_occupy(card):
			return false
	return true


# Hooks of the blocker's keywords
func can_block(blocker: Card, attack: FateAttack) -> bool:
	for keyword in hooks_for(blocker):
		if not keyword.can_block(blocker, attack):
			return false
	return true


# Hooks of the attacker's keywords
func can_be_blocked_by(attacker: Card, blocker: Card, attack: FateAttack) -> bool:
	for keyword in hooks_for(attacker):
		if not keyword.can_be_blocked_by(attacker, blocker, attack):
			return false
	return true


# Hooks of the target's keywords
func can_be_attacked(target: Card, attacker: Card) -> bool:
	for keyword in hooks_for(target):
		if not keyword.can_be_attacked(target, attacker):
			return false
	return true


# --- combat events -----------------------------------------------------------------------------

func attack_declared(attack: FateAttack) -> void:
	for keyword in hooks_for(attack.attacker):
		keyword.on_attack_declared(attack.attacker, attack)


func blocked(attack: FateAttack, blockers: Array) -> void:
	for keyword in hooks_for(attack.attacker):
		keyword.on_blocked(attack.attacker, attack, blockers)


func blocking(blocker: Card, attack: FateAttack) -> void:
	for keyword in hooks_for(blocker):
		keyword.on_blocking(blocker, attack)


# Called once for each participant of the attack (see FateKeyword.before_combat_damage)
func before_combat_damage(attack: FateAttack) -> void:
	var participants: Array = [attack.attacker]
	participants.append_array(attack.blockers)
	if attack.target_card != null:
		participants.append(attack.target_card)
	for card in participants:
		if is_instance_valid(card):
			for keyword in hooks_for(card):
				keyword.before_combat_damage(card, attack)


# `source` is the Card that dealt the damage (keywords on it hear about it); null is ignored
func damage_dealt(source, target, amount: int, cause: String) -> void:
	if source is Card and is_instance_valid(source):
		for keyword in hooks_for(source):
			keyword.on_damage_dealt(source, target, amount, cause)


# --- damage and destruction ----------------------------------------------------------------------------

# Chained, never below 0
func modify_damage_taken(card: Card, stat: String, amount: int, cause: String, source) -> int:
	var result := amount
	for keyword in hooks_for(card):
		result = maxi(0, keyword.modify_damage_taken(card, stat, result, cause, source))
	return result


func would_be_destroyed(card: Card, cause: String, source) -> bool:
	for keyword in hooks_for(card):
		if not keyword.would_be_destroyed(card, cause, source):
			return false
	return true


func death_destination(card: Card, cause: String) -> String:
	for keyword in hooks_for(card):
		var zone: String = keyword.death_destination(card, cause)
		if zone != "":
			return zone
	return "discard"


func destroyed(card: Card, cause: String, source) -> void:
	for keyword in hooks_for(card):
		keyword.on_destroyed(card, cause, source)


# --- stats ---------------------------------------------------------------------------------------------

func stat_bonus(card: Card, stat: String) -> int:
	var total := 0
	for keyword in hooks_for(card):
		total += keyword.stat_bonus(card, stat)
	return total


# --- actions (hover buttons) -----------------------------------------------------------------------------

# The actions every keyword of the card offers, see FateKeyword.actions() and FateActions
func actions(card: Card) -> Array:
	var list: Array = []
	for keyword in hooks_for(card):
		for action in keyword.actions(card):
			if action is Dictionary and action.has("id") and action.has("run"):
				list.append(action)
	return list


# --- time ----------------------------------------------------------------------------------------------------

func _on_maintenance_finished(_player_id: int) -> void:
	for card in game.creatures_in_play(game.active_id):
		for keyword in hooks_for(card):
			keyword.on_maintenance(card)


func _on_end_of_turn_expiry(_player_id: int) -> void:
	for card in game.creatures_in_play(game.active_id):
		for keyword in hooks_for(card):
			keyword.on_turn_end(card)
