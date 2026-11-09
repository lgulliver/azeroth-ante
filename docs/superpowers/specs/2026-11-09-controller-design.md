# Azeroth Ante: Controller Support

Date: 2026-11-09. Status: draft for approval.
Builds on v0.7.0 (the Options page and flight-path auto-open).

Legend: **[Liam]** decided by Liam. **[Call]** my call. **[Balatro]** copied from Balatro's controller layout. The layout comes from unofficial sources (balatrowiki.org/w/Controls and shortcutposters.com/games/balatro), which disagree in places.

## Intent

WoW Forever has native controller support that players can turn on. An addon that supports Forever should support controllers too. **[Liam]** A player in gamepad mode must be able to operate the whole addon without touching the mouse. **[Liam: "operate the addon in its entirety"]** On a pad it should feel like Balatro on a pad. **[Liam]**

Native controller support is a Forever feature, so Forever is the target and the only client tested with a pad. **[Liam]** Retail has the gamepad API behind a console setting with no options UI. There, the code must load and do nothing harmful. Pad play on Retail is best-effort and untested. **[Call]**

## Goals

- Every action a mouse player can take (except window move/resize, see Non-goals) is reachable from the pad: deck select (prev/next, Play), the blind screen (Play, Reroll Boss, Abandon Run), playing a hand (select cards, play, discard), the trinket row (tooltip, sell, reorder), the consumable row (Use/Sell popup), the round outcome and tally, the shop (buy cards, packs and the voucher, reroll, Next Blind), packs (pick, skip), deck view, achievements, the win/lose screen (New Run), and the queue-pop overlay (Resume). The builder should audit every `OnClick`, `OnMouseDown` and `OnEnter` in `UI/` to make sure nothing is missed. The ones found so far are in AchievementsView, CardWidget, ConsumableRow, DeckSelect, DeckView, HandView, Lifecycle, MainFrame, Outcome, PackView, Screens, Sidebar, Tally and TrinketRow.
- Anything that shows a tooltip on mouse hover also shows it when it has focus.
- Mouse play stays exactly as it is today. **[Liam]**

## Non-goals

- Moving or resizing the window from the pad. The saved position and size are enough. **[Call]**
- Taking over the pad's Menu button. It stays with WoW's game menu. **[Call]**
- A virtual mouse cursor. WoW's own gamepad cursor already exists; this is native, focus-based navigation.

## Anti-goals

- Moving the character while the player is trying to play cards. While the addon has the pad, pad input must not reach character movement or action bars.
- Trapping the player. There is always one obvious way out: B, repeated, ends with the window closed and the pad back to the character.
- Changing anything for mouse players: no new hints, highlights or layout when the pad isn't in use.

## Settings [Liam]

All three live on the existing Azeroth Ante page under Options > AddOns (`UI/Options.lua`, stored in `AzerothAnteDB.options`), and all default to **on**:

| Setting | Key | Effect |
|---|---|---|
| Open when you join a queue | `openOnQueue` | Joining a queue opens the window. |
| Open on flight paths | `openOnFlight` | Already shipped in 0.7.0. |
| Take the controller when the window opens itself | `padOnAutoOpen` | When a queue or flight opens the window, the pad drives the addon straight away. |

`openOnQueue` doesn't depend on the controller work and can ship first. With it off **[Call]**:
- joining a queue doesn't open the window;
- the queue pop still plays its sound, and still shows the overlay if the window is already open;
- accepting the queue or entering combat still closes the window, as now.

## Controller mode

**Getting in:**
- With `padOnAutoOpen` on, an automatic open (queue or flight) puts the addon in controller mode.
- A key binding, "Azeroth Ante: open / take controller", lives in WoW's Key Bindings screen under an Azeroth Ante header, and the player binds it to a pad button or combo. It opens the window if it's shut. If the window is open but not in controller mode, it enters controller mode. **[Call: one binding for both]** It needs a `Bindings.xml` and the matching `BINDING_HEADER_`/`BINDING_NAME_` globals, which must be added to `.luacheckrc` and to the allowed-globals lists in `tests/test_queue.lua` and `tests/smoke_ui.lua`.
- `/ante` keeps toggling the window. A toggle that opens the window doesn't take the pad. **[Call]**

