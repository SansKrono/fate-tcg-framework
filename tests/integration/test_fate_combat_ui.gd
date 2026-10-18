extends "res://tests/FateCommon.gd"
# Tests of the combat UI (FateCombatUI): the clicks that select attackers and blockers, the
# markers, the player avatars, the log and the layout. The clicks go through the same entry points
# the mouse reaches (FateCardTemplate._on_Card_gui_input -> card_clicked, FatePlayerAvatar.pressed,
# the marker buttons); the combat itself is tested in test_fate_combat.gd.

const Phase := FateGame.Phase

var ui: FateCombatUI
var combat: FateCombat


func before_each():
	await super.before_each()
	ui = board.combat_ui
	combat = game.combat


func _markers() -> Array:
	return ui.get_children().filter(func(c): return c is Button and not c is FatePlayerAvatar \
			and not c.is_queued_for_deletion())


# --- layout -------------------------------------------------------------------------------------------------

func test_each_player_has_a_plate_that_shows_name_and_life():
	assert_eq(ui.avatars.size(), 2)
	assert_eq(ui.avatars[1].tooltip_text, "Player 1")
	assert_eq(ui.avatars[1].life_text(), str(LIFE))
	assert_eq(ui.avatars[2].life_text(), str(LIFE))
	game.player(2).life = 13
	assert_eq(ui.avatars[2].life_text(), "13", "It follows the life total")


func test_avatars_and_log_do_not_cover_other_parts_of_the_table():
	await get_tree().process_frame
	await get_tree().process_frame
	var mine: Array = [ui.avatars[1], ui.avatars[2], ui.log_label]
	var others := []
	for grid in get_tree().get_nodes_in_group("placement_grid"):
		others.append([grid.name, grid.get_global_rect()])
	for child in board.get_children():
		if child is Control and child != ui and (child.name.ends_with("Wrapper") or child.name == "StatusBar"):
			others.append([child.name, child.get_global_rect()])
	for i in mine.size():
		for j in range(i + 1, mine.size()):
			assert_false(mine[i].get_global_rect().intersects(mine[j].get_global_rect()),
					"%s must not overlap %s" % [mine[i].name, mine[j].name])
	for control in mine:
		var rect: Rect2 = control.get_global_rect()
		assert_true(Rect2(Vector2.ZERO, FateBoard.SCREEN).encloses(rect), "%s is on screen" % control.name)
		for other in others:
			assert_false(rect.intersects(other[1]), "%s must not overlap %s" % [control.name, other[0]])


# --- declaring by clicking --------------------------------------------------------------------------------------

func test_clicking_an_attacker_selects_it_and_clicking_an_enemy_creature_declares_the_attack():
	var mine := await put_creature(1, 2, 2)
	var enemy := await put_creature(2, 1, 1)
	start_combat()
	assert_true(ui.wants_card_clicks())
	ui.card_clicked(mine)
	assert_eq(ui.selected, mine)
	assert_string_contains(ui.prompt(), "attack with")
	ui.card_clicked(enemy)
	assert_null(ui.selected)
	assert_eq(combat.attacks.size(), 1)
	assert_eq(combat.attacks[0].target_card, enemy)
	assert_eq(_markers().size(), 1, "The attack is marked")
	assert_eq(_markers()[0].text, "1")


func test_clicking_a_player_avatar_attacks_the_player():
	var mine := await put_creature(1, 2, 2)
	start_combat()
	ui.avatar_clicked(2)
	assert_eq(combat.attacks.size(), 0, "Nothing is selected yet")
	assert_string_contains(ui.message, "Select")
	ui.card_clicked(mine)
	ui.avatars[2].pressed.emit()
	assert_eq(combat.attacks.size(), 1)
	assert_true(combat.attacks[0].targets_player())
	assert_eq(combat.attacks[0].target_player, 2)


func test_clicking_the_selected_creature_again_deselects_it_and_clicking_an_attacker_cancels_it():
	var mine := await put_creature(1, 2, 2)
	start_combat()
	ui.card_clicked(mine)
	ui.card_clicked(mine)
	assert_null(ui.selected)
	ui.card_clicked(mine)
	ui.avatar_clicked(2)
	assert_eq(combat.attacks.size(), 1)
	ui.card_clicked(mine)
	assert_eq(combat.attacks.size(), 0, "Clicking an attacker takes it back")
	assert_eq(_markers().size(), 0, "... and its marker")
	ui.card_clicked(mine)
	ui.avatar_clicked(2)
	ui.marker_clicked(combat.attacks[0])
	assert_eq(combat.attacks.size(), 0, "The marker cancels too")


func test_clicks_on_creatures_that_cannot_attack_explain_why():
	var tilted := await put_creature(1, 2, 2, {}, true)
	var enemy := await put_creature(2, 1, 1)
	start_combat()
	ui.card_clicked(tilted)
	assert_null(ui.selected)
	assert_string_contains(ui.message, "strike position")
	assert_string_contains(ui.prompt(), "strike position")
	ui.card_clicked(enemy)
	assert_string_contains(ui.message, "Select")


