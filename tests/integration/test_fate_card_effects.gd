extends "res://tests/FateCommon.gd"
# The card-logic foundation: card scripts (cards/FateCardEffect.gd) reach the game through the registry
# (FateCardEffects). These tests register small scripts of their own for real cards and check every hook.

const BASE := "res://src/custom/fate/cards/FateCardEffect.gd"


# A recording script: counts what happened to the card it is registered for
class Recorder:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var log: Array = []
	var problem_text := ""
	var destination := ""
	var bonus := 0
	var keywords := {}
	var picks: Array = []

	func _init(name_of_card := "") -> void:
		card_name = name_of_card

	func play_problem(_card: Card, _caster_id: int) -> String:
		return problem_text

	func candidates(_card: Card, _caster_id: int) -> Array:
		return picks

	func default_choice(_card: Card, _caster_id: int):
		return picks[0] if not picks.is_empty() else null

	func resolve(_card: Card, _caster_id: int, choice) -> void:
		log.append(["resolve", choice])

	func on_play(_card: Card) -> void:
		log.append(["play"])

	func on_enter(_card: Card) -> void:
		log.append(["enter"])

	func on_leave(_card: Card, dest: String) -> void:
		log.append(["leave", dest])

	func on_destroyed(_card: Card, cause: String, _source) -> void:
		log.append(["destroyed", cause])

	func spell_destination(_card: Card, _caster_id: int) -> String:
		return destination

	func on_card_played(_card: Card, played: Card) -> void:
		log.append(["saw", played.canonical_name])

	func on_phase(_card: Card, _active_id: int, phase: int) -> void:
		log.append(["phase", phase])

	func static_stat_bonus(host: Card, target: Card, stat: String) -> int:
		return bonus if stat == "Strike" and target.controller_id == host.controller_id \
				and target.properties.get("Type") == "Creature" else 0

	func static_keywords(host: Card, target: Card) -> Dictionary:
		return keywords if target.controller_id == host.controller_id else {}


func _names(log: Array) -> Array:
	return log.map(func(e): return e[0])


func _register(card_name: String) -> Recorder:
	var fx := Recorder.new(card_name)
	game.card_effects.register(fx)
	return fx


func _to_main_with_mana() -> void:
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()


func test_the_registry_finds_scripts_and_registers_by_name() -> void:
	var fx := _register("Reinforcements")
	assert_eq(game.card_effects.effect_of("Reinforcements"), fx)
	assert_true("Reinforcements" in game.card_effects.registered_names())


func test_a_regular_spell_resolves_then_goes_to_the_discard_pile() -> void:
	var fx := _register("Reinforcements")
	await _to_main_with_mana()
	var spell := await put_in_hand(1, "Reinforcements")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.1)
	assert_eq(_names(fx.log), ["resolve", "play"])
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))


func test_play_problem_keeps_the_card_in_hand_and_unpaid() -> void:
	var fx := _register("Reinforcements")
	fx.problem_text = "No target"
	await _to_main_with_mana()
	var spell := await put_in_hand(1, "Reinforcements")
	var before := total_mana(game.mana_pool(1))
	assert_false(game.can_play_from_hand(spell))
	assert_false(game.play_from_hand(spell))
	assert_eq(total_mana(game.mana_pool(1)), before, "nothing was paid")
	assert_eq(fx.log, [])


func test_a_spell_with_a_choice_takes_the_default_or_the_chooser() -> void:
	var fx := _register("Reinforcements")
	fx.has_choice = true
	await _to_main_with_mana()
	var a := await put_creature(2, "Moral Captain")
	var b := await put_creature(2, "Righteous Guard")
	fx.picks = [a, b]
	var spell := await put_in_hand(1, "Reinforcements")
	game.play_from_hand(spell)
	await wait_seconds(0.1)
	assert_eq(fx.log[0], ["resolve", a], "the default choice")
	# A chooser overrides it, an invalid answer falls back to the default
	game.choices.chooser = func(request): return request.options[1]
	var spell2 := await put_in_hand(1, "Reinforcements")
	fx.log.clear()
	game.play_from_hand(spell2)
	await wait_seconds(0.1)
	assert_eq(fx.log[0], ["resolve", b], "the chooser's answer")
	game.choices.chooser = Callable()


