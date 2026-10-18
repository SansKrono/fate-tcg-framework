# Answers the questions card effects ask (game.choices, FateChoices.gd): which target, which cards, and
# "you may ..." confirmations. The AI controller installs `choose` and `confirm` as the chooser and
# confirmer of its seat, so a spell that needs a target never waits for a person.
#
# The AI cannot know what an arbitrary effect does with its pick, so it infers the INTENT of the choice:
#   "harm"  the pick suffers: destroy, damage, take control of, negate, remove, discard (opponent's things)
#   "help"  the pick benefits: buffs, returning, equipping, drawing, switching (own things)
#   "give"  the AI pays or gives something up: a consume cost, "discard a card", "target opponent chooses"
# Sources of the intent, best first:
#   1. the card script: an optional method `ai_intent(request) -> String` ("harm" / "help" / "give" / "")
#   2. the kind and the rules text of the card (keyword lists below)
#   3. the options themselves: all of the opponent's -> harm, all of the AI's own -> help
# Then each option is scored by what it is worth (creatures: FateAIEval.unit_value; other cards in play
# and cards in zones: hand_value), flipped by the intent, and the best `count` win. A card script that
# knows better only has to define `ai_intent`, or answer through `default_choice`.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")
const Snapshot := preload("res://src/custom/fate/ai/FateAISnapshot.gd")

const HARM_WORDS := ["destroy", "damage", "deal ", "negate", "remove", "take control", "convert",
		"consume target", "opponent's", "enemy", "steal", "claimed", "to the bottom", "in strike position"]
const HELP_WORDS := ["gain", "+1", "+2", "return", "draw", "equip", "attach", "switch", "untap", "unoccupy",
		"your creature", "you control", "put into your", "move target card"]
const GIVE_WORDS := ["consume", "discard a", "sacrifice", "pay", "chooses", "give"]


# The chooser of a seat (FateChoices request in, answer out). `seat` is the AI's player id.
static func choose(game: FateGame, seat: int, profile, request: Dictionary):
	var options: Array = request.options
	if options.is_empty():
		return null
	var count: int = request.count
	var source = request.get("source")
	var intent := intent_of(game, seat, request)
	var scored: Array = []
	for o in options:
		var s := score_option(game, seat, o, intent)
		if profile.noise > 0.0:
			s += profile.rng.randf_range(-profile.noise, profile.noise)
		scored.append([s, o])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	# An optional choice that can only hurt the AI is skipped
	if request.optional and scored[0][0] <= -2.0:
		return null if count == 1 else []
	if count == 1:
		return scored[0][1]
	return scored.slice(0, mini(count, scored.size())).map(func(e): return e[1])


# The "you may ..." answer: the default of the request (the card's own preference) unless the prompt says
# something is lost and the AI would lose its last cards
static func confirm(game: FateGame, seat: int, _profile, request: Dictionary) -> bool:
	var prompt: String = str(request.get("prompt", "")).to_lower()
	if prompt.contains("discard") and game.player(seat).hand().get_all_cards().size() <= 1:
		return false
	return bool(request.get("default", true))


# --- intent -----------------------------------------------------------------------------------------

static func intent_of(game: FateGame, seat: int, request: Dictionary) -> String:
	var script = request.get("script")
	if script == null and request.get("source") is Card and game.card_effects != null:
		script = game.card_effects.effect_of(request.source.canonical_name)
	if script != null and script.has_method("ai_intent"):
		var declared: String = script.ai_intent(request)
		if declared != "":
			return declared
	var kind: String = str(request.get("kind", "")).to_lower()
	var text: String = kind
	var source = request.get("source")
	if source is Card:
		text += " " + str(source.properties.get("Abilities", "")).to_lower()
		# Somebody else's card asking me to pick: I choose what to give
		if source is FateCardTemplate and source.controller_id != request.player and "choose" in text:
			return "give"
	if kind.contains("consume") or kind.contains("discard") or kind.contains("sacrifice"):
		return "give"
	var harm := _hits(text, HARM_WORDS)
	var help := _hits(text, HELP_WORDS)
	if harm > help:
		return "harm"
	if help > harm:
		return "help"
	# Decide from the options
	var mine := 0
	var theirs := 0
	for o in request.options:
		var owner_id := _owner_of(o)
		if owner_id == seat:
			mine += 1
		elif owner_id != 0:
			theirs += 1
	if theirs > 0 and mine == 0:
		return "harm"
	return "help"


