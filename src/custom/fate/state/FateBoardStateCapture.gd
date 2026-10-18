# Captures the live Fate table into a FateBoardState (FateGame.capture_board_state calls this).
#
# Reads the nodes of the table and never changes the game: zones in order (hand left to right,
# piles TOP FIRST, grids by slot), per card the face, tilt, owner, controller, entered turn,
# tokens, attachments, forced blocker and (when FateStats can export them) damage, modifiers and
# granted keywords. Cards that other cards refer to get an id ("c1", "c2"... in the order they
# are first referred to). Cards that are not in the game data are embedded as definitions.
# The data goes through FateBoardState.from_dict, so equal tables give equal (canonical) data.
#
# Format reference: docs/FATE_BOARD_STATE.md.
class_name FateBoardStateCapture
extends RefCounted

const ForcedBlocker := preload("res://src/custom/fate/keywords/KwForcedBlocker.gd")

# The cards in the order they were captured: [{"card": Card, "entry": Dictionary}]
var _captured: Array = []
# Card -> its entry (the dictionary that is in the zone array)
var _entries := {}
# Card -> id for the cards that are referred to by another card
var _ids := {}
# The card names used (for the definitions)
var _names := {}
# game.equip while capturing (equipped relics are listed in the relic zone, not under their creature)
var game_equip = null
# game.doctrines while capturing (the achieved flag of doctrine cards)
var game_doctrines = null


# The table as a FateBoardState, or null if it is in a step that cannot be stored (then
# `game.board_state_errors` says why). `opts`: "name" and "description" of the state.
static func capture(game: FateGame, opts := {}) -> FateBoardState:
	game.board_state_errors = []
	var refusal := refusal_reason(game)
	if refusal != "":
		game.board_state_errors = [refusal]
		return null
	var capturer := FateBoardStateCapture.new()
	capturer.game_equip = game.equip
	capturer.game_doctrines = game.doctrines
	var data: Dictionary = capturer._capture(game, opts)
	return FateBoardState.from_dict(data)


# Why the table cannot be stored right now, or "" if it can
static func refusal_reason(game: FateGame) -> String:
	if not game.is_started:
		return "the game has not started yet"
	if game.is_over:
		return "the game is over"
	var phase_key := ""
	for key in FateBoardState.PHASES:
		if FateBoardState.PHASES[key] == game.phase:
			phase_key = key
	if phase_key == "":
		var phase_name: String = FateTurn.Phase.keys()[game.phase].to_lower()
		return "the %s phase cannot be stored: %s" % [phase_name,
				FateBoardState.REFUSED_PHASES.get(phase_name, "save between steps of the turn")]
	if game.reactions != null and game.reactions.open_window() != null:
		return "a reaction window is open: close it (pass priority) and save again"
	if game.phase == FateTurn.Phase.COMBAT_DECLARE and game.combat != null \
			and not game.combat.attacks.is_empty():
		return "attackers are declared: confirm or remove them, or save before attacking"
	return ""


func _capture(game: FateGame, opts: Dictionary) -> Dictionary:
	var phase_key := ""
	for key in FateBoardState.PHASES:
		if FateBoardState.PHASES[key] == game.phase:
			phase_key = key
	var choice: String = game.energy_choice
	if choice == "" and phase_key != "energy":
		# Tests can reach the main phase without the energy choice: the file format needs one
		choice = FateBoardState.default_energy_choice(phase_key)
	var out := {
		"format": FateBoardState.FORMAT,
		"version": FateBoardState.VERSION,
		"name": str(opts.get("name", "")),
		"description": str(opts.get("description", "")),
		"turn": {
			"number": game.turn_number,
			"active_player": game.active_id,
			"phase": phase_key,
			"energy_choice": choice,
		},
		"rng": {"seed": str(cfc.game_rng.seed), "state": str(cfc.game_rng.state)},
		"players": {},
	}
	var pids: Array = game.players.keys()
	pids.sort()
	for pid in pids:
		out["players"][str(pid)] = _capture_player(game, game.players[pid])
	out["world"] = _capture_grid(FateZones.grid("world", 0), "world", 0)
	_finish_cards(game)
	out["definitions"] = _definitions()
	return out


func _capture_player(game: FateGame, player: FatePlayer) -> Dictionary:
	var pid: int = player.id
	var out := {"life": player.life}
	var counters: Dictionary = game.tokens.counters_of(player.id) if game.tokens != null else {}
	if not counters.is_empty():
		out["counters"] = counters
	out["hand"] = _capture_pile(player.hand(), "hand", pid, false)
	for zone in ["deck", "discard", "removed"]:
		out[zone] = _capture_pile(FateZones.container(zone, pid), zone, pid, true)
	for zone in FateBoardState.GRID_ZONES:
		out[zone] = _capture_grid(FateZones.grid(zone, pid), zone, pid)
	return out


# A pile or the hand. `top_first`: piles have the top card as the last child, the hand lists
# its leftmost card first
func _capture_pile(container, zone: String, pid: int, top_first: bool) -> Array:
	var entries := []
	if container == null:
		return entries
	var cards: Array = container.get_all_cards().duplicate()
	if top_first:
		cards.reverse()
	for card in cards:
		entries.append(_entry_of(card, zone, pid))
	return entries


