# The MAIN phase of the Fate AI: what to cast, what to keep mana for, which creatures defend and which
# attack.
#
# Order of a main phase (see run()):
#   1. Pick the plays. Every card of the hand is worth something (FateAIEval.hand_value; "dead" cards
#      are worth nothing and are never cast: the engine would only take their mana). A subset search
#      finds the set of cards worth the most that the mana can pay for (pips per domain, then generic),
#      where a reaction spell in the subset means "keep mana for it" (FateAIReactions.hold_value).
#   2. Play them, then use abilities worth their mana (FateAIAbilities).
#   3. Plan the attack (FateAICombat.plan_attack). That decides who attacks, so
#   4. every creature that does NOT attack is tilted to guard: attackers stay upright afterwards and
#      cannot intercept, only guarding or occupied creatures can (docs/FATE_RULES_SPEC.md D5, D6).
# The controller then moves on to the declare step and declares the planned attacks.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")
const Reactions := preload("res://src/custom/fate/ai/FateAIReactions.gd")
const Abilities := preload("res://src/custom/fate/ai/FateAIAbilities.gd")
const Sim := preload("res://src/custom/fate/ai/FateAISim.gd")
const AIChoices := preload("res://src/custom/fate/ai/FateAIChoices.gd")

# The subset search looks at this many cards at most (2^12 subsets)
const MAX_ITEMS := 12


# --- the plays ---------------------------------------------------------------------------------------

# Can this set of cards be paid for together from the pool {domain: untapped energy}? Pips need energy
# of their domain; the generic part takes anything that is left.
static func affordable(game: FateGame, pool: Dictionary, cards: Array) -> bool:
	var need := {}
	var generic := 0
	var pips_total := 0
	for c in cards:
		var cost: Dictionary = game.mana.cost_of(c)
		generic += cost.generic
		for d in cost.pips:
			need[d] = need.get(d, 0) + cost.pips[d]
			pips_total += cost.pips[d]
	var total := 0
	for d in pool:
		total += pool[d]
	for d in need:
		if pool.get(d, 0) < need[d]:
			return false
	return pips_total + generic <= total


# Plans the plays of the main phase. Returns
#   {"plays": Array of Cards in the order to play them, "held": Array of reaction Cards the mana is kept
#    for, "reserved": int mana kept back, "value": float}
static func plan_plays(game: FateGame, state: Dictionary, profile) -> Dictionary:
	var me: int = state.me
	var pool: Dictionary = state.mana[me].pool
	var items: Array = []
	for card in state.hand_me:
		var role := Eval.role(game, card)
		match role:
			"reaction":
				var v := Reactions.hold_value(state, profile, card)
				if v > 0.0:
					items.append({"card": card, "held": true, "value": v})
			"creature", "live":
				if game.can_play_from_hand(card):
					# A spell with a target is only worth casting when there is a good one
					var extra := AIChoices.cast_worth(game, me, card) if role == "live" else 0.0
					if extra < 0.0:
						continue
					items.append({"card": card, "held": false,
							"value": Eval.hand_value(game, card) + extra + 0.03 * float(card.mana_value())})
	items.sort_custom(func(a, b): return a.value > b.value)
	if items.size() > MAX_ITEMS:
		items.resize(MAX_ITEMS)
	var creature_slots := _free_slots(game, me, "creatures")
	var best_mask := 0
	var best_value := 0.0
	var n := items.size()
	for mask in range(1, 1 << n):
		var cards: Array = []
		var value := 0.0
		var creatures := 0
		for i in n:
			if mask & (1 << i):
				cards.append(items[i].card)
				value += items[i].value
				if items[i].card.properties.get("Type") == "Creature" and not items[i].held:
					creatures += 1
		if creatures > creature_slots or value <= best_value:
			continue
		if affordable(game, pool, cards):
			best_value = value
			best_mask = mask
	var plays: Array = []
	var held: Array = []
	var reserved := 0
	for i in n:
		if best_mask & (1 << i):
			if items[i].held:
				held.append(items[i].card)
				reserved += items[i].card.mana_value()
			else:
				plays.append(items[i].card)
	# Pips first, then the dearest: keeps the payment of each card simple
	plays.sort_custom(func(a, b):
		var pa: int = str(a.properties.get("Pips", "")).length()
		var pb: int = str(b.properties.get("Pips", "")).length()
		if pa != pb:
			return pa > pb
		return a.mana_value() > b.mana_value())
	return {"plays": plays, "held": held, "reserved": reserved, "value": best_value}


