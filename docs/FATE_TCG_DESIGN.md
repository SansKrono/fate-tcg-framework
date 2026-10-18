# Fate TCG: Framework Adaptation Design Document

Adapts the early design draft *Fate TCG.md* ("Control the fate of Dominarus") to the Godot 4
card framework in this repository (branch `v4-migration`). It identifies every mechanic, keyword, stat,
card type and zone in the draft, links each to an existing framework component, and marks everything
that needs custom implementation.

- **Source of the game rules:** `Fate TCG.md` (the "draft"). Where the draft is ambiguous or
  contradicts itself, this document states the interpretation it assumes and lists it in
  [Section 12](#12-open-questions-and-draft-inconsistencies) so the designer can confirm.
- **Source of framework facts:** read directly from `src/core` and `src/custom` (file references are given
  throughout). Statements about what the framework does *not* contain were checked by searching the source.

## Contents

1. [Summary and coverage](#1-summary-and-coverage)
2. [Legend](#2-legend)
3. [Framework primer](#3-framework-primer)
4. [Game model: players, turns, win condition](#4-game-model-players-turns-win-condition)
5. [Cards: types, stats and data model](#5-cards-types-stats-and-data-model)
6. [Zones and piles](#6-zones-and-piles)
7. [Energy and mana](#7-energy-and-mana)
8. [Combat](#8-combat)
9. [Keywords and ability patterns](#9-keywords-and-ability-patterns)
10. [Doctrines](#10-doctrines)
11. [Tokens, deck building and spell rules](#11-tokens-deck-building-and-spell-rules)
12. [Open questions and draft inconsistencies](#12-open-questions-and-draft-inconsistencies)
13. [Custom systems specification](#13-custom-systems-specification)
14. [Card-by-card implementation catalog](#14-card-by-card-implementation-catalog)
15. [Implementation roadmap](#15-implementation-roadmap)
16. [Test strategy](#16-test-strategy)
17. [Implementation status (proof of concept)](#17-implementation-status-proof-of-concept)

---

## 1. Summary and coverage

The framework supplies the **table and the card automation**: card scenes, hand/pile/board containers,
drag and drop, rotation and flipping, attachments, tokens, counters, a data-driven scripting engine with
signal triggers, filters, costs, alterants and targeting, a deck builder, and a GUT test harness.

It does **not** supply a game rules layer. A search of `src/` finds no turn or phase system, no player or
ownership concept (every container is looked up by a single global name in `cfc.NMAP`), no combat, no
life total, no response/priority window, and no continuous-effect (static buff) layer. Fate's rules are
built almost entirely out of exactly those things, so the work splits as follows:

| Area | Coverage | Notes |
|------|----------|-------|
| Card rendering, hand, deck, discard, viewing, focus | **Native** | Core framework |
| Card types as scene templates, card data files, deck builder, copy limits | **Native / config** | `Type` property selects the scene; `_max_allowed` limits copies |
| Strike / Guard / Occupied *visual* positions | **Native** | Card rotation and board grids |
| Equipping relics, embodied energy cards | **Native** | Card attachments |
| Spawning tokens, drawing, discarding, searching a deck, shuffling | **Native** | Scripting-engine tasks |
| Cost reduction, "create an additional token" | **Native** | Alterants |
| Turn and phase flow | **Custom** (SYS-TURN) | Needed by almost every card |
| Two players, ownership and control | **Custom** (SYS-PLAYER) | Largest structural gap |
| Energy zone, mana, pip costs, once-per-turn energy play | **Custom** (SYS-ENERGY) | Uses native grid, counters and costs |
| Combat, blocking, damage, savage, indomitable | **Custom** (SYS-COMBAT) | Targeting arrow is reused |
| Reaction spells and responses | **Custom** (SYS-RESPONSE) | |
| "Until end of turn" and static stat modifiers, granted keywords | **Custom** (SYS-MOD) | |
| Doctrines | **Custom** (SYS-DOCTRINE) | Reuses card scripts and `per_*` counting |
| Resource tokens (scrap, ingot) | **Native + small custom** | Recommended as counters |
| Win condition, starting rules | **Undefined in the draft** | See Section 12 |

**Card catalog totals** (Section 14 covers all 83 cards in the draft; Decklist 2 contains only four unfinished
theme notes, listed separately):

| Implementation class | Meaning | Cards |
|----------------------|---------|-------|
| A | Card definition plus script tasks that exist today | 9 |
| B | Also needs generic custom systems (SYS-*), but no card-specific code | 63 |
| C | Needs a card-specific new task, rule exception or new UI | 11 |

All 83 cards additionally need the three baseline systems (SYS-PLAYER, SYS-TURN, SYS-ENERGY). The counts are
tallied from the class column of the Section 14 tables.

## 2. Legend

**Status tags** used in every mapping table:

| Tag | Meaning |
|-----|---------|
| **NATIVE** | Works today with the named framework component and no new code |
| **CONFIG** | Works by editing data/config files only (card definitions, script definitions, `CFConst`, `CardConfig`, scenes) |
| **EXTEND** | Needs new code that plugs into a documented framework extension point (override, subclass, new scripting task, new SP filter) |
| **CUSTOM** | New system or new code with no framework equivalent |
| **DECIDE** | The draft does not define it; a design decision is needed before implementation |

**Class A / B / C** (catalog only): A = NATIVE/CONFIG only; B = needs listed SYS systems but no card-specific code; C = needs card-specific new task, rule or UI.

**Custom system IDs** (specified in Section 13): SYS-TURN, SYS-PLAYER, SYS-ENERGY, SYS-COMBAT, SYS-RESPONSE,
SYS-MOD, SYS-KEYWORD, SYS-DOCTRINE, SYS-SLOT, SYS-CONTROL, SYS-TOKEN, SYS-FILTER, SYS-DECK.

## 3. Framework primer

Components this design relies on. Paths are relative to the repo root.

| Component | File(s) | What it gives Fate |
|-----------|---------|--------------------|
| `Card` | `src/core/CardTemplate.gd`, `src/custom/CGFCardTemplate.gd` | Card node (an `Area2D`): states (`CardState`), `properties` dictionary, faceup/viewed, rotation (`card_rotation`), `move_to()`, attachments (`attach_to_host`, `attachments`, `current_host_card`), token drawer, targeting arrow, drag handling |
| Card scenes | `src/custom/cards/*.tscn`, `CardConfig.gd` | One scene per card `Type`. `CardConfig` declares string, number and array properties and the scene property |
| Card data | `src/custom/cards/sets/SetDefinition_*.gd` | `CARDS` dictionary: name to properties (`Type`, `Tags`, `Cost`, `Power`, `Abilities`, `_meta` keys) |
| Card scripts | `src/custom/cards/sets/SetScripts_*.gd` | Per card: trigger -> card state (`board`, `hand`, `pile`) -> list of task dictionaries. See `src/custom/cards/sets/README.md` and `SCRIPTING_ENGINE.md` |
| Scripting engine | `src/core/ScriptingEngine/ScriptingEngine.gd` | Tasks: `rotate_card`, `flip_card`, `view_card`, `move_card_to_container`, `move_card_to_board`, `mod_tokens`, `spawn_card`, `spawn_card_to_container`, `shuffle_container`, `attach_to_card`, `host_card`, `modify_properties`, `ask_integer`, `add_grid`, `mod_counter`, `execute_scripts`, `nested_script`, `null_script`, plus `custom_script` |
| Script keys | `src/core/ScriptingEngine/ScriptProperties.gd`, `src/custom/SP.gd` | `subject` (`target`, `self`, `trigger`, `boardseek`, `tutor`, `index`, `previous`), `is_cost`, `is_optional_<state>`, `is_else`, `needs_selection`, `per_*` counting, `filter_*` trigger filters, `alterants`, `temp_mod_*`, `nested_tasks`, `repeat`, `store_integer` |
| Signals | `CFControl.gd` (`signal_propagator`) | Card signals that trigger scripts: `card_rotated`, `card_flipped`, `card_viewed`, `card_moved_to_board`, `card_moved_to_pile`, `card_moved_to_hand`, `card_token_modified`, `card_attached`, `card_unattached`, `card_targeted`, `card_properties_modified`; counters emit `counter_modified`. Objects in group `scriptables` with an `execute_scripts()` method also receive triggers |
| Alterants | `AlterantEngine.gd`, `ScriptAlter.gd` | Modify the value of `mod_counter`, `mod_tokens` and `spawn_card` tasks (cost changes, extra tokens) |
| Containers | `CardContainer.gd`, `Pile.gd`, `Hand.gd` | `Pile` (`faceup_cards`, shuffle styles, view popup, sorted popup), `Hand` (`hand_size`, `ExcessCardsBehaviour`), anchored placement |
| Board | `BoardTemplate.gd`, `src/custom/CGFBoard.gd`, `BoardPlacementGrid.gd`, `BoardPlacementSlot.gd` | Table, named grids with slots (`auto_extend`), `add_grid` task, `get_grid()` |
| Counters | `Counters.gd`, `src/custom/CGFCounters.gd` | Named global counters, `mod_counter`, `per_counter`, `counter_modified` trigger |
| Tokens | `Token.gd`, `Card/TokenDrawer.gd`, `CFConst.TOKENS_MAP` | Counted markers shown on a card, `mod_tokens`, `per_token` |
| Filters | `Utils/CardFilter.gd`, `SP.filter_trigger` | Property filtering for subjects, triggers and the card viewer; `SP` is the designated place to add game-specific filters |
| Selection UI | `SelectionWindow.gd`, `CardChoices.gd`, `OptionalConfirmation.gd`, `AskInteger.gd` | Pick cards, choose a mode, confirm optional effects, enter a number |
| Move hooks | `CardTemplate.common_pre_move_scripts`, `common_post_move_scripts`, `check_play_costs`, `pay_play_costs` | Override points to redirect or deny moves and to charge costs |
| Deck builder | `src/core/CardViewer/`, `src/custom/CGFDeckbuilder/` | Card library, filters, deck lists (`user://Decks/`), per-card limits via `_max_allowed` |
| Viewport focus | `ViewportCardFocus.gd` | Zoomed card plus info panels; keyword help from `CardConfig.EXPLANATIONS` |
| Test harness | `tests/UTcommon.gd`, `addons/gut` | Board/main setup, fake mouse, drag/drop helpers |

**Script execution states.** A card runs scripts under `board` only while face-up on the table,
`hand` while in the hand, and `pile` while in any pile (`CardTemplate.get_state_exec`). This matters for
Fate: a card in the discard pile or a face-down energy card runs its `pile` or no scripts, which is exactly
how "castable from discard" and "face-down cards have no abilities" can be modelled.

---

## 4. Game model: players, turns, win condition

### 4.1 Players and ownership (SYS-PLAYER) - CUSTOM

The draft is a two-player game (it also allows more) in which cards constantly change sides: take control of
a creature, place an opponent's card in your energy zone, "opponent chooses a permanent to give you",
"target player's library". The framework has one set of globally named containers (`cfc.NMAP["hand"]`,
`["deck"]`, `["discard"]`, the board) and no notion of who owns or controls a card.

| Need | Framework | Plan |
|------|-----------|------|
| Per-player hand, deck, discard, energy, removed-from-game | `Hand`, `Pile` nodes registered under unique names | **EXTEND**: instantiate one set per player with suffixed names (`hand_p1`, `deck_p2`, ...). Scripts already take container names (`src_container`, `dest_container`), so tasks work unchanged once names are generated from the acting player |
| Owner and controller of a card | none | **CUSTOM**: add `owner_id` (fixed at deck load) and `controller_id` (changes on "take control") to the Fate card script (`CGFCardTemplate`). `controller_id` is derived from which board half/zone a permanent sits in |
| "You" / "opponent" in scripts | none | **EXTEND**: add `SP` filters (`filter_controller`, `filter_owner`, values `you`, `opponent`, `any`) in `src/custom/SP.gd`, which is the supported extension point |
| Two boards on one screen | `BoardTemplate`, `CardContainer.Anchors` | **CONFIG**: lay out two mirrored halves with anchors and named `BoardPlacementGrid`s |
| Multiplayer | none | **DECIDE**: hotseat, AI opponent or network. Recommended first target: hotseat plus a simple scripted opponent, with all rules written against a `PlayerContext` so networking can be added later |

### 4.2 Turn structure (SYS-TURN) - CUSTOM

Draft turn: **Upkeep** -> **Main 1** -> **Combat** -> **Main 2** -> **End** (the draft lists "Main phase" once and
refers to "first or second main phase" in the spell rules, so Main 2 is assumed).

| Draft step | Rule | Framework mapping | Status |
|------------|------|-------------------|--------|
| Upkeep: choose Manifest or Ponder | Manifest: draw 1 and place 1 card in energy zone. Ponder: draw 2, no energy play. Cannot do both | Choice via `CardChoices`/`OptionalConfirmation`; draw via `move_card_to_container` (`src_container: deck`, `subject: index`, `dest_container: hand`); energy play via SYS-ENERGY | **EXTEND** |
| Upkeep: reset | All creatures to strike position; relics and energy untapped | `rotate_card` tasks on `boardseek` subjects; also restore current stats and clear "until end of turn" modifiers (SYS-MOD) | **CONFIG** + SYS-MOD |
| Main phases | Play cards, set positions, activate abilities | Existing drag-to-board and double-click `manual` scripts; add phase gating | **EXTEND** |
| Combat | Declare attackers/targets, declare blockers, resolve each combat | SYS-COMBAT | **CUSTOM** |
| End step | End turn; "at the end of turn" effects fire here | SYS-TURN phase signal | **CUSTOM** |

**Design:** a `TurnManager` node (child of the Fate board, added to group `scriptables`) holds
`current_player`, `phase`, `turn_number` and per-turn flags (energy played, spells cast, once-per-turn
abilities used). It emits phase changes through the existing signal propagator
(`cfc.signal_propagator._on_signal_received(card_or_manager, "phase_begins", {"phase": "upkeep", "player": id})`)
and the new trigger name is added to `known_card_signals`. Existing trigger filtering then lets card scripts say
"at the beginning of your turn" without any per-card code (add `filter_phase` and `filter_player` to `SP`).
`CFControl.game_paused` already exists to block player input and can be reused while resolving responses.

### 4.3 Win condition and starting rules - DECIDE

The draft allows attacks "directly at players" but never defines life, win or loss, opening hand size,
mulligans, who goes first, maximum hand size, or what happens on an empty deck. Proposed defaults, all
configurable:

| Rule | Proposed default | Implementation |
|------|------------------|----------------|
| Life total | 10 | One `life` counter per player in `CGFCounters.needed_counters`; damage through `mod_counter` (alterant-aware) |
| Loss | Life <= 0, or draw from an empty deck | Check on `counter_modified` and on draw |
| Opening hand | 7, one free mulligan | Setup phase in `TurnManager` |
| Hand size | 10 (framework default) | `Hand.hand_size`, `ExcessCardsBehaviour.DISCARD_OLDEST` |
| First player | Random, skips first draw | `cfc.game_rng` (seeded RNG already exists) |

---

## 5. Cards: types, stats and data model

### 5.1 Card types

| Draft type | Framework mapping | Status |
|------------|-------------------|--------|
| **Creature** | Scene `Creature.tscn` (new, copy of an existing card scene), `Type = "Creature"`. Lives on a creature grid | **CONFIG** |
| **Relic** | Scene `Relic.tscn`, `Type = "Relic"`. Lives on the relic grid or attached to a creature | **CONFIG** |
| **Spell: regular** | Scene `Spell.tscn`, tag `Spell`. Scripts run from `hand` state; the card resolves, then moves to discard | **CONFIG** + timing gate (SYS-TURN) |
| **Spell: reaction** | Same scene; cast in response windows | **CUSTOM** (SYS-RESPONSE) |
| **Spell: persisting - field** | One slot per player. New field spell sent to discard when replaced | **EXTEND** (SYS-SLOT, replacement via `common_pre_move_scripts`) |
| **Spell: persisting - world** | One shared slot between the two fields. Only one in play | **EXTEND** (SYS-SLOT) |
| **Token** (soldier, automaton, relic tokens) | `Type = "Token"` cards, spawned by `spawn_card`; hidden from the deck builder by `CardConfig.TYPES_TO_HIDE_IN_CARDVIEWER` | **CONFIG** |
| **Doctrine** | New scene `Doctrine.tscn`, not part of the 40-card deck | **CUSTOM** (SYS-DOCTRINE) |

`Type` is also the framework's scene selector (`CardConfig.SCENE_PROPERTY`), so a Fate card's *type* and
*scene* are the same field. Persisting-spell kind (field / world) and spell speed (regular / reaction) are
therefore stored as `Tags` or meta properties (below).

### 5.2 Stats

| Draft stat | Meaning | Framework mapping | Status |
|------------|---------|-------------------|--------|
| Mana cost number | Generic mana | `Cost` (already in `CardConfig.PROPERTIES_NUMBERS`) | **CONFIG** |
| `#` pips after the cost (`1##`, `###`) | Draft notation. Interpreted as domain mana the card requires, because the draft says costs are "1-2 mana of a specific concept and the rest any colour" | New string property, e.g. `"II"`. Proposed as the hidden `_pips`; implemented as the displayed `Pips` (Section 17.5). See Section 12, item 1 | **DECIDE** |
| **Strike** (left stat) | Attack value; also the stat used while in strike position | New number property `Strike` added to `PROPERTIES_NUMBERS` | **CONFIG** |
| **Guard** (right stat) | Block value | New number property `Guard` | **CONFIG** |
| Current in-use value | Combat damage lowers the stat in use until end of turn | `properties` holds the *current* value; base values are always recoverable from `cfc.card_definitions[name]`. Reset at upkeep | **CUSTOM** (SYS-MOD) |
| Creature subtypes (Goblin Engineer, Human Soldier, Ghost...) | Rules text refers to them ("Ghost in addition") | `Tags` array | **CONFIG** |
| Unique | One copy per deck | `_max_allowed: 1` (already read by the deck builder) | **NATIVE** |
| Domain / colour | Chaos, Order, Primal, Innovation (the draft uses Divine/Abyssal and Chaos/Order interchangeably) | Property `Domain` (array for dual-domain cards in Decklist 2) | **CONFIG** |

**Property additions** (all in `src/custom/cards/CardConfig.gd`):

```gdscript
const PROPERTIES_STRINGS := ["Type", "Requirements", "Abilities", "Domain"]
const PROPERTIES_NUMBERS := ["Cost", "Strike", "Guard"]   # "Power" is removed
const PROPERTIES_ARRAYS  := ["Tags"]
const NUMBERS_HIDDEN_ON_0 := ["Strike", "Guard"]          # relics and spells show no stats
const EXPLANATIONS := { ... one entry per keyword, see Section 9 ... }
const CARD_BBCODE  := { "strike": "[img=...]", "guard": "[img=...]" }
```

The card front scene needs `Strike` and `Guard` labels (the framework fills a label for every non-underscore
property and reports an error for a property without a label) and the `Cost` / `_pips` display.

**Example definition**

```gdscript
"Steelwork Salvager": {
    "Type": "Creature", "Domain": ["Innovation"], "Tags": ["Goblin", "Engineer"],
    "Cost": 2, "_pips": "II", "Strike": 2, "Guard": 1, "Requirements": "",
    "Abilities": "When Steelwork Salvager attacks, create a scrap token.",
    "_max_allowed": 3, "_keywords": [],
},
```

### 5.3 Card positions

| Position | Draft rule | Framework mapping | Status |
|----------|-----------|-------------------|--------|
| **Strike** | Face-up, portrait. Can attack, cannot block | `card_rotation == 0` on the creature grid | **NATIVE** (`rotate_card`, `Card.set_card_rotation`) |
| **Guard** | Tilted sideways. Can block, cannot attack | `card_rotation == 90` on the creature grid | **NATIVE** |
| **Occupied** | Tilted, moved to a row directly behind active creatures. Cannot attack or return to strike this turn; can still be targeted; guard stat is used. **Designer update:** it can intercept attacks (decision D5) | `card_rotation == 90` and moved to the `occupied` grid. Reset at upkeep | **EXTEND** (SYS-SLOT, `occupy` helper task) |
| Switching position | Main phase action (draft) plus card effects | Position change button/drag plus `rotate_card`; filter with `filter_degrees` | **EXTEND** |

Rotation changes already raise `card_rotated`, so "after this creature attacks, switch it to guard" is a
trigger on `card_rotated` or on the attack signal.

---

## 6. Zones and piles

| Draft zone | Framework component | Config | Status |
|------------|--------------------|--------|--------|
| **Deck** (40 cards, 3 copies, legendary 1) | `Pile` (`CGFDeck`): `faceup_cards = false`, shuffle styles, popup view, `get_top_card()` | One per player | **NATIVE** |
| **Hand** | `Hand` (`CGFHand`): oval fan, `hand_size`, `excess_cards` | One per player | **NATIVE** |
| **Discard** | `Pile` (`CGFDiscard`): `faceup_cards = true`, sorted popup | One per player. Cards here run `pile` scripts, which enables "cast from discard" | **NATIVE** |
| **Energy zone** | `BoardPlacementGrid` (`energy`), cards placed face-down. Not a `Pile`, because energy cards must tilt when spent, and must be individually visible to the owner, selectable, and able to carry attachments | One grid per player, `auto_extend = true` | **EXTEND** (SYS-ENERGY) |
| **Creature row (active)** | `BoardPlacementGrid` (`creatures`), `auto_extend = true` | Strike and guard creatures | **CONFIG** |
| **Occupied row** | `BoardPlacementGrid` (`occupied`), directly behind the creature row | | **CONFIG** |
| **Relic zone** | `BoardPlacementGrid` (`relics`) | Unattached relics. Equipped relics are attachments | **CONFIG** |
| **Field spell slot** | `BoardPlacementGrid` (`field_spell`) with one slot | Replacement rule in SYS-SLOT | **EXTEND** |
| **World spell slot** | `BoardPlacementGrid` (`world_spell`) with one slot, centred between the fields | Shared between players | **EXTEND** |
| **Removed from game** | `Pile` (`removed`), `faceup_cards = true`, per player | Used by Untethered, Lucran, Wraithful Treespirits. Cards there run no scripts that matter | **CONFIG** |
| **Doctrine area** | `BoardPlacementGrid` (`doctrines`) | Holds up to the allowed number of doctrine cards, revealed before the game | **CUSTOM** (SYS-DOCTRINE) |
| **Beneath a creature** (embody) | Card attachment (`ATTACH_BEHIND`), face-down | Holds the embodied energy card | **NATIVE** (`attach_to_host`) |
| **Tokens** | Cards in the creature or relic grid (creature and relic tokens); counters for scrap and ingots | See Section 11.1 | **EXTEND** |

`BoardPlacementGrid` slots are discovered by the `add_grid` task, `board.get_grid(name)` and the
`grid_name` key of `move_card_to_board` / `spawn_card`, so every zone above can be targeted from scripts
by name. `CardContainer.Anchors` positions piles and the hand at screen anchors and shifts overlapping
containers (`overlap_shift_direction`), which handles the mirrored two-player layout.

**Important script-state consequences**

- Face-down energy cards run no `board` scripts, so they have no abilities in the energy zone (correct per draft).
- "Flip cast" and "cast from discard" are cards executing a `pile` or energy-zone script, or being moved to the
  board through a cast helper. Both are implemented by one shared custom task (`cast_card`, Section 13).
- A card moved between piles raises `card_moved_to_pile` with `source` and `destination`; this is the basis of
  "when X dies" (board -> discard) triggers.
- Cards moved by `move_card_to_container` always land in the named container's `Pile`. Moving a card into an
  opponent's energy zone is the same call with the opponent's container name.

---

## 7. Energy and mana

### 7.1 Rules recap (from the draft)

- Four mana types, one per domain. Cards cost mostly generic mana plus 1-2 of a specific domain.
- Any card can be played face-down as mana, **once per turn** (instead of Ponder). It becomes 1 mana of one of
  its domains (the player picks if it has two). It cannot later be cast face-up unless an effect says so.
- Energy cards untap at upkeep. Energy has a *mana value* used by Embody, Dockside Ambusher and Equal Footing
  (assumed: the card's printed `Cost`).
- Some effects move cards into energy (from the opponent's deck, discards, board) and some take them out
  (flip cast, Teshra, Guardian Spirits).

### 7.2 Mapping

| Mechanic | Framework piece | Status |
|----------|-----------------|--------|
| Energy zone holds face-down cards | `energy` grid, `set_is_faceup(false)`; owner can peek with `view_card` | **EXTEND** |
| Energy card taps when spent | `rotate_card` 90 degrees; untap with `rotate_card` 0 at upkeep | **NATIVE** |
| Which domain an energy card provides | Property `_energy_domain` set at play time (chosen by player for dual-domain cards) | **CUSTOM** (SYS-ENERGY) |
| Available mana pool | Computed on demand from untapped energy cards plus temporary mana (Holy Amulet, Ancient Tree). Displayed with the existing counters UI: one counter per domain | **CUSTOM** (read-only counters from `CGFCounters`) |
| Cost payment (`Cost` generic plus `_pips`) | Override `Card.check_play_costs()` (returns the `CostsState` colour, so unaffordable cards glow red) and `pay_play_costs()` in `CGFCardTemplate`. The existing example charges a `credits` counter on hand -> board moves; replace it | **EXTEND** |
| Cost reduction / increase (Meek Minion, other cards) | Alterants on `mod_counter` with `filter_tags: ["PlayCost"]`, as shown in `ScriptProperties.KEY_ALTERANTS` | **NATIVE** |
| Once-per-turn energy play | Gate in `common_pre_move_scripts` (deny the move into the energy grid if the flag is spent) and clear the flag in SYS-TURN. Choosing Manifest or Ponder at upkeep sets the flag | **EXTEND** |
| "Pay X" in abilities (Spirit Wielder, Beetle Brawler, Teshra) | Same payment helper, invoked as a cost task. Modelled as a `custom_script` cost step | **CUSTOM** |
| Flip cast | New task `cast_card` (Section 13): cast a card from the energy zone (or discard) paying (or ignoring) its cost; the energy card leaves the zone | **CUSTOM** |
| Ingot token as "1 mana any colour" | Ingots are a per-player counter; payment helper may spend them | **CUSTOM** |
| Mana value of an energy card | `Cost` property read via `get_property` | **NATIVE** |

### 7.3 Payment UX

The framework's drag-to-board flow charges nothing for Fate, so payment must be explicit: when a card is
dropped from hand, SYS-ENERGY computes whether a payment exists. If exactly one way to pay exists it is
auto-selected; otherwise a `SelectionWindow` (already used for card selection) lets the player tap specific
energy cards. Cost failure returns the card to hand through the existing `KEY_IS_COST` / `abort_on_cost_failure`
machinery, which is designed for this ("costs are checked before any other task").

---

## 8. Combat

Combat is the largest custom system (SYS-COMBAT). The framework provides the visuals and selection tools
but no combat rules.

### 8.1 Rules as interpreted from the draft

1. **Declare attackers.** The active player picks creatures in strike position and, for each, a target: an
   opposing player or an opposing creature (or, with special cards, a relic or persisting spell).
2. **Declare blockers.** The defending player assigns creatures in guard position to attackers that target them
   or their creatures. Reaction spells and abilities may be used here. Strike-position creatures cannot block.
   **Designer update (second pass):** creatures in the occupied zone *can* intercept (using their Guard); the
   first draft said they could not. See `docs/FATE_RULES_SPEC.md` decision D5.
3. **Resolve damage.** Per attacker, in the attacking player's order. If several creatures block one attacker,
   the attacking player chooses the damage assignment order.
4. Repeat until all declared attackers are resolved.

**Damage algorithm (interpretation, see Section 12 item 4).** Let `A` be the attacker's current Strike and `D` the
defender's relevant stat (Guard if blocking or guarding; Strike if the defender is itself in strike position and was
attacked). Each side is reduced by the other: `A' = max(0, A - D)`, `D' = max(0, D - A)`. The creature whose used
stat reaches zero is destroyed; if both reach zero both are destroyed. The draft example confirms this: Strike 3 vs
Guard 2 leaves the striker at 1 until end of turn and destroys the guard. Reduced values persist until the
reset at upkeep. Separately, any creature whose Strike **and** Guard are both zero is destroyed immediately, in or
out of combat. Unblocked attackers deal `A` damage to the targeted player.

### 8.2 Mapping

| Combat element | Framework piece | Status |
|----------------|-----------------|--------|
| Choosing an attack target by drawing an arrow | `Card.targeting_arrow` (`TargetingArrow`): `initiate_targeting()`, `complete_targeting()`, signals `target_selected`, `potential_target_found`. The arrow only recognises `Card` objects as targets (`area is Card` in `TargetingArrow.gd`) | **EXTEND** |
| Attacking a player | Needs a clickable target. Add a `PlayerAvatar` that extends `Card` (so the arrow detects it), hidden from card queries by a distinct group | **CUSTOM** |
| Attacking relics / persisting spells (Zelith, Battering Ram) | Same arrow with a wider valid-target filter | **EXTEND** |
| Declaring blockers | A second arrow phase for the defending player, reusing the arrow with a `blocker` mode | **EXTEND** |
| Multiple blockers and damage order | Selection UI (`SelectionWindow`) to order blockers | **EXTEND** |
| Position rules (strike attacks, guard blocks) | `card_rotation` read in combat checks | **NATIVE** (data) + **CUSTOM** (checks) |
| Stat reduction until end of turn | SYS-MOD current-value reduction; automatically cleaned in upkeep | **CUSTOM** |
| Destroy to discard | `move_card_to_container` with `dest_container: discard` (the card moves to the *owner's* discard) | **NATIVE** |
| "Deals damage to a player" | `mod_counter` on `life`, alterant-aware | **NATIVE** |
| "Whenever X attacks / is blocked / deals damage / dies" | New signals `creature_attacks`, `creature_blocked`, `damage_dealt` added to `known_card_signals` + SP filters (`filter_is_attacker`, ...). "Dies" already works as `card_moved_to_pile` with `filter_source: board`, `filter_destination: discard` | **EXTEND** |
| Skipped combats (negation, remove from combat) | Combat manager flag per attacker | **CUSTOM** |
| Unblockable, cannot block | Combat check against keyword/ability flags (SYS-KEYWORD) | **CUSTOM** |
| Forced single blocker ("must be blocked by target creature exclusively") | Combat check against a per-attack restriction | **CUSTOM** |

### 8.3 Combat state machine

`CombatManager` (child of the board, group `scriptables`): `IDLE -> DECLARE_ATTACKERS -> DECLARE_BLOCKERS ->
RESPONSE_WINDOW -> RESOLVE -> NEXT_ATTACKER -> END`. At every transition that can be responded to it opens a
SYS-RESPONSE window (Section 13). It owns the list of `AttackRecord`s
(`attacker`, `target`, `blockers[]`, `restrictions`, `negated`).

---

## 9. Keywords and ability patterns

### 9.1 Keywords listed in the draft

The framework has **no keyword concept**: keywords are card text. Each keyword below is implemented as a
SYS-KEYWORD flag/behaviour. Cards list keywords in a meta property `_keywords` (already supported by
`CardConfig.EXPLANATIONS`: matching entries create hover info panels), and temporary keywords granted by
other cards are stored on the card in a `_granted_keywords` dictionary with an expiry.

| Keyword | Draft meaning | Implementation | Framework link | Status |
|---------|---------------|----------------|----------------|--------|
| **Charge** | May attack the turn it is played | Summoning-sickness rule keyed on `_entered_turn`; Charge bypasses it | Property flag read by SYS-COMBAT | **CUSTOM** |
| **Consume** | Move a card to the discard | Cost or effect task | `move_card_to_container` to `discard`, usable with `is_cost: true` and `subject: self/target/boardseek` | **NATIVE** |
| **Embody X** | Pay X; put an energy card beneath the creature; creature gains Strike and Guard equal to that card's mana value; reusing it discards the previous card | Attach the energy card face-down behind the creature; bonus is computed by SYS-MOD from the attachment; the previous attachment is moved to discard first | `attach_to_card`/`host_card`, `ATTACH_BEHIND`, attachments list | **EXTEND** |
| **Evolve** | Discard this card; search the deck for the named card and put it on the field; it has Charge until end of turn | Script: `move_card_to_container` (self -> discard), `tutor` subject by `Name` filter, `move_card_to_board`, grant Charge until EOT | Existing tasks + SYS-MOD | **CONFIG** + SYS-MOD |
| **Flip Cast** | Cast a spell from the energy zone, only when an effect permits | Shared `cast_card` task, with a per-turn permission token granted by the enabling card/doctrine | See Section 13 | **CUSTOM** |
| **Indomitable** | Cannot die from combat damage | Combat check: destruction by combat damage is replaced by "stays at 1 current stat" or simply not destroyed (**DECIDE**); non-combat destruction still works | SYS-KEYWORD | **CUSTOM** |
| **Limiter X** | Limits uses of an ability to X (per turn assumed) | Per-card, per-ability use counter, cleared by SYS-TURN | Could reuse the framework's token drawer (a `used` token) for visibility | **EXTEND** |
| **Savage X** | When this creature is blocked, deal X damage to the blocking creature's controller or another of their creatures | Combat hook after blockers are declared | `mod_counter` on `life`, or `modify_properties` on a creature | **CUSTOM** |
| **Occupy** | As part of an activated ability the card is tilted and moved to the occupied zone; it cannot return to strike or block this turn | Activated-ability cost task `occupy`: `rotate_card` 90 + `move_card_to_board` into the `occupied` grid | `rotate_card`, `move_card_to_board`, `is_cost` | **EXTEND** |
| **Productive** | May occupy the turn it is played | Summoning-sickness rule for occupy keyed on `_entered_turn` | | **CUSTOM** |
| **Reaction** | May activate abilities in response to its field or itself being targeted | Response windows | SYS-RESPONSE | **CUSTOM** |
| **Untethered** | When it dies, remove from game | Death replacement: pre-move hook redirects the destination from `discard` to `removed` | `common_pre_move_scripts` (documented redirect hook) | **EXTEND** |

### 9.2 Terms used on cards but not defined in the draft

| Term | Where used | Proposed meaning / mapping |
|------|------------|---------------------------|
| **Tap** | Acquisition Fabricator, Battle Smith, Factory Crafter, Devote Paladin, Invigorated Workforce | Likely an older name for Occupy. Treated as Occupy (Section 12 item 5) |
| **Convert** | Unseen Manipulator | Take control (SYS-CONTROL) |
| **Intel** | Unseen Manipulator | Mode label: draw two cards |
| **Perpetual spell** | Zelith, Smite, Broadening/World text | Same as persisting spell (field or world) |
| **Evolution X (Name)** | Beetle Brawler | Same as Evolve with a cost; see Section 12 item 6 |
| **Undying**, **Spell sling** | Decklist 2 notes | Themes with no rules text yet |
| **Soldier / Goblin / Automaton / Scrap / Ingot / Battle Hammer / Soul Spear** | Tokens | Section 11.1 |
| **Unique** | Many | Deck-limit rule and subtype word; `_max_allowed: 1` |
| **Energy value** | Dockside Ambusher | Mana value of an energy card = printed `Cost` |
| **Mana card** | Enthralled Civilian | A card in the energy zone |

### 9.3 Ability types

| Draft ability type | Framework mapping | Status |
|--------------------|-------------------|--------|
| **Triggered** ("when X enters / dies / attacks") | A script keyed by a signal name (the trigger), with `filter_*` keys limiting it. Examples: enters = `card_moved_to_board` with `trigger: self`; dies = `card_moved_to_pile` (`filter_source: board`, `filter_destination: discard`); card attached = `card_attached`; modified counter = `counter_modified` | **NATIVE** (existing signals), **EXTEND** (attack/damage/phase signals) |
| **Activated** (cost, then effect; main phase only) | `manual` trigger (double-click) under the `board` state. Costs are tasks with `is_cost: true`, evaluated first and aborting everything on failure. Main-phase restriction is added as a filter in SYS-TURN | **NATIVE** + **EXTEND** (gate) |
| **Static** ("creatures you control gain +1") | No equivalent: alterants only change cost/token/spawn values. Needs the SYS-MOD continuous-effect layer | **CUSTOM** |
| **Modal** ("choose 1") | A script whose state value is a dictionary of titled task lists; the framework shows `CardChoices` | **NATIVE** |
| **Optional** ("you may") | The optional key (`KEY_IS_OPTIONAL`, written `is_optional_<state>`, e.g. `is_optional_board: true`, at script level; see `ScriptProperties.gd`) shows the framework's confirmation dialog before the script or task runs | **NATIVE** |
| **Targeted** | `subject: target` starts the targeting arrow; `filter_properties`/`filter_cardfilters` restrict legal targets | **NATIVE** (cards), **EXTEND** (players, controller filters) |
| **Search** ("search your deck for ...") | `subject: tutor` with `src_container: deck` and filters, then `shuffle_container` | **NATIVE** |
| **Look at the top N** | `subject: index` with `needs_selection` / `selection_count`, then move chosen cards | **NATIVE** |
| **Counting** ("equal to the number of cards named X") | `per_boardseek` with `filter_card_name`, `per_property`, `per_token`, `per_counter` | **NATIVE** |
| **Repeat / for each** | `repeat`, `nested_tasks` | **NATIVE** |

### 9.4 Effect verbs: draft wording to framework task

| Draft wording | Task / approach |
|---------------|-----------------|
| Draw a card | `move_card_to_container` `src_container: deck`, `subject: index`, `subject_index: top`, `dest_container: hand` |
| Discard / consume / destroy / sacrifice | `move_card_to_container` to `discard` (owner's), with `is_cost` when it is a cost |
| Put on the bottom of the deck | `move_card_to_container` with `dest_index: bottom` |
| Remove from the game | `move_card_to_container` to `removed` |
| Create a token | `spawn_card` (card token) or `mod_counter` (scrap/ingot) |
| Search for a card and put it in hand / on the field | `tutor` + `move_card_to_container` / `move_card_to_board`, then `shuffle_container` |
| Look at the top two, keep one | `index` subject with selection |
| Attach / equip | `attach_to_card`, `host_card` |
| Switch position | `rotate_card` |
| Unoccupy | `occupy` helper in reverse, or `rotate_card` 0 + `move_card_to_board` back to the creature grid |
| Take control of | SYS-CONTROL |
| Place into energy zone | `move_card_to_board` into the owner's `energy` grid and `flip_card` face-down |
| Deal N damage | `deal_damage` (new task over `mod_counter`/`modify_properties`) |
| Gain +N until end of turn | `grant_modifier` (SYS-MOD) |
| Cannot be blocked, cannot be targeted | SYS-KEYWORD flag; target legality via `SP` filter and arrow validation |
| Negate / remove from combat | SYS-COMBAT |
| Copy a token | `spawn_card` with the token's name |
| Return creature from discard to the field | `move_card_to_board` with `src_container: discard` and a `Tags` change via `modify_properties` for added subtype |

---

## 10. Doctrines

Doctrines are the draft's milestone passives. Each player brings a selection, shown to the opponent before the
game, bought with a **faith point** budget (higher tiers and "radicalized" branch changes cost more). Once a
doctrine's goal is met its reward persists unless an effect removes it.

### 10.1 Mapping

| Draft element | Mapping | Status |
|---------------|---------|--------|
| A doctrine as an object | New card `Type = "Doctrine"` (scene `Doctrine.tscn`), kept in the `doctrines` grid, with properties `Branch`, `Tier`, `FaithCost`, `_goal`, `_reward`. Not in the 60-card deck | **CUSTOM** |
| Passive reward | A normal card script under the `board` state, using triggers/alterants. The reward only runs while the doctrine is `_achieved`, enforced with a `filter_properties` check on the doctrine card | **EXTEND** |
| Goal evaluation | `DoctrineManager` re-evaluates after every `card_moved_*`, `card_attached`, `counter_modified` and `phase_begins` signal | **CUSTOM** |
| **Devotion N** (X pips of a domain across your permanents) | Sum of `_pips` of that domain over the player's face-up permanents. `per_boardseek` counting with `count_unique` off cannot sum a string property, so add a devotion helper to SYS-DOCTRINE | **CUSTOM** |
| **Count** (hand size, creatures, relics, tokens, energy, controlled enemy cards) | `per_boardseek` / `per_token` / `per_counter` with filters, compared against a threshold | **NATIVE** (counting) + **CUSTOM** (threshold check) |
| **Sacrifice** | Count of "consume/sacrifice" events via a per-player counter incremented from a trigger | **EXTEND** |
| **Discard** (X cards of a type in discard) | `per_boardseek`-style count over the discard pile (`src_container: discard`) with `filter_cardfilters` | **NATIVE** |
| Faith point deck-building and tiers | Extension of the deck builder UI | **CUSTOM** (SYS-DECK) |
| Reveal doctrines before play | Pre-game setup screen/phase | **CUSTOM** |
| Cards that interact with doctrines (shortcut, suppress, amplify) | Doctrine cards expose `_suppressed` and `_amplify` flags that effect scripts can modify with `modify_properties`-style tasks | **DECIDE** |

### 10.2 Doctrine catalog

| ID | Doctrine | Goal | Reward | Reward implementation | Status |
|----|----------|------|--------|-----------------------|--------|
| C1 | Subtle Influence | Count control 2 (2 opponent cards in your energy zone or field) | Once per turn, flip cast a card by paying its cost | Grants a flip-cast permission token each turn (`cast_card`) | CUSTOM |
| C2 | Ensue Chaos | Devotion 5 Chaos | Instead of playing a card from hand for turn, take the top card of an opponent's deck into your energy zone | Alters the upkeep energy-play option (SYS-TURN/SYS-ENERGY) | CUSTOM |
| C3 | Convert the Masses | Count control 6 | At the beginning of each turn, take the weakest creature on a target player's field | Phase trigger + SYS-CONTROL, "weakest" = lowest Strike+Guard | CUSTOM |
| O1 | Maintain Your Presence | Count Creature 4 | Create a 1/1 soldier at the beginning of your turn | Phase trigger + `spawn_card` | CONFIG |
| O2 | Defend the Innocent | Devotion 5 Order | While conditions are met, creatures gain +1 Strike and +1 Guard | Static effect, SYS-MOD | CUSTOM |
| O3 | Vanquish Thine Foes | Count Creature 10 | When your creatures attack, any creature that interacts with them is destroyed | Combat hook | CUSTOM |
| P1 | Be a Fierce Presence | Power 4 (a creature with Strike or Guard >= 4) | Your highest-Strike creature may guard from strike position as well as attack | Combat rule override | CUSTOM |
| P2 | Devote Yourself to the Wilds | Devotion 5 Primal | Creatures can attack the turn they are played | Grants Charge globally | CUSTOM |
| P3 | Channel the Spirit's Will | Ghost Count 4 (4 Ghosts and/or embodying creatures) | A creature that would die from combat damage stays and its controller takes 3 damage instead | Combat replacement effect | CUSTOM |
| I1 | Construct the Future | Count Relic 3 | Create a scrap token at the beginning of your upkeep | Phase trigger + `mod_counter` scrap | CONFIG |
| I2 | Devote Yourself to Progress | Devotion 5 Innovation | Creatures can occupy the turn they are played | Grants Productive globally | CUSTOM |
| I3 | Produce Endlessly | Token Count 6 | Whenever you create a token, create an additional one of that kind | **Alterant** on `spawn_card` / scrap `mod_counter` (the framework's alterant engine does exactly this) | EXTEND |

The draft heading says "Innervation"; the domain is Innovation (Section 12).

---

## 11. Tokens, deck building and spell rules

### 11.1 Tokens

The draft uses two different things called tokens, which the framework distinguishes:

| Fate token | Behaviour | Recommended representation | Status |
|------------|-----------|----------------------------|--------|
| **Scrap, Ingot** | Fungible resources created and consumed in bulk; "consume a scrap", "Token Count 6", "copy target token", ingot pays 1 mana | **Per-player counters** (`scrap`, `ingot`) in `CGFCounters.needed_counters`. `mod_counter` creates/consumes them, `per_counter` counts them, alterants double them (Produce Endlessly). Counters already appear as a HUD readout | **NATIVE** |
| **Soldier 1/1, Goblin 1/1, Iron Automaton 3/3** | Creature tokens | Token-type cards (`Type = "Token"`) with `Strike`/`Guard`, created with `spawn_card` into a creature grid, optionally in guard position | **CONFIG** |
| **Battle Hammer, Soul Spear** | Relic tokens, equipped on creation or consumed | Token-type relic cards; `spawn_card` then `attach_to_card`/`host_card` | **CONFIG** |
| "Count a token" for doctrines and "copy target token" | Counts both counters and Token-type cards | Count helper in SYS-DOCTRINE; Fabrication Line needs a "copy" mode for counters | **EXTEND** |

Framework "tokens" (`mod_tokens`, `TOKENS_MAP`, token drawer) are counters shown *on* a card. They are not used for
Fate's tokens; they remain available for markers such as a `used` marker for Limiter, or `+1/+1` markers.
Alternative considered: making scrap and ingot real cards. It is rejected because it needs a stacking UI and
adds nothing the counters do not already provide (DECIDE if physical tokens are wanted for presentation).

### 11.2 Deck building

| Draft rule | Mapping | Status |
|------------|---------|--------|
| 40 card deck | Deck validation on save/start (`FateDecks.problems`) | **CUSTOM** (SYS-DECK) |
| Up to 3 copies | `_max_allowed: 3` on every non-unique card (`MAX_COPIES` in `tools/gen_fate_cards.py`) | **NATIVE** |
| One copy of each legendary card (unique cards, which include every God) | `_max_allowed: 1` | **NATIVE** |
| Domain filters, text search | Card library and filter lines | **NATIVE** |
| Dual-domain cards | `Domain` array | **CONFIG** |
| Doctrine selection with faith budget | Extra pane in the deck builder | **CUSTOM** |
| Saved deck files | `DECKS_PATH` | **NATIVE** |

### 11.3 Spells

| Rule | Mapping | Status |
|------|---------|--------|
| Regular spell, own turn, Main 1 or 2 | Gate in the cast helper using the current phase | **EXTEND** |
| Reaction spell, any time in response | SYS-RESPONSE window | **CUSTOM** |
| Reaction spells never counter spells | Content rule: no card may target a spell on a stack. No stack is required (see SYS-RESPONSE) | **DESIGN** |
| Field spell: one per player's field; new one replaces the old (old to discard) | `common_pre_move_scripts` on a field spell finds the occupant of `field_spell`, moves it to discard, then allows the move | **EXTEND** |
| World spell: one in play, shared | Same, on the shared `world_spell` grid | **EXTEND** |
| Persisting spell with a duration | Counter or token on the spell, decremented by a phase trigger | **CONFIG** |
| Spell resolves then goes to discard | End of the cast helper | **EXTEND** |

---

## 12. Open questions and draft inconsistencies

Each item lists the interpretation this document assumes. Please confirm or correct before the affected
system is built.

| # | Topic | What the draft says | Assumed here | Affects |
|---|-------|---------------------|--------------|---------|
| 1 | `#` marks in names (`Steelwork Salvager 2#`, `Factory Refinery ###`) | Never defined. Cost line says "1-2 mana of a specific concept, the rest any" | Number = generic mana, each `#` = one pip of the card's domain. Spells show only a number (no pips) | SYS-ENERGY, devotion, catalog |
| 2 | Domain names | Divine/Order, Abyssal/Chaos, Innovation/Innervation, "Dominarus"/"Domarus" appear | Canonical names: **Order, Chaos, Primal, Innovation**; flavour names Divine and Abyssal are display text | Data, UI |
| 3 | Win condition, life, opening hand, mulligan, first player, empty deck | Absent | Defaults in Section 4.3 | SYS-TURN, SYS-PLAYER |
| 4 | Combat damage details | Higher stat wins; both lose the other's value; both stats at zero kills | Algorithm in Section 8.1. Open: ties (both die?), a defender in strike position, whether direct damage to a player equals the full Strike, which player's turn "resets" damaged stats ("start of a new turn") | SYS-COMBAT, SYS-MOD |
| 5 | "Tap" vs "Occupy" | "Tap" is used on 5 cards, never defined. Occupy is defined | Tap = Occupy | Catalog, SYS-SLOT |
| 6 | "Evolve" vs "Evolution 2 (Ironside Beetle)" | Evolve has no cost. Beetle Brawler prints a number | Evolution X pays X, then performs Evolve | Beetle Brawler |
| 7 | Summoning sickness | Charge ("can attack the turn they are played"), Productive ("can occupy the turn they are played"), Invigorated Workforce and two doctrines imply creatures cannot attack or occupy the turn they enter, but no rule states it | A general entry-turn restriction exists | SYS-COMBAT, SYS-KEYWORD |
| 8 | Missing or odd data | Goblin Ledgerkeeper has no Strike/Guard; Specter of Hate is 2/0 yet "cannot block even in guard position"; "Sharman" for Shaman; "Zenith" in Zelith's text; Unseen Reach has no cost; War of Attrition text is incomplete ("switch of your creatures") | Ledgerkeeper 0/1 placeholder; Specter keeps Guard 0; Unseen Reach cost 2; War of Attrition affects all your creatures; fix spellings | Data |
| 9 | Spell costs | Reaction and regular spells list a bare number | Generic mana only | Data |
| 10 | "Iron ingot" vs "ingot" | Both used | One resource: **ingot**. "Battle hammer" and "iron automaton" tokens are made from ingots | Innovation cards |
| 11 | "Until end of turn" with damage persistence | Damage lowers stats until the *start of a new turn* | Reset all current stats and positions at the active player's upkeep, "until end of turn" modifiers expire in the End step | SYS-MOD |
| 12 | "creature you do not own" (Ikthar, Double Agent) | "own" vs "control" | Means *control* for effects; ownership matters only for where a card returns | SYS-PLAYER |
| 13 | Indomitable | "Cannot die from combat damage" | Combat damage that would destroy it is ignored; stat is clamped to 1 | SYS-COMBAT |
| 14 | Response timing | "Reaction spells can be cast at any time in response to an event or effect" but there is no stack and no counterspells | Response windows at fixed points (attack declaration, blocker declaration, being targeted, spell cast, ability activation); no stack: a reaction resolves immediately and may not negate spells or abilities | SYS-RESPONSE |
| 15 | Trigger ordering | Simultaneous triggers (several creatures dying, Krelga's replacement) | Active player's triggers first, then the other player | SYS-TURN |
| 16 | Doctrine counts and costs | "X faith points", number of doctrines per player, tier costs, "radicalize" cost, tiers beyond 3 | Three tiers per branch; tier N costs N faith; starting a second branch costs +1; budget 6. All tunable data | SYS-DOCTRINE, SYS-DECK |
| 17 | Equip rules | "Cannot be changed once equipped", discard with creature, still targetable. Holy Amulet equips "of your choice" | Equip happens on entry, target chosen as an enter-the-board trigger. If the creature leaves, equipped relics go to the discard | Relic cards |
| 18 | "Energy value" / "mana value" | Used by Embody, Dockside Ambusher, Meek Minion, Harbinger | The card's printed generic `Cost` plus pips | SYS-ENERGY |
| 19 | Number of players | "Multiplayer (optimal for 2)" | Build for exactly two; keep `PlayerContext` indexable | SYS-PLAYER |
| 20 | Draw/discard order words ("Delve into the Beyond: put a card to the bottom, draw two") | Order matters (draw first or second) | As written: bottom first, then draw | Spell data |
| 21 | Domain of the 14 "additional card ideas" | The draft lists them without a domain | Assigned by theme (see `tools/gen_fate_cards.py`, `ADDITIONAL_DOMAIN`; flagged `_domain_assumed` in the data). Brogir and Rarink: Innovation. Self-destruction, Broadening Influence, Specter of Hate, Unseen Reach: Chaos. Sigil Mage, Holy Healer, Insightful Investigator, Wave of Fear: Order. Toll of War, No Where to Hide, Battering Ram, Goblin Scout Leader: Primal | Card data, decks |

---

## 13. Custom systems specification

Each system is a script plus, where noted, a scene. All live under `src/custom/fate/` (new folder) so core
framework files stay untouched, except for the extension points the framework itself documents
(overridable `PATH_*` constants in `CFConst.gd`, `SP.gd`, `CardConfig.gd`, `CustomScripts.gd`, the `common_*`
and `check_play_costs` card hooks, and the `known_card_signals` list).

### SYS-TURN - TurnManager
- **Role:** players' turn order, phases (setup, upkeep, main 1, combat, main 2, end), per-turn flags.
- **Framework hooks:** emits triggers through `cfc.signal_propagator`; added to group `scriptables`; uses `cfc.game_paused` during modal choices.
- **API:** `begin_turn()`, `advance_phase()`, `signal phase_begins(player, phase)`, `can_act(player)`, `flags[player]` (`energy_played`, `spells_cast`, `ability_uses`).
- **Depends on:** SYS-PLAYER.

### SYS-PLAYER - PlayerContext, ownership, control
- **Role:** the two players, their container names, life, doctrine list; `owner_id`/`controller_id` on cards.
- **Framework hooks:** `SP` filters `filter_controller`, `filter_owner`; container names resolved per player so existing tasks work.
- **API:** `get_player(id)`, `container(player, "deck")`, `opponent_of(id)`, `signal control_changed(card, old, new)`.
- **Used by:** every other system.

### SYS-ENERGY - EnergyManager
- **Role:** energy grids, mana domains, cost parsing (`Cost` + `_pips`), payment, once-per-turn energy play, Manifest/Ponder choice, cast helper.
- **Framework hooks:** `check_play_costs`, `pay_play_costs`, `common_pre_move_scripts` (energy-play gate), alterants (`PlayCost` tag), `CGFCounters` (domain readouts), `SelectionWindow` (choose which energy to tap).
- **API:** `can_pay(card, player) -> bool`, `pay(card, player)`, `play_energy(card, player, domain)`, `add_temp_mana(player, domain, n)`, `cast_card(card, source, pay_cost)`.
- **New scripting task:** `cast_card` (flip cast, cast from discard, "cast one of your mana cards").

### SYS-COMBAT - CombatManager
- **Role:** attack and block declaration, damage resolution, combat triggers, restrictions (unblockable, forced single blocker, negation).
- **Framework hooks:** `TargetingArrow`, `rotate_card`, `move_card_to_container`, `mod_counter`, `SelectionWindow`.
- **API:** `declare_attack(attacker, target)`, `declare_block(blocker, attacker)`, `resolve()`, `signal creature_attacks`, `signal creature_blocked`, `signal damage_dealt`.
- **New scripting tasks:** `deal_damage`, `negate_attack`, `remove_from_combat`, `destroy_creature`.
- **Depends on:** SYS-TURN, SYS-MOD, SYS-KEYWORD, SYS-RESPONSE, SYS-PLAYER (+ a `PlayerAvatar` target that extends `Card`).

### SYS-RESPONSE - ResponseWindow
- **Role:** opens a bounded window at fixed events so the non-active player can cast reaction spells or use reaction abilities. No stack.
- **Framework hooks:** `OptionalConfirmation` / `SelectionWindow` for "respond?", `cfc.game_paused`.
- **API:** `open(event_name, context) -> await`, `signal responded`.
- **Rules:** reactions resolve immediately; cannot negate a spell or ability (draft rule).

### SYS-MOD - StatModifier layer
- **Role:** effective Strike/Guard = base + permanent modifiers + temporary ("until end of turn") modifiers + static effects + embody bonus - combat damage; keyword grants with expiry.
- **Framework hooks:** card `properties` (current value), `modify_properties` (task), `get_property`, `card_properties_modified` signal, `cfc.card_definitions` (base).
- **API:** `grant_modifier(card, stat, amount, expires)`, `grant_keyword(card, kw, expires)`, `effective(card, stat)`, `reset_turn()`.
- **New scripting task:** `grant_modifier`.

### SYS-KEYWORD - keyword registry
- **Role:** source of truth for keyword names, display text (`CardConfig.EXPLANATIONS`), and runtime flags (Charge, Indomitable, Savage X, Untethered, Productive, Limiter, Reaction, unblockable, cannot-block).
- **API:** `has(card, kw) -> bool`, `value(card, kw) -> int`, `grant`/`revoke`.

### SYS-SLOT - zones and placement rules
- **Role:** creature, occupied, relic, field-spell, world-spell, doctrine grids and their rules (one-slot replacement, occupy move, entry-turn tracking).
- **Framework hooks:** `BoardPlacementGrid`, `add_grid`, `move_card_to_board`, `common_pre_move_scripts`, `common_post_move_scripts`.
- **New scripting tasks:** `occupy`, `unoccupy`.

### SYS-CONTROL - control change
- **Role:** change `controller_id`, move the permanent to the new controller's grid, handle "until end of turn" control, return on leave.
- **New scripting task:** `take_control`.

### SYS-TOKEN - tokens and counters
- **Role:** scrap/ingot counters, token creation including alterants, token copy, token counting for doctrines.
- **Framework hooks:** `Counters`, `mod_counter`, `spawn_card`, `AlterantEngine`.

### SYS-FILTER - SP extension
- **Role:** extra `filter_*` keys used by Fate scripts, defined in `src/custom/SP.gd`: `filter_controller`, `filter_owner`, `filter_phase`, `filter_player`, `filter_is_attacker`, `filter_is_blocked`, `filter_domain`, `filter_keyword`, `filter_creature_type`, `filter_mana_value`.

### SYS-DOCTRINE - DoctrineManager
- **Role:** doctrine cards, goal evaluation (devotion, count, sacrifice, discard), reward activation, reveal step.
- **Framework hooks:** card scripts on the doctrine card, signals listed in Section 10, `per_*` counting.

### SYS-DECK - deck rules
- **Role:** 40-card decks, copy limits (already native), doctrine selection with a faith budget, saved-deck format extension.
- **Framework hooks:** `DeckBuilder`, `CardViewer`, `DBListCardObject._max_allowed`, `DeckLoader`.

---

## 14. Card-by-card implementation catalog

Covers every card in *Fate TCG.md*: Decklist 1 (Innovation, Chaos, Order, Primal), the "Additional card ideas"
list, and the Decklist 2 theme notes.

**Baseline systems (required by every card, not repeated per row):** SYS-PLAYER (container naming, owner/controller),
SYS-TURN (phase gating of regular spells and activated abilities) and SYS-ENERGY (cost payment). The
"Mapping" column lists only what is *specific* to the card.

**Classes:**
- **A**: card definition plus script tasks that exist today.
- **B**: also needs the generic custom systems named in the row (no card-specific code).
- **C**: needs a card-specific new task, rule exception, or new UI.

Abbreviations: `mcc` = `move_card_to_container`, `mctb` = `move_card_to_board`, `occ` = Occupy (including "Tap"), `EOT` = end of turn.
Stats are Strike/Guard. Stats shown as `?` are missing in the draft.

### 14.1 Innovation

| Card | Cost | Type / subtypes | S/G | Draft effect | Mapping | Class |
|------|------|-----------------|-----|--------------|---------|-------|
| Rustmarket Tinkerer | 1## | Creature, Goblin Engineer | 1/3 | Occupy: cast 1 relic from your discard by paying its cost | `occ` cost; `cast_card` from discard with relic filter; SYS-SLOT, SYS-ENERGY | B |
| Steelwork Salvager | 2## | Creature, Goblin Engineer | 2/1 | When it attacks, create a scrap token | `creature_attacks` trigger; `mod_counter` scrap; SYS-COMBAT, SYS-TOKEN | B |
| Goblin Ledgerkeeper | # | Creature, Goblin Shopkeeper | ? | Occupy: create a scrap token | `occ`; `mod_counter` scrap; stats missing in draft | B |
| Skulking Goblin | 1# | Creature, Goblin Thief | 2/1 | When it attacks you may draw a card then discard a card | Attack trigger, optional key (`is_optional_board`), draw `mcc`, discard `mcc` with `needs_selection`; SYS-COMBAT | B |
| Acquisition Fabricator | 2# | Creature, Dwarf Engineer | 2/3 | Tap, consume a scrap: create an ingot token (consume for 1 mana of any colour) | `occ`; cost `mod_counter` scrap -1; `mod_counter` ingot +1; ingot payable as mana in SYS-ENERGY | B |
| Battle Smith | 1## | Creature, Dwarf Brawler | 3/3 | Tap, consume an ingot: create a Battle Hammer token attached to a creature you control (+2 Strike) | `occ`; cost ingot; `spawn_card` Battle Hammer; `attach_to_card`; SYS-MOD (+2 Strike) | B |
| Factory Crafter | 1## | Creature, Dwarf Engineer | 2/4 | Tap, consume an ingot: create a 3/3 iron automaton token in guard position | `occ`; cost ingot; `spawn_card` Automaton then `rotate_card` 90 | B |
| Thrang, Perpetual Innovation | 5## | Unique Creature, Construct God | 6/6 | Consume a scrap: unoccupy target permanent you control. Cannot be targeted by spells | Cost scrap; `unoccupy`; untargetable-by-spells flag; SYS-SLOT, SYS-KEYWORD, SYS-FILTER | B |
| Scrap Cannon | 2# | Relic | - | Consume a scrap: 1 damage to any target (to a creature, reduces the stat for its current position) | Cost scrap; `deal_damage`; SYS-COMBAT, SYS-MOD; arrow targets players too | B |
| Factory Refinery | ### | Relic | - | Pay 1, consume a scrap: create an ingot token | Cost: pay 1 mana + scrap; `mod_counter` ingot | B |
| Garbage Heap | 1# | Relic | - | Consume this relic: create 2 scrap tokens | `mcc` self -> discard (cost); `mod_counter` scrap +2 | A |
| Scrap Recycler | 1# | Relic | - | Once per turn you may consume a relic. If you do, draw a card | Limiter once per turn; cost `mcc` relic; draw | B |
| Thrang's Crafting Table | 3## | Unique Relic | - | Consume 1 ingot: create Battle Hammer token, attach to a creature. Consume 2: create 3/3 guard automaton. Consume 3: search for Thrang into hand | Modal script (3 titled options); ingot costs; `spawn_card`+`attach_to_card`; `tutor`; SYS-TOKEN | B |
| Rapid Scavenging | 2 | Spell (regular) | - | Create 2 scrap tokens | `mod_counter` scrap +2 | A |
| Fabrication Line | 3 | Spell (regular) | - | Create 2 copies of target token you control | Copy mode for counters and token cards (`spawn_card` x2) | C |
| Factory Shutdown | 2 | Spell (reaction) | - | All attacks against you and your field are negated | SYS-RESPONSE at attack declaration; `negate_attack` for all attackers | B |
| Safety Measure | 2 | Spell (reaction) | - | Destroy target attacking creature | Response window; target filter `filter_is_attacker`; `mcc` -> discard | B |
| Invigorated Workforce | 3 | Unique Spell (field) | - | Creatures with tap abilities can tap as soon as they enter your field | Field slot; grants Productive to the controller's creatures (SYS-KEYWORD); SYS-SLOT | B |

### 14.2 Chaos

| Card | Cost | Type / subtypes | S/G | Draft effect | Mapping | Class |
|------|------|-----------------|-----|--------------|---------|-------|
| Harbinger of Krelgar | 1## | Creature, Civilian Abomination | 1/1 | When it dies, take control of target creature with mana value 2 or less | `card_moved_to_pile` trigger (board -> discard); `take_control`; `filter_mana_value`; SYS-CONTROL | B |
| Enthralled Civilian | # | Creature, Civilian Cultist | 1/1 | Main phase: consume it to cast one of your mana cards (it stops being mana) | Cost `mcc` self; `cast_card` from energy zone, paying cost; SYS-ENERGY | B |
| Unseen Manipulator | 2## | Creature, Abomination | 3/2 | Enters: choose 1: Convert (take control of target non-unique creature an opponent controls) / Intel (draw two) | Modal enters-trigger; `take_control`; draw `mcc`; SYS-CONTROL | B |
| Dockside Ambusher | 3# | Creature, Abomination | 3/3 | When you flip cast it from your energy zone, target opponent chooses a non-token permanent of mana value 4 or less to give you, placed in your energy zone | Flip-cast signal; opponent-side `SelectionWindow` decision; `take_control` into energy zone; SYS-PLAYER decision routing | C |
| Cultist Fanatic | 2# | Creature, Civilian Cultist | 3/1 | When it deals damage to a player or creature, you may sacrifice it to flip cast a card from your energy zone without paying | `damage_dealt` trigger; optional; cost `mcc` self; `cast_card` with `pay_cost: false` | B |
| Unending Echo | 1# | Creature, Ghost | 2/1 | Can be cast from your discard by paying its cost | `pile`-state castability flag; `cast_card` from discard | B |
| Ikthar, The Great Summoner | 2## | Unique Creature, Human Abomination | 3/3 | Occupy, consume a creature you do not control: search your deck for a unique creature, reveal, put in hand, shuffle | `occ`; cost with an *opposing* creature subject; `tutor` with `filter_properties` unique; `shuffle_container`. Wording ("do not own") resolved in Section 12 item 12 | B |
| Krelga, Abyssal Nightmare | 5## | Unique Creature, Abomination God | 6/6 | Creatures destroyed by Krelga return under your control. When Krelga is destroyed, place it in your energy zone | Post-combat-destruction trigger + `take_control`; Krelga's own death redirected to the energy zone by `common_pre_move_scripts` | B |
| Dockside Alter | 1## | Relic | - | Once during your turn, consume a creature; when you do you may flip cast from your energy zone | Limiter once per turn; cost `mcc` creature; optional `cast_card` | B |
| Murkmist Gemstone | 1# | Relic | - | Enters attached to a creature. When that creature dies, take control of the creature that destroyed it, if any | `attach_to_card` on entry; death trigger carries killer reference from SYS-COMBAT; `take_control` | B |
| Delve into the Beyond | 3 | Spell (regular) | - | Put a card from your hand on the bottom of your deck. Draw two | `mcc` hand -> deck bottom (`needs_selection`); draw x2 | A |
| Deep Thought | 2 | Spell (regular) | - | Look at the top two cards of your deck, put one in your hand and the other on the bottom | `index` subject x2 with selection; `mcc` to hand and to deck bottom | A |
| Unforgotten Sacrifice | 4 | Spell (regular) | - | Flip play a card from your energy zone without paying. Then place the top card of your deck face-down in your energy zone | `cast_card` free; `mcc` deck top -> `mctb` energy grid face-down | B |
| Claimed by the Abyss | 4 | Spell | - | Take target creature on any field and place it face-down in your energy zone | `mctb` into the caster's energy grid, `flip_card` face-down; SYS-CONTROL (card changes owner of position, keeps owner id) | B |
| Repurpose | 2 | Spell (regular) | - | Move target card in a player's discard into your energy zone | `mctb` from any discard to energy grid, face-down | B |
| Double Agent | 2 | Spell (reaction) | - | When a player declares attacks, take control of another creature you do not control until EOT. It enters in guard position | Response window at attack declaration; temporary `take_control` with expiry; `rotate_card` 90 | C |
| Eldritch Knowledge | 2 | Spell (field) | - | Whenever you flip cast, draw a card | Field slot; trigger on the `flip_cast` signal; draw | B |

### 14.3 Order

| Card | Cost | Type / subtypes | S/G | Draft effect | Mapping | Class |
|------|------|-----------------|-----|--------------|---------|-------|
| Zelith, Mage Justiciar | 2## | Unique Creature, Human Mage | 3/4 | May attack perpetual spells as if creatures; spells hit are destroyed | Widened attack target set in SYS-COMBAT; destroy `mcc` | C |
| Moral Captain | 1## | Creature, Human Soldier | 2/2 | When you attack, two target creatures gain +1 Strike until EOT | Attack trigger; two targets; `grant_modifier` (SYS-MOD) | B |
| Righteous Guard | 1# | Creature, Human Soldier | 1/1 | Enters: create 1/1 soldiers equal to the number of cards named Righteous Guard on your field | Enters-trigger; `per_boardseek` with `filter_card_name` + `filter_controller`; `spawn_card` count | B |
| Tactical Combatant | 2# | Creature, Human Soldier | 3/3 | After it attacks, switch it to guard position | Attack-resolved trigger; `rotate_card` 90 | B |
| Devote Paladin | 2## | Creature, Human Soldier | 4/3 | Tap, consume an energy card: your creatures gain +1 Strike and Savage (1) | `occ`; cost `mcc` energy card; `grant_modifier` + keyword grant on all friendly creatures | B |
| Streetside Recruiter | ## | Creature, Human Soldier | 1/2 | Occupy: create a 1/1 human soldier | `occ`; `spawn_card` | B |
| Faithful Worshiper | 1# | Creature, Human Cleric | 1/1 | Consume a card in your energy zone: your creatures gain Indomitable until EOT | Cost `mcc` energy card; keyword grant with EOT expiry | B |
| Lucran, Divine Saviour | 5## | Unique Creature, Angel God | 6/6 | When a creature you control dies choose 1: place the card in your energy zone (not tokens); or remove it from the game and create a Soul Spear relic (consume: 2 damage to any target) | Death trigger with modal choice; `mctb` energy / `mcc` removed; `spawn_card` Soul Spear; `deal_damage` | B |
| Holy Amulet | 1# | Relic | - | Equips to a creature of your choice. Creature gains Occupy: add one Order energy | Enters-trigger target + `attach_to_card`; granted activated ability producing temporary mana (`add_temp_mana`) | C |
| Spiked Barricade | 1# | Relic | - | Can be used to guard an attacking creature; when it does, destroy that creature and discard the barricade | Relic as legal blocker in SYS-COMBAT; destroy + discard `mcc` | C |
| Reinforcements | 3 | Spell | - | Create 2 soldier tokens (1/1) | `spawn_card` x2 | A |
| Smite | 2 | Spell | - | Destroy target non-unique creature, or destroy target perpetual spell | Modal; `filter_properties` non-unique; `mcc` -> discard | A |
| Battle Ready | 3 | Spell | - | Switch up to 3 target creatures to strike position; +1 Strike until EOT | `rotate_card` 0 with `up_to` 3; `grant_modifier` | B |
| Hold the Line | 2 | Spell (reaction) | - | Cast when your field is attacked: switch any number of your creatures to guard; +1 Guard until EOT | Response window; `rotate_card` 90; `grant_modifier` | B |
| Equal Footing | 4 | Spell (world) | - | At end of each player's turn, if they do not have the most energy, they may move a card from their discard to their energy zone | World slot; End-step trigger; `per_boardseek` energy comparison; optional `mctb` | B |
| Recovering Resources | 3 | Spell (field) | - | Once during end of each turn, if a creature you own died, you may draw a card | Field slot; Limiter; "died this turn" flag in SYS-TURN; draw | B |
| War of Attrition | 3 | Spell (field) | - | At the beginning of your turn, switch of your creatures to occupied (guard but cannot defend) | Phase trigger; `occupy` on a selection of creatures (draft text incomplete, Section 12) | B |

### 14.4 Primal

| Card | Cost | Type / subtypes | S/G | Draft effect | Mapping | Class |
|------|------|-----------------|-----|--------------|---------|-------|
| Beetle Brawler | 1# | Creature, Insect Brawler | 2/2 | Pay 2: when it attacks this turn it must be blocked exclusively by target creature. Evolution 2 (Ironside Beetle) | Pay helper; combat restriction record; Evolve script (self -> discard, `tutor` by name, `mctb`, grant Charge) | B |
| Ironside Beetle | 2## | Creature, Insect Brawler | 4/3 | Same forced-block ability; Savage 1 | As above; Savage keyword | B |
| Meek Minion | # | Creature, Goblin | 1/1 | Consume: reduce the cost of the next creature you play by 2 | Cost self `mcc`; one-shot alterant on `PlayCost` with expiry | B |
| Feracious Beast | 3# | Creature, Beast | 4/3 | Savage 2 | Keyword only | B |
| Spirit Wielder | 1## | Creature, Elf Shaman | 1/1 | Pay 3: Embody (move an energy card beneath it; gains Strike and Guard equal to its mana value; one at a time, replaced card to discard) | Embody: `attach_to_card` face-down; SYS-MOD bonus; replaced card `mcc` discard | B |
| Elder Spirit | 2# | Creature, Elf Shaman | 2/2 | Occupy: put the top card of your deck into your energy zone | `occ`; `mcc` deck top -> energy grid face-down | B |
| Wraithful Treespirits | 3## | Creature, Ghost Treefolk | 4/4 | Untethered | Death redirect to `removed` | B |
| Teshra, Primal Mother | 5## | Unique Creature, Elf God | 6/6 | Indomitable. Pay 3: flip a creature from your energy zone; it may attack this turn; at EOT return it to the energy zone | Temporary creature that is both an energy card and an attacker: move out, restore at End step; skipped if destroyed | C |
| Teshra's War Gauntlets | 3# | Unique Relic | - | Enters equipped to a creature of your choice; it gains Savage 1 and Indomitable when attacking | Enters-trigger target + attach; conditional keyword grant while attacking | B |
| Dragon's Tooth | 1# | Relic | - | Enters attached to a creature of your choice; it gains Savage 1 | Enters-trigger target + attach; Savage grant while attached | B |
| Ancient Tree | 1## | Relic | - | Occupy: produce 1 Primal energy | `occ`; `add_temp_mana(primal)` | B |
| Primal Wraith | 3 | Spell | - | Creatures you control gain Savage 1 until EOT | `grant_keyword` with EOT expiry | B |
| Cycle of Life | 3 | Spell (field) | - | Once during your turn, if a card is placed in your discard, move it to your energy zone | Field slot; Limiter; `card_moved_to_pile` trigger (destination discard); `mctb` energy | B |
| Return to Nature | 1 | Spell | - | Target relic or spell is placed in its owner's energy zone | `mctb` to owner's energy grid, face-down | B |
| Second Calling | 3 | Spell | - | Return target creature from your discard to the field; it is also a Ghost | `mctb` from discard; `modify_properties` Tags + Ghost | B |
| Forests Protection | 2 | Spell (reaction) | - | When your field is attacked, your creatures gain Indomitable until EOT | Response window; keyword grant | B |
| Guardian Spirits | 4 | Spell (field) | - | At the beginning of your turn you may flip a creature from your energy zone; it may attack this turn and returns to the energy zone at EOT | Same temporary-creature mechanism as Teshra | C |

### 14.5 Additional card ideas

| Card | Cost | Type / subtypes | S/G | Draft effect | Mapping | Class |
|------|------|-----------------|-----|--------------|---------|-------|
| Brogir, Master Artificer | 4 | Unique Creature, Dwarf Engineer | 3/4 | Productive. Occupy, choose 1: consume scrap -> ingot; or consume ingot -> Battle Hammer | Productive; `occ`; modal with costs | B |
| Rarink, Crafty Opportunist | 3 | Unique Creature, Goblin Thief | 2/2 | Whenever a non-token relic leaves the battlefield, create 2 scrap tokens | `card_moved_to_pile` trigger with `filter_properties` Type relic and not Token; scrap +2 | B |
| Self-destruction | 6 | Spell | - | Additional cost: consume X permanents. Opponents consume X permanents | `ask_integer` for X; cost selection; opponent-side selection; SYS-PLAYER | C |
| Sigil Mage | 2 | Creature, Mage | 1/2 | The first spell you cast each turn is placed in your energy zone instead of your discard | Spell-resolution destination redirect with per-turn flag; SYS-TURN | B |
| Holy Healer | 2 | Creature, Human Cleric | 1/1 | Enters: take a creature from your discard and put it in your hand | `mcc` discard -> hand with creature filter | A |
| Insightful Investigator | 2 | Creature, Human Soldier | 1/2 | Enters: look at the top two cards of target player's library; you may put one or both on the bottom | `index` subject on any player's deck, optional moves to bottom | B |
| Toll of War | 6 | Spell | - | Destroy all creatures in strike position | `boardseek` all, `filter_degrees: 0`, `mcc` discard | A |
| Broadening Influence | 5 | Unique Spell (world) | - | Instead of playing a card from hand into your energy zone, you may take the top card of an opponent's library into your energy zone | World slot; adds an alternative energy-play option to the upkeep choice for all players | C |
| No Where to Hide | 6 | Spell | - | Destroy all creatures in guard position | `boardseek`, `filter_degrees: 90`, `mcc` discard | A |
| Wave of Fear | 3 | Spell (reaction) | - | When another player declares attacks, remove any number of target attacking creatures from combat | Response window; `remove_from_combat` | B |
| Specter of Hate | ## | Creature, Ghost | 2/0 | Cannot be blocked and cannot block, but can be targeted | Unblockable and cannot-block flags | B |
| Unseen Reach | 2 (assumed) | Spell (field) | - | At the beginning of combat on your turn, choose a creature you control; it cannot be blocked this turn | Field slot; phase trigger; grant Unblockable until EOT | B |
| Battering Ram | 3 | Creature, Beast | 3/2 | May target relics as if creatures; relics hit are destroyed | Widened attack target set (shared with Zelith) | C |
| Goblin Scout Leader | 2 | Creature, Goblin Brawler | 2/1 | When it attacks, create a 1/1 goblin in strike position | Attack trigger; `spawn_card` into the creature grid | B |

### 14.6 Decklist 2 theme notes (no cards yet)

| Theme | Domains | Draft note | Systems it will need |
|-------|---------|-----------|----------------------|
| Undying Marauders | Chaos / Primal | Undying recursion, cost reduction for undying effect | Undying keyword (return from discard), PlayCost alterants, cast from discard (`cast_card`) |
| Evolution | Innovation / Primal | Evolution mechanic | Evolve keyword (Section 9), tutor by name, Charge grant |
| Fallen Faith | Order / Chaos | Doctrine manipulation | SYS-DOCTRINE interaction flags (shortcut, suppress, amplify) |
| Mages of the Sigil | Order / Innovation | Spell sling | Per-turn spell-count tracking, Sigil Mage style redirect, cast-from-zone |

---

## 15. Implementation roadmap

Ordered so each milestone is playable and testable, following the dependencies between the SYS systems.
The "cards unlocked" column is an estimate from the Mapping column of Section 14, cumulative out of 83.

| Milestone | Scope | Systems | Cards unlocked (cumulative) |
|-----------|-------|---------|------------------------------|
| **M0 - Project setup** | Rename stats (`Strike`, `Guard`), add `Domain`, `_pips`; add Creature/Relic/Spell/Token scenes; card fronts with the new labels; `CFConst`, `CardConfig`, token images; new `src/custom/fate/` folder; remove the demo `credits`/`research` counters | none | 0 |
| **M1 - Two-player table** | Mirrored layout, per-player containers, `PlayerContext`, owner/controller ids, `SP` controller/owner filters, two-deck load | SYS-PLAYER, SYS-FILTER, SYS-SLOT (grids only) | 0 (table only) |
| **M2 - Turn flow and energy** | **Done** | Ten-step turn with a phase state machine (`FateTurn`), automatic maintenance and draw, the energy-phase choice, main-phase mana payment (`FateMana`), `entered_turn`. Not done: Manifest/Ponder wording is replaced by the designer's choice (play energy OR draw extra), picker UI for which energy to tap |
| **M3 - Creatures and combat** | **Done** | Declare, intercept, resolve (`FateCombat`), stat layer (`FateStats`), destroy/damage pipeline (`FateEffects`), life and game over, click-driven combat UI. Keywords: Charge, Productive, Occupy, Savage, Indomitable, Untethered, Unblockable, Cannot block, Forced blocker (Section 17.7) |
| M4 - Abilities, tokens, control | Not started | Token cards are defined in the data only. Embody (an activated ability) is in |
| **M5 - Reactions and persisting spells** | **Partial** | Reaction windows and 5 of the 6 reaction spells are in (Double Agent needs take-control). Field and world slots have no replacement rule yet |
| M6 - Doctrines | Not started | Doctrine cards are on the table, with no goals or rewards |
| M7 - Class C cards and polish | Not started | |

### 17.3 Zones (Section 6)

| Zone | Status | Implementation |
|------|--------|----------------|
| Deck | **Done** | `FateDeck` pile per player, 40 cards, click to draw |
| Hand | **Done** | `FateHand` per player; the top player's hand hangs from the top edge |
| Discard | **Done** | `Pile`, face-up, per player |
| Energy zone | **Done** | `BoardPlacementGrid` "Energy P#", 6 slots, grows (`auto_extend`); cards go in face-down |
| Creature row | **Done** | "Creatures P#", 6 slots; creatures dropped on the table land here automatically |
| Occupied row | **Done** | Grid directly behind the creature row. The Occupy action moves creatures in (tilted); maintenance moves them back; occupied creatures can intercept |
| Relic zone | **Done** | "Relics P#", 3 slots; relics land here |
| Field spell slot | **Partial** | "Field P#", one slot; the replace-the-old-spell rule is not implemented |
| World spell slot | **Partial** | Shared "World" grid, one slot; replacement rule not implemented |
| Removed from game | **Done** | Small face-up pile per player (half scale) |
| Doctrine area | **Partial** | "Doctrines P#" holds three doctrine cards per player; no goals or rewards |
| Beneath a creature (embody) | **Done** | Embody attaches a face-down energy card behind the creature (framework attachment) |
| Token zone | Not started | Token cards exist in the data (`FateData.TOKENS`) but nothing creates them |

### 17.4 Cards, stats and rules

| Item (design section) | Status | Notes |
|-----------------------|--------|-------|
| Card types (5.1): Creature, Relic, Spell, Doctrine | **Done** | One scene per type under `src/custom/cards/`, front hides Strike and Guard for non-creatures |
| Spells by kind (5.1, 11.3) | **Partial** | `_spell_kind` is stored. Regular spells are paid for and resolve into the owner's discard in the main phase; reaction spells only in a reaction window (5 have effects); field and world spells go to their slots. Other spells have no effects yet |
| Stats (5.2): Cost, pips, Strike, Guard, subtypes, domain, unique | **Done** | All 83 catalog cards are defined with their stats. Pips are stored as the displayed string property `Pips` (Section 5.2 proposed a hidden `_pips`) so they appear on the card. `mana_value()` = generic cost + pips |
| Current vs base stat (5.2) | **Done** | `FateStats`: base from the card data, damage and modifiers on top, expiries (end of turn, owner's maintenance, permanent), keyword grants |
| Positions (5.3): strike, guard, occupied | **Done** | Strike upright, guard tilted (main phase, own creatures), occupied via the Occupy action. Combat reads the positions |
| Card catalog (14) | **Partial** | Data only. Tokens (3 creature, 2 relic) and the 12 doctrines are also defined |
| Keywords (9.1) | **Partial** | Charge, Productive, Occupy, Savage, Indomitable, Untethered, Embody done (Section 17.7). Evolve, Flip Cast, Limiter, Consume (as a rule) and Reaction beyond combat windows are not. `_keywords` is also the display list for the later info panels |
| Ownership (4.1) | **Partial** | `owner_id` and `controller_id` are set; control never changes. Players can only play their own cards from hand, in their own main phase |
| Energy and mana (7) | **Partial** | Face-down energy zone, untap in maintenance, per-domain mana count, automatic payment of generic cost and pips (tapping), `pay_generic` for abilities. No picker UI, no domain choice for dual-domain energy cards, no ingots |
| Turn structure (4.2) | **Done** | See M2 and `docs/FATE_RULES_SPEC.md` Section 1 |
| Win condition (4.3) | **Done (default rules)** | Life 10; unblocked attacks and damage lower it; at 0 or less the game ends with a "Player N wins" banner. Empty-deck loss and mulligans are not implemented |
| Doctrines (10) | Not started | Cards only |
| Combat (8) | **Done** | Declare, intercept (guard or occupied creatures), resolve in order, damage per Section 8.1; designer rule: occupied creatures may intercept (the draft said they cannot) |
| Deck building (11.2) | **Partial** | The designs are meant to be played as a single colour, so player 1 plays a mono Order deck and player 2 a mono Primal deck (`FateGame.PLAYER_DOMAINS`). Each is a curated 40-card list in `FateDecks.DECKLISTS` (3 copies at most, one of each legendary card, one God) with a curve of mostly 2-4 mana cards for smooth early turns: Order 18/16/5/0/0/0/1 and Primal 5/11/11/8/2/2/1 cards at mana value 1 to 7. Other domains get a generated legal deck. Spell effects other than the reactions are not implemented yet, so several spells in the lists do nothing beyond their cost. The deck builder UI is unchanged |

### 17.5 Decisions made during implementation

| Topic | Decision |
|-------|----------|
| Where card data lives | `FateData.gd` is registered at runtime (`FateGame.register_cards()`), not in `src/custom/cards/sets/`, because the framework unit tests count the demo definitions |
| Tokens | Creature and relic tokens use the Creature and Relic scenes with `_token: true` and `_hide_in_deckbuilder`, not the demo `Token` scene (which has Power instead of Strike and Guard) |
| Board construction | Built in code (`FateBoard.gd`) from the framework `Pile`, `Hand` and `BoardPlacementGrid` scenes, so both players get identical, mirrored zones |
| Card size on the table | 0.4 scale (`play_area_scale`) so six zones fit per player in 720 pixels. Hover for the zoomed view |
| Hands | Both hands are face-up (hotseat). The oval fan is switched off |
| Core edits | `MousePointer.gd` compared the card's parent to `cfc.NMAP.hand`; it now checks the `hands` group so more than one hand works. `BoardPlacementSlot.gd` highlight sizing (next row) |
| Slot highlight | `BoardPlacementSlot` now sizes its highlight panels (and gives each slot its own collision shape) from the grid's card scale. Before, the highlight stayed at the full 120x192 card size in any grid using a different `card_play_scale`, which looked oversized and misplaced on the 0.4-scale Fate grids |
| Player count | Exactly two (Section 12 item 19) |
| Rules decisions | The designer's turn and combat rules, and the decisions taken where the designer was silent (D1 to D8, e.g. the first player draws on turn 1), are in `docs/FATE_RULES_SPEC.md` Section 5 |
| Keyword architecture | One script per keyword in `src/custom/fate/keywords/`, auto-discovered by the registry; hooks for attack/block rules, damage, destruction destination, stat bonuses, hover actions and reaction windows (`src/custom/fate/keywords/README.md`) |
| Shared mana payment | `FateMana.plan_generic` / `pay_generic` pay an arbitrary generic amount (used by Embody and Forced blocker) |
| Zone checks | `FateZones.zone_of(card)` is the zone a card is in now; `FateCardTemplate.board_zone()` is the zone its type goes to. `can_tilt` uses the former so an occupied creature cannot be repositioned |
| Window scaling | `FateBoard` switches the root window to canvas-items scaling at 1280x720 (aspect kept) while the table is open and restores the previous settings when it closes, so the menu and demo board are unaffected |

### 17.6 Known limitations

- Hovering a card in the top player's hand pops it the wrong way (up, off screen); the magnified view still works.
- The layout is designed in a 1280x720 space and the window content is scaled to it (aspect kept), so the table fills a 16:9 window at any size and shows bars in other shapes. Text is rendered at the design resolution and stretched, so it softens in very large windows.
- Cards on the table are small by design; slot labels are the grid names.
- Both hands are visible, so this is not yet a fair two-player game; hiding the inactive hand belongs with a turn-handover screen.
- Dropping a card on the energy zone does nothing; use double-click.
- The status bar is small (two rows in a 32 px band); long prompts are cut short.
- No target-choice UI yet: Savage hits the blocking player by default, Safety Measure and Wave of Fear use default targets, Embody and Forced blocker use deterministic choosers (all replaceable hooks). Blockers cannot be ordered in the UI (declaration order is used).
- Combat arrows are all drawn at once and can cross the status bar when there are many attacks.
- Double Agent is not castable (needs take-control). Reaction windows only open in combat (after attackers are declared and after blockers are confirmed).
- Effects of individual cards (tokens, drawing, searching and so on) are not implemented, only the generic systems and the keywords above.

### 17.7 Turn, combat and keyword implementation (second pass)

Custom systems from Section 13, as built (files in `src/custom/fate/`):

| System | Status | Files |
|--------|--------|-------|
| SYS-TURN | **Done** | `FateTurn.gd`, `FateGame.gd` (phase machine, signals, hooks for combat) |
| SYS-ENERGY | **Partial** | `FateMana.gd` (pool, payment, `pay_generic`); energy-phase play in `FateGame`. Flip cast (`cast_card`) not started |
| SYS-COMBAT | **Done** | `FateCombat.gd`, `FateAttack.gd`, `FateCombatUI.gd`, `FatePlayerAvatar.gd` |
| SYS-MOD | **Done** | `FateStats.gd` (modifiers, damage, grants, expiries, reset) |
| SYS-KEYWORD | **Done** | `FateKeyword.gd`, `FateKeywords.gd` (registry), `FateActions.gd` (hover actions), `keywords/Kw*.gd` |
| SYS-RESPONSE | **Partial** | `FateReactions.gd`, `reactions/React*.gd`; combat windows only |
| Effects pipeline (destroy, deal damage) | **Done** | `FateEffects.gd` |
| SYS-CONTROL, SYS-TOKEN, SYS-DOCTRINE, SYS-DECK | Not started | |

Keywords and mechanics (Section 9.1):

| Keyword | Status | Behaviour as implemented |
|---------|--------|--------------------------|
| Charge | **Done** | May attack the turn it enters; without it a creature cannot (`KwCharge`) |
| Productive | **Done** | May occupy the turn it enters (`KwProductive`) |
| Occupy | **Done** | Hover button for creatures with the ability; tilts and moves to the occupied zone; cannot attack, can intercept; maintenance returns it (`KwOccupy`) |
| Savage X | **Done** | When blocked, X damage to the blocking player (or a creature via a chooser hook), once per blocked attack, before combat damage (`KwSavage`) |
| Indomitable | **Done** | Combat damage cannot take the used stat below 1; non-combat destruction still works (`KwIndomitable`) |
| Untethered | **Done** | Dies to the owner's removed pile (`KwUntethered`) |
| Unblockable, Cannot block | **Done** | `KwUnblockable`, `KwCannotBlock` (Specter of Hate has both) |
| Forced blocker | **Done** | Pay 2: only a named creature may block this attacker this turn (`KwForcedBlocker`; Beetle Brawler, Ironside Beetle) |
| Embody X | **Done** | Pay X: a face-down energy card beneath the creature, bonus Strike and Guard equal to its mana value (`KwEmbody`; Spirit Wielder) |
| Reaction | **Partial** | Windows after declare and after intercept; Factory Shutdown, Safety Measure, Hold the Line, Forests Protection, Wave of Fear (`FateReactions`) |
| Evolve, Flip Cast, Limiter, Consume (rule) | Not started | |

Tests: the headless suite (framework tests plus the Fate tests above) has 655 tests; the last full run had one
failure, a Fate PoC test that depended on a random starting hand, which was then made deterministic and re-run on its
own. The full suite was not re-run after that one-test fix.
