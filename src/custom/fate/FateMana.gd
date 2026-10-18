# Mana and cost payment. Rules: docs/FATE_RULES_SPEC.md, Section 2 and decision D4.
# Design document: Section 7 (SYS-ENERGY).
#
# Each untapped energy card in a player's energy zone is 1 mana of one of its domains. A
# card costs its generic `Cost` plus its `Pips`: one mana of that domain per pip letter
# (I, C, O, P, see FateGame.DOMAIN_BY_INITIAL). Generic cost can be paid with any domain.
# Paying taps (rotates 90 degrees) the chosen energy cards through the framework.
#
# Owned by FateGame (`game.mana`); FateGame has thin wrappers (`mana_pool`, `can_pay`, `pay`).
class_name FateMana
extends RefCounted

# The order in which domains win ties when choosing what to spend, so that payment is
# deterministic
const DOMAINS := ["Innovation", "Chaos", "Order", "Primal"]

var game: FateGame
# player id -> Array of cost reductions {"amount", "filter", "expiry", "source"}, see add_cost_reduction
var _reductions := {}
# player id -> {domain: amount} of floating mana, see add_floating
var _floating := {}


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.end_of_turn_expiry.connect(_on_end_of_turn_expiry)


# The domain an energy card gives. A dual-domain card gives only its first domain: choosing
# between the two is not implemented (D4 says a picker UI is a later task).
func energy_domain(card: Card) -> String:
	var domains: Array = card.properties.get("_domains", [])
	return domains[0] if not domains.is_empty() else ""


# The untapped energy cards of a player, in slot order
func untapped_energy(player_id: int) -> Array:
	var found := []
	for card in game.player(player_id).cards_in_grid("energy"):
		if card.card_rotation == 0:
			found.append(card)
	return found


# The mana available to a player, as a dictionary domain -> amount (untapped energy only)
func mana_pool(player_id: int) -> Dictionary:
	var pool := {}
	for d in DOMAINS:
		pool[d] = 0
	for card in untapped_energy(player_id):
		var d := energy_domain(card)
		if pool.has(d):
			pool[d] += 1
	var floating: Dictionary = _floating.get(player_id, {})
	for d in floating:
		if pool.has(d):
			pool[d] += floating[d]
	return pool


# What a card costs: {"generic": int, "pips": {domain: count}}
func cost_of(card: Card) -> Dictionary:
	return {
		"generic": int(card.properties.get("Cost", 0)),
		"pips": pips_of(str(card.properties.get("Pips", ""))),
	}


# Parses a pip string ("IIC") into {domain: count}
func pips_of(pips: String) -> Dictionary:
	var counted := {}
	for letter in pips:
		var d: String = FateGame.DOMAIN_BY_INITIAL.get(letter, "")
		if d != "":
			counted[d] = counted.get(d, 0) + 1
	return counted


# Chooses what would pay for a card (D4). Returns
# {"ok": bool, "cards": Array of energy cards to tap, "ingots": int}. Nothing is tapped or spent.
#
# 1. Pips first, each with energy of its own domain.
# 2. The generic cost with whatever is left, one mana at a time, always from the domain
#    that is most spare once the other cards still in the player's hand are accounted for
#    (domains the hand still needs pips of are kept as long as possible). Ties go to the
#    order of DOMAINS, then to slot order.
# 3. Only what the untapped energy cannot cover is paid with ingot counters (FateTokens): an ingot is 1
#    mana of any colour, so it pays a pip of any domain or 1 generic. "ingots" is how many are spent.
func plan_payment(card: Card) -> Dictionary:
	var pid: int = card.owner_id
	var cost := effective_cost(card)
	# Floating mana is spent first (it is gone at the end of the turn): pips with its own domain, generic with any
	var floating: Dictionary = floating_of(pid)
	var used_floating := {}
	var pips := {}
	for d in cost.pips:
		var use := mini(int(floating.get(d, 0)), cost.pips[d])
		_take_floating(floating, used_floating, d, use)
		pips[d] = cost.pips[d] - use
	var generic: int = cost.generic
	for d in DOMAINS:
		var use := mini(int(floating.get(d, 0)), generic)
		_take_floating(floating, used_floating, d, use)
		generic -= use
	var by_domain := {}
	for d in DOMAINS:
		by_domain[d] = []
	for energy in untapped_energy(pid):
		var d := energy_domain(energy)
		if by_domain.has(d):
			by_domain[d].append(energy)
	var chosen := []
	var ingots := 0
	for d in pips:
		var own: Array = by_domain.get(d, [])
		var take := mini(own.size(), pips[d])
		for _i in range(take):
			chosen.append(own.pop_front())
		ingots += pips[d] - take
	var left := 0
	for d in by_domain:
		left += by_domain[d].size()
	ingots += maxi(0, generic - left)
	if ingots > ingots_available(pid):
		return {"ok": false, "cards": [], "ingots": 0, "floating": {}}
	var demand := _hand_demand(pid, card)
	for _i in range(generic - maxi(0, generic - left)):
		var best := ""
		var best_spare := 0
		for d in DOMAINS:
			if by_domain[d].is_empty():
				continue
			var spare: int = by_domain[d].size() - demand.get(d, 0)
			if best == "" or spare > best_spare:
				best = d
				best_spare = spare
		chosen.append(by_domain[best].pop_front())
	return {"ok": true, "cards": chosen, "ingots": ingots, "floating": used_floating}


