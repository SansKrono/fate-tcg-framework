extends "res://tests/FateCommon.gd"
# Tests of FateStats export_card / import_card / refresh_all / clear_all, the stat half of the board
# state system (docs/FATE_BOARD_STATE.md). Cards are named by string ids instead of instance ids.

var _ids := {}
var _cards := {}


func before_each():
	await super.before_each()
	_ids = {}
	_cards = {}


# id_of for export_card: hands out "c1", "c2"... per card, and remembers the card for card_of
func _id_of(card: Card) -> String:
	var key := card.get_instance_id()
	if not _ids.has(key):
		_ids[key] = "c%d" % (_ids.size() + 1)
		_cards[_ids[key]] = card
	return _ids[key]


func _card_of(id: String):
	return _cards.get(id)


func _shown(card: Card) -> Array:
	return [card.properties["Strike"], card.properties["Guard"]]


func test_export_of_a_card_without_stat_state_is_empty():
	var card := await put_creature(1, 2, 2)
	assert_eq(game.stats.export_card(card, _id_of), {})
	assert_true(_ids.is_empty(), "No id was handed out")


func test_export_has_only_the_non_empty_keys():
	var card := await put_creature(1, 3, 3)
	game.stats.apply_damage(card, "Guard", 2)
	var data := game.stats.export_card(card, _id_of)
	assert_eq(data, {"damage": {"Guard": 2}})
	game.stats.add_modifier(card, "Strike", 1, "permanent")
	data = game.stats.export_card(card, _id_of)
	assert_eq(data.keys().size(), 2)
	assert_eq(data["modifiers"], [{"stat": "Strike", "amount": 1, "expiry": "permanent"}],
			"A null source is left out")
	assert_false(data.has("grants"))


func test_round_trip_into_a_fresh_card_gives_the_same_tables_and_stats():
	var a := await put_creature(1, 3, 3)
	game.stats.apply_damage(a, "Strike", 1)
	game.stats.apply_damage(a, "Guard", 2)
	game.stats.add_modifier(a, "Strike", 2, "permanent")
	game.stats.add_modifier(a, "Guard", -1, "end_of_turn")
	game.stats.grant_keyword(a, "Savage", 2, "owner_maintenance")
	game.stats.grant_keyword(a, "Indomitable", 1, "permanent")
	var data := game.stats.export_card(a, _id_of)
	var b := await put_creature(1, 3, 3)
	assert_eq(_shown(b), [3, 3])
	game.stats.import_card(b, data, _card_of)
	game.stats.refresh_all()
	assert_eq(game.stats.export_card(b, _id_of), data, "Identical tables")
	assert_eq(_shown(b), _shown(a), "Identical displayed Strike and Guard")
	assert_eq(game.stats.damage_on(b, "Strike"), 1)
	assert_eq(game.stats.damage_on(b, "Guard"), 2)
	assert_eq(game.stats.modifier_total(b, "Strike"), 2)
	assert_eq(game.stats.modifier_total(b, "Guard"), -1)
	assert_eq(game.stats.grants_of(b).size(), 2)
	assert_eq(game.stats.grants_of(b)[0].keyword, "Savage")
	assert_eq(game.stats.grants_of(b)[0].value, 2)
	assert_eq(game.stats.grants_of(b)[1].keyword, "Indomitable")
	assert_eq(_shown(b), [3 + 2 - 1, 3 - 1 - 2])


