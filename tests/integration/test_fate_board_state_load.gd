extends "res://tests/FateCommon.gd"
# Loading board states into the table: FateGame.load_board_state / FateBoardStateApply.

const Phase := FateGame.Phase


func _state(text: String) -> FateBoardState:
	return FateBoardState.from_json(text)


func _wrap(body: String) -> String:
	return '{"format": "fate-board-state", "version": 1, %s}' % body


func _names(cards: Array) -> Array:
	return cards.map(func(c): return c.canonical_name)


# --- the shared example files ----------------------------------------------------------------------

func test_every_shared_board_loads_and_round_trips():
	for entry in FateBoardStateFiles.list():
		if entry["source"] != FateBoardStateFiles.SOURCE_SHARED:
			continue
		var result: Dictionary = await game.load_board_state(FateBoardStateFiles.load_state(entry["path"]),
				{"verify": true})
		assert_true(result["ok"], "%s loads: %s" % [entry["name"], str(result["errors"])])


func test_empty_main_phase():
	await load_board("empty_main_phase")
	assert_eq(game.phase, Phase.MAIN)
	assert_eq(game.turn_number, 1)
	assert_eq(game.active_id, 1)
	assert_eq(_names(FateZones.container("hand", 1).get_all_cards()), ["Battle Smith", "Ancient Tree", "Scrap Cannon"])
	assert_eq(_names(FateZones.container("hand", 2).get_all_cards()), ["Battle Smith", "Goblin Ledgerkeeper"])
	assert_eq(FateZones.container("deck", 1).get_card_count(), 0)
	assert_eq(game.player(1).cards_in_grid("doctrines").size(), 3, "doctrines: auto")
	assert_eq(game.player(1).life, 10)
	assert_true(game.is_started)


func test_mana_and_energy():
	await load_board("mana_and_energy")
	var energy := game.player(1).cards_in_grid("energy")
	assert_eq(energy.size(), 5)
	for card in energy:
		assert_true(card.is_energy)
		assert_false(card.is_faceup, "Energy is face-down")
	assert_eq(energy[3].card_rotation, 90, "The fourth is tapped")
	assert_eq(total_mana(game.mana_pool(1)), 4, "One of five is spent")
	assert_eq(game.energy_choice, "energy")


func test_goblin_attack_ready_then_the_attack_can_be_played_out():
	await load_board("goblin_attack_ready")
	assert_eq(game.phase, Phase.COMBAT_DECLARE)
	assert_eq(game.combat.step, FateCombat.Step.DECLARE)
	assert_eq(game.turn_number, 4)
	var grid := FateZones.grid("creatures", 1)
	assert_null(grid.get_slot(0).occupying_card, "Slot 0 is empty on purpose")
	var leader: Card = grid.get_slot(1).occupying_card
	assert_eq(leader.canonical_name, "Goblin Scout Leader")
	assert_eq(grid.get_slot(2).occupying_card.canonical_name, "Battle Smith")
	assert_eq(leader.entered_turn, 2)
	# Strike 2 + the buff of 2, Guard 1 less the damage of 1 would be 0: see the numbers of the card
	assert_eq(game.stats.current(leader, "Strike"), game.stats.base(leader, "Strike") + 2)
	assert_eq(game.stats.damage_on(leader, "Guard"), 1)
	assert_true(game.keywords.has(leader, "Savage"), "The granted keyword is there")
	var blocker: Card = FateZones.grid("creatures", 2).get_slot(0).occupying_card
	assert_eq(blocker.card_rotation, 90)
	assert_eq(game.player(2).life, 7)
	# The loaded position plays on like any other
	assert_true(game.combat.declare_attack(leader, game.player(2)), game.combat.last_error)
	run_combat()
	assert_lt(game.player(2).life, 7, "The unblocked attack hit")


# --- the game state is exactly the file --------------------------------------------------------------------

func _live_cards() -> Array:
	return get_tree().get_nodes_in_group("cards").filter(
			func(c): return is_instance_valid(c) and not c.is_queued_for_deletion())


func test_loading_replaces_the_whole_table():
	await put_creature(1, 2, 2)
	await put_energy(1, "Beetle Brawler")
	await put_creature(2, 3, 3)
	await load_board("empty_main_phase")
	assert_eq(game.creatures_in_play().size(), 0)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 0)
	assert_eq(_live_cards().size(), 3 + 2 + 3 + 3, "Hands and the six doctrines are all that is left")


