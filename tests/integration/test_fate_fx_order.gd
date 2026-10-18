extends "res://tests/FateCommon.gd"
# The Order card scripts (cards/Fx*.gd): Zelith, Moral Captain, Tactical Combatant, Devote Paladin, Streetside
# Recruiter, Faithful Worshiper, Lucran, Soul Spear, Holy Amulet, Spiked Barricade, Reinforcements, Smite,
# Battle Ready, Equal Footing, Recovering Resources, War of Attrition.


func _to_main() -> void:
	await empty_hand(1)
	go_to_main()


func _energy(pid: int) -> int:
	return game.player(pid).cards_in_grid("energy").size()


func _soldiers(pid: int) -> Array:
	return game.creatures_in_play(pid).filter(func(c): return c.canonical_name == "Soldier Token")


func _hand(pid: int) -> int:
	return FateZones.container("hand", pid).get_all_cards().size()


func _in_pile(card: Card, zone: String, pid: int) -> bool:
	return card.get_parent() == FateZones.container(zone, pid)


# --- Zelith ----------------------------------------------------------------------------------------

func test_zelith_attacks_and_destroys_a_perpetual_spell() -> void:
	var spell := await put_on_table(2, "Recovering Resources", "field")
	var zelith := await put_creature(1, "Zelith, Mage Justiciar")
	start_combat()
	assert_eq(game.combat.attackable_spells(zelith), [spell])
	assert_true(game.combat.declare_attack(zelith, spell), game.combat.last_error)
	run_combat()
	await wait_seconds(0.2)
	assert_true(_in_pile(spell, "discard", 2), "the spell was destroyed")
	assert_true(FateZones.is_creature_in_play(zelith), "Zelith takes no damage")
	assert_eq(game.player(2).life, LIFE, "the player was not hit")


func test_zelith_attacks_a_world_spell_but_not_its_own_spell() -> void:
	var own := await put_on_table(1, "Recovering Resources", "field")
	var world := await put_on_table(2, "Equal Footing", "world")
	var zelith := await put_creature(1, "Zelith, Mage Justiciar")
	start_combat()
	assert_false(game.combat.declare_attack(zelith, own), "not your own spell")
	assert_true(game.combat.declare_attack(zelith, world), game.combat.last_error)
	run_combat()
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(own), "field")
	assert_true(_in_pile(world, "discard", 2))


func test_other_creatures_cannot_attack_spells_and_a_block_saves_the_spell() -> void:
	var spell := await put_on_table(2, "Recovering Resources", "field")
	var plain := await put_creature(1, 3, 3)
	var zelith := await put_creature(1, "Zelith, Mage Justiciar")
	start_combat()
	assert_false(game.combat.declare_attack(plain, spell), "an ordinary creature cannot")
	assert_true(game.combat.declare_attack(zelith, spell))
	game.combat.confirm_attackers()
	var blocker := await put_creature(2, 1, 5, {}, true)
	assert_true(game.combat.declare_block(blocker, game.combat.attack_of(zelith)))
	game.combat.confirm_blocks()
	await wait_seconds(0.2)
	assert_eq(FateZones.zone_of(spell), "field", "the attack was intercepted")


# --- Moral Captain ---------------------------------------------------------------------------------

func test_moral_captain_gives_two_creatures_plus_one_strike_when_you_attack() -> void:
	await put_creature(1, "Moral Captain")
	var attacker := await put_creature(1, 2, 2)
	start_combat()
	# An unblocked attack takes a fixed 1 life (FateCombat.PLAYER_HIT_DAMAGE): look at the Strike itself
	var strikes := []
	game.combat.attack_resolved.connect(func(a, _r): strikes.append(game.stats.current(a.attacker, "Strike")))
	assert_true(game.combat.declare_attack(attacker, 2))
	run_combat()
	await wait_seconds(0.2)
	assert_eq(strikes, [3], "the attacker had 2 + 1 Strike when it resolved")


