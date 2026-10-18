# Base class of the doctrine scripts (cards/Fx<DoctrineName>.gd). Not a card script itself (no Fx prefix, the
# registry does not load it). A doctrine's reward is active while the doctrine is achieved (FateDoctrines):
# `active(card)` asks. Rewards that need a start / an end (a permission granted ...) override on_reward_start /
# on_reward_end; the manager calls them when the goal is met, again after a board state was loaded, and when the
# flag is removed. Docs: FateDoctrines.gd, docs/FATE_TCG_DESIGN.md Section 10.
extends "res://src/custom/fate/cards/FateCardEffect.gd"


# Is the reward of this doctrine card active?
func active(card: Card) -> bool:
	return game.doctrines != null and game.doctrines.achieved(card)


# The goal was just met (or a loaded board state has it already)
func on_reward_start(_card: Card) -> void:
	pass


# The achieved flag was removed by an effect
func on_reward_end(_card: Card) -> void:
	pass


# Is this the start (MAINTENANCE) of the turn of the doctrine's controller?
func is_my_turn_start(card: Card, active_id: int, phase: int) -> bool:
	return phase == FateGame.Phase.MAINTENANCE and active_id == card.controller_id


# Is `target` a creature in play of the doctrine's controller?
func is_my_creature(host: Card, target: Card) -> bool:
	return target.controller_id == host.controller_id and target.properties.get("Type") == "Creature" \
			and FateZones.zone_of(target) in FateZones.CREATURE_ZONES
