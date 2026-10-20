# Turns the live table into plain data the AI can search without touching nodes: the "snapshot".
#
# state = {
#   "me", "opp"      the seat the AI plays and the other seat
#   "turn", "active", "phase"
#   "life"           {1: int, 2: int}
#   "units"          {uid: unit}  every creature in play of both players, see unit_of()
#   "mana"           {pid: {"total": energy cards, "untapped": int, "pool": {domain: n}}}
#   "hand_me"        Array of the AI's own cards in hand (live nodes, the AI may look at them)
#   "hand_count"     {pid: int}
#   "deck_count"     {pid: int}
#   "discard"        {pid: Array of card names}  public information
#   "hand_opp"       only when `cheat` is set: the opponent's cards, see FateAIProfile.cheat
#   "face_weight"    how much damage to the opponent's life is worth (profile aggression)
#   "w"              the valuation weights of the seat's profile (FateAIProfile.eval_weights); absent = defaults
#   "ai_seats"       the seats played by an AI (their Savage creatures pick targets, FateAISim._savage)
# }
#
# Hidden information: the opponent's hand and deck order are NOT in a snapshot unless `cheat` is on.
# The engine does not hide them (hands are only visual), so this is where the AI plays fair.
#
# No class_name (see FateAIEval.gd).
extends RefCounted


# The snapshot for a seat with its profile: the aggression, the cheat flag and the valuation weights
static func for_profile(game: FateGame, me: int, profile) -> Dictionary:
	return build(game, me, profile.aggression, profile.cheat, profile.eval_weights())


static func build(game: FateGame, me: int, face_weight := 1.0, cheat := false, weights := {}) -> Dictionary:
	var state := {
		"me": me, "opp": FateZones.opponent_of(me),
		"turn": game.turn_number, "active": game.active_id, "phase": game.phase,
		"life": {}, "units": {}, "mana": {}, "hand_count": {}, "deck_count": {}, "discard": {},
		"hand_me": [], "face_weight": face_weight, "ai_seats": game.ai_controllers.keys(),
	}
	if not weights.is_empty():
		state["w"] = weights
	for pid in game.players:
		var p: FatePlayer = game.players[pid]
		state.life[pid] = p.life
		var pool: Dictionary = game.mana_pool(pid)
		var untapped := 0
		for d in pool:
			untapped += pool[d]
		state.mana[pid] = {
			"total": p.cards_in_grid("energy").size(), "untapped": untapped, "pool": pool,
		}
		var hand = p.hand()
		state.hand_count[pid] = hand.get_all_cards().size() if hand else 0
		var deck = p.deck()
		state.deck_count[pid] = deck.get_all_cards().size() if deck else 0
		var names: Array = []
		var discard = p.discard()
		if discard:
			for c in discard.get_all_cards():
				names.append(c.canonical_name)
		state.discard[pid] = names
		for card in game.creatures_in_play(pid):
			var u := unit_of(game, card)
			state.units[u.uid] = u
	var my_hand = game.player(me).hand()
	if my_hand:
		state.hand_me = my_hand.get_all_cards()
	if cheat:
		var opp_hand = game.player(state.opp).hand()
		state["hand_opp"] = opp_hand.get_all_cards() if opp_hand else []
	return state


# One creature in play as a dictionary:
#   uid, card (the node), name, owner, ctrl (controller)
#   strike, guard          the current stats (after damage and modifiers)
#   full_strike, full_guard  the same without damage (what the creature heals back to)
#   pos                    "strike" (upright in the creature zone), "guard" (tilted there) or "occupied"
#   kw                     {keyword name: value}, innate and granted
#   mv                     mana value
#   unique                 legendary
#   sick                   entered play this turn (cannot attack without Charge)
#   can_attack             the keywords allow it to attack (position and phase are checked separately)
static func unit_of(game: FateGame, card: Card) -> Dictionary:
	var zone := FateZones.zone_of(card)
	var pos := "strike"
	if zone == "occupied":
		pos = "occupied"
	elif card.card_rotation == 90:
		pos = "guard"
	var stats := game.stats
	var s: int = stats.current(card, "Strike")
	var g: int = stats.current(card, "Guard")
	var owner_id: int = card.owner_id if card is FateCardTemplate else 0
	var ctrl: int = card.controller_id if card is FateCardTemplate else 0
	var entered: int = card.entered_turn if card is FateCardTemplate else 0
	return {
		"uid": card.get_instance_id(), "card": card, "name": card.canonical_name,
		"owner": owner_id, "ctrl": ctrl,
		"strike": s, "guard": g,
		"full_strike": s + stats.damage_on(card, "Strike"),
		"full_guard": g + stats.damage_on(card, "Guard"),
		"pos": pos, "kw": game.keywords.all_on(card), "mv": card.mana_value(),
		"unique": bool(card.properties.get("_unique", false)),
		"token": bool(card.properties.get("_token", false)),
		"ability": has_engine(game.card_effects.effect_of(card.canonical_name)) if game.card_effects != null else false,
		"sick": entered > 0 and entered == game.turn_number,
		"can_attack": game.keywords.can_attack(card),
	}


# The creatures of one player in a snapshot
static func units_of(state: Dictionary, pid: int) -> Array:
	var found: Array = []
	for uid in state.units:
		if state.units[uid].ctrl == pid:
			found.append(state.units[uid])
	return found


# A copy of a snapshot that can be changed without touching the original (cards are shared)
static func copy_of(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


# The methods the card's own script file defines (not the inherited ones)
static func script_methods(effect) -> Array:
	var names: Array = []
	var script = effect.get_script()
	if script != null:
		for m in script.get_script_method_list():
			names.append(m.name)
	return names


# Is the card a piece of an engine: its script has an activated ability (actions) or a trigger that fires over
# the turns? (The engine_value and w_ability weights.) Cached per script.
static var _engine_cache := {}

static func has_engine(effect) -> bool:
	if effect == null:
		return false
	var script = effect.get_script()
	if script == null:
		return false
	var key: String = script.resource_path
	if _engine_cache.has(key):
		return _engine_cache[key]
	var methods := script_methods(effect)
	var found := false
	for hook in ["actions", "on_phase", "on_maintenance", "on_turn_end", "on_attack_declared",
			"on_attack_resolved", "on_card_played", "on_energy_played", "on_card_destroyed"]:
		if hook in methods:
			found = true
	_engine_cache[key] = found
	return found
