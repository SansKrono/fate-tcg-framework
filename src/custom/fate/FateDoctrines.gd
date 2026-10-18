# Doctrines: goals, achieved state and the helpers their rewards use. Assigned to `game.doctrines`.
# No class_name (FateGame loads it by path). docs/FATE_TCG_DESIGN.md Section 10.
#
# A doctrine is a card of Type "Doctrine" in a player's doctrines grid. Its text has a "Goal:" line, which is
# parsed here (goal_of), and a reward, which is the card script cards/Fx<Name>.gd (they extend
# cards/FateDoctrineEffect.gd). When the goal is met the doctrine is ACHIEVED: the flag is card meta
# (META), it persists until an effect removes it (set_achieved(card, false)) or the doctrine leaves the table, and
# the reward is active while it is set.
#
# Goals (the "Goal:" line):
#   Devotion N <Domain>   N pips of the domain on the player's creatures, relics and field spell
#                         (the Pips text holds the initial letters: "CC", "O")
#   Count control N       N cards the player controls but does not own (game.control.controlled_not_owned)
#   Count Creature N / Count Relic N / Count Energy N / Count Token N
#   Token Count N         scrap / ingot counters plus token cards (game.tokens.token_count)
#   Power N               a creature of the player with Strike or Guard >= N
#   Ghost Count N         creatures of the player tagged Ghost and/or embodying an energy card
#
# Evaluation runs after the events that change the table (phase begins, cards played, entered, left, destroyed,
# counters, control, flip casts, stat changes, damage, a loaded board state). A condition that holds only
# between two events is not noticed.
#
# Rewards are told with the script hooks on_reward_start(card) / on_reward_end(card) (FateDoctrineEffect): at the
# moment of achievement, again after a board state was loaded, and on_reward_end when the flag is removed.
# Helpers for the rewards: guards_upright (Be a Fierce Presence), attack_about_to_resolve (Vanquish Thine
# Foes, called by FateCombat), take_opponent_card_as_energy (Ensue Chaos).
extends RefCounted

signal doctrine_achieved(card: Card, player_id: int)
# The achieved flag of a doctrine card changed (a marker on the card follows it)
signal doctrine_changed(card: Card)

const META := "doctrine_achieved"
const TINT_ACHIEVED := Color(1.25, 1.12, 0.7)
const TINT_PENDING := Color(0.62, 0.62, 0.68)
# The choice name of the energy phase when a doctrine's option was taken (counts as an energy play)
const ENERGY_REWARD_KEY := "Ensue Chaos"

var game: FateGame
# False: goals are never checked (tests that are not about doctrines switch them off in FateCommon: the
# doctrines both players start with would otherwise fire on the creatures a test puts on the table)
var enabled := true
var _goals := {}
var _evaluating := false
var _again := false


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.phase_begins.connect(func(_p, _ph): evaluate())
	game.card_played.connect(func(_c): evaluate())
	game.creature_destroyed.connect(func(_c, _cause): evaluate())
	game.energy_played.connect(func(_c): evaluate())
	game.damage_dealt.connect(func(_s, _t, _a, _c): evaluate())
	game.board_state_loaded.connect(func(_n): resync())
	if game.tokens != null:
		game.tokens.counter_changed.connect(func(_p, _c, _v): evaluate())
		game.tokens.token_created.connect(func(_c): evaluate())
	if game.control != null:
		game.control.control_changed.connect(func(_c, _o, _n): evaluate())
	if game.casting != null:
		game.casting.flip_cast.connect(func(_c, _p): evaluate())
	if game.stats != null:
		game.stats.stats_changed.connect(func(_c): evaluate())
	if game.card_effects != null:
		game.card_effects.table_changed.connect(evaluate)


# --- state ---------------------------------------------------------------------------------------

# Is this doctrine achieved (its reward active)?
func achieved(card: Card) -> bool:
	return is_instance_valid(card) and bool(card.get_meta(META, false))


# Sets or removes the achieved flag ("unless an effect removes it"). Starts or ends the reward.
func set_achieved(card: Card, value: bool) -> void:
	if not is_instance_valid(card) or achieved(card) == value:
		return
	card.set_meta(META, value)
	_mark(card)
	var effect = _effect_of(card)
	if value:
		if effect != null and effect.has_method("on_reward_start"):
			effect.on_reward_start(card)
	elif effect != null and effect.has_method("on_reward_end"):
		effect.on_reward_end(card)
	_refresh_creatures()
	doctrine_changed.emit(card)
	if value:
		doctrine_achieved.emit(card, card.controller_id)


