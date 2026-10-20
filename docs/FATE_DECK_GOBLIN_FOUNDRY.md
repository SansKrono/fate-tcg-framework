# Goblin Foundry (Innovation, optimised)

The optimised Innovation deck of the catalogue (`FateDecks.OPTIMISED["Innovation"]`, preset id `innovation_optimised`).
A scrap engine that ends in fire: goblins and Garbage Heaps make **scrap**, Scrap Cannons turn every spare scrap into
a point of damage to the opponent's life, Factory Crafter and Battle Smith turn **ingots** (made from scrap) into
automatons and hammers, and Safety Measure and Factory Shutdown buy the time. Slow to start, and the stock of scrap
is a clock the opponent cannot see.

Card text, stats and costs are from the card catalogue (`src/custom/fate/FateData.gd`) and the card scripts
(`src/custom/fate/cards/`). Numbers from games are from the AI simulation lab (`src/custom/fate/sim/README.md`), the
AI at normal strength on both sides; how they were obtained is in `docs/FATE_DECKS.md`.

## The list

40 cards: 21 creatures, 10 relics, 9 spells. Every card is mono Innovation, so there are no colour problems and the
curve alone decides how smooth the early turns are. Mana value = generic cost + one per pip.

| # | Card | Type | Mana value |
|---|------|------|-----------|
| 3 | Goblin Ledgerkeeper | Creature | 1 |
| 3 | Skulking Goblin | Creature | 2 |
| 3 | Acquisition Fabricator | Creature | 3 |
| 3 | Battle Smith | Creature | 3 |
| 3 | Factory Crafter | Creature | 3 |
| 3 | Rustmarket Tinkerer | Creature | 3 |
| 1 | Rarink, Crafty Opportunist (unique) | Creature | 3 |
| 1 | Brogir, Master Artificer (unique) | Creature | 4 |
| 1 | Thrang, Perpetual Innovation (unique, God) | Creature | 7 |
| 3 | Garbage Heap | Relic | 2 |
| 3 | Factory Refinery | Relic | 3 |
| 3 | Scrap Cannon | Relic | 3 |
| 1 | Thrang's Crafting Table (unique) | Relic | 5 |
| 3 | Rapid Scavenging | Spell (regular) | 2 |
| 3 | Safety Measure | Spell (reaction) | 2 |
| 3 | Factory Shutdown | Spell (reaction) | 2 |

```
mana value   1    2    3    4    5    7
cards        3   15   19    1    1    1
```

Nineteen of the forty cards cost 3 and fifteen cost 2: the deck is never short of something to do with its mana, and
the one expensive card (Thrang) is also the one the Crafting Table fetches. Every card is also energy when it is not
cast: in this deck Garbage Heap, Rapid Scavenging, Factory Refinery and the reactions are the cards that most often
become mana (see "How it plays in practice").

## The resources

Three resources are not cards. They are counters on the player (`FateTokens`), and the whole deck is a way of turning
one into the next:

| Resource | Made by | Spent on |
|----------|---------|----------|
| **Scrap** | Goblin Ledgerkeeper (Occupy), Garbage Heap (2 when consumed), Rapid Scavenging (2), Rarink (2 whenever a non-token relic leaves), Brogir, doctrine I1 (1 each upkeep) | Acquisition Fabricator, Factory Refinery, Brogir (scrap into ingot); **Scrap Cannon (1 damage each)**; Thrang (unoccupy) |
| **Ingot** | Acquisition Fabricator (Tap, consume a scrap), Factory Refinery (pay 1, consume a scrap), Brogir | Factory Crafter (3/3 automaton), Battle Smith (hammer), Brogir (hammer), Thrang's Crafting Table (hammer / automaton / Thrang), 1 mana of any colour |
| **Tokens** | Iron Automaton (3/3 guard, from Factory Crafter or the Table), Battle Hammer (relic, +2 Strike, from Smith / Brogir / the Table) | They are the army. A hammer keeps its slot in the relic zone while it sits on its creature |

Board limits that shape the deck: **6 creature slots, 6 occupied slots, 3 relic slots, 1 field slot**. The three relic
slots are shared by Garbage Heap, Factory Refinery, Scrap Cannon, the Crafting Table and every Battle Hammer; the six
creature slots by the engine creatures and the automatons.

