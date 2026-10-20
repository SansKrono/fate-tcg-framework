# The Fate AI player

An AI that plays either seat (or both) of a Fate game: energy or extra draw, what to cast, what to attack,
how to block, reactions, activated abilities and the choices card effects ask for. Switch it on with

* `--ai=1`, `--ai=2` or `--ai=both` (and `--ai-level=<profile>`, see "Profiles") after `--` on the command line:
  `godot --path . src/custom/fate/FateMain.tscn -- --ai=2 --ai-level="hard+aggro;caution=0.3"`
* the "AI players" row of the debug panel (F3), or in code `game.set_ai(seat, true, level)`.

With one AI seat the person stays at the bottom of the screen (the AI's hand stays hidden) and the
"Next phase" / "End turn" controls are locked during the AI's own turn. `FATE_AI_LOG=1` prints every decision
and the reason; `controller.log_lines` / `controller.problems` hold them (problems = things the engine refused,
should stay empty).

## How it decides

| File | Role |
|------|------|
| `FateAIController.gd` | One per seat. Listens to the game's signals and drives the same public API a player's clicks end in. Deferred out of signal handlers; pauses between actions (`profile.pace`) |
| `FateAISnapshot.gd` | Table -> plain data (units with stats/keywords/position, life, mana, own hand). Never contains the opponent's hand unless `profile.cheat` |
| `FateAISim.gd` | Pure-data copy of the combat rules (damage, blockers order, Savage, Indomitable ...). Parity with `FateCombat` is checked by `tests/integration/test_fate_ai_sim_parity.gd`: change both or neither |
| `FateAIEval.gd` | What a creature, life total, hand card and position are worth. Decides which cards are "live" (a card script with real hooks) or "dead" (energy fodder) |
| `FateAIEnergy.gd` | Energy or draw: a target energy count per deck, dead cards first, never draws the deck away |
| `FateAIMain.gd` | Main phase: subset search for the best set of plays the mana pays for (keeping mana for reactions), abilities, attack plan, then tilts everyone who stays home to guard |
| `FateAICombat.gd` | Attack planning (best blocks of the opponent + penalty for the counter-attack), lethal check, block assignment, damage order |
| `FateAIReactions.gd` | When to hold mana for and cast each reaction spell, by simulating with and without the effect |
| `FateAIAbilities.gd` | Embody, Force block, and the cheap safe abilities of card scripts (`plan_generic`) |
| `FateAIChoices.gd` | Answers `game.choices` (targets, picks, "you may") by inferring the intent of the choice; Savage targets |
| `FateAIProfile.gd` | The weighted player: every number the planners read, the grades (novice ... expert) and styles (aggro, control, ramp, engine, thief) that set them, and how a profile is asked for (specs, files). See "Profiles" |
| `FateAIWhatIf.gd` | "What if" for pump / removal spells and abilities (Battle Ready, Primal Wraith, Smite, Devote Paladin, Faithful Worshiper): apply the effect to the snapshot, plan the attack again, the gain is the worth |
| `FateAIDoctrine.gd` | The bonus of a play that advances the goal of a doctrine that is not achieved yet |

The attack/guard trade-off is the heart of it: attackers stay upright and cannot intercept, only guarding or
occupied creatures can (docs/FATE_RULES_SPEC.md D5, D6). The AI decides the attack in the main phase and tilts
the rest, scoring each attack plan against the opponent's best blocks and its counter-attack next turn.

## When a card gets implemented

The AI learns about cards from their scripts (`src/custom/fate/cards/Fx*.gd`):

* a spell is cast, a relic or field spell is played, only if its script defines real hooks (`resolve`, `on_enter` ...);
  cards without a script are "dead" and become energy
* optional hints on the script (`cards/FateCardEffect.gd`): `ai_value(card, caster)` what the card is worth in hand,
  `ai_intent(request)` what a choice is for ("harm", "help", "give")
* abilities made with `make_action` are used when their costs are only Occupy / mana the turn leaves spare /
  counters / once-per-turn, and the creature does not attack. Others need an entry in
  `FateAIAbilities.CARD_RULES` (card name -> Callable(game, card, action) -> bool)
* `FateAIEval.LIVE_EFFECTS` and `REACTION_VALUE` hold manual values

## Tests

`tests/unit/test_fate_ai_sim.gd` (simulator, planners), `tests/integration/test_fate_ai_cards.gd` (choices, liveness,
abilities), `test_fate_ai_selfplay.gd` (whole games, no illegal moves), `test_fate_ai_sim_parity.gd` (engine vs
simulator), `test_fate_ai_tournament.gd` (opt-in strength measure: `FATE_AI_GAMES=8`).

For many games at once - balance statistics per deck and card, in parallel processes - use the simulation lab
(`src/custom/fate/sim/README.md`).

## Profiles: the weighted player

Every decision reads its numbers from a `FateAIProfile` (`ai/FateAIProfile.gd`, the table `PARAMS`: default, range,
group, what it does; `godot --headless --path . res://src/custom/fate/sim/FateSimCLI.tscn -- --list-params` prints
it). A profile is built in layers, each overriding the one before:

1. **defaults** of `PARAMS`
2. **grade** = how well it plays (the *foresight* group): `novice`, `easy`, `normal`, `hard`, `expert`, or any skill
   `0..1` between them (numbers interpolate). Noise, search width, look-ahead turns (`lookahead` 0/1/2), slips
   (`mistake_rate`: missed lethal, forgotten reaction, unblocked attack, overlooked best play), subset search size,
   `reaction_fear` (discount for tricks the opponent may hold)
3. **style** = how it likes to play: the style of the deck's domain unless another is named (`aggro`, `control`,
   `ramp`, `engine`, `thief`, `balanced`; `legacy` is the AI before the card-knowledge features, for A/B tests). The
   hand-tuned numbers of a domain (`DOMAIN_FIXED`) win over its style
