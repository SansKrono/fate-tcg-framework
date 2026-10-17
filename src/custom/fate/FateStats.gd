# The stats layer: base stats, damage, modifiers and keyword grants of creatures.
# Design document: Section 9 (SYS-MOD). Rules: docs/FATE_RULES_SPEC.md, Section 3 (damage) and
# decision D7 (damage lasts until the OWNER's next maintenance).
#
# Owned by FateGame (`game.stats`).
#
# A creature's stat (Strike or Guard) is always
#       current = max(0, base + modifiers + keyword bonuses - damage)
#   base       from the card definition (`cfc.card_definitions[name]`), never changes
#   modifiers  add_modifier(): buffs and debuffs, each with an expiry and a source
#   bonuses    FateKeyword.stat_bonus() of the keywords on the card (Embody)
#   damage     apply_damage(): what combat and effects took off the stat that was used
# The card's `properties["Strike"]` / `["Guard"]` always hold the CURRENT value and the labels on
# the card face are refreshed through the framework (`modify_property`), so what the player sees
# is what the rules use.
#
# State-based check: a creature in play whose Strike AND Guard are both 0 is destroyed at once
# (FateEffects.destroy, cause "stats"). It runs after every change, unless `begin_batch()` holds
# it back so that several changes count as simultaneous.
#
# Expiries (the `expiry` of modifiers and keyword grants):
#   EXPIRY_END_OF_TURN   gone when `end_of_turn_expiry` fires (the END phase of any turn)
#   EXPIRY_MAINTENANCE   gone at the card OWNER's next maintenance (the same moment as damage)
#   EXPIRY_PERMANENT     stays until removed (remove_modifiers_from) or the card leaves the table
# Any other string is accepted and only ends through expire(that_string).
class_name FateStats
extends RefCounted

signal stats_changed(card)

const STATS := ["Strike", "Guard"]
const EXPIRY_END_OF_TURN := "end_of_turn"
const EXPIRY_MAINTENANCE := "owner_maintenance"
const EXPIRY_PERMANENT := "permanent"
# Effects with these expiries end when the owner's maintenance resets the card
const RESET_EXPIRIES := [EXPIRY_END_OF_TURN, EXPIRY_MAINTENANCE]

var game: FateGame
# card instance id -> {"Strike": amount, "Guard": amount} of damage taken
var _damage := {}
# card instance id -> Array of modifier dictionaries {stat, amount, expiry, source}
var _mods := {}
# card instance id -> Array of grant dictionaries {keyword, value, expiry, source}
var _grants := {}
# While > 0 the both-zero check only collects cards (see begin_batch)
var _batch := 0
var _batch_cards: Array = []


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.maintenance_started.connect(_on_maintenance_started)
	game.end_of_turn_expiry.connect(_on_end_of_turn_expiry)


# --- reading ---------------------------------------------------------------------------------

# The base value of a stat, from the card definition
func base(card: Card, stat: String) -> int:
	return int(cfc.card_definitions.get(card.canonical_name, {}).get(stat, 0))


# The sum of the modifiers on a stat
func modifier_total(card: Card, stat: String) -> int:
	var total := 0
	for mod in _mods.get(card.get_instance_id(), []):
		if mod.stat == stat:
			total += mod.amount
	return total


# The damage taken on a stat
func damage_on(card: Card, stat: String) -> int:
	return int(_damage.get(card.get_instance_id(), {}).get(stat, 0))


# The effective value of a stat: base + modifiers + keyword bonuses - damage, never below 0
func current(card: Card, stat: String) -> int:
	var total := base(card, stat) + modifier_total(card, stat) - damage_on(card, stat)
	total += game.keywords.stat_bonus(card, stat)
	return maxi(0, total)


# The keywords granted to a card: Array of {keyword, value, expiry, source}
func grants_of(card: Card) -> Array:
	return _grants.get(card.get_instance_id(), [])


# --- changing --------------------------------------------------------------------------------------

# Lowers the stat that was used by `amount`, never below 0, and remembers it as damage. Returns
# how much was really taken off. Keyword prevention and the like is FateEffects.deal_damage's
# job: this is the bookkeeping.
func apply_damage(card: Card, stat: String, amount: int) -> int:
	var taken := clampi(amount, 0, current(card, stat))
	if taken > 0:
		var entry: Dictionary = _damage.get(card.get_instance_id(), {})
		entry[stat] = int(entry.get(stat, 0)) + taken
		_damage[card.get_instance_id()] = entry
		refresh(card)
	return taken


# Adds `amount` (negative to weaken) to a stat. Returns a handle for remove_modifier().
# `source` is whatever created it (a card or null), so remove_modifiers_from(source) can undo it.
func add_modifier(card: Card, stat: String, amount: int, expiry := EXPIRY_END_OF_TURN,
		source = null) -> Dictionary:
	var mod := {"stat": stat, "amount": amount, "expiry": expiry, "source": source}
	var list: Array = _mods.get(card.get_instance_id(), [])
	list.append(mod)
	_mods[card.get_instance_id()] = list
	refresh(card)
	return mod


