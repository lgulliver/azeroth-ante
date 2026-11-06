# Trinkets Wave 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the trinket engine (state, hooks, retriggers, rules, probability, copying, reorder) and all 80 wave 1 trinkets: every **S** row in the spec plus Hearthstone.

**Architecture:**
- A new `Core/TrinketEngine.lua` owns the hook calls, copy resolution and the commit of scoring side effects.
- `Core/Scoring.lua` stays pure and works on scratch copies of the trinket instances.
- Trinket data moves to an append-only registry (`Trinkets.add`) split over `Data/Trinkets.lua` (registry and remaps) and `Data/TrinketsS.lua` (new scoring trinkets).

**Deferred to later waves:** each of these lands with the first trinkets that need it.
- Selling during a blind (spec call 6), wave 2.
- Hands, discards and hand size derived from trinkets (call 5), wave 2.
- The CREDIT_CARD, SHOWMAN, CHAOS and ASTRONOMER rules, wave 2.
- `bonusChips` and the remaining trigger points, waves 2 and 3.

**Tech Stack:** Lua 5.1 (LuaJIT for tests), WoW UI API (Retail 120100/120105, Forever 16001).

**Spec:** `docs/superpowers/specs/2026-11-07-trinkets-design.md`. Read its Engine, UI, "The 145" and "Calls made after the builder check" sections. The calls section takes precedence.

## Global Constraints

- Lua 5.1. Every file starts with `local _, ns = ...`. The only globals are `AzerothAnteDB`, `SLASH_AZEROTHANTE1` and `SlashCmdList.AZEROTHANTE`.
- `Core/` and `Data/` never call the WoW API or reference `AzerothAnteDB`.
- All randomness goes through `run.rng` or `ctx.rng`. Every listed chance goes through `ns.Prob.roll`, which consumes exactly one draw.
- Run state is plain data. The save version bumps to 4 and v3 migrates; it is never invalidated.
- Mouse only. Never the global `MouseIsOver`; use `frame:IsMouseOver()`. Feature-guard optional APIs.
- All new UI uses Theme helpers (`Theme.Inset/Raised/Button/Label/Value/Edge/Pixel`) and `Tween`.
- User-facing strings use ASCII plus "×", with gold written as "Ng", never "$".
- Trinket names, ids, rarity, cost and effect are copied **verbatim** from the spec table. Rarity values are `"common"`, `"uncommon"` and `"rare"`.
- Icons are `Interface\\Icons\\...` paths of real, well-known icons. No invented paths.
- Commit trailers:
  - Sonnet: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` + `Claude-Session: https://claude.ai/code/session_0111s9FDrYc6V71XhuzMRHhc`
  - Codex output is committed by the controller.
- Suites that must stay green: `luajit tests/run.lua`, `luajit tests/smoke_ui.lua`, `luajit tests/syntax.lua`, `python3 tests/test_media.py`.

## Review Focus

1. A speculative `Scoring.score` call (bot, tests) must never change `run.trinkets` state. Task 3 adds a test that scores the same hand twice and asserts identical results and untouched state.
2. Blueprint pointing at Blueprint, Brainstorm pointing at Blueprint pointing back, or a copier at the right edge must neither crash nor loop. Task 3 tests cycles and the edge.
3. A trinket destroyed mid-hand (Ice Cream, Seltzer) must not shift other trinkets' animations or lose their state. Task 3 asserts uids in events and the row order after commit. Task 6 smoke checks the tally runs over a destroy.
4. Loading a v3 save that is mid-blind with remapped trinkets must give every instance a uid, state and sellBonus, plus `init` state such as the Idol's rank and suit. Task 1 tests it.
5. Dragging a trinket while a hand is tallying, or dropping it outside the row, must leave the order unchanged. Task 6 smoke covers both.

---

### Task 1: Instances, registry, probability, rules, save v4

**Files:**
- Create: `AzerothAnte/Core/Prob.lua`, `AzerothAnte/Core/TrinketRules.lua`
- Modify:
  - `AzerothAnte/Data/Trinkets.lua`: add the registry API; keep the existing 20 defs for now
  - `AzerothAnte/Core/Shop.lua:24-63,108-120,168-182`
  - `AzerothAnte/Core/Packs.lua:145-152`
  - `AzerothAnte/Data/Relics.lua:20-64,230-240`
  - `AzerothAnte/Data/Scrolls.lua:25-40,200-216`
  - `AzerothAnte/Core/Scoring.lua:81-86,152-157`: Lucky and Glass go through Prob
  - `AzerothAnte/Core/Run.lua`
  - `AzerothAnte/Core/Save.lua`
  - `AzerothAnte/AzerothAnte.toc`: add `Core\Prob.lua` and `Core\TrinketRules.lua` before `Data\Trinkets.lua`
