# Tokens and counters. Assigned to `game.tokens`. No class_name (FateGame loads it by path).
# docs/FATE_TCG_DESIGN.md Section 11.1. OWNER: the "tokens and counters" session of the card-logic work.
#
# Two different things are called tokens in the game:
#   * resource counters, per player: scrap and ingot (FateTokens.COUNTERS). Created and consumed by cards
#     ("create a scrap token", "consume a scrap"). An ingot pays 1 mana of any colour (FateMana must be
#     taught to spend them, see `ingot_mana`).
#   * token CARDS on the table: creature tokens (Soldier 1/1, Goblin 1/1, Iron Automaton 3/3) and relic
#     tokens (Battle Hammer, Soul Spear). Defined in FateData.TOKENS (`_token: true`); they use the Creature /
#     Relic scenes. A token card that leaves the table ceases to exist (does not go to the discard pile).
#
# The API below is what card scripts (cards/Fx*.gd) call. The stub implements plain counters only; the
# session that owns this file implements the rest, keeping these signatures, and adds a test
# (tests/integration/test_fate_tokens.gd).
extends RefCounted

signal counter_changed(player_id: int, counter_name: String, value: int)
signal token_created(card: Card)

const COUNTERS := ["scrap", "ingot"]
# The counter that pays 1 mana (FateMana falls back to it when the untapped energy is not enough)
const MANA_COUNTER := "ingot"
# The table zones that hold token cards
const TOKEN_ZONES := ["creatures", "occupied", "relics"]

var game: FateGame
var _counters := {}
# Callable(player_id: int, kind: String, amount: int) -> int, see add_replacement()
var _replacements: Array[Callable] = []


func _init(owner_game: FateGame) -> void:
	game = owner_game


# --- counters --------------------------------------------------------------------------------

# How many of a counter a player has
func counter(player_id: int, counter_name: String) -> int:
	return int(_counters.get(player_id, {}).get(counter_name, 0))


# Gives a player `amount` of a counter ("create 2 scrap tokens"). The amount goes through the replacement
# effects first (add_replacement: doctrine I3 "create an additional one"). Returns how many were really
# added.
func add(player_id: int, counter_name: String, amount := 1) -> int:
	amount = replaced_amount(player_id, counter_name, amount)
	if amount <= 0:
		return 0
	set_counter(player_id, counter_name, counter(player_id, counter_name) + amount)
	return amount


# Takes `amount` of a counter away if the player has that many ("consume a scrap"). Returns whether it did.
func spend(player_id: int, counter_name: String, amount := 1) -> bool:
	if counter(player_id, counter_name) < amount:
		return false
	if amount > 0:
		set_counter(player_id, counter_name, counter(player_id, counter_name) - amount)
	return true


# Sets a counter to a value, no replacement effects (loading a board state, tests, debug)
func set_counter(player_id: int, counter_name: String, value: int) -> void:
	value = maxi(0, value)
	var table: Dictionary = _counters.get(player_id, {})
	if int(table.get(counter_name, 0)) == value:
		return
	table[counter_name] = value
	_counters[player_id] = table
	counter_changed.emit(player_id, counter_name, value)


# The counters of a player that are not 0, {"scrap": 2}. For board states.
func counters_of(player_id: int) -> Dictionary:
	var out := {}
	for c in COUNTERS:
		if counter(player_id, c) > 0:
			out[c] = counter(player_id, c)
	return out


# Forgets all counters (a new game, a loaded board state). The replacement effects stay: they belong to
# the rules, not to the position.
func reset() -> void:
	var old := _counters
	_counters = {}
	for pid in old:
		for c in old[pid]:
			if int(old[pid][c]) != 0:
				counter_changed.emit(pid, c, 0)


# How many ingots a player can spend as mana (FateMana)
func ingot_mana(player_id: int) -> int:
	return counter(player_id, MANA_COUNTER)


# --- replacement effects ---------------------------------------------------------------------------------

# Registers a replacement for token creation: `fn(player_id, kind, amount) -> int` is asked whenever a
# player is about to get `amount` counters (`kind` = "scrap" / "ingot") or token cards (`kind` = the token
# name, "Soldier Token") in ONE event (a call of add / create_many / copy; `create` is an event of 1). It
# returns the amount to create instead (Produce Endlessly: `amount + 1`; return `amount` to leave it).
# Several are chained in the order they were added. Remove it again with remove_replacement(same callable).
# A card on the table can do the same without registering anything: a `token_amount(host, player_id, kind,
# amount) -> int` method on its card script is asked while the card is on the table.
func add_replacement(fn: Callable) -> void:
	if fn.is_valid() and not fn in _replacements:
		_replacements.append(fn)


func remove_replacement(fn: Callable) -> void:
	_replacements.erase(fn)


func clear_replacements() -> void:
	_replacements.clear()