func remove_modifier(card: Card, mod: Dictionary) -> void:
	var list: Array = _mods.get(card.get_instance_id(), [])
	if list.has(mod):
		list.erase(mod)
		refresh(card)


# Removes every modifier AND keyword grant that `source` created, on every card
# ("while this relic is in play" effects end when the source leaves)
func remove_modifiers_from(source) -> void:
	if source == null:
		return
	var touched: Array = []
	for table in [_mods, _grants]:
		for id in table.keys():
			var kept: Array = []
			for entry in table[id]:
				if is_same(entry.source, source):
					if not id in touched:
						touched.append(id)
				else:
					kept.append(entry)
			table[id] = kept
	_refresh_ids(touched)


# Gives a card a keyword (with a value) for a while. Counts for FateKeywords.has/value/all_on and
# for the keyword's hooks. Returns a handle for remove_grant().
func grant_keyword(card: Card, keyword: String, value := 1, expiry := EXPIRY_END_OF_TURN,
		source = null) -> Dictionary:
	var grant := {"keyword": keyword, "value": value, "expiry": expiry, "source": source}
	var list: Array = _grants.get(card.get_instance_id(), [])
	list.append(grant)
	_grants[card.get_instance_id()] = list
	refresh(card)
	return grant


func remove_grant(card: Card, grant: Dictionary) -> void:
	var list: Array = _grants.get(card.get_instance_id(), [])
	if list.has(grant):
		list.erase(grant)
		refresh(card)


# Ends every modifier and grant with this expiry, on one card or (default) on all of them
func expire(expiry: String, only_card: Card = null) -> void:
	var touched: Array = []
	for table in [_mods, _grants]:
		for id in table.keys():
			if only_card != null and id != only_card.get_instance_id():
				continue
			var kept: Array = []
			for entry in table[id]:
				if entry.expiry == expiry:
					if not id in touched:
						touched.append(id)
				else:
					kept.append(entry)
			table[id] = kept
	_refresh_ids(touched)


# The maintenance reset of one creature (D7): damage is gone and the effects that end with the
# owner's maintenance or the turn are gone. Permanent modifiers and grants stay.
func reset_card(card: Card) -> void:
	_damage.erase(card.get_instance_id())
	for table in [_mods, _grants]:
		var list: Array = table.get(card.get_instance_id(), [])
		table[card.get_instance_id()] = list.filter(
				func(entry): return not entry.expiry in RESET_EXPIRIES)
	refresh(card)


# Forgets everything about a card (damage, modifiers, grants) and shows its base stats. Done when
# a card leaves the table.
func clear_card(card: Card) -> void:
	var id := card.get_instance_id()
	var had := _damage.has(id) or _mods.has(id) or _grants.has(id)
	_damage.erase(id)
	_mods.erase(id)
	_grants.erase(id)
	if had or _shows_other_than_base(card):
		_show(card, false)


# Recomputes the stats of a card, updates the card face and runs the state-based check. Call it
# when something a stat depends on changed (a keyword's own state, see FateKeyword.stat_bonus).
func refresh(card: Card) -> void:
	if not is_instance_valid(card):
		return
	_show(card, true)
	stats_changed.emit(card)


# --- simultaneous changes -------------------------------------------------------------------------------

# Until end_batch(), the both-zero check only collects cards. Used by combat so that all damage of
# one attack counts as dealt at the same moment. Batches nest.
func begin_batch() -> void:
	_batch += 1


func end_batch() -> void:
	_batch = maxi(0, _batch - 1)
	if _batch > 0:
		return
	var cards := _batch_cards
	_batch_cards = []
	for card in cards:
		_check_zero(card)


# --- internals ---------------------------------------------------------------------------------------------

func _refresh_ids(ids: Array) -> void:
	for id in ids:
		var card = instance_from_id(id)
		if card is Card:
			refresh(card)


# Writes the current stats into the card's properties, through the framework so the labels follow
func _show(card: Card, check: bool) -> void:
	for stat in STATS:
		if not card.properties.has(stat):
			continue
		var value := current(card, stat) if check else base(card, stat)
		if card.properties[stat] != value:
			card.modify_property(stat, value, false, ["Scripted"])
	if check:
		if _batch > 0:
			if not card in _batch_cards:
				_batch_cards.append(card)
		else:
			_check_zero(card)


func _shows_other_than_base(card: Card) -> bool:
	for stat in STATS:
		if card.properties.has(stat) and card.properties[stat] != base(card, stat):
			return true
	return false


# The state-based check: Strike and Guard both 0 destroys a creature in play
func _check_zero(card: Card) -> void:
	if not FateZones.is_creature_in_play(card):
		return
	if current(card, "Strike") == 0 and current(card, "Guard") == 0:
		game.effects.destroy(card, null, FateEffects.CAUSE_STATS)


func _on_maintenance_started(player_id: int) -> void:
	# D7: the owner's maintenance. A creature may stand in the other player's zone (take-control
	# effects), so look at both players' creatures and go by owner.
	for card in game.creatures_in_play():
		if card.owner_id == player_id:
			reset_card(card)


func _on_end_of_turn_expiry(_player_id: int) -> void:
	expire(EXPIRY_END_OF_TURN)
