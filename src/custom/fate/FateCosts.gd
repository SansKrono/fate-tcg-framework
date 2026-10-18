# Costs of activated abilities, as small dictionaries a card script lists in make_action() (see
# cards/FateCardEffect.gd). Assigned to `game.costs`. No class_name (FateGame loads it by path).
#
# A cost is {"id": String, "label": String, "problem": Callable(card) -> String, "pay": Callable(card) -> bool}:
# `problem` says why it cannot be paid right now ("" if it can), `pay` pays it. The card is the one whose
# ability it is. Costs are checked all together first and paid in order, so a cost must not depend on
# another cost of the same ability having been paid.
#
# Ready-made costs
#   occupy()                         tilt and move to the occupied zone ("Occupy", and "Tap": Section 12 item 5)
#   tilt_self()                      "Occupy" of a relic (Ancient Tree): tilt it, it untaps at maintenance
#   mana(n)                          "Pay N": N generic mana
#   pay_domain(domain, n)            "Pay one Order mana": N untapped energy cards of one domain
#   consume_self()                   "Consume this card"
#   consume_card(zones, filter, count, options)       "Consume a creature / relic / energy card ..."
#   consume_other_cards(zones, filter, count, chosen) the same, never the card itself, with cards the caller picked
#   discard_hand_card(count, filter)  "Discard a card"
#   return_self_to_hand()            "Return this card to your hand"
#   counter(name, n)                 "Consume N scrap" (FateTokens)
#   once_per_turn(key, uses, scope)  Limiter / "once per turn" (FateLimiter); once_per_game(key)
#   either(a, b)                     "Consume a scrap or pay 1": the first alternative that can be paid
# Helpers for filters (Callable(candidate, source) -> bool): filter_creature(), filter_type(type),
# filter_non_token(), filter_token(), filter_name(name), filter_all([f1, f2]).
# Spells with an "additional cost: consume X permanents": cost_pay_extra() from FateCardEffect.pay_extra_cost.
#
# List once_per_turn LAST in an ability's costs: it counts the use when it is paid, and an earlier cost that
# stays paid because a later one failed is the lesser loss.
extends RefCounted

# Every zone whose cards are "permanents" ("consume X permanents": Self-destruction). Doctrines are not.
const PERMANENT_ZONES := ["creatures", "occupied", "relics", "field", "energy", "world"]
# The zones a creature stands in
const CREATURE_ZONES := ["creatures", "occupied"]

var game: FateGame


func _init(owner_game: FateGame) -> void:
	game = owner_game


# The first reason a cost of the list cannot be paid, or ""
func problem(card: Card, costs: Array) -> String:
	for cost in costs:
		var why: String = cost.problem.call(card)
		if why != "":
			return why
	return ""


# Pays the costs in order. Returns false if one of them failed (the earlier ones stay paid). A coroutine
# (a cost may wait for a choice): `await game.costs.pay(card, costs)`.
func pay(card: Card, costs: Array) -> bool:
	for cost in costs:
		if not await cost.pay.call(card):
			return false
	return true


# --- Occupy and mana ----------------------------------------------------------------------------------------

# "Occupy" (and "Tap": the same): tilt the creature and move it to the occupied zone (needs the Occupy
# rules: main phase, free occupied slot, not the turn it entered unless Productive)
func occupy() -> Dictionary:
	var kw = game.keywords.get_keyword("Occupy")
	return _cost("occupy", "Occupy",
			func(card): return kw.occupy_problem(card),
			func(card): return kw.occupy(card))


# "Occupy" of a RELIC (Ancient Tree): tilt it. A relic has no occupied zone; it untaps at its controller's
# maintenance. Only for permanents that are not creatures (a creature uses occupy()).
func tilt_self() -> Dictionary:
	return _cost("tilt_self", "Tilt",
			func(card):
				if FateZones.zone_of(card) == "":
					return "Not on the table"
				return "" if card.card_rotation == 0 else "Already tilted",
			func(card):
				card.set_card_rotation(90)
				return true)


# "Pay N": N generic mana
func mana(amount: int) -> Dictionary:
	return _cost("mana", "Pay %d" % amount,
			func(card): return "" if game.mana.can_pay_generic(card.controller_id, amount) else "Not enough mana",
			func(card): return game.mana.pay_generic(card.controller_id, amount))


