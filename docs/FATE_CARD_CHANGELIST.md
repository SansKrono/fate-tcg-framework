# Card changelist (2026-10-21 / 22)

Every card change from the Innovation and Order rebalances, in one place. The reasons and measurements are in
`docs/FATE_INNOVATION_CARDS.md` and `docs/FATE_ORDER_CARDS.md`. The catalog that holds these values is
`docs/FATE_TCG_DESIGN.md` Section 14 (generated into `src/custom/fate/FateData.gd` by `tools/gen_fate_cards.py`).

Cost notation: digits are generic mana, each `#` is one pip of the card's domain. **S/G** = Strike / Guard.

The balance was measured with the AI at **normal** strength on both sides, in both modes: doctrines on and doctrines
off (round robin of the four optimised decks, 200 games per pairing, seed `doc-h`, +-4.0 per deck):

| Deck | Doctrines on | Doctrines off |
|------|--------------|---------------|
| Goblin Foundry (Innovation) | 53.2% | 51.7% |
| Wild Stampede (Primal) | 51.5% | 50.8% |
| Abyssal Usurpers (Chaos) | 47.7% | 49.3% |
| Iron Vanguard (Order) | 47.6% | 48.1% |

The last step (the doctrine rebalance, 2026-10-22) is at the end and in `docs/FATE_DOCTRINES.md`.

## Rule change

| Rule | Before | After |
|------|--------|-------|
| Relic zone | 3 slots, no more relics once full | No limit. Starts with 3 slots and grows like the energy zone |
| Field spells | Cast only on your own field | Cast on **either** player's field. It replaces the field spell there (that one goes to its owner's discard pile). The player whose field it is in controls it ("you" in its text); the caster owns it |

## Innovation (Goblin Foundry)

### Changed cards

| Card | Type | Before | After | Why |
|------|------|--------|-------|-----|
| Goblin Ledgerkeeper | Creature, Goblin Shopkeeper | `#`, 0/1 (placeholder: the draft had no stats) | `#`, **1/2** | A 0/1 died to anything and could not attack |
| Steelwork Salvager | Creature, Goblin Engineer | `2##`, 2/1 | **`1#`, 2/2** | Nobody played a 4-mana 2/1. Now a cheap attacker that makes scrap |
| Factory Refinery | Relic | `###` | **`1#`** | Three pips were hard to cast on time |
| Rapid Scavenging | Spell | `2`: Create 2 scrap tokens | `2`: Create 2 scrap tokens. **Draw a card** | Cost a card and gave none back |

### New cards

| Card | Type | Cost | S/G | Effect |
|------|------|------|-----|--------|
| Clockwork Sentinel | Creature, Construct | `1#` | 2/2 | When it is destroyed, create 2 scrap tokens (2/3 for a while after the field spell rule, back to 2/2 in the doctrine rebalance) |
| Scrapheap Colossus | Creature, Construct | `2##` | 2/2 | Gets +1 Strike and +1 Guard for each relic you control |
| Disassemble | Spell | `2` | - | Destroy target non-unique creature an opponent controls with 3 or less in the stat of its current position. Create 2 scrap tokens |

Scripts: `FxClockworkSentinel.gd`, `FxScrapheapColossus.gd`, `FxDisassemble.gd` (new); `FxRapidScavenging.gd` (draw).

## Order (Iron Vanguard)

### Changed cards

| Card | Type | Before | After | Why |
|------|------|--------|-------|-----|
| Lucran, Divine Saviour | Unique Creature, Angel God | `5##`, 6/6 | **`3##`, 5/5** | The Order AI stops adding energy at 5, so a 7-cost god was almost never cast |
| Reinforcements | Spell | `3` | **`2`** | Two 1/1s for three mana was the worst card in the deck |

War of Attrition keeps its original text (see below). The AI casts it on the opponent's field (`harms_holder` in `FxWarofAttrition.gd`), and treats one
on its own field as a threat to replace or Smite.

### Tried and reverted

These were in earlier iterations and went back to their original stats. They are **not** changed.

