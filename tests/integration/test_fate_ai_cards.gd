extends "res://tests/FateCommon.gd"
# The AI and the card-logic layer: it answers the choices of card effects, knows which cards do something
# (a registered script with real hooks) and uses the cheap abilities of card scripts.

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const AIChoices := preload("res://src/custom/fate/ai/FateAIChoices.gd")
const MainPhase := preload("res://src/custom/fate/ai/FateAIMain.gd")
const Abilities := preload("res://src/custom/fate/ai/FateAIAbilities.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")
const Profile := preload("res://src/custom/fate/ai/FateAIProfile.gd")


# A card script with a target choice over all creatures, and an optional hand-made intent
class TargetFx:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var intent := ""
	var picked = null

	func _init(name_of_card := "") -> void:
		card_name = name_of_card
		has_choice = true

	func candidates(_card: Card, _caster_id: int) -> Array:
		return game.creatures_in_play()

	func ai_intent(_request: Dictionary) -> String:
		return intent

	func resolve(_card: Card, _caster_id: int, choice) -> void:
		picked = choice


# A permanent with an Occupy ability
class AbilityFx:
	extends "res://src/custom/fate/cards/FateCardEffect.gd"
	var ran := 0

	func _init(name_of_card := "") -> void:
		card_name = name_of_card

	func actions(card: Card) -> Array:
		return [make_action(card, "work", "Work", "Occupy: do work", [game.costs.occupy()],
				func(_c): ran += 1)]


func _profile() -> Profile:
	var p := Profile.new()
	p.configure(["Order"], Profile.Level.NORMAL, 7)
	p.pace = 0.0
	return p


func _request(kind: String, source: Card, options: Array, extra := {}) -> Dictionary:
	var r := {"kind": kind, "player": 1, "source": source, "options": options, "count": 1,
			"optional": false, "default": options[0] if not options.is_empty() else null}
	r.merge(extra, true)
	return r


func test_a_harmful_choice_hits_the_opponents_best_creature() -> void:
	var fx := TargetFx.new("Smite")
	fx.intent = "harm"
	game.card_effects.register(fx)
	var mine := await put_creature(1, 5, 5)
	var weak := await put_creature(2, 1, 1)
	var strong := await put_creature(2, 4, 3)
	var spell := await put_in_hand(1, "Smite")
	var answer = AIChoices.choose(game, 1, _profile(), _request("Smite", spell, [mine, weak, strong], {"script": fx}))
	assert_eq(answer, strong)


func test_the_intent_is_read_from_the_rules_text() -> void:
	# Smite: "Destroy target ..." -> harm, without any hint from the script
	var spell := await put_in_hand(1, "Smite")
	var mine := await put_creature(1, 5, 5)
	var theirs := await put_creature(2, 2, 2)
	assert_eq(AIChoices.intent_of(game, 1, _request("target creature", spell, [mine, theirs])), "harm")
	var answer = AIChoices.choose(game, 1, _profile(), _request("target creature", spell, [mine, theirs]))
	assert_eq(answer, theirs)


func test_a_helpful_choice_picks_the_own_best_creature_and_a_cost_gives_the_cheapest() -> void:
	var spell := await put_in_hand(1, "Battle Ready")
	var small := await put_creature(1, 1, 1)
	var big := await put_creature(1, 4, 4)
	var enemy := await put_creature(2, 6, 6)
	var help = AIChoices.choose(game, 1, _profile(), _request("target creature", spell, [small, big, enemy],
			{"script": null}))
	# "Switch up to 3 target creatures ... +1 Strike": a buff
	assert_eq(help, big)
	var give = AIChoices.choose(game, 1, _profile(), _request("card to consume", spell, [big, small]))
	assert_eq(give, small, "a consume cost gives up the cheapest")


func test_several_picks_and_an_unwanted_optional_pick() -> void:
	var spell := await put_in_hand(1, "Smite")
	var a := await put_creature(2, 3, 3)
	var b := await put_creature(2, 1, 1)
	var c := await put_creature(2, 5, 5)
	var two = AIChoices.choose(game, 1, _profile(), _request("target creatures", spell, [a, b, c], {"count": 2}))
	assert_eq(two.size(), 2)
	assert_has(two, c)
	assert_has(two, a)
	# Only own creatures to destroy, and the pick is optional: skip
	var mine := await put_creature(1, 5, 5)
	var none = AIChoices.choose(game, 1, _profile(), _request("target creature", spell, [mine], {"optional": true}))
	assert_null(none)


func test_a_seat_with_an_ai_answers_through_game_choices() -> void:
	var fx := TargetFx.new("Smite")
	fx.intent = "harm"
	game.card_effects.register(fx)
	game.set_ai(1)
	var mine := await put_creature(1, 5, 5)
	var theirs := await put_creature(2, 2, 2)
	var spell := await put_in_hand(1, "Smite")
	var answer = await game.choices.pick("target creature", 1, spell, [mine, theirs])
	assert_eq(answer, theirs, "the AI chooser of seat 1 answered")
	game.set_ai(1, false)
	assert_false(game.choices.choosers.has(1), "switched off, the chooser is gone")


func test_cards_without_a_real_script_are_dead_and_cards_with_one_are_live() -> void:
	var dead := await put_in_hand(1, "Smite")
	assert_eq(Eval.role(game, dead), "dead", "a spell with no script does nothing")
	var fx := TargetFx.new("Smite")
	game.card_effects.register(fx)
	assert_eq(Eval.role(game, dead), "live", "its script defines resolve")
	assert_gt(Eval.hand_value(game, dead), 1.5)
	var creature := await put_in_hand(1, "Moral Captain")
	assert_eq(Eval.role(game, creature), "creature")


func test_a_harmful_spell_is_not_cast_without_a_worthy_target() -> void:
	var fx := TargetFx.new("Smite")
	fx.intent = "harm"
	game.card_effects.register(fx)
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()
	var spell := await put_in_hand(1, "Smite")
	await put_creature(1, 3, 3)
	var plan := MainPhase.plan_plays(game, Snapshot.build(game, 1), _profile())
	assert_false(spell in plan.plays, "only its own creature to hit: not cast")
	await put_creature(2, 3, 3)
	plan = MainPhase.plan_plays(game, Snapshot.build(game, 1), _profile())
	assert_true(spell in plan.plays, "an enemy creature to hit: cast")


func test_a_cheap_ability_is_used_by_a_creature_that_stays_home() -> void:
	var fx := AbilityFx.new("Streetside Recruiter")
	game.card_effects.register(fx)
	await empty_hand(1)
	await fill_mana(1, 3)
	go_to_main()
	var creature := await put_creature(1, "Streetside Recruiter")
	var state := Snapshot.build(game, 1)
	var home := Abilities.plan_generic(game, state, _profile(), 3, {})
	assert_eq(home.size(), 1, "an Occupy ability of a creature that does not attack")
	var attacking := {creature.get_instance_id(): true}
	assert_eq(Abilities.plan_generic(game, state, _profile(), 3, attacking).size(), 0,
			"not when it attacks: it must stay upright")
	assert_true(await game.actions.run(creature, home[0].id))
	assert_eq(fx.ran, 1)
