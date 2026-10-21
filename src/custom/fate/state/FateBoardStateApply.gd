# Rebuilds the Fate table from a FateBoardState (FateGame.load_board_state calls this).
#
# The table is REPLACED: everything on it is deleted, then the cards are created where the state says
# and the game state is set directly. No rules run while loading: nothing is drawn, paid or untapped,
# no "played" effects fire, the automatic steps of the turn are not run. The table is exactly the
# state.
#
# Order of the work (it matters, see the comments):
#   1 validate (the table is untouched if the state is invalid)
#   2 remember the current table to go back to it if something fails
#   3 register the card definitions of the state, reset the keyword test hooks
#   4 reset the table, put the seats in place
#   5 create the cards: piles, hand, grids, world; zone look, owner, entered turn, tokens
#   6 attach the cards beneath their creatures (Embody), forced blockers
#   7 turn, phase, life, combat step
#   8 stats (damage, modifiers, grants), then one refresh
#   9 rng, UI refresh, signals
#  10 verify: capture again and compare with the state; on a difference go back to the old table
#
# Format reference: docs/FATE_BOARD_STATE.md.
class_name FateBoardStateApply
extends RefCounted

const Embody := preload("res://src/custom/fate/keywords/KwEmbody.gd")
const ForcedBlocker := preload("res://src/custom/fate/keywords/KwForcedBlocker.gd")
# What verify() does not compare: the labels, the rng (restored separately), the definitions (they
# only matter for cards in use); and the ids, which are compared by what they refer to
const VERIFY_IGNORED_TOP := ["name", "description", "rng", "definitions"]

var game: FateGame
var state: FateBoardState
var opts: Dictionary
var errors: Array[String] = []
var warnings: Array[String] = []
# The owner a world card gets when the state does not say (the active player)
var _world_owner := 1
# id in the state -> the card it names
var _by_id := {}
# [{"card": Card, "entry": Dictionary, "path": String}] of every card created, in file order
var _created: Array = []

# Only one load at a time
static var _busy := false


# Loads `state` into the table of `game`. A coroutine: await it. Returns
# {ok: bool, errors: Array[String], warnings: Array[String]}. When ok is false the table is the one
# it was before (or, if that table could not be stored, an empty one: see `warnings`).
# opts: "verify" (default: true while testing; capture the result and compare), "rollback" (default
# true), "reset_hooks" (default true: forget the test choosers of the keywords). "_test_fail" makes
# the load fail at the end, for testing the way back.
static func apply(game_node: FateGame, board_state: FateBoardState, options := {}) -> Dictionary:
	if _busy:
		return {"ok": false, "errors": ["Another board state is being loaded"], "warnings": []}
	_busy = true
	var run := FateBoardStateApply.new()
	run.game = game_node
	run.state = board_state
	run.opts = options
	var result: Dictionary = await run._run()
	_busy = false
	return result


func _run() -> Dictionary:
	errors.assign(state.validate())
	warnings.assign(state.warnings)
	if not errors.is_empty():
		return _result()
	var snapshot: FateBoardState = null
	if opts.get("rollback", true) and game.is_started:
		snapshot = game.capture_board_state()
		if snapshot == null:
			warnings.append("The current table cannot be stored (%s): it cannot be restored if loading fails" % \
					"; ".join(game.board_state_errors))
	_register_definitions()
	if opts.get("reset_hooks", true):
		_reset_keyword_hooks()
	await game.reset_table()
	var data: Dictionary = state.data
	var active: int = data["turn"]["active_player"]
	_world_owner = active
	_seat(active)
	await _create_cards(data)
	if errors.is_empty():
		_attach_cards()
		_equip_cards()
		_set_special_state()
		_set_game_state(data)
		_import_stats()
		_restore_rng(data)
		_refresh_ui(active)
	if errors.is_empty() and opts.get("_test_fail", false):
		errors.append("Test failure after the table was built (opts._test_fail)")
	if errors.is_empty() and opts.get("verify", cfc.is_testing):
		errors.append_array(_verify(data))
	if not errors.is_empty():
		await _roll_back(snapshot)
		return _result()
	game.board_state_loaded.emit(state.state_name())
	return _result()


func _result() -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


# --- before ------------------------------------------------------------------------------------------

# The test cards of the state become real definitions (the keys are card names). A definition in a
# file only has to say what it needs (see docs/FATE_BOARD_STATE.md), so the properties the card faces,
# the hover panels and the rules read are filled in with empty values (a card without Tags crashed the
# hover panel: OVUtils.populate_info_panels iterates them).
func _register_definitions() -> void:
	var defs: Dictionary = state.data["definitions"]
	for card_name in defs:
		cfc.card_definitions[card_name] = complete_definition(defs[card_name])


