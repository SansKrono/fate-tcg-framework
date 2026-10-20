extends "res://tests/FateCommon.gd"
# Tests of Occupy (src/custom/fate/keywords/KwOccupy.gd). Rules: docs/FATE_RULES_SPEC.md, Section 4:
# tilt the card and move it to the occupied zone; it cannot attack, can intercept (Guard), and
# returns untapped at its owner's maintenance. Player 1 is the active player.

const Phase := FateGame.Phase
const TestKeyword := preload("res://tests/FateTestKeyword.gd")
const REAL_CARD := "Rustmarket Tinkerer"  # Strike 1, Guard 3, "Occupy" in its display list

var occupy_kw


func before_each():
	await super.before_each()
	occupy_kw = game.keywords.get_keyword("Occupy")


func _zone(card: Card) -> String:
	return FateZones.zone_of(card)


func _occupy_ids(card: Card) -> Array:
	# Only the keyword actions: a card script may offer its own ability (Rustmarket Tinkerer's recast)
	return game.actions.list(card).map(func(a): return a.id).filter(
			func(id): return id in ["occupy", "embody", "force_block", "evolve"])


# A creature on the table with the Occupy ability and the game in the main phase. It has the keyword and no card script:
# a card with an Occupy ability of its own (REAL_CARD) has that ability as its button instead of the plain one
func _occupier(pid := 1) -> Card:
	var card := await put_creature(pid, 1, 3, {"Occupy": 1})
	if pid == game.active_id:
		go_to_main()
	return card


# --- the keyword is discovered -----------------------------------------------------------------

func test_the_registry_finds_occupy():
	assert_not_null(occupy_kw, "KwOccupy was registered")
	assert_true(occupy_kw.universal, "Real cards only list Occupy in their display list")


func test_has_ability_reads_the_display_list_and_the_keyword():
	var listed := await put_creature(1, REAL_CARD)
	var plain := await put_creature(1, 2, 2)
	var innate := await put_creature(1, 2, 2, {"Occupy": 1})
	assert_true(occupy_kw.has_ability(listed))
	assert_false(occupy_kw.has_ability(plain))
	assert_true(occupy_kw.has_ability(innate))
	game.stats.grant_keyword(plain, "Occupy", 1, "permanent")
	assert_true(occupy_kw.has_ability(plain), "A granted Occupy counts (an equipment gives it)")


# --- occupying -----------------------------------------------------------------------------------

func test_occupy_tilts_the_card_and_moves_it_to_the_occupied_zone():
	var card := await _occupier()
	var old_slot: BoardPlacementSlot = card._placement_slot
	assert_true(occupy_kw.occupy(card))
	await wait_card_settled(card)
	assert_eq(_zone(card), "occupied")
	assert_eq(card.card_rotation, 90, "Tilted")
	assert_null(old_slot.occupying_card, "The creature slot is free again")
	assert_eq(card._placement_slot.occupying_card, card, "The occupied slot knows its card")
	assert_eq(card._placement_slot, game.player(1).grid("occupied").get_all_slots()[0])
	assert_eq(card.get_parent(), board)
	assert_true(FateZones.is_creature_in_play(card), "Still a creature in play")
	assert_eq(game.player(1).cards_in_grid("creatures").size(), 0)
	assert_eq(game.stats.current(card, "Guard"), 3, "Stats untouched")


func test_the_creature_slot_can_be_reused_after_occupying():
	var first := await _occupier()
	var slot: BoardPlacementSlot = first._placement_slot
	occupy_kw.occupy(first)
	var second := await put_creature(1, 2, 2)
	assert_eq(second._placement_slot, slot, "The next creature takes the freed slot")


func test_occupying_several_creatures_uses_different_slots():
	var a := await _occupier()
	var b := await put_creature(1, REAL_CARD)
	assert_true(occupy_kw.occupy(a))
	assert_true(occupy_kw.occupy(b))
	assert_ne(a._placement_slot, b._placement_slot)
	assert_eq(game.player(1).cards_in_grid("occupied").size(), 2)


func test_the_occupy_helper_does_not_need_the_ability():
	var plain := await put_creature(1, 2, 2)
	go_to_main()
	assert_true(occupy_kw.can_occupy_now(plain))
	assert_true(occupy_kw.occupy(plain), "Other cards can occupy a creature that has no Occupy ability")
	assert_eq(_zone(plain), "occupied")


