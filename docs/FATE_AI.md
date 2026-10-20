# The Fate AI: weighted players

How the AI player decides, which knobs exist, how to build players of different strength and style, and what each
domain asks of it. Code: `src/custom/fate/ai/` (its `README.md` is the file map). Measurements come from the
simulation lab (`src/custom/fate/sim/README.md`).

## 1. The idea

Every decision the AI makes reads named numbers from one **profile** (`FateAIProfile.gd`). A profile has three kinds of
parameters, set in layers:

| Layer | Question it answers | Parameters |
|-------|---------------------|-----------|
| **Grade** (novice, easy, normal, hard, expert, or a skill 0..1) | How well does it see and know? | `foresight` group (noise, search width, look-ahead, slips, fear of tricks) and the *knowledge* switches (does it value effects by simulation, chain abilities, evolve, ramp toward bombs, pursue doctrines) |
| **Style** (aggro, control, ramp, engine, thief, balanced; one per domain by default) | What does it want? | `strategy`, `value`, `mana`, `domain` groups: aggression, caution, trading, what a creature, a keyword, a card is worth, energy habits |
| **Overrides** | This exact bot | any `{param: value}` |

`godot --headless --path . res://src/custom/fate/sim/FateSimCLI.tscn -- --list-params` prints every parameter with
default, range and meaning. A profile is asked for with a *spec*: `"hard"`, `"0.7+ramp"`, `"hard+aggro;caution=0.3"`,
a dictionary, or the name of a JSON file in `res://ai_profiles/` or `user://ai_profiles/`.

```json
{"label": "patient wall", "grade": "hard", "style": "control",
 "params": {"guard_reserve": 2, "attack_margin": 1.0, "reaction_weight": 1.6}}
```

## 2. The decisions and their knobs

| Decision | Planner | What shapes it |
|----------|---------|----------------|
| Energy or draw, which card to give up | `FateAIEnergy` | `energy_target`, `max_energy`, `draw_bias`, `ramp_bias`, `energy_lookahead`, `deck_safety`, `deck_race`; card worth (`creature_value`, `spell_value`, `engine_value` ...) |
| What to cast, what mana to hold | `FateAIMain.plan_plays` | worth of every card, `mana_use_weight`, `search_items`, `doctrine_pursuit`, `effect_gain_weight`, `removal_min_target`, `pump_min_attackers`, `hold_reactions`, `opp_attack_prior`, `max_held_per_name` |
| Abilities | `FateAIAbilities`, `FateAIMain.run` | `ability_use`, `ability_risk`, `ability_margin`, `ability_rounds`, `produce_mana_first`, `use_evolve`, `flip_before_attack`, `use_embody` and friends, `energy_card_value`, `spare_energy_floor`, `scrap_burn`, `burn_reserve` |
| Who attacks, and what | `FateAICombat.plan_attack` | `aggression`, `caution`, `lookahead`, `think_width`, `search_sweeps`, `attack_margin`, `guard_reserve`, `reaction_fear`, valuation weights (`w_*`, `preserve_value`, `kill_value`, `life_*`) |
| Who blocks | `FateAICombat.plan_blocks` | the same valuation, `chump_block` (what own life is worth when defending), `search_sweeps`, `mistake_rate` |
| Reactions | `FateAIReactions` | `reaction_weight`, `reaction_price`, `reaction_value`, modelled spells only |
| Choices of card effects | `FateAIChoices` | intent of the choice, worth of the options, `steal_value`, `flip_cast_bias`, `sacrifice_willingness`, noise |

Two pieces make "knowing a card" cheap to add:

* **What-if** (`FateAIWhatIf.gd`): a pump or removal effect is applied to a copy of the table, the attack is planned
  again, and the difference in score is what the card is worth *now*. Battle Ready, Primal Wraith, Smite, Devote
  Paladin and Faithful Worshiper are modelled; others use a flat worth.
* **Ability values** (`FateAIAbilities._value`): an activated ability with a model (scrap, ingot, hammer, automaton,
  recruit, Scrap Cannon, Garbage Heap, Enthralled Civilian, Ikthar ...) is used when it is worth more than
  `ability_margin`; other abilities only when their costs are safe. Engine creatures stay out of the attack when what
  their ability makes is worth more than their share of it.

## 3. What each domain asked for

The domains were studied one by one (code reading by four research agents, then simulation). The research found these
blind spots; the status says what the weighted AI does about each.

### Order (wide army, buffs, doctrines)
| Finding | Status |
|---------|--------|
| Pump spells cast with no attack in mind, targets by body size; Smite on any token | **Fixed**: what-if worth, chooser follows the model, `removal_min_target` |
| Devote Paladin, Faithful Worshiper never used (consume-energy costs) | **Fixed**: what-if abilities, priced by `energy_card_value`, `spare_energy_floor` |
| Moral Captain's +1 Strike unknown to the attack plan | **Fixed** (two best attackers) |
| Lucran (7) stuck in hand at 5 energy | **Fixed**: `energy_lookahead` |
| Doctrines never pursued (O1/O2/O3) | **Partly**: `doctrine_pursuit` bonus for plays toward the goal (1.0 from the normal grade: Order 48.8% to 54.6%, the other domains unchanged); O3 is not in the combat simulator |
| Tokens cost a slot; Recruiter attacks instead of recruiting | **Fixed**: slots counted for creatures and relics, engine hold |
| Sigil Mage after spells, Tactical Combatant's auto-guard, Zelith's spell attacks | Open |

