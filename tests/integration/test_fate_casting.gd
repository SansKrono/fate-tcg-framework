extends "res://tests/FateCommon.gd"
# Casting from other zones (FateCasting, game.casting): flip cast from the energy zone, cast from the discard
# pile, return to the table, creatures borrowed from the energy zone, flip cast permissions.
# Player 1 plays Order: every card used here is an Order card unless the test says otherwise.

const ENERGY_CARD := "Holy Amulet"


# Records what the game tells the script of one card
class Recorder:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var log: Array = []
	var picks: Array = []

	func _init(name_of_card := "") -> void:
		card_name = name_of_card

	func candidates(_card: Card, _caster_id: int) -> Array:
		return picks

	func default_choice(_card: Card, _caster_id: int):
		return picks[0] if not picks.is_empty() else null

	func resolve(_card: Card, caster_id: int, choice) -> void:
		log.append(["resolve", caster_id, choice])

	func on_play(_card: Card) -> void:
		log.append(["play"])

	func on_enter(_card: Card) -> void:
		log.append(["enter"])

	func on_flip_cast(_card: Card, cast_card: Card, caster_id: int) -> void:
		log.append(["flip_cast", cast_card.canonical_name, caster_id])


func _names(log: Array) -> Array:
	return log.map(func(e): return e[0])


func _register(card_name: String) -> Recorder:
	var fx := Recorder.new(card_name)
	game.card_effects.register(fx)
	return fx


# `count` untapped energy cards that are not the card under test
func _energy(count: int, pid := 1) -> Array:
	var cards := []
	for _i in range(count):
		cards.append(await put_energy(pid, ENERGY_CARD))
	return cards


func _untapped(pid := 1) -> int:
	return game.mana.untapped_energy(pid).size()


func _in_discard(card_name: String, pid := 1) -> Card:
	var card: Card = await game.place_in_container(card_name, pid, "discard")
	await wait_seconds(0.1)
	return card


# --- flip cast: permanents -------------------------------------------------------------------------

func test_a_free_flip_cast_creature_enters_with_the_normal_triggers() -> void:
	var fx := _register("Moral Captain")
	await _energy(2)
	var captain := await put_energy(1, "Moral Captain")
	var mana_events := []
	game.mana_changed.connect(func(pid): mana_events.append(pid))
	assert_true(await game.casting.flip_cast_card(captain, 1, false))
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(captain), "creatures")
	assert_true(captain.is_faceup)
	assert_false(captain.is_energy)
	assert_eq(captain.controller_id, 1)
	assert_eq(captain.entered_turn, game.turn_number)
	assert_eq(_names(fx.log).filter(func(n): return n != "flip_cast"), ["play", "enter"])
	assert_eq(_untapped(), 2, "free: the other energy is not tapped")
	assert_true(1 in mana_events, "mana_changed was emitted")
	assert_false(game.keywords.can_attack(captain), "a new creature is summoning sick")


func test_the_energy_slot_of_a_flip_cast_card_is_free() -> void:
	await _energy(2)
	var captain := await put_energy(1, "Moral Captain")
	var slot: BoardPlacementSlot = captain._placement_slot
	assert_eq(game.player(1).cards_in_grid("energy").size(), 3)
	await game.casting.flip_cast_card(captain, 1, false)
	assert_null(slot.occupying_card, "no stale card in the old slot")
	assert_ne(captain._placement_slot, slot)
	assert_eq(game.player(1).cards_in_grid("energy").size(), 2)
	assert_false(captain in game.player(1).cards_in_grid("energy"))


func test_a_paid_flip_cast_is_paid_by_the_other_energy() -> void:
	await _energy(3)
	var captain := await put_energy(1, "Moral Captain")
	assert_eq(game.mana.cost_of(captain), {"generic": 1, "pips": {"Order": 2}})
	assert_true(await game.casting.flip_cast_card(captain, 1, true))
	assert_eq(_untapped(), 0, "3 mana for the captain, all from the other energy")
	assert_eq(FateZones.zone_of(captain), "creatures")


func test_the_flip_cast_card_never_pays_for_itself() -> void:
	var others := await _energy(2)
	var captain := await put_energy(1, "Moral Captain")
	# 3 untapped energy in the zone, but the captain is one of them and costs 3
	assert_eq(_untapped(), 3)
	assert_ne(game.casting.flip_cast_problem(captain, 1, true), "")
	assert_false(await game.casting.flip_cast_card(captain, 1, true))
	assert_eq(FateZones.zone_of(captain), "energy", "still in the energy zone")
	assert_true(captain.is_energy)
	assert_false(captain.is_faceup)
	assert_eq(_untapped(), 3, "nothing was tapped")
	for card in others:
		assert_eq(card.card_rotation, 0)
	# Free is fine
	assert_true(await game.casting.flip_cast_card(captain, 1, false))