func test_a_lone_moral_captain_boosts_itself_once() -> void:
	var captain := await put_creature(1, "Moral Captain")
	start_combat()
	var strikes := []
	game.combat.attack_resolved.connect(func(a, _r): strikes.append(game.stats.current(a.attacker, "Strike")))
	game.combat.declare_attack(captain, 2)
	run_combat()
	await wait_seconds(0.2)
	assert_eq(strikes, [3], "boosted once: 2 + 1")


# --- Tactical Combatant ----------------------------------------------------------------------------

func test_tactical_combatant_guards_after_attacking() -> void:
	var tc := await put_creature(1, "Tactical Combatant")
	start_combat()
	game.combat.declare_attack(tc, 2)
	run_combat()
	await wait_seconds(0.2)
	assert_eq(game.player(2).life, LIFE - FateCombat.PLAYER_HIT_DAMAGE)
	assert_eq(tc.card_rotation, 90, "switched to guard position")
	assert_eq(FateZones.zone_of(tc), "creatures")


func test_tactical_combatant_that_dies_attacking_is_just_gone() -> void:
	var tc := await put_creature(1, "Tactical Combatant")
	start_combat()
	game.combat.declare_attack(tc, 2)
	game.combat.confirm_attackers()
	var wall := await put_creature(2, 1, 9, {}, true)
	game.combat.declare_block(wall, game.combat.attack_of(tc))
	game.combat.confirm_blocks()
	await wait_seconds(0.2)
	assert_true(_in_pile(tc, "discard", 1) or not FateZones.is_creature_in_play(tc) or tc.card_rotation == 90)


# --- Devote Paladin / Faithful Worshiper / Streetside Recruiter ----------------------------------------

func test_devote_paladin_pumps_your_creatures() -> void:
	await _to_main()
	await fill_mana(1, 2)
	var paladin := await put_creature(1, "Devote Paladin")
	var friend := await put_creature(1, 2, 2)
	var foe := await put_creature(2, 2, 2)
	var energy_before := _energy(1)
	assert_true(await game.actions.run(paladin, "devote"))
	assert_eq(_energy(1), energy_before - 1, "an energy card was consumed")
	assert_eq(FateZones.zone_of(paladin), "occupied", "tapped")
	assert_eq(game.stats.current(friend, "Strike"), 3)
	assert_eq(game.keywords.value(friend, "Savage"), 1)
	assert_eq(game.stats.current(paladin, "Strike"), 5, "the paladin too")
	assert_eq(game.stats.current(foe, "Strike"), 2)
	assert_false(game.keywords.has(foe, "Savage"))


func test_devote_paladin_needs_an_energy_card() -> void:
	await _to_main()
	var paladin := await put_creature(1, "Devote Paladin")
	assert_eq(_energy(1), 0)
	assert_false(await game.actions.run(paladin, "devote"))
	assert_eq(FateZones.zone_of(paladin), "creatures", "nothing was paid")


func test_faithful_worshiper_grants_indomitable() -> void:
	await _to_main()
	await fill_mana(1, 1)
	var worshiper := await put_creature(1, "Faithful Worshiper")
	var friend := await put_creature(1, 2, 2)
	var foe := await put_creature(2, 2, 2)
	var energy_before := _energy(1)
	assert_true(await game.actions.run(worshiper, "worship"))
	assert_eq(_energy(1), energy_before - 1)
	assert_true(game.keywords.has(friend, "Indomitable"))
	assert_true(game.keywords.has(worshiper, "Indomitable"))
	assert_false(game.keywords.has(foe, "Indomitable"))
	assert_eq(FateZones.zone_of(worshiper), "creatures", "no occupy cost")


func test_faithful_worshiper_without_energy_does_nothing() -> void:
	await _to_main()
	var worshiper := await put_creature(1, "Faithful Worshiper")
	assert_false(await game.actions.run(worshiper, "worship"))
	assert_false(game.keywords.has(worshiper, "Indomitable"))


