# The card script registry: finds the Fx*.gd scripts of src/custom/fate/cards/, hands them to the
# keyword registry (a card script is a keyword for the card with its name, see cards/FateCardEffect.gd)
# and turns game events into the calls of the hooks that FateKeyword does not have: a card was played, a
# permanent entered or left the table, a spell resolves, something happened that the cards on the table
# watch. Assigned to `game.card_effects`. No class_name on purpose (FateGame loads it by path, the way it
# loads FateReactions: the global class cache is shared by everybody working at once).
#
# What reaches a script, and from where:
#   keyword hooks (can_attack, on_destroyed, actions, stat_bonus ...)   FateKeywords.hooks_for adds the script
#   play_problem                                                        FateGame.can_play_from_hand
#   resolve / pay_extra_cost / on_play (regular spells)                 game.card_played, a spell is being played
#   on_play / on_enter (permanents)                                     game.card_played, then the card settles
#   on_enter for cards that did not come from the hand                  FateCardTemplate.common_post_move_scripts
#   on_leave                                                            FateCardTemplate.common_post_move_scripts
#   on_card_played / on_card_destroyed / on_phase / on_damage /
#   on_energy_played / on_attack_resolved                               the signals of FateGame and FateCombat
#   static_keywords / static_stat_bonus                                 FateKeywords.all_on / FateStats.current
extends RefCounted

const EFFECT_DIR := "res://src/custom/fate/cards/"
const EFFECT_PREFIX := "Fx"
# The zones whose cards count as "on the table" for watching and static effects (not energy: face-down
# energy cards have no abilities, docs/FATE_TCG_DESIGN.md Section 6)
const TABLE_ZONES := ["creatures", "occupied", "relics", "field", "doctrines"]

var game: FateGame
# card name -> script instance
var _effects := {}
# Card -> {"caster": int, "choice": the pick already made or null, "done": bool, "resolved": bool}: casts that
# FateCasting runs from somewhere other than the hand, see begin_cast
var _casts := {}


func _init(owner_game: FateGame) -> void:
	game = owner_game
	discover()
	game.card_played.connect(_on_card_played)
	game.creature_destroyed.connect(_on_card_destroyed)
	game.phase_begins.connect(_on_phase_begins)
	game.damage_dealt.connect(_on_damage_dealt)
	game.energy_played.connect(_on_energy_played)
	game.combat.attack_resolved.connect(_on_attack_resolved)
	if game.casting != null:
		game.casting.flip_cast.connect(_on_flip_cast)


# --- registration --------------------------------------------------------------------------------

# Scans a folder (default EFFECT_DIR) and registers every Fx*.gd script. Returns how many.
func discover(folder := EFFECT_DIR) -> int:
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
			push_warning("FateCardEffects: cannot load card script " + script_name)
			continue
		var effect = script.new()
		if not effect is FateKeyword or effect.get("card_name") == null or effect.card_name == "":
			push_warning("FateCardEffects: %s is not a card script with a card_name" % script_name)
			continue
		register(effect)
		found += 1
	return found


# "FxSmite.gd.remap" / "FxSmite.gdc" (exports) -> "FxSmite.gd"; "" for anything that is not a card script
static func script_file_name(file_name: String) -> String:
	var n := file_name
	if n.ends_with(".remap"):
		n = n.trim_suffix(".remap")
	if n.ends_with(".gdc"):
		n = n.trim_suffix(".gdc") + ".gd"
	if n.begins_with(EFFECT_PREFIX) and n.ends_with(".gd"):
		return n
	return ""


# Adds (or replaces) the script of a card. Tests use it for scripts that are not in EFFECT_DIR.
func register(effect) -> void:
	effect.game = game
	effect.keyword_name = effect.card_name
	_effects[effect.card_name] = effect


func unregister(card_name: String) -> void:
	_effects.erase(card_name)


# The script of a card name, or null
func effect_of(card_name: String):
	return _effects.get(card_name)