# A card definition with every property the game reads, the missing ones empty
static func complete_definition(definition: Dictionary) -> Dictionary:
	var out: Dictionary = definition.duplicate(true)
	var defaults := {
		"Tags": [], "Abilities": "", "Cost": 0, "Pips": "", "_domains": [],
		"_innate_keywords": {}, "_unique": false, "_max_allowed": 3,
	}
	for key in defaults:
		if not out.has(key):
			out[key] = defaults[key]
	if not out.has("Domain"):
		out["Domain"] = out["_domains"][0] if not out["_domains"].is_empty() else ""
	if out.get("Type") == "Creature":
		for stat in ["Strike", "Guard"]:
			if not out.has(stat):
				out[stat] = 0
	return out


# The keywords can be given a "chooser" by tests (static, so it outlives the game): a loaded board
# starts without any
func _reset_keyword_hooks() -> void:
	Embody.chooser = Callable()
	ForcedBlocker.chooser = Callable()
	var savage := load("res://src/custom/fate/keywords/KwSavage.gd")
	savage.target_chooser = Callable()


func _seat(active: int) -> void:
	var board = cfc.NMAP.get("board")
	if board != null and board.has_method("apply_seats"):
		board.apply_seats(active)


# --- creating the cards -----------------------------------------------------------------------------------

func _create_cards(data: Dictionary) -> void:
	for pid in FateBoardState.PLAYER_IDS:
		var player_data: Dictionary = data["players"].get(str(pid), {})
		await _fill_pile(pid, "deck", _deck_entries(pid, player_data.get("deck", [])), true)
		for zone in ["discard", "removed"]:
			await _fill_pile(pid, zone, player_data.get(zone, []), true)
		await _fill_pile(pid, "hand", player_data.get("hand", []), false)
		for zone in FateBoardState.GRID_ZONES:
			_fill_grid(pid, zone, _grid_entries(pid, zone, player_data.get(zone, [])), "players.%d.%s" % [pid, zone])
			if not errors.is_empty():
				return
	_fill_grid(0, "world", data["world"], "world")


# The cards of a deck: the list, or a built deck of the player's domains (`{"build": true, "size": N}`)
func _deck_entries(pid: int, value) -> Array:
	if value is Dictionary:
		var names: Array = FateDecks.build(game.player(pid).domains, cfc.game_rng)
		var size: int = value.get("size", names.size())
		return names.slice(0, size).map(func(card_name): return {"card": card_name})
	return value


# The cards of a grid zone: the list, or for "doctrines": "auto" the player's default three
func _grid_entries(pid: int, zone: String, value) -> Array:
	if zone == "doctrines" and value is String:
		return FateDecks.doctrines_for(game.player(pid).domains).map(func(card_name): return {"card": card_name})
	return value


# Piles are listed top first and filled from the bottom; the hand is listed left to right
func _fill_pile(pid: int, zone: String, entries: Array, top_first: bool) -> void:
	var path := "players.%d.%s" % [pid, zone]
	var ordered := entries.duplicate()
	if top_first:
		ordered.reverse()
	for i in ordered.size():
		var entry: Dictionary = ordered[i]
		var card: Card = await game.place_in_container(entry["card"], pid, zone)
		var index: int = (ordered.size() - 1 - i) if top_first else i
		if card == null:
			errors.append("%s[%d]: could not create %s" % [path, index, entry["card"]])
			return
		_finish_card(card, entry, zone, pid, "%s[%d]" % [path, index])


func _fill_grid(pid: int, zone: String, entries: Array, path: String) -> void:
	for i in entries.size():
		var entry = entries[i]
		if entry == null:
			continue
		# The zone's player decides the grid; the owner of the card is set afterwards
		var card: Card = game.place_card_at(entry["card"], pid if pid != 0 else 1, zone, i)
		if card == null:
			errors.append("%s[%d]: could not place %s in slot %d (taken, or no such slot)" % \
					[path, i, entry["card"], i])
			return
		_finish_card(card, entry, zone, pid, "%s[%d]" % [path, i])
		if card is FateCardTemplate:
			card.apply_zone_look(zone, entry.get("face", ""), entry.get("tapped", null))


# What every created card gets, whatever its zone
func _finish_card(card: Card, entry: Dictionary, zone: String, pid: int, path: String) -> void:
	if card is FateCardTemplate:
		# In the shared world zone the default owner is the active player
		var owner: int = entry.get("owner", pid if pid != 0 else _world_owner)
		if owner != card.owner_id:
			card.assign_owner(owner)
		# Unless the state says otherwise the controller is the player whose zone it is
		card.controller_id = entry.get("controller", pid if pid != 0 else owner)
		# A field spell stands in its controller's field slot, whoever owns it
		if zone == "field":
			card.aim_field(pid)
			card.controller_id = pid
		card.entered_turn = entry.get("entered_turn", 0)
		if entry.get("achieved", false):
			card.set_meta("doctrine_achieved", true)
	_created.append({"card": card, "entry": entry, "path": path})
	if entry.has("id"):
		_by_id[entry["id"]] = card
	var tokens: Dictionary = entry.get("tokens", {})
	for token_name in tokens:
		if card.tokens == null or card.tokens.mod_token(token_name, tokens[token_name], true,
				false, ["Scripted"]) == CFConst.ReturnCode.FAILED:
			warnings.append("%s.tokens.%s: no such token, ignored" % [path, token_name])


