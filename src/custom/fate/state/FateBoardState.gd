# A complete Fate board position as data: the zones of both players in order, stats, damage,
# modifiers and granted keywords, tapped energy, life, turn, phase and rng. It converts to and from
# plain JSON so testers can read, edit and share positions outside the game, and FateGame can
# capture the live table into one (capture_board_state) and rebuild the table from one
# (load_board_state).
#
# Format reference for humans: docs/FATE_BOARD_STATE.md. JSON Schema for editors:
# boards/board_state.schema.json.
#
# The data is always held in its CANONICAL form (see normalize()): shorthand expanded, defaults
# removed, numbers as ints, trailing empty slots trimmed. Two states describe the same table if
# and only if their canonical data are equal, which is how round trips are tested.
#
# Nothing here touches the game: this class only parses, normalises, validates and prints.
class_name FateBoardState
extends Resource

const FORMAT := "fate-board-state"
const VERSION := 1

const PLAYER_IDS := [1, 2]
# Zones that are card piles: listed TOP FIRST in the file (internally the top card is the last child)
const PILE_ZONES := ["hand", "deck", "discard", "removed"]
# Zones that are placement grids: listed BY SLOT INDEX (null = empty slot)
const GRID_ZONES := ["creatures", "occupied", "relics", "field", "energy", "doctrines"]
const ZONE_ORDER := ["hand", "deck", "discard", "removed", "creatures", "occupied", "relics", "field",
		"energy", "doctrines"]
# How many cards a zone holds. Energy has no real limit (the grid grows), ENERGY_MAX is a sanity limit.
const ENERGY_MAX := 40
const HAND_SIZE := 10
const GRID_CAPACITY := {
	"creatures": 6, "occupied": 6, "relics": 3, "field": 1, "doctrines": 3, "energy": ENERGY_MAX,
}
const WORLD_CAPACITY := 1

# The phases a board can be saved in: between steps of the turn
const PHASES := {
	"energy": FateTurn.Phase.ENERGY,
	"main": FateTurn.Phase.MAIN,
	"combat_declare": FateTurn.Phase.COMBAT_DECLARE,
}
# Phases that exist but cannot be stored, with the reason shown to the user
const REFUSED_PHASES := {
	"maintenance": "the untap step runs by itself, save in the energy phase or later",
	"draw": "the draw step runs by itself, save in the energy phase or later",
	"combat_intercept": "blockers are being assigned: save before attackers are confirmed",
	"combat_resolve": "attacks are mid-resolution: save between steps",
	"end": "the end phase runs by itself, save in the main phase or earlier",
}
const ENERGY_CHOICES := ["", "energy", "draw", "debug"]
const STATS := ["Strike", "Guard"]
const FACES := ["up", "down"]
const CARD_KEYS := ["card", "id", "face", "tapped", "owner", "controller", "entered_turn", "damage",
		"modifiers", "grants", "tokens", "attached", "forced_blocker"]
const PLAYER_KEYS := ["life"] + ZONE_ORDER
const TOP_KEYS := ["format", "version", "name", "description", "turn", "rng", "players", "world",
		"definitions"]
const MODIFIER_KEYS := ["stat", "amount", "expiry", "source"]
const GRANT_KEYS := ["keyword", "value", "expiry", "source"]
const DEFAULT_EXPIRY := "end_of_turn"

# The canonical data (see normalize()). Always has all the top-level keys.
var data: Dictionary = {}
# Problems found while reading the JSON or the dictionary (not by validate())
var load_errors: Array[String] = []
# Warnings found by the last validate()
var warnings: Array[String] = []


func _init() -> void:
	data = normalize({})


# --- reading and writing ---------------------------------------------------------------------

# A state from a dictionary (as parsed from JSON). Never fails: problems show up in validate().
static func from_dict(raw: Variant) -> FateBoardState:
	var state := FateBoardState.new()
	if raw is Dictionary:
		state.data = normalize(raw)
	else:
		state.load_errors.append("The top level of a board state must be an object { ... }")
	return state


# A state from JSON text. Never null: when the text is not JSON, `load_errors` says why and the
# data is empty.
static func from_json(text: String) -> FateBoardState:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		var state := FateBoardState.new()
		state.load_errors.append("Not valid JSON: %s (line %d)" % [parser.get_error_message(),
				parser.get_error_line()])
		return state
	return from_dict(parser.data)


# The canonical data as a dictionary (a copy)
func to_dict() -> Dictionary:
	return data.duplicate(true)


