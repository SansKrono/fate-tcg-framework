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


func _init(owner_game: FateGame) -> void:
	game = owner_game


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


# Chooses the energy cards that would pay for a card (D4). Returns
# {"ok": bool, "cards": Array of energy cards to tap}. Nothing is tapped.
#
# 1. Pips first, each with energy of its own domain.
# 2. The generic cost with whatever is left, one mana at a time, always from the domain
#    that is most spare once the other cards still in the player's hand are accounted for
#    (domains the hand still needs pips of are kept as long as possible). Ties go to the
#    order of DOMAINS, then to slot order.
func plan_payment(card: Card) -> Dictionary:
	var pid: int = card.owner_id
	var cost := cost_of(card)
	var by_domain := {}
	for d in DOMAINS:
		by_domain[d] = []
	for energy in untapped_energy(pid):
		var d := energy_domain(energy)
		if by_domain.has(d):
			by_domain[d].append(energy)
	var chosen := []
	for d in cost.pips:
		if not by_domain.has(d) or by_domain[d].size() < cost.pips[d]:
			return {"ok": false, "cards": []}
		for _i in range(cost.pips[d]):
			chosen.append(by_domain[d].pop_front())
	var left := 0
	for d in by_domain:
		left += by_domain[d].size()
	if left < cost.generic:
		return {"ok": false, "cards": []}
	var demand := _hand_demand(pid, card)
	for _i in range(cost.generic):
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
	return {"ok": true, "cards": chosen}


func can_pay(card: Card) -> bool:
	return plan_payment(card).ok


# Pays for a card: taps the chosen energy cards. Returns false (and taps nothing) if the
# card cannot be paid for.
func pay(card: Card) -> bool:
	var plan := plan_payment(card)
	if not plan.ok:
		return false
	for energy in plan.cards:
		energy.set_card_rotation(90)
	game.mana_changed.emit(card.owner_id)
	return true


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
	return amount <= 0 or not plan_generic(player_id, amount, avoid, slot_order).is_empty()


# Taps energy for `amount` generic mana. Returns false (and taps nothing) if it cannot be paid.
func pay_generic(player_id: int, amount: int, avoid: Array = [], slot_order := false) -> bool:
	if amount <= 0:
		return true
	var plan := plan_generic(player_id, amount, avoid, slot_order)
	if plan.is_empty():
		return false
	for energy in plan:
		energy.set_card_rotation(90)
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