**Getting out [Liam]:**
- B unwinds one level at a time:
  1. deselects cards;
  2. closes the open panel (deck view, achievements, a pack, the consumable popup, a trinket being moved);
  3. on the top-level screen, closes the window.
- Closing the window always hands the pad back to the character. The run is saved as today, so nothing is lost.
- Accepting a queue or entering combat closes the window as now, which also leaves controller mode. **[Call]**
- **A queue pop releases the pad.** The window and the pop overlay stay on screen, but the pad goes back to the game so the player can reach Blizzard's Accept dialog. Blizzard protects the accept calls, so the addon can't accept for them. Ready checks (`READY_CHECK`) and role checks (`LFG_ROLE_CHECK_SHOW`) also release the pad. After a declined or expired pop, the player re-enters with the binding. **[Call: otherwise a pad player could miss their queue]**
- With `openOnQueue` off and the window closed, a queue pop plays the sound but doesn't open the window. **[Call]**

**The mouse while in controller mode [Call]:** a mouse click or mouse movement over the window hides the focus highlight and button hints. The pad stays captured. The next pad press shows them again.

## Taking the pad away from the character

The intended approach is for the main frame to take gamepad buttons while in controller mode: `frame:EnableGamePadButton(true)` with `OnGamePadButtonDown`, and `EnableGamePadStick` if the stick is read directly. Per the Warcraft Wiki, these are delivered only to the top-most frame with gamepad buttons enabled.

Liam's reasoning that this works in Forever: bags and other UI are already usable with the pad. That's Blizzard's own cursor, not addon code, so the builder should confirm the API early, on the first in-game test.

**First build is a capture test [Liam tests on Forever]:** the first slice of the plan is just entering and leaving controller mode, logging pad buttons, before anything is built on top. Liam loads it in Forever and reports back.

**Left stick [Liam]:** navigation uses the left stick as well as the d-pad. Whether the stick still walks the character while the addon holds the pad is unknown until that test. If it does, stop and bring it back to Liam. Do **not** change gamepad CVars (such as the movement-stick setting) without his decision; changing the player's settings carries the risk of leaving them changed after a crash or `/reload`.

The fallback for **buttons**, if Forever doesn't block them reaching the character this way, is ConsolePort's approach: temporary override bindings (`SetOverrideBindingClick`) on the pad buttons, cleared on exit. Override bindings can't change in combat. That's fine, because entering combat already closes the window.

## Button layout [Balatro, Liam approved]

Xbox names; the PlayStation and Switch equivalents are the same physical buttons.

| Button | Does |
|---|---|
| Left stick / d-pad | Move focus. Whatever has focus shows its tooltip. |
| A | Select or deselect the focused card, or press the focused button. |
| B | Unwind (see Getting out). |
| RT | Play hand |
| LT | Discard |
| LB / RB | Sort hand by suit / by rank (new feature, see below) |
| Y | Reroll the shop on the shop screen; Reroll Boss on the blind screen when that voucher is owned |
| X | Skip the open pack. The addon has no blind skipping, so X does nothing elsewhere. |
| View / Back | Open deck view |
| Menu / Start | Left to WoW |

A shortcut button does the same thing as its on-screen button, including when that button is disabled: a disabled action does nothing, and its reason tooltip shows if it has one. **[Call]**

## Focus

- **Movement:** focus moves spatially between everything selectable on the current screen: cards in the hand, trinkets, consumables, shop offers, sidebar buttons and screen buttons. D-pad and stick both move it.
  - **[Call]** left/right moves within a row (hand, trinkets, consumables, shop offers), and up/down moves between rows.
  - The builder chooses how rows and their order are defined per screen.