4. **overrides**: `{param: value}`, clamped to the range

Groups: `foresight` (how well it sees), `strategy` (aggression, caution, trading life for creatures, margin to
attack, guards kept home), `value` (what creatures, keywords, life, hand cards, engine pieces are worth), `mana`
(energy target, ramp, draw bias, deck race, holding reactions, spending), `combat`, `ability` (Embody, Evolve, flips,
pumps, risky costs), `domain` (steal value, evasion cap, sacrifice, flip cast).

### Asking for a profile (a "spec")

| Where | Example |
|-------|---------|
| `game.set_ai(seat, true, spec)` | `2` (a Level: 0 easy, 1 normal, 2 hard, 3 expert, 4 novice), `"hard"`, `"0.7+ramp"`, `"hard+aggro;caution=0.3"`, `{"grade": "easy", "style": "control", "params": {...}}` |
| game | `--ai-level=hard+control;guard_reserve=2` (or `--ai-profile=`) |
| sim lab | `--levels="hard+aggro;aggression=1.4,normal"` (deck A, deck B); a spec is also what a run's `levels` hold |
| file | `res://ai_profiles/<name>.json` or `user://ai_profiles/<name>.json`: `{"label": "cautious bot", "grade": "hard", "style": "control", "params": {"caution": 1.2}}`; use the file name as the spec |

Planners read `profile.<param>`; the valuation numbers travel with the snapshot (`state.w`, `profile.eval_weights()`),
so two AI seats with different profiles never share numbers. To add a knob: add it to `PARAMS`, declare the field in
`FateAIProfile.gd` (`tests/unit/test_fate_ai_profile.gd` fails when the two lists differ) and read it where it matters.

### What the AI knows about the cards

* **Abilities** (`FateAIAbilities._value`): scrap / ingot chains (rounds: `ability_rounds`), hammers, automatons,
  Scrap Cannon (face only), Recruiter, Garbage Heap, Enthralled Civilian, Ikthar ...; an engine creature stays home
  when its ability is worth more than its share of the attack (`Main._hold_engines`). Other abilities: safe costs only.
* **What-if** (`FateAIWhatIf`): pump / removal spells and the Paladin / Worshiper abilities are worth what the attack
  plan gains with them. The chooser takes the creatures the model assumed (`profile.focus`).
* **Mana makers first** (Elder Spirit, Ancient Tree), **Evolve** (Beetle Brawler arrives with Charge), **Teshra's
  flip before the attack**, **ramp toward bombs** (`energy_lookahead`, `ramp_bias`), **deck race** (no extra draws when
  the deck runs out first), **doctrine pursuit** (`doctrine_pursuit`), **Scrap Cannon burst** (`FateAIAbilities.plan_burn`,
  `Main.run` step 8b: every scrap the engine does not need goes at the opponent's life, all of it for lethal).
* **Choices**: flip casts take the dearest card, Unseen Manipulator weighs Convert against Intel, Unseen Reach picks
  the attacker the blockers would hurt most, Cultist Fanatic sacrifices only for a worthwhile card.
* **Reactions**: mana is only held for reactions the AI can score (`FateAIReactions.MODELLED`, now with Double Agent).

### Measuring

`tests/unit/test_fate_ai_profile.gd` (the table, grades, specs, the planners reading the knobs). Strength and style
differences are measured with the simulation lab: `--decks=X,X --levels="A,B"` puts two profiles of one deck against each
other (seats alternate); read the `MATCHUP` line.
