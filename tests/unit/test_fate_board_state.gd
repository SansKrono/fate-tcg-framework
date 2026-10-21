extends GutTest
# FateBoardState (parse, normalise, print, validate) and FateBoardStateFiles. These tests never
# build a table: they only work on data.

var _known: Dictionary


func before_all():
	_known = {}
	for table in [FateData.CARDS, FateData.TOKENS, FateData.DOCTRINES]:
		for card_name in table:
			_known[card_name] = true


func _state(text: String) -> FateBoardState:
	return FateBoardState.from_json(text)


func _errors(text: String) -> Array[String]:
	return _state(text).validate(_known)


func _has_error(errors: Array[String], fragment: String) -> bool:
	for e in errors:
		if fragment in e:
			return true
	return false


# --- the smallest states ---------------------------------------------------------------------------

func test_a_state_with_only_format_and_version_is_valid():
	var state := _state('{"format": "fate-board-state", "version": 1}')
	assert_eq(state.validate(_known), [])
	assert_eq(state.data["turn"], {"number": 1, "active_player": 1, "phase": "main", "energy_choice": "draw"})


func test_a_new_state_is_an_empty_valid_board():
	var state := FateBoardState.new()
	assert_eq(state.validate(_known), [])
	assert_eq(state.data["format"], FateBoardState.FORMAT)
	assert_eq(state.data["version"], FateBoardState.VERSION)


func test_the_energy_phase_defaults_to_no_choice_made():
	var state := _state('{"format": "fate-board-state", "version": 1, "turn": {"phase": "energy"}}')
	assert_eq(state.data["turn"]["energy_choice"], "")
	assert_eq(state.validate(_known), [])


func test_player_defaults():
	var state := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {}}}')
	assert_eq(state.player(1)["life"], FatePlayer.STARTING_LIFE)
	assert_eq(state.zone(1, "hand"), [])
	assert_eq(state.zone(2, "hand"), [], "A player without an entry has empty zones")


# --- reading JSON ----------------------------------------------------------------------------------------

func test_text_that_is_not_json_is_reported_not_thrown():
	var state := _state("{ this is not json")
	var errors := state.validate(_known)
	assert_true(_has_error(errors, "Not valid JSON"), str(errors))
	assert_false(state.is_valid())


func test_a_json_array_is_not_a_state():
	var errors := _errors("[1, 2]")
	assert_true(_has_error(errors, "top level"), str(errors))


func test_json_numbers_become_ints():
	var state := _state('{"format": "fate-board-state", "version": 1, "turn": {"number": 3.0}, "players": {"1": {"life": 7.0}}}')
	assert_eq(typeof(state.data["turn"]["number"]), TYPE_INT)
	assert_eq(typeof(state.player(1)["life"]), TYPE_INT)
	assert_eq(state.player(1)["life"], 7)


func test_a_real_fraction_stays_a_float_and_is_rejected():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"life": 7.5}}}')
	assert_true(_has_error(errors, "players.1.life"), str(errors))


# --- cards ---------------------------------------------------------------------------------------------------

func test_a_card_name_expands_to_an_object():
	var state := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {"hand": ["Battle Smith"]}}}')
	assert_eq(state.zone(1, "hand"), [{"card": "Battle Smith"}])


func test_defaults_are_removed_so_equal_boards_have_equal_data():
	var terse := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": ["Battle Smith"]}}}')
	var wordy := _state('''{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": [
			{"card": "Battle Smith", "tapped": false, "face": "up", "owner": 1, "controller": 1,
			 "entered_turn": 0, "damage": {"Strike": 0}, "modifiers": [], "tokens": {}}]}}}''')
	assert_eq(wordy.data, terse.data)


func test_defaults_depend_on_the_zone():
	var state := _state('''{"format": "fate-board-state", "version": 1, "players": {"1": {
			"occupied": [{"card": "Battle Smith", "tapped": true}],
			"energy": [{"card": "Beetle Brawler", "face": "down"}, {"card": "Beetle Brawler", "face": "up"}]}}}''')
	assert_eq(state.zone(1, "occupied"), [{"card": "Battle Smith"}], "Occupied creatures are tilted by default")
	assert_eq(state.zone(1, "energy"), [{"card": "Beetle Brawler"}, {"card": "Beetle Brawler", "face": "up"}])


func test_grid_zones_keep_gaps_and_lose_trailing_empty_slots():
	var state := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": [null, "Battle Smith", null, null]}}}')
	assert_eq(state.zone(1, "creatures"), [null, {"card": "Battle Smith"}])


func test_empty_zones_are_dropped():
	var state := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {"hand": [], "creatures": [null]}}}')
	assert_false(state.player(1).has("hand"))
	assert_false(state.player(1).has("creatures"))


