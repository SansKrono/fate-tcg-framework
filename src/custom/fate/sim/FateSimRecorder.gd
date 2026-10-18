# Watches one game through its signals and turns it into a plain-data record for the report
# (FateSimReport). It only listens: it never changes the game.
#
# The record of a game (finish()):
#   {"type": "game", "game": number in the run, "matchup": n, "seed": text,
#    "winner_seat": 0 (nobody) | 1 | 2, "reason": "life" | "deck_out" | "turn_cap" | "stall",
#    "turns": the turn number the game ended on, "frames": n, "ms": wall-clock milliseconds,
#    "seats": {"1": seat data, "2": seat data}, "problems": [AI refusals, at most 6],
#    "errors": {"file.gd:12  text": count} script errors printed during the game (added by FateSimRunner)}
#   seat data: {"label", "deck" (0 = matchup deck a, 1 = b), "won": bool, "life_end", "life_by_turn": [life at
#     the start of each game turn, starting at turn 1], "creatures_lost", "dmg_taken": {cause: life lost},
#     "attacks", "player_hits", "blocked_attacks", "mana_spent", "mana_available", "board_sum", "board_turns",
#     "energy_plays", "draw_choices", "cards_played", "turns", "cards": {card name: card data}}
#   card data: {"copies" in the deck, "seen" (left the deck), "played" (cast or put into play from the hand),
#     "energy" (played as energy), "turn_sum" (sum of the turns it was played on), "dmg_c" (damage to
#     creatures), "dmg_p" (damage to players), "kills" (creatures destroyed with it as the source),
#     "deaths", "attacks", "hits" (unblocked hits on the player)}
#
# Damage causes in `dmg_taken`: "combat" (a creature hit), "death_loss" (a creature lost in combat, the
# source is null), and the cause strings of effects ("effect", "savage" ...).
#
# No class_name (see FateAIEval.gd).
extends RefCounted

var game: FateGame
var _seats := {}
var _deck_of_seat := {}
var _deck_out := 0


# `labels` and `decks` are by seat id: the deck label and which matchup deck (0 or 1) sits there
func _init(owner_game: FateGame, labels: Dictionary, decks: Dictionary) -> void:
	game = owner_game
	for seat in game.players:
		_seats[seat] = {
			"label": labels[seat], "deck": decks[seat], "won": false, "life_end": 0, "life_by_turn": [],
			"creatures_lost": 0, "dmg_taken": {}, "attacks": 0, "player_hits": 0, "blocked_attacks": 0,
			"mana_spent": 0, "mana_available": 0, "board_sum": 0, "board_turns": 0, "energy_plays": 0,
			"draw_choices": 0, "cards_played": 0, "turns": 0, "cards": {},
		}
		_deck_of_seat[seat] = decks[seat]
	game.turn_started.connect(_on_turn_started)
	game.end_phase_begins.connect(_on_end_phase)
	game.energy_phase_choice_made.connect(_on_energy_choice)
	game.energy_played.connect(_on_energy_played)
	game.card_played.connect(_on_card_played)
	game.creature_destroyed.connect(_on_destroyed)
	game.damage_dealt.connect(_on_damage)
	game.deck_empty.connect(func(pid): _deck_out = pid)
	game.combat.attack_declared.connect(_on_attack_declared)
	game.combat.attack_resolved.connect(_on_attack_resolved)


