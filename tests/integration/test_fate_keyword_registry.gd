extends "res://tests/FateCommon.gd"
# Tests of the keyword registry (FateKeywords): discovery, what a card has, and the combination
# rules of the hooks. Hook dispatch inside combat is tested in test_fate_combat.gd. The test
# keywords come from tests/FateTestKeyword.gd (configurable, records its calls), registered per
# test, and tests/fate_keywords/ (discovery); neither is under src/ so neither ships.

const TestKeyword := preload("res://tests/FateTestKeyword.gd")
const TEST_DIR := "res://tests/fate_keywords/"


func _kw(kw_name: String, kw_priority := 0, universal := false) -> FateKeyword:
	var kw := TestKeyword.make(kw_name, kw_priority, universal)
	game.keywords.register(kw)
	return kw


# --- discovery -----------------------------------------------------------------------------------------

func test_script_file_names_cover_editor_and_export_listings():
	assert_eq(FateKeywords.script_file_name("KwSavage.gd"), "KwSavage.gd")
	assert_eq(FateKeywords.script_file_name("KwSavage.gd.remap"), "KwSavage.gd", "Export: remapped")
	assert_eq(FateKeywords.script_file_name("KwSavage.gdc"), "KwSavage.gd", "Export: compiled")
	assert_eq(FateKeywords.script_file_name("KwSavage.gd.uid"), "")
	assert_eq(FateKeywords.script_file_name("README.md"), "")
	assert_eq(FateKeywords.script_file_name("Helper.gd"), "", "Only Kw*.gd")


func test_discovery_registers_keyword_scripts_from_a_folder():
	assert_false(game.keywords.registered_names().has("Test found"))
	assert_eq(game.keywords.discover(TEST_DIR), 1, "KwTestFound.gd only: the other two are skipped")
	var kw := game.keywords.get_keyword("Test found")
	assert_not_null(kw)
	assert_eq(kw.priority, 7)
	assert_eq(kw.game, game, "The registry hands the game to the keyword")
	assert_true(game.keywords.registered_names().has("Test found"))


func test_the_default_folder_is_scanned_at_startup():
	# What is in src/custom/fate/keywords/ varies with the keywords written so far; every script
	# there must have been registered under its own name
	assert_eq(FateKeywords.KEYWORD_DIR, "res://src/custom/fate/keywords/")
	for file_name in DirAccess.get_files_at(FateKeywords.KEYWORD_DIR):
		var script_name := FateKeywords.script_file_name(file_name)
		if script_name != "":
			var kw = load(FateKeywords.KEYWORD_DIR + script_name).new()
			assert_not_null(game.keywords.get_keyword(kw.keyword_name), script_name + " is registered")


func test_register_replaces_a_keyword_of_the_same_name_and_unregister_removes_it():
	var first := _kw("Twice Test")
	var second := _kw("Twice Test")
	assert_eq(game.keywords.get_keyword("Twice Test"), second)
	game.keywords.unregister("Twice Test")
	assert_null(game.keywords.get_keyword("Twice Test"))
	assert_ne(first, second)
	assert_false(game.keywords.register(TestKeyword.make("")), "A keyword needs a name")


# --- what a card has -------------------------------------------------------------------------------------

func test_innate_keywords_have_and_value():
	var card := await put_creature(1, 2, 2, {"Savage": 2, "Untethered": 1})
	assert_true(game.keywords.has(card, "Savage"))
	assert_eq(game.keywords.value(card, "Savage"), 2)
	assert_true(game.keywords.has(card, "Untethered"))
	assert_false(game.keywords.has(card, "Indomitable"))
	assert_eq(game.keywords.value(card, "Indomitable"), 0)
	assert_eq(game.keywords.all_on(card), {"Savage": 2, "Untethered": 1})
	var plain := await put_creature(1, 1, 1)
	assert_eq(game.keywords.all_on(plain), {})
	var real := await put_creature(1, "Feracious Beast")
	assert_eq(game.keywords.value(real, "Savage"), 2, "Real card data: _innate_keywords")


func test_granted_keywords_add_to_innate_ones():
	var card := await put_creature(1, 2, 2, {"Savage": 1})
	game.stats.grant_keyword(card, "Savage", 2, "permanent")
	game.stats.grant_keyword(card, "Indomitable", 1, "end_of_turn")
	assert_eq(game.keywords.value(card, "Savage"), 3, "Values add up")
	assert_eq(game.keywords.all_on(card), {"Savage": 3, "Indomitable": 1})
	assert_eq(card.properties["_innate_keywords"], {"Savage": 1}, "The card's own data is not touched")


func test_an_unknown_keyword_name_is_harmless():
	var card := await put_creature(1, 2, 2, {"No such keyword": 1})
	assert_true(game.keywords.has(card, "No such keyword"))
	assert_true(game.keywords.can_attack(card))
	assert_eq(game.keywords.modify_damage_taken(card, "Strike", 3, "combat", null), 3)


