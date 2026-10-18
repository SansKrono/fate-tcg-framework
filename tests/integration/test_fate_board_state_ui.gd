extends "res://tests/FateCommon.gd"
# The "Board states" section of the debug panel (FateDebug): the file list, save, load, delete,
# copy and paste. It must work whether the table's capture / loader are real or still stubs.

const TEST_NAME := "zz_ui_test_state"
const BAD_JSON := '{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": ["Battel Smith"]}}}'

var debug: FateDebug
var loader_calls := 0
var clipboard := ""


func before_each():
	await super.before_each()
	debug = board.debug
	debug.set_enabled(true)
	loader_calls = 0
	clipboard = ""
	debug.board_clipboard_read = func(): return clipboard
	debug.board_clipboard_write = func(text): clipboard = text


func after_each():
	FateBoardStateFiles.delete_state(TEST_NAME)


func _open() -> void:
	debug._bs_set_open(true)


func _item_texts() -> Array:
	var texts := []
	for i in debug._bs_list.item_count:
		texts.append(debug._bs_list.get_item_text(i))
	return texts


func _select(item_text: String) -> void:
	for i in debug._bs_list.item_count:
		if debug._bs_list.get_item_text(i) == item_text:
			debug._bs_list.select(i)
			debug._bs_list.item_selected.emit(i)
			return
	fail_test("No list item %s in %s" % [item_text, _item_texts()])


func _spy_loader(result := {"ok": true, "errors": [], "warnings": []}) -> void:
	debug.board_loader = func(_state, _opts := {}):
		loader_calls += 1
		return result


func test_section_starts_collapsed_and_toggles():
	assert_false(debug._bs_body.visible)
	assert_string_contains(debug._bs_toggle.text, "Board states")
	debug._bs_toggle.pressed.emit()
	assert_true(debug._bs_body.visible)
	debug._bs_toggle.pressed.emit()
	assert_false(debug._bs_body.visible)


func test_list_shows_the_shared_files():
	_open()
	var texts := _item_texts()
	for shared in ["empty_main_phase", "mana_and_energy", "goblin_attack_ready"]:
		assert_has(texts, "[repo] %s" % shared)
	assert_does_not_have(texts, "[repo] board_state.schema")


func test_selecting_an_item_fills_the_name():
	_open()
	_select("[repo] goblin_attack_ready")
	assert_eq(debug._bs_name.text, "goblin_attack_ready")


func test_repo_files_cannot_be_deleted():
	_open()
	_select("[repo] empty_main_phase")
	assert_true(debug._bs_buttons["delete"].disabled)
	await debug._bs_delete()
	assert_string_contains(debug._bs_status.text, "shared repo file")
	assert_has(_item_texts(), "[repo] empty_main_phase")


func test_repo_checkbox_follows_the_editor_feature():
	assert_eq(debug._bs_repo_check.disabled, not OS.has_feature("editor"))
	assert_ne(debug._bs_repo_check.tooltip_text, "")


func test_load_of_an_invalid_state_shows_the_paths_and_skips_the_loader():
	clipboard = BAD_JSON
	_spy_loader()
	await debug._bs_paste_and_load()
	assert_eq(loader_calls, 0, "An invalid state is never given to the loader")
	assert_string_contains(debug._bs_status.text, "players.1.creatures[0].card")
	assert_string_contains(debug._bs_status.text, "Battel Smith")


func test_more_than_five_errors_are_cut_off():
	debug._bs_show(["a", "b", "c", "d", "e", "f", "g"], ["w"])
	var lines: PackedStringArray = debug._bs_status.text.split("\n")
	assert_eq(lines.size(), 7, "5 errors, (+2 more), warning count")
	assert_eq(lines[4], "e")
	assert_eq(lines[5], "(+2 more)")
	assert_eq(lines[6], "1 warning")


func test_load_of_a_good_state_calls_the_loader_and_shows_the_result():
	_open()
	_select("[repo] empty_main_phase")
	_spy_loader()
	await debug._bs_load_selected()
	assert_eq(loader_calls, 1)
	assert_string_contains(debug._bs_status.text, "Loaded")
	_spy_loader({"ok": false, "errors": ["boom at players.1"], "warnings": ["careful"]})
	await debug._bs_load_selected()
	assert_eq(loader_calls, 2)
	assert_string_contains(debug._bs_status.text, "boom at players.1")
	assert_string_contains(debug._bs_status.text, "1 warning")


