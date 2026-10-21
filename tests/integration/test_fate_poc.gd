extends "res://tests/FateCommon.gd"
# Tests of the Fate proof of concept: zones, decks, card stats, ownership and the
# basic two-player turn flow. See docs/FATE_TCG_DESIGN.md, "Implementation status".
# The setup and the helpers (find_in_hand, put_energy, ...) are in tests/FateCommon.gd;
# the turn phases and mana payment have their own tests in test_fate_turn.gd.


# --- data ------------------------------------------------------------------

func test_card_data_is_complete():
	assert_eq(FateData.CARDS.size(), 83, "All catalog cards are defined")
	assert_eq(FateData.DOCTRINES.size(), 12, "All doctrines are defined")
	for card_name in FateData.CARDS:
		var props: Dictionary = FateData.CARDS[card_name]
		assert_true(props.get("Type") in ["Creature", "Relic", "Spell"], card_name + " has a card type")
		assert_true(props.get("Domain") in ["Innovation", "Chaos", "Order", "Primal"], card_name + " has a domain")
		assert_true(props.has("Cost") and props.has("Pips") and props.has("Abilities"), card_name + " has cost, pips and text")
		if props.Type == "Creature":
			assert_true(props.has("Strike") and props.has("Guard"), card_name + " has strike and guard")
		if props.Type == "Spell":
			assert_true(props.get("_spell_kind") in ["Regular", "Reaction", "Field", "World"], card_name + " has a spell kind")
		assert_true(cfc.card_definitions.has(card_name), card_name + " is registered with the framework")


func test_deck_rules():
	for pid in game.players:
		var names := []
		for c in FateZones.container("deck", pid).get_all_cards():
			names.append(c.canonical_name)
		for c in FateZones.container("hand", pid).get_all_cards():
			names.append(c.canonical_name)
		assert_eq(names.size(), FateDecks.DECK_SIZE, "Player %d has a 40 card deck" % pid)
		var counts := {}
		for n in names:
			counts[n] = counts.get(n, 0) + 1
		for n in counts:
			assert_true(counts[n] <= FateDecks.copy_limit(n), "%s within its copy limit" % n)
			assert_true(cfc.card_definitions[n].Domain in game.player(pid).domains, "%s matches the player's domains" % n)


# --- zones -----------------------------------------------------------------

func test_zones_exist_for_both_players():
	for pid in [1, 2]:
		for zone in ["deck", "discard", "removed", "hand"]:
			assert_not_null(FateZones.container(zone, pid), "%s of player %d exists" % [zone, pid])
		for zone in FateZones.GRIDS:
			assert_not_null(FateZones.grid(zone, pid), "%s grid of player %d exists" % [zone, pid])
	assert_not_null(FateZones.grid("world", 0), "The shared world spell grid exists")
	assert_eq(FateZones.grid("creatures", 1).get_slot_count(), 6)
	assert_eq(FateZones.grid("relics", 2).get_slot_count(), 3)
	assert_true(FateZones.grid("relics", 2).auto_extend, "The relic zone grows: no limit on relics")
	assert_eq(FateZones.grid("field", 1).get_slot_count(), 1)
	assert_eq(FateZones.grid("world", 0).get_slot_count(), 1)
	assert_true(FateZones.grid("energy", 1).auto_extend, "The energy zone grows")


func test_players_are_on_opposite_halves():
	var p1: Vector2 = FateZones.grid("creatures", 1).global_position
	var p2: Vector2 = FateZones.grid("creatures", 2).global_position
	# The table rows mirror around the midline (FateLayout.TABLE_MIDLINE)
	assert_gt(p1.y, FateLayout.TABLE_MIDLINE, "Player 1 creatures are on the bottom half")
	assert_lt(p2.y, FateLayout.TABLE_MIDLINE, "Player 2 creatures are on the top half")
	assert_gt(FateZones.container("hand", 1).global_position.y, FateLayout.TABLE_MIDLINE)