- Test: `tests/test_trinket_core.lua` (new), `tests/test_save.lua`

**Interfaces:**
- Produces:
  - `Trinkets.add(def)`: appends `def.id` to `Trinkets.order` and stores `Trinkets.def[id]`. Errors on a duplicate id.
  - `Trinkets.create(run, id, ed, paid) -> instance`: returns `{ id, ed, paid, sellBonus = 0, state = {}, uid = run.nextTrinketUid }`, increments `run.nextTrinketUid`, then calls `def.init(instance, run)` if present. Does **not** insert into `run.trinkets` and does not call `onObtain`; callers do both, as today.
  - `Trinkets.inPool(run, id) -> bool`: `def.inPool(run)` if present, else true.
  - `Shop.sellValue(trinket) -> int` = `max(1, floor((paid or baseCost)/2)) + (trinket.sellBonus or 0)`, where baseCost = def.cost + ED_COST. Scrolls.lua:29 reuses `Shop.sellValue`.
  - `Prob.mult(trinkets) -> int` = 2^(count of instances whose def.rule == "OOPS").
  - `Prob.roll(rng, trinkets, num, den) -> bool` = `RNG.next(rng) < num * Prob.mult(trinkets) / den`. Always draws once.
  - `Prob.odds(trinkets, num) -> int` = `num * Prob.mult(trinkets)`, for descriptions.
  - `TrinketRules.set(trinkets) -> table`: `{ [rule] = true }` from every instance's `def.rule`.
  - `TrinketRules.has(trinkets, rule) -> bool`.
  - `Run.moveTrinket(run, from, to) -> bool`: reorders `run.trinkets`; false if either index is invalid.
  - `run.nextTrinketUid` (starts at 1) and `run.roundHandPlays = {}`, both in `Run.new`. `roundHandPlays` resets in `startBlind`, and `Run.play` increments it after scoring.
  - `Save.VERSION = 4`.

- [ ] **Step 1: Write failing tests** in `tests/test_trinket_core.lua`:
  - `create_assigns_uid_state_sellbonus`: two creates give uids 1 and 2, `state` is `{}` and `sellBonus` is 0.
  - `create_calls_init` uses a stub def with `init = function(self) self.state.x = 7 end`.
  - `add_rejects_duplicate`.
  - `sell_value_includes_bonus`: paid 6, sellBonus 3 gives 6. With no paid, a cost 5 common gives 2.
  - `prob_roll_draws_once_and_doubles`:
    - Use a stub def with `rule = "OOPS"`. Seed the rng and record the next value. Check `roll(rng, {}, 1, 4)` against `< 0.25`.
    - Re-seed and check `roll(rng, {oops}, 1, 4)` against `< 0.5`.
    - Two oops instances give `Prob.mult == 4`.
    - At 4 in 4, the rng state still advances by exactly one.
  - `rules_set_collects_rules`.
  - `move_trinket_reorders`: `{a,b,c}`, then `move(1,3)` gives `{b,c,a}`, and `move(0,2)` gives false.
  - `all_creation_sites_use_create`: buy a shop trinket, take a Buffoon pack trinket, and use the Judgement relic. Each resulting instance has a `uid` and `state`.
  - In `tests/test_save.lua`, `v3_save_migrates_trinkets`:
    - A v3 db with `trinkets = { {id="BLOODLUST", ed=nil, paid=8} }` and no `nextTrinketUid` loads.
    - The trinket gets uid 1, state `{}`, sellBonus 0 and `init` applied, and `run.nextTrinketUid == 2` and `run.roundHandPlays` is `{}`.
