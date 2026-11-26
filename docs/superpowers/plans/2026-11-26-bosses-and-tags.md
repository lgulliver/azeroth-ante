# Bosses and Skip Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Balatro's full boss roster (15 regular bosses + 5 finishers, with face-down cards) and blind skipping with all 24 tags, Warcraft-named.

**Architecture:** Bosses stay data in `Data/Bosses.lua`, gaining optional hooks that `Core/Run.lua` and `Core/Scoring.lua` call through `Run.activeBoss(run)` (so a disabled boss is silent). Tags are data in a new `Data/Tags.lua` with hooks fired by a small `Core/Tags.lua` at fixed moments (taken, shop opened, blind started, boss defeated). UI changes are limited to the blind-select screen, the hand view, the trinket row and the sidebar.

**Tech Stack:** Lua 5.1 (WoW addon), LuaJIT test runner (`tests/run.lua`, `tests/smoke_ui.lua` with `tests/wowstub.lua`), luacheck.

**Spec:** `docs/superpowers/specs/2026-11-26-bosses-and-tags-design.md`

## Global Constraints

- Numbers, rules, minimum antes and odds are vanilla Balatro 1.0.1 (balatrowiki.org); names and flavour are Warcraft's, exactly as in the spec tables.
- Ids in the spec tables are the code ids; existing ids (HOGGER … RAGNAROS) never change, so saves and achievements carry over.
- `Core/` and `Data/` never call the WoW API (CONTRIBUTING.md).
- Every boss rule reads its boss through `Run.activeBoss(run)`; a disabled boss (Matador-style `disableBoss`) does nothing and turns face-down cards up.
- Saves: bump `Save.VERSION` to 7; older saves load with `run.tags = {}`, `run.blindTags = {}`, `run.skips = 0`, `run.playedThisAnte = {}`.
- Comments and code match the surrounding style; Conventional Commits; commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not mention how art or code was produced.
- Verification for every task: `luajit tests/run.lua` (0 failed), `luajit tests/smoke_ui.lua` ("smoke ok"), `luajit tests/syntax.lua`, `luacheck AzerothAnte tests` (0 errors; warnings stay at 128).

## Review Focus

1. A boss disabled mid-blind (by the boss-disabling trinket) must undo every lasting effect: face-down cards flip up, Kel'Thuzad's forced card is released, Ragnaros's disabled trinket is re-enabled, Xavius's debuff lifts, Targorr's −1 hand size refills. Test in Task 6 (`disabling_finisher_restores_everything`) and Task 3 (`disabling_boss_turns_cards_up`).
2. A save/reload mid-blind keeps boss state: face-down flags, the forced card, the disabled trinket, played-this-ante ids, held tags and the next two blind tags. Test in Task 7 (`save_v6_loads_with_empty_tag_state`, `save_roundtrip_keeps_boss_state`).
3. Gluth/Shade of Aran with only illegal hands left must not soft-lock: the player can still discard, and with no discards and no legal hand the blind is lost (Balatro behaviour). Test in Task 4 (`mouth_no_legal_hand_loses_when_no_discards`).
4. Baron Revilgaz can push gold below zero only to the gold floor (`Run.goldFloor`, Credit Card −20); never further. Test in Task 4 (`tooth_respects_gold_floor`).
5. Skipping when a free-pack tag opens a pack outside the shop: the pack must be resolvable (pick or skip) from the blind screen, survive `/reload`, and never charge gold. Test in Task 8 (`gift_pack_opens_free_on_blind_screen`) and the smoke test in Task 8.

---

### Task 1: Finisher draw, finisher reward and per-boss target multipliers

**Files:**
- Modify: `AzerothAnte/Data/Bosses.lua`, `AzerothAnte/Core/Run.lua` (`Run.new`, `Run.canRerollBoss`, `pickBoss`, `Run.winBlind`), `AzerothAnte/Data/Achievements.lua` (`bossCount`, RETCON)
- Test: `tests/test_bosses.lua` (new), `tests/test_content.lua:194-196`, `tests/test_voucher_run.lua:184`