func test_a_flip_cast_relic_goes_to_the_relic_zone() -> void:
	var fx := _register("Spiked Barricade")
	await _energy(2)
	var relic := await put_energy(1, "Spiked Barricade")
	assert_true(await game.casting.flip_cast_card(relic, 1, true))
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(relic), "relics")
	assert_true(relic.is_faceup)
	assert_eq(_names(fx.log).filter(func(n): return n != "flip_cast"), ["play", "enter"])
	assert_eq(_untapped(), 0)


func test_a_flip_cast_field_spell_takes_the_slot_and_replaces_the_old_one() -> void:
	var first := await put_energy(1, "Recovering Resources")
	assert_true(await game.casting.flip_cast_card(first, 1, false))
	assert_eq(FateZones.zone_of(first), "field")
	var second := await put_energy(1, "War of Attrition")
	assert_true(await game.casting.flip_cast_card(second, 1, false))
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(second), "field")
	assert_eq(first.get_parent(), FateZones.container("discard", 1), "the old field spell was replaced")
	assert_null(first._placement_slot)


# --- flip cast: spells -------------------------------------------------------------------------------------

func test_a_flip_cast_spell_resolves_and_goes_to_the_discard_pile() -> void:
	var fx := _register("Battle Ready")
	await _energy(3)
	var spell := await put_energy(1, "Battle Ready")
	assert_true(await game.casting.flip_cast_card(spell, 1, true))
	await wait_seconds(0.1)
	assert_eq(_names(fx.log), ["resolve", "play"])
	assert_eq(fx.log[0][1], 1, "cast by player 1")
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))
	assert_true(spell.is_faceup)
	assert_false(spell.is_energy)
	assert_eq(_untapped(), 0, "3 paid by the others")
	assert_false(spell in game.player(1).cards_in_grid("energy"))


func test_a_flip_cast_spell_is_not_paid_for_by_itself_either() -> void:
	_register("Battle Ready")
	await _energy(2)
	var spell := await put_energy(1, "Battle Ready")
	assert_false(await game.casting.flip_cast_card(spell, 1, true))
	assert_eq(FateZones.zone_of(spell), "energy")


func test_the_choice_of_a_flip_cast_spell_is_passed_on() -> void:
	var fx := _register("Battle Ready")
	fx.has_choice = true
	var a := await put_creature(2, "Moral Captain")
	var b := await put_creature(2, "Righteous Guard")
	fx.picks = [a, b]
	var s1 := await put_energy(1, "Battle Ready")
	await game.casting.flip_cast_card(s1, 1, false, b)
	assert_eq(fx.log[0], ["resolve", 1, b], "the given choice")
	fx.log.clear()
	var s2 := await put_energy(1, "Battle Ready")
	await game.casting.flip_cast_card(s2, 1, false)
	assert_eq(fx.log[0], ["resolve", 1, a], "without one, the default choice")


func test_a_spell_without_a_legal_target_cannot_be_flip_cast() -> void:
	game.card_effects.register(RefusingRecorder.new("Battle Ready"))
	var spell := await put_energy(1, "Battle Ready")
	assert_eq(game.casting.flip_cast_problem(spell, 1, false), "No target")
	assert_false(await game.casting.flip_cast_card(spell, 1, false))
	assert_eq(FateZones.zone_of(spell), "energy")


class RefusingRecorder:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"

	func _init(name_of_card := "") -> void:
		card_name = name_of_card

	func play_problem(_card: Card, _caster_id: int) -> String:
		return "No target"


func test_reaction_spells_cannot_be_flip_cast() -> void:
	var reaction := await put_energy(1, "Hold the Line")
	assert_ne(game.casting.flip_cast_problem(reaction, 1, false), "")
	assert_false(await game.casting.flip_cast_card(reaction, 1, false))
	assert_eq(FateZones.zone_of(reaction), "energy")


func test_only_a_card_of_the_players_own_energy_zone_can_be_flip_cast() -> void:
	var theirs := await put_energy(2, "Moral Captain")
	assert_false(await game.casting.flip_cast_card(theirs, 1, false))
	var hand_card := await put_in_hand(1, "Moral Captain")
	assert_false(await game.casting.flip_cast_card(hand_card, 1, false))