# Human-friendly JSON: keys in reading order, a card with only a name as a plain string
func to_json(pretty := true) -> String:
	return JSON.stringify(_for_output(data), "\t" if pretty else "", false)


func is_valid() -> bool:
	return load_errors.is_empty() and validate().is_empty()


# A short description for lists and logs
func describe() -> String:
	var turn: Dictionary = data["turn"]
	return "%s (turn %d, player %d, %s)" % [str(data["name"]) if str(data["name"]) != "" else "unnamed",
			int(turn["number"]), int(turn["active_player"]), str(turn["phase"])]


# --- the data model: accessors ---------------------------------------------------------------

func state_name() -> String:
	return str(data["name"])


func set_state_name(value: String) -> void:
	data["name"] = value


# The data of a player ({} if the player has no entry)
func player(player_id: int) -> Dictionary:
	return data["players"].get(str(player_id), {})


# The entries of a zone of a player: an Array of cards (canonical dictionaries or null for an
# empty grid slot), or [] if the zone is empty. The world zone is the shared grid (player 0).
func zone(player_id: int, zone_name: String) -> Array:
	if player_id == 0 or zone_name == "world":
		return data["world"]
	var value = player(player_id).get(zone_name, [])
	return value if value is Array else []


# Calls `visitor(path: String, entry: Dictionary, zone_name: String, player_id: int)` for every
# card of the state, including attached cards, in file order.
func each_card(visitor: Callable) -> void:
	for pid in PLAYER_IDS:
		for zone_name in ZONE_ORDER:
			_visit_zone(zone(pid, zone_name), "players.%d.%s" % [pid, zone_name], zone_name, pid, visitor)
	_visit_zone(data["world"], "world", "world", 0, visitor)


func _visit_zone(entries: Array, path: String, zone_name: String, pid: int, visitor: Callable) -> void:
	for i in entries.size():
		var entry = entries[i]
		if entry is Dictionary:
			visitor.call("%s[%d]" % [path, i], entry, zone_name, pid)
			var attached = entry.get("attached", [])
			if attached is Array:
				_visit_zone(attached, "%s[%d].attached" % [path, i], "attached", pid, visitor)


# --- defaults --------------------------------------------------------------------------------

static func default_tapped(zone_name: String) -> bool:
	# Occupied creatures stay tilted (decision in the design doc, Section 5.3)
	return zone_name == "occupied"


static func default_face(zone_name: String) -> String:
	return "down" if zone_name in ["energy", "deck", "attached"] else "up"


# The energy choice a phase implies when the file does not say
static func default_energy_choice(phase_name: String) -> String:
	return "" if phase_name == "energy" else "draw"


# --- normalising -----------------------------------------------------------------------------

# Turns anything the format allows into canonical data: all top-level keys present, ints for whole
# numbers (JSON gives floats), card shorthand ("Battle Smith") expanded to {"card": ...}, fields
# equal to their default removed, empty zones removed, trailing empty grid slots trimmed.
# Values of the wrong type are kept as they are, so that validate() can report them.
static func normalize(raw: Dictionary) -> Dictionary:
	var src: Dictionary = _intify(raw)
	var out := {
		"format": src.get("format", FORMAT),
		"version": src.get("version", VERSION),
		"name": src.get("name", ""),
		"description": src.get("description", ""),
		"turn": _normalize_turn(src.get("turn", {})),
		"players": {},
		"world": _normalize_zone(src.get("world", []), "world", _world_owner(src.get("turn", {}))),
		"definitions": src.get("definitions", {}),
	}
	if src.has("rng"):
		out["rng"] = src["rng"]
	var players = src.get("players", {})
	if players is Dictionary:
		for key in players:
			var pid := int(str(key)) if str(key).is_valid_int() else 0
			out["players"][str(key)] = _normalize_player(players[key], pid)
	else:
		out["players"] = players
	for key in src:
		if not key in TOP_KEYS and not out.has(key):
			out[key] = src[key]
	return out


# The default owner (and controller) of a card in the shared world zone: the active player
static func _world_owner(turn) -> int:
	if turn is Dictionary and turn.get("active_player", 1) in PLAYER_IDS:
		return int(turn.get("active_player", 1))
	return 1


static func _normalize_turn(raw) -> Variant:
	if not raw is Dictionary:
		return raw
	var turn: Dictionary = raw.duplicate()
	if not turn.has("number"):
		turn["number"] = 1
	if not turn.has("active_player"):
		turn["active_player"] = 1
	if not turn.has("phase"):
		turn["phase"] = "main"
	if not turn.has("energy_choice"):
		turn["energy_choice"] = default_energy_choice(str(turn["phase"]))
	return turn