| Card | Tried | Kept | Why reverted |
|------|-------|------|--------------|
| Faithful Worshiper | 1/2 | 1/1 | At 1/2 it survived the Foundry's blockers and Scrap Cannon; Order beat the Foundry 66 to 71% |
| Sigil Mage | 2/2 | 1/2 | Not needed once the other changes were in |
| Holy Healer | 2/1 | 1/1 | Not needed once the other changes were in |
| War of Attrition | Whenever a creature you control dies in combat, each opponent loses 1 life | Original text | The old effect only hurt its owner, so it was reworded. With field spells castable on the opponent, the original works as written and was restored |

## After the field spell rule

Round robin with the new rule, before any card change (seed `field-rr`): Chaos 55.7%, Order 52.4%, Primal 49.7%,
**Foundry 42.2%**. War of Attrition on the Foundry's field occupies its creatures every turn, so they can neither
attack nor use their Occupy abilities (Fabricator, Smith, Crafter), and Order won that pairing 60-40.

| Try | Change | Foundry vs Order / Primal / Chaos (100 games each) | Foundry |
|-----|--------|-----------------------------------------------------|---------|
| v1 | Clockwork Sentinel 2/3, Acquisition Fabricator `1#` | 57 / 65 / 47% | 56.3% (too strong) |
| **v2 (adopted)** | Clockwork Sentinel 2/3 | 48.5 / 48 / 56% | **50.8%** |

## Deck list changes

| Deck | Out | In |
|------|-----|----|
| Goblin Foundry (Innovation) | 3 Skulking Goblin, 3 Rustmarket Tinkerer, 1 Rarink, 1 Thrang's Crafting Table, 3 Factory Shutdown, 1 Garbage Heap | 3 Steelwork Salvager, 3 Clockwork Sentinel, 3 Scrapheap Colossus, 3 Disassemble |
| Iron Vanguard (Order) | 3 Hold the Line | 3 Righteous Guard |

Unchanged: Wild Stampede (Primal) and Abyssal Usurpers (Chaos). No Primal or Chaos card was changed.

## Doctrine rebalance (2026-10-22)

With doctrines off Chaos won 64% and Order 35%: Order's cards were tuned weak because its doctrines were the strongest
(+11.6 points), Chaos's doctrines the weakest (-10). The cards were balanced for the doctrines-off game, then the
doctrine goals so that each domain gains about the same from its doctrines. Details: `docs/FATE_DOCTRINES.md`.

### Cards

| Card | Domain | Before | After |
|------|--------|--------|-------|
| Unseen Manipulator | Chaos | `2##` | **`3##`** |
| Double Agent | Chaos | cost 2 | **cost 3** |
| Battle Ready | Order | cost 3 | **cost 2** |
| Holy Healer | Order | 1/1 | **1/2** |
| Sigil Mage | Order | 1/2 | **2/2** |
| Righteous Guard | Order | 1/1 | **1/2** |
| Moral Captain | Order | 2/2 | **2/3** |
| Tactical Combatant | Order | 3/3 | **3/4** |
| Clockwork Sentinel | Innovation | 2/3 | **2/2** |

Tried and dropped: Streetside Recruiter 2/2 (it attacked instead of making soldiers; Order lost to the Foundry 2 to 1).

### Doctrine goals (rewards unchanged)

| Doctrine | Before | After |
|----------|--------|-------|
| C2 Ensue Chaos | Devotion 5 Chaos | **Devotion 4 Chaos** |
| C3 Convert the Masses | Count control 6 | **Count control 4** |
| O2 Defend the Innocent | Devotion 5 Order | **Devotion 6 Order** |
| P2 Devote Yourself to the Wilds | Devotion 5 Primal | **Devotion 6 Primal** |
| I2 Devote Yourself to Progress | Devotion 5 Innovation | **Devotion 6 Innovation** |

Tried and dropped: Defend the Innocent as +1 Guard only, or at Devotion 7; Maintain Your Presence at 5 creatures.

