extends "res://tests/FateCommon.gd"
# The human choice UI (ui/FateChoiceUI.gd): the questions card effects ask through game.choices, answered
# with the entry points the mouse reaches (card_clicked, player_clicked, the buttons). Tests do not get
# the UI from the board (cfc.is_testing keeps the deterministic defaults), so each test adds its own.

const UI_SCRIPT := "res://src/custom/fate/ui/FateChoiceUI.gd"

# A spell whose resolve() records the choice it got (the pick goes through game.choices)
class Picker:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var log: Array = []
	var picks: Array = []

	func _init(name_of_card := "") -> void:
		card_name = name_of_card
		has_choice = true

	func candidates(_card: Card, _caster_id: int) -> Array:
		return picks

	func default_choice(_card: Card, _caster_id: int):
		return picks[0] if not picks.is_empty() else null

	func resolve(_card: Card, _caster_id: int, choice) -> void:
		log.append(choice)


var ui


func before_each():
	await super.before_each()
	ui = load(UI_SCRIPT).new()
	board.add_child(ui)
	ui.setup(game)


# Starts a question without waiting for the answer: returns a box that holds the answer once it is given
func _ask_pick(kind: String, player: int, source, options: Array, count := 1, optional := false) -> Dictionary:
	var box := {"done": false, "value": null}
	var run := func():
		box.value = await game.choices.pick(kind, player, source, options, count, optional)
		box.done = true
	run.call()
	await get_tree().process_frame
	return box


func _ask_confirm(prompt: String, player: int, source, default := true) -> Dictionary:
	var box := {"done": false, "value": null}
	var run := func():
		box.value = await game.choices.confirm(prompt, player, source, default)
		box.done = true
	run.call()
	await get_tree().process_frame
	return box


func _three_creatures() -> Array:
	var cards := []
	for n in ["Moral Captain", "Righteous Guard", "Skulking Goblin"]:
		cards.append(await put_creature(2, n))
	return cards


# --- the question is asked and answered ---------------------------------------------------------------------

func test_a_spell_with_a_choice_asks_the_ui_and_resolves_with_the_clicked_card() -> void:
	var fx := Picker.new("Reinforcements")
	game.card_effects.register(fx)
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()
	var cards := await _three_creatures()
	fx.picks = cards
	var spell := await put_in_hand(1, "Reinforcements")
	game.play_from_hand(spell)
	await get_tree().process_frame
	assert_true(ui.is_open(), "the choice is open")
	assert_eq(ui.mode, "table", "every candidate stands on the table")
	assert_eq(ui.candidates(), cards)
	assert_eq(ui.request.source, spell)
	assert_true(ui.card_clicked(cards[1]))
	await wait_seconds(0.2)
	assert_false(ui.is_open())
	assert_eq(fx.log, [cards[1]], "the spell resolved with the clicked card")
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))


