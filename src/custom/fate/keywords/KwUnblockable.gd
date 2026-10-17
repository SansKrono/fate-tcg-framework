# Unblockable: this attacker cannot be intercepted (docs/FATE_RULES_SPEC.md, Section 4).
# It still attacks as usual: against a creature it just never has a blocker, against a player it
# hits the life total. Granted copies ("it cannot be blocked this turn") work the same way, with
# game.stats.grant_keyword(card, "Unblockable", 1, "end_of_turn").
extends FateKeyword


func _init() -> void:
	keyword_name = "Unblockable"


# `attacker` is the host. Any false from any keyword wins, so no other keyword can re-allow a block.
func can_be_blocked_by(_attacker: Card, _blocker: Card, _attack: FateAttack) -> bool:
	return false
