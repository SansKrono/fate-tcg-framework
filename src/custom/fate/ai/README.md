# The Fate AI player

An AI that plays either seat (or both) of a Fate game: energy or extra draw, what to cast, what to attack,
how to block, reactions, activated abilities and the choices card effects ask for. Switch it on with

* `--ai=1`, `--ai=2` or `--ai=both` (and `--ai-level=easy|normal|hard`) after `--` on the command line:
  `godot --path . src/custom/fate/FateMain.tscn -- --ai=2 --ai-level=hard`
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
| `FateAIProfile.gd` | Weights per deck (Order aggro, Primal ramp) and level (easy: noisy, hard: wide search) |

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
