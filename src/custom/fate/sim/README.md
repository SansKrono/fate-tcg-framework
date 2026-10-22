# AI simulation lab

Plays many AI-against-AI games of the real engine, in several processes at once, and reports what a designer
needs to balance the domains and their cards. Nothing is simulated or approximated: it is the same rules, cards
and AI as a real game (`docs/FATE_RULES_SPEC.md`, `src/custom/fate/ai/`), played without a person watching.

## Using it

**In the game:** main menu -> *Fate AI Simulation Lab*. Pick deck A and deck B (a domain, a deck of the catalogue, or the path of a deck
`.json` file), or tick *Round robin* to play every domain against every other (pick the deck of each domain: its default list, optimised or starter). Set the games per matchup, the
number of processes, the AI level of each deck, press *Start*. The tables fill up while the games are played;
*Stop* keeps what was played. *Earlier runs* reloads a finished run.

**From the command line** (no window, prints the report, exit code 0 when all games were played):

```
godot --headless --path . res://src/custom/fate/sim/FateSimCLI.tscn -- --decks=Order,Primal --games=40
godot --headless --path . res://src/custom/fate/sim/FateSimCLI.tscn -- --decks=all --games=20 --workers=6
```

| Argument | |
|----------|---|
| `--decks=A,B` | two decks: a domain (`Order`, `Primal`, `Chaos`, `Innovation`), a deck of the catalogue (`order_optimised`, `primal_starter` ...) or a deck `.json` file. Three or more decks play a round robin; `--decks=all` (the four domains), `optimised` and `starters` are shortcuts |
| `--against=X,Y` | a gauntlet: every deck of `--decks` plays every deck of this list, and no other pairs. The way to compare variants of a deck |
| `--discover=Domain` | deck discovery: every matchup is a new random legal deck of the domain (labelled `Domain (random)`) against the next of `--versus` (default: the four domain decks), `--samples` decks (100), `--games` per deck (2). The report adds the cards up over all samples |
| `--games=n` | games per matchup (20) |
| `--workers=n` | processes at the same time (cores - 1) |
| `--levels=normal,hard` | AI profile of deck A and deck B: a grade (novice / easy / normal / hard / expert), a skill `0..1`, a style and parameters (`"hard+aggro;caution=0.3"`), or a profile file (`res://ai_profiles/<name>.json`). The same deck against itself with two profiles measures what a profile is worth. `--list-params` prints every parameter. See `src/custom/fate/ai/README.md` and `docs/FATE_AI.md` |
| `--seed=text` | the same seed and options give the same games |
| `--turn-cap=n` | a game still going on this turn is a draw (60) |
| `--no-swap` | deck A always goes first (default: alternate, which cancels the first-player advantage) |
| `--no-doctrines` | start without the doctrine cards (their goals are never checked) |
| `--quiet` | the final report only |

A deck file is `{"label": "My Order", "cards": {"Righteous Guard": 3, ...}}` (or just the `{card: copies}` map).
It must follow the deck rules (`FateDecks.problems`: 40 cards, 3 copies, 1 of a legendary).

## What it measures

Everything is in `report.txt` of the run (and in the Report tab); `report.json` holds the same as data and
`cards.csv` the card table. Win rates leave out games nobody won and carry the half-width of their 95%
interval (`52.0% (+-9.8)`): do not balance on a number whose interval covers 50%.

* **Overall:** games, how they ended (`life`, `deck_out`, `turn_cap`, `stall`), turns (average, median, the turn
  the winner won on), the **first-player advantage**, script errors and illegal AI moves.
* **Per deck / domain:** win rate (mirror matches left out), win rate on the play and on the draw, life left,
  creatures lost, attacks that got through, share of energy spent, creatures in play, casts per turn, where
  the life lost came from (`combat` hits, `death_loss` for creatures lost, effects).
* **Per matchup:** wins both ways, draws, length - the matrix that shows which domain beats which.
* **Per card:** how often it was seen, the deck's win rate with and without it (`delta`), casts per game seen,
  how often it was played as energy or never used, the turn it comes down, damage, kills, deaths.
* **Flags**, only when the samples are big enough (30 games on both sides) and the gap is bigger than noise:
  `STRONG` / `WEAK` (delta), `FAVOURED` / `DISFAVOURED` (deck win rate), `MOSTLY-ENERGY` (the AI uses the card
  as energy: its script probably does nothing yet) and `RARELY-PLAYED`.