func test_the_game_goes_on_after_the_answer() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("target creature", 1, null, cards)
	assert_eq(game.phase, FateGame.Phase.ENERGY, "the turn waits while the question is open")
	ui.card_clicked(cards[0])
	assert_true(box.done)
	assert_eq(box.value, cards[0])
	assert_eq(ui.shield.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the table takes clicks again")
	assert_false(ui.visible)
	go_to_main()
	assert_eq(game.phase, FateGame.Phase.MAIN, "the phases advance as before")
	# And a second question works as well
	var second := await _ask_pick("target creature", 1, null, cards)
	ui.card_clicked(cards[2])
	assert_eq(second.value, cards[2])


func test_a_wrong_click_is_refused_and_the_question_stays_open() -> void:
	var cards := await _three_creatures()
	var other := await put_creature(1, "Moral Captain")
	var box := await _ask_pick("target creature", 1, null, cards)
	assert_false(ui.card_clicked(other), "not a candidate")
	assert_false(box.done)
	assert_true(ui.is_open())
	assert_string_contains(ui.prompt_text(), "not one of the choices")
	ui.card_clicked(cards[0])
	assert_true(box.done)


func test_the_prompt_says_whose_choice_it_is_what_and_for_which_card() -> void:
	var cards := await _three_creatures()
	var source := await put_creature(1, "Moral Captain")
	# Player 2 is not the active player: "target opponent chooses"
	_ask_pick("target creature", 2, source, cards)
	var text: String = ui.prompt_text()
	assert_string_contains(text, "Player 2")
	assert_string_contains(text, "target creature")
	assert_string_contains(text, "Moral Captain")
	assert_eq(ui.prompt_label.text, text, "the bar shows it")
	assert_true(ui.bar.visible)
	ui.card_clicked(cards[0])


# --- more than one card ------------------------------------------------------------------------------------------

func test_a_pick_of_several_toggles_and_waits_for_confirm() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("targets", 1, null, cards, 2)
	assert_true(ui.ok_button.visible, "there is a Confirm button")
	assert_true(ui.ok_button.disabled)
	assert_false(ui.confirm_pressed(), "nothing picked yet")
	ui.card_clicked(cards[2])
	assert_eq(ui.selected, [cards[2]])
	assert_true(ui.ok_button.disabled, "one of two")
	assert_true(ui.card_clicked(cards[2]), "clicking again takes it back")
	assert_eq(ui.selected, [])
	ui.card_clicked(cards[2])
	ui.card_clicked(cards[0])
	assert_false(ui.ok_button.disabled)
	assert_false(ui.card_clicked(cards[1]), "a third is refused")
	assert_false(box.done)
	assert_true(ui.confirm_pressed())
	assert_true(box.done)
	assert_eq(box.value, [cards[2], cards[0]])


# --- optional ---------------------------------------------------------------------------------------------------------------

func test_an_optional_pick_can_be_skipped_with_none() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("target creature", 1, null, cards, 1, true)
	assert_true(ui.none_button.visible)
	assert_true(ui.none_pressed())
	assert_true(box.done)
	assert_null(box.value)
	assert_false(ui.is_open())


func test_escape_skips_an_optional_pick_but_not_a_mandatory_one() -> void:
	var cards := await _three_creatures()
	var mandatory := await _ask_pick("target creature", 1, null, cards)
	assert_false(ui.none_button.visible, "no None button")
	assert_false(ui.none_pressed(), "None is refused")
	assert_false(ui.cancel_pressed(), "Escape is ignored")
	assert_false(mandatory.done)
	assert_true(ui.is_open())
	ui.card_clicked(cards[1])
	var optional := await _ask_pick("target creature", 1, null, cards, 1, true)
	assert_true(ui.cancel_pressed())
	assert_null(optional.value)
	assert_true(optional.done)


func test_skipping_an_optional_multi_pick_gives_an_empty_array() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("targets", 1, null, cards, 2, true)
	ui.card_clicked(cards[0])
	ui.none_pressed()
	assert_eq(box.value, [])


# --- players ------------------------------------------------------------------------------------------------------------------

func test_a_player_can_be_picked_with_the_plate() -> void:
	var box := await _ask_pick("target player", 1, null, [game.player(1), game.player(2)])
	assert_eq(ui.mode, "table", "the plates are on the table")
	assert_false(ui.player_clicked(3), "there is no such player")
	assert_true(ui.player_clicked(2))
	assert_eq(box.value, game.player(2))


func test_players_and_creatures_can_be_candidates_together() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("any target", 1, null, cards + [game.player(2)])
	assert_eq(ui.mode, "table")
	ui.player_clicked(2)
	assert_eq(box.value, game.player(2))


# --- cards that are not on the table ---------------------------------------------------------------------------------

func test_cards_in_the_hand_are_picked_from_a_modal_list() -> void:
	await empty_hand(1)
	var hand_cards := []
	for n in ["Moral Captain", "Righteous Guard", "Skulking Goblin"]:
		hand_cards.append(await put_in_hand(1, n))
	var box := await _ask_pick("card to discard", 1, null, hand_cards)
	assert_eq(ui.mode, "list")
	assert_true(ui.modal.visible)
	assert_false(ui.bar.visible)
	assert_eq(ui._entries.size(), 3, "one entry per card")
	assert_string_contains(ui._entries[1].text, "Righteous Guard")
	assert_false(ui.gated, "the active player sees their own hand")
	ui._entries[1].pressed.emit()
	assert_true(box.done)
	assert_eq(box.value, hand_cards[1])
	assert_false(ui.modal.visible)


func test_a_list_pick_of_several_has_a_confirm_button() -> void:
	await empty_hand(1)
	var hand_cards := []
	for n in ["Moral Captain", "Righteous Guard", "Skulking Goblin"]:
		hand_cards.append(await put_in_hand(1, n))
	var box := await _ask_pick("cards", 1, null, hand_cards, 2, true)
	assert_true(ui.modal_ok.visible)
	assert_true(ui.modal_ok.disabled)
	assert_true(ui.modal_none.visible, "optional")
	ui._entries[0].pressed.emit()
	ui._entries[2].pressed.emit()
	assert_false(ui.modal_ok.disabled)
	assert_string_contains(ui.modal_hint.text, "2 / 2")
	ui.modal_ok.pressed.emit()
	assert_eq(box.value, [hand_cards[0], hand_cards[2]])


func test_a_mix_of_table_and_hand_cards_uses_the_list() -> void:
	await empty_hand(1)
	var in_hand := await put_in_hand(1, "Moral Captain")
	var on_table := await put_creature(1, "Righteous Guard")
	var box := await _ask_pick("card", 1, null, [in_hand, on_table])
	assert_eq(ui.mode, "list")
	ui.card_clicked(on_table)
	assert_eq(box.value, on_table)


func test_options_that_are_not_cards_can_be_listed() -> void:
	var box := await _ask_pick("counter", 1, null, ["scrap", "ingot"])
	assert_eq(ui.mode, "list")
	assert_string_contains(ui._entries[1].text, "ingot")
	ui.option_clicked("ingot")
	assert_eq(box.value, "ingot")


func test_a_list_of_a_players_hidden_cards_waits_for_reveal_when_that_player_is_not_active() -> void:
	await empty_hand(2)
	var hand_cards := []
	for n in ["Moral Captain", "Righteous Guard"]:
		hand_cards.append(await put_in_hand(2, n))
	assert_eq(game.active_id, 1)
	var box := await _ask_pick("card to discard", 2, null, hand_cards)
	assert_true(ui.gated, "behind the gate")
	assert_eq(ui._entries.size(), 0, "no card face is built yet")
	assert_true(ui.modal_reveal.visible)
	assert_string_contains(ui.modal_hint.text, "Player 2")
	assert_false(ui.card_clicked(hand_cards[0]), "no peeking")
	assert_false(box.done)
	ui.reveal_pressed()
	assert_false(ui.gated)
	assert_eq(ui._entries.size(), 2)
	assert_false(ui.modal_reveal.visible)
	ui.card_clicked(hand_cards[1])
	assert_eq(box.value, hand_cards[1])


func test_there_is_no_gate_when_an_ai_plays_the_other_seat() -> void:
	await empty_hand(2)
	var hand_cards := [await put_in_hand(2, "Moral Captain")]
	# The person plays seat 2 against an AI on seat 1 (a stand-in: only the seat is looked at)
	game.ai_controllers[1] = Node.new()
	var box := await _ask_pick("card", 2, null, hand_cards + [await put_in_hand(2, "Righteous Guard")])
	assert_false(ui.gated)
	ui.cancel_pressed()
	ui.card_clicked(ui.request.options[0])
	assert_true(box.done)
	game.ai_controllers[1].free()
	game.ai_controllers.erase(1)


# --- yes / no -------------------------------------------------------------------------------------------------------------------

func test_a_confirmation_is_answered_with_yes_or_no() -> void:
	var source := await put_creature(1, "Moral Captain")
	var yes := await _ask_confirm("Draw a card?", 1, source, false)
	assert_eq(ui.mode, "confirm")
	assert_string_contains(ui.prompt_text(), "Draw a card?")
	assert_eq(ui.ok_button.text, "Yes")
	assert_eq(ui.none_button.text, "No")
	assert_true(ui.confirm_pressed())
	assert_true(yes.done)
	assert_true(yes.value)
	var no := await _ask_confirm("Draw a card?", 1, source, true)
	assert_true(ui.none_pressed())
	assert_false(no.value)
	assert_true(no.done)


func test_escape_on_a_confirmation_takes_the_default() -> void:
	var box := await _ask_confirm("Pay?", 1, null, false)
	assert_true(ui.cancel_pressed())
	assert_false(box.value)
	var other := await _ask_confirm("Pay?", 1, null, true)
	ui.cancel_pressed()
	assert_true(other.value)


# --- the table is blocked while a question is open ----------------------------------------------------------------

func test_an_input_layer_eats_the_clicks_while_a_question_is_open() -> void:
	var cards := await _three_creatures()
	assert_eq(ui.shield.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(ui.visible)
	_ask_pick("target creature", 1, null, cards)
	assert_eq(ui.shield.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_true(ui.visible)
	assert_true(Rect2(Vector2.ZERO, ui.size).encloses(Rect2(ui.shield.position, ui.shield.size)), "it covers the screen")
	assert_gt(ui.z_index, board.combat_ui.z_index, "above the combat overlay")
	ui.card_clicked(cards[0])
	assert_eq(ui.shield.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_a_mouse_click_on_a_candidate_picks_it() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("target creature", 1, null, cards)
	await get_tree().process_frame
	var rect: Rect2 = ui.option_rect(cards[2])
	assert_gt(rect.size.x, 0.0, "the candidate has a place on the screen")
	assert_eq(ui.option_at(rect.get_center()), cards[2])
	assert_null(ui.option_at(Vector2(2, 2)), "nothing there")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = rect.get_center()
	ui._on_shield_input(click)
	assert_true(box.done)
	assert_eq(box.value, cards[2])


func test_the_plate_of_a_player_is_clickable() -> void:
	var box := await _ask_pick("target player", 1, null, [game.player(2)])
	var rect: Rect2 = ui.option_rect(game.player(2))
	assert_gt(rect.size.x, 0.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = rect.get_center()
	ui._on_shield_input(click)
	assert_eq(box.value, game.player(2))


# --- never stuck ---------------------------------------------------------------------------------------------------------------

func test_the_default_is_taken_when_the_game_ends_during_a_question() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("target creature", 1, null, cards)
	game.is_over = true
	await wait_seconds(0.1)
	assert_true(box.done, "the question was dropped")
	assert_eq(box.value, cards[0], "with the default")
	assert_false(ui.is_open())
	game.is_over = false


func test_a_seat_played_by_an_ai_never_gets_a_window() -> void:
	var cards := await _three_creatures()
	game.ai_controllers[2] = Node.new()
	var box := await _ask_pick("target creature", 2, null, cards)
	assert_true(box.done, "answered at once")
	assert_eq(box.value, cards[0])
	assert_false(ui.is_open())
	var confirm := await _ask_confirm("Pay?", 2, null, false)
	assert_true(confirm.done)
	assert_false(confirm.value)
	game.ai_controllers[2].free()
	game.ai_controllers.erase(2)


func test_a_seat_that_becomes_an_ai_during_a_question_takes_the_default() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("target creature", 2, null, cards)
	assert_true(ui.is_open())
	game.ai_controllers[2] = Node.new()
	await wait_seconds(0.1)
	assert_true(box.done)
	assert_eq(box.value, cards[0])
	game.ai_controllers[2].free()
	game.ai_controllers.erase(2)


func test_leaving_the_tree_answers_with_the_default() -> void:
	var cards := await _three_creatures()
	var box := await _ask_pick("target creature", 1, null, cards)
	board.remove_child(ui)
	assert_true(box.done)
	assert_eq(box.value, cards[0])
	assert_false(game.choices.chooser.is_valid(), "it unplugs itself")
	ui.free()
	ui = null
	# The defaults of FateChoices are back
	var again := await _ask_pick("target creature", 1, null, cards)
	assert_true(again.done)


func test_questions_wait_for_their_turn() -> void:
	var cards := await _three_creatures()
	var first := await _ask_pick("first", 1, null, cards)
	var second := await _ask_pick("second", 1, null, cards)
	assert_eq(ui.request.kind, "first")
	assert_false(second.done)
	ui.card_clicked(cards[1])
	assert_eq(first.value, cards[1])
	await get_tree().process_frame
	assert_true(ui.is_open(), "the second one is open now")
	assert_eq(ui.request.kind, "second")
	ui.card_clicked(cards[2])
	assert_eq(second.value, cards[2])


# --- answer() --------------------------------------------------------------------------------------------------------------------

func test_answer_sends_a_whole_answer() -> void:
	var cards := await _three_creatures()
	var single := await _ask_pick("one", 1, null, cards)
	assert_false(ui.answer("not a card"))
	assert_true(ui.answer(cards[1]))
	assert_eq(single.value, cards[1])
	var several := await _ask_pick("two", 1, null, cards, 2)
	assert_false(ui.answer([cards[0]]), "one is too few")
	assert_false(ui.answer([cards[0], cards[0]]), "the same twice")
	assert_true(ui.answer([cards[2], cards[1]]))
	assert_eq(several.value, [cards[2], cards[1]])
	var optional := await _ask_pick("three", 1, null, cards, 1, true)
	assert_true(ui.answer(null))
	assert_null(optional.value)
	var yes_no := await _ask_confirm("ok?", 1, null, false)
	assert_false(ui.answer("yes"), "a confirmation takes a bool")
	assert_true(ui.answer(true))
	assert_true(yes_no.value)
	assert_false(ui.answer(true), "nothing is open")