# "Pay one Primal mana": `amount` untapped energy cards of one domain are tapped
func pay_domain(domain: String, amount := 1) -> Dictionary:
	return _cost("pay_domain", "Pay %d %s" % [amount, domain],
			func(card): return "" if _untapped_of(card.controller_id, domain).size() >= amount \
					else "Not enough %s mana" % domain,
			func(card):
				var pool := _untapped_of(card.controller_id, domain)
				if pool.size() < amount:
					return false
				for energy in pool.slice(0, amount):
					energy.set_card_rotation(90)
				game.mana_changed.emit(card.controller_id)
				return true)


func _untapped_of(player_id: int, domain: String) -> Array:
	return game.mana.untapped_energy(player_id).filter(
			func(energy): return game.mana.energy_domain(energy) == domain)


# --- consume --------------------------------------------------------------------------------------------------------

# "Consume this card": move it to its owner's discard pile (not destroyed: no death triggers; a token
# ceases to exist)
func consume_self() -> Dictionary:
	return _cost("consume_self", "Consume",
			func(card): return "" if FateZones.zone_of(card) != "" else "Not on the table",
			func(card): return consume(card))


# "Consume a card": the controller picks `count` cards of the zones ("hand", "creatures", "occupied",
# "relics", "energy", "field", "world"; PERMANENT_ZONES for "a permanent") that pass `filter` (a Callable
# taking the candidate and the ability's card, returning bool) and they move to their OWNERS' discard piles.
# `options`:
#   "controller": "you" (default, the controller of the ability's card), "opponent" ("a creature you do not
#                 control": Ikthar; control, not ownership, Section 12 item 12) or "any"
#   "exclude_self": the ability's own card is not a candidate (false by default)
#   "chosen":     the cards to consume, already picked by the caller (an Array, or a Callable(card) that
#                 returns one, may be a coroutine) instead of asking game.choices
#   "label":      the label of the cost
func consume_card(zones: Array, filter := Callable(), count := 1, options := {}) -> Dictionary:
	var label: String = options.get("label", "Consume %d" % count)
	return _cost("consume_card", label,
			func(card): return _consume_problem(card, card.controller_id, zones, filter, count, options),
			func(card): return await _consume_pay(card, card.controller_id, zones, filter, count, options))


# "Consume another card": consume_card that never takes the ability's own card, with the cards the caller
# picked (`chosen`: an Array or a Callable returning one, null to let game.choices ask). The AI and tests
# supply their cards this way.
func consume_other_cards(zones: Array, filter := Callable(), count := 1, chosen = null,
		options := {}) -> Dictionary:
	var opts := options.duplicate()
	opts["exclude_self"] = true
	if chosen != null:
		opts["chosen"] = chosen
	return consume_card(zones, filter, count, opts)


# "Discard a card" from the hand (to the owner's discard pile; the same as consuming from the hand)
func discard_hand_card(count := 1, filter := Callable()) -> Dictionary:
	return consume_card(["hand"], filter, count, {"label": "Discard %d" % count})


# "Return this card to your hand" (a token ceases to exist)
func return_self_to_hand() -> Dictionary:
	return _cost("return_self", "Return to hand",
			func(card): return "" if FateZones.zone_of(card) != "" else "Not on the table",
			func(card): return return_to_hand(card))


# "Consume N scrap" and other counters (FateTokens)
func counter(counter_name: String, amount := 1) -> Dictionary:
	return _cost("counter", "Consume %d %s" % [amount, counter_name],
			func(card): return "" if game.tokens.counter(card.controller_id, counter_name) >= amount \
					else "Not enough %s" % counter_name,
			func(card): return game.tokens.spend(card.controller_id, counter_name, amount))


# The first of the alternatives that can be paid ("consume a scrap or pay 1"). The cost can be paid if any of
# them can; the first payable one is paid.
func either(first: Dictionary, second: Dictionary) -> Dictionary:
	return _cost("either", "%s or %s" % [first.label, second.label],
			func(card):
				var why: String = first.problem.call(card)
				if why == "":
					return ""
				return second.problem.call(card),
			func(card):
				if first.problem.call(card) == "":
					return await first.pay.call(card)
				return await second.pay.call(card))


# --- limiter ----------------------------------------------------------------------------------------------------------

# "Once per turn" / Limiter X: the ability may be used `uses` times per turn under this key (FateLimiter).
# `scope` "card" (default: each card has its own count) or "player" (all the player's cards share the key).
func once_per_turn(key := "ability", uses := 1, scope := "card") -> Dictionary:
	return _limit_cost(key, uses, scope, game.limiter.TURN,
			"Once per turn" if uses == 1 else "%d times per turn" % uses, "Already used this turn")