func test_each_card_walks_attached_cards_too():
	var state := _state('''{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": [
			{"card": "Battle Smith", "attached": ["Beetle Brawler"]}]}}}''')
	var seen := []
	state.each_card(func(path, entry, zone_name, pid): seen.append([path, entry["card"], zone_name, pid]))
	assert_eq(seen, [["players.1.creatures[0]", "Battle Smith", "creatures", 1],
			["players.1.creatures[0].attached[0]", "Beetle Brawler", "attached", 1]])


# --- printing --------------------------------------------------------------------------------------------------

func test_to_json_round_trips_to_the_same_data():
	var original := _state('''{"format": "fate-board-state", "version": 1, "name": "x",
			"turn": {"number": 4, "active_player": 2, "phase": "combat_declare", "energy_choice": "energy"},
			"players": {"1": {"life": 8, "hand": ["Battle Smith"], "creatures": [null,
				{"card": "Goblin Scout Leader", "id": "g", "damage": {"Guard": 1}, "entered_turn": 2,
				 "modifiers": [{"stat": "Strike", "amount": 2, "expiry": "permanent", "source": "g"}],
				 "grants": [{"keyword": "Savage", "value": 2}]}], "doctrines": "auto"},
				"2": {"deck": {"build": true, "size": 30}, "energy": ["Beetle Brawler", {"card": "Scrap Cannon", "tapped": true}]}},
			"world": ["Equal Footing"],
			"rng": {"seed": "abc", "state": 77}}''')
	assert_eq(original.validate(_known), [])
	var again := FateBoardState.from_json(original.to_json())
	assert_eq(again.data, original.data)
	assert_eq(again.validate(_known), [])


func test_to_json_writes_name_only_cards_as_text_and_keeps_reading_order():
	var state := _state('{"format": "fate-board-state", "version": 1, "name": "n", "players": {"1": {"creatures": ["Battle Smith", {"card": "Battle Smith", "id": "x"}]}}}')
	var text := state.to_json()
	assert_true(text.find('"Battle Smith"') != -1)
	assert_false('"card": "Battle Smith"\n' in text.substr(0, text.find('"id"')), "The plain card is a string")
	assert_true(text.find('"format"') < text.find('"turn"'))
	assert_true(text.find('"turn"') < text.find('"players"'))


func test_unknown_keys_survive_a_round_trip():
	var state := _state('{"format": "fate-board-state", "version": 1, "_note": "hello", "players": {"1": {"_x": 1}}}')
	assert_eq(FateBoardState.from_json(state.to_json()).data["_note"], "hello")
	assert_eq(FateBoardState.from_json(state.to_json()).player(1)["_x"], 1)


# --- validation: header ----------------------------------------------------------------------------

func test_wrong_format_and_newer_version_are_refused():
	assert_true(_has_error(_errors('{"format": "something-else", "version": 1}'), "format"))
	assert_true(_has_error(_errors('{"format": "fate-board-state", "version": 2}'), "newer than this game"))
	assert_true(_has_error(_errors('{"format": "fate-board-state", "version": "one"}'), "version"))


func test_unsupported_phases_say_why():
	for phase in ["maintenance", "draw", "combat_intercept", "combat_resolve", "end"]:
		var errors := _errors('{"format": "fate-board-state", "version": 1, "turn": {"phase": "%s"}}' % phase)
		assert_true(_has_error(errors, "cannot be stored"), "%s: %s" % [phase, errors])
	var mid := _errors('{"format": "fate-board-state", "version": 1, "turn": {"phase": "combat_resolve"}}')
	assert_true(_has_error(mid, "mid-resolution"), str(mid))


func test_unknown_phase_lists_the_valid_ones():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "turn": {"phase": "lunch"}}')
	assert_true(_has_error(errors, "energy, main, combat_declare"), str(errors))


func test_turn_fields_are_checked():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "turn": {"number": 0, "active_player": 3, "energy_choice": "maybe"}}')
	assert_true(_has_error(errors, "turn.number"), str(errors))
	assert_true(_has_error(errors, "turn.active_player"), str(errors))
	assert_true(_has_error(errors, "turn.energy_choice"), str(errors))


func test_a_main_phase_needs_the_energy_choice_made():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "turn": {"phase": "main", "energy_choice": ""}}')
	assert_true(_has_error(errors, "already made"), str(errors))


func test_only_players_one_and_two_exist():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "players": {"3": {}}}')
	assert_true(_has_error(errors, "players.3"), str(errors))


# --- validation: zones and cards ----------------------------------------------------------------------