# --- attachments and card meta --------------------------------------------------------------------------

# The cards "attached" to a creature are the energy that it embodied: each is created as one of the
# controller's energy cards and embodied for free (no mana is paid), which attaches it behind the
# creature the way playing the ability does.
func _attach_cards() -> void:
	for created in _created.duplicate():
		var entry: Dictionary = created["entry"]
		var host: Card = created["card"]
		for i in entry.get("attached", []).size():
			var attached: Dictionary = entry["attached"][i]
			var path: String = "%s.attached[%d]" % [created["path"], i]
			var pid: int = host.controller_id if host is FateCardTemplate else 1
			var energy: Card = game.place_card_at(attached["card"], pid, "energy")
			if energy == null:
				errors.append("%s: could not create %s" % [path, attached["card"]])
				return
			if energy is FateCardTemplate:
				energy.apply_zone_look("energy")
				# A card taken over together with its host keeps its owner
				energy.owner_id = attached.get("owner", energy.owner_id)
				energy.controller_id = attached.get("controller", pid)
			var embody = game.keywords.get_keyword("Embody")
			if embody == null or not embody.embody(host, energy, true):
				var why: String = embody.embody_problem(host, energy, true) if embody != null else "no Embody keyword"
				errors.append("%s: %s cannot embody it (%s)" % [path, host.canonical_name, why])
				return
			if attached.has("id"):
				_by_id[attached["id"]] = energy


# Relics with "equipped_to": the relic stands in its slot of the relic zone and is equipped to the creature
# with that id (game.equip, free: nothing is paid)
func _equip_cards() -> void:
	for created in _created:
		var target = created["entry"].get("equipped_to", null)
		if target == null:
			continue
		var host: Card = _by_id.get(target)
		if host == null:
			errors.append("%s.equipped_to: no card with the id \"%s\"" % [created["path"], target])
			return
		if game.equip == null or not game.equip.equip(created["card"], host):
			var why: String = game.equip.equip_problem(created["card"], host) if game.equip != null else "no equipment system"
			errors.append("%s: cannot be equipped to %s (%s)" % [created["path"], host.canonical_name, why])
			return


# Forced blockers: the creature must block `target` this turn (a card meta, see KwForcedBlocker)
func _set_special_state() -> void:
	for created in _created:
		var record = created["entry"].get("forced_blocker", null)
		if record == null:
			continue
		var target: Card = _by_id.get(record["target"])
		if target == null:
			errors.append("%s.forced_blocker.target: no card with the id \"%s\"" % [created["path"], record["target"]])
			return
		created["card"].set_meta(ForcedBlocker.META_KEY, {"target": target, "turn": record.get("turn", game.turn_number)})


# --- game state ------------------------------------------------------------------------------------------

func _set_game_state(data: Dictionary) -> void:
	var turn: Dictionary = data["turn"]
	game.turn_number = turn["number"]
	game.active_id = turn["active_player"]
	game.energy_choice = turn["energy_choice"]
	game.turn.phase = FateBoardState.PHASES[turn["phase"]]
	game.is_started = true
	game.is_over = false
	game.winner_id = 0
	for pid in FateBoardState.PLAYER_IDS:
		game.player(pid).life = data["players"].get(str(pid), {}).get("life", FatePlayer.STARTING_LIFE)
		# Scrap and ingot counters (the table reset forgot the old ones)
		var counters: Dictionary = data["players"].get(str(pid), {}).get("counters", {})
		for counter_name in FateBoardState.COUNTERS:
			game.tokens.set_counter(pid, counter_name, int(counters.get(counter_name, 0)))
	if game.phase == FateTurn.Phase.COMBAT_DECLARE:
		game.combat.begin_declaration()


func _import_stats() -> void:
	var card_of := func(id: String): return _by_id.get(id)
	for created in _created:
		var entry: Dictionary = created["entry"]
		if entry.has("damage") or entry.has("modifiers") or entry.has("grants"):
			game.stats.import_card(created["card"], entry, card_of)
	game.stats.refresh_all()


# The seed and state of the random numbers go last, so that building a deck does not change them
func _restore_rng(data: Dictionary) -> void:
	var rng = data.get("rng", null)
	if not rng is Dictionary:
		return
	if rng.has("seed"):
		cfc.game_rng.seed = _as_int(rng["seed"])
	if rng.has("state"):
		cfc.game_rng.state = _as_int(rng["state"])


