extends "res://tests/FateCommon.gd"
# The doctrines (FateDoctrines + cards/Fx<Doctrine>.gd): every goal type, persistence of the achieved state
# and the reward of each of the twelve doctrines. Docs: src/custom/fate/FateDoctrines.gd.


func before_each():
	await super.before_each()
	game.doctrines.enabled = true


# Removes the doctrine cards both players start with, so that the test controls which doctrines exist
func clear_doctrines() -> void:
	for card in game.doctrines.doctrine_cards():
		game._delete_table_card(card)
	await get_tree().process_frame


func put_doctrine(pid: int, card_name: String, achieved := false) -> Card:
	var card := game.place_card_on_table(card_name, pid, "doctrines")
	assert_not_null(card, "Test setup: room for the doctrine %s" % card_name)
	await get_tree().process_frame
	if achieved:
		game.doctrines.set_achieved(card, true)
	return card


# A creature definition tagged Ghost
func define_ghost() -> String:
	var def: Dictionary = FateData.CARDS["Moral Captain"].duplicate(true)
	def["Tags"] = ["Ghost"]
	cfc.card_definitions["Test Ghost"] = def
	return "Test Ghost"


# A creature of a domain whose pips text is exactly `pips`
func creature_with_pips(domain: String, pips: String) -> String:
	for n in FateData.CARDS:
		var props: Dictionary = FateData.CARDS[n]
		if props.Type == "Creature" and props.Domain == domain and props.get("Pips", "") == pips:
			return n
	return ""


func fire_phase(pid: int, phase: int) -> void:
	game.phase_begins.emit(pid, phase)
	await get_tree().process_frame


# --- goals ---------------------------------------------------------------------------------------------

func test_goal_lines_are_parsed() -> void:
	var expected := {
		"Subtle Influence": {"kind": "count", "what": "control", "n": 2},
		"Ensue Chaos": {"kind": "devotion", "domain": "Chaos", "n": 5},
		"Convert the Masses": {"kind": "count", "what": "control", "n": 6},
		"Maintain Your Presence": {"kind": "count", "what": "creature", "n": 4},
		"Vanquish Thine Foes": {"kind": "count", "what": "creature", "n": 10},
		"Be a Fierce Presence": {"kind": "power", "n": 4},
		"Channel the Spirit's Will": {"kind": "ghost", "n": 4},
		"Construct the Future": {"kind": "count", "what": "relic", "n": 3},
		"Produce Endlessly": {"kind": "count", "what": "token", "n": 6},
	}
	await clear_doctrines()
	for n in expected:
		var card := await put_doctrine(1, n)
		assert_eq(game.doctrines.goal_of(card), expected[n], n)
		game._delete_table_card(card)
		await get_tree().process_frame


func test_count_creature_goal_by_event_and_persistence() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Maintain Your Presence")
	for _i in range(3):
		await put_creature(1, 1, 1)
	game.doctrines.evaluate()
	assert_false(game.doctrines.achieved(doctrine), "3 creatures are not enough")
	var signals := []
	game.doctrines.doctrine_achieved.connect(func(c, p): signals.append([c, p]))
	# A token entering is an event the manager hears by itself
	game.tokens.create("Soldier Token", 1)
	await get_tree().process_frame
	assert_true(game.doctrines.achieved(doctrine), "the 4th creature achieves it")
	assert_eq(signals, [[doctrine, 1]], "doctrine_achieved")
	# Persists although the creatures die
	for c in game.creatures_in_play(1):
		game.effects.destroy(c)
	await get_tree().process_frame
	game.doctrines.evaluate()
	assert_true(game.doctrines.achieved(doctrine), "achieved stays")
	# Until an effect removes it
	game.doctrines.set_achieved(doctrine, false)
	assert_false(game.doctrines.achieved(doctrine))


func test_marker_follows_the_achieved_state() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Maintain Your Presence")
	game.doctrines.evaluate()
	var dim: Color = doctrine.modulate
	game.doctrines.set_achieved(doctrine, true)
	assert_ne(doctrine.modulate, dim, "the card looks different when achieved")
	assert_eq(doctrine.modulate, game.doctrines.TINT_ACHIEVED)


