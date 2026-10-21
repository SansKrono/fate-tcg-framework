# Base class of every card script: the rules text of ONE card, in code. One script per card in
# src/custom/fate/cards/, named Fx<CardName>.gd (spaces and punctuation removed: FxSteelworkSalvager.gd,
# FxThrangPerpetualInnovation.gd). The registry (FateCardEffects, `game.card_effects`) finds it by itself
# at startup, so adding a card never touches a shared file. Guide and examples: cards/README.md.
#
# A card script IS a keyword (it extends FateKeyword): the keyword registry runs its hooks for the card
# whose FateData name equals `card_name`, so everything a keyword can do, a card can do (attack and block
# restrictions, damage and destruction replacement, stat bonuses, death destination, "when this attacks /
# is blocked / dies / deals damage" triggers, hover actions, maintenance and end-of-turn triggers). See
# FateKeyword.gd and keywords/README.md for those hooks. This class adds what a card needs beyond them:
# being played, entering and leaving the table, watching other cards, static effects on other cards,
# spells with targets, activated abilities with costs.
#
# Like keywords, card scripts are stateless singletons. State lives on the card (properties, meta),
# the attack record (attack.metadata), the stats layer (modifiers and keyword grants with `source`
# set to the card, so they end by themselves when it leaves) or in the system that owns it
# (game.tokens counters, game.limiter uses, game.control ...). No `class_name` in card scripts.
#
# Everything here defaults to "does nothing": override only what the card does.
extends FateKeyword

# The card this script belongs to: the name in FateData.CARDS / TOKENS. Set it in _init().
var card_name := ""

# --- spells: playing and resolving ---------------------------------------------------------------------

# True if the caster picks something when the spell resolves (a target, a card from a list). The pick
# goes through game.choices (an AI or UI plugs in there); `candidates()` says what may be picked and
# `default_choice()` is what is taken when nobody chooses.
var has_choice := false


# Why this card cannot be played now (no legal target, an additional cost that cannot be paid, a
# condition of the card), or "" if it can. Checked by FateGame.can_play_from_hand before anything is
# paid. `caster_id` is the owner. Applies to every card type, not only spells.
func play_problem(_card: Card, _caster_id: int) -> String:
	return ""


# What the caster may pick from, for a spell or an enters trigger with a choice. Cards (or players:
# FatePlayer objects) in the order a deterministic fallback should take them.
func candidates(_card: Card, _caster_id: int) -> Array:
	return []


# What is chosen when nobody picks (null for no choice). Must be a valid answer for resolve().
func default_choice(_card: Card, _caster_id: int):
	return null


# Why this explicit choice is not allowed (checked before resolve), or "".
func choice_problem(_card: Card, _caster_id: int, _choice) -> String:
	return ""


# An additional cost of playing the card ("additional cost: consume X permanents"), paid after the mana
# and before the spell resolves. Return false if it could not be paid (then nothing resolves).
# `play_problem` must already have promised that it can be paid.
func pay_extra_cost(_card: Card, _caster_id: int) -> bool:
	return true


# A regular spell resolves: does what the text says. Runs after payment, before the card moves to its
# destination (the discard pile unless spell_destination says otherwise). May be a coroutine.
func resolve(_card: Card, _caster_id: int, _choice) -> void:
	pass


# The same question asked of a card on the table about somebody else's spell: "the first spell you cast each
# turn is placed in your energy zone instead of your discard" (Sigil Mage). `host` is this script's card
# on the table, `spell` the spell that resolved. Return a zone name of the spell's owner or "".
func spell_destination_for(_host: Card, _spell: Card) -> String:
	return ""


# --- permanents: entering and leaving ------------------------------------------------------------------

# The card was played from the hand (any type, a spell too, after resolve) and paid for. Triggers of
# "when you cast / play this".
func on_play(_card: Card) -> void:
	pass


# The card entered the table in a creature, occupied, relic, field, world or doctrine zone, by any
# means (played, returned from the discard pile, a token created, control taken, flip cast). Triggers of
# "when this enters". Not called for energy cards. May be a coroutine.
func on_enter(_card: Card) -> void:
	pass