static func _as_int(value) -> int:
	return value if value is int else str(value).to_int()


func _refresh_ui(active: int) -> void:
	var board = cfc.NMAP.get("board")
	cfc.flush_cache()
	for pid in FateBoardState.PLAYER_IDS:
		game.mana_changed.emit(pid)
	if board != null and board.has_method("apply_seats"):
		board.apply_seats(active)


# --- verifying ----------------------------------------------------------------------------------------------

# Captures the table and compares it with the state: the differences, or [] if they describe the
# same table. A state that asks for something the table cannot be (a slot that does not exist, a card
# the zone refused) shows up here.
func _verify(data: Dictionary) -> Array[String]:
	var captured := game.capture_board_state()
	if captured == null:
		return ["The loaded table cannot be captured to check it: %s" % "; ".join(game.board_state_errors)]
	var expected := _expected(data)
	var actual := _comparable(captured.data)
	var diffs: Array[String] = []
	_diff("", expected, actual, diffs)
	return diffs


# The state as the table should look after loading: "auto" doctrines expanded, a built deck reduced
# to its size, rng and definitions only if the state has them
func _expected(data: Dictionary) -> Dictionary:
	var copy: Dictionary = FateBoardState.normalize(data.duplicate(true))
	for pid in FateBoardState.PLAYER_IDS:
		var key := str(pid)
		if not copy["players"].has(key):
			copy["players"][key] = {"life": FatePlayer.STARTING_LIFE}
		var player_data: Dictionary = copy["players"][key]
		if player_data.get("doctrines", null) is String:
			player_data["doctrines"] = FateDecks.doctrines_for(game.player(pid).domains).map(
					func(card_name): return {"card": card_name})
		var deck = player_data.get("deck", null)
		if deck is Dictionary:
			# The cards of a built deck are random: only how many there are is checked
			player_data["deck"] = range(deck.get("size", FateDecks.DECK_SIZE)).map(func(_i): return {"card": "*"})
	return _comparable(copy)


# Ids are only names for references: a reference becomes the path of the card it names
func _comparable(source: Dictionary) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	for key in VERIFY_IGNORED_TOP:
		copy.erase(key)
	var holder := FateBoardState.new()
	holder.data = copy
	var paths := {}
	holder.each_card(func(path, entry, _zone, _pid):
		if entry.has("id"):
			paths[entry["id"]] = path)
	holder.each_card(func(_path, entry, _zone, _pid):
		entry.erase("id")
		for kind in ["modifiers", "grants"]:
			for item in entry.get(kind, []):
				if item.has("source"):
					item["source"] = paths.get(item["source"], item["source"])
		if entry.has("forced_blocker"):
			entry["forced_blocker"]["target"] = paths.get(entry["forced_blocker"]["target"],
					entry["forced_blocker"]["target"])
		if entry.has("equipped_to"):
			entry["equipped_to"] = paths.get(entry["equipped_to"], entry["equipped_to"]))
	return copy


func _diff(path: String, expected, actual, out: Array[String]) -> void:
	if expected is Dictionary and actual is Dictionary:
		for key in expected:
			if not actual.has(key):
				out.append("%s%s: the state has it, the table does not" % [_dot(path), key])
			else:
				_diff(_dot(path) + str(key), expected[key], actual[key], out)
		for key in actual:
			if not expected.has(key):
				out.append("%s%s: the table has it, the state does not" % [_dot(path), key])
	elif expected is Array and actual is Array:
		if expected.size() != actual.size():
			out.append("%s: the state has %d entries, the table %d" % [path, expected.size(), actual.size()])
			return
		for i in expected.size():
			_diff("%s[%d]" % [path, i], expected[i], actual[i], out)
	elif typeof(expected) != typeof(actual) or expected != actual:
		if not (expected is String and expected == "*"):
			out.append("%s: the state says %s, the table has %s" % [path, JSON.stringify(expected), JSON.stringify(actual)])


func _dot(path: String) -> String:
	return "" if path == "" else path + "."


# --- going back -----------------------------------------------------------------------------------------------

func _roll_back(snapshot: FateBoardState) -> void:
	if snapshot == null:
		warnings.append("The table is empty: the state could not be loaded and there was nothing to go back to")
		return
	var back := await FateBoardStateApply.new()._rerun(game, snapshot)
	if not back:
		warnings.append("Going back to the previous table failed too: the table may be incomplete")
	else:
		warnings.append("The previous table was restored")


# Loads the snapshot without verify and rollback. Returns whether it worked.
func _rerun(game_node: FateGame, board_state: FateBoardState) -> bool:
	game = game_node
	state = board_state
	opts = {"verify": false, "rollback": false, "reset_hooks": false}
	var result: Dictionary = await _run()
	return result["ok"]
