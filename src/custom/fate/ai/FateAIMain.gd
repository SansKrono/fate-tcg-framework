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
const Doctrine := preload("res://src/custom/fate/ai/FateAIDoctrine.gd")
const WhatIf := preload("res://src/custom/fate/ai/FateAIWhatIf.gd")

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
	var w: Dictionary = state.get("w", Eval.DEFAULT_W)
	var items: Array = []
	var held_names := {}
	for card in state.hand_me:
		var role := Eval.role(game, card)
		match role:
			"reaction":
				var v := Reactions.hold_value(state, profile, card)
				# One copy per name unless the profile holds more (two Hold the Lines are not twice as good)
				if v > 0.0 and held_names.get(card.canonical_name, 0) < profile.max_held_per_name:
					held_names[card.canonical_name] = held_names.get(card.canonical_name, 0) + 1
					items.append({"card": card, "held": true, "value": v})
			"creature", "live":
				if game.can_play_from_hand(card):
					# A pump or removal spell is worth what it gains in the re-planned attack
					if role == "live" and profile.effect_gain_weight > 0.0 and WhatIf.models_spell(card.canonical_name):
						var gain := spell_gain(card, WhatIf.spell(state, profile, card.canonical_name), profile)
						if gain < 0.0:
							continue
						items.append({"card": card, "held": false, "value": gain + 1.0
								+ profile.mana_use_weight * float(card.mana_value()) + Doctrine.bonus(game, me, card, profile)})
						continue
					# A spell with a target is only worth casting when there is a good one
					var extra := AIChoices.cast_worth(game, me, card, w, profile) if role == "live" else 0.0
					if extra < 0.0:
						continue
					var base_value := Eval.hand_value(game, card, w)
					# Worth nothing (a card that only hurts its caster, see FateAIEval.spell_hint): never cast
					if base_value <= 0.0:
						continue
					items.append({"card": card, "held": false,
							"value": base_value + extra + profile.mana_use_weight * float(card.mana_value())
									+ Doctrine.bonus(game, me, card, profile)})
	items.sort_custom(func(a, b): return a.value > b.value)
	# A slip of the player: the best play is overlooked
	if items.size() > 1 and profile.slips():
		items.remove_at(0)
	var limit := mini(MAX_ITEMS, profile.search_items)
	if items.size() > limit:
		items.resize(limit)
	# Only as many creatures and relics as the zones have room for
	var slots := {"creatures": _free_slots(game, me, "creatures"), "relics": _free_slots(game, me, "relics")}
	for item in items:
		item["zone"] = "" if item.held else _slot_zone(item.card)
	var best_mask := 0
	var best_value := 0.0
	var n := items.size()
	for mask in range(1, 1 << n):
		var cards: Array = []
		var value := 0.0
		var used := {"creatures": 0, "relics": 0}
		for i in n:
			if mask & (1 << i):
				cards.append(items[i].card)
				value += items[i].value
				if used.has(items[i].zone):
					used[items[i].zone] += 1
		if used.creatures > slots.creatures or used.relics > slots.relics or value <= best_value:
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
	# Bodies first (a buff, an equipment or an enabler such as Sigil Mage needs them on the table), then relics,
	# then spells; inside a kind pips first and the dearest: keeps the payment of each card simple
	plays.sort_custom(func(a, b):
		var ka := _play_kind(a)
		var kb := _play_kind(b)
		if ka != kb:
			return ka < kb
		var pa: int = str(a.properties.get("Pips", "")).length()
		var pb: int = str(b.properties.get("Pips", "")).length()
		if pa != pb:
			return pa > pb
		return a.mana_value() > b.mana_value())
	return {"plays": plays, "held": held, "reserved": reserved, "value": best_value}