func test_starting_hands_and_doctrines():
	for pid in [1, 2]:
		# Turn 1 has a draw phase too (decision D1), so the first player holds one more card
		var drawn := 1 if pid == game.active_id and not FateGame.FIRST_PLAYER_SKIPS_FIRST_DRAW else 0
		var expected := FateGame.STARTING_HAND + drawn
		assert_eq(FateZones.container("hand", pid).get_card_count(), expected, "Player %d starts with 7 cards (+ the draw of turn 1)" % pid)
		assert_eq(FateZones.container("deck", pid).get_card_count(), FateDecks.DECK_SIZE - expected)
		assert_eq(game.player(pid).cards_in_grid("doctrines").size(), 3, "Player %d has 3 doctrines" % pid)
		assert_eq(game.player(pid).life, FatePlayer.STARTING_LIFE)


func test_card_ownership():
	for pid in [1, 2]:
		for c in FateZones.container("hand", pid).get_all_cards():
			assert_eq(c.owner_id, pid)
			assert_eq(c.controller_id, pid)
		for c in FateZones.container("deck", pid).get_all_cards():
			assert_eq(c.owner_id, pid)


# --- card stats ------------------------------------------------------------

func test_creature_stats_on_card():
	var c: Card = cfc.instance_card("Steelwork Salvager")
	board.add_child(c)
	await wait_seconds(0.3)
	assert_eq(c.get_property("Strike"), 2)
	assert_eq(c.get_property("Guard"), 1)
	assert_eq(c.get_property("Cost"), 2)
	assert_eq(c.card_front.card_labels["Strike"].text, "2", "Strike label")
	assert_eq(c.card_front.card_labels["Guard"].text, "1", "Guard label")
	assert_eq(c.card_front.card_labels["Cost"].text, "2", "Cost label")
	assert_eq(c.card_front.card_labels["Pips"].text, "II", "Domain pips label")
	assert_eq(c.card_front.card_labels["Domain"].text, "Innovation")
	assert_eq(c.card_front.card_labels["Tags"].text, "Goblin - Engineer")
	assert_true(c.card_front.card_labels["Strike"].visible)
	assert_eq(c.mana_value(), 4, "Mana value is generic cost plus pips")
	c.queue_free()


func test_relics_and_spells_have_no_combat_stats():
	var relic: Card = cfc.instance_card("Garbage Heap")
	var spell: Card = cfc.instance_card("Rapid Scavenging")
	board.add_child(relic)
	board.add_child(spell)
	await wait_seconds(0.3)
	assert_false(relic.card_front.card_labels["Strike"].visible, "Relic hides strike")
	assert_false(spell.card_front.card_labels["Guard"].visible, "Spell hides guard")
	assert_false(relic.properties.has("Strike"))
	assert_eq(spell.properties.get("_spell_kind"), "Regular")
	relic.queue_free()
	spell.queue_free()


# --- table behaviour -----------------------------------------------------------

# Playing a card needs the owner's main phase and enough mana (test_fate_turn.gd has the
# rules); these tests are about where the cards land, so they provide both
func _ready_to_play(pid: int) -> void:
	await fill_mana(pid, 5)
	game.draw_extra_card()
	assert_eq(game.phase, FateGame.Phase.MAIN)


func test_creature_goes_to_its_owners_creature_zone():
	await _ready_to_play(1)
	var creature := find_in_hand(1, func(c): return c.properties.Type == "Creature")
	assert_not_null(creature, "Player 1 has a creature in hand")
	creature.move_to(board)
	await wait_seconds(0.6)
	assert_eq(creature.get_parent(), board, "Creature is on the table")
	assert_eq(creature._placement_slot.get_grid_name(), "Creatures P1", "In the creature zone of its owner")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 1)


func test_relic_goes_to_relic_zone_and_instant_spell_to_discard():
	await _ready_to_play(1)
	# An empty hand leaves room for the cards below (the hand limit is 10)
	await empty_hand(1)
	# Fixed cards: the starting hand is random, and a reaction spell is not playable in the main
	# phase (rules spec D8), so picking "any spell" from it would make this test depend on the shuffle
	var relic: Card = await put_in_hand(1, "Holy Amulet")
	var spell: Card = await put_in_hand(1, "Smite")
	# Smite needs a target (cards/FxSmite.gd)
	await put_creature(2, 1, 1)
	relic.move_to(board)
	await wait_seconds(0.6)
	assert_eq(relic._placement_slot.get_grid_name(), "Relics P1")
	spell.move_to(board)
	await wait_seconds(0.6)
	assert_eq(spell.get_parent(), FateZones.container("discard", 1), "A regular spell resolves into the discard pile")
	var reaction: Card = await put_in_hand(1, "Hold the Line")
	reaction.move_to(board)
	await wait_seconds(0.4)
	assert_eq(reaction.get_parent(), FateZones.container("hand", 1), "A reaction spell stays in hand in the main phase")