func test_devotion_goal_counts_pips_of_the_domain() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Defend the Innocent")
	var two := creature_with_pips("Order", "OO")
	var one := creature_with_pips("Order", "O")
	assert_ne(two, "")
	assert_ne(one, "")
	await put_creature(1, two)
	await put_creature(1, two)
	game.doctrines.evaluate()
	assert_eq(game.doctrines.devotion(1, "Order"), 4)
	assert_false(game.doctrines.achieved(doctrine))
	# The opponent's cards and other domains do not count
	await put_creature(2, one)
	game.doctrines.evaluate()
	assert_false(game.doctrines.achieved(doctrine))
	await put_creature(1, one)
	game.doctrines.evaluate()
	assert_eq(game.doctrines.devotion(1, "Order"), 5)
	assert_true(game.doctrines.achieved(doctrine))


func test_control_goal_counts_cards_controlled_but_not_owned() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Subtle Influence")
	var a := await put_creature(2, 1, 1)
	var b := await put_creature(2, 1, 1)
	game.control.take_control(a, 1)
	await get_tree().process_frame
	assert_false(game.doctrines.achieved(doctrine), "one stolen card")
	game.control.take_control(b, 1)
	await get_tree().process_frame
	assert_true(game.doctrines.achieved(doctrine), "two stolen cards")


func test_relic_and_token_goals() -> void:
	await clear_doctrines()
	var future := await put_doctrine(1, "Construct the Future")
	var endless := await put_doctrine(1, "Produce Endlessly")
	for _i in range(3):
		await put_on_table(1, "Rusty Pendant" if FateData.CARDS.has("Rusty Pendant") else _any_relic(), "relics")
	game.doctrines.evaluate()
	assert_true(game.doctrines.achieved(future), "3 relics")
	game.tokens.set_counter(1, "scrap", 5)
	assert_false(game.doctrines.achieved(endless), "5 tokens")
	game.tokens.set_counter(1, "ingot", 1)
	assert_true(game.doctrines.achieved(endless), "6 counters")


func _any_relic() -> String:
	for n in FateData.CARDS:
		if FateData.CARDS[n].Type == "Relic":
			return n
	return ""


func test_power_goal() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Be a Fierce Presence")
	await put_creature(1, 3, 3)
	game.doctrines.evaluate()
	assert_false(game.doctrines.achieved(doctrine))
	await put_creature(1, 1, 4)
	game.doctrines.evaluate()
	assert_true(game.doctrines.achieved(doctrine), "a Guard of 4 counts")


func test_ghost_count_goal() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Channel the Spirit's Will")
	var ghost := define_ghost()
	for _i in range(3):
		await put_creature(1, ghost)
	game.doctrines.evaluate()
	assert_false(game.doctrines.achieved(doctrine))
	await put_creature(1, ghost)
	game.doctrines.evaluate()
	assert_true(game.doctrines.achieved(doctrine))


# --- rewards: turn triggers ---------------------------------------------------------------------------------

func test_rewards_are_inactive_until_achieved() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Maintain Your Presence")
	await put_doctrine(1, "Construct the Future")
	await fire_phase(1, FateGame.Phase.MAINTENANCE)
	assert_eq(game.tokens.token_count(1), 0)


func test_maintain_your_presence_creates_a_soldier_on_your_turn() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Maintain Your Presence", true)
	await fire_phase(2, FateGame.Phase.MAINTENANCE)
	assert_eq(game.creatures_in_play(1).size(), 0, "not on the opponent's turn")
	await fire_phase(1, FateGame.Phase.MAINTENANCE)
	assert_eq(game.creatures_in_play(1).size(), 1)
	assert_eq(game.creatures_in_play(1)[0].canonical_name, "Soldier Token")


func test_construct_the_future_creates_scrap() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Construct the Future", true)
	await fire_phase(1, FateGame.Phase.MAINTENANCE)
	assert_eq(game.tokens.counter(1, "scrap"), 1)
	await fire_phase(2, FateGame.Phase.MAINTENANCE)
	assert_eq(game.tokens.counter(1, "scrap"), 1)