**Interfaces:**
- Produces: `Bosses.pool` (regular ids, unchanged name), `Bosses.FINALS = { "RAGNAROS", "CTHUN", "YOGG", "XAVIUS", "KELTHUZAD" }` (replaces `Bosses.FINAL`), `Bosses.isFinal(id) -> bool`, `Run.blindReward(run) -> number` (3/4/5, finisher 8). Every boss def keeps `targetMult`, `minStage`, `name`, `desc`.

- [ ] **Step 1: Write failing tests** in `tests/test_bosses.lua`:
  - `stage_8_draws_a_finisher`: over seeds 1..200, `Bosses.isFinal(run.bosses[8])` and every finisher appears at least once.
  - `finishers_never_before_stage_8`: stages 1..7 never hold a finisher.
  - `finisher_reroll_stays_final`: at stage 8, blind 3, with `run.vouchers.DIRECTORS_CUT = true` and gold 100, `Run.rerollBoss(run)` succeeds and returns another finisher id.
  - `finisher_pays_8`: winning stage 8's boss gives `run.lastPayout.reward == 8` (stub `Shop.open` not needed: stage 8 ends the run; assert before phase check).
  - `cthun_target_is_6x`: `Run.target(8, 3, "CTHUN") == 300000`.
  - Update `test_content.lua:194` to assert `Bosses.FINALS[1] == "RAGNAROS"`, and `test_voucher_run.lua:184` to `Bosses.isFinal(run.bosses[8])`.
- [ ] **Step 2:** `luajit tests/run.lua bosses` → FAIL (`FINALS` nil).
- [ ] **Step 3:** Add `CTHUN` (targetMult 6, desc "A colossal target."), `YOGG`, `XAVIUS`, `KELTHUZAD` defs (targetMult 2; rules come in Task 6; desc from the spec table). `Run.new` sets `run.bosses[8]` to `RNG.pick(run.rng, Bosses.FINALS)`. `Run.canRerollBoss` drops the stage-8 refusal; `pickBoss` draws from `FINALS` when `stage == 8`. `Run.winBlind` uses `Run.blindReward(run)`. Achievements: `bossCount` counts ids in `pool` and `FINALS` seen; RETCON compares to `#pool + #FINALS`.
- [ ] **Step 4:** Full verification (Global Constraints) → green.
- [ ] **Step 5:** Commit `feat: finisher bosses draw at ante 8`.

### Task 2: Face-down cards and the four face-down bosses

**Files:**
- Modify: `AzerothAnte/Core/Run.lua` (`refill`, `Run.startBlind`, `Run.play`, `Run.discard`, `Run.winBlind`, `lose`, `Run.disableBoss`), `AzerothAnte/Data/Bosses.lua`, `AzerothAnte/UI/HandView.lua`, `AzerothAnte/UI/Sidebar.lua` (hand preview)
- Test: `tests/test_bosses.lua`, `tests/smoke_ui.lua`

**Interfaces:**
- Produces: `card.faceDown` (boolean, persisted with the card). `local function drawCards(run, n, why)` in Run.lua replaces direct `Cards.draw` calls; `why` is `"start"`, `"play"` or `"discard"`. Boss hook `onDraw(run, card, why) -> bool` (true = face down). `Run.revealHand(run)` clears `faceDown` on every card in hand.
- New bosses (ids/names/minStage per spec): `MOROES` (`why == "start"` and `run.handsPlayedRound == 0`), `THERMAPLUGG` (`RNG.next(run.rng) < 1/7`), `MOROGRIM` (`why == "play"`), `SKERAM` (`Cards.isFace(card, rules)`; face cards only).