# The card left the table (destroyed, consumed, returned, turned into energy ...). `destination` is the
# name of the zone it went to ("discard", "removed", "hand", "energy", "deck", ...). The card is
# already there. Modifiers and keyword grants the card was the `source` of are removed by the
# registry before this runs. Destruction has its own, richer hook: on_destroyed (FateKeyword).
func on_leave(_card: Card, _destination: String) -> void:
	pass


# Where a regular spell goes after it resolved: a zone name of its owner ("discard", "energy",
# "removed", "deck" ...). "" for the default (the discard pile). Asked of the spell's own script AND of
# every card on the table (a creature that redirects spells, see on_spell_destination), the first
# non-empty answer wins.
func spell_destination(_card: Card, _caster_id: int) -> String:
	return ""


# --- watching the game (runs for cards ON THE TABLE, whoever caused the event) -----------------------------------
# `card` is the table card this script is on (the host). Check controllers yourself: `card.controller_id`.

# Another card was played (`played`), after it resolved or entered
func on_card_played(_card: Card, _played: Card) -> void:
	pass


# Any card on the table was destroyed (it is already in its new zone). `source` is a Card or null.
func on_card_destroyed(_card: Card, _destroyed: Card, _cause: String, _source) -> void:
	pass


# A phase begins (game.phase_begins). `active_id` is whose turn it is. FateGame.Phase values.
func on_phase(_card: Card, _active_id: int, _phase: int) -> void:
	pass


# Damage was really dealt (game.damage_dealt): `target` is a creature Card or a FatePlayer.
func on_damage(_card: Card, _source, _target, _amount: int, _cause: String) -> void:
	pass


# A card was played as energy (game.energy_played)
func on_energy_played(_card: Card, _energy: Card) -> void:
	pass


# An alternative to playing a card from the hand into the energy zone in the ENERGY phase, offered by the host
# on the table to `player_id` (any player: Broadening Influence is a world spell). The button label, or "" if it
# is not offered now. FateGame.energy_alternatives / use_energy_alternative.
func energy_alternative(_host: Card, _player_id: int) -> String:
	return ""


# Does it: returns whether it worked (then the ENERGY choice counts as made)
func use_energy_alternative(_host: Card, _player_id: int) -> bool:
	return false


# Another card left the table for `destination` ("discard", "hand", "energy", "gone" for a token ...), whoever's it
# was; it is already there. "Whenever a non-token relic leaves the battlefield" (Rarink). Check the card yourself.
func on_card_left(_card: Card, _left: Card, _destination: String) -> void:
	pass


# A card was placed in a pile (`zone`: "discard", "removed" or "deck" of its owner), from anywhere: the table, the hand,
# a resolved spell. It is already there. "If a card is placed in your discard, move it to your energy zone" (Cycle of
# Life). Check `placed.owner_id` and `zone` yourself. May be a coroutine.
func on_card_to_pile(_card: Card, _placed: Card, _zone: String) -> void:
	pass


# Any card on the table is about to be destroyed: it has not moved yet, so relics equipped to it are still
# attached. `source` is the Card or null that destroys it. Use it to remember something for on_leave.
func on_card_dying(_card: Card, _dying: Card, _cause: String, _source) -> void:
	pass


# A card was flip cast from an energy zone by `caster_id` (game.casting.flip_cast), after it was cast
# completely. `cast_card` is the card that was cast: on the table if it is a permanent (a script also hears
# its own flip cast: Dockside Ambusher), already in its destination if it is a spell. "Whenever you flip
# cast, draw a card" (Eldritch Knowledge). May be a coroutine.
func on_flip_cast(_card: Card, _cast_card: Card, _caster_id: int) -> void:
	pass


# One attack finished resolving (FateCombat.attack_resolved); `result` as in FateCombat.resolve_attack.
# Runs for the host if it is the attacker, a blocker or the attacked creature of that attack.
func on_attack_resolved(_card: Card, _attack: FateAttack, _result: Dictionary) -> void:
	pass


# --- static effects on other cards ----------------------------------------------------------------------------

# Keywords the card on the table gives to `target`, as {keyword name: value}, merged into
# game.keywords.all_on(target) for as long as the host is on the table ("your creatures have Productive").
# Called often: be cheap, no side effects. Do NOT call game.keywords.has/value/all_on on `target` from here
# (they call you); look at card properties and zones instead.
func static_keywords(_host: Card, _target: Card) -> Dictionary:
	return {}