# The doctrine cards of a player (or of both, player_id 0) in the doctrines grid
func doctrine_cards(player_id := 0) -> Array:
	var found := []
	for pid in game.players:
		if player_id == 0 or pid == player_id:
			found.append_array(game.player(pid).cards_in_grid("doctrines"))
	return found


# The achieved doctrine of that name that `player_id` controls, or null
func active_card(card_name: String, player_id: int):
	for card in doctrine_cards(player_id):
		if card.canonical_name == card_name and achieved(card) and card.controller_id == player_id:
			return card
	return null


# Checks the goal of every doctrine that is not achieved yet
func evaluate() -> void:
	if not enabled:
		return
	if _evaluating:
		_again = true
		return
	_evaluating = true
	for card in doctrine_cards():
		_mark(card)
		if not achieved(card) and goal_met(card):
			set_achieved(card, true)
	_evaluating = false
	if _again:
		_again = false
		evaluate()


# After a board state was loaded: rewards that keep their state elsewhere (casting permissions are reset
# by the load) start again, the markers follow the flags, goals are checked (stat faces are the load's job)
func resync() -> void:
	for card in doctrine_cards():
		_mark(card)
		if achieved(card):
			var effect = _effect_of(card)
			if effect != null and effect.has_method("on_reward_start"):
				effect.on_reward_start(card)
	# The creature faces were refreshed by the load itself (a refresh here would run the 0/0 check)
	evaluate()


# --- goals -----------------------------------------------------------------------------------------

# The parsed goal of a doctrine: {"kind": "devotion" | "count" | "power" | "ghost", "n": int, "domain": String,
# "what": String ("control", "creature", "relic", "energy", "token")}. {} if the text has no known goal.
func goal_of(card: Card) -> Dictionary:
	var line := ""
	for text_line in str(card.properties.get("Abilities", "")).split("\n"):
		if text_line.begins_with("Goal:"):
			line = text_line.trim_prefix("Goal:").strip_edges()
	if _goals.has(line):
		return _goals[line]
	var goal := _parse(line)
	_goals[line] = goal
	return goal


static func _parse(line: String) -> Dictionary:
	var found := RegEx.create_from_string("^Devotion (\\d+) (\\w+)").search(line)
	if found != null:
		return {"kind": "devotion", "n": int(found.get_string(1)), "domain": found.get_string(2)}
	found = RegEx.create_from_string("^Token Count (\\d+)").search(line)
	if found != null:
		return {"kind": "count", "what": "token", "n": int(found.get_string(1))}
	found = RegEx.create_from_string("^Ghost Count (\\d+)").search(line)
	if found != null:
		return {"kind": "ghost", "n": int(found.get_string(1))}
	found = RegEx.create_from_string("^Power (\\d+)").search(line)
	if found != null:
		return {"kind": "power", "n": int(found.get_string(1))}
	found = RegEx.create_from_string("^Count (\\w+) (\\d+)").search(line)
	if found != null:
		return {"kind": "count", "what": found.get_string(1).to_lower(), "n": int(found.get_string(2))}
	return {}


func goal_met(card: Card) -> bool:
	var goal := goal_of(card)
	if goal.is_empty():
		return false
	return progress(card.controller_id, goal) >= int(goal["n"])


# The number the goal counts for a player, now
func progress(player_id: int, goal: Dictionary) -> int:
	match goal.get("kind", ""):
		"devotion":
			return devotion(player_id, str(goal["domain"]))
		"count":
			return count_of(player_id, str(goal["what"]))
		"power":
			var best := 0
			for creature in game.creatures_in_play(player_id):
				best = maxi(best, maxi(game.stats.current(creature, "Strike"), game.stats.current(creature, "Guard")))
			return best
		"ghost":
			var total := 0
			for creature in game.creatures_in_play(player_id):
				if is_ghost(creature) or is_embodying(creature):
					total += 1
			return total
	return 0