func test_flip_castable_lists_the_energy_cards_that_can_be_cast() -> void:
	await _energy(3)
	var captain := await put_energy(1, "Moral Captain")
	var reaction := await put_energy(1, "Hold the Line")
	var castable: Array = game.casting.flip_castable(1)
	assert_true(captain in castable)
	assert_false(reaction in castable, "reactions cannot be flip cast")
	var creatures: Array = game.casting.flip_castable(1, func(c): return c.properties.get("Type") == "Creature")
	assert_eq(creatures, [captain])
	# Only the ones the others can pay for: the captain costs 3, three other energy cards exist (the
	# reaction card is one of them)
	assert_true(captain in game.casting.flip_castable(1, Callable(), true))
	assert_eq(game.casting.flip_castable(2), [])


# --- permissions -------------------------------------------------------------------------------------------------

func test_a_permission_is_a_number_of_uses_for_this_turn() -> void:
	assert_false(game.casting.can_flip_cast(1))
	game.casting.grant_permission(1, "dockside_alter")
	assert_true(game.casting.can_flip_cast(1))
	assert_false(game.casting.can_flip_cast(2))
	assert_eq(game.casting.permission_uses(1, "dockside_alter"), 1)
	assert_true(game.casting.use_permission(1))
	assert_false(game.casting.can_flip_cast(1))
	assert_false(game.casting.use_permission(1))
	game.casting.grant_permission(1, "x", 2)
	assert_true(game.casting.use_permission(1, "x"))
	assert_eq(game.casting.permission_uses(1, "x"), 1)
	game.casting.revoke_permission(1, "x")
	assert_false(game.casting.can_flip_cast(1))


func test_flip_casting_with_a_permission_spends_one_use_only_when_it_works() -> void:
	game.casting.grant_permission(1, "subtle", 1)
	var captain := await put_energy(1, "Moral Captain")
	# Not payable: the permission stays
	assert_false(await game.casting.flip_cast_with_permission(captain, 1, true))
	assert_eq(game.casting.permission_uses(1, "subtle"), 1)
	assert_true(await game.casting.flip_cast_with_permission(captain, 1, false))
	assert_eq(game.casting.permission_uses(1, "subtle"), 0)
	var guard := await put_energy(1, "Righteous Guard")
	assert_false(await game.casting.flip_cast_with_permission(guard, 1, false), "no use left")
	assert_eq(FateZones.zone_of(guard), "energy")


func test_a_player_without_permission_cannot_use_the_permission_route() -> void:
	var guard := await put_energy(1, "Righteous Guard")
	assert_false(await game.casting.flip_cast_with_permission(guard, 1, false))
	# The action itself is the effect of a card and needs no standing permission
	assert_true(await game.casting.flip_cast_card(guard, 1, false))


func test_permissions_reset_when_a_turn_starts() -> void:
	game.casting.grant_permission(1, "once", 1)
	game.casting.grant_permission(1, "doctrine", 1, true)
	assert_true(game.casting.use_permission(1, "doctrine"))
	assert_eq(game.casting.permission_uses(1, "doctrine"), 0)
	# Granting an every-turn permission again does not renew it within the turn
	game.casting.grant_permission(1, "doctrine", 1, true)
	assert_eq(game.casting.permission_uses(1, "doctrine"), 0)
	game.end_turn()
	assert_eq(game.casting.permission_uses(1, "once"), 0, "a one-off grant ends with the turn")
	assert_eq(game.casting.permission_uses(1, "doctrine"), 1, "the doctrine's permission renews every turn")


# --- the flip_cast signal and the on_flip_cast hook ------------------------------------------------------------

func test_flip_cast_is_announced_to_the_cards_on_the_table() -> void:
	var watcher := _register("Eldritch Knowledge")
	await put_on_table(1, "Eldritch Knowledge", "field")
	var own := _register("Moral Captain")
	var seen := []
	game.casting.flip_cast.connect(func(card, pid): seen.append([card.canonical_name, pid]))
	var captain := await put_energy(1, "Moral Captain")
	await game.casting.flip_cast_card(captain, 1, false)
	await wait_seconds(0.1)
	assert_eq(seen, [["Moral Captain", 1]])
	assert_eq(watcher.log, [["flip_cast", "Moral Captain", 1]])
	assert_true(["flip_cast", "Moral Captain", 1] in own.log, "a card hears its own flip cast too")
	# A refused flip cast is announced to nobody
	watcher.log.clear()
	var reaction := await put_energy(1, "Hold the Line")
	await game.casting.flip_cast_card(reaction, 1, false)
	assert_eq(watcher.log, [])