func test_cannot_play_the_opponents_cards():
	await fill_mana(2)
	game.draw_extra_card()
	var theirs := find_in_hand(2, func(c): return c.properties.Type == "Creature")
	assert_not_null(theirs)
	theirs.move_to(board)
	await wait_seconds(0.5)
	assert_eq(theirs.get_parent(), FateZones.container("hand", 2), "Player 2 cannot play on player 1's turn")


# --- energy and turns ------------------------------------------------------

func test_play_as_energy_once_per_turn():
	# Turn 1 starts in the energy phase. The once-per-turn rule is now the phase rule: the
	# choice ends the phase, so no second energy card can be played
	assert_eq(game.phase, FateGame.Phase.ENERGY)
	var a := find_in_hand(1, func(c): return true)
	assert_true(game.can_play_as_energy(a))
	assert_true(game.play_as_energy(a), "First energy play succeeds")
	await wait_seconds(0.6)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 1, "The card is in the energy zone")
	assert_false(a.is_faceup, "Energy is face-down")
	assert_eq(total_mana(game.mana_pool(1)), 1, "One energy card gives one mana")
	assert_eq(game.phase, FateGame.Phase.MAIN, "The energy play ended the energy phase")
	var b := find_in_hand(1, func(c): return c != a)
	assert_false(game.can_play_as_energy(b), "Only one energy play per turn")
	assert_false(game.play_as_energy(b))
	assert_eq(game.player(1).cards_in_grid("energy").size(), 1)


func test_end_turn_switches_player_and_draws():
	var p2_hand: int = FateZones.container("hand", 2).get_card_count()
	var first := find_in_hand(1, func(c): return true)
	game.play_as_energy(first)
	await wait_seconds(0.4)
	game.end_turn()
	await wait_seconds(0.6)
	assert_eq(game.active_id, 2)
	assert_eq(game.turn_number, 2)
	assert_eq(FateZones.container("hand", 2).get_card_count(), p2_hand + 1, "The new active player draws a card in the draw phase")
	assert_eq(game.phase, FateGame.Phase.ENERGY, "The turn waits for the energy choice")
	assert_eq(game.energy_choice, "", "Player 2 may play energy")
	var second := find_in_hand(2, func(c): return true)
	assert_true(game.can_play_as_energy(second))
	assert_false(game.can_play_as_energy(find_in_hand(1, func(c): return true)), "Player 1 is no longer active")
	game.end_turn()
	await wait_seconds(0.4)
	assert_eq(game.active_id, 1)
	assert_eq(game.energy_choice, "", "The energy choice is available again")


func test_window_content_scales_to_the_design_size():
	var window := get_tree().root
	assert_eq(window.content_scale_size, Vector2i(1280, 720), "Content is scaled from the design size")
	assert_eq(window.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_KEEP)
	# Leaving the table puts the previous scaling back
	var before: Dictionary = board._previous_scaling
	main.queue_free()
	await wait_seconds(0.3)
	assert_eq(window.content_scale_mode, before.mode, "The previous scale mode is restored")
	assert_eq(window.content_scale_size, before.size, "The previous scale size is restored")


func test_slot_highlight_matches_the_slot():
	for grid_name in ["creatures", "relics", "energy", "doctrines", "field"]:
		var slot: BoardPlacementSlot = FateZones.grid(grid_name, 1).get_slot(0)
		var expected: Vector2 = CFConst.CARD_SIZE * FateLayout.zone_scale(grid_name)
		assert_eq(slot.custom_minimum_size, expected, "%s slot is sized for table cards" % grid_name)
		slot.set_highlight(true)
		await get_tree().process_frame
		await get_tree().process_frame
		var highlight: Control = slot.get_node("Highlight")
		assert_almost_eq(highlight.size, expected, Vector2(1, 1), "%s highlight has the slot size" % grid_name)
		assert_almost_eq(highlight.global_position, slot.global_position, Vector2(1, 1),
				"%s highlight sits on the slot" % grid_name)
		var shape: RectangleShape2D = slot.get_node("Area2D/CollisionShape2D").shape
		assert_eq(shape.size, expected, "%s slot collision matches the slot" % grid_name)
		slot.set_highlight(false)
