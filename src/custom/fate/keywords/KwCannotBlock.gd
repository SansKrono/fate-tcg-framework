# Cannot block: this creature cannot intercept attacks, even in the guard position or occupied
# (docs/FATE_RULES_SPEC.md, Section 4). It can still be targeted by attacks, which the core
# already allows: the keyword only restricts the blocking side.
extends FateKeyword


func _init() -> void:
	keyword_name = "Cannot block"


# `blocker` is the host. Runs on top of the core rule (guarding or occupied, free to block).
func can_block(_blocker: Card, _attack: FateAttack) -> bool:
	return false
