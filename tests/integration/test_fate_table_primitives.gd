extends "res://tests/FateCommon.gd"
# The low-level table primitives of the board state loader (FateGame.place_card_at,
# place_in_container, reset_table; FateCardTemplate.apply_zone_look).

const CREATURE := "Battle Smith"
const RELIC := "Moral Captain"
const WORLD := "Equal Footing"


func _names(cards: Array) -> Array:
	return cards.map(func(c): return c.canonical_name)


func _live_cards() -> int:
	return get_tree().get_nodes_in_group("cards").filter(
			func(c): return is_instance_valid(c) and not c.is_queued_for_deletion()).size()


# --- place_card_at -------------------------------------------------------------------------------

func test_place_at_slot_index_with_gaps():
	var a := game.place_card_at(CREATURE, 1, "creatures", 3)
	var b := game.place_card_at(CREATURE, 1, "creatures", 1)
	assert_not_null(a)
	assert_not_null(b)
	var grid := FateZones.grid("creatures", 1)
	assert_eq(grid.get_slot(3).occupying_card, a)
	assert_eq(grid.get_slot(1).occupying_card, b)
	assert_null(grid.get_slot(0).occupying_card)
	assert_eq(a.owner_id, 1)
	assert_eq(a.entered_turn, 0)
	assert_eq(a.state, Card.CardState.ON_PLAY_BOARD)
	assert_eq(FateZones.zone_of(a), "creatures")
	# -1 takes the first free slot, which is the gap at 0
	var c := game.place_card_at(CREATURE, 1, "creatures")
	assert_eq(grid.get_slot(0).occupying_card, c)


func test_place_refuses_occupied_slot_out_of_range_and_unknown_card():
	assert_not_null(game.place_card_at(CREATURE, 1, "creatures", 2))
	assert_null(game.place_card_at(CREATURE, 1, "creatures", 2), "Occupied")
	assert_null(game.place_card_at(CREATURE, 1, "creatures", 6), "Six creature slots")
	assert_not_null(game.place_card_at(CREATURE, 1, "relics", 4), "The relic zone grows: no limit")
	assert_null(game.place_card_at("No such card", 1, "creatures", 0))
	assert_null(game.place_card_at(CREATURE, 1, "hand", 0), "Not a grid")
	assert_eq(FateZones.grid("creatures", 1).get_slot_count(), 6, "Nothing grew")


func test_place_card_on_table_is_the_first_free_slot_wrapper():
	for _i in range(6):
		assert_not_null(game.place_card_on_table(CREATURE, 2, "creatures"))
	assert_null(game.place_card_on_table(CREATURE, 2, "creatures"), "Full")


func test_energy_grid_grows_to_the_slot_index():
	var grid := FateZones.grid("energy", 1)
	var before := grid.get_slot_count()
	assert_eq(before, FateLayout.ENERGY_START_SLOTS)
	var card := game.place_card_at(RELIC, 1, "energy", 8)
	assert_not_null(card)
	assert_eq(grid.get_slot_count(), 9)
	assert_eq(grid.get_slot(8).occupying_card, card)
	assert_null(game.place_card_at(RELIC, 1, "energy", 8), "Occupied")
	assert_eq(grid.get_slot_count(), 9)
	# -1 fills the gaps first
	var gap := game.place_card_at(RELIC, 1, "energy")
	assert_eq(grid.get_slot(0).occupying_card, gap)


func test_world_zone_is_shared_and_ignores_the_player():
	var world := game.place_card_at(WORLD, 1, "world", 0)
	assert_not_null(world)
	assert_eq(FateZones.zone_of(world), "world")
	assert_null(game.place_card_at(CREATURE, 1, "world", 0), "One shared slot, taken")
	assert_null(game.place_card_at(CREATURE, 2, "world", 0))


# --- apply_zone_look -------------------------------------------------------------------------------

func test_zone_look_defaults():
	var energy := game.place_card_at(RELIC, 1, "energy")
	energy.apply_zone_look("energy")
	assert_true(energy.is_energy)
	assert_false(energy.is_faceup)
	assert_eq(energy.card_rotation, 0)
	var occupied := game.place_card_at(CREATURE, 1, "occupied")
	occupied.apply_zone_look("occupied")
	assert_false(occupied.is_energy)
	assert_true(occupied.is_faceup)
	assert_eq(occupied.card_rotation, 90)
	var plain := game.place_card_at(CREATURE, 1, "creatures")
	plain.apply_zone_look("creatures")
	assert_true(plain.is_faceup)
	assert_eq(plain.card_rotation, 0)


func test_zone_look_overrides():
	var energy := game.place_card_at(RELIC, 1, "energy")
	energy.apply_zone_look("energy", "up", true)
	assert_true(energy.is_energy)
	assert_true(energy.is_faceup)
	assert_eq(energy.card_rotation, 90)
	var creature := game.place_card_at(CREATURE, 1, "creatures")
	creature.apply_zone_look("creatures", "down", true)
	assert_false(creature.is_faceup)
	assert_eq(creature.card_rotation, 90)
	creature.apply_zone_look("occupied", "", false)
	assert_true(creature.is_faceup)
	assert_eq(creature.card_rotation, 0)


# --- place_in_container ----------------------------------------------------------------------------

