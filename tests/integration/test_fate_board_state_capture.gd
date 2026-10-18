extends "res://tests/FateCommon.gd"
# Tests of FateGame.capture_board_state / FateBoardStateCapture: the live table as board state data.
# Format: docs/FATE_BOARD_STATE.md. Tables are built with the helpers of tests/FateCommon.gd.

const Phase := FateGame.Phase
const Forced := preload("res://src/custom/fate/keywords/KwForcedBlocker.gd")


func _capture(opts := {}) -> FateBoardState:
	var state := game.capture_board_state(opts)
	assert_not_null(state, "Captured: %s" % str(game.board_state_errors))
	return state


# The captured zone as plain card names (null for an empty slot)
func _names(state: FateBoardState, pid: int, zone: String) -> Array:
	var names := []
	for entry in state.zone(pid, zone):
		names.append(entry["card"] if entry is Dictionary else null)
	return names


func _has_stats_export() -> bool:
	return game.stats.has_method("export_card")


# --- the whole table ---------------------------------------------------------------------------------

func test_a_fresh_game_is_captured_and_valid():
	var state := _capture({"name": "Fresh", "description": "turn one"})
	assert_eq(state.validate(), [] as Array[String])
	assert_eq(state.state_name(), "Fresh")
	assert_eq(state.data["description"], "turn one")
	var turn: Dictionary = state.data["turn"]
	assert_eq(turn["number"], 1)
	assert_eq(turn["active_player"], 1)
	assert_eq(turn["phase"], "energy")
	assert_eq(turn["energy_choice"], "")
	for pid in [1, 2]:
		assert_eq(state.player(pid)["life"], LIFE)
		assert_eq(state.zone(pid, "hand").size(), FateZones.container("hand", pid).get_card_count())
		assert_eq(state.zone(pid, "doctrines").size(), 3, "Three doctrines in play")
		assert_eq(state.zone(pid, "deck").size(), FateZones.container("deck", pid).get_card_count())


func test_capture_does_not_change_the_game_and_is_repeatable():
	await put_creature(1, 2, 2)
	await put_energy(1, "Garbage Heap", true)
	var before_cards := get_tree().get_nodes_in_group("cards").size()
	var first := _capture()
	var second := _capture()
	assert_eq(first.data, second.data, "Capturing twice gives the same data")
	assert_eq(get_tree().get_nodes_in_group("cards").size(), before_cards)
	assert_eq(game.board_state_errors, [] as Array[String])


func test_json_round_trip_keeps_the_data():
	game.draw_extra_card()
	var a := await put_creature(1, 3, 2)
	var b := await put_creature(1, 1, 1, {}, true)
	if _has_stats_export():
		game.stats.add_modifier(a, "Strike", 2, "end_of_turn", b)
		game.stats.grant_keyword(b, "Savage", 1, "permanent", a)
		game.stats.apply_damage(a, "Guard", 1)
	await put_energy(1, "Garbage Heap", true)
	var state := _capture()
	var again := FateBoardState.from_json(state.to_json())
	assert_eq(again.data, state.data, "from_json(to_json()) is the same data")
	assert_eq(again.validate(), [] as Array[String])


func test_life_turn_and_rng_are_captured():
	game.player(1).life = 7
	game.player(2).life = 3
	cfc.game_rng.seed = 123456789012345
	cfc.game_rng.randi()
	var state := _capture()
	assert_eq(state.player(1)["life"], 7)
	assert_eq(state.player(2)["life"], 3)
	assert_eq(state.data["rng"]["seed"], "123456789012345", "The seed is text")
	assert_eq(state.data["rng"]["state"], str(cfc.game_rng.state), "The state is text")


func test_main_phase_and_energy_choice():
	game.draw_extra_card()
	assert_eq(game.phase, Phase.MAIN)
	var state := _capture()
	assert_eq(state.data["turn"]["phase"], "main")
	assert_eq(state.data["turn"]["energy_choice"], "draw")
	assert_eq(state.validate(), [] as Array[String])


# --- zone order -----------------------------------------------------------------------------------------