func can_pay(card: Card) -> bool:
	return plan_payment(card).ok


# Pays for a card: taps the chosen energy cards (and spends the ingots the plan needs). Returns false (and
# taps nothing) if the card cannot be paid for.
func pay(card: Card) -> bool:
	var plan := plan_payment(card)
	if not plan.ok:
		return false
	for energy in plan.cards:
		energy.set_card_rotation(90)
	_spend_ingots(card.owner_id, plan.ingots)
	_spend_floating(card.owner_id, plan.floating)
	_use_cost_reductions(card)
	game.mana_changed.emit(card.owner_id)
	return true


# How many ingot counters a player can spend as mana
func ingots_available(player_id: int) -> int:
	return game.tokens.ingot_mana(player_id) if game.tokens != null else 0


func _spend_ingots(player_id: int, amount: int) -> void:
	if amount > 0:
		game.tokens.spend(player_id, game.tokens.MANA_COUNTER, amount)


# Plans paying `amount` generic mana (no domain pips), for abilities such as "Pay 3". Returns the
# untapped energy cards to tap, or an empty array if it cannot be paid. Cards in `avoid` are only
# used if the others cannot cover the amount. By default each mana comes from the domain with the
# most untapped energy left (ties: DOMAINS order, then slot order); `slot_order` takes cards in slot
# order instead.
func plan_generic(player_id: int, amount: int, avoid: Array = [], slot_order := false) -> Array:
	var pool := []
	var spare := []
	for energy in untapped_energy(player_id):
		if energy in avoid:
			spare.append(energy)
		else:
			pool.append(energy)
	var chosen := []
	if slot_order:
		chosen = pool.slice(0, amount)
	else:
		var by_domain := {}
		for energy in pool:
			var d := energy_domain(energy)
			if not by_domain.has(d):
				by_domain[d] = []
			by_domain[d].append(energy)
		for _i in range(amount):
			var best := ""
			for d in DOMAINS:
				if by_domain.has(d) and not by_domain[d].is_empty() \
						and (best == "" or by_domain[d].size() > by_domain[best].size()):
					best = d
			if best == "":
				break
			chosen.append(by_domain[best].pop_front())
	for energy in spare:
		if chosen.size() >= amount:
			break
		chosen.append(energy)
	return chosen if chosen.size() >= amount else []


func can_pay_generic(player_id: int, amount: int, avoid: Array = [], slot_order := false) -> bool:
	return amount <= 0 or plan_generic_payment(player_id, amount, avoid, slot_order).ok


# Like plan_generic, but ingot counters make up what the untapped energy cannot cover (the energy is
# all used first). Returns {"ok": bool, "cards": Array of energy cards, "ingots": int}.
func plan_generic_payment(player_id: int, amount: int, avoid: Array = [], slot_order := false) -> Dictionary:
	if amount <= 0:
		return {"ok": true, "cards": [], "ingots": 0, "floating": {}}
	# Floating mana first, then the energy, then ingots
	var floating: Dictionary = floating_of(player_id)
	var used_floating := {}
	var rest := amount
	for d in DOMAINS:
		var use := mini(int(floating.get(d, 0)), rest)
		_take_floating(floating, used_floating, d, use)
		rest -= use
	if rest <= 0:
		return {"ok": true, "cards": [], "ingots": 0, "floating": used_floating}
	var cards := plan_generic(player_id, rest, avoid, slot_order)
	if not cards.is_empty():
		return {"ok": true, "cards": cards, "ingots": 0, "floating": used_floating}
	var all := plan_generic(player_id, untapped_energy(player_id).size(), avoid, slot_order)
	var short := rest - all.size()
	if short > ingots_available(player_id):
		return {"ok": false, "cards": [], "ingots": 0, "floating": {}}
	return {"ok": true, "cards": all, "ingots": short, "floating": used_floating}


# Taps energy (and spends ingots if the energy is not enough) for `amount` generic mana. Returns false (and
# taps nothing) if it cannot be paid.
func pay_generic(player_id: int, amount: int, avoid: Array = [], slot_order := false) -> bool:
	if amount <= 0:
		return true
	var plan := plan_generic_payment(player_id, amount, avoid, slot_order)
	if not plan.ok:
		return false
	for energy in plan.cards:
		energy.set_card_rotation(90)
	_spend_ingots(player_id, plan.ingots)
	_spend_floating(player_id, plan.floating)
	game.mana_changed.emit(player_id)
	return true