- **Where focus starts on each screen [Call]:** the screen's primary button (Play, Next Blind, New Run, and so on), except during a hand, where it starts on the first card.
- **Highlight [Call]:** reuse the mouse hover look (cards lift, buttons light up, tooltips appear), plus a thin gold outline on the focused element so it's visible even on elements that don't react to hover.
- **Overlays:** when a panel opens (deck view, achievements, pack, consumable popup, queue-pop overlay), focus is trapped inside it until it closes, then returns to where it was.
- **Re-renders:** when a render replaces the focused element (a card played, an item bought), focus goes to the nearest remaining element in the same row, or to the screen default.
- **Hand animations:** pad input that would change state is ignored while a hand is resolving (flight or tally), matching the guards the mouse paths already have.

## Trinkets and consumables [Call]

- **Trinkets:** A on a trinket opens a small popup with Sell and Move, in the style of the existing consumable popup.
  - Move lifts the trinket. Left/right shifts it along the row with a live preview, A drops it, and B puts it back where it was.
  - The order is committed on drop, through the same code path as a mouse drag-reorder (`dragOrder` in `TrinketRow.lua`).
- **Consumables:** A opens the existing Use/Sell popup, and focus moves into it.

## Hand sorting (new) [Liam via the Balatro layout]

The addon has no hand sorting today. LB sorts the hand by suit and RB by rank, Balatro style.
- **Pad only [Liam]:** there are no sort buttons for mouse players, so mouse play stays exactly as it is.
- **A real reorder [Balatro]:** sorting reorders `run.hand` itself. Played cards and `ctx.held` follow `run.hand` index order (`Run.play`), and some trinkets read position (for example "retrigger the first scoring card", and the held-card `heldIndex` hooks). So the order can change scores, exactly as hand order does in Balatro.
- **The sort sticks [Call, Balatro]:** the chosen mode is stored on the run (for example `run.sortMode`, saved with it), and newly drawn cards are placed in that order. No mode means today's order, so existing saves and the seeded smoke sweep are unaffected until a sort is chosen. A save-version bump and migration may be needed.

## Button hints [Liam]

- **When they show:** in controller mode only, each shortcut's on-screen button shows its glyph, e.g. "Play Hand [RT]" or "Reroll [Y]".
- **Pad style [Liam]:** match the player's pad (Xbox, PlayStation, and so on) by following the button-icon style WoW's own gamepad settings use. The builder confirms which API or CVar exposes that. Fall back to Xbox labels.
- **Icons [Call]:** use WoW's built-in gamepad button atlas icons where they exist, and text labels otherwise.
- **Buttons must still fit:** the existing button-fit logic (`Theme.FitButton`) still applies, and the smoke test's "buttons that fit their labels" check must still pass with hints shown.

## Testing

- Unit tests for any pure focus/navigation logic (the row model, nearest-neighbour moves, re-render fallback) and for hand sorting.
- The UI smoke test (`tests/smoke_ui.lua`, with its 30-seed sweep in CI) gains a scripted controller run: a full run from deck select to the win or lose screen using only pad events through the stub. That needs `EnableGamePadButton`, `OnGamePadButtonDown` and binding stubs in `tests/wowstub.lua`.
- The README's in-game checklist gains controller checks for Forever, plus a Retail check that the addon loads and plays normally with the mouse. The Forever checks include that the character doesn't move while the addon has the pad.

## Left to the builder

- Module structure (for example a `UI/Pad.lua` focus manager, with each screen registering its focusable rows).
- Stick dead zones and key-repeat timing for held directions.
- The exact gold-outline art (an existing `Media/` texture or a new one via `tools/gen_media.py`).
- Release slicing: `openOnQueue` can ship on its own first; the rest can ship as one release or in stages.