- [ ] **Step 2:** Run `luajit tests/run.lua trinket_core` and `luajit tests/run.lua save`. Expected: FAIL (`attempt to call field 'create'`).
- [ ] **Step 3: Implement.**
  - Route Shop.buy, Packs (Buffoon), Relics (Judgement, Wraith, Ankh, Soul fallback) and Scrolls (trinket creators) through `Trinkets.create`. Their pools use `Trinkets.inPool`.
  - Packs entries get `paid = 0`.
  - In Scoring, Lucky becomes `Prob.roll(rng, trinkets, 1, 5)` and `Prob.roll(rng, trinkets, 1, 15)`, and Glass becomes `Prob.roll(rng, trinkets, 1, 4)`.
  - Save loads versions 2, 3 and 4. For 2 and 3, run the trinket migration after the existing v2 block.
- [ ] **Step 4:** Run all four suites. Expected: green, with old scoring tests unchanged.
- [ ] **Step 5:** Commit: `feat: trinket instances, Prob, TrinketRules, save v4`.

### Task 2: Rule-aware cards and hand evaluation

**Files:**
- Modify: `AzerothAnte/Core/Cards.lua`, `AzerothAnte/Core/HandEval.lua`
- Test: `tests/test_handeval.lua`, `tests/test_cards.lua`

**Interfaces:**
- Consumes: `TrinketRules.set` (Task 1).
- Produces:
  - `Cards.isFace(card, rules)`: with `rules.PAREIDOLIA`, every non-Stone card is a face card.
  - `Cards.hasSuit(card, suit, rules)`: with `rules.SMEARED`, H≡D and S≡C.
  - `HandEval.evaluate(cards, rules) -> handId, scoringIdx` and `HandEval.contains(cards, rules)`. `rules` is optional; nil behaves exactly as today.
- Rules handled: `FOUR_FINGERS`, `SHORTCUT`, `SMEARED`, `SPLASH`. With SPLASH, scoringIdx is every played card.

- [ ] **Step 1: Write failing tests** in `tests/test_handeval.lua`:
  - `four_fingers_flush_four_cards`: H2 H5 H9 HK + S3 with `{FOUR_FINGERS=true}` gives `FLUSH`, and scoringIdx is the 4 Hearts.
  - `four_fingers_straight_four_cards_only_played`: 5 6 7 8 played alone with FOUR_FINGERS gives `STRAIGHT`, all 4 scoring.
  - `four_fingers_straight_flush`: H5 H6 H7 H8 + S2 gives `STRAIGHT_FLUSH`, scoring the 4.
  - `shortcut_gap_straight`: 2 4 6 8 10 with `{SHORTCUT=true}` gives STRAIGHT; 2 4 6 8 11 does not; A 2 3 5 6 does.
  - `four_fingers_and_shortcut`: 3 5 7 9 + K gives STRAIGHT, scoring 3 5 7 9.
  - `smeared_flush`: H2 D5 H9 DK H3 with `{SMEARED=true}` gives FLUSH; without it, HIGH_CARD.
  - `splash_all_score`: a Pair of 7s plus 3 kickers with `{SPLASH=true}` gives PAIR, with all 5 scoring.
  - `nil_rules_unchanged`: every existing handeval test still passes.
  - In `test_cards.lua`, `pareidolia_all_face` (a 2 is face with the rule, Stone never is) and `smeared_suit`.
- [ ] **Step 2:** Run `luajit tests/run.lua handeval`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Straight detection searches the distinct ranks (Ace both 14 and 1) for a run of `need` = 4 (FOUR_FINGERS) or 5 cards, where each step is +1, or +1/+2 with SHORTCUT. Scoring cards are those forming the run, one per rank.
  - Flush: some suit is held (via `hasSuit` with rules) by at least `need` live cards. Those cards score.
  - Straight-flush detection needs both on the same card subset; take the union of the straight cards that also share the flush suit.
  - Without FOUR_FINGERS, behaviour, including the "exactly 5 live cards" requirement, is unchanged.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: all pass.
- [ ] **Step 5:** Commit: `feat: rule-aware hand evaluation (Four Fingers, Shortcut, Smeared, Splash, Pareidolia)`.

### Task 3: Trinket engine, pure scoring, commit, round end