- [ ] **Step 1: Failing tests:**
  - `moroes_first_hand_face_down`: start a blind on MOROES; every card in `run.hand` has `faceDown`; after one `Run.play`, newly drawn cards do not.
  - `thermaplugg_one_in_seven`: over 3000 drawn cards across many blinds, the face-down share is within 0.10–0.19.
  - `morogrim_face_down_after_play_only`: start: none face down; after a play: the refilled cards are face down; after a discard: refilled cards are not.
  - `skeram_face_cards_only`: every face-down card is J/Q/K; every J/Q/K drawn is face down.
  - `played_cards_turn_up` / `blind_end_turns_hand_up`: played cards have `faceDown == nil` in the result's card events and in the deck; after `winBlind` no card in `run.deck` is face down.
  - `disabling_boss_turns_cards_up`: on SKERAM, `Run.disableBoss(run)` clears every `faceDown` in hand.
  - Smoke: a face-down card in hand shows its back (`w.back:IsShown()`) and a face-down card in the selection makes the sidebar hand preview read "?" instead of a hand name.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `drawCards`; call `boss.onDraw` for each drawn card when `Run.activeBoss(run)` has it. In `Run.play`, clear `faceDown` on played cards before scoring. `winBlind`, `lose` and `disableBoss` call `Run.revealHand`, and `Deck` cards drop the flag at blind end. HandView: `w:SetFaceUp(not card.faceDown)` wherever it sets face-up for a hand card; selection still works. Sidebar preview: hand label "?" while any selected card is face down.
- [ ] **Step 4:** Verification → green.
- [ ] **Step 5:** Commit `feat: face-down cards and four bosses that use them`.

### Task 3: Rule bosses that need no new flow (Thredd, Targorr, Patchwerk, Archaedas)

**Files:**
- Modify: `AzerothAnte/Data/Bosses.lua`, `AzerothAnte/Core/Deck.lua` (`Deck.handSize`), `AzerothAnte/Core/Run.lua` (`Run.scoreCtx`, debuff call sites, stage advance), `AzerothAnte/Core/Scoring.lua` (debuff call sites)
- Test: `tests/test_bosses.lua`

**Interfaces:**
- Changes: boss `debuff(card, rules, info)`; `info.playedThisAnte` is a set of card ids. `Run.scoreCtx` adds `playedThisAnte = run.playedThisAnte`; Scoring passes `ctx` as `info`; Run's discard/round-end calls pass `run`.
- Produces: `run.playedThisAnte` (card id -> true), filled in `Run.play` after scoring for every played card, cleared when `run.stage` increases. Read it as `run.playedThisAnte or {}` until Task 7's save migration lands. Boss field `handSize` (number, added to `Deck.handSize` while the boss is active).
- New bosses: `THREDD` (Clubs debuffed, `hasSuit(card, "C", rules)`), `TARGORR` (`handSize = -1`), `PATCHWERK` (`targetMult = 4`, no rule), `ARCHAEDAS` (`debuff = info.playedThisAnte[card.id]`).

- [ ] **Step 1: Failing tests:** `thredd_debuffs_clubs`; `targorr_hand_size_minus_one` (hand of 7 on a default deck; back to 8 next blind); `patchwerk_target_4x` (`Run.target(2, 3, "PATCHWERK") == 3200`); `archaedas_debuffs_cards_played_this_ante` (play a card in the small blind, meet it again in the boss blind: a `debuff` event for it; next ante it scores); `disabling_targorr_refills_hand`.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. Disabling a boss that set `handSize` calls `refill` (the existing `applyMods` path draws up when hand size grows).
- [ ] **Step 4:** Verification → green. **Step 5:** Commit `feat: Bazil Thredd, Targorr, Patchwerk and Archaedas`.

### Task 4: Play-time bosses (Greenskin, Frostwhisper, Revilgaz, Gruul, Gluth, Aran, Hakkar)

**Files:**
- Modify: `AzerothAnte/Data/Bosses.lua`, `AzerothAnte/Core/Run.lua` (`Run.canPlay`, `Run.play`, `Run.discard`, `refill`), `AzerothAnte/UI/HandView.lua` (Play button reason)
- Test: `tests/test_bosses.lua`, `tests/smoke_ui.lua`