# What a modelled spell (FateAIWhatIf) gains this turn, weighted; -1 when it is not worth casting (a removal spell
# is kept for a creature worth removing, a buff needs creatures that attack because of it). `r` is the result of
# WhatIf.spell.
static func spell_gain(card: Card, r: Dictionary, profile) -> float:
	if r.is_empty():
		return -1.0
	var gain: float = float(r.gain) * profile.effect_gain_weight
	if card.canonical_name == "Smite":
		return gain if gain >= profile.removal_min_target else -1.0
	if gain < profile.ability_margin or int(r.attackers) < profile.pump_min_attackers:
		return -1.0
	return gain


# The zone with limited room a card needs ("creatures", "relics"), or "" (spells replace or leave at once)
static func _slot_zone(card: Card) -> String:
	var type := str(card.properties.get("Type", ""))
	if type == "Creature":
		return "creatures"
	if type == "Relic":
		return "relics"
	return ""


static func _play_kind(card: Card) -> int:
	match str(card.properties.get("Type", "")):
		"Creature":
			return 0
		"Relic":
			return 1
	return 2


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
	var state := Snapshot.for_profile(game, seat, profile)
	# 1. Abilities that make mana: before the cards are cast, so their mana can pay for them
	for entry in Abilities.plan_mana_makers(game, state, profile):
		if not ctrl.alive(token):
			return
		if is_instance_valid(entry.card) and await game.actions.run(entry.card, entry.id):
			ctrl.note("uses %s of %s" % [entry.id, entry.card.canonical_name])
		await ctrl.pause()
	state = Snapshot.for_profile(game, seat, profile)
	# 2. Evolve (Beetle Brawler into Ironside Beetle): the new creature has Charge, so it counts for this turn
	for _i in range(2):
		var evo := Abilities.plan_evolve(game, state, profile, int(state.mana[seat].untapped))
		if evo.is_empty() or float(evo.gain) < profile.ability_margin + 1.0:
			break
		var kw_evo = game.keywords.get_keyword("Evolution")
		var evolved_name: String = evo.card.canonical_name
		var fetched = kw_evo.evolve(evo.card)
		if fetched != null:
			ctrl.note("evolves %s into %s (gain %.1f)" % [evolved_name, fetched.canonical_name, evo.gain])
		await ctrl.pause()
		state = Snapshot.for_profile(game, seat, profile)
		if fetched == null:
			break
	# 3. The cards
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
		# A pump or a removal spell: check again with the creatures that are on the table now, and tell the
		# chooser whom the model meant
		if profile.effect_gain_weight > 0.0 and WhatIf.models_spell(name):
			var fresh := Snapshot.for_profile(game, seat, profile)
			var r := WhatIf.spell(fresh, profile, name)
			if spell_gain(card, r, profile) < 0.0:
				ctrl.note("keeps %s (no gain now)" % name)
				continue
			profile.focus = r.focus
		if game.play_from_hand(card):
			ctrl.note("plays %s" % name)
		else:
			ctrl.problem("could not play %s" % name)
		await ctrl.pause()
		profile.focus = []
	if not ctrl.alive(token):
		return
	state = Snapshot.for_profile(game, seat, profile)
	var spare: int = int(state.mana[seat].untapped) - int(plan.reserved)
	# 4. Abilities that strengthen the whole army for this combat (Devote Paladin, Faithful Worshiper)
	for pump in Abilities.plan_pumps(game, state, profile):
		if not ctrl.alive(token):
			return
		if is_instance_valid(pump.card) and await game.actions.run(pump.card, pump.id):
			ctrl.note("uses %s of %s (gain %.1f)" % [pump.id, pump.card.canonical_name, pump.gain])
		await ctrl.pause()
		state = Snapshot.for_profile(game, seat, profile)
		spare = int(state.mana[seat].untapped) - int(plan.reserved)
	# 5. A creature from the energy zone (Teshra): it must be on the table before the attack is planned
	var flipper = Abilities.plan_flip(game, state, profile, spare)
	if flipper != null:
		if await game.actions.run(flipper, "teshra_flip"):
			ctrl.note("flips a creature out of the energy zone with %s" % flipper.canonical_name)
			spare -= 3
		await ctrl.pause()
		state = Snapshot.for_profile(game, seat, profile)
	# 6. Embody
	var embody := Abilities.plan_embody(game, state, profile, spare)
	if not embody.is_empty():
		var kw = game.keywords.get_keyword("Embody")
		if kw.embody(embody.card, embody.energy):
			ctrl.note("embodies %s under %s" % [embody.energy.canonical_name, embody.card.canonical_name])
			spare -= kw.cost_of(embody.card)
		await ctrl.pause()
		state = Snapshot.for_profile(game, seat, profile)
	# 7. The attack, then who stays home
	var attack := Combat.plan_attack(state, profile)
	if not attack.lethal:
		attack = _hold_engines(game, state, profile, attack)
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
	# 8. Abilities written in card scripts: the ones the AI can value or that are cheap and safe, for creatures that
	# stay home. Several rounds: the scrap of the first is the ingot of the second
	for _round in range(profile.ability_rounds):
		var used := Abilities.plan_generic(game, state, profile, spare, attacking)
		var ran := 0
		for entry in used:
			if not ctrl.alive(token):
				return
			if is_instance_valid(entry.card) and await game.actions.run(entry.card, entry.id):
				ctrl.note("uses %s of %s" % [entry.id, entry.card.canonical_name])
				ran += 1
			await ctrl.pause()
		if ran == 0:
			break
		# New creatures, occupied ones, new counters: look at the table again. The abilities that became usable
		# (the Fabricator once the Ledgerkeeper made scrap) may now be worth more than an attack
		state = Snapshot.for_profile(game, seat, profile)
		spare = int(state.mana[seat].untapped) - int(plan.reserved)
		if not attack.lethal and profile.effect_gain_weight > 0.0:
			attack = _hold_engines(game, state, profile, Combat.plan_attack(state, profile))
			attacks = attack.attacks
			ctrl.attack_plan = attacks
			attacking = {}
			for a in attacks:
				attacking[a.uid] = true
	# 8b. Scrap Cannon: every scrap the engine does not need at the opponent's life, all of it for lethal
	var burn := Abilities.plan_burn(game, state, profile)
	if not burn.is_empty():
		var fired := 0
		for _shot in burn.shots:
			if not ctrl.alive(token) or not is_instance_valid(burn.card):
				return
			if not await game.actions.run(burn.card, "fire"):
				break
			fired += 1
			await ctrl.pause()
		if fired > 0:
			ctrl.note("fires the Scrap Cannon %d times%s" % [fired, " (lethal)" if burn.lethal else ""])
		state = Snapshot.for_profile(game, seat, profile)
	# 9. Who guards
	for uid in state.units:
		var u: Dictionary = state.units[uid]
		if u.ctrl != seat or u.pos != "strike" or attacking.has(uid):
			continue
		if u.kw.has("Cannot block") or not game.can_tilt(u.card):
			continue
		u.card.set_card_rotation(90)


# A creature with a worthwhile occupy ability (an engine piece: it makes scrap, ingots, tokens ...) does not attack
# when what the ability makes is worth more than its share of the attack. Returns the attack plan without it.
static func _hold_engines(game: FateGame, state: Dictionary, profile, attack: Dictionary) -> Dictionary:
	if not profile.ability_use or game.card_effects == null:
		return attack
	var current := attack
	for a in attack.attacks.duplicate():
		var u: Dictionary = state.units.get(a.uid, {})
		if u.is_empty():
			continue
		var worth := Abilities.occupy_value(game, state, profile, u.card)
		if worth <= profile.ability_margin:
			continue
		var s2 := Snapshot.copy_of(state)
		s2.units[a.uid].can_attack = false
		var plan2 := Combat.plan_attack(s2, profile)
		if plan2.score + worth >= current.score:
			current = plan2
			state = s2
	return current


static func _describe(state: Dictionary, a: Dictionary) -> String:
	var u: Dictionary = state.units.get(a.uid, {})
	var who: String = "?" if u.is_empty() else u.name
	if a.kind == "player":
		return "%s -> player" % who
	var t: Dictionary = state.units.get(a.target, {})
	return "%s -> %s" % [who, "?" if t.is_empty() else t.name]