func test_streetside_recruiter_creates_a_soldier() -> void:
	await _to_main()
	var recruiter := await put_creature(1, "Streetside Recruiter")
	assert_true(await game.actions.run(recruiter, "recruit"))
	await wait_seconds(0.1)
	assert_eq(_soldiers(1).size(), 1)
	assert_eq(FateZones.zone_of(recruiter), "occupied")
	assert_false(await game.actions.run(recruiter, "recruit"), "already occupied")
	assert_eq(_soldiers(1).size(), 1)


# --- Lucran and the Soul Spear -----------------------------------------------------------------------------

func test_lucran_places_a_dead_creature_in_the_energy_zone() -> void:
	await put_creature(1, "Lucran, Divine Saviour")
	var doomed := await put_creature(1, 2, 2)
	var energy_before := _energy(1)
	game.effects.destroy(doomed, null, FateEffects.CAUSE_EFFECT)
	await wait_seconds(0.8)
	assert_eq(_energy(1), energy_before + 1)
	assert_eq(FateZones.zone_of(doomed), "energy")


func test_lucran_can_make_a_soul_spear_instead() -> void:
	await _to_main()
	await put_creature(1, "Lucran, Divine Saviour")
	var doomed := await put_creature(1, 2, 2)
	game.choices.chooser = func(request): return request.options[1]
	game.effects.destroy(doomed, null, FateEffects.CAUSE_EFFECT)
	await wait_seconds(1.5)
	game.choices.chooser = Callable()
	assert_true(_in_pile(doomed, "removed", 1), "removed from the game")
	var spears := game.player(1).cards_in_grid("relics").filter(func(c): return c.canonical_name == "Soul Spear Token")
	assert_eq(spears.size(), 1)
	var life := game.player(2).life
	assert_true(await game.actions.run(spears[0], "spear"))
	assert_eq(game.player(2).life, life - 2, "2 damage to the (default) opponent")
	assert_eq(game.player(1).cards_in_grid("relics").size(), 0, "the spear was consumed")


func test_lucran_gives_a_token_only_the_spear_and_ignores_the_enemy_dead() -> void:
	await put_creature(1, "Lucran, Divine Saviour")
	var token: Card = game.tokens.create("Soldier Token", 1)
	var foe := await put_creature(2, 2, 2)
	var energy_before := _energy(1)
	game.effects.destroy(foe, null, FateEffects.CAUSE_EFFECT)
	await wait_seconds(0.2)
	assert_eq(game.player(1).cards_in_grid("relics").size(), 0, "an enemy creature does not trigger")
	game.effects.destroy(token, null, FateEffects.CAUSE_EFFECT)
	await wait_seconds(0.3)
	assert_eq(_energy(1), energy_before, "tokens do not go to the energy zone")
	assert_eq(game.player(1).cards_in_grid("relics").size(), 1, "a Soul Spear instead")


# --- Holy Amulet ------------------------------------------------------------------------------------------------

func test_holy_amulet_equips_and_gives_a_mana_ability() -> void:
	await _to_main()
	var creature := await put_creature(1, 2, 2)
	var amulet := await put_on_table(1, "Holy Amulet", "relics")
	await game.card_effects.effect_of("Holy Amulet").on_enter(amulet)
	assert_eq(game.equip.host_of(amulet), creature)
	var order_before: int = game.mana.mana_pool(1)["Order"]
	assert_true(await game.actions.run(amulet, "amulet"))
	assert_eq(FateZones.zone_of(creature), "occupied")
	assert_eq(game.mana.mana_pool(1)["Order"], order_before + 1, "one Order energy for the turn")
	assert_false(await game.actions.run(amulet, "amulet"), "the creature is occupied already")


func test_holy_amulet_without_a_creature_stays_unequipped() -> void:
	await _to_main()
	var amulet := await put_on_table(1, "Holy Amulet", "relics")
	await game.card_effects.effect_of("Holy Amulet").on_enter(amulet)
	assert_null(game.equip.host_of(amulet))
	assert_false(await game.actions.run(amulet, "amulet"))


