# One declared attack of a combat phase (the "AttackRecord"). Rules: docs/FATE_RULES_SPEC.md,
# Section 3. Created by FateCombat.declare_attack(); keywords and effects read and change it.
class_name FateAttack
extends RefCounted

# The attacking creature
var attacker: Card
# What it attacks: a creature (target_card) or a player (target_player, 1 or 2; 0 for a creature)
var target_card: Card = null
var target_player := 0
# The blockers in the order the attacker spends its Strike on them (damage order). Starts as the
# order the blocks were declared; FateCombat.order_blockers() changes it.
var blockers: Array = []
# Position in the declaration order: the order the attacks resolve in (0 is first)
var order := 0
# Negated: still resolves in its turn but deals no damage (FateCombat.negate_attack)
var negated := false
# Removed from combat (FateCombat.remove_from_combat): resolves as a no-op in its turn
var removed := false
# A blocker was declared on this attack. Stays true when the blockers later leave play, so an
# attack that was blocked never turns into a hit on its target (spec, Section 3)
var was_blocked := false
# Done: `result` describes how it went (see FateCombat.resolve_attack)
var resolved := false
var result := {}
# Extra rules about who may block this attack. Dictionaries with a "kind":
#   {"kind": "only",   "cards": [Card, ...]}  only these creatures may block (forced single blocker)
#   {"kind": "except", "cards": [Card, ...]}  these creatures may not block
#   {"kind": "none"}                            nobody may block
# Each may carry a "source" (usually the card creating it) for remove_restrictions_from().
# All restrictions must allow a blocker.
var restrictions: Array = []
# Free space for keywords and effects to remember things about this attack
var metadata := {}


func _init(attacking_card: Card, target, attack_order := 0) -> void:
	attacker = attacking_card
	order = attack_order
	if target is Card:
		target_card = target
	elif target is FatePlayer:
		target_player = target.id
	else:
		target_player = int(target)


func targets_player() -> bool:
	return target_card == null


# Is the attack still going to resolve with effect? (not removed, negated or resolved)
func is_live() -> bool:
	return not removed and not negated and not resolved


func is_blocked() -> bool:
	return was_blocked


# Adds a block restriction, see `restrictions`
func add_restriction(restriction: Dictionary) -> void:
	restrictions.append(restriction)


func remove_restrictions_from(source) -> void:
	restrictions = restrictions.filter(func(r): return not is_same(r.get("source"), source))


# Do the restrictions allow this creature to block? (The keyword hooks are checked separately.)
func restrictions_allow(blocker: Card) -> bool:
	for r in restrictions:
		match r.get("kind", ""):
			"only":
				if not blocker in r.get("cards", []):
					return false
			"except":
				if blocker in r.get("cards", []):
					return false
			"none":
				return false
	return true


# A short description for logs: "Skulking Goblin -> Player 2"
func describe() -> String:
	var target_text := "Player %d" % target_player
	if target_card != null and is_instance_valid(target_card):
		target_text = target_card.canonical_name
	return "%s -> %s" % [attacker.canonical_name if is_instance_valid(attacker) else "?", target_text]