# Pips of a domain on the face-up permanents a player controls (creatures, relics, field spell)
func devotion(player_id: int, domain: String) -> int:
	var letter := ""
	for initial in FateGame.DOMAIN_BY_INITIAL:
		if FateGame.DOMAIN_BY_INITIAL[initial] == domain:
			letter = initial
	if letter == "":
		return 0
	var total := 0
	for zone in ["creatures", "occupied", "relics", "field"]:
		for card in game.player(player_id).cards_in_grid(zone):
			if card is FateCardTemplate and card.controller_id == player_id and card.is_faceup:
				total += str(card.properties.get("Pips", "")).count(letter)
	return total


func count_of(player_id: int, what: String) -> int:
	match what:
		"control":
			return game.control.controlled_not_owned(player_id).size()
		"creature":
			return game.creatures_in_play(player_id).size()
		"relic":
			return game.player(player_id).cards_in_grid("relics").filter(
					func(c): return c.controller_id == player_id).size()
		"energy":
			return game.player(player_id).cards_in_grid("energy").size()
		"token":
			return game.tokens.token_count(player_id)
	return 0


func is_ghost(card: Card) -> bool:
	var tags = card.properties.get("Tags", [])
	return tags is Array and "Ghost" in tags


func is_embodying(card: Card) -> bool:
	var embody = game.keywords.get_keyword("Embody")
	return embody != null and embody.embodied_card(card) != null


# --- helpers for the rewards -------------------------------------------------------------------------------------

# Be a Fierce Presence: may this creature guard from the strike position? It must be the highest-Strike
# creature (ties: all of them) of a player who has the doctrine achieved.
func guards_upright(creature: Card) -> bool:
	if not is_instance_valid(creature) or active_card("Be a Fierce Presence", creature.controller_id) == null:
		return false
	if not FateZones.is_creature_in_play(creature):
		return false
	var mine := game.stats.current(creature, "Strike")
	for other in game.creatures_in_play(creature.controller_id):
		if game.stats.current(other, "Strike") > mine:
			return false
	return true


# Vanquish Thine Foes: called by FateCombat right before an attack resolves. Every creature that interacts
# with an attack of the doctrine's owner (its blockers, the creature it attacks) is destroyed.
func attack_about_to_resolve(attack: FateAttack) -> void:
	if attack.removed or attack.negated or not is_instance_valid(attack.attacker):
		return
	var doctrine = active_card("Vanquish Thine Foes", attack.attacker.controller_id)
	if doctrine == null:
		return
	var victims: Array = attack.blockers.duplicate()
	if attack.target_card != null and FateZones.is_creature_in_play(attack.target_card):
		victims.append(attack.target_card)
	for victim in victims:
		if is_instance_valid(victim) and FateZones.is_creature_in_play(victim) \
				and victim.controller_id != attack.attacker.controller_id:
			game.effects.destroy(victim, doctrine, FateEffects.CAUSE_EFFECT)


# Ensue Chaos, as the choice of the energy phase: "instead of playing a card from hand, take the top card of an
# opponent's deck into your energy zone".
func can_take_opponent_card(player_id: int) -> bool:
	if active_card(ENERGY_REWARD_KEY, player_id) == null or game.energy_choice != "" or game.is_over \
			or game.phase != FateGame.Phase.ENERGY or game.active_id != player_id:
		return false
	var deck = FateZones.container("deck", FateZones.opponent_of(player_id))
	return deck != null and not deck.get_all_cards().is_empty() \
			and FateZones.grid("energy", player_id).find_available_slot() != null


# Does it. Returns the card taken, or null.
func take_opponent_card_as_energy(player_id: int) -> Card:
	if not can_take_opponent_card(player_id):
		return null
	var cards: Array = game.library.look_top(FateZones.opponent_of(player_id), 1)
	if cards.is_empty() or not game.library.to_energy(cards[0], player_id):
		return null
	game.energy_played.emit(cards[0])
	game._make_energy_choice(FateGame.CHOICE_ENERGY)
	return cards[0]


# --- internals ----------------------------------------------------------------------------------------------

func _effect_of(card: Card):
	return game.card_effects.effect_of(card.canonical_name) if game.card_effects != null else null


# The look of a doctrine card: dim until achieved, warm and bright after
func _mark(card: Card) -> void:
	var tint := TINT_ACHIEVED if achieved(card) else TINT_PENDING
	if card.modulate != tint:
		card.modulate = tint


# Static bonuses of rewards (Defend the Innocent) show on the card faces
func _refresh_creatures() -> void:
	for creature in game.creatures_in_play():
		game.stats.refresh(creature)
