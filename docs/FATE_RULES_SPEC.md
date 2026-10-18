# Fate Rules Implementation Spec: Turns, Combat and Keywords

Working spec for the second implementation pass of the Fate proof of concept (see
`docs/FATE_TCG_DESIGN.md`, Sections 4, 8 and 9, and its status in Section 17). It fixes the rules that are
being implemented and the conventions all contributors (human or agent) follow. Rules text comes from the game
designer; where the designer was silent, the decision is listed in Section 5 so it can be changed.

## 1. Turn structure

A turn is these steps, in order. "Phase" below means a value of the turn manager's phase enum.

| # | Step | Phase | What happens |
|---|------|-------|--------------|
| 1 | The player's turn starts | (start) | Active player changes, turn counter increments, per-turn flags reset, `turn_started` is emitted |
| 2 | Maintenance | `MAINTENANCE` | All of the player's mana (energy cards) untap. Occupied cards untap and move back to their zone (the creature zone). Other tapped permanents untap. Creatures return to the strike position. Current combat stats reset to their base values (and "until end of turn" effects are gone). Automatic |
| 3 | Draw phase | `DRAW` | The player draws one card. Automatic |
| 4 | Energy phase | `ENERGY` | The player chooses ONE of: play a card from hand face-down into the energy zone, or draw an additional card (forgoing the energy play). The phase ends when the choice is made |
| 5 | Main phase | `MAIN` | The player taps mana to play cards from hand for their cost. They may also position creatures (strike / guard). Cards that cannot be paid for are not played |
| 6 | Combat phase: declare attackers | `COMBAT_DECLARE` | The player declares which of their creatures attack and what each attacks: an opposing creature or the opposing player directly |
| 7 | Combat phase: intercept | `COMBAT_INTERCEPT` | The enemy player may intercept an attack, only with creatures that are guarding or occupied |
| 8 | Combat phase: resolve | `COMBAT_RESOLVE` | Each combat resolves one at a time, in the order the attacks were declared |
| 9 | End phase | `END` | After combat is resolved. "Until end of turn" effects expire |
| 10 | The player declares the end of the turn | (end) | The next player's turn starts (step 1) |

The player advances the turn manually with a "next phase" control and an "end turn" control; phases that
need no input (maintenance, draw) run by themselves. Phases with a choice or work to do wait for the player.

## 2. Mana and costs

- Mana comes from energy cards. Each untapped energy card in a player's energy zone is 1 mana of one of
  its domains. An energy card is tapped (rotated 90 degrees) when spent.
- Playing a card in the main phase costs its generic `Cost` plus its domain `Pips` (one mana of that
  domain per pip; generic cost can be paid with any domain). The player must be able to pay all of it.
- Playing means: moving the card from hand to its zone (creatures, relics, field and world spells) or,
  for regular spells, resolving it into the discard pile.
- Only the owner, during their own main phase, can play cards from their hand.

## 3. Combat

1. **Declare.** The active player picks creatures that can attack (in the creature zone, in strike position, not
   tapped or occupied, passing keyword restrictions, each at most once per combat phase) and a target for each: an
   opposing creature or the opposing player. Attacks are kept in the order declared.
2. **Intercept.** The defending player may assign blockers: creatures that are **guarding** (guard position) or
   **occupied** (in the occupied zone). A blocker blocks one attacker; several blockers may block the same
   attacker. A blocker can intercept any attack, whatever its target. Keywords can restrict this.
3. **Resolve.** Attacks resolve one at a time in declaration order.

**Damage.** Combat damage lowers the stat the creature is *using*, never the card's base stat:

- an attacker uses its **Strike**;
- a blocker, or an attacked creature that is in guard or occupied position, uses its **Guard**;
- an attacked creature that is in strike position and not blocking uses its **Strike** (both creatures use Strike).

For one attacker (stat `A`) against one defender (stat `D`): `A' = max(0, A - D)` and `D' = max(0, D - A)`.
The creature whose used stat reaches 0 is destroyed (both are, if both reach 0). Example: Strike 3 attacking
Guard 2 leaves the attacker at 1 and destroys the defender. With several blockers on one attacker, the attacking
player orders them; the attacker's Strike is spent on each in order (a blocker absorbs at most its current Guard
before the next one takes damage), and the attacker loses the sum of the blockers' used stats. An unblocked
attack on a player lowers their life by 1, whatever the attacker's Strike (an attacker with 0 Strike deals none). If an attacker's target was removed before
it resolves, the attack deals no damage unless blocked. Reduced stats stay reduced until that creature's owner's
next maintenance.
At any time, a creature whose Strike **and** Guard are both 0 is destroyed. Destroyed creatures go to their owner's
discard pile unless a keyword changes that (Section 4).

## 4. Keywords and combat effects (in scope for this pass)

| Keyword / mechanic | Rule |
|--------------------|------|
| **Charge** | May attack the turn it enters play. Without it, a creature cannot attack the turn it enters |
| **Productive** | May occupy the turn it enters play. Without it, a creature cannot occupy the turn it enters |
| **Occupy** | Tilt the card and move it to the occupied zone (an activated-ability cost). An occupied creature cannot attack and cannot return to strike until maintenance, but it **can intercept** attacks (using its Guard) and can be targeted |
| **Savage X** | When this creature is blocked, it deals X damage to the blocking creature's controller or to another creature that controller has |
| **Indomitable** | Cannot die from combat damage (its used stat is held at 1 instead of reaching 0) |
| **Untethered** | When it dies, remove it from the game (removed pile) instead of the discard pile |
| **Unblockable / cannot block** | Cannot be intercepted; or cannot intercept (even in guard position or occupied). Can still be targeted |
| **Forced single blocker** | An attacker restricted so that only a named creature may block it |
| **Embody X** | Pay X to move an energy card beneath the creature; the creature gets +Strike and +Guard equal to that card's mana value; one card at a time (a replaced card goes to the discard pile) |
| **Reaction windows** | At the end of the declare step and during the intercept step, players may cast reaction spells (paying mana) before the attacks continue |