# "Once per game"
func once_per_game(key := "ability", scope := "card") -> Dictionary:
	return _limit_cost(key, 1, scope, game.limiter.GAME, "Once per game", "Already used this game")


func _limit_cost(key: String, uses: int, scope: String, mode: String, label: String, why: String) -> Dictionary:
	return _cost("limiter", label,
			func(card):
				var allowed: bool = game.limiter.can_use_player(card.controller_id, key, uses, mode) \
						if scope == "player" else game.limiter.can_use(card, key, uses, mode)
				return "" if allowed else why,
			func(card):
				return game.limiter.use_player(card.controller_id, key, uses, mode) if scope == "player" \
						else game.limiter.use(card, key, uses, mode))


# --- filters (Callable(candidate, source) -> bool) --------------------------------------------------------------

func filter_creature() -> Callable:
	return filter_type("Creature")


func filter_type(card_type: String) -> Callable:
	return func(c, _source): return c.properties.get("Type") == card_type


func filter_name(card_name: String) -> Callable:
	return func(c, _source): return c.canonical_name == card_name


func filter_non_token() -> Callable:
	return func(c, _source): return not is_token(c)


func filter_token() -> Callable:
	return func(c, _source): return is_token(c)


# All of the filters (invalid ones are skipped)
func filter_all(filters: Array) -> Callable:
	return func(c, source):
		for f in filters:
			if f is Callable and f.is_valid() and not f.call(c, source):
				return false
		return true


# --- the cards a consume cost can take -----------------------------------------------------------------------------

# The cards `source`'s ability could consume (see consume_card for the options). `options.player`
# overrides whose point of view it is (default: the controller of `source`).
func consume_candidates(source: Card, zones: Array, filter := Callable(), options := {}) -> Array:
	var you: int = options.get("player", source.controller_id)
	var who: String = options.get("controller", "you")
	var pids := []
	for pid in game.players:
		if who == "any" or (who == "you" and pid == you) or (who == "opponent" and pid != you):
			pids.append(pid)
	var found := []
	for zone in zones:
		for pid in pids:
			for c in _cards_of(pid, zone):
				if c in found or (options.get("exclude_self", false) and c == source):
					continue
				if not filter.is_valid() or filter.call(c, source):
					found.append(c)
	return found


# The cards of a player in one zone ("hand", a grid zone, or "world": the shared slot counts for the player
# who controls its card)
func _cards_of(pid: int, zone: String) -> Array:
	if zone == "hand":
		return game.player(pid).hand().get_all_cards()
	if zone != "world":
		return game.player(pid).cards_in_grid(zone)
	var found := []
	var world := FateZones.grid("world", 0)
	if world == null:
		return found
	for slot in world.get_all_slots():
		if slot.occupying_card and slot.occupying_card.controller_id == pid:
			found.append(slot.occupying_card)
	return found


# Moves a card to its owner's discard pile as a cost ("Consume"). A token ceases to exist instead.
# Returns whether it moved.
func consume(card: Card) -> bool:
	if not is_instance_valid(card):
		return false
	var owner_id: int = card.owner_id if card is FateCardTemplate else game.active_id
	var was_energy: bool = card is FateCardTemplate and card.is_energy
	if is_token(card):
		_cease_to_exist(card)
		return true
	card.set_card_rotation(0)
	_move_off_the_table(card, FateZones.container("discard", owner_id))
	if was_energy:
		game.mana_changed.emit(card.controller_id)
	return true


# "Return to hand": to the OWNER's hand (a token ceases to exist)
func return_to_hand(card: Card) -> bool:
	if not is_instance_valid(card):
		return false
	if is_token(card):
		_cease_to_exist(card)
		return true
	var owner_id: int = card.owner_id if card is FateCardTemplate else game.active_id
	card.set_card_rotation(0)
	_move_off_the_table(card, FateZones.container("hand", owner_id))
	return true


# Is this card a token (a card from FateData.TOKENS)? Asks game.tokens when it can, else the data flag.
func is_token(card: Card) -> bool:
	if game.tokens != null and game.tokens.has_method("is_token"):
		return game.tokens.is_token(card)
	return bool(card.properties.get("_token", false))


# A scripted move to a pile or the hand. The framework frees the grid slot of the card only after the move
# animation, so for a moment the slot would still look taken (and the late cleanup would also wipe a card
# that was put there meanwhile): free it now.
func _move_off_the_table(card: Card, destination: Node) -> void:
	var on_table: bool = card.get_parent() == cfc.NMAP.board
	card.move_to(destination, -1, null, ["Scripted"])
	if on_table and card.get_parent() != cfc.NMAP.board:
		var slot: BoardPlacementSlot = card._placement_slot
		if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
			slot.occupying_card = null
		card._placement_slot = null