**Interfaces:**
- Boss hooks: `canPlayHand(run, handId) -> ok, reason`; `beforeScore(run, handId)` (runs after `Run.canPlay`, before `Scoring.score`); `afterPlay(run, played, handId)` (after the score is added, before refill); `drawCount(run, why) -> n` (overrides the refill count).
- `Run.canPlay(run, idx)` evaluates the hand with `HandEval.evaluate(cards, TrinketRules.set(run.trinkets))` and asks `canPlayHand`.
- Rules (spec table): GREENSKIN discards 2 random held cards (no discard spent; Purple seals do not fire — Balatro's Hook). FROSTWHISPER lowers `run.handLevels[handId]` by 1 to a minimum of 1 before scoring. REVILGAZ subtracts 1g per played card, never below `Run.goldFloor(run)`. GRUUL: if `handId` is the most-played hand (`run.handPlays`, ties count, read before this play is counted) set `run.gold = math.min(run.gold, 0)` → 0. GLUTH: first hand type played this round (`run.roundHandPlays`) is the only one allowed; reason "Only <hand name> can be played." ARAN: a hand type already in `run.roundHandPlays` is refused; reason "<hand name> was already played this round." HAKKAR: `drawCount` returns 3 after a play or discard (start of blind draws normally).

- [ ] **Step 1: Failing tests:** one per boss (`hook_discards_two_held`, `arm_lowers_level_before_scoring` (base event shows level-1 chips), `tooth_charges_per_card`, `tooth_respects_gold_floor`, `ox_zeroes_gold_on_most_played`, `mouth_locks_first_hand_type`, `eye_refuses_repeat`, `serpent_draws_three`), plus `mouth_no_legal_hand_loses_when_no_discards` (Gluth locked to Flush, hand with no flush and 0 discards: `Run.checkHand` ends the blind as lost) and a smoke check that the Play button is disabled with the boss's reason.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. `Run.checkHand` additionally loses when the boss has `canPlayHand`, discards are 0, and no 1–5 card subset of the hand is playable (`HandView` already uses `Run.canPlay` for its button).
- [ ] **Step 4:** Verification. Also `luajit tools/sim/sim.lua 20` completes (the bot must not crash on refused plays; if it tries a refused hand, it discards or plays its next-best legal hand — update `tools/sim/bot.lua` accordingly).
- [ ] **Step 5:** Commit `feat: seven play-time bosses`.

### Task 5: Boss data review and blind-select copy

**Files:**
- Modify: `AzerothAnte/Data/Bosses.lua` (descs), `AzerothAnte/UI/BlindSelect.lua` (shows `minStage`-correct boss; no change expected), `README.md` (manual checklist), `CHANGELOG.md`
- Test: `tests/test_content.lua`

- [ ] **Step 1: Failing test** `boss_roster_matches_spec` in test_content: `#Bosses.pool == 23`, `#Bosses.FINALS == 5`, and a table of id → `{ minStage, targetMult }` exactly as the spec (existing eight included).
- [ ] **Step 2:** FAIL until Tasks 1–4 are in; fix any drift. **Step 3:** Descs are one short sentence each, matching the spec "Rule" column. CHANGELOG "Added" entry listing the new bosses by name; README checklist line "A face-down card shows its back and flips when played."
- [ ] **Step 4:** Verification. **Step 5:** Commit `docs: boss roster notes`.

### Task 6: Finisher rules (Ragnaros, Yogg-Saron, Xavius, Kel'Thuzad)

**Files:**
- Modify: `AzerothAnte/Data/Bosses.lua`, `AzerothAnte/Core/TrinketEngine.lua` (`each`, `fire`), `AzerothAnte/Core/Run.lua` (`startBlind`, `Run.play`, `Run.canPlay`, `Run.canDiscard`, `Run.sellTrinket`, `disableBoss`), `AzerothAnte/UI/TrinketRow.lua`, `AzerothAnte/UI/HandView.lua`
- Test: `tests/test_bosses.lua`, `tests/smoke_ui.lua`

**Interfaces:**
- Produces: `trinket.disabled` (bool; `TrinketEngine.each` and `fire` skip disabled trinkets), `trinket.faceDown` (bool, UI only), `run.forcedCard` (card table reference or nil), `run.flags.soldThisBlind` (bool). Boss hooks `onStart(run)` (end of `startBlind`, after the first draw) and `beforeHand(run)` (at `startBlind` and after each play).
- RAGNAROS: `beforeHand` clears `disabled` on all trinkets, then sets it on one random trinket (none if no trinkets). YOGG: `onStart` sets `faceDown` on every trinket and shuffles `run.trinkets`. XAVIUS: `debuff` returns true until `run.flags.soldThisBlind`; `Run.sellTrinket` sets it during play. KELTHUZAD: `onStart`/after each draw picks `run.forcedCard` at random from the hand if the current one left it; `Run.canPlay`/`Run.canDiscard` refuse a selection without it ("<card> must be selected."). All four clean up at `winBlind`, `lose` and `disableBoss`.

- [ ] **Step 1: Failing tests:** `ragnaros_disables_one_trinket_each_hand` (a +4 Mult trinket's effect is absent exactly when disabled), `yogg_flips_and_shuffles`, `xavius_debuffs_until_sale`, `kelthuzad_forces_a_card` (play without it refused; with it allowed; forced card replaced after it is played), `disabling_finisher_restores_everything`, smoke: disabled trinket is shaded, face-down trinket shows the trinket back, forced card is pre-selected and cannot be deselected.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** Verification + `luajit tools/sim/sim.lua 20` completes. **Step 5:** Commit `feat: finisher boss rules`.

### Task 7: Skip flow and tag state

**Files:**
- Create: `AzerothAnte/Data/Tags.lua`, `AzerothAnte/Core/Tags.lua`; add both to `AzerothAnte/AzerothAnte.toc` (Data before Core users, after `Data/Bosses.lua`)
- Modify: `AzerothAnte/Core/Run.lua` (`Run.new`, stage advance, `Run.skipBlind`), `AzerothAnte/Core/Save.lua` (VERSION 7 migration), `AzerothAnte/UI/BlindSelect.lua` (Skip button + tag icon per small/big panel), `AzerothAnte/UI/Sidebar.lua` (held tags row with tooltips)
- Test: `tests/test_tags.lua` (new), `tests/test_save.lua`, `tests/smoke_ui.lua`

**Interfaces:**
- `Tags.order` (24 ids, spec order), `Tags.def[id] = { id, name, desc, minStage, icon, onTake?, onShopOpen?, onBlindStart?, onBossDefeated? }`.
- `Tags.roll(run) -> id` (uniform among defs with `minStage <= run.stage`), `Tags.add(run, id)` (appends to `run.tags`, then fires `onTake`; a tag whose `onTake` returns `true` is consumed immediately), `Tags.fire(run, hook, ...)` (calls the hook on each held tag in order; a hook returning `true` consumes that tag).
- `run.blindTags = { [1] = id, [2] = id }` rolled at run start and whenever `run.stage` increases; `run.tags` (list of ids); `run.skips` (count).
- `Run.canSkip(run) -> ok, reason` (only phase "blind", blind 1 or 2); `Run.skipBlind(run) -> tagId` (adds `run.blindTags[run.blind]`, `run.skips + 1`, fires trinkets' `onSkip`, advances to the next blind without reward or interest).
- Placeholder defs for all 24 tags with name/desc/minStage per spec; effects come in Tasks 8–9.

- [ ] **Step 1: Failing tests:** `blind_tags_rolled_per_ante` (two tags at stage 1, never a `minStage 2` tag at stage 1; re-rolled at stage 2), `skip_small_then_big` (blind advances 1→2→3, `run.skips == 2`, gold unchanged, two tags held), `boss_cannot_be_skipped`, `save_v6_loads_with_empty_tag_state`, `save_roundtrip_keeps_boss_state` (faceDown, forcedCard by id, disabled trinket, playedThisAnte, tags, blindTags survive `Save.store`/`Save.load`; `forcedCard` is stored as `run.forcedCardId` and relinked in `Save.load`), smoke: Skip button visible on small/big, absent on boss, clicking it advances the blind and adds a tag icon to the sidebar.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** Verification. **Step 5:** Commit `feat: skip small and big blinds for a tag`.

### Task 8: Immediate and pack tags

**Files:**
- Modify: `AzerothAnte/Data/Tags.lua`, `AzerothAnte/Core/Packs.lua` (`Packs.openGift`, `Packs.current`), `AzerothAnte/UI/PackView.lua` (read `Packs.current(run)` instead of `run.shop.openPack`), `AzerothAnte/UI/Screens.lua` (blind screen hosts the pack overlay)
- Test: `tests/test_tags.lua`, `tests/smoke_ui.lua`

**Interfaces:**
- `Packs.openGift(run, packType, size)` builds a pack exactly as `Packs.open` does (shared helper `buildPack(run, offer)` extracted from `Packs.open`) with `paid = 0` and stores it in `run.giftPack`; `Packs.pick`/`Packs.skip` act on `Packs.current(run)` (`run.giftPack or run.shop.openPack`).
- Tag effects (`onTake`, consumed): ECONOMY `run.gold + math.min(math.max(run.gold, 0), 40)`; SPEED `5 * run.skips`; HANDY `1 * run.handsPlayedTotal`; GARBAGE `1 * run.discardsUnusedTotal` (new counter: unused discards added at each `winBlind`); ORBITAL levels a random visible hand 3 times; TOPUP creates up to 2 common trinkets into free slots; BOSS rerolls this ante's boss with `pickBoss` (free, no voucher needed); STANDARD/CHARM/METEOR/BUFFOON open a Heavy (mega) gift pack of that type; ETHEREAL a normal Relic Cache.

- [ ] **Step 1: Failing tests:** one per tag above with exact gold/levels; `gift_pack_opens_free_on_blind_screen` (gold unchanged, `Packs.current(run)` is the gift, picking adds the item, skipping clears it, phase stays "blind"); smoke: skipping for Scribe's Gift shows the pack overlay over the blind screen.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** Verification. **Step 5:** Commit `feat: immediate and pack tags`.

### Task 9: Shop, round and Double tags

**Files:**
- Modify: `AzerothAnte/Data/Tags.lua`, `AzerothAnte/Core/Shop.lua` (`Shop.open` fires `Tags.fire(run, "onShopOpen")`), `AzerothAnte/Core/Run.lua` (`startBlind` fires `onBlindStart`; boss win fires `onBossDefeated`)
- Test: `tests/test_tags.lua`

**Interfaces / rules:**
- `onShopOpen`: UNCOMMON/RARE replace shop card slot 1 with a free trinket of that rarity (cost 0); NEGATIVE/FOIL/HOLO/POLY make the first base-edition trinket in the shop that edition and free (if none, wait for a later shop); COUPON sets cost 0 on every card and pack in the shop as it opens (rerolled items pay normally); D6 sets `run.shop.rerollCost = 0` and rerolls increase from 0; VOUCHER adds a second voucher offer (`run.shop.extraVoucher`, same pool rules, shown beside the first).
- `onBlindStart`: JUGGLE gives `+3` hand size for that blind only (`run.blindHandSizeBonus`, read by `Deck.handSize`, cleared at blind end).
- `onBossDefeated`: INVESTMENT adds 25g to the payout as its own line.
- DOUBLE: when another tag is added while DOUBLE is held, the DOUBLE is consumed and the new tag is added twice (DOUBLE never copies DOUBLE).

- [ ] **Step 1: Failing tests:** one per tag (`uncommon_tag_free_uncommon`, `poly_tag_waits_for_base_trinket`, `coupon_frees_initial_shop_only`, `d6_rerolls_start_free`, `voucher_tag_adds_offer`, `juggle_one_blind_only`, `investment_pays_after_boss`, `double_copies_next_tag`, `double_never_copies_double`).
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** Verification. **Step 5:** Commit `feat: shop, round and Bonus Roll tags`.

### Task 10: Bot, balance check and docs

**Files:**
- Modify: `tools/sim/bot.lua`, `CHANGELOG.md`, `README.md`, `docs/superpowers/specs/2026-11-26-bosses-and-tags-design.md` (outcome section)
- Test: `luajit tools/sim/sim.lua 100`

- [ ] **Step 1:** Bot skips a small/big blind when its tag is ECONOMY, SPEED (≥2 skips), a pack tag, UNCOMMON, RARE, NEGATIVE or POLY, and resolves gift packs with its existing pack logic.
- [ ] **Step 2:** Run `luajit tools/sim/sim.lua 100`; record per-deck win rates in the spec's outcome section (expected: a few percent; the bot is a floor, not a target).
- [ ] **Step 3:** CHANGELOG "Added" entries for skipping and tags; README checklist lines for the Skip button and a gift pack.
- [ ] **Step 4:** Full verification. **Step 5:** Commit `chore: bot skips for tags; bosses and tags docs`.