static func _free_slots(game: FateGame, pid: int, zone: String) -> int:
	var grid := game.player(pid).grid(zone)
	if grid == null:
		return 0
	var free := 0
	for slot in grid.get_all_slots():
		if slot.occupying_card == null:
			free += 1
	return free


# --- the whole phase ---------------------------------------------------------------------------------

# Runs the main phase for a FateAIController `ctrl` (it provides game, seat, profile, pause(), alive(),
# note(), problem()). Leaves the game in the MAIN phase with the creatures placed; the controller
# declares the attack in `ctrl.attack_plan` next.
static func run(ctrl, token: int) -> void:
	var game: FateGame = ctrl.game
	var seat: int = ctrl.seat
	var profile = ctrl.profile
	var state := Snapshot.build(game, seat, profile.aggression, profile.cheat)
	var plan := plan_plays(game, state, profile)
	ctrl.note("main: %d plays, %d held (%s)" % [plan.plays.size(), plan.held.size(),
			", ".join(plan.plays.map(func(c): return c.canonical_name))])
	for card in plan.plays:
		if not ctrl.alive(token):
			return
		if not is_instance_valid(card) or not game.can_play_from_hand(card):
			continue
		var name: String = card.canonical_name
		# An earlier play may have filled the zone (a creature that creates tokens when it enters)
		var zone: String = card.board_zone() if card is FateCardTemplate else ""
		if zone != "" and zone != "world" and _free_slots(game, seat, zone) == 0:
			ctrl.note("no room in the %s zone for %s" % [zone, name])
			continue
		if game.play_from_hand(card):
			ctrl.note("plays %s" % name)
		else:
			ctrl.problem("could not play %s" % name)
		await ctrl.pause()
	if not ctrl.alive(token):
		return
	# Abilities that are worth their mana
	state = Snapshot.build(game, seat, profile.aggression, profile.cheat)
	var spare: int = int(state.mana[seat].untapped) - int(plan.reserved)
	var embody := Abilities.plan_embody(game, state, profile, spare)
	if not embody.is_empty():
		var kw = game.keywords.get_keyword("Embody")
		if kw.embody(embody.card, embody.energy):
			ctrl.note("embodies %s under %s" % [embody.energy.canonical_name, embody.card.canonical_name])
			spare -= kw.cost_of(embody.card)
		await ctrl.pause()
		state = Snapshot.build(game, seat, profile.aggression, profile.cheat)
	# The attack, then who stays home
	var attack := Combat.plan_attack(state, profile)
	var attacks: Array = attack.attacks
	if not attack.lethal:
		for f in Abilities.plan_force_blocks(game, state, attacks, profile, spare):
			var kwf = game.keywords.get_keyword("Forced blocker")
			if kwf.force_block(f.card, f.target):
				spare -= Abilities.FORCE_BLOCK_COST
				ctrl.note("forces %s to be the only blocker of %s" % [f.target.canonical_name, f.card.canonical_name])
	ctrl.attack_plan = attacks
	ctrl.note("attack plan: %s (score %.1f)" % [str(attacks.map(func(a): return _describe(state, a))), attack.score])
	var attacking := {}
	for a in attacks:
		attacking[a.uid] = true
	# Abilities written in card scripts: the ones that are cheap and safe, for creatures that stay home
	var used := Abilities.plan_generic(game, state, profile, spare, attacking)
	for entry in used:
		if not ctrl.alive(token):
			return
		if is_instance_valid(entry.card) and await game.actions.run(entry.card, entry.id):
			ctrl.note("uses %s of %s" % [entry.id, entry.card.canonical_name])
		await ctrl.pause()
	if not used.is_empty():
		# New creatures, occupied ones: look at the table again before choosing who guards
		state = Snapshot.build(game, seat, profile.aggression, profile.cheat)
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		if u.ctrl != seat or u.pos != "strike" or attacking.has(uid):
			continue
		if u.kw.has("Cannot block") or not game.can_tilt(u.card):
			continue
		u.card.set_card_rotation(90)


static func _describe(state: Dictionary, a: Dictionary) -> String:
	var u: Dictionary = state.units.get(a.uid, {})
	var who: String = "?" if u.is_empty() else u.name
	if a.kind == "player":
		return "%s -> player" % who
	var t: Dictionary = state.units.get(a.target, {})
	return "%s -> %s" % [who, "?" if t.is_empty() else t.name]