func test_sources_resolve_through_id_of_and_card_of():
	var spell_card := await put_creature(1, 1, 1)
	var target := await put_creature(1, 2, 2)
	game.stats.add_modifier(target, "Strike", 2, "permanent", spell_card)
	game.stats.grant_keyword(target, "Savage", 1, "permanent", spell_card)
	var data := game.stats.export_card(target, _id_of)
	var source_id: String = data["modifiers"][0]["source"]
	assert_eq(source_id, _ids[spell_card.get_instance_id()])
	assert_eq(data["grants"][0]["source"], source_id)
	# A fresh target and a fresh stand-in for the source card
	var target2 := await put_creature(1, 2, 2)
	var spell_card2 := await put_creature(1, 1, 1)
	_cards[source_id] = spell_card2
	game.stats.import_card(target2, data, _card_of)
	assert_true(is_same(game.stats._mods[target2.get_instance_id()][0].source, spell_card2))
	assert_true(is_same(game.stats.grants_of(target2)[0].source, spell_card2))
	# The imported source works: removing its modifiers ends them
	game.stats.remove_modifiers_from(spell_card2)
	assert_eq(game.stats.modifier_total(target2, "Strike"), 0)
	assert_true(game.stats.grants_of(target2).is_empty())


func test_unknown_or_missing_source_id_gives_a_null_source():
	var card := await put_creature(1, 2, 2)
	game.stats.import_card(card, {
		"modifiers": [{"stat": "Strike", "amount": 1, "expiry": "permanent", "source": "nope"},
				{"stat": "Guard", "amount": 1, "expiry": "permanent"}],
		"grants": [{"keyword": "Savage", "value": 1, "expiry": "permanent", "source": "nope"}],
	}, _card_of)
	var mods: Array = game.stats._mods[card.get_instance_id()]
	assert_null(mods[0].source)
	assert_null(mods[1].source)
	assert_null(game.stats.grants_of(card)[0].source)


func test_import_tolerates_missing_keys():
	var card := await put_creature(1, 2, 2)
	game.stats.import_card(card, {}, _card_of)
	assert_eq(game.stats.export_card(card, _id_of), {})
	game.stats.import_card(card, {"grants": [{"keyword": "Savage"}]}, _card_of)
	var grant: Dictionary = game.stats.grants_of(card)[0]
	assert_eq(grant.value, 1)
	assert_eq(grant.expiry, FateStats.EXPIRY_END_OF_TURN)
	game.stats.import_card(card, {"modifiers": [{"stat": "Strike"}]}, _card_of)
	assert_eq(game.stats.modifier_total(card, "Strike"), 0)


func test_identical_duplicate_modifiers_survive_in_order():
	var a := await put_creature(1, 3, 3)
	game.stats.add_modifier(a, "Strike", 1, "permanent")
	game.stats.add_modifier(a, "Guard", 2, "end_of_turn")
	game.stats.add_modifier(a, "Strike", 1, "permanent")
	game.stats.grant_keyword(a, "Savage", 1, "permanent")
	game.stats.grant_keyword(a, "Savage", 1, "permanent")
	var data := game.stats.export_card(a, _id_of)
	assert_eq(data["modifiers"].size(), 3)
	assert_eq(data["grants"].size(), 2)
	var b := await put_creature(1, 3, 3)
	game.stats.import_card(b, data, _card_of)
	game.stats.refresh_all()
	assert_eq(game.stats.export_card(b, _id_of), data, "Same entries in the same order")
	assert_eq(game.stats.modifier_total(b, "Strike"), 2)
	assert_eq(game.stats._mods[b.get_instance_id()][1].stat, "Guard")


func test_import_does_not_alias_the_exported_data():
	var a := await put_creature(1, 3, 3)
	game.stats.add_modifier(a, "Strike", 1, "permanent")
	var data := game.stats.export_card(a, _id_of)
	var b := await put_creature(1, 3, 3)
	game.stats.import_card(b, data, _card_of)
	data["modifiers"][0]["amount"] = 99
	assert_eq(game.stats.modifier_total(b, "Strike"), 1)