### Primal (ramp, Embody, Savage, Evolve)
| Finding | Status |
|---------|--------|
| Cycle of Life seen as a card that does nothing (hook list) | **Fixed** |
| Evolve (Beetle Brawler to Ironside Beetle) never used | **Fixed**: `use_evolve`, valued as the re-planned attack with Charge |
| Elder Spirit / Ancient Tree after all mana is spent | **Fixed**: `produce_mana_first` |
| Teshra's flip after the attack was planned | **Fixed**: `flip_before_attack` |
| Equipment to the best body, not the attacker | **Fixed** (`creature to equip` chooser) |
| Embody does not compete with casting | Open |
| Meek Minion, Return to Nature on own relics, Battering Ram relic targets | Open |

### Chaos (steal, flip cast, unblockable)
| Finding | Status |
|---------|--------|
| Double Agent never cast, yet mana held for it | **Fixed**: modelled; mana only held for modelled reactions |
| Flip casts picked the cheapest card; Cultist Fanatic sacrificed for anything | **Fixed**: dearest card, worth check (`flip_cast_bias`, `sacrifice_willingness`) |
| Unseen Manipulator always Convert | **Fixed**: Convert against Intel by worth (`steal_value`) |
| Unseen Reach picked a creature that is not attacking | **Fixed** (scored on the attack plan) |
| Enthralled Civilian, Ikthar unused | **Fixed**: ability values; Dockside Alter and Echo recursion open |
| Specters valued by Strike though an unblocked hit is 1 life | `evasion_cap` exists; the default is uncapped |
| Death triggers (Harbinger, Krelga, Murkmist) not in the simulator | Open |

### Innovation (scrap and ingot engine)
| Finding | Status |
|---------|--------|
| Abilities ran after the attack plan, and `enabled` was read once | **Fixed**: `ability_rounds`, re-plan of the attack after each round |
| Engine creatures attack instead of engineering | **Fixed**: engine hold (`occupy_value`) |
| Garbage Heap, Scrap Recycler (consume costs) never used | **Heap fixed**, Recycler open |
| Scrap Cannon shot at creatures | **Fixed**: face only, worth by life |
| Scrap piled up (20 to 37) while a Cannon fired three shots a turn; the Cannon pitched as energy | **Fixed**: `plan_burn` fires every scrap above `burn_reserve`, all of it for lethal (`scrap_burn`, normal grade and above); the Cannon is a live card |
| Relic slots not counted when choosing plays | **Fixed** |
| Games decided by decking | **Mitigated**: `deck_race` (no extra draws when the deck runs out first) |
| Ledgerkeeper pitched as energy | `engine_value`, `w_ability` exist (the engine style) |

## 4. Making a bot

* A weaker player: lower the grade (`easy`, `novice`) or the skill, or raise `noise` / `mistake_rate`.
* A different personality at the same strength: change the style, or the strategy parameters.
* A specific bot: write a JSON profile file and pass its name as the spec (`--levels=my_bot,hard`).
* Check a change: `--decks=D,D --levels="A,B" --games=100` puts the two profiles of deck `D` against each other, seats
  alternating; read the `MATCHUP` line (about +-10 points of noise at 100 games).

## 5. What was measured

All with the simulation lab, the optimised decks of `docs/FATE_DECKS.md`, one deck against itself with two profiles
(60 to 100 games, seats alternating; about +-10 points of noise).

| Comparison | Result (first profile wins - second wins) |
|------------|-------------------------------------------|
| easy against novice (Primal / Order / Chaos) | 43-17, 38-22, 45-15 |
| normal against easy | 47-13, 40-20, 43-17 |
| hard against normal | 30-30, 38-22, 33-27 |
| expert against hard | 33-27, 31-29, 31-29 |
| new knowledge (normal) against the old AI (`normal+legacy`) | Primal 61-39, Order 58-42, Chaos 50-50, Innovation 49-51 |
| Innovation without `deck_race` against with | 4-55 (its games last about 50 turns and end by deck-out) |
| Innovation with 8 / 10 energy against 5 / 8 | 37-23 |
| every style (balanced, control, ramp, aggro, thief) against the domain default | 46-56 out of 100: styles are personalities, not strength |
| Goblin Foundry against the other three optimised decks, with and without the Cannon burst (108 games) | 31.5% to 40.7% |
| Order against Primal, Chaos, Foundry with `doctrine_pursuit` 1 against 0 (240 games) | 54.6% against 48.8% |

So: **grades set strength** (novice < easy < normal clearly, hard and expert by smaller steps: the extra search width
and look-ahead add little because most of the strength is in knowing the cards), **styles and the strategy
parameters set behaviour**. The extremes show in the game records (attacks per turn 0.73 for an all-out attacker
against 0.20 for a passive one with three guards kept home, the attacker winning 40-20), while moderate settings leave
the win rate where it was. Order decks still spend only about 37% of their mana (Primal 85 to 90%): the cheap-card
curve, not the profile, is the limit there.

Two cautions for anybody tuning:

* The same seed gives the same shuffles whatever the profiles are, so two *identical* profiles do not score 50-50 on
  a seed (Primal, seed `sw1`: 30-50). Compare a variant with a run of `normal` against `normal` on the same seed.
* Going first wins most games (60 to 87% depending on the deck, 72% over the four optimised decks), more than any
  profile parameter or deck list does (`docs/FATE_DECKS.md`, "The field", has what rule changes do to it).
* A single-card difference between two decks or two profiles cannot be seen at 100 games (+-9 points); only the
  big levers (a win condition the AI did not use, a doctrine, a style at its extreme) show.
