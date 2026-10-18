# Choices a card effect asks of a player: pick a target, pick cards from a list, answer "you may ...".
# Assigned to `game.choices`. No class_name (FateGame loads it by path).
#
# There is no choice UI yet. Every question has a deterministic default (the first valid options), so
# the rules work without anybody answering; an AI player or a UI plugs in through `chooser` /
# `confirmer` (for everybody) or `choosers` / `confirmers` (per player id; they win over the general
# ones). The callables may be coroutines: callers always `await` the answer.
#
#   chooser(request: Dictionary) -> Variant
#     request: {"kind": String (what is being picked, "target creature"), "player": int (who picks),
#               "source": Card (the card asking), "options": Array, "count": int, "optional": bool,
#               "default": Variant (what is taken if the answer is invalid or null)}
#     return: one option when count is 1, an Array of `count` options otherwise; null (only when optional)
#             for "none"; null is also "no opinion, use the default".
#   confirmer(request: Dictionary) -> bool|null
#     request: {"prompt": String, "player": int, "source": Card, "default": bool}
#
# An answer that is not made of valid options is replaced by the default; the game never stalls.
extends RefCounted

var game: FateGame
var chooser := Callable()
var confirmer := Callable()
var choosers := {}
var confirmers := {}


func _init(owner_game: FateGame) -> void:
	game = owner_game


# Picks `count` of `options` for `player`. Returns one option (count 1), an Array (count > 1), or null
# (optional and nothing wanted, or no options at all).
func pick(kind: String, player: int, source: Card, options: Array, count := 1, optional := false):
	# "target ..." picks of a spell never offer a card that cannot be targeted by spells (see targetable)
	if kind.begins_with("target"):
		options = legal_targets(source, options)
	var wanted := mini(count, options.size())
	if wanted <= 0:
		return null if count == 1 else []
	var fallback = options[0] if count == 1 else options.slice(0, wanted)
	var request := {"kind": kind, "player": player, "source": source, "options": options,
			"count": count, "optional": optional, "default": fallback}
	var answer = await _ask(player, request)
	if answer == null and optional:
		return null if count == 1 else []
	if count == 1:
		return answer if answer in options else fallback
	if answer is Array and answer.size() == wanted and answer.all(func(a): return a in options) \
			and _distinct(answer):
		return answer
	return fallback


# The choice of a spell or an enters trigger that has_choice: asks for it with the script's own list
# (candidates) and default, and validates with its choice_problem. `effect` is the card script.
func pick_for_card(effect, card: Card, player: int):
	var options: Array = legal_targets(card, effect.candidates(card, player))
	var fallback = effect.default_choice(card, player)
	if fallback is Card and not targetable(card, fallback):
		fallback = options[0] if not options.is_empty() else null
	var request := {"kind": card.canonical_name, "player": player, "source": card, "options": options,
			"count": 1, "optional": false, "default": fallback, "script": effect}
	var answer = await _ask(player, request)
	if answer != null and effect.choice_problem(card, player, answer) == "":
		return answer
	return fallback


# Can `source` target `target`? A card script that cannot be targeted by some sources (Thrang, Perpetual
# Innovation: "cannot be targeted by spells") defines `can_be_targeted_by(target: Card, source: Card) -> bool`.
# Only the script of the target is asked; anything that is not a card on a script is targetable.
func targetable(source, target) -> bool:
	if not target is Card or not is_instance_valid(target) or game.card_effects == null:
		return true
	var effect = game.card_effects.effect_of(target.canonical_name)
	if effect == null or not effect.has_method("can_be_targeted_by"):
		return true
	return effect.can_be_targeted_by(target, source)


# `options` without what `source` may not target. Spells that build their own candidate lists call this
# too (pick() and pick_for_card() already apply it to "target ..." picks and to the has_choice list of a
# spell), so a spell cannot forget it.
func legal_targets(source, options: Array) -> Array:
	return options.filter(func(option): return targetable(source, option))


# A yes/no question to `player`. The default answer when nobody answers is `default`.
func confirm(prompt: String, player: int, source: Card, default := true) -> bool:
	var fn: Callable = confirmers.get(player, confirmer)
	if fn.is_valid():
		var answer = await fn.call({"prompt": prompt, "player": player, "source": source, "default": default})
		if answer is bool:
			return answer
	return default


func _ask(player: int, request: Dictionary):
	var fn: Callable = choosers.get(player, chooser)
	if not fn.is_valid():
		return null
	return await fn.call(request)


static func _distinct(items: Array) -> bool:
	for i in items.size():
		for j in range(i + 1, items.size()):
			if items[i] == items[j]:
				return false
	return true