# How many pips of each domain the other cards in the player's hand need
func _hand_demand(player_id: int, except: Card) -> Dictionary:
	var demand := {}
	var hand := game.player(player_id).hand()
	if not hand:
		return demand
	for other in hand.get_all_cards():
		if other == except:
			continue
		var pips := pips_of(str(other.properties.get("Pips", "")))
		for d in pips:
			demand[d] = demand.get(d, 0) + pips[d]
	return demand


# --- floating mana (Ancient Tree: "produce 1 Primal energy") ----------------------------------------------------
# Mana that does not come from an energy card: added by an effect, spent before the energy cards by every
# payment (cards, "Pay N" abilities), gone at the end of the turn. A pip of a domain takes floating mana of that
# domain, generic mana takes any.

# Adds `amount` floating mana of a domain ("Primal") for a player
func add_floating(player_id: int, domain: String, amount := 1) -> void:
	if amount <= 0 or not domain in DOMAINS:
		return
	var pool: Dictionary = _floating.get(player_id, {})
	pool[domain] = int(pool.get(domain, 0)) + amount
	_floating[player_id] = pool
	game.mana_changed.emit(player_id)


# The floating mana of a player as {domain: amount} (a copy, only domains above 0)
func floating_of(player_id: int) -> Dictionary:
	var copy := {}
	var pool: Dictionary = _floating.get(player_id, {})
	for d in pool:
		if pool[d] > 0:
			copy[d] = pool[d]
	return copy


func floating_total(player_id: int) -> int:
	var total := 0
	for amount in floating_of(player_id).values():
		total += amount
	return total


# Empties the floating mana (of one player, or everybody)
func clear_floating(player_id := 0) -> void:
	var ids := [player_id] if player_id != 0 else _floating.keys()
	for pid in ids:
		if _floating.erase(pid):
			game.mana_changed.emit(pid)


func _take_floating(pool: Dictionary, used: Dictionary, domain: String, amount: int) -> void:
	if amount <= 0:
		return
	pool[domain] = int(pool.get(domain, 0)) - amount
	used[domain] = int(used.get(domain, 0)) + amount


func _spend_floating(player_id: int, used: Dictionary) -> void:
	var pool: Dictionary = _floating.get(player_id, {})
	for d in used:
		pool[d] = maxi(0, int(pool.get(d, 0)) - int(used[d]))


# --- cost reductions (Meek Minion: "reduce the cost of the next creature you play by 2") --------------------------
# A one-shot alteration of what a card costs. It applies to the player's NEXT card that passes `filter`, lowers
# the GENERIC part of the cost (never below 0; the pips of the card stay), and is used up when that card is paid
# for (`pay`, so a flip cast or a cast from the discard pile counts as playing it). `filter` is
# Callable(card) -> bool (empty: any card), `expiry` "" (until used) or "end_of_turn". `source` is only a label.
# Returns the reduction record; cancel it with remove_cost_reduction.

func add_cost_reduction(player_id: int, amount: int, filter := Callable(), expiry := "", source = null) -> Dictionary:
	var reduction := {"amount": amount, "filter": filter, "expiry": expiry, "source": source}
	if not _reductions.has(player_id):
		_reductions[player_id] = []
	_reductions[player_id].append(reduction)
	game.mana_changed.emit(player_id)
	return reduction


func remove_cost_reduction(player_id: int, reduction: Dictionary) -> void:
	if _reductions.has(player_id):
		_reductions[player_id].erase(reduction)
		game.mana_changed.emit(player_id)


# The reductions that would apply to this card now (the player is the card's owner)
func cost_reductions_for(card: Card) -> Array:
	var found := []
	for reduction in _reductions.get(card.owner_id, []):
		if not reduction.filter.is_valid() or reduction.filter.call(card):
			found.append(reduction)
	return found


# What the card costs its owner now: cost_of() minus the generic reductions that apply
func effective_cost(card: Card) -> Dictionary:
	var cost := cost_of(card)
	for reduction in cost_reductions_for(card):
		cost.generic = maxi(0, cost.generic - int(reduction.amount))
	return cost


func _use_cost_reductions(card: Card) -> void:
	var applied := cost_reductions_for(card)
	if applied.is_empty():
		return
	for reduction in applied:
		_reductions[card.owner_id].erase(reduction)


func _on_end_of_turn_expiry(_player_id: int) -> void:
	clear_floating()
	for pid in _reductions:
		_reductions[pid] = _reductions[pid].filter(func(r): return r.expiry != "end_of_turn")