func _capture_grid(grid: BoardPlacementGrid, zone: String, pid: int) -> Array:
	var entries := []
	if grid == null:
		return entries
	for slot in grid.get_all_slots():
		var card = slot.occupying_card
		if card != null and is_instance_valid(card):
			entries.append(_entry_of(card, zone, pid))
		else:
			entries.append(null)
	return entries


# The entry of a card, with the cards attached to it. Stat state, ids and forced blockers are
# added later (_finish_cards), when all the cards are known.
func _entry_of(card: Card, zone: String, pid: int) -> Dictionary:
	var entry := {"card": card.canonical_name}
	_names[card.canonical_name] = true
	# Which side shows in a hand or a pile follows from the container (and from who sits where),
	# so only cards on the table (and attached ones) have a face of their own
	if not zone in FateBoardState.PILE_ZONES \
			and card.is_faceup != (FateBoardState.default_face(zone) == "up"):
		entry["face"] = "up" if card.is_faceup else "down"
	entry["tapped"] = card.card_rotation == 90
	if card is FateCardTemplate:
		if card.owner_id in FateBoardState.PLAYER_IDS:
			entry["owner"] = card.owner_id
		if card.controller_id in FateBoardState.PLAYER_IDS:
			entry["controller"] = card.controller_id
		entry["entered_turn"] = card.entered_turn
		# A doctrine whose goal was met keeps its reward (FateDoctrines)
		if card.properties.get("Type") == "Doctrine" and game_doctrines != null and game_doctrines.achieved(card):
			entry["achieved"] = true
	var tokens := {}
	if card.tokens != null:
		for token_name in card.tokens.get_all_tokens():
			var count: int = card.tokens.get_token_count(token_name)
			if count > 0:
				tokens[token_name] = count
	if not tokens.is_empty():
		entry["tokens"] = tokens
	_captured.append({"card": card, "entry": entry})
	_entries[card] = entry
	var attached := []
	for other in card.attachments:
		# An equipped relic stays in its slot of the relic zone (its entry says "equipped_to")
		if is_instance_valid(other) and not (game_equip != null and game_equip.is_equipped(other)):
			attached.append(_entry_of(other, "attached", pid))
	if not attached.is_empty():
		entry["attached"] = attached
	return entry


# Forced blockers and stat state (they refer to other cards), then the ids of the referenced cards
func _finish_cards(game: FateGame) -> void:
	var export_stats: bool = game.stats != null and game.stats.has_method("export_card")
	var id_of := Callable(self, "_id_of")
	for item in _captured.duplicate():
		var card: Card = item["card"]
		var entry: Dictionary = item["entry"]
		if card.has_meta(ForcedBlocker.META_KEY):
			var record = card.get_meta(ForcedBlocker.META_KEY)
			if record is Dictionary and _entries.has(record.get("target")):
				entry["forced_blocker"] = {"target": _id_of(record["target"]),
						"turn": int(record.get("turn", 0))}
		if game.equip != null and game.equip.has_method("host_of") and game.equip.host_of(card) != null \
				and _entries.has(game.equip.host_of(card)):
			entry["equipped_to"] = _id_of(game.equip.host_of(card))
		if export_stats:
			var stat_state = game.stats.export_card(card, id_of)
			if stat_state is Dictionary:
				_merge_stat_state(entry, stat_state.duplicate(true))
	for card in _ids:
		_entries[card]["id"] = _ids[card]


# Merges the damage / modifiers / grants of the stats layer into an entry. A source that is not
# on the table is left out (the entry would refer to a card that no entry has).
func _merge_stat_state(entry: Dictionary, stat_state: Dictionary) -> void:
	for key in stat_state:
		entry[key] = stat_state[key]
	for kind in ["modifiers", "grants"]:
		var list = entry.get(kind)
		if list is Array:
			for item in list:
				if item is Dictionary and item.get("source", null) == "":
					item.erase("source")


# The id of a captured card (assigned on first use). "" for something that is not on the table.
func _id_of(card) -> String:
	if card == null or not is_instance_valid(card) or not _entries.has(card):
		return ""
	if not _ids.has(card):
		_ids[card] = "c%d" % (_ids.size() + 1)
	return _ids[card]


# The definitions of the cards that are not in the game data (test cards made up at run time)
func _definitions() -> Dictionary:
	var out := {}
	for card_name in _names:
		if FateData.CARDS.has(card_name) or FateData.TOKENS.has(card_name) \
				or FateData.DOCTRINES.has(card_name):
			continue
		if cfc.card_definitions.has(card_name):
			out[card_name] = _json_safe(cfc.card_definitions[card_name])
	return out


# A deep copy with only what JSON can hold: numbers, text, bools, arrays and dictionaries
static func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			var item = _json_safe(value[key])
			if item != null or value[key] == null:
				out[str(key)] = item
		return out
	if value is Array:
		var out := []
		for item in value:
			var safe = _json_safe(item)
			if safe != null or item == null:
				out.append(safe)
		return out
	if value is StringName:
		return str(value)
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return null
