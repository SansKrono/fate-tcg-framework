# Base class of every keyword (Savage, Indomitable, Untethered, ...). Design document: Section
# 13 (SYS-KEYWORD). Rules: docs/FATE_RULES_SPEC.md, Section 4.
#
# A keyword is ONE script in src/custom/fate/keywords/, named Kw<Name>.gd, that extends this class
# and overrides the hooks it needs. The registry (FateKeywords) finds it by itself at startup, so
# adding a keyword never touches a shared file. The hook API, the combination rules and a worked
# example are documented in src/custom/fate/keywords/README.md.
#
# Keywords are stateless singletons: one instance serves every card that has the keyword. All
# state belongs on the card (FateCardTemplate), on the attack record (FateAttack.metadata) or in
# the stats layer (modifiers and keyword grants). Every hook receives the card the keyword is ON
# (`card`) as its first argument.
class_name FateKeyword
extends RefCounted

# The name of the keyword: the key used in a card's `_innate_keywords` dictionary and in
# `FateStats.grant_keyword()`, for example "Savage" or "Cannot block". Set it in `_init()`.
var keyword_name := ""
# Hooks of keywords run in ascending priority, then by name. Matters for the chained hooks
# (modify_damage_taken, death_destination): lower numbers go first.
var priority := 0
# A universal keyword's hooks run for EVERY card, whether or not the card has the keyword. Use it
# for rules that apply by default and that a keyword lifts (Charge: a creature cannot attack the
# turn it enters unless it has Charge. The keyword Charge cannot forbid that on creatures that do
# not have it, so it is universal and checks `has(card)` itself).
var universal := false
# The game; set by the registry when it takes the keyword over
var game: FateGame


# --- helpers -------------------------------------------------------------------------

# Does this card have this keyword (innate or granted)?
func has(card: Card) -> bool:
	return game.keywords.has(card, keyword_name)


# The value of this keyword on the card (Savage 2 -> 2; 0 if the card does not have it)
func value(card: Card) -> int:
	return game.keywords.value(card, keyword_name)


# --- eligibility (all keywords must allow) ----------------------------------------------------

# May this creature be declared as an attacker? Runs on top of the core conditions (controller is
# the active player, in the creature zone, upright, not yet attacked). Hook runs for the attacker.
func can_attack(_card: Card) -> bool:
	return true


# May this creature occupy now? Used by the Occupy action, see actions().
func can_occupy(_card: Card) -> bool:
	return true


# May this creature intercept this attack? `blocker` is the host. The core has already checked
# that it is guarding or occupied and not blocking another attack. Cannot block: return false.
func can_block(_blocker: Card, _attack: FateAttack) -> bool:
	return true


# May this attacker be intercepted by this blocker? `attacker` is the host. Unblockable: return
# false. A forced single blocker is better expressed with `attack.add_restriction()`.
func can_be_blocked_by(_attacker: Card, _blocker: Card, _attack: FateAttack) -> bool:
	return true


# May this creature be the target of an attack by `attacker`? `target` is the host.
func can_be_attacked(_target: Card, _attacker: Card) -> bool:
	return true


# --- combat events -----------------------------------------------------------------------------

# The attackers were confirmed (the declare step ends). Runs for the attacker, once per attack, in
# declaration order, before the reaction window of the declare step.
func on_attack_declared(_card: Card, _attack: FateAttack) -> void:
	pass


# The intercept step ended with at least one blocker on this attack. Runs for the attacker (host),
# in declaration order, when the blocks are confirmed. `blockers` is in damage order.
func on_blocked(_card: Card, _attack: FateAttack, _blockers: Array) -> void:
	pass


# The same moment, for each blocker (host = blocker): it is blocking `attack`.
func on_blocking(_card: Card, _attack: FateAttack) -> void:
	pass


# Right before this attack's damage is worked out. Runs for every participant: the attacker, each
# blocker still in play and the attacked creature (if any); check `attack.attacker == card` to
# tell them apart. Stat modifiers added here count for the damage. Not run for a negated attack.
func before_combat_damage(_card: Card, _attack: FateAttack) -> void:
	pass


# `card` (the host) dealt `amount` (more than 0) damage to `target` (a creature Card or a
# FatePlayer). `cause` is a FateEffects.CAUSE_* value, "combat" for combat damage.
func on_damage_dealt(_card: Card, _target, _amount: int, _cause: String) -> void:
	pass


# --- damage and destruction ------------------------------------------------------------------------

# Chained: `card` is about to lose `amount` of `stat` ("Strike" or "Guard") from `source` (a Card
# or null). Return the amount to lose instead (0 prevents the damage). The next keyword gets your
# result. Indomitable: for combat, return `min(amount, current - 1)`.
func modify_damage_taken(_card: Card, _stat: String, amount: int, _cause: String, _source) -> int:
	return amount


# `card` is about to be destroyed. Return false to prevent that. All keywords must agree (any
# false wins). The card stays where it is when prevented.
func would_be_destroyed(_card: Card, _cause: String, _source) -> bool:
	return true


# Where the card goes when it is destroyed: the name of one of its OWNER's zones ("discard",
# "removed", "deck", "hand"). Return "" for no opinion (the default is "discard"). The first
# keyword (by priority, then name) that answers wins. Untethered: "removed".
func death_destination(_card: Card, _cause: String) -> String:
	return ""


# The card was destroyed and has been moved. Runs after the move, with the card's keyword grants
# still in place (they are cleared afterwards). `source` is a Card or null.
func on_destroyed(_card: Card, _cause: String, _source) -> void:
	pass


# --- stats and time ------------------------------------------------------------------------------------

# Summed: how much does this keyword add to `stat` of the host? (Embody: +Strike and +Guard
# equal to the energy under the creature.) Do not call FateStats.current() from here (it calls
# you): use base() or your own state. When your state changes, call `game.stats.refresh(card)`.
func stat_bonus(_card: Card, _stat: String) -> int:
	return 0


# At the end of every turn (the END phase, after "until end of turn" effects expired), for each
# creature in play that the active player controls.
func on_turn_end(_card: Card) -> void:
	pass


# At the start of every turn, after maintenance reset the stats and untapped, for each creature
# in play that the active player controls.
func on_maintenance(_card: Card) -> void:
	pass


# --- activated actions ---------------------------------------------------------------------------------------

# Buttons this keyword adds to the hover buttons of the host (Occupy, Embody). Return an array of
# dictionaries, built when the buttons are refreshed, so `enabled` can reflect the current state:
#   {"id": "occupy", "label": "Occ", "tooltip": "Tilt and move to the occupied zone",
#    "enabled": true, "run": Callable}
# `run` is called with the card, may be a coroutine, and should return true when it acted.
# Only the controller sees the buttons. See FateActions.
func actions(_card: Card) -> Array:
	return []