func test_convert_the_masses_takes_the_weakest_creature() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Convert the Masses", true)
	var strong := await put_creature(2, 3, 3)
	var weak := await put_creature(2, 1, 1)
	await fire_phase(1, FateGame.Phase.MAINTENANCE)
	assert_eq(weak.controller_id, 1, "the weakest changed sides")
	assert_eq(strong.controller_id, 2)
	# Every turn: also at the beginning of the opponent's
	await fire_phase(2, FateGame.Phase.MAINTENANCE)
	assert_eq(strong.controller_id, 1)


# --- rewards: static effects ---------------------------------------------------------------------------------------

func test_defend_the_innocent_buffs_your_creatures() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Defend the Innocent")
	var mine := await put_creature(1, 2, 2)
	var theirs := await put_creature(2, 2, 2)
	assert_eq(game.stats.current(mine, "Strike"), 2)
	game.doctrines.set_achieved(doctrine, true)
	assert_eq(game.stats.current(mine, "Strike"), 3)
	assert_eq(game.stats.current(mine, "Guard"), 3)
	assert_eq(game.stats.current(theirs, "Strike"), 2, "not the opponent's")
	game.doctrines.set_achieved(doctrine, false)
	assert_eq(game.stats.current(mine, "Guard"), 2)


func test_wilds_and_progress_grant_charge_and_productive() -> void:
	await clear_doctrines()
	var wilds := await put_doctrine(1, "Devote Yourself to the Wilds")
	var progress := await put_doctrine(1, "Devote Yourself to Progress")
	var mine := await put_creature(1, 2, 2)
	var theirs := await put_creature(2, 2, 2)
	assert_false(game.keywords.has(mine, "Charge"))
	assert_false(game.keywords.has(mine, "Productive"))
	game.doctrines.set_achieved(wilds, true)
	game.doctrines.set_achieved(progress, true)
	assert_true(game.keywords.has(mine, "Charge"))
	assert_true(game.keywords.has(mine, "Productive"))
	assert_false(game.keywords.has(theirs, "Charge"), "not the opponent's")
	# A creature that entered this turn may attack and occupy
	mine.entered_turn = game.turn_number
	start_combat()
	assert_eq(game.combat.attack_problem(mine), "")


func test_produce_endlessly_adds_one_token_per_creation() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Produce Endlessly", true)
	game.tokens.add(1, "scrap", 1)
	assert_eq(game.tokens.counter(1, "scrap"), 2)
	game.tokens.create("Soldier Token", 1)
	assert_eq(game.creatures_in_play(1).size(), 2)
	game.tokens.create_many("Soldier Token", 2, 1)
	assert_eq(game.creatures_in_play(2).size(), 1, "only your own creations")


func test_subtle_influence_grants_a_flip_cast_each_turn() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Subtle Influence")
	var key: String = "doctrine:Subtle Influence"
	assert_false(game.casting.can_flip_cast(1))
	game.doctrines.set_achieved(doctrine, true)
	assert_eq(game.casting.permission_uses(1, key), 1)
	game.casting.use_permission(1, key)
	assert_eq(game.casting.permission_uses(1, key), 0)
	game.turn_started.emit(1, 5)
	assert_eq(game.casting.permission_uses(1, key), 1, "renewed every turn")
	game.doctrines.set_achieved(doctrine, false)
	assert_false(game.casting.can_flip_cast(1))


# --- rewards: energy phase and combat ----------------------------------------------------------------------

func test_ensue_chaos_takes_the_top_card_of_the_opponents_deck() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(1, "Ensue Chaos")
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	assert_false(game.doctrines.can_take_opponent_card(1), "not before it is achieved")
	game.doctrines.set_achieved(doctrine, true)
	assert_true(game.doctrines.can_take_opponent_card(1))
	var deck_before: int = FateZones.container("deck", 2).get_all_cards().size()
	var top: Card = game.library.look_top(2, 1)[0]
	var taken: Card = game.doctrines.take_opponent_card_as_energy(1)
	await get_tree().process_frame
	assert_eq(taken, top)
	assert_eq(FateZones.container("deck", 2).get_all_cards().size(), deck_before - 1)
	assert_eq(FateZones.zone_of(top), "energy")
	assert_eq(top.controller_id, 1)
	assert_eq(top.owner_id, 2)
	assert_eq(game.energy_choice, FateGame.CHOICE_ENERGY, "it was the choice of the phase")
	assert_eq(game.phase, FateGame.Phase.MAIN)
	assert_false(game.doctrines.can_take_opponent_card(1), "once per energy phase")