Read the flags as "look at this card", not as a verdict: a card drawn late in a long game looks better than it
is, and the AI plays some cards better than others.

## How it works

| File | Role |
|------|------|
| `FateSimConfig.gd` | The description of a run (decks, matchups, games, workers, seed ...), game numbering and seeds, deck files |
| `FateSimRunner.gd` | Builds a fresh table like the tests do, puts the AI on both seats, plays one game and returns its record |
| `FateSimRecorder.gd` | Listens to one game's signals (casts, damage, deaths, attacks, mana, life per turn) and builds the record |
| `FateSimErrorLog.gd` | An engine `Logger` that counts the script errors printed during a game |
| `FateSimWorker.gd/.tscn` | The main scene of one process: plays its share of the games, writes one JSON line per game |
| `FateSimCoordinator.gd` | Starts the worker processes, reads their files while they run, keeps the report, saves it |
| `FateSimReport.gd` | Pure data: aggregates records into the numbers, flags, text and CSV |
| `FateSimScreen.gd/.tscn` | The in-game screen; `FateSimCLI.gd/.tscn` the command-line entry |

**Why processes.** A table is a scene tree with global lookups (`cfc.NMAP`), so one process can play one game at
a time. Parallel games are separate Godot processes (`--headless`, uncapped frame rate), each with a share of the
games (`game % workers`). Results travel through `user://fate_sim/<run>/worker_<k>.jsonl`, so a crashed worker
loses only its unplayed games, and the raw records stay on disk for other tools.

**Reproducible.** Game `g` of a run uses the seed `"<seed>|<matchup>|<game>"` for the shuffle and the AI, so the
same options replay the same games (checked by `tests/integration/test_fate_sim_runner.gd`).

**Custom decks.** `FateGame.decklist_override` (player -> `{card: copies}`) replaces a seat's deck list for the
games started after it is set; `FateGame.domain_override` sets the domains. The runner sets both for every game.

## Files of a run

`user://fate_sim/<run_id>/` (on macOS `~/Library/Application Support/Godot/app_userdata/<project>/fate_sim/`):
`config.json`, `worker_<k>.jsonl`, and when it ends `report.txt`, `report.json`, `cards.csv`. The *Open folder*
button of the screen shows it.

## Tests

`tests/unit/test_fate_sim_report.gd` (numbering, statistics, flags, text/CSV), `tests/integration/test_fate_sim_runner.gd`
(real games, records, seeds, custom decks, error counting), `tests/integration/test_fate_sim_coordinator.gd`
(real worker processes, stop, earlier runs, the screen).

## Finding good cards and decks

* **Which cards win games?** Run a discovery (`--discover=Primal --samples=200`). Every sample is a different random
  legal deck, so the effect of a card can be separated from the rest: regress the result on the copies of each card
  in the deck (the raw records are in `worker_<k>.jsonl`; each seat has `cards.<name>.copies`). The `seen` columns of
  the report are weak in long games, when nearly every card of a 40-card deck is drawn.
* **Is this deck better than that one?** Put both in a gauntlet (`--decks=a.json,b.json --against=primal_optimised,...`)
  and compare their win rates against the same opponents. Differences below about 10 points need 100+ games per
  deck to be believed.
* The decks of the game's catalogue (`FateDecks.presets()`, picked on the deck selection screen) were built this
  way: see `docs/FATE_DECKS.md`.

## Comparing AI profiles

`--decks=primal_optimised,primal_optimised --levels="hard,normal" --games=100` plays one deck against itself with
two profiles (the seats alternate, so the first-player advantage cancels). The `MATCHUP` line is *profile A wins -
profile B wins*; each game is replayed with the same seed whatever the profiles are, so give two runs of the same
comparison the same `--seed` and compare them with a run of `normal,normal` on that seed: identical profiles do not
give 50-50 on a given seed, the difference to that run is what the profile changed. Behaviour (attacks per turn, mana
spent, creatures lost ...) per profile is in the records (`worker_<k>.jsonl`: each seat has `deck` 0/1 = profile A/B).

## Doctrines in the report

The report has a DOCTRINES section: per deck and doctrine, the share of games it was achieved in, the average game
turn it was achieved on, and the win rate of the games with and without it (also in report.json, "doctrines"). A
deck may name its own doctrines (`"doctrines": [names]` in a deck file or config deck); without them it plays its
domain's three. To see what doctrines are worth to each deck, run the same round robin with and without
`--no-doctrines` and compare (docs/FATE_DOCTRINES.md).