static func _normalize_player(raw, pid: int) -> Variant:
	if not raw is Dictionary:
		return raw
	var out := {"life": raw.get("life", FatePlayer.STARTING_LIFE)}
	for zone_name in ZONE_ORDER:
		if raw.has(zone_name):
			var zone_value = _normalize_zone(raw[zone_name], zone_name, pid)
			if not (zone_value is Array and zone_value.is_empty()):
				out[zone_name] = zone_value
	for key in raw:
		if not key in PLAYER_KEYS:
			out[key] = raw[key]
	return out


# Zones: arrays of cards, plus two special forms (deck {"build": ...}, doctrines "auto")
static func _normalize_zone(value, zone_name: String, pid: int) -> Variant:
	if not value is Array:
		return value
	var entries := []
	for entry in value:
		entries.append(_normalize_entry(entry, zone_name, pid))
	if zone_name in GRID_ZONES or zone_name == "world":
		while not entries.is_empty() and entries.back() == null:
			entries.pop_back()
	return entries


static func _normalize_entry(entry, zone_name: String, pid: int) -> Variant:
	if entry == null:
		return null
	if entry is String:
		return {"card": entry}
	if not entry is Dictionary:
		return entry
	var out: Dictionary = entry.duplicate()
	if _eq(out.get("tapped", null), default_tapped(zone_name)):
		out.erase("tapped")
	if _eq(out.get("face", null), default_face(zone_name)):
		out.erase("face")
	for key in ["owner", "controller"]:
		if pid != 0 and _eq(out.get(key, null), pid):
			out.erase(key)
	if _eq(out.get("entered_turn", null), 0):
		out.erase("entered_turn")
	if _eq(out.get("id", null), ""):
		out.erase("id")
	var damage = out.get("damage", null)
	if damage is Dictionary:
		for stat in damage.keys():
			if _eq(damage[stat], 0):
				damage.erase(stat)
		if damage.is_empty():
			out.erase("damage")
	var tokens = out.get("tokens", null)
	if tokens is Dictionary:
		for token in tokens.keys():
			if _eq(tokens[token], 0):
				tokens.erase(token)
		if tokens.is_empty():
			out.erase("tokens")
	for key in ["modifiers", "grants"]:
		var list = out.get(key, null)
		if list is Array:
			if list.is_empty():
				out.erase(key)
			else:
				for item in list:
					if item is Dictionary:
						if _eq(item.get("expiry", null), DEFAULT_EXPIRY):
							item.erase("expiry")
						if key == "grants" and _eq(item.get("value", null), 1):
							item.erase("value")
						if item.has("source") and item["source"] == null:
							item.erase("source")
	var attached = out.get("attached", null)
	if attached is Array:
		if attached.is_empty():
			out.erase("attached")
		else:
			var cards := []
			for item in attached:
				cards.append(_normalize_entry(item, "attached", pid))
			out["attached"] = cards
	return out