# What `amount` of `kind` becomes after the replacement effects (never below 0)
func replaced_amount(player_id: int, kind: String, amount: int) -> int:
	for fn in _replacements:
		amount = int(fn.call(player_id, kind, amount))
	if game.card_effects != null:
		for host in game.card_effects.table_cards():
			var effect = game.card_effects.effect_of(host.canonical_name)
			if effect != null and effect.has_method("token_amount"):
				amount = int(effect.token_amount(host, player_id, kind, amount))
	return maxi(0, amount)


# --- token cards ----------------------------------------------------------------------------------------------

# Creates a token card from FateData.TOKENS for `player_id` on the table and returns it (null if its zone is
# full, the name is not a token, or `attach_to` is not a creature in play). `options`: {"zone": String
# (default: the zone of its type), "tilted": bool (guard position), "attach_to": Card (a relic token goes on
# this creature, via game.equip.equip if that exists)}. The token is owned and controlled by the player,
# enters "played" (entered_turn = this turn, so Charge and summoning sickness work), emits token_created
# and runs the on_enter of its script. Replacement effects may create more of it: the other tokens are
# placed the same way, `create` returns the first one (create_many returns all).
func create(token_name: String, player_id: int, options := {}) -> Card:
	var made := create_many(token_name, player_id, 1, options)
	return made[0] if not made.is_empty() else null


# `count` tokens as one event (replacement effects see `count`). Returns the new cards, fewer than
# asked (or none) when the zone is full. `options` as in create(); a relic token with "attach_to" is only
# sensible for count 1 (every extra relic goes on the same creature).
func create_many(token_name: String, player_id: int, count := 1, options := {}) -> Array:
	var made := []
	if not FateData.TOKENS.has(token_name) or not game.players.has(player_id) or count <= 0:
		return made
	var attach_to = options.get("attach_to")
	if attach_to != null and not FateZones.is_creature_in_play(attach_to):
		return made
	var zone := str(options.get("zone", _zone_of_type(token_name)))
	var total := replaced_amount(player_id, token_name, count)
	for _i in range(total):
		var card := _place_token(token_name, player_id, zone, options)
		if card == null:
			break
		made.append(card)
	return made


func _zone_of_type(token_name: String) -> String:
	return "relics" if FateData.TOKENS[token_name].get("Type") == "Relic" else "creatures"


func _place_token(token_name: String, player_id: int, zone: String, options: Dictionary) -> Card:
	var card := game.place_card_at(token_name, player_id, zone)
	if card == null:
		return null
	if card is FateCardTemplate:
		card.apply_zone_look(zone, "", true if options.get("tilted", false) else null)
		card.entered_turn = game.turn_number
	var host = options.get("attach_to")
	if host != null and card.properties.get("Type") == "Relic" \
			and game.equip != null and game.equip.has_method("equip"):
		game.equip.equip(card, host)
	token_created.emit(card)
	if game.card_effects != null:
		game.card_effects.card_entered(card)
	return card


# Is this card a token (a card from FateData.TOKENS)?
func is_token(card: Card) -> bool:
	return is_instance_valid(card) and bool(card.properties.get("_token", false))


# A token card left the table (FateCardEffects.card_left calls this): it ceases to exist, it does not stay
# in the pile or hand it moved to. Deleted the way FateGame.reset_table deletes cards, without waiting for
# the slide into the pile to end.
func token_left(card: Card, _destination := "") -> void:
	if not is_instance_valid(card) or card.is_queued_for_deletion():
		return
	# Back on the table (moved inside it): it did not leave
	if card.get_parent() == cfc.NMAP.get("board"):
		return
	game.stats.clear_card(card)
	var parent := card.get_parent()
	if parent:
		parent.remove_child(card)
	card.remove_from_group("cards")
	card.queue_free()
	cfc.flush_cache()


# How many tokens a player has: token cards on the table plus all their counters (doctrine "Token Count")
func token_count(player_id: int) -> int:
	var total := 0
	for c in COUNTERS:
		total += counter(player_id, c)
	for zone in TOKEN_ZONES:
		for card in game.player(player_id).cards_in_grid(zone):
			if is_token(card):
				total += 1
	return total


# "Create N copies of target token you control" (Fabrication Line): `source` is a token card on the table
# or a counter name ("scrap"). A card is copied by creating its token again for `player_id` in the zone
# kind of its type (not attached, not tilted), a counter by adding `copies` of it. Both are one creation
# event for the replacement effects. Returns the new cards (empty for counters and when `source` is not a
# token).
func copy(source, player_id: int, copies := 1) -> Array:
	if source is String or source is StringName:
		if str(source) in COUNTERS:
			add(player_id, str(source), copies)
		return []
	if not source is Card or not is_token(source):
		return []
	return create_many(source.canonical_name, player_id, copies)