func test_import_writes_directly_without_refresh_or_signal():
	var card := await put_creature(1, 2, 2)
	var seen := []
	game.stats.stats_changed.connect(func(c): seen.append(c))
	game.stats.import_card(card, {"modifiers": [{"stat": "Strike", "amount": 4,
			"expiry": "permanent"}]}, _card_of)
	assert_true(seen.is_empty(), "No signal")
	assert_eq(_shown(card), [2, 2], "The face is not refreshed by import")
	game.stats.refresh_all()
	assert_eq(seen, [card], "refresh_all emits stats_changed")
	assert_eq(_shown(card), [6, 2])


func test_refresh_all_does_not_destroy_a_creature_at_zero_stats():
	var card := await put_creature(1, 2, 2)
	var seen := []
	game.creature_destroyed.connect(func(c, cause): seen.append(c))
	game.stats.import_card(card, {"damage": {"Strike": 2, "Guard": 2}}, _card_of)
	game.stats.refresh_all()
	assert_eq(_shown(card), [0, 0])
	assert_true(FateZones.is_creature_in_play(card), "Still in play")
	assert_true(seen.is_empty())
	assert_true(game.stats._batch_cards.is_empty(), "Nothing queued for a later check")
	assert_eq(game.stats._batch, 0)
	# A normal refresh does run the state-based check
	game.stats.refresh(card)
	assert_false(FateZones.is_creature_in_play(card), "refresh() still destroys")
	assert_eq(seen, [card])


func test_refresh_all_inside_a_batch_keeps_the_outer_batch():
	var other := await put_creature(1, 1, 1)
	var card := await put_creature(1, 2, 2)
	game.stats.begin_batch()
	game.stats.add_modifier(other, "Strike", -1, "permanent")
	game.stats.import_card(card, {"damage": {"Strike": 1}}, _card_of)
	game.stats.refresh_all()
	assert_eq(game.stats._batch, 1)
	assert_true(other in game.stats._batch_cards, "The outer batch kept its pending card")
	assert_false(card in game.stats._batch_cards, "refresh_all did not queue its cards")
	game.stats.end_batch()


func test_clear_all_leaves_nothing():
	var a := await put_creature(1, 3, 3)
	var b := await put_creature(2, 3, 3)
	game.stats.apply_damage(a, "Strike", 1)
	game.stats.add_modifier(a, "Guard", 1, "permanent")
	game.stats.grant_keyword(b, "Savage", 1, "permanent")
	game.stats.begin_batch()
	game.stats.apply_damage(b, "Guard", 1)
	game.stats.clear_all()
	assert_true(game.stats._damage.is_empty())
	assert_true(game.stats._mods.is_empty())
	assert_true(game.stats._grants.is_empty())
	assert_eq(game.stats._batch, 0)
	assert_true(game.stats._batch_cards.is_empty())
	assert_eq(game.stats.export_card(a, _id_of), {})
	assert_eq(game.stats.export_card(b, _id_of), {})
	assert_eq(game.stats.damage_on(a, "Strike"), 0)
	assert_true(game.stats.grants_of(b).is_empty())


func test_import_replaces_existing_entries():
	var card := await put_creature(1, 3, 3)
	game.stats.apply_damage(card, "Strike", 2)
	game.stats.add_modifier(card, "Strike", 5, "permanent")
	game.stats.grant_keyword(card, "Savage", 1, "permanent")
	game.stats.import_card(card, {"damage": {"Guard": 1},
			"modifiers": [{"stat": "Guard", "amount": 2, "expiry": "end_of_turn"}]}, _card_of)
	assert_eq(game.stats.damage_on(card, "Strike"), 0, "Old damage gone")
	assert_eq(game.stats.damage_on(card, "Guard"), 1)
	assert_eq(game.stats.modifier_total(card, "Strike"), 0, "Old modifier gone")
	assert_eq(game.stats.modifier_total(card, "Guard"), 2)
	assert_true(game.stats.grants_of(card).is_empty(), "Old grant gone")
	game.stats.import_card(card, {}, _card_of)
	assert_eq(game.stats.export_card(card, _id_of), {}, "An empty import clears the card")