# == that is false instead of an error when the two values have different types (values come
# from hand-edited files)
static func _eq(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


# Whole floats become ints, recursively (Godot's JSON parser only produces floats)
static func _intify(value: Variant) -> Variant:
	if value is float:
		return int(value) if float(int(value)) == value else value
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _intify(value[key])
		return out
	if value is Array:
		var out := []
		for item in value:
			out.append(_intify(item))
		return out
	return value


# --- printing --------------------------------------------------------------------------------

# The data in reading order, with name-only cards as plain strings and the defaults that the
# loader fills in (turn flags) left out of the way
static func _for_output(canonical: Dictionary) -> Dictionary:
	var out := {}
	for key in TOP_KEYS:
		if not canonical.has(key):
			continue
		var value = canonical[key]
		if key == "players" and value is Dictionary:
			var players := {}
			for pid in value:
				players[pid] = _player_for_output(value[pid])
			value = players
		elif key == "world" and value is Array:
			if value.is_empty():
				continue
			value = _zone_for_output(value)
		elif key in ["description", "definitions"] and (_eq(value, "") or _eq(value, {})):
			continue
		out[key] = value
	for key in canonical:
		if not out.has(key):
			out[key] = canonical[key]
	return out


static func _player_for_output(player_data) -> Variant:
	if not player_data is Dictionary:
		return player_data
	var out := {}
	for key in PLAYER_KEYS:
		if player_data.has(key):
			out[key] = _zone_for_output(player_data[key]) if player_data[key] is Array else player_data[key]
	for key in player_data:
		if not out.has(key):
			out[key] = player_data[key]
	return out


static func _zone_for_output(entries: Array) -> Array:
	var out := []
	for entry in entries:
		out.append(_card_for_output(entry))
	return out


static func _card_for_output(entry) -> Variant:
	if not entry is Dictionary:
		return entry
	if entry.size() == 1 and entry.has("card"):
		return entry["card"]
	var out := {}
	for key in CARD_KEYS:
		if entry.has(key):
			out[key] = _zone_for_output(entry[key]) if key == "attached" else entry[key]
	for key in entry:
		if not out.has(key):
			out[key] = entry[key]
	return out


# --- validation ------------------------------------------------------------------------------

# Every problem with the state, as messages that start with the place in the JSON
# ("players.1.creatures[3].card: ..."), or an empty array if the state can be loaded. Never
# throws. `known_cards` is a dictionary whose keys are the card names that exist (default: the
# cards of the game plus the state's own `definitions`). Fills `warnings` with things that are
# allowed but probably unintended.
func validate(known_cards: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	warnings = []
	errors.append_array(load_errors)
	if not _eq(data["format"], FORMAT):
		errors.append("format: must be \"%s\", found %s" % [FORMAT, JSON.stringify(data["format"])])
	var version = data["version"]
	if not version is int:
		errors.append("version: must be a whole number")
	elif version > VERSION:
		errors.append("version: %d is newer than this game understands (%d)" % [version, VERSION])
	var names: Dictionary = known_cards if not known_cards.is_empty() else _known_card_names()
	_validate_definitions(errors, names)
	_validate_turn(errors)
	_validate_rng(errors)
	var ids := {}
	if not data["players"] is Dictionary:
		errors.append("players: must be an object with the keys \"1\" and \"2\"")
	else:
		for key in data["players"]:
			if not str(key) in ["1", "2"]:
				errors.append("players.%s: only players 1 and 2 exist" % key)
		for pid in PLAYER_IDS:
			if data["players"].has(str(pid)):
				_validate_player(errors, pid, data["players"][str(pid)], names, ids)
	_validate_zone(errors, "world", data["world"], "world", 0, names, ids)
	var refs := []
	each_card(func(path, entry, _zone, _pid): _collect_refs(refs, path, entry))
	for ref in refs:
		if not ids.has(ref[1]):
			errors.append("%s: refers to the card id \"%s\" which no card has" % [ref[0], ref[1]])
	return errors


static func _known_card_names() -> Dictionary:
	var names := {}
	for table in [FateData.CARDS, FateData.TOKENS, FateData.DOCTRINES]:
		for card_name in table:
			names[card_name] = true
	for card_name in cfc.card_definitions:
		names[card_name] = true
	return names


func _validate_definitions(errors: Array[String], names: Dictionary) -> void:
	var defs = data["definitions"]
	if not defs is Dictionary:
		errors.append("definitions: must be an object of card name -> card definition")
		return
	for card_name in defs:
		var path := "definitions.%s" % card_name
		if not defs[card_name] is Dictionary:
			errors.append("%s: must be a card definition object" % path)
			continue
		if not defs[card_name].has("Type"):
			errors.append("%s.Type: a card definition needs a Type (Creature, Relic, Spell...)" % path)
		names[card_name] = true


func _validate_turn(errors: Array[String]) -> void:
	var turn = data["turn"]
	if not turn is Dictionary:
		errors.append("turn: must be an object")
		return
	if not turn["number"] is int or turn["number"] < 1:
		errors.append("turn.number: must be a whole number, 1 or more")
	if not turn["active_player"] in PLAYER_IDS or not turn["active_player"] is int:
		errors.append("turn.active_player: must be 1 or 2")
	var phase := str(turn["phase"])
	if REFUSED_PHASES.has(phase):
		errors.append("turn.phase: \"%s\" cannot be stored: %s" % [phase, REFUSED_PHASES[phase]])
	elif not PHASES.has(phase):
		errors.append("turn.phase: unknown phase \"%s\", use one of %s" % [phase, ", ".join(PHASES.keys())])
	if not str(turn["energy_choice"]) in ENERGY_CHOICES:
		errors.append("turn.energy_choice: must be one of %s" % JSON.stringify(ENERGY_CHOICES))
	elif phase != "energy" and str(turn["energy_choice"]) == "":
		errors.append("turn.energy_choice: in the %s phase the choice of the energy phase is already made (\"energy\" or \"draw\")" % phase)
	elif phase == "energy" and str(turn["energy_choice"]) != "":
		warnings.append("turn.energy_choice: the energy phase has a choice already made, so it cannot be made again")


func _validate_rng(errors: Array[String]) -> void:
	if not data.has("rng"):
		return
	var rng = data["rng"]
	if not rng is Dictionary:
		errors.append("rng: must be an object { \"seed\": ..., \"state\": ... }")
		return
	for key in ["seed", "state"]:
		if rng.has(key) and not (rng[key] is int or rng[key] is String):
			errors.append("rng.%s: must be a whole number or text" % key)


func _validate_player(errors: Array[String], pid: int, player_data, names: Dictionary, ids: Dictionary) -> void:
	var path := "players.%d" % pid
	if not player_data is Dictionary:
		errors.append("%s: must be an object" % path)
		return
	if not (player_data["life"] is int):
		errors.append("%s.life: must be a whole number" % path)
	for key in player_data:
		if not key in PLAYER_KEYS:
			warnings.append("%s.%s: unknown key, ignored" % [path, key])
	for zone_name in ZONE_ORDER:
		if player_data.has(zone_name):
			_validate_zone(errors, "%s.%s" % [path, zone_name], player_data[zone_name], zone_name, pid, names, ids)


func _validate_zone(errors: Array[String], path: String, value, zone_name: String, pid: int,
		names: Dictionary, ids: Dictionary) -> void:
	if zone_name == "deck" and value is Dictionary:
		if not _eq(value.get("build", false), true):
			errors.append("%s: a deck given as an object must be { \"build\": true, \"size\": N }" % path)
		if value.has("size") and not (value["size"] is int and value["size"] >= 0):
			errors.append("%s.size: must be a whole number, 0 or more" % path)
		return
	if zone_name == "doctrines" and value is String:
		if value != "auto":
			errors.append("%s: use \"auto\" for the default doctrines or a list of cards" % path)
		return
	if not value is Array:
		errors.append("%s: must be a list of cards" % path)
		return
	var capacity: int = WORLD_CAPACITY if zone_name == "world" else GRID_CAPACITY.get(zone_name, -1)
	if capacity >= 0 and value.size() > capacity:
		errors.append("%s: holds at most %d cards, found %d slots" % [path, capacity, value.size()])
	if zone_name == "hand" and value.size() > HAND_SIZE:
		warnings.append("%s: more than the hand size (%d); extra cards are allowed for testing" % [path, HAND_SIZE])
	for i in value.size():
		var entry = value[i]
		var entry_path := "%s[%d]" % [path, i]
		if entry == null:
			if zone_name in PILE_ZONES:
				errors.append("%s: a pile has no empty slots, remove the null" % entry_path)
			continue
		_validate_card(errors, entry_path, entry, zone_name, pid, names, ids)


func _validate_card(errors: Array[String], path: String, entry, zone_name: String, pid: int,
		names: Dictionary, ids: Dictionary) -> void:
	if not entry is Dictionary:
		errors.append("%s: a card is a name or an object { \"card\": name, ... }" % path)
		return
	var card_name = entry.get("card", null)
	if not card_name is String or card_name == "":
		errors.append("%s.card: missing the card name" % path)
	elif not names.has(card_name):
		errors.append("%s.card: unknown card \"%s\"%s" % [path, card_name, _suggest(card_name, names)])
	for key in entry:
		if not key in CARD_KEYS:
			warnings.append("%s.%s: unknown key, ignored" % [path, key])
	if entry.has("id"):
		if not entry["id"] is String:
			errors.append("%s.id: must be text" % path)
		elif ids.has(entry["id"]):
			errors.append("%s.id: \"%s\" is used by more than one card" % [path, entry["id"]])
		else:
			ids[entry["id"]] = true
	if entry.has("face") and not str(entry["face"]) in FACES:
		errors.append("%s.face: must be \"up\" or \"down\"" % path)
	if entry.has("tapped") and not entry["tapped"] is bool:
		errors.append("%s.tapped: must be true or false" % path)
	for key in ["owner", "controller"]:
		if entry.has(key) and not (entry[key] is int and entry[key] in PLAYER_IDS):
			errors.append("%s.%s: must be 1 or 2" % [path, key])
	if entry.has("entered_turn") and not (entry["entered_turn"] is int and entry["entered_turn"] >= 0):
		errors.append("%s.entered_turn: must be a whole number, 0 or more" % path)
	_validate_damage(errors, path, entry)
	_validate_effects(errors, path, entry)
	var tokens = entry.get("tokens", {})
	if not tokens is Dictionary:
		errors.append("%s.tokens: must be an object of token name -> count" % path)
	else:
		for token in tokens:
			if not (tokens[token] is int and tokens[token] > 0):
				errors.append("%s.tokens.%s: must be a whole number above 0" % [path, token])
	var forced = entry.get("forced_blocker", null)
	if forced != null:
		if not forced is Dictionary or not forced.get("target", null) is String:
			errors.append("%s.forced_blocker: must be { \"target\": <card id>, \"turn\": N }" % path)
		elif not (forced.get("turn", 0) is int):
			errors.append("%s.forced_blocker.turn: must be a whole number" % path)
	var attached = entry.get("attached", [])
	if not attached is Array:
		errors.append("%s.attached: must be a list of cards" % path)
	else:
		for i in attached.size():
			if attached[i] == null:
				errors.append("%s.attached[%d]: must be a card" % [path, i])
			else:
				_validate_card(errors, "%s.attached[%d]" % [path, i], attached[i], "attached", pid, names, ids)
	if zone_name != "attached" and not zone_name in PILE_ZONES and _eq(entry.get("tapped", false), true) \
			and zone_name in ["relics", "field", "doctrines"]:
		warnings.append("%s.tapped: tilting only means something for creatures and energy" % path)


func _validate_damage(errors: Array[String], path: String, entry: Dictionary) -> void:
	var damage = entry.get("damage", {})
	if not damage is Dictionary:
		errors.append("%s.damage: must be an object like { \"Guard\": 1 }" % path)
		return
	for stat in damage:
		if not str(stat) in STATS:
			errors.append("%s.damage.%s: the stats are %s" % [path, stat, ", ".join(STATS)])
		elif not (damage[stat] is int and damage[stat] >= 0):
			errors.append("%s.damage.%s: must be a whole number, 0 or more" % [path, stat])


func _validate_effects(errors: Array[String], path: String, entry: Dictionary) -> void:
	for kind in ["modifiers", "grants"]:
		var list = entry.get(kind, [])
		if not list is Array:
			errors.append("%s.%s: must be a list" % [path, kind])
			continue
		for i in list.size():
			var item = list[i]
			var item_path := "%s.%s[%d]" % [path, kind, i]
			if not item is Dictionary:
				errors.append("%s: must be an object" % item_path)
				continue
			if kind == "modifiers":
				if not str(item.get("stat", "")) in STATS:
					errors.append("%s.stat: must be one of %s" % [item_path, ", ".join(STATS)])
				if not item.get("amount", null) is int:
					errors.append("%s.amount: must be a whole number" % item_path)
			else:
				if not item.get("keyword", null) is String or item["keyword"] == "":
					errors.append("%s.keyword: missing the keyword name" % item_path)
				if not item.get("value", 1) is int:
					errors.append("%s.value: must be a whole number" % item_path)
			var expiry = item.get("expiry", DEFAULT_EXPIRY)
			if not expiry is String or expiry == "":
				errors.append("%s.expiry: must be text (end_of_turn, owner_maintenance or permanent)" % item_path)
			var source = item.get("source", null)
			if source != null and not source is String:
				errors.append("%s.source: must be a card id or left out" % item_path)


# [path, id] of everything in a card that refers to another card
static func _collect_refs(refs: Array, path: String, entry: Dictionary) -> void:
	for kind in ["modifiers", "grants"]:
		var list = entry.get(kind, [])
		if list is Array:
			for i in list.size():
				if list[i] is Dictionary and list[i].get("source", null) is String:
					refs.append(["%s.%s[%d].source" % [path, kind, i], list[i]["source"]])
	var forced = entry.get("forced_blocker", null)
	if forced is Dictionary and forced.get("target", null) is String:
		refs.append(["%s.forced_blocker.target" % path, forced["target"]])


# " (did you mean "Battle Smith"?)" for the nearest known name, or ""
static func _suggest(card_name: String, names: Dictionary) -> String:
	var best := ""
	var best_score := 0.0
	for candidate in names:
		var score: float = str(candidate).to_lower().similarity(card_name.to_lower())
		if score > best_score:
			best_score = score
			best = str(candidate)
	return " (did you mean \"%s\"?)" % best if best_score >= 0.6 else ""