func test_load_by_typed_name_and_unknown_name():
	_open()
	_spy_loader()
	debug._bs_name.text = "mana_and_energy"
	await debug._bs_load_selected()
	assert_eq(loader_calls, 1)
	debug._bs_name.text = "no_such_state_anywhere"
	await debug._bs_load_selected()
	assert_eq(loader_calls, 1, "A missing file is not loaded")
	assert_string_contains(debug._bs_status.text, "No board state called")
	debug._bs_name.text = ""
	await debug._bs_load_selected()
	assert_eq(loader_calls, 1)
	assert_ne(debug._bs_status.text, "")


func test_the_real_loader_result_is_shown_as_text():
	# Works for the stub ("not implemented") and for the real loader alike
	_open()
	_select("[repo] empty_main_phase")
	var probe: Dictionary = await game.load_board_state(FateBoardStateFiles.load_state("empty_main_phase"))
	_select("[repo] empty_main_phase")
	await debug._bs_load_selected()
	await wait_seconds(0.2)
	if probe.get("ok", false):
		assert_string_contains(debug._bs_status.text, "Loaded")
	else:
		assert_string_contains(debug._bs_status.text, str(probe["errors"][0]))


func test_the_real_capture_failure_is_shown_as_text():
	_open()
	debug._bs_name.text = TEST_NAME
	await debug._bs_save()
	if FateBoardStateFiles.resolve(TEST_NAME) == "":
		# Capture refused (or still a stub): the reason is on screen and nothing was written
		assert_ne(debug._bs_status.text, "")
		if not game.board_state_errors.is_empty():
			assert_string_contains(debug._bs_status.text, game.board_state_errors[0])
	else:
		assert_string_contains(debug._bs_status.text, "Saved")


func test_save_writes_a_personal_file_that_is_listed_and_delete_removes_it():
	_open()
	debug.board_capture = func(): return FateBoardState.new()
	debug._bs_name.text = TEST_NAME
	await debug._bs_save()
	assert_string_contains(debug._bs_status.text, "Saved")
	assert_true(FileAccess.file_exists("user://boards/%s.json" % TEST_NAME))
	assert_has(_item_texts(), "[personal] %s" % TEST_NAME)
	assert_eq(debug._bs_list.get_selected_items().size(), 1, "The saved file is selected")
	# The file is a readable state
	assert_true(FateBoardStateFiles.load_state(TEST_NAME).validate().is_empty())
	assert_false(debug._bs_buttons["delete"].disabled)
	await debug._bs_delete()
	assert_false(FileAccess.file_exists("user://boards/%s.json" % TEST_NAME))
	assert_does_not_have(_item_texts(), "[personal] %s" % TEST_NAME)
	assert_eq(debug._bs_name.text, "")


func test_save_without_a_name_or_when_capture_refuses():
	_open()
	debug.board_capture = func(): return FateBoardState.new()
	debug._bs_name.text = "  "
	await debug._bs_save()
	assert_string_contains(debug._bs_status.text, "name")
	debug.board_capture = func(): return null
	game.board_state_errors = ["turn: the table is in the draw step"]
	debug._bs_name.text = TEST_NAME
	await debug._bs_save()
	assert_string_contains(debug._bs_status.text, "draw step")
	assert_false(FileAccess.file_exists("user://boards/%s.json" % TEST_NAME))


func test_copy_json_puts_the_capture_on_the_clipboard():
	debug.board_capture = func(): return FateBoardState.new()
	debug._bs_copy_json()
	var copied := clipboard
	assert_string_contains(copied, "fate-board-state")
	assert_string_contains(debug._bs_status.text, "Copied")
	# and back: the pasted text loads
	_spy_loader()
	await debug._bs_paste_and_load()
	assert_eq(loader_calls, 1)


func test_copy_json_shows_why_capture_refused():
	debug.board_capture = func(): return null
	game.board_state_errors = ["turn.phase: not now"]
	debug._bs_copy_json()
	assert_string_contains(debug._bs_status.text, "turn.phase: not now")


func test_f3_toggle_still_works():
	debug.set_enabled(false)
	assert_false(debug._panel.visible)
	debug.set_enabled(true)
	assert_true(debug._panel.visible)