func test_a_flip_cast_is_also_a_play_for_the_watchers() -> void:
	var watcher := _register("Eldritch Knowledge")
	var played := []
	game.card_played.connect(func(c): played.append(c))
	var captain := await put_energy(1, "Moral Captain")
	await game.casting.flip_cast_card(captain, 1, false)
	assert_eq(played, [captain], "card_played fires for a flip cast")
	assert_not_null(watcher)


# --- cast from the discard pile ------------------------------------------------------------------------------------

func test_a_creature_is_cast_from_the_discard_pile_paying_its_cost() -> void:
	var fx := _register("Righteous Guard")
	await fill_mana(1, 1)
	var guard := await _in_discard("Righteous Guard")
	assert_eq(guard.get_parent(), FateZones.container("discard", 1))
	assert_true(await game.casting.cast_from_discard(guard, 1, true))
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(guard), "creatures")
	assert_eq(guard.entered_turn, game.turn_number)
	assert_eq(_names(fx.log), ["play", "enter"])
	assert_eq(_untapped(), 0, "Righteous Guard costs 2")


func test_a_cast_from_the_discard_pile_needs_the_mana_unless_it_is_free() -> void:
	var guard := await _in_discard("Righteous Guard")
	assert_false(await game.casting.cast_from_discard(guard, 1, true))
	assert_eq(guard.get_parent(), FateZones.container("discard", 1), "still in the discard pile")
	assert_true(await game.casting.cast_from_discard(guard, 1, false))
	assert_eq(FateZones.zone_of(guard), "creatures")


func test_a_relic_is_cast_from_the_discard_pile() -> void:
	await _energy(2)
	var relic := await _in_discard("Spiked Barricade")
	assert_true(await game.casting.cast_from_discard(relic, 1, true))
	assert_eq(FateZones.zone_of(relic), "relics")
	assert_eq(_untapped(), 0)


func test_only_cards_in_the_owners_discard_pile_are_cast_from_it() -> void:
	var elsewhere := await put_in_hand(1, "Righteous Guard")
	assert_false(await game.casting.cast_from_discard(elsewhere, 1, false))
	var theirs := await _in_discard("Righteous Guard", 2)
	assert_false(await game.casting.cast_from_discard(theirs, 1, false), "the discard pile of the owner, cast by the owner")
	assert_true(await game.casting.cast_from_discard(theirs, 2, false))


func test_a_spell_cast_from_the_discard_pile_resolves_and_returns_to_it() -> void:
	var fx := _register("Battle Ready")
	await fill_mana(1, 2)
	var spell := await _in_discard("Battle Ready")
	assert_true(await game.casting.cast_from_discard(spell, 1, true))
	await wait_seconds(0.1)
	assert_eq(_names(fx.log), ["resolve", "play"])
	assert_eq(spell.get_parent(), FateZones.container("discard", 1))
	assert_eq(_untapped(), 1)


# --- return to the table ---------------------------------------------------------------------------------------------

func test_a_card_returns_to_the_table_without_being_cast() -> void:
	var fx := _register("Righteous Guard")
	var played := []
	game.card_played.connect(func(c): played.append(c))
	var guard := await _in_discard("Righteous Guard")
	assert_true(game.casting.return_to_table(guard, 1))
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(guard), "creatures")
	assert_eq(guard.card_rotation, 0)
	assert_eq(guard.entered_turn, game.turn_number)
	assert_eq(guard.controller_id, 1)
	assert_eq(_names(fx.log), ["enter"], "enters, but was not played")
	assert_eq(played, [])
	assert_eq(_untapped(), 0)


func test_a_card_can_return_to_the_table_tilted() -> void:
	var guard := await _in_discard("Righteous Guard")
	assert_true(game.casting.return_to_table(guard, 1, {"tilted": true}))
	assert_eq(FateZones.zone_of(guard), "creatures")
	assert_eq(guard.card_rotation, 90)


func test_a_relic_and_a_field_spell_return_to_their_zones() -> void:
	var relic := await _in_discard("Spiked Barricade")
	assert_true(game.casting.return_to_table(relic, 1))
	assert_eq(FateZones.zone_of(relic), "relics")
	var field := await _in_discard("Recovering Resources")
	assert_true(game.casting.return_to_table(field, 1))
	assert_eq(FateZones.zone_of(field), "field")


