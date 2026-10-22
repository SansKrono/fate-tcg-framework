# Fate TCG: Optimised Decks

Snapshot of `FateDecks.OPTIMISED` in `src/custom/fate/FateDecks.gd`. Each deck is 40 cards, max 3 copies per card, 1 copy of legendary cards (Gods and unique cards). MV = mana value (generic cost plus pips).

## Order: Iron Vanguard

A fast human army. Cheap soldiers, Righteous Guards and Reinforcements go wide, Moral Captain and Battle Ready send the whole line in with extra Strike, Devote Paladin adds Savage, War of Attrition keeps their army occupied, Smite removes the blocker that matters and Lucran closes the game.

| MV | Card | Copies |
|---|---|---|
| 2 | Faithful Worshiper | 3 |
| 2 | Holy Healer | 3 |
| 2 | Reinforcements | 3 |
| 2 | Righteous Guard | 3 |
| 2 | Sigil Mage | 3 |
| 2 | Smite | 3 |
| 2 | Streetside Recruiter | 3 |
| 3 | Battle Ready | 3 |
| 3 | Moral Captain | 3 |
| 3 | Recovering Resources | 3 |
| 3 | Tactical Combatant | 3 |
| 3 | War of Attrition | 2 |
| 4 | Devote Paladin | 3 |
| 4 | Zelith, Mage Justiciar | 1 |
| 5 | Lucran, Divine Saviour | 1 |
| | **Total** | **40** |

Curve: MV2 = 21, MV3 = 14, MV4 = 4, MV5 = 1.

## Primal: Wild Stampede

Big, efficient beasts on a smooth curve. Battering Ram, Beetle Brawler, Feracious Beast and Ironside Beetle hit hard with Savage, Elder Spirit and Cycle of Life ramp energy, Wraithful Treespirits and Teshra finish the game.

| MV | Card | Copies |
|---|---|---|
| 1 | Meek Minion | 3 |
| 1 | Return to Nature | 2 |
| 2 | Beetle Brawler | 3 |
| 2 | Dragon's Tooth | 3 |
| 2 | Goblin Scout Leader | 3 |
| 3 | Ancient Tree | 1 |
| 3 | Battering Ram | 3 |
| 3 | Cycle of Life | 3 |
| 3 | Elder Spirit | 3 |
| 3 | Spirit Wielder | 2 |
| 4 | Feracious Beast | 3 |
| 4 | Guardian Spirits | 2 |
| 4 | Ironside Beetle | 3 |
| 4 | Teshra's War Gauntlets | 1 |
| 5 | Wraithful Treespirits | 2 |
| 6 | No Where to Hide | 1 |
| 6 | Toll of War | 1 |
| 7 | Teshra, Primal Mother | 1 |
| | **Total** | **40** |

Curve: MV1 = 5, MV2 = 9, MV3 = 12, MV4 = 9, MV5 = 2, MV6 = 2, MV7 = 1.

## Chaos: Abyssal Usurpers

Steals the other player's army. Unseen Manipulator and Harbinger of Krelgar take their creatures, Claimed by the Abyss and Double Agent turn their attackers against them, and unblockable Specters keep the pressure on until Krelga ends it.

| MV | Card | Copies |
|---|---|---|
| 1 | Enthralled Civilian | 3 |
| 2 | Double Agent | 3 |
| 2 | Murkmist Gemstone | 3 |
| 2 | Repurpose | 2 |
| 2 | Specter of Hate | 3 |
| 2 | Unending Echo | 3 |
| 2 | Unseen Reach | 3 |
| 3 | Cultist Fanatic | 3 |
| 3 | Dockside Alter | 3 |
| 3 | Harbinger of Krelgar | 3 |
| 4 | Claimed by the Abyss | 3 |
| 4 | Dockside Ambusher | 3 |
| 4 | Ikthar, The Great Summoner | 1 |
| 4 | Unseen Manipulator | 3 |
| 7 | Krelga, Abyssal Nightmare | 1 |
| | **Total** | **40** |

Curve: MV1 = 3, MV2 = 17, MV3 = 9, MV4 = 10, MV7 = 1.

## Innovation: Goblin Foundry

A scrap engine that ends in fire. Goblins, Salvagers and Clockwork Sentinels make scrap even as they fall, Scrap Cannons turn every spare scrap into a point of damage, Factory Crafter and Battle Smith turn ingots into automatons and hammers, Scrapheap Colossus grows with every relic and Disassemble takes the small threats apart.

| MV | Card | Copies |
|---|---|---|
| 1 | Goblin Ledgerkeeper | 3 |
| 2 | Clockwork Sentinel | 3 |
| 2 | Disassemble | 3 |
| 2 | Factory Refinery | 3 |
| 2 | Garbage Heap | 2 |
| 2 | Rapid Scavenging | 3 |
| 2 | Safety Measure | 3 |
| 2 | Steelwork Salvager | 3 |
| 3 | Acquisition Fabricator | 3 |
| 3 | Battle Smith | 3 |
| 3 | Factory Crafter | 3 |
| 3 | Scrap Cannon | 3 |
| 4 | Brogir, Master Artificer | 1 |
| 4 | Scrapheap Colossus | 3 |
| 7 | Thrang, Perpetual Innovation | 1 |
| | **Total** | **40** |

Curve: MV1 = 3, MV2 = 20, MV3 = 12, MV4 = 4, MV7 = 1.

## Notes

- MV values come from the section comments in `FateDecks.gd`, not computed from card data. Order's Lucran is commented MV5 there while the older starter list comments it MV7.
- Design docs: `docs/FATE_DECKS.md`, `docs/FATE_ORDER_CARDS.md`, `docs/FATE_INNOVATION_CARDS.md`.