func test_unoccupy_returns_the_card_upright():
	var card := await _occupier()
	occupy_kw.occupy(card)
	assert_true(occupy_kw.unoccupy(card))
	assert_eq(_zone(card), "creatures")
	assert_eq(card.card_rotation, 0)
	assert_eq(game.player(1).cards_in_grid("occupied").size(), 0)
	assert_false(occupy_kw.unoccupy(card), "Not occupied any more")


func test_unoccupy_refuses_when_the_creature_zone_is_full():
	var card := await _occupier()
	occupy_kw.occupy(card)
	for _i in range(6):
		await put_creature(1, 1, 1)
	assert_null(game.player(1).grid("creatures").find_available_slot())
	assert_false(occupy_kw.unoccupy(card))
	assert_eq(_zone(card), "occupied")


# --- combat ---------------------------------------------------------------------------------------

func test_an_occupied_creature_cannot_be_declared_as_an_attacker():
	var card := await _occupier()
	var ready := await put_creature(1, 2, 2)
	assert_true(await game.actions.run(card, "occupy"))
	start_combat()
	assert_false(card in game.combat.eligible_attackers())
	assert_true(ready in game.combat.eligible_attackers())
	assert_false(game.combat.declare_attack(card, 2))
	assert_eq(game.combat.last_error, "An occupied creature cannot attack")
	assert_false(game.combat.declare_attack(card, await put_creature(2, 1, 1)))


func test_an_occupied_creature_can_be_targeted():
	var attacker := await put_creature(1, 2, 2)
	var target := await put_creature(2, 1, 4, {}, false, "occupied")
	start_combat()
	assert_true(game.combat.declare_attack(attacker, target))


func test_an_occupied_creature_blocks_with_its_guard():
	# Strike 3 attacker, Guard 2 blocker: the attacker is left with 1 and the blocker is destroyed
	var attacker := await put_creature(1, 3, 3)
	var blocker := await put_creature(2, 1, 2)
	go_to_main()
	assert_true(occupy_kw.occupy(blocker, true), "An effect occupies it outside its controller's turn")
	start_combat()
	assert_true(game.combat.declare_attack(attacker, 2))
	var attack: FateAttack = game.combat.attack_of(attacker)
	game.combat.confirm_attackers()
	assert_eq(game.phase, Phase.COMBAT_INTERCEPT)
	assert_true(blocker in game.combat.eligible_blockers(attack), "Occupied creatures intercept")
	assert_true(game.combat.declare_block(blocker, attack), game.combat.last_error)
	game.combat.confirm_blocks()
	assert_eq(attack.result.kind, "blocked")
	assert_eq(game.stats.current(attacker, "Strike"), 1, "3 - 2")
	assert_eq(blocker.get_parent(), FateZones.container("discard", 2), "Guard 2 - 3 = 0: destroyed")
	assert_eq(game.player(2).life, LIFE - 1, "The attack did not reach the player, the lost blocker cost a life")


func test_a_blocking_occupied_creature_that_survives_deals_its_guard():
	var attacker := await put_creature(1, 2, 2)
	var blocker := await put_creature(2, 1, 5, {}, false, "occupied")
	start_combat()
	game.combat.declare_attack(attacker, 2)
	var attack: FateAttack = game.combat.attack_of(attacker)
	game.combat.confirm_attackers()
	assert_true(game.combat.declare_block(blocker, attack))
	game.combat.confirm_blocks()
	assert_eq(game.stats.damage_on(blocker, "Guard"), 2, "It lost 2 of its Guard")
	assert_eq(game.stats.current(blocker, "Guard"), 3)
	assert_eq(attacker.get_parent(), FateZones.container("discard", 1), "Strike 2 - Guard 5 = 0")
	assert_eq(_zone(blocker), "occupied", "Still occupied afterwards")


# --- maintenance ----------------------------------------------------------------------------------