**Occupy** (also written Tap on the older cards) tilts the creature into the occupied zone: it can no longer attack
this turn, can still block with its Guard, and returns at the owner's next maintenance. A creature cannot occupy the
turn it is played (unless it is Productive, or doctrine I2 is done, or Invigorated Workforce is out), so every engine
creature starts working one turn after it arrives.

## Card by card

### Creatures

| Card | Mana value | Strike / Guard | Type | Ability |
|------|-----------|---------------|------|---------|
| **Goblin Ledgerkeeper** x3 | 1 (0 + I) | 0 / 1 | Goblin Shopkeeper | Occupy: create a scrap token |
| **Skulking Goblin** x3 | 2 (1 + I) | 2 / 1 | Goblin Thief | When it attacks you may draw a card, then discard a card |
| **Acquisition Fabricator** x3 | 3 (2 + I) | 2 / 3 | Dwarf Engineer | Tap, consume a scrap: create an ingot token (an ingot can be consumed for 1 mana of any colour) |
| **Battle Smith** x3 | 3 (1 + II) | 3 / 3 | Dwarf Brawler | Tap, consume an ingot: create a Battle Hammer token attached to a creature you control (+2 Strike) |
| **Factory Crafter** x3 | 3 (1 + II) | 2 / 4 | Dwarf Engineer | Tap, consume an ingot: create a 3/3 iron automaton token in guard position |
| **Rustmarket Tinkerer** x3 | 3 (1 + II) | 1 / 3 | Goblin Engineer | Occupy: cast 1 relic from your discard by paying its cost |
| **Rarink, Crafty Opportunist** x1 | 3 | 2 / 2 | Goblin Thief (unique) | Whenever a non-token relic leaves the battlefield, create 2 scrap tokens |
| **Brogir, Master Artificer** x1 | 4 | 3 / 4 | Dwarf Engineer (unique) | Productive. Occupy, choose 1: consume scrap into an ingot; or consume an ingot into a Battle Hammer |
| **Thrang, Perpetual Innovation** x1 | 7 (5 + II) | 6 / 6 | Construct God (unique) | Consume a scrap: unoccupy target permanent you control. Cannot be targeted by spells |

What each does in the plan:

* **Goblin Ledgerkeeper** is the engine's first stone: a 0/1 for one mana whose only job is one scrap per turn from the
  turn after it lands. The AI still gives it up as energy in about half the games where it sees it, when a hand
  has better things to cast, and plays it when the turn has a mana to spare.
* **Skulking Goblin** is the deck's early body and its filter: a 2/1 for two that loots when it attacks, which turns
  the extra relics and reactions in a hand into cards the deck wants.
* **Acquisition Fabricator** (2/3) is the converter that turns the Ledgerkeeper's scrap into ingots. Its ingot is also
  mana of any colour, which is how the deck pays for Thrang.
* **Battle Smith** (3/3, the best body of the engine) and **Factory Crafter** (2/4 that produces 3/3 guards) are the two
  ingot sinks. Crafter is the better rate (an ingot is a 3/3 body); Smith adds +2 Strike to a creature that is going
  to attack. Both can also block, because they stay in the creature zone until they Tap.
* **Rustmarket Tinkerer** (1/3) is a wall that recasts a relic from the discard pile by paying its cost: a consumed
  Garbage Heap (2 more scrap, 2 more with Rarink on the table), or a Scrap Cannon that was destroyed.
* **Rarink** (2/2) pays 2 scrap whenever a non-token relic leaves: every Garbage Heap consumed is worth 4 scrap with
  him out. Battle Hammers are tokens and do not count.
* **Brogir** (3/4, Productive) is the best creature in the deck: he works the turn he is played, and he is both the
  converter and a sink. One copy.
* **Thrang** (6/6) is the finisher and the engine refresher at once: each scrap un-occupies any occupied creature or
  tilted permanent, so an engine creature works a second time in the same turn. Spells cannot target him and he is unique, so
  Smite, Claimed by the Abyss and Unseen Manipulator's Convert cannot take him; combat and damage still can.

### Relics

| Card | Mana value | Ability |
|------|-----------|---------|
| **Garbage Heap** x3 | 2 (1 + I) | Consume this relic: create 2 scrap tokens |
| **Factory Refinery** x3 | 3 (0 + III) | Pay 1, consume a scrap: create an ingot token |
| **Scrap Cannon** x3 | 3 (2 + I) | Consume a scrap: 1 damage to any target (to a creature, it reduces the stat for its current position) |
| **Thrang's Crafting Table** x1 | 5 (3 + II) | Consume 1 ingot: create a Battle Hammer, attach it to a creature. Consume 2: create a 3/3 guard automaton. Consume 3: search for Thrang into your hand |