Out of scope for this pass: Evolve, Flip Cast, Limiter, doctrines, tokens, take-control and card scripts for the other
cards. (The AI opponent came later: `src/custom/fate/ai/README.md`.)

## 5. Decisions where the designer was silent

| # | Question | Decision | Where to change it |
|---|----------|----------|--------------------|
| D1 | Does the first player draw on turn 1? | Yes: every turn includes the draw phase | `FATE_FIRST_PLAYER_SKIPS_FIRST_DRAW` constant, default `false` |
| D2 | Which tapped permanents untap in maintenance? | Energy, relics, creatures (and occupied cards move back to the creature zone); creatures also return to strike position (design doc Section 4.2) | Maintenance step |
| D3 | May the player do neither in the energy phase? | No. They choose one of the two; there is no skip | Energy phase |
| D4 | How is mana chosen when paying? | Automatically: domain pips are paid first with energy of that domain, then generic cost with whatever remains, preferring to keep domains that are still needed. A picker UI is a later task | Mana payment helper |
| D5 | Can occupied creatures intercept? | Yes (designer rule for this pass; the earlier draft said no) | Intercept step |
| D6 | Do creatures that were declared as attackers stay tilted? | They remain upright. Attacking does not tap | Declare step |
| D7 | Whose maintenance resets damage? | The damaged creature's owner's | Maintenance step |
| D8 | Reaction spells outside reaction windows? | Cannot be cast in the main phase | Main phase play rule |

## 6. Architecture and conventions

- All Fate code lives in `src/custom/fate/` (new folders below it are fine). Tests are in `tests/integration/`
  (`test_fate_*.gd`, extending `res://tests/UTcommon.gd`, see `tests/integration/test_fate_poc.gd` for the setup).
- Reuse the framework before writing new code: `FateZones` (zone names and lookups), `FatePlayer`, `FateGame`,
  `FateCardTemplate`, `FateBoard`, and the framework's `Card` rotation, `move_to`, attachments and signals. Do not
  hard-code `cfc.NMAP.hand`/`deck`/`discard`; use `FateZones.container(zone, player_id)`.
- Core framework edits (`src/core/`) only when a framework bug blocks the work, kept minimal and reported.
- New keywords are one script each in `src/custom/fate/keywords/` and register themselves through the keyword
  registry (see the hook API documented in `src/custom/fate/keywords/README.md`, written with the combat core),
  so keyword work never edits shared files.
- Card definitions are generated: `python3 tools/gen_fate_cards.py` rewrites `src/custom/fate/FateData.gd`.
  Cards list their innate keywords in `_innate_keywords` (name -> value); `_keywords` is the display list.
- Code style: tabs, GDScript 4, comments in the existing style (explain why, reference the rule).
- Run tests with the headless GUT command in `CONTRIBUTING.md` (single file: `-gdir=res://tests/integration
  -gselect=test_fate_xxx`). Prefer waiting with `wait_card_settled`/signals over fixed delays. Never commit.
- Existing tests must keep passing; update tests only when a rule here intentionally changes behaviour, and say so.

## 7. Implementation status (second pass)

All of Sections 1 to 4 are implemented and tested headless (turn phases, mana payment, combat, the stat layer and
the keywords in the Section 4 table). Where the build made decisions beyond Section 5:

- The turn ends by itself after the END phase (`FateTurn.end_phase_waits_for_player` makes it wait).
  `game.end_turn()` jumps straight to END and starts the next turn.
- Occupied cards move to the first free creature slot at maintenance; if the creature zone is full they stay in
  the occupied zone, untapped.
- A used stat of 0 destroys a creature in combat even when no damage was dealt (a Strike 0 attacker dies; a Guard 0
  blocker dies). Non-combat damage only kills through the both-stats-zero rule. This follows the damage algorithm
  (`D' = max(0, D - A)`) and the rule that a used stat of 0 means destroyed; change `ZERO_KILLS_CAUSES` in
  `FateEffects` if it is not wanted.
- Savage damage is dealt when blocks are confirmed, before the intercept reaction window and before combat damage.
- A creature killed while blocking leaves its attack; if it was the only blocker the attack deals nothing
  (`blockers_gone`).
- Indomitable holds the used stat at 1 against combat damage only; granted keywords expire when the END phase
  starts.
- Reaction windows exist after the declare step and after the intercept step; reaction spells are cast by
  double-clicking them in hand while a window is open for their owner; a window with nothing castable does not
  pause the game.
- `T` (tilt) works only for the controller's creatures in the creature zone during their main phase.

Not implemented: card-specific effect scripts. (Evolve, Flip Cast, Limiter, take-control and tokens are systems now; the AI
player is described in `src/custom/fate/ai/README.md`.) Open: ordering UI for several blockers, target-choice UIs (default choosers are used).