# --- combination rules ----------------------------------------------------------------------------------------

func test_eligibility_hooks_need_every_keyword_to_allow():
	var yes := _kw("Yes Test")
	var no := _kw("No Test")
	no.allow_attack = false
	no.allow_occupy = false
	no.allow_block = false
	no.allow_blocked_by = false
	no.allow_attacked = false
	var plain := await put_creature(1, 1, 1, {"Yes Test": 1})
	var mixed := await put_creature(1, 1, 1, {"Yes Test": 1, "No Test": 1})
	var attack := FateAttack.new(plain, 2)
	assert_true(game.keywords.can_attack(plain))
	assert_false(game.keywords.can_attack(mixed), "One keyword saying no is enough")
	assert_true(game.keywords.can_occupy(plain))
	assert_false(game.keywords.can_occupy(mixed))
	assert_true(game.keywords.can_block(plain, attack))
	assert_false(game.keywords.can_block(mixed, attack))
	assert_true(game.keywords.can_be_blocked_by(plain, mixed, attack))
	assert_false(game.keywords.can_be_blocked_by(mixed, plain, attack), "The attacker's keywords decide")
	assert_true(game.keywords.can_be_attacked(plain, mixed))
	assert_false(game.keywords.can_be_attacked(mixed, plain))
	assert_eq(yes.hooks_called("can_attack").size(), 1,
			"Asked for the first card; for the second, 'No Test' (earlier by name) already said no")


func test_hooks_run_for_the_keywords_on_the_card_only_unless_universal():
	var on_card := _kw("Own Test")
	var elsewhere := _kw("Elsewhere Test")
	var everywhere := _kw("Everywhere Test", 0, true)
	var card := await put_creature(1, 1, 1, {"Own Test": 1})
	game.keywords.can_attack(card)
	assert_eq(on_card.hooks_called("can_attack").size(), 1)
	assert_eq(elsewhere.hooks_called("can_attack").size(), 0)
	assert_eq(everywhere.hooks_called("can_attack").size(), 1, "A universal keyword runs for every card")
	var bare := await put_creature(1, 1, 1)
	game.keywords.can_attack(bare)
	assert_eq(everywhere.hooks_called("can_attack").size(), 2)
	assert_eq(on_card.hooks_called("can_attack").size(), 1)


func test_a_universal_keyword_can_forbid_by_default_and_lift_it_for_cards_with_the_keyword():
	var charge := _kw("Charge Test", 0, true)
	charge.allow_attack = false
	# (a real one would check game.turn_number and has(card) itself; here it just says no)
	var card := await put_creature(1, 1, 1, {"Charge Test": 1})
	assert_false(game.keywords.can_attack(card))
	game.keywords.unregister("Charge Test")
	assert_true(game.keywords.can_attack(card), "Unregistered keywords stop running")


func test_hooks_run_in_priority_order_then_by_name():
	var log := []
	for spec in [["B Test", 5], ["A Test", 5], ["Late Test", 9], ["Early Test", -3]]:
		var kw := _kw(spec[0], spec[1])
		kw.use_shared_log = true
		kw.shared_log = log
	var card := await put_creature(1, 1, 1, {"B Test": 1, "A Test": 1, "Late Test": 1, "Early Test": 1})
	game.keywords.can_attack(card)
	assert_eq(log, ["Early Test:can_attack", "A Test:can_attack", "B Test:can_attack",
			"Late Test:can_attack"])


func test_modify_damage_taken_chains_through_the_keywords_in_order():
	var first := _kw("First Test", 0)
	first.damage_reduction = 2
	var second := _kw("Second Test", 1)
	second.damage_cap = 2
	var card := await put_creature(1, 5, 5, {"First Test": 1, "Second Test": 1})
	assert_eq(game.keywords.modify_damage_taken(card, "Strike", 7, "effect", null), 2,
			"7 - 2 = 5, then capped at 2")
	assert_eq(second.hooks_called("modify_damage_taken")[0][3], 5, "The second keyword got the first's result")
	first.damage_reduction = 10
	assert_eq(game.keywords.modify_damage_taken(card, "Strike", 7, "effect", null), 0, "Never below 0")


func test_hold_at_one_keeps_the_used_stat_from_reaching_zero():
	# The mechanism Indomitable uses: it cannot die from combat damage, other damage is normal
	var indomitable := _kw("Hold Test")
	indomitable.hold_at_one = true
	var card := await put_creature(1, 3, 3, {"Hold Test": 1})
	assert_eq(game.effects.deal_damage(card, 5, null, "combat"), 2)
	assert_eq(game.stats.current(card, "Strike"), 1, "Held at 1")
	assert_true(FateZones.is_creature_in_play(card), "Not destroyed by combat damage")
	assert_eq(game.effects.deal_damage(card, 5, null, "effect"), 1, "Other damage is not held")
	assert_eq(game.stats.current(card, "Strike"), 0)