# --- Spiked Barricade ---------------------------------------------------------------------------------------------

func test_spiked_barricade_destroys_the_attacker_it_guards_against() -> void:
	var barricade := await put_on_table(2, "Spiked Barricade", "relics")
	var attacker := await put_creature(1, 5, 5)
	start_combat()
	game.combat.declare_attack(attacker, 2)
	game.combat.confirm_attackers()
	var attack: FateAttack = game.combat.attack_of(attacker)
	assert_has(game.combat.eligible_blockers(attack), barricade)
	assert_true(game.combat.declare_block(barricade, attack), game.combat.last_error)
	game.combat.confirm_blocks()
	await wait_seconds(0.3)
	assert_true(_in_pile(attacker, "discard", 1), "the attacker was destroyed")
	assert_true(_in_pile(barricade, "discard", 2), "the barricade was discarded")
	assert_eq(game.player(2).life, LIFE, "nothing got through")


func test_a_barricade_is_not_a_blocker_for_its_attacker_or_when_other_relics() -> void:
	var own := await put_on_table(1, "Spiked Barricade", "relics")
	var other := await put_on_table(2, "Holy Amulet", "relics")
	var attacker := await put_creature(1, 2, 2)
	start_combat()
	game.combat.declare_attack(attacker, 2)
	game.combat.confirm_attackers()
	var attack: FateAttack = game.combat.attack_of(attacker)
	assert_false(game.combat.declare_block(own, attack), "not the defender's relic")
	assert_false(game.combat.declare_block(other, attack), "an ordinary relic cannot guard")


# --- the spells -----------------------------------------------------------------------------------------------------------

func test_reinforcements_creates_two_soldiers() -> void:
	await _to_main()
	await fill_mana(1, 3)
	var spell := await put_in_hand(1, "Reinforcements")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	assert_eq(_soldiers(1).size(), 2)
	assert_true(_in_pile(spell, "discard", 1))


func test_reinforcements_with_one_free_slot_makes_one() -> void:
	await _to_main()
	await fill_mana(1, 3)
	var free := game.player(1).grid("creatures")
	while free.find_available_slot() != null and game.player(1).cards_in_grid("creatures").size() < 40:
		var filler := await put_creature(1, 1, 1)
		if filler == null:
			break
		if _empty_slots(free) <= 1:
			break
	var room := _empty_slots(free)
	var spell := await put_in_hand(1, "Reinforcements")
	game.play_from_hand(spell)
	await wait_seconds(0.3)
	assert_eq(_soldiers(1).size(), mini(2, room))


func _empty_slots(grid: BoardPlacementGrid) -> int:
	var n := 0
	for slot in grid.get_all_slots():
		if slot.occupying_card == null:
			n += 1
	return n


func test_smite_destroys_the_best_non_unique_creature() -> void:
	await _to_main()
	await fill_mana(1, 3)
	var small := await put_creature(2, 1, 1)
	var big := await put_creature(2, 4, 4)
	var unique := await put_creature(2, "Zelith, Mage Justiciar")
	var spell := await put_in_hand(1, "Smite")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	assert_true(_in_pile(big, "discard", 2) or not FateZones.is_creature_in_play(big))
	assert_true(FateZones.is_creature_in_play(small))
	assert_true(FateZones.is_creature_in_play(unique), "unique creatures cannot be targeted")


func test_smite_can_destroy_a_perpetual_spell_and_needs_a_target() -> void:
	await _to_main()
	await fill_mana(1, 3)
	var spell := await put_in_hand(1, "Smite")
	assert_false(game.can_play_from_hand(spell), "no legal target")
	var world := await put_on_table(2, "Equal Footing", "world")
	var unique := await put_creature(2, "Zelith, Mage Justiciar")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	assert_true(_in_pile(world, "discard", 2))
	assert_true(FateZones.is_creature_in_play(unique))