func test_vanquish_thine_foes_destroys_creatures_that_interact_with_the_attack() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Vanquish Thine Foes", true)
	var attacker := await put_creature(1, 2, 2)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, 2))
	game.combat.confirm_attackers()
	assert_true(game.combat.declare_block(blocker, game.combat.attack_of(attacker)))
	run_combat()
	await get_tree().process_frame
	assert_false(FateZones.is_creature_in_play(blocker), "the blocker was destroyed")
	assert_true(FateZones.is_creature_in_play(attacker))
	assert_eq(game.stats.current(attacker, "Strike"), 2, "and dealt no damage")


func test_vanquish_thine_foes_destroys_the_attacked_creature() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Vanquish Thine Foes", true)
	var attacker := await put_creature(1, 1, 1)
	var target := await put_creature(2, 5, 5)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, target))
	run_combat()
	await get_tree().process_frame
	assert_false(FateZones.is_creature_in_play(target))
	assert_true(FateZones.is_creature_in_play(attacker))


func test_be_a_fierce_presence_lets_the_highest_strike_creature_guard_upright() -> void:
	await clear_doctrines()
	var doctrine := await put_doctrine(2, "Be a Fierce Presence")
	var attacker := await put_creature(1, 1, 1)
	var best := await put_creature(2, 3, 1)
	var other := await put_creature(2, 2, 2)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, 2))
	game.combat.confirm_attackers()
	var attack: FateAttack = game.combat.attack_of(attacker)
	assert_ne(game.combat.block_problem(best, attack), "", "not before it is achieved")
	game.doctrines.set_achieved(doctrine, true)
	assert_eq(game.combat.block_problem(best, attack), "", "the highest Strike may guard upright")
	assert_ne(game.combat.block_problem(other, attack), "", "the others cannot")
	assert_true(game.combat.declare_block(best, attack))
	run_combat()
	await get_tree().process_frame
	assert_eq(attacker.get_parent() != null, true)


func test_channel_the_spirits_will_keeps_a_creature_and_hurts_its_controller() -> void:
	await clear_doctrines()
	await put_doctrine(1, "Channel the Spirit's Will", true)
	var attacker := await put_creature(1, 1, 3)
	var blocker := await put_creature(2, 1, 5, {}, true)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, 2))
	game.combat.confirm_attackers()
	assert_true(game.combat.declare_block(blocker, game.combat.attack_of(attacker)))
	run_combat()
	await get_tree().process_frame
	# The attacker loses all its Strike (it would die) but stays; its controller takes 3
	assert_true(FateZones.is_creature_in_play(attacker), "the creature stays")
	assert_eq(game.player(1).life, LIFE - 3, "its controller takes 3 damage instead")
	assert_eq(game.player(2).life, LIFE, "the other player is not hurt")


# --- board states -------------------------------------------------------------------------------------------------------

func test_achieved_state_survives_a_board_state_round_trip() -> void:
	await clear_doctrines()
	var done := await put_doctrine(1, "Defend the Innocent", true)
	await put_doctrine(1, "Maintain Your Presence")
	assert_true(game.doctrines.achieved(done))
	var state := capture_board()
	assert_not_null(state, "the table can be captured: %s" % str(game.board_state_errors))
	await load_board(state)
	var doctrines: Array = game.doctrines.doctrine_cards(1)
	assert_eq(doctrines.size(), 2)
	for card in doctrines:
		assert_eq(game.doctrines.achieved(card), card.canonical_name == "Defend the Innocent", card.canonical_name)
	var mine := await put_creature(1, 2, 2)
	assert_eq(game.stats.current(mine, "Strike"), 3, "the reward is active after the load")
