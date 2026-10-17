# Base class of the reaction spell effects. One script per spell in this folder, named
# `React<Name>.gd` (spaces removed), extending this file; FateReactions (game.reactions) scans the
# folder and registers each by its `card_name`. Not a class_name script on purpose (the global class
# cache is shared by everybody working at once), so subclasses extend it by path.
#
# An effect is a stateless singleton: it validates the spell's own condition, offers the possible
# targets and resolves. Paying for the card, the window checks, moving the card to the discard pile
# and the UI are the manager's job.
extends RefCounted

# The card this effect belongs to (FateData key), set in _init() of the subclass
var card_name := ""
# The windows (FateCombat.WINDOW_*) the spell may be cast in; empty means every window
var windows: Array = []
# True if the caster may pick targets (the manager asks its `chooser` for them)
var has_choice := false
# Set by the manager
var game: FateGame


# Why the spell's own condition is not met right now, or "" if it is. `caster_id` is the player who
# would cast it (the window's player).
func problem(_caster_id: int) -> String:
	return ""


# What the caster may pick from (cards), for effects with a choice
func candidates(_caster_id: int) -> Array:
	return []


# What is chosen when nobody picks (the deterministic default); null if the effect has no choice
func default_choice(_caster_id: int):
	return null


# Why this explicit choice is not allowed, or ""
func choice_problem(_caster_id: int, _choice) -> String:
	return ""


# Does the effect. The manager has validated everything and paid already.
func resolve(_card: Card, _caster_id: int, _choice) -> void:
	pass


# --- helpers for the subclasses -------------------------------------------------------------------

# The attacks of this combat that have not been removed or resolved and whose target is the
# player or one of the player's creatures in play. `live_only` also leaves out negated ones.
func attacks_on(caster_id: int, live_only := false) -> Array:
	var found := []
	if game.combat == null:
		return found
	for attack in game.combat.attacks:
		if attack.removed or attack.resolved or (live_only and attack.negated):
			continue
		if attack.targets_player():
			if attack.target_player == caster_id:
				found.append(attack)
		elif FateZones.is_creature_in_play(attack.target_card) \
				and attack.target_card.controller_id == caster_id:
			found.append(attack)
	return found


# The attacks (not removed or resolved) declared by the opponents of `caster_id`, in declaration
# order, whose attacker is still in play
func opposing_attacks(caster_id: int) -> Array:
	var found := []
	if game.combat == null:
		return found
	for attack in game.combat.attacks:
		if attack.removed or attack.resolved or not FateZones.is_creature_in_play(attack.attacker):
			continue
		if attack.attacker.controller_id != caster_id:
			found.append(attack)
	return found


# The attacking creatures of opposing_attacks()
func opposing_attackers(caster_id: int) -> Array:
	return opposing_attacks(caster_id).map(func(a): return a.attacker)


# Turns a Card, a FateAttack or an array of them into an array of cards
func as_cards(choice) -> Array:
	var cards := []
	var items: Array = choice if choice is Array else [choice]
	for item in items:
		cards.append(item.attacker if item is FateAttack else item)
	return cards
