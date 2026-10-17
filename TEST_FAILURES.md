# Unit Test Failure Tracker

Tracks the failing GUT tests on the `v4-migration` branch. Each task is
self-contained: an agent should be able to pick one, fix it, run the verify
command, and tick the box.

- Source of truth for the failure list: `test-results.txt` (36 failing, an
  editor run) and a fresh headless run on 2026-10-17 (15 failing, 0 `SCRIPT ERROR`).
- Last full headless run: **273 tests, 254 passing, 15 failing, 8 risky/pending**.
- Status legend: `[ ]` open, `[x]` fixed and verified. A task is only done when
  its **Verify** command passes *and* the full suite shows no new failures.

## Progress

| Done | ID | Area | Tests | Headless | Editor run |
|------|----|------|-------|----------|------------|
| [ ] | TF-01 | Card label text updates dropped | 4 | fails | fails |
| [ ] | TF-02 | Node auto-rename / `set_name` override | 2 | fails | fails |
| [ ] | TF-03 | Pile popup sort order | 1 | fails | fails |
| [ ] | TF-04 | Pile popup scale and facing | 2 | fails | fails |
| [ ] | TF-05 | Viewport-focus duplicate rotation | 1 | fails | fails |
| [ ] | TF-06 | Face-down duplicate visibility | 1 | fails | fails |
| [ ] | TF-07 | Simulated hover / targeting | 3 | fails | fails |
| [ ] | TF-08 | `StateExecutions` card position | 1 | fails | fails |
| [ ] | TF-09 | Tests that fail only in the editor run (window size) | 21 | passes | fails |
| [ ] | TF-10 | Pending / risky tests (non-blocking) | 8 | n/a | n/a |

Counts: TF-01 to TF-08 = 15 headless failures (matches the run). TF-09 = the 21
extra failures that appear only in `test-results.txt` (36 − 15).

## How to run tests

Run from the repo root. Strip colour codes so output is greppable.

```bash
# One test script (name match, no .gd). Use the dir that contains it.
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_card_class -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Passing Tests|Failing Tests"

godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_viewport_focus -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Passing Tests|Failing Tests"

# Full suite (~6 minutes). Compare "Failing Tests" against the table above.
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -gexit > /tmp/gut_full.log 2>&1
```

Notes for agents:

