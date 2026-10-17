# Keywords: how to add one

Each keyword (Savage, Indomitable, Untethered, Charge, ...) is **one script in this folder**, named
`Kw<Name>.gd`, that extends `FateKeyword`. The registry (`FateKeywords`, `game.keywords`) scans this
folder at startup and registers every `Kw*.gd` it finds, so **you never edit a shared file** (not the
registry, not `FateCombat`, `FateEffects`, `FateStats`, `FateBoard`, `FateGame`, `FateCommon.gd`). Add
your script and your test, nothing else.

Rules for the script:

* `extends FateKeyword`, **no `class_name`** (the global class cache is shared between everybody
  working at once), file name `Kw<Name>.gd` (spaces removed: `KwCannotBlock.gd`).
* Set `keyword_name` in `_init()`: it is the key used in a card's `_innate_keywords` and in
  `game.stats.grant_keyword(...)`, exactly as in `FateData.gd` (`"Savage"`, `"Cannot block"`, ...).
* Keywords are **stateless singletons**: one instance serves every card. Keep state on the card, on
  the attack record (`attack.metadata`), or in the stats layer, never in a member variable of the
  keyword.
* Override only the hooks you need. All hooks have a safe default in `FateKeyword.gd`.
* Every hook receives the card the keyword is ON (`card`) as its first argument. A hook is only
  called for cards that have the keyword (innate or granted), except for keywords with
  `universal = true` (see below).
* Your test goes to `tests/integration/test_fate_kw_<name>.gd` and extends
  `res://tests/FateCommon.gd`. Do not put test-only keywords in this folder (they would ship): use
  `tests/FateTestKeyword.gd` or register your own object with `game.keywords.register(...)`.

## A complete example

```gdscript
# KwIndomitable.gd
extends FateKeyword


func _init() -> void:
	keyword_name = "Indomitable"


# Combat damage cannot take the used stat to 0: hold it at 1
func modify_damage_taken(card: Card, stat: String, amount: int, cause: String, _source) -> int:
	if cause != FateEffects.CAUSE_COMBAT:
		return amount
	return mini(amount, maxi(0, game.stats.current(card, stat) - 1))
```

A test for it (`tests/integration/test_fate_kw_indomitable.gd`):

```gdscript
extends "res://tests/FateCommon.gd"

func test_combat_damage_leaves_one():
	var card := await put_creature(1, 2, 2, {"Indomitable": 1})
	game.effects.deal_damage(card, 5, null, "combat")
	assert_eq(game.stats.current(card, "Strike"), 1)
	assert_true(FateZones.is_creature_in_play(card))
```

## The hooks

Combination rules decide what happens when a card has several keywords. Keywords always run in
ascending `priority` (default 0), then by name.

### Eligibility: every keyword must allow it (any `false` wins)

