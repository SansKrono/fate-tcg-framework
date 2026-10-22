# Order card inventory and rebalance

Every Order card in the game: cost, stats and what the script does. The **Original** columns show the cards before the
rebalance. The **Rebalanced** column shows what changed (blank means no change). The deck columns give the copies in
the optimised deck (Iron Vanguard, `FateDecks.OPTIMISED["Order"]`) before and after. Source of truth: the catalog in
`docs/FATE_TCG_DESIGN.md` Section 14.3 / 14.5 (generated into `src/custom/fate/FateData.gd` by `tools/gen_fate_cards.py`)
and the scripts in `src/custom/fate/cards/` and `src/custom/fate/reactions/`. This was done after the Innovation rebalance
and the lifting of the relic limit (`docs/FATE_INNOVATION_CARDS.md`), and was measured against that field.

Cost notation: digits are generic mana, and each `#` is one Order pip. **MV** = mana value. **S/G** = Strike / Guard.

## Cards

| Card | Type / subtypes | Original cost (MV) | Original S/G | Effect | **Rebalanced** | Deck before | Deck after |
|------|-----------------|--------------------|--------------|--------|----------------|-------------|------------|
| Streetside Recruiter | Creature, Human Soldier | `##` (2) | 1/2 | Occupy: create a 1/1 soldier | | 3 | 3 |
| Righteous Guard | Creature, Human Soldier | `1#` (2) | 1/1 | Enters: create a 1/1 soldier for each Righteous Guard on your field (itself included) | | - | 3 |
| Faithful Worshiper | Creature, Human Cleric | `1#` (2) | 1/1 | Consume an energy card: your creatures gain Indomitable until end of turn | *(tried at 1/2 and reverted, see below)* | 3 | 3 |
| Sigil Mage | Creature, Mage | `2` (2) | 1/2 | The first spell you cast each turn goes to your energy zone instead of the discard pile | *(tried at 2/2 and reverted)* | 3 | 3 |
| Holy Healer | Creature, Human Cleric | `2` (2) | 1/1 | Enters: return a creature from your discard pile to your hand | *(tried at 2/1 and reverted)* | 3 | 3 |
| Insightful Investigator | Creature, Human Soldier | `2` (2) | 1/2 | Enters: look at the top two cards of a player's deck; put any of them on the bottom | | - | - |
| Moral Captain | Creature, Human Soldier | `1##` (3) | 2/2 | When you attack, two target creatures gain +1 Strike until end of turn | | 3 | 3 |
| Tactical Combatant | Creature, Human Soldier | `2#` (3) | 3/3 | After it attacks, it switches to guard position | | 3 | 3 |
| Devote Paladin | Creature, Human Soldier | `2##` (4) | 4/3 | Occupy, consume an energy card: your creatures gain +1 Strike and Savage 1 until end of turn | | 3 | 3 |
| Zelith, Mage Justiciar | Unique Creature, Human Mage | `2##` (4) | 3/4 | May attack field and world spells; a spell it hits is destroyed | | 1 | 1 |
| Lucran, Divine Saviour | Unique Creature, Angel God | `5##` (7) | 6/6 | When a creature you control dies, choose: put the card in your energy zone (not tokens), or remove it and create a Soul Spear (consume: 2 damage to any target) | **`3##` (5), 5/5.** The Order AI stops adding energy at 5 cards, so a 7-cost god was cast in only 0.07 of the games it was drawn in | 1 | 1 |
| Holy Amulet | Relic | `1#` (2) | - | Equips to a creature; it gains "Occupy: add one Order energy" | | - | - |
| Spiked Barricade | Relic | `1#` (2) | - | Can block an attacker; destroys it and is discarded | | - | - |
| Reinforcements | Spell | `3` (3) | - | Create 2 soldier tokens (1/1) | **Cost `2`.** Two 1/1s for three mana was the worst card in the deck by win-rate effect (-9 to -17 points) | 3 | 3 |
| Smite | Spell | `2` (2) | - | Destroy target non-unique creature, or a field / world spell | | 3 | 3 |
| Battle Ready | Spell | `3` (3) | - | Up to 3 creatures switch to strike position and gain +1 Strike until end of turn | | 3 | 3 |
| Hold the Line | Spell (reaction) | `2` (2) | - | When your field is attacked: switch any of your creatures to guard; +1 Guard until end of turn | | 3 | - |
| Wave of Fear | Spell (reaction) | `3` (3) | - | When another player attacks, remove any number of attacking creatures from combat | | - | - |
| Recovering Resources | Spell (field) | `3` (3) | - | Once each end step, if a creature you own died this turn, you may draw a card | | 3 | 3 |
| War of Attrition | Spell (field) | `3` (3) | - | *Draft text incomplete.* Implemented as: at the start of your turn, occupy all your creatures | *Reworded in v1 to v5 (combat deaths cost the opponent life), then restored: field spells can now be cast on the opponent's field, where this hurts them.* | 2 | 2 |
| Equal Footing | Spell (world) | `4` (4) | - | At the end of each turn, a player with fewer energy cards may move a card from their discard pile to their energy zone | | - | - |