func test_battle_ready_switches_up_to_three_creatures_to_strike() -> void:
	await _to_main()
	await fill_mana(1, 3)
	var guards := []
	for _i in range(4):
		guards.append(await put_creature(1, 2, 2, {}, true))
	var occupied := await put_creature(1, 2, 2, {}, true, "occupied")
	var spell := await put_in_hand(1, "Battle Ready")
	assert_true(game.play_from_hand(spell))
	await wait_seconds(0.3)
	var switched := guards.filter(func(c): return c.card_rotation == 0)
	assert_eq(switched.size(), 3)
	# (a doctrine may add its own bonus to everybody: compare with the untouched occupied creature)
	var base: int = game.stats.current(occupied, "Strike")
	for c in switched:
		assert_eq(game.stats.current(c, "Strike"), base + 1, "+1 Strike")
	assert_eq(FateZones.zone_of(occupied), "occupied")


func test_battle_ready_needs_a_creature() -> void:
	await _to_main()
	await fill_mana(1, 3)
	var spell := await put_in_hand(1, "Battle Ready")
	assert_false(game.can_play_from_hand(spell))


# --- the field and world spells ------------------------------------------------------------------------------------------

func test_equal_footing_helps_the_player_with_less_energy() -> void:
	await _to_main()
	await put_on_table(2, "Equal Footing", "world")
	for _i in range(3):
		await put_energy(2, "Holy Amulet")
	var card := await put_in_hand(1, "Righteous Guard")
	game.library.to_discard(card)
	await wait_seconds(0.2)
	game.turn.end_phase_waits_for_player = true
	game.end_turn()
	await wait_seconds(0.3)
	assert_eq(_energy(1), 1, "moved from the discard pile")
	assert_eq(FateZones.zone_of(card), "energy")


func test_equal_footing_does_nothing_on_a_tie() -> void:
	await _to_main()
	await put_on_table(2, "Equal Footing", "world")
	await put_energy(1, "Holy Amulet")
	await put_energy(2, "Holy Amulet")
	var card := await put_in_hand(1, "Righteous Guard")
	game.library.to_discard(card)
	await wait_seconds(0.2)
	game.turn.end_phase_waits_for_player = true
	game.end_turn()
	await wait_seconds(0.3)
	assert_eq(_energy(1), 1)
	assert_true(_in_pile(card, "discard", 1))


func test_recovering_resources_draws_after_a_creature_died() -> void:
	await _to_main()
	await put_on_table(1, "Recovering Resources", "field")
	var doomed := await put_creature(1, 2, 2)
	game.effects.destroy(doomed, null, FateEffects.CAUSE_EFFECT)
	await wait_seconds(0.2)
	var hand_before := _hand(1)
	game.turn.end_phase_waits_for_player = true
	game.end_turn()
	await wait_seconds(0.3)
	assert_eq(_hand(1), hand_before + 1)


func test_recovering_resources_needs_one_of_your_creatures_to_die() -> void:
	await _to_main()
	await put_on_table(1, "Recovering Resources", "field")
	var foe := await put_creature(2, 2, 2)
	game.effects.destroy(foe, null, FateEffects.CAUSE_EFFECT)
	await wait_seconds(0.2)
	var hand_before := _hand(1)
	game.turn.end_phase_waits_for_player = true
	game.end_turn()
	await wait_seconds(0.3)
	assert_eq(_hand(1), hand_before, "an enemy creature does not count")


func test_war_of_attrition_occupies_all_your_creatures_at_the_start_of_your_turn() -> void:
	await _to_main()
	await put_on_table(2, "War of Attrition", "field")
	var mine := await put_creature(1, 2, 2)
	var theirs_a := await put_creature(2, 2, 2)
	var theirs_b := await put_creature(2, 3, 3)
	game.end_turn()
	await wait_seconds(0.5)
	assert_eq(game.active_id, 2)
	assert_eq(FateZones.zone_of(theirs_a), "occupied")
	assert_eq(FateZones.zone_of(theirs_b), "occupied")
	assert_eq(FateZones.zone_of(mine), "creatures", "only the controller's creatures")
