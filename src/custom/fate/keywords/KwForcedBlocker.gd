# Forced single blocker (docs/FATE_RULES_SPEC.md, Section 4): "Pay 2: when it attacks this turn it
# must be blocked by target creature exclusively" (Beetle Brawler, Ironside Beetle).
#
# The data has no keyword for it (the rule is only in the card's Abilities text), so this keyword is
# `universal`: its hooks run for every card and it decides by itself which cards have the ability:
#   * the card has the keyword "Forced blocker" (innate or granted), or
#   * its Abilities text contains one of ABILITY_MARKERS (case-insensitive).
#
# Flow
#   1. MAIN phase of the controller: the hover button "Force block (pay 2)" (action id
#      "force_block", see actions()) pays 2 generic mana and picks one of the OPPONENT's creatures
#      in play. The pick comes from the static `chooser` (a UI or test hook), default: the
#      opposing creature with the highest current Guard, ties by node order (the order of
#      game.creatures_in_play()).
#   2. `force_block(card, target)` is the same thing with an explicit target (tests, a later UI,
#      the AI). It records the target on the card (metadata, valid for the current turn number).
#   3. When the card is declared as an attacker (on_attack_declared) the restriction
#      {"kind": "only", "cards": [target], "source": card} is added to the attack, so only the
#      target may block it. The other block rules still apply: if the target is gone, cannot block
#      ("Cannot block" keyword), is not guarding/occupied or is blocking another attack, nobody
#      can block the attack at all (if it is already gone when the attack is declared the
#      restriction is {"kind": "none"}).
#   4. The ability ends with the turn: forced_target() only answers during the turn it was used in
#      and on_turn_end clears the record.
#
# The action is offered only while it is legal: MAIN phase, the controller's turn, the creature in
# play, an opposing creature to name, 2 untapped mana, and not used yet this turn (a second payment
# would change nothing the first did not already guarantee).
extends FateKeyword

# Text fragments of the Abilities line that give a card the ability. The real data reads "must be
# blocked exclusively by target creature" (Beetle Brawler) and "Same forced-block ability"
# (Ironside Beetle); the designer's wording "must be blocked by target creature exclusively" also
# matches the first one.
const ABILITY_MARKERS := ["must be blocked", "forced-block", "forced block"]
# The generic mana the ability costs
const COST := 2
const ACTION_ID := "force_block"
const META_KEY := "fate_forced_blocker"

# Chooses the creature to name. `Callable(card: Card, candidates: Array) -> Card`; may be a
# coroutine (a UI awaiting a click); return null to cancel. Not set: the deterministic default
# (see default_target). Static because keywords are stateless singletons: set it with
# `load("res://src/custom/fate/keywords/KwForcedBlocker.gd").chooser = ...` and reset it with
# `Callable()`.
static var chooser := Callable()


func _init() -> void:
	keyword_name = "Forced blocker"
	universal = true


# --- the ability --------------------------------------------------------------------------------

# Does this card have the ability (keyword or Abilities text)?
func has_ability(card: Card) -> bool:
	if has(card):
		return true
	var text := str(card.properties.get("Abilities", "")).to_lower()
	for marker in ABILITY_MARKERS:
		if text.contains(marker):
			return true
	return false


# The opposing creatures in play that could be named, in node order
func candidates(card: Card) -> Array:
	return game.creatures_in_play(FateZones.opponent_of(card.controller_id))


# The default pick: highest current Guard, ties go to the first in node order
func default_target(cands: Array) -> Card:
	var best: Card = null
	for c in cands:
		if best == null or game.stats.current(c, "Guard") > game.stats.current(best, "Guard"):
			best = c
	return best


# The creature this card named this turn, or null (nothing named, expired, or the creature left
# play)
func forced_target(card: Card) -> Card:
	if not is_instance_valid(card) or not card.has_meta(META_KEY):
		return null
	var record: Dictionary = card.get_meta(META_KEY)
	if int(record.get("turn", -1)) != game.turn_number:
		return null
	var target = record.get("target")
	return target if is_instance_valid(target) and FateZones.is_creature_in_play(target) else null


# Why the ability cannot be used now (without checking a target): "" if it can
func problem(card: Card) -> String:
	if game.is_over or not game.is_started:
		return "The game is not running"
	if not is_instance_valid(card) or not FateZones.is_creature_in_play(card):
		return "Not a creature in play"
	if not has_ability(card):
		return "It has no such ability"
	if card.controller_id != game.active_id or game.phase != FateGame.Phase.MAIN:
		return "Only in its controller's main phase"
	if forced_target(card) != null:
		return "Already used this turn"
	if candidates(card).is_empty():
		return "The opponent has no creature to name"
	if not game.mana.can_pay_generic(card.controller_id, COST):
		return "Not enough mana"
	return ""


# Pays COST generic mana and names `target` (an opposing creature in play) for this turn. Returns
# false, changing nothing, when it is not legal (see problem()).
func force_block(card: Card, target: Card) -> bool:
	if problem(card) != "":
		return false
	if not is_instance_valid(target) or not target in candidates(card):
		return false
	game.mana.pay_generic(card.controller_id, COST)
	card.set_meta(META_KEY, {"target": target, "turn": game.turn_number})
	return true


# --- hooks -----------------------------------------------------------------------------------------

func actions(card: Card) -> Array:
	if problem(card) != "":
		return []
	return [{
		"id": ACTION_ID, "label": "Force block (pay %d)" % COST,
		"tooltip": "Pay %d: when it attacks this turn it must be blocked by target creature exclusively" % COST,
		"enabled": true,
		"run": _run,
	}]


# The hover button: choose (default or `chooser`), then pay and record
func _run(card: Card) -> bool:
	var cands := candidates(card)
	var target = null
	if chooser.is_valid():
		target = await chooser.call(card, cands)
	else:
		target = default_target(cands)
	if not target is Card:
		return false
	return force_block(card, target)


# The card was declared as an attacker: only the named creature may block it
func on_attack_declared(card: Card, attack: FateAttack) -> void:
	if not card.has_meta(META_KEY) or int(card.get_meta(META_KEY).get("turn", -1)) != game.turn_number:
		return
	var target := forced_target(card)
	attack.metadata["forced_blocker"] = target
	if target == null:
		attack.add_restriction({"kind": "none", "source": card})
	else:
		attack.add_restriction({"kind": "only", "cards": [target], "source": card})


# The ability lasts until end of turn
func on_turn_end(card: Card) -> void:
	if card.has_meta(META_KEY):
		card.remove_meta(META_KEY)