func test_the_spell_destination_can_be_changed() -> void:
	var fx := _register("Reinforcements")
	fx.destination = "removed"
	await _to_main_with_mana()
	var spell := await put_in_hand(1, "Reinforcements")
	game.play_from_hand(spell)
	await wait_seconds(0.2)
	assert_eq(spell.get_parent(), FateZones.container("removed", 1))


func test_a_creature_hears_play_enter_and_leave() -> void:
	var fx := _register("Righteous Guard")
	await _to_main_with_mana()
	var creature := await put_in_hand(1, "Righteous Guard")
	assert_true(game.play_from_hand(creature))
	await wait_seconds(0.2)
	assert_eq(_names(fx.log), ["play", "enter"])
	fx.log.clear()
	game.effects.destroy(creature, null, FateEffects.CAUSE_EFFECT)
	await wait_seconds(0.2)
	assert_has(_names(fx.log), "destroyed")
	assert_has(fx.log, ["leave", "discard"])


func test_a_card_that_arrives_without_being_played_still_enters() -> void:
	var fx := _register("Righteous Guard")
	var creature := await put_in_hand(1, "Righteous Guard")
	var slot := game.player(1).grid("creatures").find_available_slot()
	creature.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	await wait_seconds(0.2)
	assert_eq(_names(fx.log), ["enter"], "entered, but not played")


func test_cards_on_the_table_watch_other_cards_and_phases() -> void:
	var watcher_fx := _register("Dragon's Tooth")
	await put_on_table(1, "Dragon's Tooth", "relics")
	await _to_main_with_mana()
	var creature := await put_in_hand(1, "Righteous Guard")
	game.play_from_hand(creature)
	await wait_seconds(0.2)
	assert_has(watcher_fx.log, ["saw", "Righteous Guard"])
	game.advance_phase()
	assert_has(watcher_fx.log, ["phase", FateGame.Phase.COMBAT_DECLARE])


func test_static_effects_change_stats_and_keywords_while_the_card_is_on_the_table() -> void:
	var fx := _register("Dragon's Tooth")
	fx.bonus = 2
	fx.keywords = {"Savage": 1}
	var creature := await put_creature(1, 2, 2)
	assert_eq(game.stats.current(creature, "Strike"), 2)
	var relic := await put_on_table(1, "Dragon's Tooth", "relics")
	assert_eq(game.stats.current(creature, "Strike"), 4, "+2 Strike from the relic")
	assert_true(game.keywords.has(creature, "Savage"), "Savage from the relic")
	var enemy := await put_creature(2, 2, 2)
	assert_eq(game.stats.current(enemy, "Strike"), 2, "only the controller's creatures")
	game.effects.destroy(relic)
	assert_eq(game.stats.current(creature, "Strike"), 2)
	assert_false(game.keywords.has(creature, "Savage"))


func test_an_activated_ability_pays_its_costs_and_runs() -> void:
	var ran := []
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()
	var creature := await put_creature(1, "Streetside Recruiter")
	# The card script offers one hover action costing 2 mana
	var script_class := GDScript.new()
	script_class.source_code = "extends \"%s\"\nvar ran: Array\nfunc actions(card):\n\treturn [make_action(card, 'ping', 'Ping', 'tip', [game.costs.mana(2)], func(c): ran.append(c.canonical_name))]\n" % BASE
	script_class.reload()
	var actioned = script_class.new()
	actioned.card_name = "Streetside Recruiter"
	actioned.ran = ran
	game.card_effects.register(actioned)
	var before := total_mana(game.mana_pool(1))
	assert_true(await game.actions.run(creature, "ping"))
	assert_eq(ran, ["Streetside Recruiter"])
	assert_eq(total_mana(game.mana_pool(1)), before - 2, "two mana paid")


func test_once_per_turn_blocks_the_second_use() -> void:
	var creature := await put_creature(1, "Righteous Guard")
	assert_true(game.limiter.use(creature, "x"))
	assert_false(game.limiter.can_use(creature, "x"))
	assert_false(game.limiter.use(creature, "x"))
	assert_true(game.limiter.can_use(creature, "y"))
	game.end_turn()
	assert_true(game.limiter.can_use(creature, "x"), "a new turn")