func test_hand_is_listed_left_to_right():
	await empty_hand(1)
	await put_in_hand(1, "Battle Smith")
	await put_in_hand(1, "Garbage Heap")
	await put_in_hand(1, "Moral Captain")
	var hand_cards: Array = FateZones.container("hand", 1).get_all_cards()
	var expected := []
	for c in hand_cards:
		expected.append(c.canonical_name)
	var state := _capture()
	assert_eq(_names(state, 1, "hand"), expected, "Child order of the hand")
	assert_eq(expected.size(), 3)


func test_piles_are_listed_top_first():
	var pile: Pile = FateZones.container("discard", 1)
	var top: Card = pile.get_top_card() if pile.get_card_count() > 0 else null
	assert_null(top, "Test setup: empty discard")
	for card_name in ["Battle Smith", "Garbage Heap", "Moral Captain"]:
		var card: Card = cfc.instance_card(card_name)
		pile.add_child(card)
		card.assign_owner(1)
		card._determine_idle_state()
	var state := _capture()
	assert_eq(_names(state, 1, "discard"), ["Moral Captain", "Garbage Heap", "Battle Smith"],
			"The last child (the top card) comes first")
	var deck_pile: Pile = FateZones.container("deck", 1)
	var deck_top: Card = deck_pile.get_top_card()
	assert_eq(_names(state, 1, "deck")[0], deck_top.canonical_name, "The next drawn card is first")
	assert_eq(state.zone(1, "deck").size(), deck_pile.get_card_count(), "The deck is an explicit list")
	assert_false(state.zone(1, "deck").is_empty())


func test_deck_cards_default_to_face_down():
	var state := _capture()
	for entry in state.zone(1, "deck"):
		assert_false(entry.has("face"), "Face-down is the deck default")
	var drawn: Card = FateZones.container("deck", 1).get_top_card()
	drawn.set_is_faceup(true, true)
	var after := _capture()
	assert_eq(after.zone(1, "deck")[0].get("face"), "up", "A face-up deck card is written")


func test_grids_are_listed_by_slot_with_gaps():
	var grid := FateZones.grid("creatures", 1)
	var card := await put_creature(1, 2, 2)
	var far_slot := grid.get_slot(3)
	var other := await put_creature(1, 1, 1)
	# Move the second creature to slot 3 by hand: leaves slots 1, 2 empty
	far_slot.occupying_card = other
	other._placement_slot = far_slot
	for i in grid.get_slot_count():
		var s := grid.get_slot(i)
		if s != far_slot and s.occupying_card == other:
			s.occupying_card = null
	var state := _capture()
	var creatures := state.zone(1, "creatures")
	assert_eq(creatures.size(), 4, "Trailing empty slots are trimmed")
	assert_eq(creatures[0]["card"], card.canonical_name)
	assert_null(creatures[1])
	assert_null(creatures[2])
	assert_eq(creatures[3]["card"], other.canonical_name)


func test_energy_by_slot_tapped_and_faces():
	await put_energy(1, "Garbage Heap")
	await put_energy(1, "Battle Smith", true)
	var state := _capture()
	var energy := state.zone(1, "energy")
	assert_eq(energy.size(), 2)
	assert_eq(energy[0], {"card": "Garbage Heap"}, "Face-down untapped energy is all defaults")
	assert_eq(energy[1], {"card": "Battle Smith", "tapped": true})
	assert_eq(state.validate(), [] as Array[String])


func test_doctrines_are_a_card_list():
	var state := _capture()
	var doctrines := state.zone(1, "doctrines")
	assert_true(doctrines is Array)
	assert_eq(doctrines.size(), 3)
	for entry in doctrines:
		assert_true(FateData.DOCTRINES.has(entry["card"]))
	assert_false(state.player(1)["doctrines"] is String, "Not \"auto\"")


func test_world_is_the_shared_grid():
	var world := game.place_card_on_table("Battle Smith", 1, "creatures")
	assert_not_null(world)
	var world_grid := FateZones.grid("world", 0)
	var slot: BoardPlacementSlot = world_grid.get_slot(0)
	var card: Card = cfc.instance_card("Garbage Heap")
	cfc.NMAP.board.add_child(card)
	card.assign_owner(2)
	card.position = slot.global_position
	card._placement_slot = slot
	slot.occupying_card = card
	card.state = Card.CardState.ON_PLAY_BOARD
	await get_tree().process_frame
	var state := _capture()
	assert_eq(state.data["world"].size(), 1)
	assert_eq(state.data["world"][0]["card"], "Garbage Heap")
	assert_eq(state.data["world"][0]["owner"], 2, "World cards keep their owner")


