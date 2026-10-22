# Innovation card inventory and rebalance

Every Innovation card in the game: cost, stats and what the script does. The **Original** columns show the
cards before the rebalance. The **Rebalanced** column shows what changed (blank means no change). The deck
columns give the copies in the optimised deck (Goblin Foundry, `FateDecks.OPTIMISED["Innovation"]`) before and
after. Source of truth: the catalog in `docs/FATE_TCG_DESIGN.md` Section 14.1 / 14.5 (generated into
`src/custom/fate/FateData.gd` by `tools/gen_fate_cards.py`) and the scripts in `src/custom/fate/cards/` and
`src/custom/fate/reactions/`.

Cost notation: digits are generic mana, and each `#` is one Innovation pip. **MV** = mana value (generic + pips).
**S/G** = Strike / Guard. **Occupy** (older cards say *Tap*) moves the creature into the occupied zone until your
next maintenance. While occupied it cannot attack but still blocks. A creature cannot occupy on the turn it
arrives unless it is Productive.

## Cards

| Card | Type / subtypes | Original cost (MV) | Original S/G | Original effect | **Rebalanced** | Deck before | Deck after |
|------|-----------------|--------------------|--------------|-----------------|----------------|-------------|------------|
| Goblin Ledgerkeeper | Creature, Goblin Shopkeeper | `#` (1) | 0/1 (placeholder) | Occupy: create a scrap token | **1/2**. The draft had no stats. A 0/1 died to anything, and with 0 Strike it destroyed itself when it attacked | 3 | 3 |
| Skulking Goblin | Creature, Goblin Thief | `1#` (2) | 2/1 | When it attacks you may draw a card, then discard a card | | 3 | - |
| Rustmarket Tinkerer | Creature, Goblin Engineer | `1##` (3) | 1/3 | Occupy: cast a relic from your discard by paying its cost | | 3 | - |
| Steelwork Salvager | Creature, Goblin Engineer | `2##` (4) | 2/1 | When it attacks, create a scrap token | **`1#` (2), 2/2**. At 4 mana for a 2/1 nobody played it. Now a cheap attacker that feeds the Cannon | - | 3 |
| Acquisition Fabricator | Creature, Dwarf Engineer | `2#` (3) | 2/3 | Occupy, consume a scrap: create an ingot token | | 3 | 3 |
| Battle Smith | Creature, Dwarf Brawler | `1##` (3) | 3/3 | Occupy, consume an ingot: create a Battle Hammer attached to a creature you control (+2 Strike) | | 3 | 3 |
| Factory Crafter | Creature, Dwarf Engineer | `1##` (3) | 2/4 | Occupy, consume an ingot: create a 3/3 Iron Automaton in guard position. *(Uncommitted work in progress, not part of this rebalance: Occupy, consume a relic: create a 1/1 Automaton in guard position)* | | 3 | 3 |
| Rarink, Crafty Opportunist | Unique Creature, Goblin Thief | `3` (3) | 2/2 | Whenever a non-token relic (anyone's) leaves the battlefield, create 2 scrap tokens | | 1 | - |
| Brogir, Master Artificer | Unique Creature, Dwarf Engineer | `4` (4) | 3/4 | Productive. Occupy, choose one: consume a scrap to create an ingot; or consume an ingot to create a Battle Hammer on a creature | | 1 | 1 |
| Thrang, Perpetual Innovation | Unique Creature, Construct God | `5##` (7) | 6/6 | Consume a scrap: unoccupy target permanent you control. Cannot be targeted by spells | | 1 | 1 |
| **Clockwork Sentinel** *(new)* | Creature, Construct | - | - | - | **`1#` (2), 2/3 (2/2 until the field spell rule, see `docs/FATE_CARD_CHANGELIST.md`). When it is destroyed, create 2 scrap tokens.** An early blocker that pays off when it dies: the scrap is two Cannon shots or two ingots | - | 3 |
| **Scrapheap Colossus** *(new)* | Creature, Construct | - | - | - | **`2##` (4), 2/2. Gets +1 Strike and +1 Guard for each relic you control.** A body big enough to attack, built from the relics the deck already plays. Hammers count | - | 3 |
| Garbage Heap | Relic | `1#` (2) | - | Consume this relic: create 2 scrap tokens | | 3 | 2 |
| Scrap Recycler | Relic | `1#` (2) | - | Once per turn, consume a relic: draw a card | | - | - |
| Scrap Cannon | Relic | `2#` (3) | - | Consume a scrap: 1 damage to any target (no limit per turn) | | 3 | 3 |
| Factory Refinery | Relic | `###` (3) | - | Pay 1, consume a scrap: create an ingot token | **`1#` (2)**. Three pips made it hard to cast on time | 3 | 3 |
| Thrang's Crafting Table | Unique Relic | `3##` (5) | - | Consume 1 ingot: Battle Hammer. 2 ingots: 3/3 Iron Automaton in guard. 3 ingots: search your deck for Thrang | | 1 | - |
| Rapid Scavenging | Spell (regular) | `2` (2) | - | Create 2 scrap tokens | **Create 2 scrap tokens. Draw a card.** Was a card spent for no card back. It now replaces itself | 3 | 3 |
| **Disassemble** *(new)* | Spell (regular) | - | - | - | **`2` (2). Destroy target non-unique creature an opponent controls with 3 or less in the stat of its current position. Create 2 scrap tokens.** The domain's first proactive removal. It is narrower than Order's Smite (same cost) and pays back in scrap | - | 3 |
| Fabrication Line | Spell (regular) | `3` (3) | - | Create 2 copies of target token you control (a token card, or a scrap / ingot counter) | | - | - |
| Invigorated Workforce | Unique Spell (field) | `3` (3) | - | Your creatures with an Occupy / Tap ability are Productive | | - | - |
| Factory Shutdown | Spell (reaction) | `2` (2) | - | All attacks against you and your creatures this combat are negated | | 3 | - |
| Safety Measure | Spell (reaction) | `2` (2) | - | Destroy target attacking creature | | 3 | 3 |

Both lists have 40 cards. Before: 21 creatures, 10 relics, 9 spells. After: 25 creatures, 8 relics, 9 spells.

## Tokens and resources

| Token | Kind | Stats / effect | Made by |
|-------|------|----------------|---------|
| Scrap | Counter on the player | Spent by Fabricator, Refinery, Brogir, Scrap Cannon, Thrang | Ledgerkeeper, Salvager, Garbage Heap, Rapid Scavenging, Rarink, doctrine I1; **Clockwork Sentinel, Disassemble** |
| Ingot | Counter on the player | Spent by Battle Smith, Factory Crafter, Brogir, Crafting Table; or as 1 mana of any colour | Fabricator, Refinery, Brogir |
| Iron Automaton Token | Creature, Construct | 3/3 | Factory Crafter, Crafting Table |
| Automaton Token | Creature, Construct | 1/1 *(work in progress)* | Factory Crafter (relic mode) |
| Battle Hammer Token | Relic, attached | Attached creature +2 Strike; sits in the relic zone (and counts for Scrapheap Colossus) | Battle Smith, Brogir, Crafting Table |

## Doctrines (unchanged)

| ID | Doctrine | Goal | Reward |
|----|----------|------|--------|
| I1 | Construct the Future | Control 3 relics | Create a scrap token at the start of your turn |
| I2 | Devote Yourself to Progress | Devotion 5 Innovation | Your creatures can occupy the turn they are played |
| I3 | Produce Endlessly | Control 6 tokens | Whenever you create tokens, create one more of that kind |

## Rule change: no limit on relics

The relic zone used to have **3 slots**, shared by every relic, including Battle Hammers that sit on creatures. It now
works like the energy zone. It starts with 3 slots and grows by one whenever it is full, so a player can have any
number of relics. On the table the cards squeeze together to stay in one row (`FateLayout.UNLIMITED_ZONES`,
`RELIC_START_SLOTS`, `RELIC_ROW_WIDTH`; `FateBoard._squeeze_rows`). The AI treats a growing zone as always having
room. Board-state files allow up to 40 relics, the same sanity limit as energy.

## How the deck was measured

All numbers come from the AI simulation lab (`src/custom/fate/sim/README.md`): AI at normal strength on both sides,
seats alternating, doctrines on, 100 games per pairing. A win rate of N games has an uncertainty of about +-5.6 points
at 300 games and +-9.6 at 100 games, so differences smaller than that are noise.

### 1. Baseline: the original cards

Round robin of the four optimised decks, 600 games.

| Deck | Relic limit 3 | No relic limit |
|------|---------------|----------------|
| Abyssal Usurpers (Chaos) | 57.3% | 55.3% |
| Wild Stampede (Primal) | 56.3% | 56.7% |
| Iron Vanguard (Order) | 50.2% | 49.3% |
| **Goblin Foundry (Innovation)** | **36.1%** | **38.7%** |

Lifting the relic limit helped the Foundry by only about 2.6 points, which is within noise. The relic limit was not
what held the deck back.

### 2. What was weak (from the baseline records)

| Measure (per deck, baseline with the limit) | Foundry | Other three |
|---------------------------------------------|---------|-------------|
| Attacks per turn | 0.34 | 0.80 to 1.02 |
| Hits on the opponent per game | 0.73 | 2.8 to 3.5 |
| Win rate on the draw | 15% | 26 to 31% |
| Win rate on the play | 57% | 75 to 84% |
| Combat damage taken per game | 3.65 | 2.0 to 2.2 |

* **No offence.** The engine creatures (Fabricator, Crafter, Smith, Tinkerer, Ledgerkeeper) occupy every turn, and the AI
  rightly keeps them home. Almost the only thing that attacked was Skulking Goblin, a 2/1. Nearly all damage came from
  the Scrap Cannon, about 1.3 per game. The deck could not turn going first into a win (57% on the play, compared with
  75 to 84%).
- **Bodies too small for their cost.** A 0/1 one-drop, a 1/3, a 2/1 for four mana. It took more combat damage than any
  other deck.
- **Dead cards.** Factory Refinery (three pips), Rapid Scavenging, Garbage Heap, Factory Shutdown, Safety Measure and the
  Crafting Table were turned into energy 60 to 80% of the time. The deck spent only 46% of its mana.
- **No proactive removal.** The only answers were reactive (Safety Measure) or 1 damage at a time (Cannon).

### 3. Iterations

Each version played 100 games against each of the other three optimised decks (300 games).

| Version | Changes | Relic limit | Foundry win rate | vs Order / Primal / Chaos |
|---------|---------|-------------|------------------|---------------------------|
| Original | - | 3 | 36.1% | 36 / 41 / 31% |
| Original | - | none | 38.7% | 43 / 39 / 34% |
| v1 | Ledgerkeeper 1/2, Salvager `1#` 2/2, Refinery `1#`, Rapid Scavenging draws; new Clockwork Sentinel (2/3), Scrapheap Colossus (base 2/2), Disassemble (cost 3); new list | 3 | 46.3% (+-5.6) | 52 / 50 / 37% |
| v2 | Disassemble cost 2; Colossus base 3/3; 2 Garbage Heap in place of 2 Rustmarket Tinkerer | 3 | 55.7% (+-5.6) | 57 / 61 / 49% |
| v2 | same | none | 61.0% (+-5.5), **too strong** | 66 / 61 / 56% |
| **v3 (adopted)** | Clockwork Sentinel 2/3 to **2/2**; Colossus base 3/3 to **2/2** | none | **53.2% (+-5.6)** | 60 / 56 / 44% |

With unlimited relics, v2 was clearly too strong, because a Colossus with no cap on relics grows without limit. v3 takes
back one point of Guard from the Sentinel and one point of each stat from the Colossus base, and lands at even within noise.

### 4. The field after the rebalance

Round robin of the four optimised decks after the rebalance, with no relic limit (600 games, seed `final`):

| Deck | Win rate | On the play | On the draw | Before (no relic limit) |
|------|----------|-------------|-------------|--------------------------|
| Abyssal Usurpers (Chaos) | 56.3% (+-5.6) | 80% | 33% | 55.3% |
| Wild Stampede (Primal) | 52.8% (+-5.6) | 81% | 25% | 56.7% |
| **Goblin Foundry (Innovation)** | **50.8% (+-5.6)** | 69% | 32% | 38.7% |
| Iron Vanguard (Order) | 40.0% (+-5.5) | 64% | 16% | 49.3% |

| Matchup (first deck wins) | |
|---------|--|
| Order against Primal / Chaos / Foundry | 40% / 36% / 44% |
| Primal against Chaos / Foundry | 49% / 49.5% |
| Chaos against Foundry | 54% |

The Foundry is now in the middle of the field, and none of its matchups is outside noise. **Order is now the weakest
deck.** It lost about 9 points compared with the run with no relic limit and the original cards (49.3%). Most of that
comes from the Foundry matchup, which went from 57-43 for Order to 44-56. Order is the deck to look at next.

## Notes

* A script error, `FateAIEval.gd:118 Out of bounds get index '0'`, appears in 1 or 2 games per 300 in the AI's position
  scoring. It is older than this work (it is in runs from 2026-10-20) and does not depend on a deck.
* Going first still wins about 70% of games in every pairing (`docs/FATE_DECKS.md`). That is a rules question, not a deck
  question, and is untouched here.
* Cards still unused by the optimised deck: Skulking Goblin, Rustmarket Tinkerer, Rarink, Scrap Recycler, Fabrication
  Line, Invigorated Workforce, Factory Shutdown and Thrang's Crafting Table. They stay unchanged and available for
  other lists.