func registered_names() -> Array:
	var names := _effects.keys()
	names.sort()
	return names


# --- the cards on the table -----------------------------------------------------------------------

# Every card on the table that counts for watching and static effects, both players, plus the world slot
func table_cards() -> Array:
	var found := []
	for pid in game.players:
		for zone in TABLE_ZONES:
			found.append_array(game.players[pid].cards_in_grid(zone))
	var world := FateZones.grid("world", 0)
	if world != null:
		for slot in world.get_all_slots():
			if slot.occupying_card:
				found.append(slot.occupying_card)
	return found


# --- questions the rest of the game asks ---------------------------------------------------------------------

# Why a card cannot be played from the hand now, according to its script: "" if it can
func play_problem(card: Card) -> String:
	var effect = _effects.get(card.canonical_name)
	if effect == null:
		return ""
	return effect.play_problem(card, card.owner_id)


# The zone name (of its owner) a resolved regular spell goes to. Asked of the spell's own script, then of
# the cards on the table; "discard" if nobody has an opinion. FateCardTemplate moves the card there.
func spell_destination(spell: Card) -> String:
	var own = _effects.get(spell.canonical_name)
	if own != null:
		var zone: String = own.spell_destination(spell, spell.owner_id)
		if zone != "":
			return zone
	for table_card in table_cards():
		var effect = _effects.get(table_card.canonical_name)
		if effect == null:
			continue
		var zone: String = effect.spell_destination_for(table_card, spell) \
				if effect.has_method("spell_destination_for") else ""
		if zone != "":
			return zone
	return "discard"


# Keywords that the cards on the table give to `target` ({name: value}); merged into all_on()
func static_keywords(target: Card) -> Dictionary:
	var merged := {}
	for host in table_cards():
		var effect = _effects.get(host.canonical_name)
		if effect == null:
			continue
		var given: Dictionary = effect.static_keywords(host, target)
		for k in given:
			merged[k] = int(merged.get(k, 0)) + int(given[k])
	return merged


# Strike / Guard that the cards on the table give to `target`; added into FateStats.current
func static_stat_bonus(target: Card, stat: String) -> int:
	var total := 0
	for host in table_cards():
		var effect = _effects.get(host.canonical_name)
		if effect != null:
			total += effect.static_stat_bonus(host, target, stat)
	return total


# --- the lifecycle of a card, called by FateCardTemplate and the signals below ------------------------------------

# A card landed in a table zone (not energy) by any means. `from_hand` is true when it was played from
# the hand (then card_played already ran on_play). Deferred one frame so that the card has settled in its slot.
func card_entered(card: Card, from_hand := false) -> void:
	_enter.call_deferred(card)


func _enter(card: Card) -> void:
	if not is_instance_valid(card) or FateZones.zone_of(card) not in TABLE_ZONES + ["world"]:
		return
	var effect = _effects.get(card.canonical_name)
	if effect != null:
		await effect.on_enter(card)


# A card left the table for `destination`. Called (deferred) by FateCardTemplate.common_pre_move_scripts.
func card_left(card: Card, destination: String) -> void:
	if not is_instance_valid(card):
		return
	# Whatever the card was giving (modifiers, keyword grants with it as the source) ends with it
	game.stats.remove_modifiers_from(card)
	var effect = _effects.get(card.canonical_name)
	if effect != null:
		effect.on_leave(card, destination)
	# A token that left the table ceases to exist (it never reaches a pile)
	if game.tokens != null and game.tokens.is_token(card):
		game.tokens.token_left(card, destination)


# --- events -----------------------------------------------------------------------------------------------------------