func test_an_unknown_card_gets_a_path_and_a_suggestion():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": [null, null, null, "Battel Smith"]}}}')
	assert_eq(errors.size(), 1, str(errors))
	assert_true(errors[0].begins_with("players.1.creatures[3].card:"), errors[0])
	assert_true("did you mean \"Battle Smith\"" in errors[0], errors[0])


func test_cards_defined_in_the_state_are_known():
	var text := '''{"format": "fate-board-state", "version": 1,
			"definitions": {"Test 3/2": {"Type": "Creature", "Strike": 3, "Guard": 2}},
			"players": {"1": {"creatures": ["Test 3/2"]}}}'''
	assert_eq(_errors(text), [])
	var missing_type := _errors('{"format": "fate-board-state", "version": 1, "definitions": {"Bad": {"Strike": 1}}}')
	assert_true(_has_error(missing_type, "definitions.Bad.Type"), str(missing_type))


func test_zone_capacity_is_enforced():
	var seven := '["Battle Smith","Battle Smith","Battle Smith","Battle Smith","Battle Smith","Battle Smith","Battle Smith"]'
	var errors := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": %s}}}' % seven)
	assert_true(_has_error(errors, "players.1.creatures: holds at most 6"), str(errors))
	var relics := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"relics": [null, null, null, "Garbage Heap"]}}}')
	assert_eq(relics, [], "the relic zone has no limit")
	var world := _errors('{"format": "fate-board-state", "version": 1, "world": ["Equal Footing", "Equal Footing"]}')
	assert_true(_has_error(world, "world: holds at most 1"), str(world))


func test_a_big_hand_is_allowed_with_a_warning():
	var cards := ", ".join(range(12).map(func(_i): return '"Battle Smith"'))
	var state := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {"hand": [%s]}}}' % cards)
	assert_eq(state.validate(_known), [])
	assert_eq(state.warnings.size(), 1)


func test_piles_have_no_empty_slots():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"hand": ["Battle Smith", null]}}}')
	assert_true(_has_error(errors, "players.1.hand[1]"), str(errors))


func test_deck_and_doctrine_special_forms():
	assert_eq(_errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"deck": {"build": true, "size": 20}, "doctrines": "auto"}}}'), [])
	var bad_deck := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"deck": {"size": 20}}}}')
	assert_true(_has_error(bad_deck, "players.1.deck"), str(bad_deck))
	var bad_doctrines := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"doctrines": "all of them"}}}')
	assert_true(_has_error(bad_doctrines, "players.1.doctrines"), str(bad_doctrines))


func test_card_field_types_are_checked():
	var errors := _errors('''{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": [
			{"card": "Battle Smith", "tapped": "yes", "face": "sideways", "owner": 5, "entered_turn": -1,
			 "damage": {"Speed": 1, "Guard": -2}, "tokens": {"tech": -1}}]}}}''')
	for fragment in ["tapped", "face", "owner", "entered_turn", "damage.Speed", "damage.Guard", "tokens.tech"]:
		assert_true(_has_error(errors, "creatures[0]." + fragment), "%s: %s" % [fragment, errors])


func test_a_card_without_a_name_is_an_error():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "players": {"1": {"hand": [{"id": "x"}, 5]}}}')
	assert_true(_has_error(errors, "players.1.hand[0].card"), str(errors))
	assert_true(_has_error(errors, "players.1.hand[1]"), str(errors))


func test_unknown_keys_only_warn():
	var state := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {"hand": [{"card": "Battle Smith", "note": "x"}], "mood": 1}}}')
	assert_eq(state.validate(_known), [])
	assert_eq(state.warnings.size(), 2, str(state.warnings))


# --- validation: ids and references --------------------------------------------------------------------

func test_ids_must_be_unique():
	var errors := _errors('''{"format": "fate-board-state", "version": 1, "players": {
			"1": {"hand": [{"card": "Battle Smith", "id": "a"}]},
			"2": {"hand": [{"card": "Battle Smith", "id": "a"}]}}}''')
	assert_true(_has_error(errors, "\"a\" is used by more than one card"), str(errors))


func test_references_must_resolve_to_a_card():
	var errors := _errors('''{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": [
			{"card": "Battle Smith",
			 "modifiers": [{"stat": "Strike", "amount": 1, "source": "ghost"}],
			 "grants": [{"keyword": "Savage", "source": "phantom"}],
			 "forced_blocker": {"target": "nobody", "turn": 1}}]}}}''')
	assert_true(_has_error(errors, "modifiers[0].source: refers to the card id \"ghost\""), str(errors))
	assert_true(_has_error(errors, "grants[0].source: refers to the card id \"phantom\""), str(errors))
	assert_true(_has_error(errors, "forced_blocker.target: refers to the card id \"nobody\""), str(errors))