| Hook | Host (`card`) | Meaning |
|------|---------------|---------|
| `can_attack(card) -> bool` | the would-be attacker | May it be declared as an attacker? Extra to the core rules (active player's, in the creature zone, upright, not yet attacked) |
| `can_occupy(card) -> bool` | the would-be occupier | May it occupy now? The core never calls it by itself: the Occupy action asks `game.keywords.can_occupy(card)` |
| `can_block(blocker, attack) -> bool` | the would-be blocker | May it intercept this attack? Extra to the core rules (guarding or occupied, not blocking another attack). "Cannot block": return false |
| `can_be_blocked_by(attacker, blocker, attack) -> bool` | the attacker | May this blocker intercept it? "Unblockable": return false |
| `can_be_attacked(target, attacker) -> bool` | the target creature | May it be the target of this attacker's attack? |

For a forced single blocker, do not use `can_block`: in `on_attack_declared` add a restriction to the
attack, `attack.add_restriction({"kind": "only", "cards": [the_creature], "source": card})`. Kinds:
`"only"` (only these may block), `"except"` (these may not), `"none"` (nobody). `FateAttack` evaluates
them; `attack.remove_restrictions_from(source)` removes them. The restriction must be added before
the intercept step starts, so use `on_attack_declared` (it runs when the attackers are confirmed).

### Combat events: every keyword is called

| Hook | Host | When |
|------|------|------|
| `on_attack_declared(card, attack)` | the attacker | The attackers were confirmed (end of the declare step), once per attack, in declaration order, before the declare reaction window. Declaring and cancelling before the confirmation fires nothing |
| `on_blocked(card, attack, blockers)` | the attacker | The blocks were confirmed and this attack has at least one blocker (`blockers` is in damage order). Before the intercept reaction window |
| `on_blocking(card, attack)` | each blocker | Same moment, for the blockers |
| `before_combat_damage(card, attack)` | attacker, each blocker still in play, the attacked creature | Right before the attack's damage is worked out (not for negated or removed attacks). Called once per participant: compare `attack.attacker == card` to tell them apart. Stat modifiers added here count |
| `on_damage_dealt(card, target, amount, cause)` | the source that dealt it | `amount` > 0 was dealt to `target` (a creature `Card` or a `FatePlayer`). `cause` is `"combat"`, `"effect"` or `"stats"` |

### Damage and destruction

| Hook | Combination | Meaning |
|------|-------------|---------|
| `modify_damage_taken(card, stat, amount, cause, source) -> int` | chained: each keyword gets the previous result; never below 0 | `card` is about to lose `amount` of `stat` ("Strike"/"Guard"). Return the amount to lose instead (0 prevents it). `source` is a `Card` or null |
| `would_be_destroyed(card, cause, source) -> bool` | all must return true (any `false` prevents destruction) | Return false to keep the card on the table |
| `death_destination(card, cause) -> String` | the first keyword that answers wins | `"discard"` (default), `"removed"`, `"deck"`, `"hand"`: a zone of the card's OWNER. Return `""` for "no opinion". Untethered: `"removed"` |
| `on_destroyed(card, cause, source)` | all are called | After the card was moved. Its keyword grants are still in place (cleared right after) |

Used stat: damage lowers the stat the creature is using: Strike when upright in the creature zone,
Guard when guarding (tilted) or occupied (`FateEffects.used_stat(card)`). Combat damage that brings
the used stat to 0 destroys the creature (`FateEffects.ZERO_KILLS_CAUSES`); so does "Strike and
Guard both 0" for any cause, checked after every stat change.

### Stats and time

| Hook | Combination | Meaning |
|------|-------------|---------|
| `stat_bonus(card, stat) -> int` | summed | Added to `stat` of the host (Embody). **Do not call `game.stats.current()` in here** (it calls you; use `game.stats.base()` or your own state). When your state changes call `game.stats.refresh(card)` so the card face and the checks update |
| `on_turn_end(card)` | all are called | End of every turn (END phase, after "until end of turn" effects expired), for the creatures the active player controls |
| `on_maintenance(card)` | all are called | Start of every turn after the maintenance reset and untap, for the creatures the active player controls |

### Universal keywords

A keyword with `universal = true` (set it in `_init()`) is called for EVERY card, whether or not the
card has the keyword. Use it for rules that apply by default and that a keyword lifts. Example,
Charge: a creature cannot attack the turn it enters play unless it has Charge. Creatures without
Charge have no keyword to forbid that, so the Charge script is universal:

```gdscript
func _init() -> void:
	keyword_name = "Charge"
	universal = true

func can_attack(card: Card) -> bool:
	if card is FateCardTemplate and card.entered_turn == game.turn_number and not has(card):
		return false
	return true
```

(`entered_turn` is the turn the card was played from the hand, 0 for cards that were put on the table
by other means, so it never matches a real turn number.)

### Card actions (hover buttons): Occupy, Embody

A keyword can offer an action button on its card by overriding `actions(card) -> Array`. Return an
array of dictionaries, rebuilt every time the hover buttons appear (so `enabled` can reflect the
current state):

```gdscript
func actions(card: Card) -> Array:
	return [{
		"id": "occupy", "label": "Occ", "tooltip": "Tilt and move to the occupied zone",
		"enabled": game.keywords.can_occupy(card) and FateZones.zone_of(card) == "creatures",
		"run": _occupy,
	}]

func _occupy(card: Card) -> bool:
	card.set_card_rotation(90)
	# move_to with the "Scripted" tag is never refused by the play rules
	var slot := game.player(card.controller_id).grid("occupied").find_available_slot()
	if slot == null:
		return false
	card.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	return true
```

`run` receives the card, may be a coroutine (awaiting a choice, say) and returns `true` when it did
something. The buttons show only for the card's controller, on the table, while the game goes on
(`FateActions`, `game.actions`). Tests and the AI use the same entry points:
`game.actions.list(card)` and `await game.actions.run(card, "occupy")`. The signal
`game.actions.action_performed(card, id)` fires after a run.

## What you can call

* `game.keywords`: `has(card, name)`, `value(card, name)`, `all_on(card)`, plus the dispatchers
  (`can_attack`, `can_occupy`, ...) and `register()` / `unregister()` (for tests).
  `value` is the sum of the innate value and the granted values.
* `game.stats`: `base`, `current`, `apply_damage`, `add_modifier(card, stat, amount, expiry,
  source)`, `grant_keyword(card, name, value, expiry, source)`, `remove_modifiers_from(source)`,
  `refresh(card)`. Expiries: `"end_of_turn"`, `"owner_maintenance"`, `"permanent"`.
* `game.effects`: `destroy(card, source, cause)`, `deal_damage(target, amount, source, cause)` where
  `target` is a creature `Card` or a `FatePlayer` (`game.player(id)`).
* `game.combat`: `attacks`, `attack_of(card)`, `block_of(card)`, `negate_attack(attack)`,
  `remove_from_combat(card)`, `order_blockers(attack, ordered)`, `step`,
  `eligible_attackers()`, `eligible_blockers(attack)`.
* Signals on `game`: `creature_destroyed(card, cause)`, `damage_dealt(source, target, amount,
  cause)`, `player_defeated(player_id)`, `game_ended(winner_id)`, `maintenance_finished`,
  `turn_started`, `end_of_turn_expiry`, ... Prefer the hooks. If a keyword needs a signal that no hook covers, it can connect to it the first
  time one of its hooks runs (`game` is set by then), guarding with `is_connected` so it connects once.

## Reaction windows (for the Reaction keyword/mechanic)

`FateCombat` opens a reaction window at the end of the declare step (`"declare_end"`) and at the end
of the intercept step (`"intercept_end"`), after the keyword events of that step. It emits
`game.combat.reaction_window_requested(window)` where `window` is a `FateCombat.ReactionWindow`:
`window.step`, `window.player_id` (the defending player, who may react). By default combat continues
at once. A handler that needs time (a player choosing and paying for a reaction spell) calls
`var token := window.hold()` **while the signal is emitted** and `window.release(token)` when done
(`window.close()` ends the window regardless; the "Next phase" button does that). Combat waits
meanwhile; effects of reactions use the normal API (`negate_attack`, `remove_from_combat`,
`deal_damage`, ...). The combat UI shows "Reaction window" in the prompt while one is open.
Nothing in the core casts reaction spells.

## Testing helpers (tests/FateCommon.gd)

* `await put_creature(pid, strike, guard, innate := {}, tilted := false, zone := "creatures")`:
  a test creature with those stats and `_innate_keywords` (or pass a real card name as the second
  argument). `tilted` guards; zone `"occupied"` for occupied creatures.
* `start_combat()`: to the declare step of the active player (the END phase then waits for the
  player, so damage taken this turn is still there afterwards).
* `game.combat.declare_attack(attacker, target)` (target: creature, `FatePlayer` or player id),
  `confirm_attackers()`, `declare_block(blocker, attack)`, `confirm_blocks()`; with
  `combat.resolve_delay == 0` (the tests' default) everything resolves at once.
* `tests/FateTestKeyword.gd`: a configurable, recording keyword for testing the registry and
  combat paths; `TestKeyword.make("Name", priority, universal)` then `game.keywords.register(kw)`.
* Damage resets at the owner's maintenance (D7): during `game.end_turn()` the other player's
  maintenance clears THEIR creatures' damage. Keep `end_phase_waits_for_player` true (see
  `start_combat`) when you inspect the result of a combat.
