# Doctrines: balance and how to add more

The doctrines of each domain (`docs/FATE_TCG_DESIGN.md` Section 10.2, generated into `FateData.DOCTRINES`), what
they did to the balance of the four optimised decks, what was changed, and how the system is meant to grow.

All numbers: round robin of the four optimised decks, AI at normal strength on both sides, seats alternating.
"Doctrines off" is the sim option `--no-doctrines` (UI: "Start with the doctrine cards" unticked): the doctrine
cards are on the table but their goals are never checked.

## The problem

| Deck | Doctrines on | Doctrines off | Doctrines worth |
|------|--------------|---------------|-----------------|
| Abyssal Usurpers (Chaos) | 54.3% | **64.3%** | -10.0 |
| Wild Stampede (Primal) | 52.3% | 49.3% | +3.0 |
| Goblin Foundry (Innovation) | 46.8% | 51.4% | -4.6 |
| Iron Vanguard (Order) | 46.4% | **34.8%** | +11.6 |

(100 games per pairing, +-5.6 per deck; seed `doc-on`.)

The doctrines did not hold Order back: Order reached them early and depended on them. Its first two are the
strongest rewards of any domain for a go-wide army (Maintain Your Presence: a free soldier every turn from turn 9 in
four games out of five; Defend the Innocent: +1/+1 to every creature, two games out of three by turn 9-10). The
decks had been balanced with doctrines on, so Order's cards were tuned weak to make up for its doctrines, and with
doctrines off nothing made up for it. Chaos was the reverse: the strongest card base, the least help from its
doctrines.

Doctrines cannot fix the "off" mode (they are not in play there), so the work went in two steps: the cards of each
deck balanced without doctrines, then the doctrine goals tuned so that every domain gains about the same from them.

## What each doctrine does in play

