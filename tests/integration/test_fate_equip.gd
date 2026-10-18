extends "res://tests/FateCommon.gd"
# Equipment and persisting-spell slots (FateEquip, game.equip): relics on creatures, the field and world
# spell slots, spells with a duration, and the board-state round trip of an equipped relic.

const RELIC := "Dragon's Tooth"
const TOKEN_RELIC := "Battle Hammer Token"
const FIELD_A := "Eldritch Knowledge"
const FIELD_B := "Recovering Resources"
const WORLD_A := "Equal Footing"
const WORLD_B := "Broadening Influence"


# Records on_leave for the cards it is registered for
class Recorder:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var log: Array = []

	func _init(name_of_card := "") -> void:
		card_name = name_of_card

	func on_leave(_card: Card, dest: String) -> void:
		log.append(["leave", dest])


func _to_main_with_mana() -> void:
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()


func _discard_names(pid: int) -> Array:
	return FateZones.container("discard", pid).get_all_cards().map(func(c): return c.canonical_name)


# --- equipping ---------------------------------------------------------------------------------

func test_equip_attaches_the_relic_to_the_creature() -> void:
	var host := await put_creature(1, "Battle Smith")
	var relic := await put_on_table(1, RELIC, "relics")
	var heard := []
	game.equip.equipped.connect(func(r, c): heard.append([r, c]))
	assert_true(game.equip.equip(relic, host))
	assert_eq(game.equip.host_of(relic), host)
	assert_eq(game.equip.relics_on(host), [relic])
	assert_eq(heard, [[relic, host]], "the equipped signal")
	assert_true(relic in host.attachments, "a framework attachment, it follows the creature")
	assert_eq(relic.current_host_card, host)
	assert_eq(FateZones.zone_of(relic), "relics", "still a relic zone permanent")
	assert_true(relic in game.player(1).cards_in_grid("relics"), "still in its slot, so still targetable")
	assert_true(relic in game.card_effects.table_cards(), "and on the table for the card scripts")


func test_equip_works_on_an_occupied_creature_and_for_the_other_players_creature() -> void:
	var occupied := await put_creature(1, "Battle Smith", 1, {}, false, "occupied")
	var relic := await put_on_table(1, RELIC, "relics")
	assert_true(game.equip.equip(relic, occupied))
	var enemy := await put_creature(2, "Moral Captain")
	var relic2 := await put_on_table(1, RELIC, "relics")
	assert_true(game.equip.equip(relic2, enemy))
	assert_eq(game.equip.host_of(relic2), enemy)


func test_a_second_equip_is_refused_and_the_first_stays() -> void:
	var a := await put_creature(1, "Battle Smith")
	var b := await put_creature(1, "Moral Captain")
	var relic := await put_on_table(1, RELIC, "relics")
	assert_true(game.equip.equip(relic, a))
	assert_false(game.equip.equip(relic, b), "cannot be changed once equipped")
	assert_false(game.equip.equip(relic, a), "nor equipped again")
	assert_eq(game.equip.host_of(relic), a)
	assert_eq(game.equip.relics_on(b), [])


func test_several_relics_on_one_creature() -> void:
	var host := await put_creature(1, "Battle Smith")
	var r1 := await put_on_table(1, RELIC, "relics")
	var r2 := await put_on_table(1, TOKEN_RELIC, "relics")
	assert_true(game.equip.equip(r1, host))
	assert_true(game.equip.equip(r2, host))
	assert_eq(game.equip.relics_on(host).size(), 2)


func test_equip_refuses_what_is_not_a_relic_on_the_table_or_a_creature_in_play() -> void:
	var host := await put_creature(1, "Battle Smith")
	var other := await put_creature(1, "Moral Captain")
	var relic := await put_on_table(1, RELIC, "relics")
	assert_false(game.equip.equip(other, host), "a creature is not a relic")
	assert_false(game.equip.equip(relic, relic), "a relic is not a creature")
	var in_hand := await put_in_hand(1, RELIC)
	assert_false(game.equip.equip(in_hand, host), "the relic has to be on the table")
	var energy := await put_energy(1, RELIC)
	assert_false(game.equip.equip(energy, host), "an energy card is not a table relic")
	assert_eq(game.equip.host_of(relic), null)


