# Savage X: when this creature is blocked, it deals X damage to the controller of the blocking
# creature OR to another creature that controller has. Rules: docs/FATE_RULES_SPEC.md, Section 4.
#
# Timing: the damage is dealt when the blocks are confirmed (hook on_blocked), once per blocked
# attack however many blockers there are, BEFORE the intercept reaction window and long before
# the attack's combat damage is worked out. A blocker killed by Savage therefore never takes
# part in combat damage (FateCombat drops it from the attack when it is destroyed; if it was the
# only blocker the attack resolves as "blockers_gone": it was blocked, so it does not reach its
# target).
#
# X is the keyword value: innate and granted values add up (Savage 2 + a granted Savage 1 = 3).
#
# Targets. The candidates are the blocking player (the controller of the first blocker, in
# damage order) and every creature that player has in play (blockers included: "another creature
# that controller has" is any creature of theirs). There is no target-choice UI yet, so the
# target is picked by `target_chooser`, a static Callable a later UI or AI replaces:
#
#   KwSavage.target_chooser = func(attacker: Card, attack: FateAttack, candidates: Array,
#           amount: int):
#       return candidates[0]   # a FatePlayer or one of the creature Cards in `candidates`
#
# `candidates[0]` is always the blocking FatePlayer, followed by the creatures. Return one of
# them. An unset chooser, or an answer that is not a candidate, falls back to the default: the
# blocking player. The chooser must answer synchronously (a coroutine is not awaited).
#
# The damage is dealt through game.effects.deal_damage() with the cause CAUSE_SAVAGE, so the
# keywords' modify_damage_taken / on_damage_dealt and the player-defeat rule apply. A creature
# loses the stat it is using (Strike upright, Guard when guarding or occupied). Core only kills
# at used stat 0 for combat damage, so Savage destroys the creature itself (through
# effects.destroy(), which asks would_be_destroyed) when its used stat reached 0; Indomitable
# only holds against combat damage, so it does not stop Savage damage from reaching 0.
extends FateKeyword

# The cause passed to deal_damage / destroy for Savage damage
const CAUSE_SAVAGE := "savage"
# attack.metadata key: {"amount", "target"} once Savage triggered for the attack (it also makes
# the keyword trigger at most once per attack, whatever calls the hook)
const META_KEY := "savage"

# The extension point described in the header comment. Static: it is shared by every game in
# the process, so a test that sets it must reset it to Callable().
static var target_chooser := Callable()


func _init() -> void:
	keyword_name = "Savage"


func on_blocked(card: Card, attack: FateAttack, blockers: Array) -> void:
	if attack.metadata.has(META_KEY) or attack.negated or attack.removed or attack.resolved:
		return
	if game.is_over or not FateZones.is_creature_in_play(card):
		return
	var amount := value(card)
	if amount <= 0:
		return
	var live_blockers := blockers.filter(func(b): return FateZones.is_creature_in_play(b))
	if live_blockers.is_empty():
		return
	var blocking_player := game.player(live_blockers[0].controller_id)
	var candidates: Array = [blocking_player]
	candidates.append_array(game.creatures_in_play(blocking_player.id))
	var target = _choose(card, attack, candidates, amount)
	attack.metadata[META_KEY] = {"amount": amount, "target": target}
	_deal(card, target, amount)


# The chooser's answer if it is one of the candidates, else the blocking player
func _choose(card: Card, attack: FateAttack, candidates: Array, amount: int):
	if target_chooser.is_valid():
		var answer = target_chooser.call(card, attack, candidates, amount)
		if answer != null and answer in candidates:
			return answer
	return candidates[0]


func _deal(source: Card, target, amount: int) -> void:
	if target is FatePlayer:
		game.effects.deal_damage(target, amount, source, CAUSE_SAVAGE)
		return
	var stat := game.effects.used_stat(target)
	var dealt := game.effects.deal_damage(target, amount, source, CAUSE_SAVAGE, stat)
	if dealt > 0 and FateZones.is_creature_in_play(target) and game.stats.current(target, stat) <= 0:
		game.effects.destroy(target, source, CAUSE_SAVAGE)