* **Scrap Cannon** is the win condition. The ability has no tap and no limit per turn, only the scrap it eats, so a
  Cannon plus N scrap is N points of damage to the opponent at once, at any point of your main phase. Damage to a
  *player* is permanent (damage to a creature heals at its owner's maintenance), which is why the AI aims it at the
  face. With 10 life to take, ten scrap is a lethal turn without a single attack.
* **Garbage Heap** is two scrap for two mana, once (cast it, then consume it for free). With Rarink it is four; with
  Rustmarket Tinkerer it can be cast again from the discard. It is also the fastest way to reach doctrine I1
  (three relics).
* **Factory Refinery** is a second converter that does not need a creature, a tap or a free occupied slot (it costs a
  mana and a scrap). It is also a relic for doctrine I1.
* **Thrang's Crafting Table** is the singleton flexible sink: a hammer for one ingot, a 3/3 for two, and for three the
  tutor that finds Thrang.

### Spells

| Card | Mana value | Kind | Ability |
|------|-----------|------|---------|
| **Rapid Scavenging** x3 | 2 | Regular | Create 2 scrap tokens |
| **Safety Measure** x3 | 2 | Reaction | Destroy target attacking creature |
| **Factory Shutdown** x3 | 2 | Reaction | All attacks against you and your field are negated |

* **Rapid Scavenging** is the cheapest way to turn mana into two scrap (a Cannon's worth of damage) and the card that
  most improved the list: the old list had Scrap Recycler (a relic that draws) in its place.
* **Safety Measure** and **Factory Shutdown** are the defence of a deck that does nothing on turns 1 to 3: one kills
  an attacker, the other cancels a whole attack. Both are held (mana left open) only when the AI expects an attack.

### Tokens the deck makes

| Token | Stats | Made by |
|-------|-------|---------|
| Iron Automaton | 3/3 creature, enters in guard position | Factory Crafter, Thrang's Crafting Table |
| Battle Hammer | relic, attached creature gains +2 Strike | Battle Smith, Brogir, Thrang's Crafting Table |

### Doctrines (automatic, not in the 40 cards)

| Tier | Doctrine | Goal | Reward |
|------|----------|------|--------|
| 1 | Construct the Future | Count Relic 3 | Create a scrap token at the beginning of your upkeep |
| 2 | Devote Yourself to Progress | Devotion 5 Innovation | Creatures can occupy the turn they are played |
| 3 | Produce Endlessly | Token Count 6 | Whenever you create a token, create an additional one of that kind |

The deck reaches I1 with its ten relics (three on the table is a Heap, a Refinery and a Cannon), I2 with its mono
Innovation board and I3 by hoarding scrap, ingots and automatons: with I3, every scrap and ingot is doubled.

## The plan

1. **Turns 1 to 3: survive and set up.** Ledgerkeeper first (it needs one turn before it works), then a converter
   (Fabricator or Refinery) or a body (Skulking Goblin, Smith, Crafter, Tinkerer). Keep two mana open for a reaction
   when the opponent can attack.
2. **Turns 4 to 8: the engine runs.** Each turn the engine creatures occupy (scrap, then ingot, then payoff) while the
   rest block; automatons and hammers build a board that blocks well and starts to attack. This is also when the first
   Cannon goes down.
3. **Turn 8 on: the burn.** A Scrap Cannon with a stock of scrap fires every scrap that the engine does not need
   (the AI keeps two back for ingots) at the opponent's life, all of it the turn the stock reaches their life total.
   Rapid Scavenging and a consumed Garbage Heap are two scrap each at once, which is how the last points are found.
4. **The finisher** is Thrang (fetched by the Table for three ingots), who also refreshes every occupied engine creature.

## How the AI plays it

The AI (`docs/FATE_AI.md`) has three pieces of knowledge for this deck:

* **The engine runs in rounds** (`ability_rounds`): scrap first, then the ingot it makes, then the automaton or hammer,
  in the same turn, and the attack is planned again after each round, because an engine creature that attacks cannot
  occupy (`FateAIMain._hold_engines`).
* **The Cannon burst** (`scrap_burn`, `burn_reserve`; `FateAIAbilities.plan_burn`): every scrap above the reserve is
  fired at the opponent's life, all of it when it is lethal. Before this the Foundry sat on 20 to 37 scrap with a
  Cannon on the table; with it, the old Foundry list went from 31.5% to 40.7% against the other three decks.
* **The Cannon is a card**, not mana: it is worth five points in hand so it is not pitched to the energy zone early
  (`FateAIEval.LIVE_EFFECTS`).

## How it plays in practice

Round robin of the four optimised decks, 100 games per pairing, normal AI on both sides, seats alternating:

| | Win rate |
|-|---------|
| Overall | 40.7% (+-5.5) |
| On the play / on the draw | 55% / 26% |
| Against Iron Vanguard (Order) | 40% |
| Against Wild Stampede (Primal) | 44% |
| Against Abyssal Usurpers (Chaos) | 38% |
| Average length | 25 to 27 turns against Order, 18 to 19 against Primal and Chaos |

Per card, over those games (what the AI did with each card; "energy" is the share of the games in which it was played
as mana instead of cast):

| Card | Casts per game it was seen | Played as energy | Game turn it comes down |
|------|----------------------------|------------------|--------------------|
| Battle Smith | 1.42 | 4% | 9.4 |
| Factory Crafter | 1.41 | 6% | 10.2 |
| Acquisition Fabricator | 1.40 | 7% | 11.1 |
| Skulking Goblin | 1.15 | 30% | 7.4 |
| Rustmarket Tinkerer | 1.07 | 26% | 12.3 |
| Scrap Cannon | 0.95 | 40% | 15.3 |
| Garbage Heap | 0.84 | 71% | 15.1 |
| Brogir | 0.84 | 6% | 11.0 |
| Goblin Ledgerkeeper | 0.68 | 59% | 6.8 |
| Rarink | 0.63 | 16% | 12.6 |
| Thrang | 0.61 | 1% (38% never used) | 14.8 |
| Safety Measure | 0.55 | 56% | 12.3 |
| Factory Refinery | 0.47 | 70% | 16.4 |
| Rapid Scavenging | 0.39 | 77% | 18.0 |
| Thrang's Crafting Table | 0.18 | 74% | 18.4 |
| Factory Shutdown | 0.18 | 80% | 16.7 |

Read it as a description of the AI's play, not as a ranking of the cards: the "win rate with the card" figures of the
report (every card above +10 points except Rarink) mostly say that a card that is drawn late in a long game looks
good. What it shows is that the three engine creatures are cast about once in every game they are seen, the
Ledgerkeeper is often used as mana (a 0/1 is sometimes the best card to give up for energy), Heap, Refinery,
Scavenging and the reactions are mostly mana, and the Cannon comes down at game turn 15 on average (it is played as mana in 40% of the games
where it is seen): too late. The deck has no fast way to find it (the Table is a single copy that also costs 5).

## Weaknesses

* **Slow.** Nothing the deck does on turns 1 to 3 pressures the opponent, so it wins almost only on the play (55%
  against 26%). Against Chaos (38%) the engine pieces get stolen: Unseen Manipulator and Claimed by the Abyss take a
  Fabricator or Crafter, Double Agent turns an automaton against its owner for a turn, and unblockable Specters ignore
  the walls. Safety Measure is the answer to an attacker; nothing answers a Specter except the Cannon.
* **Relic slots.** Three slots for Heap, Refinery, Cannon, Table and every hammer. A hammer stays in its slot while its
  creature lives, so a fourth relic cannot be cast. The AI counts slots when choosing what to cast.
* **Long games.** At 25 or more turns, a 40-card deck can run out of cards (about one game in twenty ends that way
  over the four decks). The AI stops drawing extra cards when its deck would run out first (`deck_race`).
* **The first-player advantage** (72% over the four decks, see `docs/FATE_DECKS.md`) hurts a slow deck more than a
  fast one.

## Changing it

What was tried and what it did is in `docs/FATE_DECKS.md`, "The second pass". The short version: removing Scrap
Recycler and Steelwork Salvager for Rapid Scavenging and Factory Refinery was the one list change that showed (about
+6 points in the gauntlet that produced it, 40.7% to 47%); Refinery or Fabrication Line in place of Battle Smith or Tinkerer, and
Invigorated Workforce, were worse (32 to 36%); a different AI style (control, aggro) or energy target did not change
the result. To try another list, put it in a deck file and run it as a gauntlet against the other decks
(`src/custom/fate/sim/README.md`, "Finding good cards and decks"); 100 games per opponent cannot separate a swap of
one or two cards, only a change of plan.