func test_maintenance_returns_the_occupied_creature_untapped():
	var card := await _occupier()
	assert_true(await game.actions.run(card, "occupy"))
	game.end_turn()
	assert_eq(game.active_id, 2)
	assert_eq(_zone(card), "occupied", "It stays occupied through the other player's turn")
	assert_eq(card.card_rotation, 90)
	game.end_turn()
	assert_eq(game.active_id, 1)
	await wait_card_settled(card)
	assert_eq(_zone(card), "creatures", "Maintenance moved it back")
	assert_eq(card.card_rotation, 0, "... in the strike position")
	assert_null(game.player(1).grid("occupied").get_all_slots()[0].occupying_card)
	assert_true(card in game.player(1).cards_in_grid("creatures"))


# --- restrictions ---------------------------------------------------------------------------------

func test_only_in_the_main_phase():
	var card := await put_creature(1, 1, 3, {"Occupy": 1})
	assert_eq(game.phase, Phase.ENERGY)
	assert_eq(occupy_kw.occupy_problem(card), "You can only occupy in your main phase")
	assert_false(occupy_kw.occupy(card))
	assert_eq(_occupy_ids(card), [])
	assert_false(await game.actions.run(card, "occupy"))
	assert_eq(_zone(card), "creatures")
	go_to_main()
	assert_eq(_occupy_ids(card), ["occupy"])
	start_combat_from_main()
	assert_eq(_occupy_ids(card), [], "Not in the combat phase either")
	assert_false(occupy_kw.occupy(card))
	assert_eq(_zone(card), "creatures")


func start_combat_from_main() -> void:
	game.turn.end_phase_waits_for_player = true
	assert_true(game.advance_phase())
	assert_eq(game.phase, Phase.COMBAT_DECLARE)


func test_only_the_controller_in_their_own_turn():
	var theirs := await put_creature(2, 1, 3, {"Occupy": 1})
	go_to_main()
	assert_eq(occupy_kw.occupy_problem(theirs), "It is not your creature")
	assert_false(occupy_kw.occupy(theirs))
	assert_eq(_occupy_ids(theirs), [])
	assert_false(await game.actions.run(theirs, "occupy"))
	assert_eq(_zone(theirs), "creatures")


func test_a_creature_cannot_occupy_twice():
	var card := await _occupier()
	assert_true(occupy_kw.occupy(card))
	assert_eq(occupy_kw.occupy_problem(card), "It is already occupied")
	assert_false(occupy_kw.occupy(card))
	assert_eq(_occupy_ids(card), [])
	assert_eq(game.player(1).cards_in_grid("occupied").size(), 1)


func test_a_full_occupied_zone_refuses():
	var filler := []
	for _i in range(6):
		filler.append(await put_creature(1, 1, 1, {}, false, "occupied"))
	var card := await _occupier()
	assert_eq(occupy_kw.occupy_problem(card), "The occupied zone is full")
	assert_false(occupy_kw.occupy(card))
	assert_eq(_occupy_ids(card), [])
	assert_eq(_zone(card), "creatures")
	assert_eq(card.card_rotation, 0, "It was not tilted by the failed attempt")
	# Making room makes it legal again
	occupy_kw.unoccupy(filler[0])
	assert_true(occupy_kw.occupy(card))


func test_only_creatures_in_the_creature_zone_can_occupy():
	go_to_main()
	var relic := await put_on_table(1, "Rustmarket Tinkerer", "relics")
	assert_ne(occupy_kw.occupy_problem(relic), "", "A card in the relic zone")
	assert_false(occupy_kw.occupy(relic))
	assert_eq(_occupy_ids(relic), [])
	var in_hand := await put_in_hand(1, REAL_CARD)
	assert_ne(occupy_kw.occupy_problem(in_hand), "", "A creature in the hand")
	assert_false(occupy_kw.occupy(in_hand))
	assert_eq(_occupy_ids(in_hand), [])
	assert_false(await game.actions.run(in_hand, "occupy"))
	assert_eq(in_hand.get_parent(), FateZones.container("hand", 1))
	var relic_name := ""
	for n in FateData.CARDS:
		if FateData.CARDS[n].Type == "Relic":
			relic_name = n
			break
	var real_relic := await put_on_table(1, relic_name, "relics")
	assert_eq(occupy_kw.occupy_problem(real_relic), "Not a creature")
	assert_false(occupy_kw.occupy(real_relic))