# --- per card -----------------------------------------------------------------------------------------

func test_tilted_creature_and_occupied_default():
	var guard := await put_creature(1, 2, 2, {}, true)
	var ready := await put_creature(1, 1, 1)
	var worker := await put_creature(1, "Battle Smith", 1, {}, false, "occupied")
	var state := _capture()
	var creatures := state.zone(1, "creatures")
	assert_eq(creatures[0]["tapped"], true, "Guarding creature is tapped")
	assert_false(creatures[1].has("tapped"))
	var occupied := state.zone(1, "occupied")
	assert_false(occupied[0].has("tapped"), "A tilted occupied creature is the default")
	# An occupied creature that is upright is written explicitly
	worker.set_card_rotation(0)
	var upright := _capture()
	assert_eq(upright.zone(1, "occupied")[0]["tapped"], false)
	assert_not_null(guard)
	assert_not_null(ready)


func test_owner_controller_entered_turn_and_tokens():
	var card := await put_creature(1, 2, 2)
	card.controller_id = 2
	card.entered_turn = 3
	card.tokens.mod_token("tech", 2)
	await get_tree().process_frame
	var state := _capture()
	var entry: Dictionary = state.zone(1, "creatures")[0]
	assert_false(entry.has("owner"), "Owner is the zone's player")
	assert_eq(entry["controller"], 2)
	assert_eq(entry["entered_turn"], 3)
	assert_eq(entry["tokens"], {"tech": 2})
	assert_eq(state.validate(), [] as Array[String])


func test_ids_only_on_referenced_cards():
	var a := await put_creature(1, 3, 3)
	var b := await put_creature(1, 1, 1)
	var c := await put_creature(1, 2, 2)
	if _has_stats_export():
		game.stats.add_modifier(a, "Strike", 2, "end_of_turn", b)
		game.stats.grant_keyword(c, "Savage", 1, "end_of_turn", b)
	c.set_meta(Forced.META_KEY, {"target": a, "turn": game.turn_number})
	var state := _capture()
	var creatures := state.zone(1, "creatures")
	assert_true(creatures[0].has("id"), "a is the forced blocker's target")
	assert_eq(creatures[2]["forced_blocker"]["target"], creatures[0]["id"])
	assert_eq(creatures[2]["forced_blocker"]["turn"], game.turn_number)
	if _has_stats_export():
		assert_true(creatures[1].has("id"), "b is a modifier source")
		assert_eq(creatures[0]["modifiers"][0]["source"], creatures[1]["id"])
		assert_eq(creatures[2]["grants"][0]["source"], creatures[1]["id"])
		assert_ne(creatures[0]["id"], creatures[1]["id"])
	assert_false(creatures[2].has("id"), "c is not referred to")
	assert_eq(state.validate(), [] as Array[String])


func test_unreferenced_cards_have_no_id():
	await put_creature(1, 3, 3)
	await put_creature(1, 1, 1)
	var state := _capture()
	for entry in state.zone(1, "creatures"):
		assert_false(entry.has("id"))


func test_stat_state_is_captured_when_stats_can_export():
	if not _has_stats_export():
		pending("FateStats.export_card does not exist yet")
		return
	var a := await put_creature(1, 3, 3)
	game.stats.add_modifier(a, "Strike", 2, "permanent")
	game.stats.grant_keyword(a, "Savage", 2, "end_of_turn")
	game.stats.apply_damage(a, "Guard", 1)
	var state := _capture()
	var entry: Dictionary = state.zone(1, "creatures")[0]
	assert_eq(entry["damage"], {"Guard": 1})
	assert_eq(entry["modifiers"], [{"stat": "Strike", "amount": 2, "expiry": "permanent"}])
	assert_eq(entry["grants"], [{"keyword": "Savage", "value": 2}])
	assert_false(entry.has("id"), "No source, so no id")


