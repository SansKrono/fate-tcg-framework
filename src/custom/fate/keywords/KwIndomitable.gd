# Indomitable: the creature cannot die from combat damage (docs/FATE_RULES_SPEC.md, Section 4).
# Its used stat is held at 1 instead of reaching 0: Strike 3 blocked by Guard 5 stays at Strike 1,
# a Guard 2 blocker hit by Strike 4 stays at Guard 1.
#
# Two hooks work together:
#
# 1. modify_damage_taken (the visible part). Combat damage is capped at `current - 1`, so the
#    stat itself stays at 1 and the card face shows 1. Doing it as a damage cap (and not as a
#    +1 stat bonus) keeps the stats layer honest: `current()` is what the rules use and what the
#    label shows. Only the COMBAT cause is limited; effect damage and stat-zero are not.
#    Damage dealt BY an Indomitable creature is not touched: FateCombat works that out from the
#    stats before anybody is damaged.
#
# 2. would_be_destroyed (the safety net). The core kills a creature whose used stat is 0 after
#    combat damage (FateEffects.ZERO_KILLS_CAUSES). A stat that was ALREADY 0 before the fight (a
#    Guard 0 blocker, a debuffed stat) is not "reached" by damage, so the cap cannot help there,
#    yet the creature must still not die from combat. So destruction with cause "combat" is
#    vetoed outright.
#
# The "Strike and Guard both 0" rule (cause "stats") is NOT affected by this keyword. Combat can
# never cause it: the used stat is held at 1, so a combat hit cannot take the last point of the
# last non-zero stat. An Indomitable creature whose stats are lowered to 0 by non-combat means
# (effect damage on both stats, debuffs) is destroyed like any other, and so are all non-combat
# destruction causes.
extends FateKeyword


func _init() -> void:
	keyword_name = "Indomitable"
	# modify_damage_taken is chained, lowest priority first. Go last so that the cap is applied to
	# the final amount: a keyword that raised the damage after us would undo the cap.
	priority = 100


func modify_damage_taken(card: Card, stat: String, amount: int, cause: String, _source) -> int:
	if cause != FateEffects.CAUSE_COMBAT:
		return amount
	# Never below 0 (a stat already at 0 or 1 takes nothing), never above what was asked
	return mini(amount, maxi(0, game.stats.current(card, stat) - 1))


func would_be_destroyed(_card: Card, cause: String, _source) -> bool:
	return cause != FateEffects.CAUSE_COMBAT