func test_a_can_occupy_veto_of_another_keyword_blocks_it():
	var veto := TestKeyword.make("Veto")
	veto.allow_occupy = false
	game.keywords.register(veto)
	var card := await put_creature(1, define_creature(1, 3, {"Occupy": 1, "Veto": 1}))
	go_to_main()
	assert_eq(occupy_kw.occupy_problem(card), "It cannot occupy now")
	assert_false(occupy_kw.occupy(card))
	assert_eq(_occupy_ids(card), [], "The button is not offered")
	assert_false(await game.actions.run(card, "occupy"))
	assert_eq(_zone(card), "creatures")
	assert_false(veto.hooks_called("can_occupy").is_empty(), "The registry asked the keyword")
	veto.allow_occupy = true
	assert_true(await game.actions.run(card, "occupy"))
	assert_eq(_zone(card), "occupied")


func test_productive_rule_applies_through_the_registry():
	# Without Productive a creature cannot occupy the turn it was played (KwProductive)
	var card := await put_creature(1, 1, 3, {"Occupy": 1})
	go_to_main()
	card.entered_turn = game.turn_number
	assert_false(occupy_kw.can_occupy_now(card))
	assert_eq(_occupy_ids(card), [])
	card.entered_turn = game.turn_number - 1
	assert_true(occupy_kw.can_occupy_now(card))


# --- the action ---------------------------------------------------------------------------------------

func test_the_action_is_offered_only_to_creatures_with_the_ability():
	var with_ability := await put_creature(1, 1, 3, {"Occupy": 1})
	var without := await put_creature(1, 2, 2)
	go_to_main()
	assert_eq(_occupy_ids(with_ability), ["occupy"])
	assert_eq(_occupy_ids(without), [])
	var action: Dictionary = game.actions.find(with_ability, "occupy")
	assert_true(action.enabled)
	assert_eq(action.label, "Occupy")
	game.stats.grant_keyword(without, "Occupy", 1, "permanent")
	assert_eq(_occupy_ids(without), ["occupy"], "A granted Occupy gives the button")


func test_a_card_with_its_own_occupy_ability_has_no_plain_button():
	# Goblin Ledgerkeeper's "Occupy: create a scrap token" is the button "Scrap"; a plain "Occupy" beside it would
	# tilt the creature and make nothing
	for card_name in [REAL_CARD, "Goblin Ledgerkeeper", "Streetside Recruiter", "Acquisition Fabricator"]:
		var card := await put_creature(1, card_name)
		go_to_main()
		card.entered_turn = game.turn_number - 1
		assert_true(occupy_kw.has_ability(card), card_name)
		assert_true(occupy_kw.script_occupies(card), card_name)
		assert_eq(_occupy_ids(card), [], "%s offers no plain Occupy" % card_name)
		assert_false(await game.actions.run(card, "occupy"), card_name)
		assert_true(game.actions.list(card).any(func(a): return a.get("costs", []).any(func(c): return c.id == "occupy")),
				"%s still offers its own ability" % card_name)
	var granted := await put_creature(1, 2, 2)
	game.stats.grant_keyword(granted, "Occupy", 1, "permanent")
	assert_false(occupy_kw.script_occupies(granted))
	assert_eq(_occupy_ids(granted), ["occupy"], "an equipment that grants Occupy still gets the plain button")


func test_the_ledgerkeeper_button_makes_the_scrap():
	var card := await put_creature(1, "Goblin Ledgerkeeper")
	go_to_main()
	card.entered_turn = game.turn_number - 1
	assert_eq(game.tokens.counter(1, "scrap"), 0)
	assert_true(await game.actions.run(card, "scrap"))
	assert_eq(game.tokens.counter(1, "scrap"), 1)
	assert_eq(_zone(card), "occupied")


func test_running_the_action_occupies_and_reports_it():
	var card := await _occupier()
	var performed := []
	game.actions.action_performed.connect(func(c, id): performed.append([c, id]))
	assert_true(await game.actions.run(card, "occupy"))
	assert_eq(_zone(card), "occupied")
	assert_eq(card.card_rotation, 90)
	assert_eq(performed, [[card, "occupy"]])
	assert_eq(_occupy_ids(card), [], "Gone once the creature is occupied")


func test_a_refused_action_does_not_report():
	var card := await put_creature(1, 1, 3, {"Occupy": 1})
	var performed := []
	game.actions.action_performed.connect(func(c, id): performed.append([c, id]))
	assert_false(await game.actions.run(card, "occupy"), "Energy phase")
	assert_eq(performed, [])