func disconnect_all() -> void:
	if not is_instance_valid(game):
		return
	for pair in [[game.turn_started, _on_turn_started], [game.end_phase_begins, _on_end_phase],
			[game.energy_phase_choice_made, _on_energy_choice], [game.energy_played, _on_energy_played],
			[game.card_played, _on_card_played], [game.creature_destroyed, _on_destroyed],
			[game.damage_dealt, _on_damage], [game.combat.attack_declared, _on_attack_declared],
			[game.combat.attack_resolved, _on_attack_resolved]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


# --- the signals -----------------------------------------------------------------------------------

func _card(seat: int, card_name: String) -> Dictionary:
	var cards: Dictionary = _seats[seat].cards
	if not cards.has(card_name):
		cards[card_name] = {"copies": 0, "seen": 0, "played": 0, "energy": 0, "turn_sum": 0, "dmg_c": 0,
				"dmg_p": 0, "kills": 0, "deaths": 0, "attacks": 0, "hits": 0}
	return cards[card_name]


# The seat whose deck a card belongs to, 0 if it is not a card of a deck
func _seat_of(card) -> int:
	if card is Card and is_instance_valid(card) and card is FateCardTemplate and _seats.has(card.owner_id):
		return card.owner_id
	return 0


func _on_turn_started(player_id: int, turn_number: int) -> void:
	# Both players' life at the start of each turn gives a life curve per turn number
	var seat: Dictionary = _seats[player_id]
	seat.turns += 1
	seat.life_by_turn.append(game.player(player_id).life)
	seat.board_sum += game.creatures_in_play(player_id).size()
	seat.board_turns += 1


func _on_end_phase(player_id: int) -> void:
	var total := game.player(player_id).cards_in_grid("energy").size()
	if total == 0:
		return
	var untapped := 0
	for v in game.mana_pool(player_id).values():
		untapped += v
	var seat: Dictionary = _seats[player_id]
	seat.mana_available += total
	seat.mana_spent += clampi(total - untapped, 0, total)


func _on_energy_choice() -> void:
	if game.energy_choice == FateGame.CHOICE_DRAW:
		_seats[game.active_id].draw_choices += 1


func _on_energy_played(card: Card) -> void:
	var seat := _seat_of(card)
	if seat == 0:
		return
	_seats[seat].energy_plays += 1
	_card(seat, card.canonical_name).energy += 1


func _on_card_played(card: Card) -> void:
	var seat := _seat_of(card)
	if seat == 0:
		return
	_seats[seat].cards_played += 1
	var data := _card(seat, card.canonical_name)
	data.played += 1
	data.turn_sum += game.turn_number


func _on_destroyed(card: Card, _cause: String) -> void:
	var seat := _seat_of(card)
	if seat != 0 and card.properties.get("Type") == "Creature":
		_seats[seat].creatures_lost += 1
		_card(seat, card.canonical_name).deaths += 1
	# FateEffects.last_source: who destroyed the card (null when the effects layer does not say)
	var killer = game.effects.get("last_source")
	var source_seat := _seat_of(killer)
	if source_seat != 0:
		_card(source_seat, killer.canonical_name).kills += 1


func _on_damage(source, target, amount: int, cause: String) -> void:
	var source_seat := _seat_of(source)
	if target is FatePlayer:
		var key := cause
		if source == null and cause == FateEffects.CAUSE_COMBAT:
			key = "death_loss"
		var taken: Dictionary = _seats[target.id].dmg_taken
		taken[key] = taken.get(key, 0) + amount
		if source_seat != 0:
			_card(source_seat, source.canonical_name).dmg_p += amount
	elif source_seat != 0:
		_card(source_seat, source.canonical_name).dmg_c += amount


func _on_attack_declared(attack: FateAttack) -> void:
	var seat := _seat_of(attack.attacker)
	if seat == 0:
		return
	_seats[seat].attacks += 1
	_card(seat, attack.attacker.canonical_name).attacks += 1


func _on_attack_resolved(attack: FateAttack, result: Dictionary) -> void:
	var seat := _seat_of(attack.attacker)
	if seat == 0:
		return
	match result.kind:
		"player":
			_seats[seat].player_hits += 1
			_card(seat, attack.attacker.canonical_name).hits += 1
		"blocked", "blockers_gone":
			_seats[seat].blocked_attacks += 1


# --- the record --------------------------------------------------------------------------------------

# Builds the record. `reason` is what the runner saw ("turn_cap" / "stall"), the recorder knows the others.
func finish(info: Dictionary, reason := "") -> Dictionary:
	var winner: int = game.winner_id if game.is_over else 0
	if game.is_over:
		reason = "deck_out" if _deck_out != 0 else "life"
	_count_cards()
	for seat in _seats:
		_seats[seat].won = seat == winner
		_seats[seat].life_end = game.player(seat).life
	var problems: Array = []
	for seat in game.ai_controllers:
		var controller = game.ai_controllers[seat]
		if is_instance_valid(controller):
			problems.append_array(controller.problems)
	var out := info.duplicate()
	out["type"] = "game"
	out["winner_seat"] = winner
	out["reason"] = reason
	out["turns"] = game.turn_number
	var seats := {}
	for seat in _seats:
		seats[str(seat)] = _seats[seat]
	out["seats"] = seats
	out["problems"] = problems.slice(0, 6)
	return out


# Every card of a deck is somewhere: still in the deck (not seen), or elsewhere (seen)
func _count_cards() -> void:
	for pid in game.players:
		for zone in ["deck", "hand", "discard", "removed"]:
			var container = FateZones.container(zone, pid)
			if container != null:
				for card in container.get_all_cards():
					_count_card(card, zone != "deck")
		for zone in FateZones.GRIDS:
			for card in game.player(pid).cards_in_grid(zone):
				_count_card(card, true)
	var world := FateZones.grid("world", 0)
	if world != null:
		for slot in world.get_all_slots():
			if slot.occupying_card:
				_count_card(slot.occupying_card, true)


func _count_card(card, seen: bool) -> void:
	var seat := _seat_of(card)
	if seat == 0:
		return
	var props: Dictionary = card.properties
	if props.get("Type") == "Doctrine" or cfc.card_definitions.get(card.canonical_name, {}).get("_token", false):
		return
	var data := _card(seat, card.canonical_name)
	data.copies += 1
	if seen:
		data.seen += 1