func test_a_reference_to_a_card_in_another_zone_is_fine():
	var errors := _errors('''{"format": "fate-board-state", "version": 1, "players": {
			"1": {"relics": [{"card": "Garbage Heap", "id": "heap"}],
			      "creatures": [{"card": "Battle Smith", "modifiers": [{"stat": "Guard", "amount": 1, "source": "heap"}]}]}}}''')
	assert_eq(errors, [])


func test_modifier_and_grant_fields_are_checked():
	var errors := _errors('''{"format": "fate-board-state", "version": 1, "players": {"1": {"creatures": [
			{"card": "Battle Smith",
			 "modifiers": [{"stat": "Speed", "amount": "lots"}],
			 "grants": [{"value": 1.5}]}]}}}''')
	assert_true(_has_error(errors, "modifiers[0].stat"), str(errors))
	assert_true(_has_error(errors, "modifiers[0].amount"), str(errors))
	assert_true(_has_error(errors, "grants[0].keyword"), str(errors))
	assert_true(_has_error(errors, "grants[0].value"), str(errors))


func test_rng_must_be_a_number_or_text():
	var errors := _errors('{"format": "fate-board-state", "version": 1, "rng": {"seed": [1], "state": true}}')
	assert_true(_has_error(errors, "rng.seed"), str(errors))
	assert_true(_has_error(errors, "rng.state"), str(errors))


func test_all_problems_are_reported_at_once():
	var errors := _errors('''{"format": "fate-board-state", "version": 1, "turn": {"phase": "lunch"},
			"players": {"1": {"life": "ten", "hand": ["Nope"]}}}''')
	assert_gte(errors.size(), 3, str(errors))


# --- files ---------------------------------------------------------------------------------------------------------

func test_file_names_are_sanitized():
	assert_eq(FateBoardStateFiles.sanitize("Two goblins vs a wall!"), "Two_goblins_vs_a_wall")
	assert_eq(FateBoardStateFiles.sanitize("../../evil"), "evil")
	assert_eq(FateBoardStateFiles.sanitize("   "), "")
	assert_eq(FateBoardStateFiles.sanitize("a-b_c 1"), "a-b_c_1")


func test_the_shared_examples_are_listed_and_valid():
	var names := []
	for entry in FateBoardStateFiles.list():
		if entry["source"] == FateBoardStateFiles.SOURCE_SHARED:
			names.append(entry["name"])
	for expected in ["empty_main_phase", "mana_and_energy", "goblin_attack_ready", "every_feature", "energy_phase_choice"]:
		assert_true(expected in names, "%s is listed: %s" % [expected, names])
	assert_false("board_state.schema" in names, "The schema is not a board state")
	for entry in FateBoardStateFiles.list():
		var state := FateBoardStateFiles.load_state(entry["path"])
		assert_eq(state.validate(_known), [], "%s is valid" % entry["path"])


func test_a_missing_state_comes_back_with_an_error_not_null():
	var state := FateBoardStateFiles.load_state("no_such_board_anywhere")
	assert_not_null(state)
	assert_true(_has_error(state.validate(_known), "No board state called"))


func test_resolve_finds_by_name_and_by_path():
	assert_eq(FateBoardStateFiles.resolve("empty_main_phase"), "res://boards/empty_main_phase.json")
	assert_eq(FateBoardStateFiles.resolve("empty_main_phase.json"), "res://boards/empty_main_phase.json")
	assert_eq(FateBoardStateFiles.resolve("res://boards/empty_main_phase.json"), "res://boards/empty_main_phase.json")
	assert_eq(FateBoardStateFiles.resolve("nothing_here"), "")
	assert_eq(FateBoardStateFiles.resolve(""), "")


func test_a_state_saved_to_the_personal_folder_loads_back_equal():
	var state := _state('{"format": "fate-board-state", "version": 1, "players": {"1": {"hand": ["Battle Smith"], "life": 4}}}')
	var saved := FateBoardStateFiles.save_state(state, "unit test board %d" % randi())
	assert_true(saved["ok"], str(saved))
	var loaded := FateBoardStateFiles.load_state(saved["path"])
	assert_eq(loaded.data["players"], state.data["players"])
	assert_eq(FateBoardStateFiles.delete_state(saved["path"].get_file().get_basename()), "")
	assert_eq(FateBoardStateFiles.resolve(saved["path"]), "")


func test_saving_needs_a_name_and_the_repo_folder_needs_the_editor():
	var state := FateBoardState.new()
	assert_false(FateBoardStateFiles.save_state(state, "   ")["ok"])
	if not OS.has_feature("editor"):
		assert_false(FateBoardStateFiles.save_state(state, "x", true)["ok"])