- `-gtest=<file>` is ignored by this setup and runs everything. Use `-gdir` plus `-gselect`.
- Many assertions are written `assert_eq(expected, actual)` (arguments swapped
  versus GUT's `assert_eq(got, expected)`). GUT prints `[first arg] expected to
  equal [second arg]`, so **the bracket on the right is the real runtime value**.
  Example: `["Testing Name Change 1"] expected to equal ["Multiple Choices Test Card"]`
  means the card's real name is `Multiple Choices Test Card`.
- Keep `fancy_movement` off in tests that read positions (`cfc.game_settings.fancy_movement = false` in `before_all`).
- `setup_board()` / `setup_main()` in `tests/UTcommon.gd` set the root window to 1280x720.
- Cause notes are labelled **Verified** (reproduced or read directly in code) or
  **Hypothesis** (plausible, not yet proven). Confirm a hypothesis before building on it.

---

## TF-01: Card label text updates are dropped

- [ ] Fixed and verified

**Tests**
- `tests/unit/test_card_class.gd` `test_CardDefinition_properties` (line 118): Cost label is `"0"`, expected `"10"`
- `tests/unit/test_card_class.gd` `test_number_properties_with_string_value` (line 144): Cost label is `"0"`, expected `"X"`
- `tests/unit/test_card_class.gd` `test_refresh_card_front` (line 214): Abilities label still shows the default text, expected `"Property Refreshed"`
- `tests/integration/test_scripting_engine_tasks_modify_properties.gd` `TestModifyPropertiesPerProperty` (line 87): Cost label is `"5"`, expected `"7"` (the property itself is correctly 7)

**Symptom:** the card property value is right but the on-card label keeps its old text.

**Likely cause (Hypothesis):** `src/core/Card/CardFront.gd` `set_label_text` (line ~56) and
`set_rich_label_text` (line ~165) start with `if node in resizing_labels: return`. A call
that arrives while the label is mid-resize (these functions `await` frames) is silently
discarded instead of being applied later. Tests that change a property right after instancing
or scaling hit that window.

**Fix direction**
1. Confirm: log in `set_label_text` when the early return fires during one of the tests above.
2. Instead of returning, remember the newest requested value for that node (for example a
   `pending_label_values` dictionary) and re-apply it when the in-flight resize finishes.
3. Keep `scale_to()` working: it already defers `set_label_text` calls with the old text, so make
   sure a pending newer value wins over that stale text.

**Verify**
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_card_class -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_scripting_engine_tasks_modify_properties -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
```
Done when none of the four tests above fail. (`test_init_card_name` and `test_card_name_setget` in the same file are TF-02.)

---

## TF-02: Node auto-rename and the `set_name` override

- [ ] Fixed and verified

**Tests** (both in `tests/unit/test_card_class.gd`)
- `test_init_card_name` (lines 69, 74, 79): `Expected 'Test Card 8' to contain 'Test Card 1'` (also `'Test Card 9'` vs `'Test Card 2'`, `'Test Card 10'` vs `'Test Card 3'`)
- `test_card_name_setget` (lines 87, 90): after `card.set_name("Testing Name Change 1")`, `canonical_name` and the Name label are still `Multiple Choices Test Card`

**Cause, part A (Hypothesis, strongly supported):** Godot 4 makes sibling node names unique by
incrementing a trailing number. A card whose node name is `Test Card 1` becomes `Test Card 2`,
`Test Card 3` ... `Test Card 8` when siblings already use those names. The test asserts the *node
name* contains the canonical name, which can no longer be true for names ending in a digit.
The framework already compensates in `CardTemplate._init_card_name` with a regex.

**Cause, part B (Hypothesis):** `CardTemplate.set_name` (line ~1038) overrides a native Godot method
(`@warning_ignore("native_method_override")`). Godot 4 does not dispatch statically typed calls
(`var card: Card`) to a script override of a native method, so `card.set_name(...)` runs the native
version and never updates `_canonical_name` or the label.

**Fix direction**
- A: change the assertions to compare `canonical_name` and the label only, or check the node name
  with a regex that ignores trailing digits. Do not rely on the node name equalling the card name.
- B: pick one: make the test set `card.canonical_name = "..."` (the supported path, as the code comment
  already recommends), or make `set_name` unnecessary by routing through `set_card_name`. If the override
  is removed, grep `src/` for other `set_name(` callers first.

**Verify**
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_card_class -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
```
Done when `test_init_card_name` and `test_card_name_setget` pass.

---

## TF-03: Pile popup sort order

- [ ] Fixed and verified

**Test:** `tests/unit/test_pile_class.gd` `test_popup_view`
- line 65: popup order is not name-sorted (14 of 17 indexes differ)
- line 69: after the popup closes, `pile.get_all_cards()` is not back in the original `card_order` (17 of 17 differ)

**Relevant code:** `src/core/Pile.gd` `populate_popup(sorted)` (line ~142) sorts with
`CFUtils.sort_scriptables_by_name` (`src/core/CFUtils.gd` line 225), and the test builds its
expectation the same way, then `.reverse()`s it.

**Likely cause (Hypothesis):** `populate_popup` reverses `card_array` *before* sorting, and
`sort_custom` is not stable in Godot 4, so equal names (the test deck has several cards with the same
name) can come out in a different order than the test's expected list. The second failure may follow
from the first: restoring order after the popup closes relies on `pre_sorted_order`.

**Fix direction**
1. Print `popup_card_names` and `ordered_card_names` in the test to see whether the *names* differ or
   only the order of equal names.
2. If only ties differ, compare sorted name lists (order of equal names is irrelevant), or add a
   deterministic tie-break to the comparator.
3. For line 69, check that closing the popup re-slots cards using `pre_sorted_order`, and that the
   test compares card objects against the original order captured before opening.

**Verify**
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_pile_class -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
```

---

## TF-04: Pile popup scale and card facing

- [ ] Fixed and verified

**Tests** (`tests/integration/test_piles.gd`, class `TestPopupView`)
- `test_popup_discard_view` (line 99): the test expects `(0.75, 0.75)` but the card's real scale is `(0.8, 0.8)` (arguments are swapped in this assertion, see "Notes for agents")
- `test_popup_deck_view` (line 124): after the popup hides, the deck card should be face-down again but is not

**Likely cause (Hypothesis):**
- Scale: the popup now scales cards to 0.8 but the test still expects 0.75 (likely changed in the Godot 4
  migration). Decide which value is intended by checking `CFConst` and the `Pile` popup slot scale, then
  update either the code or the test. Note line 118 (same-pile case) also expects `(0.75, 0.75)` and passes,
  so check why the two paths differ.
- Facing: the "return to pile" path after the popup closes does not reapply the pile's `faceup_cards` /
  `is_faceup` rule. Check `Pile._slot_card_into_popup` and the code that runs when the popup hides.

**Fix direction:** find where popup cards are scaled (`grep -n "0.75\|0.8" src/core/Pile.gd src/core/CFConst.gd`),
confirm the intended value with the other popup assertion in the same file (line 118), then fix the facing
restore.

**Verify**
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_piles -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
```
(The `pending("Drawing a card from the pile...")` in `test_popup_discard_view` is TF-10.)

---

## TF-05: Viewport-focus duplicate keeps a small rotation

- [ ] Fixed and verified

**Test:** `tests/integration/test_viewport_focus.gd` `test_single_card_focus` (line 34):
`Control.rotation_degrees` of the focus duplicate is about `0.36` to `0.96`, expected `0.0`.
The value changes between runs, which points to a tween caught mid-flight.

**Context:** the earlier "Invalid access to property or key ... Dictionary" error in this file was a
test race and is fixed (see `_wait_for_cards_to_settle` in the test). This rotation assertion was
hidden behind it and has never run to completion before.

**Likely cause (Hypothesis):** `ViewportCardFocus.focus_card` duplicates the hand card while it still
has a fan rotation and a running `$Tween`. The duplicate's state code sets `$Control.rotation_degrees = 0`
(`CardTemplate.gd`, `CardState.VIEWPORT_FOCUS`), but a copied or restarted rotation tween then eases
it away from or back toward the hand angle.

**Fix direction**
1. In the test, print `focus_dupe.get_node("Control/..." ).rotation_degrees` over a few frames to see
   if it converges to 0 (timing) or stays off (stuck tween).
2. If it converges, wait for the dupe's own tween before asserting.
3. If stuck, stop and clear the dupe's `$Tween` after duplicating in `focus_card`, then set rotation to 0.

**Verify**
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_viewport_focus -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Passing Tests|Failing Tests"
```
Done when all 6 tests in the file pass.

---

## TF-06: Face-down duplicate not visible after re-hover

- [ ] Fixed and verified

**Test:** `tests/integration/test_facedown.gd` `test_board_facedown` (line 115): after moving the mouse
away and back, `dupe_front.visible` is false. Assertions before it in the test pass.

**Likely cause (Hypothesis):** same family as TF-05 and TF-07. The test uses `move_mouse` and then reads
`main._previously_focused_cards[card]` immediately, with no wait for the focus tween or for physics
overlap to register. A re-focused dupe may not have had `is_viewed` / front visibility reapplied (see the
`Not sure why, but sometimes the dupe card will report is_faceup` workaround in `ViewportCardFocus.focus_card`).

**Fix direction:** add a short wait (or `wait_for_signal` on the focus tween) after the second `move_mouse`,
re-run. If it still fails, the `is_viewed` / `set_is_faceup` reapply branch of `focus_card` is the suspect.

**Verify**
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_facedown -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
```

---

## TF-07: Simulated hover and targeting not registering

- [ ] Fixed and verified

**Tests**
- `tests/integration/test_targetting.gd` `test_targetting` (lines 26, 28, 31): hovered card is not highlighted, highlight colour is white, `target_object` is null
- `tests/integration/test_scripting_engine_general.gd` `TestTargetScriptOnDragFromHand` (line 181): `ArrowHead` not visible after dragging a card whose script has `is_cost` targeting
- `tests/integration/test_scripting_engine_subjects.gd` `TestSubjectTarget` (lines 23, 27): `card_rotation` is `0` after the first targeted rotate, expected `270`; then `270`, expected `90`

**Common thread (Hypothesis):** these rely on the fake mouse (`board._UT_interpolate_mouse_move`,
`move_mouse`, `target_card`) to move a pointer `Area2D` that overlaps cards. Overlap detection needs a
physics frame, and the helper waits only a fixed short time (`MOUSE_SPEED` in `tests/UTcommon.gd`).
`test_targetting` also asserts immediately after `move_mouse` with no further wait. Compare with the
working helper `execute_with_target`, which awaits a frame before returning.

**Fix direction**
1. Add `await get_tree().physics_frame` (twice) after `move_mouse` in these tests, or build that wait into
   `move_mouse` in `tests/UTcommon.gd` so every hover test benefits.
2. For `TestSubjectTarget`, the `wait_for_signal(...tween_all_completed, 0.4)` timeouts may be too short for
   the rotate tween; check whether the signal times out (GUT logs a timeout) before changing durations.
3. If a pointer-in-area check is the failing step, inspect `src/core/BoardTemplate.gd` mouse pointer handling
   for the UT branch.

**Verify**
```bash
for t in test_targetting test_scripting_engine_general test_scripting_engine_subjects; do
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=$t -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
done
```
(`TestStateExecutions` in `test_scripting_engine_general` is TF-08.)

---

## TF-08: `TestStateExecutions` card does not move to the scripted position

- [ ] Fixed and verified

**Test:** `tests/integration/test_scripting_engine_general.gd` `TestStateExecutions`
`test_state_executions` (line 101, and the earlier identical assertion at line 94): the card's
`global_position` is `(0, 0)`, expected `(100, 100)`. (Remember the swapped arguments, see "Notes for agents".)

**What the test does:** `card.execute_scripts()` for a state script that moves the card to `(100,100)`,
waits on `card._tween.tween_all_completed`, then moves the card to discard, sets
`CardState.FOCUSED_IN_POPUP`, runs the scripts again and expects the same position.

**Likely cause (Hypothesis):** `execute_scripts` is a coroutine and the test does not `await` it, so the
`tween_all_completed` wait may complete for an unrelated tween before the move task has run. Compare with
`execute_with_yield` in `tests/UTcommon.gd`. Related: `move_card_to_board` has an await between slot
lookup and `move_to` (see `ScriptingEngine.gd`), and `move_to` can start a new tween that replaces the one
being waited on.

**Fix direction:** use `await execute_with_yield(card)` (or await the scripting engine's `tasks_completed`)
instead of waiting on the card tween, then wait for the position tween, then assert. Decide on a
tolerance with `assert_almost_eq`.

**Verify**
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_scripting_engine_general -gexit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Failed\]|Failing Tests"
```

---

## TF-09: Failures that appear only in the editor run (`test-results.txt`)

- [ ] Re-run in the editor and confirm, or fix the tests so they are window-size independent

These 21 tests pass in the headless run (where `setup_board()` / `setup_main()` force the root window to
1280x720) but fail in `test-results.txt`. The reported positions match a different window size, not a logic bug.
Example: `test_anchors` expects the bottom-right pile at `x = 1130` (1280 − 150) but got `x = 1339`, i.e. the
window was about 1489 px wide.

| Test file | Tests |
|-----------|-------|
| `tests/integration/test_anchors.gd` | `test_anchor_positioning_and_groups`, `test_overlap_shift_up`, `test_overlap_shift_left`, `test_overlap_shift_right`, `test_changing_viewport_size` |
| `tests/integration/test_card_draw.gd` | `test_single_card_draw_use_rectangle`, `..._use_oval`, `test_draw_multiple_cards_slow_use_rectangle`, `..._use_oval` |
| `tests/integration/test_scaling_focus.gd` | `TestSingleCardFocus` (2), `TestNeightbourPush` (2) |
| `tests/integration/test_board_use.gd` | `TestCardBoardDrop`, `TestDropRecovery`, `TestBoardBorderBlock` |
| `tests/integration/test_attachments.gd` | `TestAttachAndSwitch`, `TestAttachmentNodeOrder` |
| `tests/integration/test_card_index.gd` | `test_table_hand_z_index` |
| `tests/integration/test_manipulation_buttons.gd` | `test_manipulation_buttons_not_messing_hand_focus` |
| `tests/integration/test_mouse_pointer.gd` | `test_highlight_priority` |

**Cause (Verified for the layout tests, Hypothesis for the rest):** the editor-embedded game window ignores
`get_tree().root.size = Vector2i(1280, 720)`, so anchor, hand-fan and viewport-border maths use the
editor's window size. `TestAttachAndSwitch` / `TestAttachmentNodeOrder` may instead have been fixed by the
`CardTemplate.gd` attachment changes (`state_finalized` resets, `DROPPING_TO_BOARD`) made after
`test-results.txt` was produced; they pass headless now.

**Fix direction**
1. Re-run the suite in the editor (GUT panel) and record which of the 21 still fail.
2. For layout tests, derive expected values from `get_viewport_rect().size` instead of hard-coded
   1280x720 numbers, or force a fixed size in tests via `get_window().content_scale_size` /
   `Window.size` plus `await get_tree().process_frame`.
3. Or document that the suite must be run headless, and keep the headless command above as the
   canonical way to run it (cheapest option).

**Verify:** in the editor, "Failing Tests" is 0 for the files in the table, or CI/headless is declared the
only supported runner in `CONTRIBUTING.md`.

---

## TF-10: Pending / risky tests (non-blocking)

- [ ] Triaged (each either implemented or deleted)

These do not fail the run but are placeholders (`pending(...)`) or assert nothing:

| File | Test | Pending message |
|------|------|-----------------|
| `test_piles.gd` `TestPopupView` | `test_popup_discard_view` | Drawing a card from the pile, picks it from the popup |
| `test_scripting_engine_general.gd` `TestBasics` | `test_basics` | Empty does not create a ScriptingEngine object |
| `test_scripting_engine_nested.gd` | `test_draw_more_cards_than_pile_max` | nested tasks (2 items) |
| `test_scripting_engine_subjects.gd` `TestSubjectPrevious` | `test_subject_previous` | filter_each_previous_subject |
| `test_scripting_engine_tasks_execute_scripts.gd` | `test_no_costs_are_paid_when_target_costs_cannot_be_paid` | 3 items |

**Done when:** each has a real assertion or is removed, and "Risky/Pending" is 0.

---

## Other log noise (not test failures)

Seen in the latest headless run, worth a look after the tasks above:
- `ERROR: Node not found: "CardChoices" (relative to ".../Board")`
- `CardFilter: Cannot compare int as strings using comparison: ge. Defaulting to 'eq' instead`
- `CardFilter: Cannot use comparisons other than 'eq' and 'ne' on string property: Abilities`
- `WARNING: 8 ObjectDB instances were leaked at exit`

## Change log

Record each completed task here (date, task ID, files changed, one line on the cause).

| Date | Task | Files | Cause / fix |
|------|------|-------|-------------|
| 2026-10-17 | (baseline) | `ScriptingEngine.gd`, `CVGridCardObject.gd`, `test_viewport_focus.gd` | Freed-node guards in async scripting; viewport-resize null guard; hand-settle wait in focus tests |
