extends "res://tests/FateCommon.gd"
# The table layout and presentation (FateLayout, FateHand seats, the table card face, the playable
# glow, the HUD panels). The rules behind them are tested elsewhere.

const Phase := FateGame.Phase


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# Every zone, pile, plate and panel of the HUD, with its rect on screen
func _layout_rects() -> Array:
	var rects := []
	for grid in get_tree().get_nodes_in_group("placement_grid"):
		rects.append([grid.name, grid.get_global_rect()])
	for child in board.get_children():
		if child is Control and child.name.ends_with("Wrapper") and not child.name.begins_with("Hand"):
			rects.append([child.name, child.get_global_rect()])
	for node_name in ["StatusBar", "ActionPanel", "CardDetailFrame", "DebugButton"]:
		rects.append([node_name, board.get_node(node_name).get_global_rect()])
	for pid in board.combat_ui.avatars:
		var plate: Control = board.combat_ui.avatars[pid]
		rects.append([plate.name, plate.get_global_rect()])
	rects.append(["CombatLogPanel", board.combat_ui.log_panel.get_global_rect()])
	return rects


func test_every_part_of_the_table_is_on_screen_and_apart():
	await _settle()
	var rects := _layout_rects()
	var screen := Rect2(Vector2.ZERO, FateLayout.SCREEN)
	for i in rects.size():
		assert_true(screen.encloses(rects[i][1]), "%s is on screen: %s" % [rects[i][0], rects[i][1]])
		for j in range(i + 1, rects.size()):
			assert_false(rects[i][1].intersects(rects[j][1]),
					"%s must not overlap %s" % [rects[i][0], rects[j][0]])


func test_the_active_player_sits_at_the_bottom():
	await _settle()
	assert_eq(board.bottom_id, 1)
	assert_gt(FateZones.grid("creatures", 1).global_position.y, FateLayout.TABLE_MIDLINE)
	assert_lt(FateZones.grid("creatures", 2).global_position.y, FateLayout.TABLE_MIDLINE)
	go_to_main()
	game.end_turn()
	await _settle()
	assert_eq(game.active_id, 2)
	assert_eq(board.bottom_id, 2, "The seats swap with the turn")
	assert_gt(FateZones.grid("creatures", 2).global_position.y, FateLayout.TABLE_MIDLINE)
	assert_lt(FateZones.grid("creatures", 1).global_position.y, FateLayout.TABLE_MIDLINE)
	assert_eq(board.combat_ui.avatars[2].position, FateLayout.plate_rect("bottom").position)
	assert_eq(board.combat_ui.avatars[1].position, FateLayout.plate_rect("top").position)


func test_cards_on_the_table_follow_their_slot_when_the_seats_swap():
	var creature := await put_creature(1, 2, 2)
	await wait_seconds(0.4)
	go_to_main()
	game.end_turn()
	await _settle()
	var slot: BoardPlacementSlot = creature._placement_slot
	assert_almost_eq(creature.global_position, slot.global_position, Vector2(1, 1))
	assert_lt(creature.global_position.y, FateLayout.TABLE_MIDLINE, "Player 1 is at the top now")


func test_the_opponent_hand_is_small_and_face_down():
	await wait_seconds(0.3)
	var top_hand = FateZones.container("hand", 2)
	var bottom_hand = FateZones.container("hand", 1)
	assert_true(top_hand.concealed)
	assert_false(bottom_hand.concealed)
	assert_almost_eq(top_hand.scale.x, FateLayout.TOP_HAND_SCALE, 0.001)
	assert_gt(top_hand.get_card_count(), 0)
	for card in top_hand.get_all_cards():
		assert_false(card.is_faceup, "%s is face-down" % card.canonical_name)
		assert_eq(card.get_node("Control").mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for card in bottom_hand.get_all_cards():
		assert_true(card.is_faceup)
	go_to_main()
	game.end_turn()
	await wait_seconds(0.3)
	assert_false(top_hand.concealed, "Player 2's hand is at the bottom now")
	for card in top_hand.get_all_cards():
		assert_true(card.is_faceup)
	assert_true(bottom_hand.concealed)


func test_a_card_drawn_into_the_concealed_hand_stays_face_down():
	var card = game.player(2).draw_card()
	await wait_seconds(0.6)
	assert_eq(card.get_parent(), FateZones.container("hand", 2))
	assert_false(card.is_faceup)


func test_the_top_hand_is_revealed_while_its_player_may_react():
	game.reactions.hold_windows = true
	await empty_hand(2)
	var reaction = await put_in_hand(2, "Hold the Line")
	await fill_mana(2, 2)
	var attacker := await put_creature(1, 2, 2)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, 2))
	game.combat.confirm_attackers()
	await wait_seconds(0.3)
	assert_true(game.reactions.window_open_for(2), "Test setup: player 2 may react")
	assert_false(FateZones.container("hand", 2).concealed)
	assert_true(reaction.is_faceup)
	assert_string_contains(board.prompt_label.text, "Player 2 may react")
	game.request_next_phase()
	await wait_seconds(0.3)
	assert_false(game.reactions.window_open_for(2))
	assert_true(FateZones.container("hand", 2).concealed, "Hidden again once the window closes")