Tokens: Soldier Token (1/1 Human Soldier), Soul Spear Token (relic, consume: 2 damage to any target). Doctrines O1-O3
are unchanged.

## What was weak

From the round robin after the Innovation rebalance (no relic limit, 600 games, 300 per deck):

| Measure | Iron Vanguard | Other three |
|---------|---------------|-------------|
| Win rate | 40.0% | 50.8 to 56.3% |
| On the draw | 16% | 25 to 33% |
| Creatures lost per game | 5.1 (death loss 4.35 life) | 4.0 to 4.6 |
| Share of energy spent | 48% | 47 to 78% |

* **Two cards were never cast.** War of Attrition (0 casts, an effect that only hurt its owner) and Hold the Line (0.01
  casts per game: the AI's combat model rarely finds +1 Guard worth a card). Five of the 40 slots were energy only.
* **The finisher never arrived.** Lucran costs 7, and the Order AI profile stops adding energy at 5 cards. He stayed
  in hand in 91% of the games he was drawn.
* **Soldiers that die cost life, and that was all they did.** Each creature lost in combat costs its controller 1 life.
  Order loses more creatures than any deck, and nothing in the list turned those deaths into anything.
* **Reinforcements** (two 1/1s for three mana) had the worst win-rate effect in the deck.

## Iterations

Each version played 100 games against each of the other three optimised decks (Primal, Chaos and the rebalanced
Foundry), 300 games, no relic limit. The +- is the 95% interval.

| Version | Changes | Win rate | vs Primal / Chaos / Foundry |
|---------|---------|----------|------------------------------|
| Original | - | 40.0% (round robin) | 40 / 36 / 44% |
| v1 | War of Attrition reworded (any death), Lucran `3##` 5/5, Reinforcements cost 2, Sigil Mage 2/2, Holy Healer 2/1, Faithful Worshiper 1/2; list: Hold the Line out, War of Attrition 3, Righteous Guard 2 | 55.0% (+-5.6) | 56 / 43 / **66%** |
| v2 | Holy Healer back to 1/1; War of Attrition 2, Righteous Guard 3 | 58.7% (+-5.5) | 54 / 51 / **71%** |
| v3 | Sigil Mage back to 1/2 | 55.3% (+-5.6) | 49 / 49 / **68%** |
| v4 | War of Attrition only for deaths **in combat** (a Scrap Cannon or a Smite does not trigger it) | 56.7% (+-5.6) | 52 / 50 / **68%** |
| **v5 (adopted)** | Faithful Worshiper back to 1/1 | **54.7% (+-5.6)** | **54 / 55 / 55%** |

From v1 to v4, Order beat the Foundry by 66 to 71%. War of Attrition was the first suspect, but making it combat-only
(v4) changed nothing. A test against the Foundry only (100 games each) found the cause: without Faithful Worshiper, v4
won 56-44. Without Lucran it won 61-39 (no change). A 1/2 Worshiper survives the Foundry's blockers and Scrap Cannon,
and gives the whole army Indomitable every turn, which shuts down a deck that defends by blocking. Back at 1/1 it dies
to a single Cannon shot, and every matchup lands at 54 to 55%.

## The field after both rebalances

Round robin of the four optimised decks, no relic limit, 600 games (seed `final-order`):

| Deck | Win rate | On the play | On the draw | Before the Order rebalance |
|------|----------|-------------|-------------|---------------------------|
| Abyssal Usurpers (Chaos) | 51.7% (+-5.6) | 81% | 23% | 56.3% |
| Wild Stampede (Primal) | 50.0% (+-5.6) | 78% | 22% | 52.8% |
| Goblin Foundry (Innovation) | 49.3% (+-5.6) | 66% | 33% | 50.8% |
| **Iron Vanguard (Order)** | **49.0% (+-5.6)** | 75% | 23% | 40.0% |

| Matchup (first deck wins) | |
|---------|--|
| Order against Primal / Chaos / Foundry | 50% / 47% / 50% |
| Primal against Chaos / Foundry | 56% / 44% |
| Chaos against Foundry | 58% |

The four decks are within 2.7 points of each other: every interval covers 50%, and no matchup is outside the
+-9.6 noise of 100 games. When this work started the spread was 21 points (Chaos 57.3%, Foundry 36.1%).

## Notes

* Hold the Line is unchanged and out of the list. With the AI as it is, it is almost never cast. A stronger effect, or
  a better model in `FateAIReactions`, is what it needs, not a cost change.
* The AI keeps the profile values it had (Order: `energy_target` 5). Lucran's lower cost fits the deck to its AI instead.
* Going first still wins about 70 to 74% of games in every pairing. That is a rules question (`docs/FATE_DECKS.md`).

## Field spells on the opponent (later the same day)

Field spells can now be cast on either player's field, replacing the one there; the player whose field it is in
controls it. War of Attrition went back to its original text and the AI casts it on the opponent's field. In the
round robin that followed, the Foundry fell to 42% (its creatures are occupied every turn, so its Occupy engine
stops). Clockwork Sentinel went to 2/3 to make up for it. Final field (seed `field-final`): Chaos 53.0%, Order 49.3%,
Primal 49.0%, Foundry 48.7%. Details: `docs/FATE_CARD_CHANGELIST.md`.

