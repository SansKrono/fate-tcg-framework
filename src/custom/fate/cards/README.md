# Card scripts: how to give a card its rules text

The engine runs the generic rules (turns, mana, combat, keywords, reaction windows). What an individual
card DOES is a **card script**: one file per card in this folder, `Fx<CardName>.gd`, extending
`FateCardEffect`. The registry (`game.card_effects`, `FateCardEffects.gd`) finds every `Fx*.gd` at startup, so
**adding a card never touches a shared file**. Card list and exact rules text: `docs/FATE_TCG_DESIGN.md`
Section 14 (and `FateData.gd`, generated from it). Rules: `docs/FATE_RULES_SPEC.md`.

## Rules for a script

* `extends "res://src/custom/fate/cards/FateCardEffect.gd"`, **no `class_name`**, file `Fx` + the card name
  with spaces and punctuation removed (`FxSteelworkSalvager.gd`, `FxThrangPerpetualInnovation.gd`).
* `_init()` sets `card_name` to the exact FateData name (`"Steelwork Salvager"`).
* Scripts are **stateless singletons**: one instance serves every copy of the card. Keep state on the card
  (`card.set_meta`, properties), on the attack (`attack.metadata`), in the stats layer (modifiers and keyword
  grants with `source = the card`, they end when it leaves the table) or in the system that owns it
  (`game.tokens` counters, `game.limiter`, `game.control`).
* Override only what the card does. Everything defaults to nothing.
* A card script **is a keyword** for its card: all `FateKeyword` hooks work (`keywords/README.md`):
  `on_attack_declared`, `on_blocked`, `on_damage_dealt`, `on_destroyed`, `death_destination`, `can_attack`,
  `can_block`, `stat_bonus`, `on_maintenance`, `on_turn_end`, `actions` ...
* Test in `tests/integration/test_fate_fx_<name>.gd` (one file per card or a few related cards), extending
  `res://tests/FateCommon.gd`. Look at `tests/integration/test_fate_card_effects.gd` for the patterns (put cards
  in hand with `put_in_hand`, on the table with `put_creature` / `put_on_table`, mana with `fill_mana`,
  play with `game.play_from_hand(card)`).

## What FateCardEffect adds to the keyword hooks

| Hook | When |
|------|------|
| `play_problem(card, caster)` | Before anything is paid: "" if the card can be played (no legal target -> a reason) |
| `has_choice`, `candidates`, `default_choice`, `choice_problem` | A pick made when the spell resolves; goes through `game.choices` (an AI or UI answers, a default exists) |
| `pay_extra_cost(card, caster)` | "Additional cost: consume X permanents", after mana, before `resolve` |
| `resolve(card, caster, choice)` | A regular spell does its thing (then goes to the discard pile) |
| `spell_destination(card, caster)` / `spell_destination_for(host, spell)` | Where the resolved spell goes ("" = discard). The second is asked of cards on the table about other spells |
| `on_play(card)` | The card was cast from the hand and paid (after `resolve` for spells) |
| `on_enter(card)` | A permanent landed on the table by any means (played, returned, token created, control taken ...). May be a coroutine |
| `on_leave(card, destination)` | A permanent left the table; its modifiers and grants are already gone |
| `on_card_played / on_card_destroyed / on_phase / on_damage / on_energy_played / on_attack_resolved` | Watching: runs for cards on the table whoever caused the event |
| `static_keywords(host, target)`, `static_stat_bonus(host, target, stat)` | "Your creatures have ..." / "+1 Strike": queried while the card is on the table. Cheap, no side effects, never call `keywords.has` / `stats.current` on `target` from them |

Helpers: `choose(card, caster, kind, options, count, optional)` and `confirm(card, caster, prompt)` (await them),
`creatures_of(pid)`, `opponent_of(pid)`, and `make_action(...)` for activated abilities:

```gdscript
func actions(card: Card) -> Array:
	return [make_action(card, "recruit", "Recruit", "Occupy: create a 1/1 soldier",
			[game.costs.occupy()],
			func(c): game.tokens.create("Human Soldier", c.controller_id))]
```

Costs (`game.costs`, `FateCosts.gd`, full list in its header): `occupy()` (also "Tap"), `mana(n)`, `pay_domain(domain, n)`,
`consume_self()`, `consume_card(zones, filter, count, options)` (options: `controller` "you" / "opponent" / "any",
`exclude_self`, `chosen`), `consume_other_cards(zones, filter, count, chosen)`, `discard_hand_card(n)`,
`return_self_to_hand()`, `counter("scrap", n)`, `once_per_turn(key, uses, scope)`, `once_per_game(key)`,
`either(a, b)`. Filters: `filter_creature()`, `filter_type(t)`, `filter_non_token()`, `filter_token()`,
`filter_name(n)`, `filter_all([...])`. "Additional cost: consume X permanents" (`pay_extra_cost`, awaited):
`return await game.costs.cost_pay_extra(card, caster, game.costs.PERMANENT_ZONES, Callable(), x)`; promise it in
`play_problem` with `game.costs.extra_problem(...)`; "opponents consume X": `game.costs.force_consume(...)`.
Add a cost there if a card needs a new kind. List `once_per_turn` last in an ability's costs.

## The systems your script calls (each owned by one file, see the file header for the API)

| `game.` | File | For |
|---------|------|-----|
| `tokens` | `FateTokens.gd` | scrap / ingot counters, creature and relic tokens, copying tokens |
| `control` | `FateControl.gd` | take control (permanent or until end of turn) |
| `casting` | `FateCasting.gd` | flip cast, cast from the discard pile, creatures borrowed from the energy zone |
| `library` | `FateLibrary.gd` | draw, look at the top, search, shuffle, move a card to hand / deck / discard / energy |
| `equip` | `FateEquip.gd` | relics on creatures, field and world slot replacement |
| `limiter` | `FateLimiter.gd` | once per turn |
| `choices` | `FateChoices.gd` | targets and "you may" |
| `effects` | `FateEffects.gd` | destroy, deal damage (existing) |
| `stats` | `FateStats.gd` | modifiers and keyword grants (existing) |

If a system you need has no function for what your card needs, add it to that system's file (small, with a
test), do not work around it inside the card script.

## Not implemented yet (so a card that needs it cannot be finished)

See the status table in `docs/FATE_TCG_DESIGN.md` Section 17; update it when you finish a piece.

## Hints for the AI player (optional)

The AI (`src/custom/fate/ai/README.md`) reads card scripts: a spell or relic with real hooks is "live" and gets cast, one
without a script is energy fodder. Two optional methods tell it more: `ai_value(card, caster)` (what the card is worth
in hand, in points of Strike/Guard) and `ai_intent(request)` (`"harm"`, `"help"` or `"give"`: what a `choose()` is for, so
the AI picks the opponent's best creature for a removal spell and its own for a buff). Abilities built with `make_action`
are used by the AI when their costs are only Occupy, spare mana, counters or once-per-turn limits.
