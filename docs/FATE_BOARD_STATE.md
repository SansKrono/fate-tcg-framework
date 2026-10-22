# Board states

A **board state** is a whole Fate table as data: both players' zones in order, stats and damage,
modifiers and granted keywords, tapped energy, life, turn, phase and rng. It is a plain JSON file, so
testers can read it, edit it in any editor, and share it. The game can **capture** the live table into
one and **load** one to rebuild the table at once. Use it for test-ready positions: "player 1 in the
declare step with a buffed Savage goblin and 3 mana", without clicking there.

Code: `src/custom/fate/state/` (`FateBoardState`, `FateBoardStateFiles`, and the capture / apply
classes). JSON Schema for editor completion: `boards/board_state.schema.json`. Ready-made examples:
`boards/*.json`.

> Status: capturing, loading, the debug panel and the `--board=` launch argument all work. See
> "Implementation notes" at the end for how loading is checked and what it cannot do yet.

## Where the files live

| Folder | What | Writable |
|--------|------|----------|
| `res://boards/` (the `boards/` folder of the repo) | Shared positions, checked into git | when the game runs from the editor |
| `user://boards/` (the game's user data folder) | Personal positions | always |

A position is addressed by its file name without `.json` (`goblin_attack_ready`) or by a full path. If
both folders have the name, the personal file wins. In an exported game the `boards/*.json` files must
be added to the export's "include non-resource files" filter.

## The format (version 1)

```json
{
  "format": "fate-board-state",
  "version": 1,
  "name": "Goblin attack ready",
  "description": "free text",
  "turn": { "number": 4, "active_player": 1, "phase": "combat_declare", "energy_choice": "energy" },
  "rng": { "seed": "x", "state": 123 },
  "players": {
    "1": { "life": 10, "hand": [...], "deck": [...], "discard": [...], "removed": [...],
           "creatures": [...], "occupied": [...], "relics": [...], "field": [...],
           "energy": [...], "doctrines": "auto" },
    "2": { ... }
  },
  "world": [...],
  "definitions": { "Test 3/2": { "Type": "Creature", ... } }
}
```

Everything except `format` and `version` is optional. A file that only says `format` and `version` is an
empty table in player 1's main phase with 10 life each and no doctrines.

### Turn

| Key | Meaning | Default |
|-----|---------|---------|
| `number` | The turn number (1 or more). `entered_turn`, Charge and Productive compare against it | 1 |
| `active_player` | 1 or 2. This player sits at the bottom of the screen | 1 |
| `phase` | `energy`, `main` or `combat_declare` (declare step with no attackers chosen yet) | `main` |
| `energy_choice` | What the active player did in the energy phase: `""` (not yet, only in the energy phase), `energy`, `draw`, or `debug` | `""` in the energy phase, else `draw` |

Boards are stored **between steps**. `maintenance`, `draw`, `combat_intercept`, `combat_resolve` and `end`
are refused, with a message saying why, because they are in the middle of something that runs by itself
(blockers being assigned, attacks resolving) or cannot be paused. Save in the step before or after.

### Players

`life` (default 10) and the zones below. A missing zone is empty.

* **Piles** `hand`, `deck`, `discard`, `removed`: a list of cards, **top first** (the first card is the next
  one drawn; in the hand it is the leftmost card is the first). No empty entries.
* **Grids** `creatures` (6 slots), `occupied` (6), `relics` (3), `field` (1), `energy` (grows, up to 40),
  `doctrines` (3): a list **by slot index**. `null` is an empty slot, so `[null, "Battle Smith"]` puts the
  card in the second slot. Trailing `null`s do not matter.
* `deck` may be `{ "build": true, "size": 40 }`: a legal random deck for the player's domains
  (`FateDecks.build`), made with the state's rng.
* `doctrines` may be `"auto"`: the player's default three doctrines.
* `world` (top level, not per player) is the shared world spell slot: a list of at most 1 card.

### Cards

A card is a **name** (everything else default): `"Battle Smith"`, or an **object**:

```json
{ "card": "Goblin Scout Leader", "id": "leader", "tapped": true, "face": "up",
  "owner": 1, "controller": 1, "entered_turn": 2,
  "damage": { "Strike": 0, "Guard": 1 },
  "modifiers": [ { "stat": "Strike", "amount": 2, "expiry": "end_of_turn", "source": "buff" } ],
  "grants":    [ { "keyword": "Savage", "value": 1, "expiry": "end_of_turn", "source": "buff" } ],
  "tokens": { "tech": 2 },
  "attached": [ "Beetle Brawler" ],
  "forced_blocker": { "target": "other", "turn": 4 } }
```

| Field | Meaning | Default |
|-------|---------|---------|
| `card` | The card name (must exist, or be in `definitions`) | required |
| `id` | A label that other cards can refer to. Only needed when something refers to the card | none |
| `face` | `up` or `down` | `down` in `energy` and `deck`, else `up` |
| `tapped` | Tilted 90 degrees. For energy this means spent; for a creature it is guarding (or, in `occupied`, working) | `true` only in `occupied` |
| `owner`, `controller` | 1 or 2 | the player whose zone it is in; for a card in `world`: the active player |
| `entered_turn` | The turn it was played from the hand; 0 = not played this way (ready: not summoning sick) | 0 |
| `damage` | Damage marked on `Strike` and/or `Guard` | none |
| `modifiers` | Buffs and debuffs: `stat` (`Strike`/`Guard`), `amount`, `expiry`, `source` (a card `id` or left out) | none |
| `grants` | Granted keywords: `keyword`, `value`, `expiry`, `source` | none |
| `tokens` | Counters on the card, token name -> count | none |
| `attached` | Cards attached behind this one (energy embodied by a creature) | none |
| `forced_blocker` | The creature `target` (a card id) this card was forced to block, and the `turn` | none |

`expiry` is `end_of_turn` (default), `owner_maintenance` (the card owner's next untap) or `permanent`.

The **stats shown on a card are not stored**: they are the card's base plus `modifiers` and Embody, minus
`damage`. Mana is not stored either: each untapped energy card is one mana, so tap energy cards to spend
mana.

### Definitions

`definitions` adds or replaces card definitions for cards that are not in the game data, such as test
creatures made up for one test. Key = card name, value = the same object as the entries of
`FateData.CARDS` (it needs at least `Type`).

## Writing and editing by hand

* Start from a file in `boards/` and change it. The game validates a file when it loads it and lists every
  problem with its place in the file, for example
  `players.1.creatures[3].card: unknown card "Battel Smith" (did you mean "Battle Smith"?)`.
* Keys the game does not know are ignored with a warning, so notes like `"_comment"` are safe.
* Numbers must be whole (`2`, not `2.5`). Booleans are `true`/`false`, not text.
* Slot numbers and zone sizes are checked: six creatures at most, one field spell, and so on (energy and relics have no limit; 40 is a sanity cap).
* Pointing the editor at the schema (VS Code: `"json.schemas"`) gives completion and basic checks.

## Using board states

| How | |
|-----|--|
| Debug panel (F3 or the orange **Debug tools** button): **Board states** | Save the table, load a file, copy the JSON, paste JSON and load it |
| Launch argument | `godot --path . src/custom/fate/FateMain.tscn -- --board=goblin_attack_ready` starts the game in that position |
| Tests | `await load_board("goblin_attack_ready")` in a test based on `tests/FateCommon.gd`, then play on from there |
| Code | `FateBoardStateFiles.load_state(name)`, `await game.load_board_state(state)`, `game.capture_board_state()` |

### What loading does, and does not do

Loading **replaces** everything on the table and sets the state directly: no rules run, no cards
are drawn, nothing is paid, no "played" effects fire, and the turn's automatic steps (untap, draw) are not
run. The table is exactly the file. If the file is invalid, or something goes wrong half way, the previous
table is restored and the problems are reported.

## Implementation notes

* **Loading is checked.** After a load, the game captures the table again and compares it with the file.
  A difference (a card that could not go where the file says, a slot that does not exist...) is reported
  with its place in the file and the previous table is restored. This always runs in tests; set the
  option `verify` to force it elsewhere: `await game.load_board_state(state, {"verify": true})`.
* **Going back.** If the current table can be stored, a failed load restores it (the result's `warnings` say
  so). If it cannot (the game is mid-combat), a failed load leaves an empty table.
* **Options** of `load_board_state`: `verify`, `rollback` (default true), `reset_hooks` (default true: the
  keyword "choosers" that tests set, static values that would outlive the game, are cleared).
* **Starting from a state:** `await game.start_from_state(state)` (what `--board=` does); if the file cannot
  be loaded the game reports it and deals a normal game.
* **Random numbers** (`rng`): `seed` and `state` are written as text, because JSON numbers lose precision on
  64-bit values. They are restored last, so a built `deck` does not disturb them.
* **Not stored yet:** anything mid-combat (declared attackers, blockers, an open reaction window). Attackers
  are declared by clicking after loading a `combat_declare` state. The state of the interface (selection,
  hover, which hand is face-up) follows from the table and is not stored.
* A card's face in a hand or a pile is not stored: it follows from the container (and from who sits at the
  bottom).

### Code map

| File | |
|------|-|
| `state/FateBoardState.gd` | The resource: parse, normalise, validate, print |
| `state/FateBoardStateFiles.gd` | Folders, listing, load / save / delete, clipboard |
| `state/FateBoardStateCapture.gd` | Table -> state (`FateGame.capture_board_state`) |
| `state/FateBoardStateApply.gd` | State -> table (`FateGame.load_board_state`) |
| `FateStats.gd` | `export_card` / `import_card` / `refresh_all` / `clear_all` for damage, modifiers, grants |
| `FateGame.gd` | `place_card_at`, `place_in_container`, `reset_table`, `start_from_state` |
| `FateDebug.gd` | The Board states section of the debug panel |
| `tests/FateCommon.gd` | `load_board(name_or_state)`, `capture_board()` for tests |

Tests: `tests/unit/test_fate_board_state.gd` (format), `tests/integration/test_fate_board_state_*.gd` and
`test_fate_table_primitives.gd`. Every file in `boards/` is loaded and round-tripped by the tests.