func test_the_host_leaving_sends_the_relic_to_its_owners_discard_pile() -> void:
	var host := await put_creature(2, "Battle Smith")
	var relic := await put_on_table(1, RELIC, "relics")
	game.equip.equip(relic, host)
	var slot = relic._placement_slot
	assert_true(game.effects.destroy(host))
	await wait_seconds(0.3)
	assert_eq(relic.get_parent(), FateZones.container("discard", 1), "the relic's owner's discard pile")
	assert_eq(host.get_parent(), FateZones.container("discard", 2))
	assert_null(game.equip.host_of(relic))
	assert_null(slot.occupying_card, "the relic slot is free again")
	assert_eq(game.player(1).cards_in_grid("relics"), [])
	assert_eq(host.attachments, [])


func test_the_host_returning_to_the_hand_sends_the_relic_to_the_discard_pile() -> void:
	var host := await put_creature(1, "Battle Smith")
	var relic := await put_on_table(1, RELIC, "relics")
	game.equip.equip(relic, host)
	host.move_to(FateZones.container("hand", 1), -1, null, ["Scripted"])
	await wait_seconds(0.3)
	assert_eq(relic.get_parent(), FateZones.container("discard", 1))
	assert_true(RELIC in _discard_names(1))


func test_a_relic_token_ceases_to_exist_with_its_host() -> void:
	var host := await put_creature(1, "Battle Smith")
	var token := await put_on_table(1, TOKEN_RELIC, "relics")
	game.equip.equip(token, host)
	game.effects.destroy(host)
	await wait_seconds(0.3)
	assert_false(is_instance_valid(token) and not token.is_queued_for_deletion(), "the token is gone")
	assert_false(TOKEN_RELIC in _discard_names(1), "and did not go to the discard pile")
	assert_eq(game.player(1).cards_in_grid("relics"), [])


func test_the_relic_leaving_alone_frees_the_creature() -> void:
	var host := await put_creature(1, "Battle Smith")
	var relic := await put_on_table(1, RELIC, "relics")
	game.equip.equip(relic, host)
	assert_true(game.effects.destroy(relic))
	await wait_seconds(0.3)
	assert_eq(game.equip.relics_on(host), [])
	assert_eq(host.attachments, [])
	assert_true(RELIC in _discard_names(1))
	assert_eq(host.get_parent(), cfc.NMAP.board, "the creature is untouched")


func test_what_the_relic_grants_ends_with_it() -> void:
	var host := await put_creature(1, "Battle Smith")
	var relic := await put_on_table(1, RELIC, "relics")
	game.equip.equip(relic, host)
	var base := game.stats.current(host, "Strike")
	game.stats.add_modifier(host, "Strike", 2, FateStats.EXPIRY_PERMANENT, relic)
	game.stats.grant_keyword(host, "Charge", 1, FateStats.EXPIRY_PERMANENT, relic)
	assert_eq(game.stats.current(host, "Strike"), base + 2)
	assert_true(game.keywords.has(host, "Charge"))
	game.effects.destroy(host)
	await wait_seconds(0.3)
	assert_eq(game.stats.modifier_total(host, "Strike"), 0)
	var left_over := game.stats.grants_of(host)
	assert_eq(left_over.size(), 0)


func test_the_relic_script_hears_it_left() -> void:
	var fx := Recorder.new(RELIC)
	game.card_effects.register(fx)
	var host := await put_creature(1, "Battle Smith")
	var relic := await put_on_table(1, RELIC, "relics")
	game.equip.equip(relic, host)
	game.effects.destroy(host)
	await wait_seconds(0.3)
	assert_eq(fx.log, [["leave", "discard"]])


func test_release_all_and_unequip() -> void:
	var host := await put_creature(1, "Battle Smith")
	var r1 := await put_on_table(1, RELIC, "relics")
	var r2 := await put_on_table(1, RELIC, "relics")
	game.equip.equip(r1, host)
	game.equip.equip(r2, host)
	assert_true(game.equip.unequip(r1))
	assert_false(game.equip.unequip(r1), "not equipped any more")
	assert_eq(game.equip.release_all(host), 1)
	await wait_seconds(0.3)
	assert_eq(_discard_names(1).count(RELIC), 2)
	assert_eq(host.get_parent(), cfc.NMAP.board)


# --- the field slot ----------------------------------------------------------------------------

func test_the_field_slot_queries() -> void:
	assert_null(game.equip.field_spell(1))
	assert_null(game.equip.world_spell())
	var field := await put_on_table(1, FIELD_A, "field")
	var world := await put_on_table(2, WORLD_A, "world")
	assert_eq(game.equip.field_spell(1), field)
	assert_null(game.equip.field_spell(2))
	assert_eq(game.equip.world_spell(), world)