func test_nothing_is_drawn_paid_or_untapped_while_loading():
	var hand_before: int = FateZones.container("hand", 1).get_card_count()
	var state := _state(_wrap('"turn": {"phase": "main", "energy_choice": "energy", "number": 2},
			"players": {"1": {"energy": [{"card": "Beetle Brawler", "tapped": true}], "deck": ["Battle Smith", "Battle Smith"]}}'))
	var signals := []
	game.phase_begins.connect(func(_p, phase): signals.append(phase))
	game.card_played.connect(func(_c): signals.append("played"))
	await load_board(state)
	assert_eq(signals, [], "No phase starts, no card is played")
	assert_eq(game.player(1).cards_in_grid("energy")[0].card_rotation, 90, "Not untapped")
	assert_eq(FateZones.container("deck", 1).get_card_count(), 2)
	assert_eq(FateZones.container("hand", 1).get_card_count(), 0, "Not even the starting hand")
	assert_true(hand_before > 0)


func test_piles_are_loaded_top_first_and_the_hand_left_to_right():
	var state := _state(_wrap('"players": {"1": {
			"hand": ["Battle Smith", "Ancient Tree", "Scrap Cannon"],
			"deck": ["Beetle Brawler", "Garbage Heap", "Scrap Recycler"],
			"discard": ["Moral Captain", "Goblin Ledgerkeeper"]}}'))
	await load_board(state)
	assert_eq(_names(FateZones.container("hand", 1).get_all_cards()), ["Battle Smith", "Ancient Tree", "Scrap Cannon"])
	assert_eq(FateZones.container("deck", 1).get_top_card().canonical_name, "Beetle Brawler", "The first listed is the top")
	assert_eq(_names(FateZones.container("deck", 1).get_all_cards()), ["Scrap Recycler", "Garbage Heap", "Beetle Brawler"],
			"Bottom first in the node order")
	assert_eq(FateZones.container("discard", 1).get_top_card().canonical_name, "Moral Captain")


func test_turn_player_phase_and_life_are_set():
	var state := _state(_wrap('"turn": {"number": 7, "active_player": 2, "phase": "energy"},
			"players": {"1": {"life": 3}, "2": {"life": 12}}'))
	await load_board(state)
	assert_eq(game.turn_number, 7)
	assert_eq(game.active_id, 2)
	assert_eq(game.phase, Phase.ENERGY)
	assert_eq(game.energy_choice, "")
	assert_eq(game.player(1).life, 3)
	assert_eq(game.player(2).life, 12)
	assert_true(game.can_draw_extra_card(), "The energy choice is open")
	assert_eq(board.bottom_id, 2, "The active player sits at the bottom")
	assert_eq(board.combat_ui.avatars[1].life_text(), "3")


func test_the_hud_follows_the_loaded_state():
	await load_board("mana_and_energy")
	assert_eq(board.status_label.text, "Turn 3 - Player 1 - Main")
	assert_string_contains(board.combat_ui.avatars[1].mana_text(), "Pri")
	assert_false(board.draw_button.visible)
	assert_true(board.next_button.visible)


# --- cards and their state -------------------------------------------------------------------------------------

func test_owner_controller_face_and_entered_turn_are_set():
	var state := _state(_wrap('"turn": {"number": 5}, "players": {"1": {"creatures": [
			{"card": "Battle Smith", "controller": 2, "entered_turn": 5, "face": "down"}]}}'))
	await load_board(state)
	var card: Card = game.player(1).cards_in_grid("creatures")[0]
	assert_eq(card.owner_id, 1)
	assert_eq(card.controller_id, 2)
	assert_eq(card.entered_turn, 5)
	assert_false(card.is_faceup)


func test_a_card_owned_by_the_other_player_in_a_zone():
	var state := _state(_wrap('"players": {"1": {"relics": [{"card": "Garbage Heap", "owner": 2}]}}'))
	await load_board(state)
	var card: Card = game.player(1).cards_in_grid("relics")[0]
	assert_eq(card.owner_id, 2)


func test_tokens_are_restored():
	var state := _state(_wrap('"players": {"1": {"creatures": [{"card": "Battle Smith", "tokens": {"tech": 2}}]}}'))
	await load_board(state)
	var card: Card = game.player(1).cards_in_grid("creatures")[0]
	assert_eq(card.tokens.get_token_count("tech"), 2)


func test_damage_modifiers_and_grants_with_sources_by_id():
	var state := _state(_wrap('"players": {"1": {
			"relics": [{"card": "Garbage Heap", "id": "heap"}],
			"creatures": [{"card": "Battle Smith", "id": "smith", "damage": {"Guard": 1},
				"modifiers": [{"stat": "Strike", "amount": 3, "expiry": "permanent", "source": "heap"}],
				"grants": [{"keyword": "Indomitable", "expiry": "permanent"}]}]}}'))
	await load_board(state)
	var smith: Card = game.player(1).cards_in_grid("creatures")[0]
	var heap: Card = game.player(1).cards_in_grid("relics")[0]
	assert_eq(game.stats.damage_on(smith, "Guard"), 1)
	assert_eq(game.stats.current(smith, "Strike"), game.stats.base(smith, "Strike") + 3)
	var exported: Dictionary = game.stats.export_card(smith, func(c): return c.canonical_name)
	assert_eq(exported["modifiers"][0]["source"], heap.canonical_name, "The id resolved to the card")
	assert_eq(game.stats.grants_of(smith).size(), 1)
	assert_true(game.keywords.has(smith, "Indomitable"))


func test_a_creature_at_zero_zero_is_not_destroyed_by_loading():
	var state := _state(_wrap('"definitions": {"Test 1/1": {"Type": "Creature", "Strike": 1, "Guard": 1, "Cost": 1, "Pips": "", "_domains": ["Innovation"]}},
			"players": {"1": {"creatures": [{"card": "Test 1/1", "damage": {"Strike": 1, "Guard": 1}}]}}'))
	await load_board(state)
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 1, "Loaded, not destroyed")


func test_definitions_of_test_cards_are_registered():
	var state := _state(_wrap('"definitions": {"Test 9/9": {"Type": "Creature", "Strike": 9, "Guard": 9, "Cost": 1, "Pips": "", "_domains": ["Innovation"]}},
			"players": {"1": {"creatures": ["Test 9/9"]}}'))
	await load_board(state)
	assert_eq(game.stats.base(game.player(1).cards_in_grid("creatures")[0], "Strike"), 9)


func test_embody_attachments_are_rebuilt_without_paying():
	var state := _state(_wrap('"players": {"1": {"creatures": [{"card": "Spirit Wielder", "attached": ["Beetle Brawler"]}],
			"energy": [{"card": "Scrap Cannon", "tapped": true}]}}'))
	await load_board(state)
	var host: Card = game.player(1).cards_in_grid("creatures")[0]
	assert_eq(host.attachments.size(), 1)
	assert_eq(host.attachments[0].canonical_name, "Beetle Brawler")
	assert_eq(game.player(1).cards_in_grid("energy").size(), 1, "The attached card left the energy zone")
	assert_eq(game.player(1).cards_in_grid("energy")[0].card_rotation, 90, "Nothing was paid or untapped")


func test_a_forced_blocker_is_restored():
	var state := _state(_wrap('"turn": {"number": 3}, "players": {
			"1": {"creatures": [{"card": "Battle Smith", "id": "attacker"}]},
			"2": {"creatures": [{"card": "Battle Smith", "forced_blocker": {"target": "attacker", "turn": 3}}]}}'))
	await load_board(state)
	var blocker: Card = game.player(2).cards_in_grid("creatures")[0]
	var record: Dictionary = blocker.get_meta("fate_forced_blocker")
	assert_eq(record["target"], game.player(1).cards_in_grid("creatures")[0])
	assert_eq(record["turn"], 3)


func test_a_built_deck_has_the_requested_size():
	var state := _state(_wrap('"players": {"1": {"deck": {"build": true, "size": 25}}}'))
	await load_board(state)
	assert_eq(FateZones.container("deck", 1).get_card_count(), 25)


func test_rng_is_restored_last():
	var state := _state(_wrap('"rng": {"seed": "12345", "state": "6789"}, "players": {"1": {"deck": {"build": true, "size": 10}}}'))
	await load_board(state)
	assert_eq(cfc.game_rng.seed, 12345)
	assert_eq(cfc.game_rng.state, 6789)


# --- round trips -------------------------------------------------------------------------------------------------------

func test_capture_after_load_gives_the_same_table():
	for fixture in ["empty_main_phase", "mana_and_energy", "goblin_attack_ready"]:
		await load_board(fixture)
		var first := capture_board()
		await load_board(first)
		var second := capture_board()
		assert_eq(second.data, first.data, "%s: load -> capture is stable" % fixture)


func test_a_built_table_round_trips_through_json():
	await put_creature(1, 3, 2, {"Savage": 1}, true)
	await put_energy(1, "Beetle Brawler", true)
	await put_energy(2, "Scrap Cannon")
	await put_on_table(2, "Garbage Heap", "relics")
	game.stats.apply_damage(game.player(1).cards_in_grid("creatures")[0], "Guard", 1)
	var before := capture_board()
	var again := FateBoardState.from_json(before.to_json())
	await load_board(again)
	assert_eq(capture_board().data, before.data)


# --- refusing and going back ---------------------------------------------------------------------------------------------

func test_an_invalid_state_changes_nothing():
	var creature := await put_creature(1, 2, 2)
	var result: Dictionary = await game.load_board_state(_state(_wrap('"players": {"1": {"hand": ["Battel Smith"]}}')))
	assert_false(result["ok"])
	assert_string_contains(result["errors"][0], "players.1.hand[0].card")
	assert_true(is_instance_valid(creature) and creature.is_inside_tree(), "The table is untouched")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 1)


func test_a_failure_while_loading_goes_back_to_the_previous_table():
	var creature := await put_creature(1, 2, 2)
	await put_energy(1, "Beetle Brawler", true)
	var before := capture_board()
	var result: Dictionary = await game.load_board_state(FateBoardStateFiles.load_state("goblin_attack_ready"),
			{"_test_fail": true})
	assert_false(result["ok"])
	assert_string_contains(" ".join(result["warnings"]), "previous table was restored")
	var after := capture_board()
	assert_eq(after.data, before.data, "The previous table is back")
	assert_eq(game.phase, FateGame.Phase.ENERGY)


func test_a_bare_declare_step_is_loaded_but_an_unsupported_phase_is_refused():
	var good: Dictionary = await game.load_board_state(_state(_wrap('"turn": {"phase": "combat_declare"}')))
	assert_true(good["ok"], str(good["errors"]))
	assert_eq(game.combat.step, FateCombat.Step.DECLARE)
	var bad: Dictionary = await game.load_board_state(_state(_wrap('"turn": {"phase": "combat_resolve"}')))
	assert_false(bad["ok"])
	assert_string_contains(bad["errors"][0], "mid-resolution")
	assert_eq(game.phase, Phase.COMBAT_DECLARE, "Still the previous table")


func test_loading_twice_in_a_row_is_fine():
	await load_board("goblin_attack_ready")
	await load_board("empty_main_phase")
	await load_board("goblin_attack_ready")
	assert_eq(game.phase, Phase.COMBAT_DECLARE)
	assert_eq(game.creatures_in_play().size(), 3)


func test_the_loaded_game_signals():
	var seen := []
	game.board_state_loaded.connect(func(name): seen.append(name))
	await load_board("empty_main_phase")
	assert_eq(seen, ["Empty main phase"])


func test_the_launch_argument_is_found():
	assert_eq(FateBoard.board_from_args(["--board=goblin_attack_ready"]), "goblin_attack_ready")
	assert_eq(FateBoard.board_from_args(["--verbose", "--board=res://boards/x.json"]), "res://boards/x.json")
	assert_eq(FateBoard.board_from_args(["--verbose"]), "")
	assert_eq(FateBoard.board_from_args([]), "")


func test_every_feature_board():
	await load_board("every_feature")
	assert_eq(game.active_id, 2)
	assert_eq(game.turn_number, 6)
	assert_eq(FateZones.container("deck", 1).get_top_card().canonical_name, "Scrap Recycler")
	assert_eq(FateZones.container("removed", 1).get_card_count(), 1)
	assert_eq(FateZones.container("discard", 1).get_card_count(), 1)
	var creatures := FateZones.grid("creatures", 1)
	assert_null(creatures.get_slot(1).occupying_card)
	var test_card: Card = creatures.get_slot(2).occupying_card
	assert_eq(test_card.canonical_name, "Test 3/3 Savage")
	assert_eq(test_card.card_rotation, 90)
	assert_eq(game.stats.current(test_card, "Guard"), 4, "3 + the +1 modifier")
	assert_true(game.keywords.has(test_card, "Savage"), "Innate keyword of the defined card")
	assert_eq(game.player(1).cards_in_grid("occupied")[0].card_rotation, 90, "Occupied is tilted by default")
	assert_eq(game.player(1).cards_in_grid("relics")[0].tokens.get_token_count("tech"), 1)
	assert_eq(FateZones.grid("world", 0).get_slot(0).occupying_card.canonical_name, "Equal Footing")
	assert_eq(FateZones.grid("field", 2).get_slot(0).occupying_card.canonical_name, "Battle Ready")
	assert_eq(FateZones.container("deck", 2).get_card_count(), 20)
	var wielder: Card = FateZones.grid("creatures", 2).get_slot(0).occupying_card
	assert_eq(wielder.attachments.size(), 1)
	assert_eq(game.player(2).cards_in_grid("energy").size(), 4)
	assert_true(FateZones.grid("creatures", 2).get_slot(1).occupying_card.has_meta("fate_forced_blocker"))
	assert_eq(board.bottom_id, 2)


func test_the_energy_phase_with_the_choice_open_can_go_on():
	await load_board("energy_phase_choice")
	assert_eq(game.phase, Phase.ENERGY)
	assert_eq(game.active_id, 2)
	assert_true(game.can_draw_extra_card())
	assert_true(game.draw_extra_card())
	assert_eq(game.phase, Phase.MAIN, "Drawing made the choice")
	await wait_seconds(0.4)
	assert_eq(_names(FateZones.container("hand", 2).get_all_cards()),
			["Beetle Brawler", "Scrap Cannon", "Battle Smith", "Ancient Tree"], "The top of the deck came into the hand")