func test_table_cards_show_their_compact_face():
	var creature := await put_creature(1, 3, 2)
	await wait_seconds(0.4)
	assert_true(creature.card_front.table_mode)
	assert_false(creature.card_front.get_node("Margin").visible)
	var in_hand = await put_in_hand(1, "Battle Smith")
	assert_false(in_hand.card_front.table_mode)
	creature.move_to(FateZones.container("hand", 1), -1, null, ["Scripted"])
	await wait_seconds(0.6)
	assert_false(creature.card_front.table_mode, "Back in the hand: the full card")


func test_table_face_follows_the_stats():
	var creature := await put_creature(1, 3, 2)
	await wait_seconds(0.4)
	creature.modify_property("Strike", 5, false, ["Scripted"])
	await _settle()
	assert_eq(creature.card_front._table_strike.text, "5")


func test_cards_take_the_scale_of_their_zone():
	var creature := await put_creature(1, 2, 2)
	var energy := await put_energy(1, "Beetle Brawler")
	await wait_seconds(0.5)
	assert_almost_eq(creature.scale.x, FateLayout.zone_scale("creatures"), 0.01)
	assert_almost_eq(energy.scale.x, FateLayout.zone_scale("energy"), 0.01)


func test_playable_cards_in_hand_glow():
	# Energy phase: every card of player 1's hand can be played as energy, player 2 plays nothing
	board._refresh_hud()
	for card in FateZones.container("hand", 1).get_all_cards():
		assert_true(card.playable and card.fx.glowing,
				"%s glows" % card.canonical_name)
	for card in FateZones.container("hand", 2).get_all_cards():
		assert_false(card.playable and card.fx.glowing)
	go_to_main()
	board._refresh_hud()
	for card in FateZones.container("hand", 1).get_all_cards():
		assert_eq(card.playable and card.fx.glowing,
				game.can_play_from_hand(card), "%s glows only if it can be paid" % card.canonical_name)


func test_the_action_button_follows_the_phase():
	assert_true(board.draw_button.visible)
	assert_false(board.next_button.visible, "Energy phase: one big button, Draw extra card")
	go_to_main()
	assert_false(board.draw_button.visible)
	assert_true(board.next_button.visible)
	assert_eq(board.next_button.text, "To combat")
	assert_eq(board.phase_strip.current, Phase.MAIN)


func test_plates_show_mana_and_the_active_player():
	await put_energy(1, "Beetle Brawler")
	game.mana_changed.emit(1)
	var plate: FatePlayerAvatar = board.combat_ui.avatars[1]
	assert_eq(plate.mana_text(), "Pri 1")
	assert_true(plate.is_active_player)
	assert_false(board.combat_ui.avatars[2].is_active_player)


func test_the_debug_button_opens_and_closes_the_debug_tools():
	var button: Button = board.debug_button
	assert_true(button.is_visible_in_tree())
	button.pressed.emit()
	assert_true(board.debug.enabled)
	assert_true(game.debug_mode)
	assert_eq(button.text, board.DEBUG_BUTTON_TEXT[true])
	button.pressed.emit()
	assert_false(board.debug.enabled)
	assert_eq(button.text, board.DEBUG_BUTTON_TEXT[false])


func test_the_energy_row_squeezes_instead_of_wrapping():
	var grid := FateZones.grid("energy", 1)
	var row_y: float = grid.get_slot(0).global_position.y
	for _i in range(12):
		await put_energy(1, "Beetle Brawler")
	await put_energy(1, "Beetle Brawler", true)
	await wait_seconds(0.4)
	assert_eq(grid.get_slot_count(), 13)
	var last: BoardPlacementSlot = grid.get_slot(12)
	assert_almost_eq(last.global_position.y, row_y, 1.0, "Still one row")
	assert_lte(last.global_position.x + last.size.x - grid.get_slot(0).global_position.x,
			FateLayout.ENERGY_ROW_WIDTH + 1.0, "Squeezed into the row width")
	for card in game.player(1).cards_in_grid("energy"):
		assert_almost_eq(card.global_position, card._placement_slot.global_position, Vector2(1, 1),
				"%s sits on its slot" % card.canonical_name)
	var counter: Control = board.energy_counters[1]
	assert_eq(counter.get_node("Column/Ready").text, "12/13")
	assert_eq(counter.get_node("Column/Tapped").text, "1 tapped")