**Files:**
- Create: `AzerothAnte/Core/TrinketEngine.lua` (TOC after `Core\Scoring.lua`'s dependencies, before `Core\Scoring.lua`), `tests/trinket_helper.lua`
- Modify:
  - `AzerothAnte/Core/Scoring.lua`
  - `AzerothAnte/Core/Run.lua:163-201` (play), `:228-272` (winBlind)
  - `AzerothAnte/Data/Trinkets.lua`: port the existing 20 to the new signatures, effects unchanged for now
- Test: `tests/test_trinket_engine.lua` (new), `tests/test_scoring.lua`, `tests/test_round_end.lua`

**Interfaces:**
- Consumes: Task 1 and Task 2 APIs.
- **Def hook signatures** (all optional). `effect` is `{ chips?, mult?, xmult?, gold?, msg?, levelHand? (bool), destroySelf? (bool) }`.
  - `before(ctx, self, isCopy) -> effect|nil`: after the hand type is known, before base chips. `levelHand` here affects this hand's base.
  - `onCard(ctx, self, card, index, isCopy) -> effect|nil`: per scoring card, per trigger.
  - `retrigger(ctx, self, card, index, isCopy) -> int|nil`: extra triggers for a scoring card.
  - `onHeld(ctx, self, card, heldIndex, isCopy) -> effect|nil`.
  - `heldRetrigger(ctx, self, card, heldIndex, isCopy) -> int|nil`: Mime.
  - `onHand(ctx, self, isCopy) -> effect|nil`.
  - `otherTrinket(ctx, self, otherDef, isCopy) -> effect|nil`: Baseball Card. Called after every trinket's onHand, before that trinket's Poly.
  - `after(ctx, self, isCopy) -> effect|nil`: after the total. Decay and `destroySelf`.
  - `onRoundEnd(run, self, isCopy) -> gold|nil`: state changes allowed only when `not isCopy`.
  - Def fields:
    - `copyable` (default true);
    - `copies = "right" | "leftmost"`, for Blueprint and Brainstorm;
    - `rule` (string);
    - `init(self, run)`;
    - `status(self, ctx_or_run) -> string|nil`;
    - `inPool(run)`.
- **ctx fields** that Run.play supplies (Scoring adds `handId`, `scoringIdx`, `rules`):
  - `cards`, `held`, `goldRef`, `handLevels`, `bossId`, `rng`, `consumables`;
  - `trinkets` (the scratch copies);
  - `handsPlayedTotal`, `isLastHand`, `discardsLeft`, `handsLeft`;
  - `handPlays` (run counts **before** this hand), `roundHandPlays` (before this hand);
  - `pileCount = #run.pile`, `trinketSlots = Run.trinketSlots(run)`.
- `TrinketEngine.source(trinkets, slot) -> instance, def | nil`: resolves copies.
  - Blueprint takes `slot+1`; Brainstorm takes slot 1.
  - Copying a copier follows the chain, with a visited set, and a cycle gives nil.
  - A non-copyable target gives nil.
  - A plain trinket returns itself.
- `TrinketEngine.each(trinkets, fn)`: calls `fn(slot, instance, def, isCopy)` for every slot whose source resolves. `isCopy` is true when the source isn't the slot's own instance.
- `Scoring.score(ctx) -> result`, with result fields:
  - `handId`, `chips`, `mult`, `total`, `events`, `gold`, `destroyed`, as today;
  - `trinketsAfter`: the scratch instances in order, with self-destroyed ones removed;
  - `levelUps = { [handId] = n }`;
  - `destroyedTrinkets = { uid, ... }`.
- **Events:** existing kinds, with `uid` added to every trinket-sourced event. New kinds:
  - `retrigger` with `slot`/`uid` when a trinket caused it;
  - `trinketMsg {slot, uid, msg}`;
  - `levelUp {handId}`;
  - `trinketDestroyed {uid}`, emitted after `total`.
- `Run.play`:
  - builds ctx from **deep copies** of `run.trinkets`;
  - commits `run.trinkets = result.trinketsAfter` and `run.handLevels[h] += n` for each levelUp;
  - increments `roundHandPlays[handId]`.
- `Run.winBlind`:
  - calls `onRoundEnd` through `TrinketEngine.each` on the real instances;
  - `payout.trinketLines = { {uid=, id=, gold=} ... }` (gold > 0 only);
  - `payout.trinkets` is their sum.
- `tests/trinket_helper.lua`, loaded with `local H = loadfile("tests/trinket_helper.lua")(ns, T)`:
  - `H.run(opts) -> run`: a fresh `Run.new(1, "ROGUE")` in phase play, with `opts.trinkets = {ids}` made via create and `opts.gold`.
  - `H.score(run, cards, held, ctxOverrides) -> result`.
  - `H.card(rank, suit, enh, ed, seal)`.

- [ ] **Step 1: Write failing tests** in `tests/test_trinket_engine.lua`, using stub defs added via `Trinkets.add` and removed in cleanup:
  - `score_is_pure`: a stub `before` increments `self.state.n`. Score twice: results are equal, `run.trinkets[1].state.n` is nil, and `result.trinketsAfter[1].state.n == 1`.
  - `before_level_affects_base`: a stub returning `{levelHand=true}` gives PAIR base chips/mult at level 2, and `levelUps.PAIR == 1`.
  - `retrigger_replays_card_step`: a stub returning 1 for every card makes a scored 5's chips count twice, with a `retrigger` event carrying `slot`.
  - `held_retrigger_mime`: a Steel held card plus a Mime stub gives ×1.5 twice.
  - `copy_right`: [Blueprint, +4 mult stub] gives +8. [Blueprint] alone gives no effect.
  - `copy_leftmost`: [+4 stub, Brainstorm] gives +8.
  - `copy_chain_and_cycle`: [Blueprint, Blueprint, +4] gives +12. [Brainstorm(1), Blueprint(2)→Brainstorm→slot1 = Brainstorm] doesn't crash and adds no effect.
  - `copy_noncopyable`: target `copyable=false` gives nothing.
  - `copy_state_not_mutated`: [Blueprint, scaling stub] increments state once, not twice, and the copy uses the source's state.
  - `baseball_order`: [uncommon stub +0 with Poly, Baseball]: mult goes +0, then ×1.5 (Baseball), then ×1.5 (Poly), with events in that order.
  - `destroy_self_after`: a stub returning `{destroySelf=true}` from `after` leaves trinketsAfter without it, and `trinketDestroyed` carries its uid after `total`.
  - `events_carry_uid`.
  - `round_end_lines`: Hearthstone (stub 4) plus Blueprint gives `trinketLines` with two entries of 4 and `payout.trinkets == 8`.
  - `card_sharp_round_counter`: roundHandPlays resets at startBlind and increments per play.
  - Existing `test_scoring.lua` and `test_round_end.lua` pass after porting their stubs to the new signatures. Assertions are unchanged.
- [ ] **Step 2:** Run `luajit tests/run.lua trinket_engine`. Expected: FAIL.
- [ ] **Step 3: Implement** `TrinketEngine.lua`, then rewrite `Scoring.score` in the spec's order:
  1. Evaluate with rules.
  2. `before` via each.
  3. Base chips/mult from (possibly levelled) levels.
  4. Scoring cards, where triggers = 1 + Red seal + Σretrigger; each trigger runs the existing card step plus every `onCard` via each.
  5. Held cards with Steel and onHeld, where triggers = 1 + Red + Σ heldRetrigger.
  6. Per trinket: edition pre, onHand, otherTrinket from every slot, edition post.
  7. Observatory.
  8. Total.
  9. `after`.
  10. Glass destroy.

  `destroySelf` applies only when `not isCopy`. Port the existing 20 defs to the new signatures with **unchanged** effects (remapping is Task 4).
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: trinket engine with pure scoring, retriggers, copying, round-end lines`.

### Task 4: Wave 1 trinkets, part A (remaps and rows 1–45)

**Files:**
- Modify: `AzerothAnte/Data/Trinkets.lua`: remap the 20 per the spec's ★ rows
- Create: `AzerothAnte/Data/TrinketsS.lua` (TOC after `Data\Trinkets.lua`)
- Test: `tests/test_trinkets_s.lua` (new)

**Interfaces:**
- Consumes: the Task 3 hook signatures, `tests/trinket_helper.lua`, `Prob.*`, `Cards.isFace(card, ctx.rules)` and `Cards.hasSuit(card, s, ctx.rules)`.
- **Scope:** the ★ remaps (rows 1, 2, 3, 4, 5, 6, 7, 9, 10, 22, 25, 27, 33, 34, 41, 53, 62, 90, 108, 145) plus the new S rows 8, 11–19, 23, 28, 29, 31, 36, 37, 39, 40, 42, 43, 44, 45.
- **Behaviour pins.** These are decisions the table doesn't settle:
  - Loyalty (BLOODLUST): `state.hands` counts hands since bought (incremented in `before` when not a copy). `onHand` gives ×4 when `hands % 6 == 0`. Status: "N remaining".
  - Misprint (LUCKY_CHARM): `mult = floor(RNG.next(ctx.rng) * 24)`.
  - Blue (FORTITUDE): `chips = 2 * ctx.pileCount`.
  - Card Sharp (AVENGING_WRATH): ×3 if `ctx.roundHandPlays[ctx.handId] >= 1`.
  - Stencil (SPIRIT_HEALER): `xmult = (ctx.trinketSlots - #ctx.trinkets) + (number of SPIRIT_HEALER instances)`. Return nil when that's ≤ 1.
  - Supernova (STARFALL): `mult = (ctx.handPlays[ctx.handId] or 0) + 1`.
  - Ride the Bus (FLIGHT_PATH): in `before`, reset `state.mult` to 0 if any scoring card is a face card (rules-aware), else add 1. `onHand` gives that mult when > 0.
  - Space Joker (TWISTING_NETHER): `before` returns `levelHand` on `Prob.roll(ctx.rng, ctx.trinkets, 1, 4)`.
  - Raised Fist (FIST_JUSTICE): the lowest `Cards.chipValue` among non-Stone held cards; on ties, the rightmost. `onHeld` fires only on that card: `mult = 2 * value`.
  - Rule trinkets (`rule =`):
    - SLEIGHT_HAND = FOUR_FINGERS, MIND_VISION = PAREIDOLIA, ARCANE_EXPLOSION = SPLASH;
    - PORTAL = SHORTCUT, MURKY_INK = SMEARED, LOADED_DICE = OOPS (both Part B);
    - all have `copyable = false`.
  - Mime (MIRROR_IMAGE): `heldRetrigger` returns 1.
  - Dusk (EVENTIDE): `retrigger` returns 1 when `ctx.isLastHand`.
  - Hack (HACK_SLASH): returns 1 for ranks 2–5.
  - Hearthstone: `onRoundEnd` returns 4.
- [ ] **Step 1: Write failing tests**, one `T.test` per trinket named `<ID>_effect`. Each builds a hand with `H.card`, scores with only that trinket, and asserts the exact chips, mult or total change implied by the spec row (plus the pins above). Also:
  - `remap_rarity_cost`: each ★ id has the spec's rarity and cost.
  - `pareidolia_with_scary_face`: Royal Guard + Mind Vision gives +30 chips on a scored 2.
  - `four_fingers_with_droll`: Elemental + Sleight of Hand gives +10 on a 4-card flush.
  - `loyalty_countdown`: hands 1–5 give no ×4, and hand 6 does.
- [ ] **Step 2:** Run `luajit tests/run.lua trinkets_s`. Expected: FAIL.
- [ ] **Step 3: Implement** the defs. Names, ids, rarity and cost come verbatim from the spec. `desc` is the spec effect text, with odds via `Prob.odds` where applicable. Each def gets an icon.
- [ ] **Step 4:** Run all four suites. Expected: green. Smoke pinned on old trinket effects may need its expected numbers updated: update them and cite the spec row in a comment.
- [ ] **Step 5:** Commit: `feat: wave 1 trinkets part A (remaps and rows 1-45)`.

### Task 5: Wave 1 trinkets, part B (rows 48–145)

**Files:**
- Modify: `AzerothAnte/Data/TrinketsS.lua`, `tests/test_trinkets_s.lua`

**Interfaces:**
- Consumes: as in Task 4.
- **Scope:** S rows 48, 49, 50, 52, 65, 69, 72, 75, 78, 82, 92, 93, 98, 99, 101, 102, 104, 109, 110, 113, 115, 116, 117, 118, 119, 122, 123, 124, 126, 127, 128, 131, 132, 133, 134, 135, 138, 140.
- **Behaviour pins:**
  - Blueprint (SCHEMATIC) and Brainstorm (MIND_CONTROL) are `copies = "right"` / `"leftmost"`, with no hooks of their own.
  - Baseball (GUILD_CHARTER): `otherTrinket` returns ×1.5 when `otherDef.rarity == "uncommon"`.
  - Ice Cream (TIGULES): `init` sets `state.chips = 100`. `after` (not a copy) subtracts 5, and gives `destroySelf` plus msg "Melted!" when it reaches ≤ 0.
  - Seltzer (MORNING_DEW): `init` sets `state.left = 10`. `retrigger` returns 1. `after` decrements, and at 0 gives `destroySelf` plus msg "Drunk!".
  - Obelisk (OBELISK): `state.x` starts at 1. In `before`, if `ctx.handId` has the strictly greatest or a tied-greatest `ctx.handPlays` count (counting this play), reset to 1; else add 0.2.
  - Wee Joker (TINY_GNOME): `onCard` on a scored 2 (not a copy) adds 8 to `state.chips` with msg "Upgrade!". `onHand` gives `chips = state.chips`.
  - Runner, Square and Spare Trousers: scale in `before`, pay in `onHand`.
  - Ancient (TITAN_RELIC) and Idol (ZANDALARI_IDOL):
    - `init` rolls a suit (Ancient), or a rank and suit from a random non-Stone deck card (Idol), using `run.rng`.
    - `onRoundEnd` (not a copy) re-rolls them and returns nil.
    - `status` shows the current suit, or rank and suit.
  - Flower Pot (PEACEBLOOM): the scoring cards can be assigned to all four suits. Natural suits come first, then each Wild covers a missing suit. Stone never counts.
  - Seeing Double (DOUBLE_VISION): a scoring card that is a Club (natural or Wild) and a different scoring card that has a non-Club suit (natural or Wild).
  - Photograph (SELFIE_CAMERA): ×2 on the first scoring face card, in scoring order and rules-aware, on every trigger of that card.
  - Hanging Chad (ECHO_DOOM): `retrigger` returns 2 for `index == ctx.scoringIdx[1]`.
  - Sock and Buskin (COURT_JESTER): returns 1 for face cards.
  - Baron: held King ×1.5. Shoot the Moon: held Queen +13. Reserved Parking: held face card, `Prob.roll` 1 in 2, gives 1g.
  - Blackboard (DARK_PACT): ×3 if every held card `hasSuit` S or C (rules-aware). An empty hand counts as true. Stone cards fail.
  - Swashbuckler: `mult` = Σ `Shop.sellValue` of the other instances.
  - Bull: `chips = 2 * max(0, ctx.goldRef.gold)`.
  - Rough Gem (UNCUT_GEM): a scored Diamond gives `gold = 1`.
  - Bloodstone: a scored Heart, on `Prob.roll` 1 in 2, gives ×1.5.
- [ ] **Step 1: Write failing tests**, one `<ID>_effect` per trinket as in Task 4. Plus:
  - `ice_cream_melts`: 20 hands lead to destroy, with trinketsAfter shrinking.
  - `seltzer_ten_hands`.
  - `blueprint_wee_joker_no_double_scale`.
  - `brainstorm_copies_baseball`: ×1.5 twice per uncommon.
  - `obelisk_resets`.
  - `idol_reroll_round_end`.
  - `oops_doubles_bloodstone`: with a forced rng sequence, a 0.6 draw triggers with Loaded Dice and not without.
- [ ] **Step 2:** Run `luajit tests/run.lua trinkets_s`. Expected: FAIL.
- [ ] **Step 3: Implement** the defs.
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: wave 1 trinkets part B (rows 48-145)`.

### Task 6: UI — reorder, tooltips, tally events, round-end lines

**Files:**
- Modify: `AzerothAnte/UI/TrinketRow.lua`, `AzerothAnte/UI/Tally.lua`, `AzerothAnte/UI/Screens.lua` (payout display and the shop/pack trinket rarity label), `AzerothAnte/UI/Theme.lua` (rarity colours, if not present)
- Test: `tests/smoke_ui.lua`

**Interfaces:**
- Consumes: `Run.moveTrinket`, `def.status`, `TrinketEngine.source`, the new event kinds and `payout.trinketLines`.
- Rarity colours: Common grey `ff9d9d9d`, Uncommon green `ff1eff00`, Rare blue `ff0070dd`.
- **Drag:**
  - Press on a slot and move more than 6px to pick the slot up. It follows the cursor horizontally, scaled 1.08.
  - The other slots tween to their new positions (0.12s).
  - On release over the row, call `Run.moveTrinket` and re-render. On release outside the row, or while `Tally.IsBusy()`, snap back with no change.
  - A click without a drag keeps its current behaviour (sell mode, tooltip).
- **Tooltip lines:**
  1. Name, coloured by rarity.
  2. Rarity word.
  3. desc.
  4. `status` (if any), in green.
  5. "Copies: <name>" or "Copies: nothing (incompatible)" for copiers.
  6. Sell value when in sell mode.
- **Tally:**
  - A `retrigger` with `slot` pulses that trinket and shows "Again!" over the card.
  - `trinketMsg` floats `msg` over the slot.
  - `levelUp` floats "Level up!" over the hand label.
  - `trinketDestroyed` fades and shrinks the slot whose uid matches (0.3s). The row re-renders after the tally completes.
  - Every trinket-slot lookup uses `uid`, not the index.
- **Round end:** the payout panel shows one line per `trinketLines` entry, "<name> +Ng", instead of a single trinkets line.

- [ ] **Step 1: Write failing smoke steps** in `tests/smoke_ui.lua`:
  - `trinket_drag_reorder`: simulate mouse down on slot 1, move past 6px to slot 3's x, and mouse up. `run.trinkets` order changes accordingly.
  - `trinket_drag_busy_noop`: while a tally is in progress, the same drag leaves the order unchanged.
  - `trinket_drag_outside_noop`.
  - `tooltip_status_and_copies`: hovering Flight Path shows its status line, and hovering a Blueprint next to Arcane Intellect shows "Copies: Arcane Intellect".
  - `tally_destroy_ice_cream`: with Ice Cream at 5 chips, play a hand. The tally completes without error, the slot is gone, and the other trinket keeps its slot and state.
  - `round_end_lines`: Hearthstone plus Blueprint shows two lines of "+4g".
- [ ] **Step 2:** Run `luajit tests/smoke_ui.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** If the stub lacks something the drag needs, extend `tests/wowstub.lua` with the minimal mouse and cursor stubs (`GetCursorPosition`, `OnMouseDown`/`OnMouseUp`/`OnUpdate`).
- [ ] **Step 4:** Run all four suites, plus `for s in $(seq 1 30); do SMOKE_SEED=$s luajit tests/smoke_ui.lua >/dev/null || echo fail $s; done`. Expected: green, with no "fail" lines.
- [ ] **Step 5:** Commit: `feat: trinket drag reorder, live tooltips, tally trinket events`.

### Task 7: Integration — sim, discovery thresholds, README, version

**Files:**
- Modify:
  - `tools/sim/bot.lua`, `tools/sim/sim.lua`
  - `AzerothAnte/Core/Profile.lua:50-60`
  - `AzerothAnte/Data/Decks.lua` (threshold fields)
  - `README.md`
  - `AzerothAnte/AzerothAnte.toc` (`## Version: 0.4.0`)
- Test: `tests/test_unlocks.lua`, `tests/test_achievements.lua`

**Interfaces:**
- Produces:
  - `Profile.totalDiscoverable()` computed from data counts (already partly true; confirm it covers `Trinkets.order` after `Trinkets.add`).
  - Deck thresholds as fractions `{ WARRIOR = 0.067, GOBLIN = 0.163, MONK = 0.25, WARLOCK = 0.337 }`, with threshold = `floor(fraction * total)`.
  - Unlocks stay persistent and grandfathered.

- [ ] **Step 1: Write failing tests:**
  - `thresholds_scale_with_total`: with the current data (total = 104 + 60 new trinkets = 164), Warrior unlocks at `floor(0.067*164) = 10`. Recompute from the actual total in the test, don't hard-code.
  - `grandfathered_unlock_kept`: a profile with WARLOCK in `unlockedDecks` and 20 discovered still has it unlocked.
- [ ] **Step 2:** Run `luajit tests/run.lua unlocks`. Expected: FAIL.
- [ ] **Step 3: Implement** the thresholds. Update the bot:
  - It scores with the pure Scoring, so speculative calls are now safe; keep its RNG copy.
  - It buys the trinket offer with the highest `rarity weight (common 1, uncommon 2, rare 3)` it can afford when it has room.
  - It never reorders.
- [ ] **Step 4:** Run `luajit tools/sim/sim.lua 200` for each deck. Expected: no errors, and each deck's win rate is between 8% and 45%.
  - If a deck is outside the band, report the rates **without** changing targets. The controller rules on it.
  - Record the rates in the README "Balance" note.
  - Update the README trinket section (count, drag to reorder, copying) and set the version to 0.4.0.
- [ ] **Step 5:** Run all four suites. Expected: green. Commit: `chore: wave 1 integration, discovery thresholds, sim, v0.4.0`.