static func _hits(text: String, words: Array) -> int:
	var n := 0
	for w in words:
		if text.contains(w):
			n += 1
	return n


# Who the option belongs to: the controller of a card on the table, the owner of other cards, the player id
static func _owner_of(option) -> int:
	if option is FatePlayer:
		return option.id
	if option is FateCardTemplate:
		return option.controller_id if FateZones.zone_of(option) != "" else option.owner_id
	return 0


# --- scoring ------------------------------------------------------------------------------------------

# How much the AI wants this option picked, given the intent. Higher is better.
static func score_option(game: FateGame, seat: int, option, intent: String) -> float:
	var mine := _owner_of(option) == seat
	var worth := _worth(game, option)
	match intent:
		"harm":
			# Hit the opponent's best thing; never one's own
			return worth if not mine else -worth - 5.0
		"give":
			# Lose the least: own cards, the cheapest first
			return -worth if mine else -worth - 8.0
		_:
			# Help: the best of one's own; helping the opponent is worse than nothing
			return worth if mine else -worth - 5.0


# What a card or a player is worth
static func _worth(game: FateGame, option) -> float:
	if option is FatePlayer:
		return 4.0
	if not option is FateCardTemplate:
		return 0.0
	var zone := FateZones.zone_of(option)
	if zone in FateZones.CREATURE_ZONES:
		return Eval.unit_value(Snapshot.unit_of(game, option))
	if zone != "":
		# A relic, field or world spell on the table
		return 1.5 + 0.5 * float(option.mana_value())
	return maxf(Eval.hand_value(game, option), 0.5)


# What casting a spell with a choice is worth on top of its base value, or -1 when it is not worth casting:
# a harmful spell with only the AI's own creatures to hit, a buff with only the opponent's to help.
static func cast_worth(game: FateGame, seat: int, card: Card) -> float:
	if game.card_effects == null:
		return 0.0
	var effect = game.card_effects.effect_of(card.canonical_name)
	if effect == null or not effect.has_choice:
		return 0.0
	var options: Array = effect.candidates(card, seat)
	if options.is_empty():
		return -1.0
	var request := {"kind": card.canonical_name, "player": seat, "source": card, "options": options,
			"count": 1, "optional": false, "script": effect}
	var intent := intent_of(game, seat, request)
	var best := -INF
	for o in options:
		best = maxf(best, score_option(game, seat, o, intent))
	return 0.5 * best if best > 0.0 else -1.0


# --- Savage ---------------------------------------------------------------------------------------------------

# The target of a Savage trigger of an AI creature (KwSavage.target_chooser; the arguments after `candidates`
# are filled in by bind): the blocking player when their life is low, otherwise a creature of theirs that the
# damage destroys and that is worth more than the damage to their life. `candidates[0]` is the blocking
# FatePlayer, the rest are their creatures. Null (no opinion) for creatures of a seat without an AI: the
# engine default (the blocking player) applies.
static func savage_target(attacker: Card, _attack, candidates: Array, amount: int, game: FateGame):
	if not is_instance_valid(game) or not game.ai_controllers.has(attacker.controller_id) \
			or candidates.is_empty():
		return null
	var player: FatePlayer = candidates[0]
	if player.life <= amount:
		return player
	var best = null
	var best_value := 1.4 * float(amount)
	for c in candidates.slice(1):
		if not c is Card or not FateZones.is_creature_in_play(c):
			continue
		var stat: String = game.effects.used_stat(c)
		if game.stats.current(c, stat) <= amount:
			var v := Eval.unit_value(Snapshot.unit_of(game, c))
			if v > best_value:
				best_value = v
				best = c
	return best if best != null else player
