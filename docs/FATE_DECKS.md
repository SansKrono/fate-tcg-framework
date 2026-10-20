# Decks of the catalogue

The deck selection screen (main menu -> *Fate Two-Player PoC*) lets each player pick one of eight decks: per domain an
**optimised** deck and a **starter** deck (`FateDecks.presets()`). Starter decks are the default lists of a domain
(`FateDecks.DECKLISTS`; Chaos and Innovation have none, so their starter is the generated deck: a plain selection
of the domain's cards). The optimised decks were built from the data of the AI simulation lab
(`src/custom/fate/sim/README.md`). The choice reaches the table through `FateGame.domain_override` and
`decklist_override`; a table opened without the screen plays Order against Primal.

> The first two tables (how the decks were made) were measured with the AI as it was before the weighted profile system
> (`docs/FATE_AI.md`). **The Goblin Foundry list was rebuilt after it** (see "The second pass"); the other three lists
> were re-tested against the new AI and kept. The current standings are under "The field".

## How they were made

1. **Discovery.** For each domain, 160 to 200 random legal decks (every copy the rules allow shuffled, 40 taken) played
   two games each against the four starter decks (about 400 games per domain, 560 deck-games for Order). Regressing
   the result on the copies of each card gave an effect per copy, with a standard error of 3 to 4 points: enough to
   see that Enthralled Civilian, Unseen Manipulator and Specter of Hate (Chaos) or Battering Ram, Feracious Beast and
   Beetle Brawler (Primal) pull their weight and that Delve into the Beyond, Rapid Scavenging or Insightful
   Investigator do not, not enough to rank the middle of a domain.
2. **Candidates.** Per domain: the starter with the best 2, 4 and 6 swaps by that data, and a first draft built from the
   best cards of the data.
3. **Gauntlet.** Every candidate played 24 games against each of the four starters. The numbers below are the win rate
   against the starters of the *other three* domains (72 games per candidate, so about +-11 points).

| Domain | Starter | Best candidate (chosen) | Other candidates |
|--------|---------|--------------------------|------------------|
| Order | 58% | first draft 56% | starter + 2 / 4 / 6 swaps: 53 / 54 / 46% |
| Primal | 67% | starter + 4 swaps 67% | + 2 / 6 swaps 65 / 65%, first draft 63% |
| Chaos | 21% | first draft 50% | - |
| Innovation | 43% | first draft 61% | + 2 / 4 / 6 swaps: 51 / 57 / 50% |

So the optimised Chaos and Innovation decks are a large step up from the generated decks, while the hand-tuned Order and
Primal starters were already at the top of what this test can tell apart: the optimised Order and Primal decks are
equal to them within noise, and were kept because they play differently (Order: more bodies and pump, Primal: more ramp).

## The field

All four optimised decks against each other, 100 games per pairing (600 games), the AI at normal strength on both
sides, seats alternating, with the AI as it is now (`docs/FATE_AI.md`):

| Deck | Win rate | On the play | On the draw |
|------|----------|-------------|-------------|
| Abyssal Usurpers (Chaos) | 58.7% (+-5.5) | 83% | 34% |
| Wild Stampede (Primal) | 53.7% (+-5.6) | 81% | 27% |
| Iron Vanguard (Order) | 47.0% (+-5.6) | 69% | 25% |
| Goblin Foundry (Innovation) | 40.7% (+-5.5) | 55% | 26% |

| Matchup (first deck wins) | |
|---------|--|
| Order against Primal / Chaos / Innovation | 44% / 37% / 60% |
| Primal against Chaos / Innovation | 49% / 56% |
| Chaos against Innovation | 62% |

The spread from best to worst deck is 18 points; with the first version of the new AI it was 46 (Chaos 66%, Primal 60%,
Order 54%, Innovation 20%). No pairing is lopsided except Chaos against Foundry.

Things the simulations also show, useful beyond these decks:

* **The player who goes first wins 72% of the games**, in every pairing. That is the biggest imbalance there is, and
  no deck list can touch it: it decides more games than the whole gap between the best and the worst deck. Tried as
  temporary rule changes (one pairing, 100 games each, Primal against Chaos): nothing 82%, the first player skipping
  the first draw 71%, the second player getting two extra cards 75%, the second player starting with one extra energy
  card on the table 37% (it flips the advantage), two extra energy cards 16%. Energy is worth far more than cards, so a
  rule between "skip the first draw" and "one free energy for the second player" is the place to look
  (`FateGame.FIRST_PLAYER_SKIPS_FIRST_DRAW` is the existing switch). Not changed: it is a rules decision.
* Games last about 18 turns; one in twenty ends by deck-out (Foundry games, 25 to 27 turns against Order, are the ones that last).
* Single-card swaps are below what a simulation can see: a swap of three copies moves a deck by a few points and the
  noise of 100 games is +-9. Every Order, Primal and Chaos variant tried (see below) landed inside it.

## The second pass (new AI)

Redone after the weighted AI (`docs/FATE_AI.md`), to see what was left on the table:

1. **Discovery again** (150 random decks per domain, two games against each of the other three optimised decks, the
   result regressed on the copies of each card, the seat of the first player as an extra term). It confirmed the lists
   of Order (Moral Captain +9 points per copy, Devote Paladin +5, Hold the Line +5, Smite +4), Primal and Chaos (Ikthar
   +11, Enthralled Civilian +9, Double Agent +8, Unseen Manipulator +8, Claimed by the Abyss +7; Delve into the Beyond
   -8) and said nothing clear about Innovation: random Foundry decks won 31% and no card stood out (standard errors of 4
   to 7 points). The deck was weak as a whole.
2. **The Foundry was weak because the AI did not know its win condition.** A trace of a game showed 20 to 37 scrap
   lying unused for 10 turns, ingots piling up and a Scrap Cannon (consume a scrap: 1 damage to any target, no limit
   per turn) on the table that fired three times a turn. The AI now fires the Cannon with every scrap the engine does
   not need and with all of it when the scrap is lethal (`scrap_burn`, `burn_reserve`; `FateAIAbilities.plan_burn`), and
   values the Cannon as a card instead of as energy. The old Foundry list went from 31.5% to 40.7% against the other
   three decks with that alone.
3. **Then the list.** Burn needs scrap, so Rapid Scavenging (two scrap) replaced Scrap Recycler (a relic that
   draws), and Factory Refinery (scrap into an ingot) replaced the 2/1 Steelwork Salvager that costs four. The three
   variants tried first (Refinery or Fabrication Line in place of Battle Smith or Tinkerer, Workforce) scored 32 to 36%;
   the chosen one 47% in the gauntlet that produced it and 40.7% in the round robin above.
4. **Order got an AI setting, not a list.** Pursuing the doctrines (`doctrine_pursuit` 1.0 instead of 0, now the
   default of the normal grade and above) moved the Order deck from 48.8% to 54.6% against Primal, Chaos and Foundry
   (240 games each) and did nothing for the other three decks (Primal 58.8 against 59.3, Chaos 59.2 against 59.6,
   Foundry 45.0 against 45.4). Lower or higher energy targets (4 and 7) and more aggression were worse (40 to 47%).
5. **Tried and not adopted** (108 to 240 games each, noise +-6 to +-9, none better than the current list): Order
   without War of Attrition (Righteous Guard instead, also with Wave of Fear, Spiked Barricade or Insightful
   Investigator), Primal without Guardian Spirits / Toll of War / Cycle of Life / Meek Minion (Primal Wraith, Forests
   Protection, Second Calling instead), Chaos without Harbinger, Murkmist Gemstone, Unseen Reach and Repurpose
   (Eldritch Knowledge, Unforgotten Sacrifice, Deep Thought instead). A style (control, aggro) or a different energy
   target made no difference to the Foundry either.

## The decks

### Iron Vanguard (Order, optimised)

A fast human army. Cheap soldiers and Reinforcements go wide, Moral Captain and Battle Ready send the whole line in with extra Strike, Devote Paladin adds Savage, Smite removes the blocker that matters and Lucran closes the game.

3x Battle Ready, 3x Devote Paladin, 3x Faithful Worshiper, 3x Hold the Line, 3x Holy Healer, 3x Moral Captain, 3x Recovering Resources, 3x Reinforcements, 3x Sigil Mage, 3x Smite, 3x Streetside Recruiter, 3x Tactical Combatant, 2x War of Attrition, 1x Lucran, Divine Saviour, 1x Zelith, Mage Justiciar

### Wild Stampede (Primal, optimised)

Big, efficient beasts on a smooth curve. Battering Ram, Beetle Brawler, Feracious Beast and Ironside Beetle hit hard with Savage, Elder Spirit and Cycle of Life ramp your energy, and Wraithful Treespirits and Teshra finish the game.

3x Battering Ram, 3x Beetle Brawler, 3x Cycle of Life, 3x Dragon's Tooth, 3x Elder Spirit, 3x Feracious Beast, 3x Goblin Scout Leader, 3x Ironside Beetle, 3x Meek Minion, 2x Guardian Spirits, 2x Return to Nature, 2x Spirit Wielder, 2x Wraithful Treespirits, 1x Ancient Tree, 1x No Where to Hide, 1x Teshra's War Gauntlets, 1x Teshra, Primal Mother, 1x Toll of War

### Abyssal Usurpers (Chaos, optimised)

Steals the other player's army. Unseen Manipulator and Harbinger of Krelgar take their creatures, Claimed by the Abyss and Double Agent turn their attackers against them, and unblockable Specters keep the pressure on until Krelga ends it.

3x Claimed by the Abyss, 3x Cultist Fanatic, 3x Dockside Alter, 3x Dockside Ambusher, 3x Double Agent, 3x Enthralled Civilian, 3x Harbinger of Krelgar, 3x Murkmist Gemstone, 3x Specter of Hate, 3x Unending Echo, 3x Unseen Manipulator, 3x Unseen Reach, 2x Repurpose, 1x Ikthar, The Great Summoner, 1x Krelga, Abyssal Nightmare

### Goblin Foundry (Innovation, optimised)

A scrap engine that ends in fire. Goblins and Garbage Heaps make scrap, Scrap Cannons turn every spare scrap into a point of damage to the opponent's life, Factory Crafter and Battle Smith turn ingots into automatons and hammers, and Safety Measure and Factory Shutdown buy the time. Slow to start, and the stock of scrap is a clock the opponent cannot see.

3x Acquisition Fabricator, 3x Battle Smith, 3x Factory Crafter, 3x Factory Refinery, 3x Factory Shutdown, 3x Garbage Heap, 3x Goblin Ledgerkeeper, 3x Rapid Scavenging, 3x Rustmarket Tinkerer, 3x Safety Measure, 3x Scrap Cannon, 3x Skulking Goblin, 1x Brogir, Master Artificer, 1x Rarink, Crafty Opportunist, 1x Thrang's Crafting Table, 1x Thrang, Perpetual Innovation

## Changing a deck

The lists are `FateDecks.OPTIMISED`. Change one, then check it the way these were checked: put the new list in a deck file
(`{"label": "...", "cards": {"Card": 3, ...}}`), run it in a gauntlet against the catalogue and compare with the
current deck on the same opponents, 100 games or more each.
