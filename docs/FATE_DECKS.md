# Decks of the catalogue

The deck selection screen (main menu -> *Fate Two-Player PoC*) lets each player pick one of eight decks: per domain an
**optimised** deck and a **starter** deck (`FateDecks.presets()`). Starter decks are the default lists of a domain
(`FateDecks.DECKLISTS`; Chaos and Innovation have none, so their starter is the generated deck: a plain selection
of the domain's cards). The optimised decks were built from the data of the AI simulation lab
(`src/custom/fate/sim/README.md`). The choice reaches the table through `FateGame.domain_override` and
`decklist_override`; a table opened without the screen plays Order against Primal.

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

All four optimised decks against each other, 40 games per pairing, the AI at normal strength on both sides, seats
alternating:

| Deck | Win rate |
|------|----------|
| Wild Stampede (Primal) | 61% (+-9) |
| Abyssal Usurpers (Chaos) | 52% (+-9) |
| Goblin Foundry (Innovation) | 46% (+-9) |
| Iron Vanguard (Order) | 42% (+-9) |

Things the simulations also show, useful beyond these decks:

* The player who goes first wins about two games in three, in every pairing. The seats are the biggest imbalance
  there is.
* Games last about 22 turns; a fifth end by deck-out (Innovation games, 33 turns, end that way about half the time).
* The AI spends only a third of its mana with Order and Innovation, but two thirds with Primal and Chaos: those two
  decks are the ones it plays best. Part of the gap above is AI play, not the cards.

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

A scrap and ingot engine. Cheap goblins make scrap, Acquisition Fabricator and Factory Crafter turn it into ingots and 3/3 automatons, Battle Smith arms the army with hammers and Thrang is the 6/6 finisher. Slow to start, hard to break.

3x Acquisition Fabricator, 3x Battle Smith, 3x Factory Crafter, 3x Factory Shutdown, 3x Garbage Heap, 3x Goblin Ledgerkeeper, 3x Rustmarket Tinkerer, 3x Safety Measure, 3x Scrap Cannon, 3x Scrap Recycler, 3x Skulking Goblin, 3x Steelwork Salvager, 1x Brogir, Master Artificer, 1x Rarink, Crafty Opportunist, 1x Thrang's Crafting Table, 1x Thrang, Perpetual Innovation

## Changing a deck

The lists are `FateDecks.OPTIMISED`. Change one, then check it the way these were checked: put the new list in a deck file
(`{"label": "...", "cards": {"Card": 3, ...}}`), run it in a gauntlet against the catalogue and compare with the
current deck on the same opponents, 100 games or more each.