func test_embodied_card_is_an_attachment():
	go_to_main()
	var wielder := await put_creature(1, "Spirit Wielder")
	var target := await put_energy(1, "Thrang's Crafting Table")
	for _i in range(3):
		await put_energy(1, "Garbage Heap")
	var kw = game.keywords.get_keyword("Embody")
	assert_true(kw.embody(wielder, target))
	await get_tree().process_frame
	var state := _capture()
	var entry: Dictionary = state.zone(1, "creatures")[0]
	assert_eq(entry["attached"], [{"card": "Thrang's Crafting Table"}], "Face-down is the attached default")
	assert_false("Thrang's Crafting Table" in _names(state, 1, "energy"), "Not in the energy grid any more")
	assert_eq(state.validate(), [] as Array[String])


# --- definitions ----------------------------------------------------------------------------------------

func test_runtime_cards_get_definitions_and_game_cards_do_not():
	var name := define_creature(4, 5)
	await put_creature(1, 4, 5)
	await put_creature(1, "Battle Smith")
	var state := _capture()
	var defs: Dictionary = state.data["definitions"]
	assert_true(defs.has(name), "The test creature is embedded")
	assert_false(defs.has("Battle Smith"), "A game card is not")
	assert_eq(defs[name]["Strike"], 4)
	assert_eq(defs[name]["Guard"], 5)
	assert_eq(defs[name]["Type"], "Creature")
	# The definition survives JSON
	var again := FateBoardState.from_json(state.to_json())
	assert_eq(again.data["definitions"], defs)
	assert_eq(again.validate(), [] as Array[String])


func test_definitions_are_json_safe():
	var name := define_creature(2, 2, {"Savage": 1})
	await put_creature(1, 2, 2, {"Savage": 1})
	var defs: Dictionary = _capture().data["definitions"]
	assert_eq(defs[name]["_innate_keywords"], {"Savage": 1})
	assert_true(JSON.stringify(defs) != "")


# --- refusals -------------------------------------------------------------------------------------------

func test_refuses_unsupported_phases():
	var cases := {
		Phase.MAINTENANCE: "maintenance",
		Phase.DRAW: "draw",
		Phase.COMBAT_INTERCEPT: "combat_intercept",
		Phase.COMBAT_RESOLVE: "combat_resolve",
		Phase.END: "end",
	}
	for phase in cases:
		game.turn.phase = phase
		var state := game.capture_board_state()
		assert_null(state, "Refused in %s" % cases[phase])
		assert_eq(game.board_state_errors.size(), 1)
		assert_true(game.board_state_errors[0].contains(FateBoardState.REFUSED_PHASES[cases[phase]]),
				"Says why: %s" % str(game.board_state_errors))
	game.turn.phase = Phase.ENERGY
	assert_not_null(game.capture_board_state(), "Allowed again")
	assert_eq(game.board_state_errors, [] as Array[String], "The errors are cleared")


func test_refuses_when_not_started_or_over():
	game.is_over = true
	assert_null(game.capture_board_state())
	assert_false(game.board_state_errors.is_empty())
	game.is_over = false
	game.is_started = false
	assert_null(game.capture_board_state())
	assert_false(game.board_state_errors.is_empty())
	game.is_started = true


func test_bare_declare_step_is_allowed():
	await put_creature(1, 2, 2)
	start_combat()
	var state := _capture()
	assert_eq(state.data["turn"]["phase"], "combat_declare")
	assert_eq(state.data["turn"]["energy_choice"], "draw")
	assert_eq(state.validate(), [] as Array[String])


func test_declared_attack_is_refused():
	var attacker := await put_creature(1, 2, 2)
	await put_creature(2, 1, 1, {}, true)
	start_combat()
	assert_true(game.combat.declare_attack(attacker, 2), "Test setup: attack declared")
	assert_null(game.capture_board_state())
	assert_false(game.board_state_errors.is_empty())


func test_open_reaction_window_is_refused():
	var window := FateCombat.ReactionWindow.new()
	window.player_id = 2
	game.combat.current_window = window
	assert_not_null(game.reactions.open_window(), "Test setup: a window is open")
	assert_null(game.capture_board_state())
	assert_true(game.board_state_errors[0].contains("reaction"), str(game.board_state_errors))
	window.close()
	assert_not_null(game.capture_board_state(), "Allowed again once the window is closed")
	game.combat.current_window = null
