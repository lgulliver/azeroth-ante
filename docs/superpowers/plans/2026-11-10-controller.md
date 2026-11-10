# Controller Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In WoW Forever's gamepad mode, the whole addon can be played from the pad, Balatro style. Two new settings ship along with it: "Open when you join a queue" and "Take the controller when the window opens itself".

**Architecture:**
- **`UI/Pad.lua`** owns controller mode. Entering it enables gamepad input on the main frame. It routes each button either to a shortcut (an existing on-screen button) or to focus movement. It releases the pad on window hide, queue pop, ready check and role check.
- **`UI/PadFocus.lua`** is a small focus model over rows of frames. It handles moves, the gold outline, tooltips (by running the frame's own OnEnter/OnLeave scripts) and the fallback when a re-render replaces the focused frame.
- **`UI/PadRows.lua`** answers "what is on screen right now": the top-most context (an overlay, else the current screen), giving its rows, starting frame, shortcut buttons and back action.
- **No new game logic:** every pad action presses an existing button, or calls the function the mouse path already calls.

**Tech Stack:**
- Lua 5.1 (WoW addon).
- Tests run with LuaJIT: `tests/run.lua` (unit) and `tests/smoke_ui.lua` against `tests/wowstub.lua`.
- luacheck.

**Spec:** `docs/superpowers/specs/2026-11-09-controller-design.md`

## Global Constraints

- Forever is the target and the only client tested with a pad. On Retail the addon must load and play normally with the mouse. Guard every gamepad API call with an existence check (`if frame.EnableGamePadButton then`).
- Mouse play must not change at all. No hint, outline or layout change appears unless controller mode is active.
- Do not change any gamepad CVar (movement stick or anything else). If the first in-game test shows the stick still walks the character, stop and report to Liam.
- New saved settings go in `AzerothAnteDB.options` through `ns.UI.Options` (`UI/Options.lua`). Defaults: `openOnQueue = true`, `padOnAutoOpen = true`.
- Pad button names: `PAD1` = A, `PAD2` = B, `PAD3` = X, `PAD4` = Y, `PADLSHOULDER`/`PADRSHOULDER` = LB/RB, `PADLTRIGGER`/`PADRTRIGGER` = LT/RT, `PADDUP`/`PADDDOWN`/`PADDLEFT`/`PADDRIGHT`, `PADBACK` = View, `PADFORWARD` = Menu.
- The only new globals allowed are `BINDING_HEADER_AZEROTHANTE` and `BINDING_NAME_AZEROTHANTE_PAD`. Add them to `.luacheckrc` `globals`, to the allowed list in `tests/test_queue.lua`'s `h:load`, and to `ALLOWED_GLOBALS` in `tests/smoke_ui.lua`.
- Match the house style: two-space indent, `local _, ns = ...` header, modules on `ns.UI.*`, short why-comments, `T.test`/`T.eq` tests.
- Every task ends with all of these green: `luajit tests/run.lua`, `luajit tests/smoke_ui.lua`, `luajit tests/syntax.lua`, `luacheck AzerothAnte`.

## Review Focus

1. **Queue pop while the pad is held:** the pad must be released so Blizzard's Accept is reachable. Task 2 test `pad_releases_on_queue_pop_ready_and_role_check`.
2. **A hand resolving (tally or lifecycle animation) while the player mashes buttons:** state-changing shortcuts must do nothing, and A must only speed the animation up. Task 4 test `pad_shortcuts_ignored_while_busy`.
3. **The focused frame disappears** (card played, item bought, panel closed): focus must land on a sensible neighbour and never on a hidden frame. Task 3 test `focus_falls_back_when_frame_hidden`.
4. **Entering combat while in move mode or a popup:** the window hides, the pad is released, and a trinket being moved goes back to where it was. Task 5 test `move_mode_cancels_on_hide`.
5. **Retail or Forever without gamepad mode:** no gamepad methods on frames, so nothing errors and mouse play is untouched. Task 2 test `pad_enter_without_gamepad_api_is_harmless`.

---

### Task 1: Queue settings (`openOnQueue`, `padOnAutoOpen`)

This task ships on its own; the rest doesn't depend on it.

**Files:**
- Modify: `AzerothAnte/UI/Options.lua`: add the two defaults and two checkboxes.
- Modify: `AzerothAnte/Queue.lua`: gate the automatic show; call the pad hook on automatic opens.
- Modify: `README.md` (feature paragraph and checklist), `CHANGELOG.md` (Unreleased > Added).
- Test: `tests/test_queue.lua`.

**Interfaces:**
- Produces:
  - `Options.DEFAULTS.openOnQueue = true`, `Options.DEFAULTS.padOnAutoOpen = true`.
  - Checkbox labels "Open when you join a queue" and "Take the controller when the window opens itself", in that order before the existing flight checkbox.
  - Variable names `AZEROTHANTE_OPEN_ON_QUEUE` and `AZEROTHANTE_PAD_ON_AUTO_OPEN`.
  - `Queue.lua` calls `ns.UI.Pad.AutoEnter()` (guarded by `if ns.UI.Pad then`) right after the automatic `Main.Show()` on queue join and flight takeoff. A queue pop never takes the pad, since Task 2 releases it on a pop. Task 2 defines `AutoEnter`.

- [ ] **Step 1: Write failing tests in `tests/test_queue.lua`**
  - Give the harness a fake `ns.UI.Pad = { AutoEnter = function() record("pad") end }`.
  - Update the existing expectations wherever an automatic show now also records `"pad"`.
  - Add these tests:
    - `queue_open_on_queue_off_skips_join_show`: `AzerothAnteDB = { options = { openOnQueue = false } }`. A queued mode followed by `LFG_UPDATE` → `h.calls` is `{}`.
    - `queue_open_on_queue_off_pop_plays_sound_only_when_closed`: same option. `LFG_PROPOSAL_SHOW` → `{ "sound" }`. Then with the window shown (`h.shown = true`), `LFG_PROPOSAL_SHOW` → `{ "pause", "sound" }`. `Main.Show` is skipped because the window is already open; `ShowPaused` still runs.
    - `queue_auto_open_calls_pad_hook`: a queue join → `{ "show", "pad" }`; flight takeoff → `{ "show", "pad" }`.
    - Extend `options_fill_defaults_keep_choices_and_register_once`: the fake `Settings` now records three settings, in the order queue, pad, flight.
- [ ] **Step 2: Run** `luajit tests/run.lua test_queue`. Expected: the new tests fail.
- [ ] **Step 3: Implement the Options changes.** Defaults and three checkboxes, all inside the existing `pcall`.
- [ ] **Step 4: Implement the `Queue.lua` changes.**
  - In `emit`, the `"show"` action does nothing when `Options.Get("openOnQueue")` is false.
  - The `"pause"` action calls `Main.Show()` only when the option is on or the window is already open. It shows the overlay only if the window ends up shown. The sound always plays.
  - Call `Pad.AutoEnter()` after the automatic `Main.Show()` on queue join and flight takeoff, but not on a pop.
  - The combat-retry path (`PLAYER_REGEN_ENABLED`) obeys the same option.
- [ ] **Step 5: Run all four checks.** Expected: all pass.
- [ ] **Step 6: Commit** `feat: setting to open on queue join`.

### Task 2: Controller mode and pad capture (in-game checkpoint)

**Files:**
- Create: `AzerothAnte/UI/Pad.lua`, and add it to the TOC after `UI\Screens.lua` and before `UI\PackView.lua`.
- Create: `AzerothAnte/Bindings.xml`.
- Modify: `AzerothAnte/AzerothAnte.lua`:
  - `/ante pad` opens the window and enters controller mode;
  - plain `/ante` still toggles;
  - define the two `BINDING_` globals here.
- Modify: `tests/wowstub.lua`:
  - frame methods `EnableGamePadButton(on)`, `EnableGamePadStick(on)`, `IsGamePadButtonEnabled()`;
  - `stub.padPress(button)`, which fires `OnGamePadButtonDown` on the most recently enabled, still-visible frame;
  - `stub.noGamePad`, a flag that makes the frame lack those methods.
- Modify: `.luacheckrc`, `tests/smoke_ui.lua` `ALLOWED_GLOBALS`, `tests/test_queue.lua` allowed globals.
- Test: `tests/test_pad.lua` (new; a harness in the `test_queue.lua` style that loads `UI/Pad.lua` with fake Main/Screens), and a pad step in `tests/smoke_ui.lua`.

**Interfaces:**
- Consumes: `ns.UI.Options.Get`, `ns.UI.Main.Show/Hide/IsShown/frame`, `ns.UI.Screens.HidePaused`.
- Produces:
  - `Pad.Enter()`: shows the window if hidden, then enables gamepad input on `Main.frame`.
  - `Pad.Release()`: disables input and leaves the window up.
  - `Pad.Exit()`: `Release()` then `Main.Hide()`.
  - `Pad.IsActive() -> boolean`.
  - `Pad.AutoEnter()`: `Enter()` only if `Options.Get("padOnAutoOpen")`.
  - `Pad.OnButton(button: string)`: the dispatch entry point that tests call directly.
  - `Pad.handlers`: a table `button -> fn()` that later tasks fill in. In this task only `PAD2` (B: `Exit()`) and `PADFORWARD` (Menu: `Exit()`, since the frame swallows it while captured) are set. Any other button prints `Azeroth Ante pad: <button>` to chat. That print is the in-game capture check; Task 7 removes it.

- [ ] **Step 1: Write the failing tests in `tests/test_pad.lua`:**
  - `pad_enter_enables_input_and_exit_hides`: `Enter` → `IsActive()` true and the frame's gamepad buttons are enabled. `OnButton("PAD2")` → inactive, input disabled, `Main.Hide` called.
  - `pad_auto_enter_respects_option`: with `padOnAutoOpen = false`, `AutoEnter` leaves the pad inactive.
  - `pad_releases_on_queue_pop_ready_and_role_check`: active, then fire each of `LFG_PROPOSAL_SHOW`, `UPDATE_BATTLEFIELD_STATUS` with status `"confirm"`, `READY_CHECK` and `LFG_ROLE_CHECK_SHOW` → inactive, and the window is not hidden. For the queue pop, Pad registers the same events itself rather than depending on Queue's order.
  - `pad_releases_when_window_hides`: `Main.frame` `OnHide` → inactive.
  - `pad_enter_without_gamepad_api_is_harmless`: a frame without `EnableGamePadButton` → `Enter` doesn't error and `IsActive()` is false.
  - `slash_pad_opens_and_enters`: in `test_queue.lua`'s bootstrap harness, `SlashCmdList.AZEROTHANTE("pad")` calls the fake Pad's `Enter`, and `SlashCmdList.AZEROTHANTE("")` still toggles.
- [ ] **Step 2: Run** `luajit tests/run.lua test_pad`. Expected: FAIL, with `UI/Pad.lua` missing.
- [ ] **Step 3: Implement `UI/Pad.lua`.**
  - Hook `Main.frame` `OnHide` → `Release()` lazily on the first `Enter`, since `Main.Create` runs at `ADDON_LOADED`.
  - Wire the `OnGamePadButtonDown` script once.
- [ ] **Step 4: Write `Bindings.xml`.** One binding, `AZEROTHANTE_PAD` under header `AZEROTHANTE`, whose body runs `SlashCmdList.AZEROTHANTE("pad")`. Its display names come from `BINDING_HEADER_AZEROTHANTE = "Azeroth Ante"` and `BINDING_NAME_AZEROTHANTE_PAD = "Open / take controller"`.
- [ ] **Step 5: Add a smoke step** in `tests/smoke_ui.lua`: `/ante pad`, then `stub.padPress("PAD2")` closes the window. With `stub.noGamePad`, `/ante pad` opens the window without error.
- [ ] **Step 6: Run all four checks.** Expected: all pass.
- [ ] **Step 7: Commit** `feat: controller mode capture and binding`.
- [ ] **Step 8: CHECKPOINT. Stop and hand to Liam for an in-game test on Forever with gamepad mode on.** Report back:
  - (a) Bind "Open / take controller" and press it: the window opens.
  - (b) Each face button, d-pad direction, bumper and trigger prints its name, and the character doesn't act on them.
  - (c) The left stick: does the character walk?
  - (d) B closes the window and the pad works the character again.
  - (e) Menu: what happens.

  If (b) fails, switch capture to the spec's fallback, `SetOverrideBindingClick` on a hidden button per pad key, cleared in `Release`. If (c) shows walking, stop: that decision is Liam's (Global Constraints). Don't start Task 3 until Liam reports.

### Task 3: Focus model

**Files:**
- Create: `AzerothAnte/UI/PadFocus.lua` (in the TOC before `UI\Pad.lua`).
- Test: `tests/test_padfocus.lua`. It uses `wowstub` frames, created the way `smoke_ui.lua`'s `newWorld` does, but loads only Theme and PadFocus.

**Interfaces:**
- Produces:
  - `PadFocus.SetRows(rows: { {frame,...}, ... }, start: frame|nil)`. Drops frames that aren't `IsVisible()`, and drops empty rows. Focus goes to `start` if it's present, else to the remembered (row, column) clamped to the new rows, else to the first frame.
  - `PadFocus.Move(dir: "left"|"right"|"up"|"down") -> boolean`.
    - Left/right moves within the row and stops at the ends; there's no wrap **[Call]**.
    - Up/down moves to the adjacent row, at the column nearest the same fraction of the row's width (`math.floor((col-1)/(#from-1)*(#to-1)+0.5)+1`; a one-frame row maps to column 1).
  - `PadFocus.Current() -> frame|nil`, and `PadFocus.Clear()`.
  - `PadFocus.SetVisible(on: boolean)`: hides or shows the outline and tooltip without losing position (used for mouse use).
  - **Focus effects:**
    - Focusing a frame runs its `OnEnter` script (`frame:GetScript("OnEnter")`), which reuses the hover lift and tooltip. Leaving it runs `OnLeave`.
    - A gold outline frame (`Theme.Edge` style, `Theme.gold`, 2px, frame level above the target) is anchored to the focused frame.
- Consumes: `ns.UI.Theme`.

- [ ] **Step 1: Write the failing tests:**
  - `focus_moves_within_and_between_rows`: rows of 3 and 2 frames → right, right, right stays on (1,3); down → (2,2); up → (1,3).
  - `focus_runs_enter_and_leave_scripts`.
  - `focus_falls_back_when_frame_hidden`: on (1,2), hide that frame, `SetRows` the same rows → focus on (1,2) of the filtered row, the old (1,3). Hide the whole row → row 1 of what's left.
  - `focus_start_overrides_memory`.
  - `focus_set_visible_hides_outline_and_tooltip_but_keeps_position`.
- [ ] **Step 2: Run** `luajit tests/run.lua test_padfocus`. Expected: FAIL.
- [ ] **Step 3: Implement `UI/PadFocus.lua`.**
- [ ] **Step 4: Run all four checks.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: pad focus model`.

### Task 4: Screens, overlays and shortcuts

**Files:**
- Create: `AzerothAnte/UI/PadRows.lua` (in the TOC before `UI\Pad.lua`).
- Modify (accessors only, no behaviour change):
  - `UI/Screens.lua`: `Screens.Current() -> string|nil`, `Screens.Panel(key) -> frame|nil`, `Screens.PausedFrame() -> frame|nil`.
  - `UI/ConsumableRow.lua`: `ConsumableRow.OpenIndex() -> number|nil` and `ConsumableRow.Popup() -> frame|nil`.
  - `UI/PackView.lua`: `PackView.Frame()`.
  - `UI/DeckView.lua`: `DeckView.Panel()`.
  - `UI/HandView.lua`: `HandView.Widgets() -> {widget,...}` in hand order.
  - `UI/TrinketRow.lua`: `TrinketRow.Slots()` and `TrinketRow.SellButtons()`.
  - Plus whatever else is needed to reach a local frame. Name each accessor after the frame it returns.
- Modify: `AzerothAnte/UI/Pad.lua`: direction, A, B and shortcut handlers; refresh rows on every press and after `Main.Render`.
- Test: `tests/test_pad.lua` (dispatch, with a fake PadRows) and `tests/smoke_ui.lua` (real rows).

**Interfaces:**
- Consumes: `PadFocus.*` (Task 3), `Pad.handlers` (Task 2).
- Produces: `PadRows.Current() -> ctx` with these fields:
  - `ctx.rows`: rows for `PadFocus.SetRows`.
  - `ctx.start`: a frame or nil.
  - `ctx.back`: a function or nil. Nil means B exits controller mode.
  - `ctx.shortcuts`: a table, `button name -> Button frame`.
  - `ctx.busy`: true while `Tally.IsBusy()`, `Lifecycle.IsBusy()` or `HandView.IsBusy()`.
  - `ctx.speedUp`: a function or nil.
- **Context precedence, first match wins:**

  | Context | rows | back | shortcuts |
  |---|---|---|---|
  | Paused overlay shown | Resume | Resume | — |
  | Trinket move mode (Task 5) | — | handled by Task 5 | — |
  | Consumable popup open | Use, Sell | `ConsumableRow.Close` | — |
  | Pack open | choices; hand cards if the pack uses the hand; Skip | none (B with no selection exits) | X = Skip |
  | Deck view shown | Close | `DeckView.Hide` | View = Close |
  | Achievements shown | Close | `AchievementsView.Hide` | — |
  | Tally/Lifecycle busy | none | — | A = speedUp, which clicks the existing overlay button (`overlay:Click()`) |
  | Screen `newrun` | `<`, deck cards, `>` / Play | — | — |
  | Screen `blind` | each slot's Play, Reroll Boss / Abandon Run | — | Y = Reroll Boss when shown |
  | Screen `play` | consumables + trinkets / sell buttons / hand cards / Play, Discard, Sort Rank, Sort Suit | — | RT Play, LT Discard, LB Sort Suit, RB Sort Rank |
  | Screen `shop` | consumables + trinkets / sell buttons / card offers, packs, voucher Buy / Reroll, Next Blind | — | Y = Reroll |
  | Screen `won`/`lost` | New Run | — | — |

  On every screen, the last row is the sidebar's Deck and Achievements buttons plus the title bar's Abandon Run and close `x`. View opens deck view everywhere except `newrun`.
- **`ctx.start`:**
  - the screen's `"primary"`-variant button (`btn.themeButton == "primary"`) that is visible and enabled;
  - on `play`, the first hand card;
  - on overlays, the first frame.
- **Buttons:**
  - **Direction:** `PadFocus.Move`.
  - **A:**
    - when `busy`, `speedUp` only;
    - on a hand card, toggle selection the way the mouse does, calling the widget's `onClick` (`w:Click()`);
    - on a trinket slot, Task 5's move mode;
    - on a consumable slot, `ConsumableRow.Open(i)`;
    - on any other button, `frame:Click()`.
  - **B:** deselect cards first if any are selected (`HandView.ClearSelection` or `PackView.ClearSelection`), else `ctx.back()`, else `Pad.Exit()`.
  - **Shortcuts:** ignored while `busy`.
    - On a disabled button, nothing happens and its reason tooltip shows, by focusing it.
    - Otherwise, `btn:Click()`.

- [ ] **Step 1: Write failing dispatch tests in `tests/test_pad.lua`**, against a fake `PadRows`:
  - `pad_b_unwinds_selection_then_panel_then_window`.
  - `pad_shortcuts_ignored_while_busy`: busy ctx, RT does nothing; A calls `speedUp`.
  - `pad_disabled_shortcut_focuses_for_reason`.
  - `pad_a_clicks_focused_button`.
- [ ] **Step 2: Run** `luajit tests/run.lua test_pad`. Expected: the new tests fail.
- [ ] **Step 3: Implement the accessors and `UI/PadRows.lua`**, then the handlers in `Pad.lua`.
- [ ] **Step 4: Extend `tests/smoke_ui.lua` with a scripted controller run**, using `stub.padPress` only after `/ante pad`:
  - pick a deck, start the small blind;
  - select cards with d-pad + A; RT plays; LT discards; LB/RB sort (assert `run.sortMode`);
  - reach the shop; buy with A; Y rerolls; View toggles deck view and B closes it;
  - Next Blind; the queue-pop overlay Resume works with A;
  - continue to a win or loss, then New Run.

  Assert focus is never on a hidden frame after any press (`PadFocus.Current():IsVisible()`).
- [ ] **Step 5: Audit the UI.** List every `SetScript("OnClick"|"OnMouseDown"|"OnEnter"` in `AzerothAnte/UI` and confirm each frame appears in some context's rows, or is reachable through one (for example the voucher tooltip icons in the sidebar). Add anything missing.
- [ ] **Step 6: Run all four checks.** Expected: all pass. The 30-seed sweep runs the controller path too: `for s in $(seq 1 30); do SMOKE_SEED=$s luajit tests/smoke_ui.lua >/dev/null || echo FAIL $s; done` prints nothing.
- [ ] **Step 7: Commit** `feat: pad navigation across every screen`.

### Task 5: Trinket move mode

**Files:**
- Modify: `AzerothAnte/UI/TrinketRow.lua`: add `TrinketRow.BeginMove(index)`, `TrinketRow.ShiftMove(dir: -1|1)`, `TrinketRow.CommitMove()`, `TrinketRow.CancelMove()`, `TrinketRow.MoveIndex() -> number|nil`. They reuse the drag preview layout (`dragOrder`) and commit through the same path as a mouse drop.
- Modify: `AzerothAnte/UI/PadRows.lua`: the move-mode context. Left/right → `ShiftMove`, A → `CommitMove`, B → `CancelMove`, everything else ignored.
- Modify: `AzerothAnte/UI/Pad.lua`: A on a trinket slot → `BeginMove`.
- Test: `tests/smoke_ui.lua`, plus `tests/test_pad.lua` for dispatch.

- [ ] **Step 1: Write failing tests.**
  - In smoke, with 3 trinkets: A on trinket 1, right, right, A → `run.trinkets` order is `{2,3,1}` (by id) and saved. A on trinket 3, left, B → order unchanged.
  - In `test_pad.lua`, `move_mode_cancels_on_hide`: in move mode, `Main.frame` `OnHide` → `CancelMove` called, pad inactive.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** `CancelMove` also runs from the window `OnHide`. A render during move mode (`TrinketRow` render ends any press) also cancels.
- [ ] **Step 4: Run all four checks.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: reorder trinkets from the pad`.

### Task 6: Button hints and mouse hand-off

**Files:**
- Create: `AzerothAnte/UI/PadHints.lua` (in the TOC before `UI\Pad.lua`).
- Modify: `AzerothAnte/UI/Pad.lua`:
  - hints on when entering, off on release;
  - watch the mouse while active. In an `OnUpdate` on the main frame, a change in `GetCursorPosition()` or `IsMouseButtonDown()` → `PadFocus.SetVisible(false)` and `PadHints.SetShown(false)`.
  - the next pad press shows both again.
- Test: `tests/test_pad.lua` and the smoke "buttons that fit their labels" check.

**Interfaces:**
- Produces:
  - `PadHints.Label(button: string) -> string`: the glyph for a pad button in the player's pad style.
    - Use WoW's own gamepad label for the key if the client provides one. The builder confirms in game which call returns the style-aware icon (candidates: `GetBindingText(button)` with gamepad icon markup, or `C_GamePad` label APIs).
    - Otherwise use Xbox text: `A B X Y LB RB LT RT View`.
  - `PadHints.SetShown(on: boolean, shortcuts: ctx.shortcuts)`: appends `" [" .. Label(btn) .. "]"` to each shortcut button's text, and restores the original text when off. It goes through `SetText`, so `Theme.FitButton` re-fits the button.
- Consumes: `ctx.shortcuts` (Task 4).

- [ ] **Step 1: Write failing tests:**
  - `hints_append_and_restore_labels`: "Play" → "Play [RT]" → "Play".
  - `hints_never_shown_without_pad`.
  - `mouse_move_hides_focus_and_hints_until_next_press`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Labels that a render rewrites (for example `Skip (2 left)`) must keep their hint. Re-apply after `Main.Render` and after `PackView` refreshes.
- [ ] **Step 4: Run all four checks, plus the 30-seed sweep.** Expected: all pass. The smoke run must check button fit with hints on.
- [ ] **Step 5: Commit** `feat: pad button hints`.

### Task 7: Finish: docs, cleanup, final in-game check

**Files:**
- Modify: `AzerothAnte/UI/Pad.lua`: remove the capture-check chat print from Task 2.
- Modify: `README.md`:
  - the feature paragraph: controller support on Forever, the binding, B to close;
  - the in-game checklist: Forever pad checks covering Review Focus 1–5 and "the character doesn't move while the addon has the pad"; Retail "loads and plays with the mouse".
- Modify: `CHANGELOG.md`: Unreleased > Added.

- [ ] **Step 1: Make the edits.**
- [ ] **Step 2: Run all four checks, plus the 30-seed sweep.** Expected: all pass.
- [ ] **Step 3: Commit** `docs: controller support`.
- [ ] **Step 4: CHECKPOINT.** Liam runs the README Forever pad checklist in game before any release.