func test_would_be_destroyed_needs_every_keyword_to_agree():
	var a := _kw("Allow Test")
	var b := _kw("Deny Test")
	b.allow_destroy = false
	var one := await put_creature(1, 1, 1, {"Allow Test": 1})
	var both := await put_creature(1, 1, 1, {"Allow Test": 1, "Deny Test": 1})
	assert_true(game.keywords.would_be_destroyed(one, "effect", null))
	assert_false(game.keywords.would_be_destroyed(both, "effect", null))
	assert_eq(a.hooks_called("would_be_destroyed")[0].slice(1), [one, "effect", null])


func test_death_destination_defaults_to_discard_and_the_first_answer_wins():
	var none := _kw("None Test", 0)
	var removed := _kw("Removed Test", 1)
	removed.destination = "removed"
	var hand := _kw("Hand Test", 2)
	hand.destination = "hand"
	var plain := await put_creature(1, 1, 1, {"None Test": 1})
	assert_eq(game.keywords.death_destination(plain, "combat"), "discard", "Nobody has an opinion")
	var both := await put_creature(1, 1, 1, {"None Test": 1, "Hand Test": 1, "Removed Test": 1})
	assert_eq(game.keywords.death_destination(both, "combat"), "removed", "Lower priority number first")
	assert_eq(none.hooks_called("death_destination").size(), 2)


func test_stat_bonus_is_summed_over_the_keywords():
	var a := _kw("Plus A Test")
	a.bonus = {"Strike": 1}
	var b := _kw("Plus B Test")
	b.bonus = {"Strike": 2, "Guard": 3}
	var card := await put_creature(1, 1, 1, {"Plus A Test": 1, "Plus B Test": 1})
	assert_eq(game.keywords.stat_bonus(card, "Strike"), 3)
	assert_eq(game.keywords.stat_bonus(card, "Guard"), 3)


func test_turn_hooks_run_for_the_active_players_creatures():
	var kw := _kw("Turn Test")
	var mine := await put_creature(1, 1, 1, {"Turn Test": 1})
	var theirs := await put_creature(2, 1, 1, {"Turn Test": 1})
	game.end_turn()
	assert_eq(kw.hooks_called("on_turn_end").map(func(c): return c[1]), [mine],
			"The end of player 1's turn: player 1's creatures")
	assert_eq(kw.hooks_called("on_maintenance").map(func(c): return c[1]), [theirs],
			"Player 2's maintenance: player 2's creatures")


# --- actions ----------------------------------------------------------------------------------------------------

func test_keyword_actions_are_listed_for_the_controller_and_can_be_run():
	var kw := _kw("Action Test")
	var ran := []
	kw.action_list = [
		{"id": "go", "label": "Go", "tooltip": "Does it", "enabled": true,
				"run": func(c): ran.append(c); return true},
		{"id": "stuck", "label": "No", "enabled": false, "run": func(c): ran.append("bad")},
	]
	var mine := await put_creature(1, 1, 1, {"Action Test": 1})
	var theirs := await put_creature(2, 1, 1, {"Action Test": 1})
	var plain := await put_creature(1, 1, 1)
	assert_eq(game.actions.list(mine).map(func(a): return a.id), ["go", "stuck"])
	assert_eq(game.actions.list(theirs), [], "Only the controller, on their turn")
	assert_eq(game.actions.list(plain), [])
	var performed := []
	game.actions.action_performed.connect(func(c, id): performed.append([c, id]))
	assert_true(await game.actions.run(mine, "go"))
	assert_false(await game.actions.run(mine, "stuck"), "Disabled")
	assert_false(await game.actions.run(mine, "missing"))
	assert_eq(ran, [mine])
	assert_eq(performed, [[mine, "go"]])


func test_action_buttons_appear_on_the_hover_buttons():
	var kw := _kw("Button Test")
	kw.action_list = [{"id": "poke", "label": "Pk", "tooltip": "Poke", "enabled": true,
			"run": func(_c): return true}]
	var card := await put_creature(1, 1, 1, {"Button Test": 1})
	var buttons: ManipulationButtons = card.buttons
	buttons.set_active(false)
	buttons.set_active(true)
	assert_true(buttons.has_node("Action_poke"), "A hover button for the action")
	assert_eq(buttons.get_node("Action_poke").text, "Pk")
	buttons.set_active(false)
	buttons.set_active(true)
	assert_eq(buttons.get_children().filter(func(c): return str(c.name).begins_with("Action_")).size(), 1,
			"Rebuilt, not duplicated")