func test_a_new_field_spell_replaces_the_old_one() -> void:
	await _to_main_with_mana()
	var first := await put_in_hand(1, FIELD_A)
	var second := await put_in_hand(1, FIELD_B)
	assert_true(game.play_from_hand(first))
	await wait_seconds(0.3)
	assert_eq(game.equip.field_spell(1), first)
	assert_true(game.play_from_hand(second))
	await wait_seconds(0.3)
	assert_eq(game.equip.field_spell(1), second, "the new one holds the slot")
	assert_eq(first.get_parent(), FateZones.container("discard", 1), "the old one is in the discard pile")
	assert_eq(game.player(1).cards_in_grid("field").size(), 1)


func test_the_field_slots_of_the_players_are_independent() -> void:
	var theirs := await put_on_table(2, FIELD_A, "field")
	await _to_main_with_mana()
	var mine := await put_in_hand(1, FIELD_B)
	assert_true(game.play_from_hand(mine))
	await wait_seconds(0.3)
	assert_eq(game.equip.field_spell(2), theirs, "the opponent's field spell stays")
	assert_eq(game.equip.field_spell(1), mine)
	assert_eq(theirs.get_parent(), cfc.NMAP.board)


func test_a_field_spell_that_lands_by_a_scripted_move_replaces_too() -> void:
	# Flip cast, cast from the discard pile ...: moves tagged "Scripted", no play from the hand
	var old := await put_on_table(1, FIELD_A, "field")
	var new_spell := await put_in_hand(1, FIELD_B)
	new_spell.move_to(cfc.NMAP.board, -1, null, ["Scripted"])
	await wait_seconds(0.5)
	assert_eq(game.equip.field_spell(1), new_spell)
	assert_eq(old.get_parent(), FateZones.container("discard", 1))


func test_a_play_that_is_refused_replaces_nothing() -> void:
	# Player 1 has no mana: the play fails and the field spell must stay
	var old := await put_on_table(1, FIELD_A, "field")
	await empty_hand(1)
	go_to_main()
	var new_spell := await put_in_hand(1, FIELD_B)
	assert_false(game.play_from_hand(new_spell))
	new_spell.move_to(cfc.NMAP.board)
	await wait_seconds(0.4)
	assert_eq(game.equip.field_spell(1), old)
	assert_eq(new_spell.get_parent(), FateZones.container("hand", 1))


func test_the_replaced_field_spell_hears_it_left() -> void:
	var fx := Recorder.new(FIELD_A)
	game.card_effects.register(fx)
	await put_on_table(1, FIELD_A, "field")
	await _to_main_with_mana()
	var spell := await put_in_hand(1, FIELD_B)
	game.play_from_hand(spell)
	await wait_seconds(0.3)
	assert_eq(fx.log, [["leave", "discard"]])


# --- the world slot ----------------------------------------------------------------------------

func test_a_new_world_spell_replaces_whoever_owned_the_old_one() -> void:
	var theirs := await put_on_table(2, WORLD_B, "world")
	await _to_main_with_mana()
	var mine := await put_in_hand(1, WORLD_A)
	assert_true(game.play_from_hand(mine))
	await wait_seconds(0.3)
	assert_eq(game.equip.world_spell(), mine)
	assert_eq(theirs.get_parent(), FateZones.container("discard", 2), "to its OWNER's discard pile")
	assert_eq(FateZones.grid("world", 0).get_all_slots().size(), 1)


func test_a_world_spell_does_not_touch_the_field_spells() -> void:
	var field := await put_on_table(1, FIELD_A, "field")
	await _to_main_with_mana()
	var world := await put_in_hand(1, WORLD_A)
	assert_true(game.play_from_hand(world))
	await wait_seconds(0.3)
	assert_eq(game.equip.field_spell(1), field)
	assert_eq(game.equip.world_spell(), world)


# --- durations ---------------------------------------------------------------------------------

func _end_of_turn(pid: int) -> void:
	game.end_phase_begins.emit(pid)
	await wait_seconds(0.3)


func test_a_duration_counts_the_controllers_turns_and_expires() -> void:
	var fx := Recorder.new(FIELD_A)
	game.card_effects.register(fx)
	var spell := await put_on_table(1, FIELD_A, "field")
	game.equip.add_duration(spell, 2)
	assert_eq(game.equip.remaining(spell), 2)
	await _end_of_turn(2)
	assert_eq(game.equip.remaining(spell), 2, "the opponent's turn does not count")
	await _end_of_turn(1)
	assert_eq(game.equip.remaining(spell), 1)
	assert_eq(game.equip.field_spell(1), spell)
	var expired := []
	game.equip.duration_expired.connect(func(c): expired.append(c))
	await _end_of_turn(1)
	assert_eq(expired, [spell])
	assert_null(game.equip.field_spell(1))
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))
	assert_eq(fx.log, [["leave", "discard"]], "its script hears on_leave")