func _on_card_played(card: Card) -> void:
	if not is_instance_valid(card):
		return
	# A cast that FateCasting runs (flip cast, cast from the discard pile): its caster and pick, and it
	# is told when this is over. Cards played from the hand have no entry.
	var info: Dictionary = _casts.get(card, {})
	var effect = _effects.get(card.canonical_name)
	if card is FateCardTemplate and card.is_instant_spell() and not card.is_reaction_spell():
		if effect != null:
			info["resolved"] = await _cast(card, effect, int(info.get("caster", card.owner_id)),
					info.get("choice"))
	elif effect != null:
		effect.on_play(card)
	for table_card in table_cards():
		var watcher = _effects.get(table_card.canonical_name)
		if watcher != null and table_card != card:
			watcher.on_card_played(table_card, card)
	info["done"] = true


# A regular spell is being played: pay the extra cost, pick, resolve, then on_play. `caster` is the
# owner when the spell is played from the hand; `given_choice` is a pick already made (null: ask). Returns
# whether the spell resolved.
func _cast(card: Card, effect, caster: int, given_choice = null) -> bool:
	if not await effect.pay_extra_cost(card, caster):
		return false
	var choice = given_choice
	if effect.has_choice and choice == null:
		choice = await game.choices.pick_for_card(effect, card, caster)
		var why: String = effect.choice_problem(card, caster, choice)
		if why != "":
			push_warning("FateCardEffects: %s: %s" % [card.canonical_name, why])
			return false
	await effect.resolve(card, caster, choice)
	effect.on_play(card)
	return true


# --- casts from other zones (FateCasting) -------------------------------------------------------------

# Announces that the next `game.card_played` of `card` is a cast by `caster_id` from somewhere other than
# the hand, with `choice` already made (null: the spell asks game.choices). The cast pipeline of the hand
# then runs for it; poll cast_running and call end_cast when it is over.
func begin_cast(card: Card, caster_id: int, choice = null) -> void:
	_casts[card] = {"caster": caster_id, "choice": choice, "done": false, "resolved": false}


# Is the cast announced by begin_cast still running (a spell waiting for a pick ...)?
func cast_running(card: Card) -> bool:
	return _casts.has(card) and not _casts[card]["done"]


# Forgets the announced cast. Returns whether a regular spell resolved (true for any other card).
func end_cast(card: Card) -> bool:
	var info: Dictionary = _casts.get(card, {})
	_casts.erase(card)
	if not is_instance_valid(card) or not card is FateCardTemplate or not card.is_instant_spell():
		return true
	return bool(info.get("resolved", false))


func _on_flip_cast(card: Card, player_id: int) -> void:
	for table_card in table_cards():
		var watcher = _effects.get(table_card.canonical_name)
		if watcher != null:
			watcher.on_flip_cast(table_card, card, player_id)


func _on_card_destroyed(card: Card, cause: String) -> void:
	for table_card in table_cards():
		var watcher = _effects.get(table_card.canonical_name)
		if watcher != null and table_card != card:
			watcher.on_card_destroyed(table_card, card, cause, null)


func _on_phase_begins(active_id: int, phase: int) -> void:
	for table_card in table_cards():
		var watcher = _effects.get(table_card.canonical_name)
		if watcher != null:
			watcher.on_phase(table_card, active_id, phase)


func _on_damage_dealt(source, target, amount: int, cause: String) -> void:
	for table_card in table_cards():
		var watcher = _effects.get(table_card.canonical_name)
		if watcher != null:
			watcher.on_damage(table_card, source, target, amount, cause)


func _on_energy_played(energy: Card) -> void:
	for table_card in table_cards():
		var watcher = _effects.get(table_card.canonical_name)
		if watcher != null:
			watcher.on_energy_played(table_card, energy)


func _on_attack_resolved(attack: FateAttack, result: Dictionary) -> void:
	var hosts: Array = [attack.attacker]
	hosts.append_array(attack.blockers)
	if attack.target_card != null:
		hosts.append(attack.target_card)
	for host in hosts:
		if not is_instance_valid(host):
			continue
		var effect = _effects.get(host.canonical_name)
		if effect != null:
			effect.on_attack_resolved(host, attack, result)