Before (seed `doc-a`, after the first card step) and after (final, seed `doc-h`, 200 games per pairing). Achieved =
share of games it was achieved in; turn = the average game turn (both players' turns count).

| ID | Doctrine | Goal before | Goal after | Achieved before | Achieved after | Turn after |
|----|----------|-------------|------------|-----------------|----------------|------------|
| C1 | Subtle Influence | Count control 2 | (same) | 74% | 76% | 10.9 |
| C2 | Ensue Chaos | Devotion 5 Chaos | **Devotion 4 Chaos** | 72% | 79% | 8.6 |
| C3 | Convert the Masses | Count control 6 | **Count control 4** | 5% | 31% | 14.6 |
| O1 | Maintain Your Presence | Count Creature 4 | (same) | 87% | 94% | 9.0 |
| O2 | Defend the Innocent | Devotion 5 Order | **Devotion 6 Order** | 69% | 44% | 11.2 |
| O3 | Vanquish Thine Foes | Count Creature 10 | (same) | 0% | 0.2% | - |
| P1 | Be a Fierce Presence | Power 4 | (same) | 99% | 99% | 6.8 |
| P2 | Devote Yourself to the Wilds | Devotion 5 Primal | **Devotion 6 Primal** | 72% | 60% | 13.0 |
| P3 | Channel the Spirit's Will | Ghost Count 4 | (same) | 0% | 0% | - |
| I1 | Construct the Future | Count Relic 3 | (same) | 23% | 24% | 18.6 |
| I2 | Devote Yourself to Progress | Devotion 5 Innovation | **Devotion 6 Innovation** | 87% | 78% | 10.7 |
| I3 | Produce Endlessly | Token Count 6 | (same) | 51% | 51% | 14.3 |

No reward changed. "+1 Guard only" for Defend the Innocent and Devotion 7 were tried and were too weak (Order 40 to
42% with doctrines on); Count Creature 5 for Maintain Your Presence as well.

The sim report shows this table for every run now (section DOCTRINES; "wr with / without" is the win rate of the
games where it was / was not achieved, which says as much about who was winning as about the doctrine).

## Card changes that came with it

The doctrines-off balance needed card changes (Order up, Chaos down). Full list in `docs/FATE_CARD_CHANGELIST.md`:

| Card | Before | After |
|------|--------|-------|
| Unseen Manipulator (Chaos) | `2##` | `3##` |
| Double Agent (Chaos) | cost 2 | cost 3 |
| Battle Ready (Order) | cost 3 | cost 2 |
| Holy Healer (Order) | 1/1 | 1/2 |
| Sigil Mage (Order) | 1/2 | 2/2 |
| Righteous Guard (Order) | 1/1 | 1/2 |
| Moral Captain (Order) | 2/2 | 2/3 |
| Tactical Combatant (Order) | 3/3 | 3/4 |
| Clockwork Sentinel (Innovation) | 2/3 | 2/2 (back to its first stats) |

Streetside Recruiter at 2/2 was tried and dropped: a 2/2 Recruiter attacks instead of staying home to make soldiers
(the AI values the attack above the 1/1 the ability makes), and Order lost to the Foundry 30 to 33%.

## Result

200 games per pairing, +-4.0 per deck:

| Deck | Doctrines on | Doctrines off | Doctrines worth |
|------|--------------|---------------|-----------------|
| Goblin Foundry (Innovation) | 53.2% | 51.7% | +1.5 |
| Wild Stampede (Primal) | 51.5% | 50.8% | +0.7 |
| Abyssal Usurpers (Chaos) | 47.7% | 49.3% | -1.6 |
| Iron Vanguard (Order) | 47.6% | 48.1% | -0.5 |

Doctrines-on: seed `doc-h`, 2026-10-22 (after the Ensue Chaos change). Doctrines-off: seed `doc-h`, before it (the
off mode does not read doctrines). Both modes are inside +-4 of even, and no domain gains or loses more than two
points from its doctrines. The widest matchups: Primal against Chaos 59% (doctrines on), Order against the Foundry
42% (on) / 48% (off).

## Open points

* **The tier-3 doctrines are almost never reached.** Vanquish Thine Foes (10 creatures) and Channel the Spirit's
  Will (4 Ghosts / embodying creatures: the Primal deck has almost none) never fire; Convert the Masses does in a
  third of the games now. Since every domain's tier 3 is equally out of reach, this does not tilt the balance, but
  the tier-3 rewards are not part of the game in practice. Worth a design pass (goals that a deck builds toward).
* **Construct the Future (I1) is a tier-1 doctrine reached in a quarter of the games**, late (turn 18). The
  Foundry runs 8 relics; three at once is rare.
* **Engine creatures that grow attack instead of using their engine.** Seen twice now (Goblin Ledgerkeeper at 1/2,
  Streetside Recruiter at 2/2). `FateAIMain._hold_engines` compares the ability with the creature's share of the
  attack one creature at a time; a bigger body makes the attack look better than it is.

## Adding doctrines (mix and match)

The system is data first:

1. **The card.** A row in `docs/FATE_TCG_DESIGN.md` Section 10.2 (`| X1 | Name | Goal | Reward | ... |`), then
   `python3 tools/gen_fate_cards.py`. The ID's letter is the branch (C, O, P, I), its digit the tier and faith cost.
2. **The goal.** The "Goal:" text is matched against the registered goal kinds (`FateDoctrines.register_goal`):
   Devotion N Domain, Count What N, Token Count N, Power N, Ghost Count N. A new kind is one `register_goal(kind,
   pattern, build, progress, contribution)` call (in `_register_builtin_goals`, or from the doctrine's own script);
   a new thing to count in "Count What N" is one `register_counter(what, count, contribution)`. `contribution` tells
   the AI how much a card from the hand adds, so the AI plays toward a new goal with no AI change.
3. **The reward.** A script `cards/Fx<Name>.gd` extending `cards/FateDoctrineEffect.gd`: the usual card hooks, gated
   by `active(card)`, or `on_reward_start` / `on_reward_end`. Optional `ai_reward_value(card, player_id)` tells the
   AI how much the reward is worth (default `FateAIDoctrine.REWARD`, 3 points).
4. **Which doctrines a deck plays.** By default the three of its domain (`FateDecks.doctrines_for`). A deck can name
   its own, from any domain: `"doctrines": [names]` in a preset of `FateDecks.OPTIMISED`, in a sim deck file
   (`{"label", "cards", "doctrines"}`) or a sim config deck; the table reads `FateGame.doctrine_override`.
5. **Measure it.** A round robin with and without doctrines (`--no-doctrines`), and the DOCTRINES table of the
   report. A doctrine set is balanced when the "worth" column (on minus off) is about the same for every deck.