func test_ordered_fill_of_hand_and_piles_keeps_the_call_order():
	await empty_hand(1)
	var names := ["Battle Smith", "Moral Captain", "Primal Wraith"]
	for zone in ["hand", "discard", "removed", "deck"]:
		var before: int = FateZones.container(zone, 1).get_all_cards().size()
		for n in names:
			assert_not_null(await game.place_in_container(n, 1, zone))
		var cards: Array = FateZones.container(zone, 1).get_all_cards()
		assert_eq(cards.size(), before + 3, zone)
		assert_eq(_names(cards.slice(before)), names, "%s: call order, top = last" % zone)
		for c in cards.slice(before):
			assert_eq(c.owner_id, 1)
	var top: Card = FateZones.container("discard", 1).get_top_card()
	assert_eq(top.canonical_name, "Primal Wraith")
	assert_eq(game.player(1).deck().get_top_card().canonical_name, "Primal Wraith")


func test_place_in_container_of_player_two_and_refusals():
	var card := await game.place_in_container(CREATURE, 2, "discard")
	assert_eq(card.get_parent(), FateZones.container("discard", 2))
	assert_eq(card.owner_id, 2)
	assert_null(await game.place_in_container("No such card", 1, "hand"))
	assert_null(await game.place_in_container(CREATURE, 1, "creatures"))


func test_place_in_container_is_fast_in_tests():
	var start := Time.get_ticks_msec()
	for _i in range(10):
		await game.place_in_container(CREATURE, 2, "removed")
	assert_lt(Time.get_ticks_msec() - start, 1500, "No fixed waits under cfc.is_testing")


# --- reset_table -----------------------------------------------------------------------------------

func test_reset_table_leaves_nothing_and_frees_the_slots():
	for pid in [1, 2]:
		await game.place_in_container(CREATURE, pid, "hand")
		await game.place_in_container(CREATURE, pid, "discard")
		await game.place_in_container(CREATURE, pid, "removed")
		for zone in ["creatures", "occupied", "relics", "doctrines"]:
			game.place_card_at(CREATURE if zone != "relics" else RELIC, pid, zone, 0)
		game.place_card_at(RELIC, pid, "energy", 9)
	var host := game.place_card_at(CREATURE, 1, "creatures", 4)
	game.place_card_at(WORLD, 1, "world", 0)
	game.stats.apply_damage(host, "Guard", 1)
	game.is_over = true
	game.winner_id = 2
	var turn_before := game.turn_number
	var active_before := game.active_id
	var phase_before := game.phase
	var life_before := game.player(1).life
	await game.reset_table()
	assert_eq(_live_cards(), 0, "No Card nodes left")
	for pid in [1, 2]:
		for zone in ["hand", "deck", "discard", "removed"]:
			assert_eq(FateZones.container(zone, pid).get_all_cards().size(), 0, zone)
		for zone in FateZones.GRIDS:
			var grid := FateZones.grid(zone, pid)
			assert_eq(grid.count_available_slots(), grid.get_slot_count(), zone)
			assert_eq(game.player(pid).cards_in_grid(zone).size(), 0, zone)
		assert_eq(FateZones.grid("energy", pid).get_slot_count(), FateLayout.ENERGY_START_SLOTS)
		assert_eq(total_mana(game.mana_pool(pid)), 0)
	var world := FateZones.grid("world", 0)
	assert_eq(world.count_available_slots(), world.get_slot_count())
	assert_false(game.is_over)
	assert_eq(game.winner_id, 0)
	assert_eq(game.energy_choice, "")
	assert_eq(game.turn_number, turn_before)
	assert_eq(game.active_id, active_before)
	assert_eq(game.phase, phase_before)
	assert_eq(game.player(1).life, life_before)
	# The table is usable again
	assert_not_null(game.place_card_at(CREATURE, 1, "creatures", 0))
	assert_not_null(await game.place_in_container(CREATURE, 1, "hand"))


func test_reset_table_cancels_a_combat_in_progress():
	var attacker := await put_creature(1, 2, 2)
	await start_combat()
	game.combat.declare_attack(attacker, game.player(2))
	assert_eq(game.combat.attacks.size(), 1)
	await game.reset_table()
	assert_eq(game.combat.step, FateCombat.Step.IDLE)
	assert_eq(game.combat.attacks.size(), 0)
	assert_null(game.combat_ui.selected)
	assert_eq(_live_cards(), 0)


# A creature that moved to a new slot just before the seats swapped (an occupied creature returning to the
# creature zone in the maintenance step, while the hotseat curtain delays the swap) must end up on its slot
# in the new layout, not on the old slot position (it appeared in the other player's half of the table)
func test_a_card_moving_while_the_seats_swap_ends_on_its_slot():
	var creature := await put_creature(1, "Moral Captain", 1, {}, false, "occupied")
	var slot := game.player(1).grid("creatures").find_available_slot()
	creature.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	board.apply_seats(2)
	await wait_seconds(1.0)
	var expected: Vector2 = slot.global_position - board.global_position
	assert_lt(creature.position.distance_to(expected), 1.0, "On its slot after the swap")


# Redirecting the slide of a card at a seat swap must not stop the tween that tilts it: a guarding creature
# stayed upright on screen although it was in the guard position
func test_a_card_tilting_while_the_seats_swap_ends_tilted():
	var creature := await put_creature(1, "Moral Captain")
	creature.set_card_rotation(90)
	board.apply_seats(2)
	await wait_seconds(1.0)
	assert_eq(creature.card_rotation, 90)
	assert_almost_eq(float(creature.get_node("Control").rotation_degrees), 90.0, 1.0, "Drawn tilted")
