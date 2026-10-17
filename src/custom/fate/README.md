# Fate proof of concept: code map

Rules: `docs/FATE_RULES_SPEC.md`. Design: `docs/FATE_TCG_DESIGN.md`.

| File | What it does |
|------|--------------|
| `FateGame.gd` | Public entry point (node `FateGame`, child of the board). Players, signals, `phase`, `advance_phase()`, `end_turn()`, `start_turn()`, the energy choice, `can_play_from_hand()`, mana wrappers, the helpers (`turn`, `mana`, `stats`, `keywords`, `effects`, `actions`, `combat`), `creatures_in_play()`, `is_over` / `winner_id` |
| `FateTurn.gd` | The turn state machine (`FateTurn.Phase`). **The combat interface is documented at the top of this file** |
| `FateMana.gd` | Mana pool and automatic payment (`mana_pool`, `can_pay`, `pay`, decision D4) |
| `FateCardTemplate.gd` | Base of all cards: ownership, `entered_turn`, the rules for dragging a card from the hand to the table (pre/post move scripts) |
| `FateBoard.gd` | Builds the table and the status bar (phase, prompt, Draw extra card / Next phase / End turn, mana and life) |
| `FateZones.gd`, `FatePlayer.gd` | Zone names and lookups (`zone_of(card)`, `is_creature_in_play(card)`); per-player state |
| `FateStats.gd` | `game.stats`: base / current Strike and Guard, damage (reset at the OWNER's maintenance, D7), modifiers and keyword grants with expiry, the both-zero check |
| `FateKeyword.gd`, `FateKeywords.gd`, `keywords/` | The keyword base class (all hooks), the auto-discovering registry `game.keywords`, and one `Kw<Name>.gd` per keyword. **Read `keywords/README.md`** |
| `FateEffects.gd` | `game.effects`: `destroy()` and `deal_damage()` (creatures and players), the death pipeline, player defeat |
| `FateCombat.gd`, `FateAttack.gd` | `game.combat`: declare / intercept / resolve, the damage algorithm, reaction windows; `FateAttack` is the attack record |
| `FateActions.gd` | `game.actions`: activated card actions (Occupy, Embody) offered by keywords as hover buttons |
| `FateCombatUI.gd`, `FatePlayerAvatar.gd` | The combat overlay: click to select attackers and blockers, markers and arrows, clickable player avatars, the combat log |

## The turn

`MAINTENANCE` (auto) -> `DRAW` (auto) -> `ENERGY` (choose one: play energy, or draw an extra card) -> `MAIN`
-> `COMBAT_DECLARE` -> `COMBAT_INTERCEPT` -> `COMBAT_RESOLVE` -> `END` -> next player's turn.

* `game.phase` is a `FateGame.Phase` value. `game.advance_phase()` moves on when that is legal and
  returns whether it did (refused in ENERGY before the choice, and in the automatic phases).
* `game.end_turn()` jumps to END and starts the next turn from any phase; it does not check the ENERGY
  choice (the "End turn" button does, through `game.can_end_turn()`).
* `END` ends the turn by itself after the expiry hooks (`FateTurn.end_phase_waits_for_player` changes that).
* Signals (on `FateGame`): `turn_started(player_id, turn_number)`, `phase_begins(player_id, phase)`,
  `phase_ended`, `maintenance_started(player_id)` (before anything untaps), `maintenance_finished(player_id)` (everything untapped and reset), `end_phase_begins(player_id)`,
  `end_of_turn_expiry(player_id)`, `turn_ended(player_id)`, `energy_phase_choice_made`, `energy_played(card)`,
  `card_played(card)`, `mana_changed(player_id)`, `deck_empty(player_id)`, and from stage 2 `creature_destroyed(card, cause)`, `damage_dealt(source, target, amount, cause)`, `player_defeated(player_id)`, `game_ended(winner_id)`.
* Card scripts get every phase start as the trigger `"phase_begins"` with details
  `{player_id, phase, phase_name}` (sent through `cfc.signal_propagator`, trigger card = the game node).

## Playing cards

Dragging a card from the hand to the table is checked in `FateCardTemplate.common_pre_move_scripts`:
owner's `MAIN` phase only, not a reaction spell (D8), and `game.can_pay(card)`. If any check fails the
card stays in the hand and nothing is charged. Creatures, relics and field/world spells are paid for when
they land on the table (and get `entered_turn = game.turn_number`); regular spells are paid for and
resolve into the owner's discard pile. Moves tagged `"Scripted"` are never checked, so game code can move
cards freely.

## Combat (stage 2)

`game.combat` is a `FateCombat`. The turn machine calls `begin_declaration()`, `begin_intercept()`,
`begin_resolution()`, `next_requested()` and `cancel_combat()` on it (the contract is at the top of
`FateTurn.gd`); the combat object calls `game.advance_phase()` when a step is done. Tests may put a
stand-in (or null: the three phases are then passed at once) in `game.combat`.

```
declare   combat.declare_attack(attacker, target)  /  cancel_attack(attacker)   confirm_attackers()
intercept combat.declare_block(blocker, attack)    /  cancel_block(blocker)      confirm_blocks()
resolve   automatic, one attack at a time in declaration order (resolve_delay between them)
```

`target` is an opposing creature, a `FatePlayer` or a player id. `FateAttack` holds attacker, target,
blockers in damage order, `negated`, `removed`, `restrictions`, `resolved`, `result`, `metadata`.
Effects: `negate_attack(attack)`, `remove_from_combat(card)`, `order_blockers(attack, ordered)`.
Signals: `attack_declared`, `blocker_declared`, `attack_resolved(attack, result)`, `combat_finished`,
`reaction_window_requested(window)` and more (see `FateCombat.gd`). With `resolve_delay == 0` (tests)
everything is synchronous.

Damage, exactly as in the spec: an attacker uses Strike; a blocker or a guarding / occupied target uses
Guard; an upright target uses Strike. Both sides lose `min(A, D)`; a creature whose used stat reaches 0
is destroyed (cause `"combat"`). With several blockers the attacker spends its Strike on them in
order and loses the sum of their stats (at most its Strike). An unblocked attack on a player lowers
life by the attacker's current Strike; at 0 or less `game.player_defeated` fires, the board shows
"Player N wins" and the turn actions stop (`game.is_over`).

Decisions beyond the spec (all in `FateCombat.gd` / `FateEffects.gd`):

* A used stat of 0 destroys even when no damage was dealt (a Strike 0 creature that attacks is
  destroyed): the rule "used stat 0 means destroyed" is taken literally.
* An attack that was blocked never turns into a hit on its target: if every blocker is gone by the time
  it resolves it deals nothing (`result.kind == "blockers_gone"`). A blocked attack whose target is gone
  still fights its blockers.
* All damage of one attack is dealt before anything is destroyed (simultaneous destruction).
* Attackers whose attack was cancelled in the declare step may attack again; removed ones may not.
* Reaction windows: end of the declare step and end of the intercept step, `FateCombat.WINDOW_*`.
* The defender's damage from the attack on their turn is erased at their own next maintenance, so an
  attacker's damage lasts through the defender's turn and the defender's does not (D7 applied literally).

Everything keyword-specific goes through the hooks in `keywords/README.md`.

## Tests

`tests/FateCommon.gd` is the shared test base (starts the game at turn 1, ENERGY phase; helpers
`put_in_hand`, `put_on_table`, `put_energy`, `fill_mana`, `empty_hand`, and for combat
`put_creature(pid, strike, guard, innate, tilted, zone)`, `start_combat()`, `run_combat()`).
`tests/FateTestKeyword.gd` is a configurable recording keyword for tests.
Tests: `test_fate_poc.gd` (zones, decks, cards), `test_fate_turn.gd` (turns, energy, main phase, mana,
status bar; runs with `game.combat = null`), `test_fate_stats.gd` (stats layer, destroy, damage),
`test_fate_keyword_registry.gd` (discovery, hooks, actions), `test_fate_combat.gd` (combat rules,
turn integration, windows, hooks in combat), `test_fate_combat_ui.gd` (clicks, avatars, log, layout).
In tests the board resolves attacks at once and `FateGame.start_game` waits less (`cfc.is_testing`).

## Reactions

`game.reactions` (`FateReactions.gd`, no `class_name`, created by `FateGame`) casts reaction spells (`_spell_kind` "Reaction") in the
reaction windows of combat (D8: never in the main phase). It listens to `game.combat.reaction_window_requested`. If the window's
player (`window.player_id`, the defender) has a reaction spell they can cast, the manager `hold()`s the window, tints the castable spells
in their hand and keeps the window open for any number of casts until the player passes ("Next phase" / `window.close()`); otherwise
combat continues at once. Holding defaults to `not cfc.is_testing` (`reactions.hold_windows`) so other tests never stop at a window.

* `reactions.cast_problem(card) -> String` ("" = castable, else why: not a reaction spell, no open window, not your window, not in
  hand, not implemented, wrong window step, the spell's own condition, not enough mana), `can_cast(card)`, `castable_in_hand(pid)`.
* `reactions.cast(card, choice = null) -> bool` (reason in `last_error`): validate, `game.pay(card)`, resolve the effect, move the
  card to its owner's discard pile, emit `game.card_played` and `reactions.reaction_cast(card, window)`. Double-clicking the card in the
  hand does the same (`FateCardTemplate.execute_scripts`, only while a window is open for its owner).
* Choices (Safety Measure: one attacker; Wave of Fear: an array of attackers; Hold the Line: an array of creatures): the explicit
  `choice` of `cast`, else `reactions.chooser = func(card, candidates): ...` (return null for the default), else the deterministic
  default (highest current Strike, ties by declaration order; all attackers; all upright creatures).
* Effects are one script per spell in `reactions/` (`React<Name>.gd` extending `FateReactionEffect.gd`, registered by `card_name`;
  `problem()`, `candidates()`, `default_choice()`, `choice_problem()`, `resolve()`). Add a script to add a spell. Double Agent has none
  (needs take-control), so it is never castable.
* Spells: Factory Shutdown negates every live attack on the caster or their creatures; Safety Measure destroys an attacking creature
  (cause "effect"); Hold the Line (declare_end only) puts the caster's upright creatures in the creature zone into guard and gives them
  +1 Guard until end of turn (already guarding creatures are not "switched", so they get no bonus); Forests Protection grants
  "Indomitable" until end of turn to all the caster's creatures in play; Wave of Fear removes attackers from combat (they stay in play).
* Tests: `tests/integration/test_fate_reactions.gd` (set `game.reactions.hold_windows = true` there).