func test_a_duration_in_turns_of_either_player() -> void:
	var spell := await put_on_table(1, WORLD_A, "world")
	game.equip.add_duration(spell, 2, "turn")
	await _end_of_turn(1)
	await _end_of_turn(2)
	assert_null(game.equip.world_spell())
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))


func test_remaining_is_minus_one_without_a_duration() -> void:
	var spell := await put_on_table(1, FIELD_A, "field")
	assert_eq(game.equip.remaining(spell), -1)
	await _end_of_turn(1)
	assert_eq(game.equip.field_spell(1), spell, "nothing expires without a countdown")


func test_a_replaced_spell_forgets_its_duration() -> void:
	var spell := await put_on_table(1, FIELD_A, "field")
	game.equip.add_duration(spell, 3)
	game.equip.send_to_discard(spell)
	await wait_seconds(0.3)
	assert_eq(game.equip.remaining(spell), -1)


# --- board state -------------------------------------------------------------------------------

const EQUIPPED_STATE := '{"format": "fate-board-state", "version": 1,
	"turn": {"number": 2, "active_player": 1, "phase": "main", "energy_choice": "energy"},
	"players": {
		"1": {"creatures": [{"card": "Battle Smith", "id": "host"}, {"card": "Moral Captain"}],
			"relics": [{"card": "Dragon\'s Tooth"}, {"card": "Dragon\'s Tooth", "id": "tooth", "equipped_to": "host"}]},
		"2": {"creatures": [{"card": "Righteous Guard", "id": "foe"}],
			"relics": [{"card": "Battle Hammer Token", "equipped_to": "foe"}]}}}'


func test_an_equipped_relic_round_trips_through_the_board_state() -> void:
	await load_board(FateBoardState.from_json(EQUIPPED_STATE))
	var host: Card = game.player(1).cards_in_grid("creatures")[0]
	var relics: Array = game.player(1).cards_in_grid("relics")
	assert_eq(relics.size(), 2)
	assert_eq(game.equip.host_of(relics[0]), null, "the first relic is not equipped")
	assert_eq(game.equip.host_of(relics[1]), host)
	assert_eq(game.equip.relics_on(host), [relics[1]])
	var foe: Card = game.player(2).cards_in_grid("creatures")[0]
	assert_eq(game.equip.relics_on(foe).size(), 1)
	assert_eq(game.player(1).cards_in_grid("creatures")[1].attachments, [])
	var first := capture_board()
	assert_not_null(first)
	var relic_entries: Array = first.data["players"]["1"]["relics"]
	assert_eq(relic_entries.size(), 2, "the relic slots are kept")
	assert_true(relic_entries[1].has("equipped_to"), "the equipped relic says whom it is on")
	assert_false(first.data["players"]["1"]["creatures"][0].has("attached"), "and it is not listed twice")
	await load_board(first)
	var second := capture_board()
	assert_eq(second.data, first.data, "capture -> load -> capture is stable")
	assert_eq(game.equip.relics_on(game.player(1).cards_in_grid("creatures")[0]).size(), 1)
	# Through JSON as well
	await load_board(FateBoardState.from_json(first.to_json()))
	assert_eq(capture_board().data, first.data)


func test_modifiers_sourced_by_an_equipped_relic_round_trip() -> void:
	await load_board(FateBoardState.from_json(EQUIPPED_STATE))
	var host: Card = game.player(1).cards_in_grid("creatures")[0]
	var relic: Card = game.equip.relics_on(host)[0]
	game.stats.add_modifier(host, "Strike", 2, FateStats.EXPIRY_PERMANENT, relic)
	var first := capture_board()
	await load_board(first)
	var host2: Card = game.player(1).cards_in_grid("creatures")[0]
	assert_eq(game.stats.current(host2, "Strike"), game.stats.base(host2, "Strike") + 2)
	assert_eq(capture_board().data, first.data)


func test_an_equipped_to_that_names_nobody_is_an_error() -> void:
	var state := FateBoardState.from_json('{"format": "fate-board-state", "version": 1,
		"players": {"1": {"relics": [{"card": "Dragon\'s Tooth", "equipped_to": "nobody"}]}}}')
	assert_false(state.validate().is_empty())