func test_a_regular_spell_or_a_card_off_a_pile_does_not_return_to_the_table() -> void:
	var spell := await _in_discard("Battle Ready")
	assert_false(game.casting.return_to_table(spell, 1))
	var in_hand := await put_in_hand(1, "Righteous Guard")
	assert_false(game.casting.return_to_table(in_hand, 1))


func test_a_full_zone_stops_a_return() -> void:
	var grid := FateZones.grid("creatures", 1)
	for _i in range(grid.get_slot_count()):
		await put_creature(1, 1, 1)
	var guard := await _in_discard("Righteous Guard")
	assert_false(game.casting.return_to_table(guard, 1))
	assert_eq(guard.get_parent(), FateZones.container("discard", 1))


# --- borrowed creatures ----------------------------------------------------------------------------------------------

func test_a_borrowed_creature_comes_with_charge_and_goes_back_at_the_end_of_the_turn() -> void:
	var fx := _register("Moral Captain")
	await _energy(2)
	var captain := await put_energy(1, "Moral Captain")
	assert_eq(_untapped(), 3)
	var borrowed: Card = game.casting.borrow_creature(captain, 1)
	assert_eq(borrowed, captain)
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(captain), "creatures")
	assert_true(captain.is_faceup)
	assert_false(captain.is_energy)
	assert_eq(_untapped(), 2, "one energy card less while it is on the table")
	assert_true(game.keywords.has(captain, "Charge"))
	assert_true(game.keywords.can_attack(captain), "it may attack the turn it is borrowed")
	assert_eq(_names(fx.log), ["enter"], "it enters, it is not cast")
	assert_true(game.casting.is_borrowed(captain))
	var slot: BoardPlacementSlot = captain._placement_slot
	go_to_main()
	game.end_turn()
	await wait_seconds(0.1)
	assert_eq(FateZones.zone_of(captain), "energy", "back in the energy zone")
	assert_true(captain.is_energy)
	assert_false(captain.is_faceup)
	assert_eq(captain.card_rotation, 0)
	assert_eq(_untapped(), 3)
	assert_false(game.keywords.has(captain, "Charge"))
	assert_false(game.casting.is_borrowed(captain))
	assert_ne(captain._placement_slot, slot)
	assert_null(slot.occupying_card, "its creature slot is free")


func test_a_borrowed_creature_that_was_destroyed_stays_in_the_discard_pile() -> void:
	var captain := await put_energy(1, "Moral Captain")
	game.casting.borrow_creature(captain, 1)
	await wait_seconds(0.1)
	assert_true(game.effects.destroy(captain))
	await wait_seconds(0.3)
	assert_eq(captain.get_parent(), FateZones.container("discard", 1))
	assert_false(game.casting.is_borrowed(captain))
	go_to_main()
	game.end_turn()
	await wait_seconds(0.2)
	assert_eq(captain.get_parent(), FateZones.container("discard", 1), "it did not return")
	assert_false(captain.is_energy)


func test_a_borrowed_creature_that_left_the_table_stays_where_it_went() -> void:
	var captain := await put_energy(1, "Moral Captain")
	game.casting.borrow_creature(captain, 1)
	await wait_seconds(0.1)
	assert_true(game.library.to_hand(captain))
	await wait_seconds(0.2)
	go_to_main()
	game.end_turn()
	await wait_seconds(0.2)
	assert_eq(captain.get_parent(), FateZones.container("hand", 1))


func test_only_a_creature_of_the_energy_zone_can_be_borrowed() -> void:
	var relic := await put_energy(1, "Spiked Barricade")
	assert_null(game.casting.borrow_creature(relic, 1))
	var hand_card := await put_in_hand(1, "Moral Captain")
	assert_null(game.casting.borrow_creature(hand_card, 1))
	var theirs := await put_energy(2, "Moral Captain")
	assert_null(game.casting.borrow_creature(theirs, 1))
	assert_eq(FateZones.zone_of(relic), "energy")


func test_a_creature_is_not_borrowed_into_a_full_creature_zone() -> void:
	var grid := FateZones.grid("creatures", 1)
	for _i in range(grid.get_slot_count()):
		await put_creature(1, 1, 1)
	var captain := await put_energy(1, "Moral Captain")
	assert_null(game.casting.borrow_creature(captain, 1))
	assert_eq(FateZones.zone_of(captain), "energy")