func test_the_selection_is_drawn_and_cleared_when_the_step_changes():
	var mine := await put_creature(1, 2, 2)
	start_combat()
	ui.card_clicked(mine)
	assert_eq(ui.selected, mine)
	game.request_next_phase()
	assert_null(ui.selected)


# --- intercepting by clicking -------------------------------------------------------------------------------------------

func test_the_defender_clicks_a_blocker_and_then_the_attacker():
	var attacker := await put_creature(1, 2, 2)
	var guard := await put_creature(2, 1, 4, {}, true)
	var upright := await put_creature(2, 1, 4)
	start_combat()
	ui.card_clicked(attacker)
	ui.avatar_clicked(2)
	board.next_button.pressed.emit()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	assert_string_contains(ui.prompt(), "Player 2")
	ui.card_clicked(upright)
	assert_null(ui.selected)
	assert_string_contains(ui.message, "guarding or occupied")
	ui.card_clicked(guard)
	assert_eq(ui.selected, guard)
	ui.card_clicked(attacker)
	assert_eq(combat.attacks[0].blockers, [guard])
	assert_null(ui.selected)
	ui.card_clicked(guard)
	assert_eq(combat.attacks[0].blockers, [], "Clicking a blocker takes it back")
	ui.card_clicked(guard)
	ui.marker_clicked(combat.attacks[0])
	assert_eq(combat.attacks[0].blockers, [guard], "The marker works for blocking too")
	board.next_button.pressed.emit()
	assert_eq(game.phase, Phase.END)
	assert_eq(game.player(2).life, LIFE, "Blocked")
	assert_eq(game.stats.current(guard, "Guard"), 2)


func test_the_defender_cannot_pick_the_attackers_creatures_as_blockers():
	var attacker := await put_creature(1, 2, 2)
	var spare := await put_creature(1, 2, 2, {}, true)
	start_combat()
	ui.card_clicked(attacker)
	ui.avatar_clicked(2)
	board.next_button.pressed.emit()
	ui.card_clicked(spare)
	assert_null(ui.selected)
	assert_ne(ui.message, "")


func test_resolution_is_logged_and_the_table_is_cleaned_up_after_the_combat():
	var attacker := await put_creature(1, 3, 2)
	var enemy := await put_creature(2, 1, 1)
	start_combat()
	ui.card_clicked(attacker)
	ui.card_clicked(enemy)
	board.next_button.pressed.emit()
	board.next_button.pressed.emit()
	assert_eq(game.phase, Phase.END)
	assert_eq(combat.log_lines.size() > 0, true)
	assert_string_contains(ui.log_label.text, "destroyed")
	assert_string_contains(ui.log_label.text.to_lower(), "test 1/1")
	assert_lte(ui.log_label.text.split("\n").size(), FateCombatUI.LOG_LINES, "Only the last few lines")
	await get_tree().process_frame
	assert_eq(_markers().size(), 0, "The markers go when the combat is over (the log keeps the story)")
	assert_null(ui.selected)
	assert_false(ui._drawn_attack_count() > 0, "No arrows are drawn after the combat")


# --- the real input path ------------------------------------------------------------------------------------------------------

func test_a_left_click_on_a_card_in_the_declare_step_selects_it_instead_of_dragging():
	var mine := await put_creature(1, 2, 2)
	start_combat()
	mine._on_Card_gui_input(fake_click(true, Vector2(10, 10)))
	assert_eq(ui.selected, mine)
	assert_null(cfc.card_drag_ongoing, "No drag was started")
	mine._on_Card_gui_input(fake_click(false, Vector2(10, 10)))
	assert_eq(ui.selected, mine, "Releasing the button changes nothing")


func test_clicks_on_cards_mean_nothing_to_the_combat_ui_outside_the_declare_and_intercept_steps():
	var mine := await put_creature(1, 2, 2)
	game.turn.end_phase_waits_for_player = true
	game.draw_extra_card()
	assert_false(ui.wants_card_clicks(), "Main phase")
	mine._on_Card_gui_input(fake_click(true, Vector2(10, 10)))
	assert_null(ui.selected)
	game.advance_phase()
	assert_true(ui.wants_card_clicks(), "Declare step")
	ui.card_clicked(mine)
	ui.avatar_clicked(2)
	board.next_button.pressed.emit()
	assert_true(ui.wants_card_clicks(), "Intercept step")
	board.next_button.pressed.emit()
	assert_eq(game.phase, Phase.END)
	assert_false(ui.wants_card_clicks(), "The attacks resolved")
	ui.card_clicked(mine)
	assert_null(ui.selected)


func test_the_status_bar_prompts_follow_the_combat_steps():
	var mine := await put_creature(1, 2, 2)
	start_combat()
	assert_eq(board.prompt_label.text, ui.prompt())
	ui.card_clicked(mine)
	assert_string_contains(board.prompt_label.text, "attack with")
	ui.avatar_clicked(2)
	game.request_next_phase()
	assert_string_contains(board.prompt_label.text, "Player 2")
	assert_false(board.next_button.disabled)
