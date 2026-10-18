extends "res://tests/FateCommon.gd"
# The AI's combat simulator (FateAISim) must give the same result as the real combat (FateCombat).
# Random boards, random attacks and blocks are played in the engine and in the simulator; life, who
# survives and the stats of the survivors must match. If this fails after a rules change, change the
# simulator (src/custom/fate/ai/FateAISim.gd) to match.

const Sim := preload("res://src/custom/fate/ai/FateAISim.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Combat := preload("res://src/custom/fate/ai/FateAICombat.gd")

const SCENARIOS := 40
# How many blocks were declared and creatures destroyed over all scenarios (the test must exercise them)
var _blocks := 0
var _deaths := 0
const KEYWORD_SETS := [{}, {}, {}, {"Indomitable": 1}, {"Savage": 1}, {"Savage": 2}, {"Unblockable": 1}]


func test_the_simulator_matches_the_engine() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260418
	game.turn.end_phase_waits_for_player = true
	for n in SCENARIOS:
		var mismatch := await _scenario(rng, n)
		assert_eq(mismatch, "", "scenario %d" % n)
		if mismatch != "":
			return
	assert_gt(_blocks, 15, "the scenarios include blocks")
	assert_gt(_deaths, 15, "the scenarios include destroyed creatures")


# Plays one random combat in the engine and in the simulator. Returns "" or a description of the
# difference.
func _scenario(rng: RandomNumberGenerator, n: int) -> String:
	await game.reset_table()
	var atk_id := game.active_id
	var def_id := FateZones.opponent_of(atk_id)
	game.player(atk_id).life = 10
	game.player(def_id).life = 10
	var attackers: Array = []
	for _i in rng.randi_range(1, 3):
		attackers.append(await put_creature(atk_id, rng.randi_range(0, 5), rng.randi_range(0, 5),
				KEYWORD_SETS[rng.randi() % KEYWORD_SETS.size()]))
	var defenders: Array = []
	for _i in rng.randi_range(1, 4):
		var tilt := rng.randi_range(0, 2)
		defenders.append(await put_creature(def_id, rng.randi_range(0, 5), rng.randi_range(0, 5),
				KEYWORD_SETS[rng.randi() % KEYWORD_SETS.size()], tilt == 1, "occupied" if tilt == 2 else "creatures"))
	# The energy choice is made without drawing: 40 scenarios would empty the decks, and an empty deck
	# loses the game (FateLibrary), which ends the combat test early
	if game.phase == FateGame.Phase.ENERGY:
		game.energy_choice = FateGame.CHOICE_DRAW
		game.advance_phase()
	game.advance_phase()
	if game.phase != FateGame.Phase.COMBAT_DECLARE:
		return "setup: not in the declare step (%s)" % FateTurn.phase_name(game.phase)
	var combat: FateCombat = game.combat
	var cards: Array = []
	cards.append_array(attackers)
	cards.append_array(defenders)
	for a in attackers:
		var target = def_id
		if rng.randf() < 0.4:
			target = defenders[rng.randi() % defenders.size()]
		combat.declare_attack(a, target)
	combat.confirm_attackers()
	var plan := {}
	if game.phase == FateGame.Phase.COMBAT_INTERCEPT:
		var taken := {}
		for i in combat.attacks.size():
			var attack: FateAttack = combat.attacks[i]
			for b in combat.eligible_blockers(attack):
				if not taken.has(b) and rng.randf() < 0.5:
					taken[b] = true
					combat.declare_block(b, attack)
					_blocks += 1
		# The simulator's view before the blocks are confirmed
		plan = _simulate(def_id)
		combat.confirm_blocks()
	else:
		plan = _simulate(def_id)
	# What the engine did
	var seen := ""
	for c in cards:
		var in_play := FateZones.is_creature_in_play(c)
		if not in_play:
			_deaths += 1
		var u: Dictionary = plan.state.units.get(c.get_instance_id(), {})
		var o = plan.result.units.get(c.get_instance_id())
		var sim_alive: bool = o == null or not o.dead
		if in_play != sim_alive:
			seen += "%s alive: engine %s, sim %s; " % [c.canonical_name, in_play, sim_alive]
			continue
		if in_play:
			var ss: int = u.strike if o == null else o.strike
			var sg: int = u.guard if o == null else o.guard
			var es := game.stats.current(c, "Strike")
			var eg := game.stats.current(c, "Guard")
			if ss != es or sg != eg:
				seen += "%s stats: engine %d/%d, sim %d/%d; " % [c.canonical_name, es, eg, ss, sg]
	for pid in [atk_id, def_id]:
		if game.player(pid).life != plan.result.life[pid]:
			seen += "life P%d: engine %d, sim %d; " % [pid, game.player(pid).life, plan.result.life[pid]]
	if seen != "":
		seen = "[%s] %s" % [_describe(plan.state, plan.attacks, plan.blocks), seen]
	game.end_turn()
	return seen


# The snapshot of the table now (from the defender's side), the engine's attacks and blocks in the
# simulator's words, and the simulated result
func _simulate(def_id: int) -> Dictionary:
	var state := Snapshot.build(game, def_id)
	var info := Combat.sim_attacks(game)
	var blocks := {}
	var engine: Array = game.combat.attacks
	for i in engine.size():
		var group: Array = []
		for b in engine[i].blockers:
			group.append(b.get_instance_id())
		if not group.is_empty():
			blocks[i] = group
	# Savage is dealt by the engine when the blocks are confirmed, so it is still to come here
	for a in info.attacks:
		a.savage_done = false
	return {"state": state, "attacks": info.attacks, "blocks": blocks,
			"result": Sim.run(state, info.attacks, blocks)}


func _describe(state: Dictionary, attacks: Array, blocks: Dictionary) -> String:
	var parts: Array = []
	for u in state.units.values():
		parts.append("%s P%d %s %d/%d %s" % [u.name, u.ctrl, u.pos, u.strike, u.guard, str(u.kw)])
	return "%s | attacks %s | blocks %s" % [", ".join(parts), str(attacks.map(func(a): return "%d->%s%d" % [a.uid, a.kind, a.target])), str(blocks)]