# A token that is consumed or returned does not go to any pile: it is gone (same as FateLibrary)
func _cease_to_exist(card: Card) -> void:
	if card.get_parent() == cfc.NMAP.board:
		var slot: BoardPlacementSlot = card._placement_slot
		if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
			slot.occupying_card = null
		card._placement_slot = null
		if not (card is FateCardTemplate and card.is_energy):
			game.card_effects.card_left(card, "gone")
		game.stats.clear_card(card)
	card.queue_free()


# --- "additional cost: consume X permanents" (FateCardEffect.pay_extra_cost) --------------------------------

# Why `caster` cannot pay an extra cost of consuming `count` cards of `zones` (the spell itself is never
# one of them), or "". For FateCardEffect.play_problem.
func extra_problem(card: Card, caster: int, zones: Array, filter := Callable(), count := 1,
		options := {}) -> String:
	var opts := options.duplicate()
	opts["player"] = caster
	opts["exclude_self"] = true
	return _consume_problem(card, caster, zones, filter, count, opts)


# Pays an extra cost of a spell: `caster` picks `count` cards of `zones` that pass `filter` and consumes them
# (to their owners' discard piles). A coroutine, for FateCardEffect.pay_extra_cost:
#
#   func pay_extra_cost(card, caster):
#       return await game.costs.cost_pay_extra(card, caster, game.costs.PERMANENT_ZONES, Callable(), 2)
#
# Returns false (nothing consumed) if the cost cannot be paid. The same options as consume_card; "chosen"
# lets the caller supply the cards.
func cost_pay_extra(card: Card, caster: int, zones: Array, filter := Callable(), count := 1,
		options := {}) -> bool:
	var opts := options.duplicate()
	opts["player"] = caster
	opts["exclude_self"] = true
	if _consume_problem(card, caster, zones, filter, count, opts) != "":
		return false
	return await _consume_pay(card, caster, zones, filter, count, opts)


# "Opponents consume X permanents": `player` chooses and consumes `count` cards of `zones` that pass `filter`
# (as many as they have if fewer). The player's own choice (game.choices.pick for them). Returns the cards
# consumed.
func force_consume(source: Card, player: int, zones: Array, filter := Callable(), count := 1) -> Array:
	var options := consume_candidates(source, zones, filter, {"player": player, "exclude_self": true})
	var wanted := mini(count, options.size())
	if wanted <= 0:
		return []
	var picked = await game.choices.pick("card to consume", player, source, options, wanted)
	var cards: Array = picked if picked is Array else [picked]
	for c in cards:
		consume(c)
	return cards


# --- internals -----------------------------------------------------------------------------------------------------------

func _consume_problem(source: Card, player: int, zones: Array, filter: Callable, count: int,
		options: Dictionary) -> String:
	var opts := options.duplicate()
	opts["player"] = player
	var candidates := consume_candidates(source, zones, filter, opts)
	var chosen = options.get("chosen")
	if chosen is Array:
		# The caller supplied the cards: each must be a legal one, no repeats, exactly `count`
		if chosen.size() != count or _has_duplicates(chosen) or not chosen.all(func(c): return c in candidates):
			return "Not the right cards to consume"
		return ""
	return "" if candidates.size() >= count else "Nothing to consume"


func _consume_pay(source: Card, player: int, zones: Array, filter: Callable, count: int,
		options: Dictionary) -> bool:
	var opts := options.duplicate()
	opts["player"] = player
	var candidates := consume_candidates(source, zones, filter, opts)
	var chosen = options.get("chosen")
	if chosen is Callable:
		chosen = await chosen.call(source)
	var cards: Array
	if chosen is Array:
		cards = chosen
	else:
		var picked = await game.choices.pick("card to consume", player, source, candidates, count)
		cards = picked if picked is Array else ([picked] if picked != null else [])
	if cards.size() != count or _has_duplicates(cards) or not cards.all(func(c): return c in candidates):
		return false
	for c in cards:
		consume(c)
	return true


func _has_duplicates(cards: Array) -> bool:
	for i in range(cards.size()):
		if cards.find(cards[i]) != i:
			return true
	return false


func _cost(id: String, label: String, problem_fn: Callable, pay_fn: Callable) -> Dictionary:
	return {"id": id, "label": label, "problem": problem_fn, "pay": pay_fn}