# Strike / Guard the host gives to `target` ("creatures you control have +1 Strike"). Summed into
# FateStats.current. Same restrictions as static_keywords; do not call game.stats.current on `target`.
func static_stat_bonus(_host: Card, _target: Card, _stat: String) -> int:
	return 0


# --- hints for the AI player (all optional) --------------------------------------------------------------------

# What having this card in hand is worth to its owner, in the points of src/custom/fate/ai/FateAIEval.gd (one
# point is about one point of Strike or Guard on a creature; a good removal spell is 5 to 8). Negative: no
# opinion, the AI estimates from the mana value. Without a script the AI treats a card as "does nothing".
func ai_value(_card: Card, _caster_id: int) -> float:
	return -1.0


# A field spell that hurts the player whose field it stands in (its controller), so its caster puts it on the
# opponent's field. The AI casts it there and values ai_value as the harm done.
func harms_holder(_card: Card) -> bool:
	return false


# What a choice of this card is for, so the AI picks sensibly: "harm" (destroy, damage: the opponent's best
# thing), "help" (a buff: its own best thing), "give" (a cost: its cheapest thing), or "" for the AI to guess
# from the rules text. `request` is the FateChoices request.
func ai_intent(_request: Dictionary) -> String:
	return ""


# --- helpers for the scripts -----------------------------------------------------------------------------------------

# The opponent of a player
func opponent_of(player_id: int) -> int:
	return FateZones.opponent_of(player_id)


# The creatures a player controls in play (creature and occupied zones)
func creatures_of(player_id: int) -> Array:
	return game.creatures_in_play(player_id)


# Picks something for `caster_id`: a card, a player or several of them out of `options`. A coroutine
# (a UI may wait for a person): `var pick = await choose(card, caster, "target creature", options)`.
# `count` > 1 returns an array; `optional` lets the answer be null. See FateChoices.
func choose(card: Card, caster_id: int, kind: String, options: Array, count := 1, optional := false):
	return await game.choices.pick(kind, caster_id, card, options, count, optional)


# Asks a yes/no question of a player ("you may ..."). A coroutine. See FateChoices.confirm.
func confirm(card: Card, caster_id: int, prompt: String, default := true) -> bool:
	return await game.choices.confirm(prompt, caster_id, card, default)


# Builds one entry for `actions()` (the hover buttons of the card, FateActions): an activated ability
# with costs. `costs` is an Array of cost dictionaries from game.costs (FateCosts: occupy(), mana(n),
# consume_self(), counter("scrap", 1), once_per_turn("key") ...). The ability is enabled in its
# controller's main phase when every cost can be paid and `condition` (optional, a Callable taking the
# card and returning "" or a reason) allows it. Running it pays the costs in order, then calls
# `effect` (taking the card; may be a coroutine). `problem` reports why it is disabled, for tooltips.
func make_action(card: Card, id: String, label: String, tooltip: String, costs: Array, effect: Callable,
		condition := Callable()) -> Dictionary:
	var why := action_problem(card, costs, condition)
	return {
		"id": id, "label": label, "tooltip": tooltip if why == "" else "%s (%s)" % [tooltip, why],
		"enabled": why == "", "problem": why, "costs": costs,
		"run": func(c: Card) -> bool: return await run_action(c, costs, effect, condition),
	}


# Why the ability cannot be used now, or ""
func action_problem(card: Card, costs: Array, condition := Callable()) -> String:
	if game.is_over or not game.is_started:
		return "The game is not going on"
	if card.controller_id != game.active_id or game.phase != FateGame.Phase.MAIN:
		return "Only in its controller's main phase"
	if FateZones.zone_of(card) == "":
		return "Not on the table"
	if condition.is_valid():
		var reason: String = condition.call(card)
		if reason != "":
			return reason
	return game.costs.problem(card, costs)


# Pays the costs and runs the effect. Returns whether it acted.
func run_action(card: Card, costs: Array, effect: Callable, condition := Callable()) -> bool:
	if action_problem(card, costs, condition) != "":
		return false
	if not await game.costs.pay(card, costs):
		return false
	await effect.call(card)
	return true
