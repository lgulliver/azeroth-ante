# Trinkets Wave 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the last engine pieces:
- card changes and creation from scoring, applied through pure side effects;
- consumable creation, with room accounting;
- deck-wide counts;
- consumable-use, pack-open, card-added and card-destroyed hooks;
- disabling and triggering the boss.

Then add all 26 **D** trinkets from the spec. That completes the 143-trinket set.

**Architecture:**
- **Scoring:** `Scoring.score` now also deep-copies the played and held cards. Hooks change only those scratch cards. The result returns `cardsAfter` (changed fields by card id) plus side effects (`createCard`, `createConsumable`, `destroyCard`). `Run.play` removes the played cards by identity first, then commits trinkets, card changes and side effects inside one `Run.withMods`.
- **Deck changes:** `Deck.add` and `Deck.destroy` record into `run.cardLog`. `TrinketEngine.flushCards(run)` fires `onCardsAdded` and `onCardsDestroyed` once per action.
- **Boss:** `Run.activeBoss(run)` returns nil while the boss is disabled. Every boss *effect* reads it. Identity and target keep using `Run.bossId`.

**Tech Stack:** Lua 5.1 (LuaJIT tests), WoW UI API (Retail 120100/120105, Forever 16001).

**Spec:** `docs/superpowers/specs/2026-11-07-trinkets-design.md`. Read "Engine", "Calls made after the builder check", "Notes carried from wave 1" and "Notes carried from wave 2". The notes take precedence.

## Global Constraints

- Lua 5.1. Every file starts with `local _, ns = ...`. No new globals.
- `Core/` and `Data/` never call the WoW API or reference `AzerothAnteDB`.
- All randomness goes through `run.rng` or `ctx.rng`. Chances go through `ns.Prob.roll`, which always draws exactly once.
- Run state is plain data. Bump to `Save.VERSION = 6`; v2–v5 saves migrate and are never invalidated.
- Mouse only. Never the global `MouseIsOver`. All new UI uses the Theme helpers and Tween.
- Strings are ASCII plus "×", with gold written "Ng". Odds use `{N}` tokens.
- Trinket name, id, rarity, cost and effect come **verbatim** from the spec table.
- These are `copyable = false` (Balatro): SIXTH_SENSE (DIVINATION), MIDAS_MASK (GILDED_MASK), LUCHADOR (GLAD_MEDALLION), SATELLITE (MAGE_TOWER).
- Scoring must stay pure: the bot's speculative `Scoring.score` calls must never change real cards, the deck, consumables or the RNG state outside `ctx.rng`.
- Commit trailers:
  - Sonnet: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` + `Claude-Session: https://claude.ai/code/session_0111s9FDrYc6V71XhuzMRHhc`
  - Codex output is committed by the controller.
- Suites that must stay green: `luajit tests/run.lua`, `luajit tests/smoke_ui.lua`, `luajit tests/syntax.lua`, `python3 tests/test_media.py`.

## Review Focus

1. Speculative scoring (bot) with Vampire, Midas Mask or Hiker owned must leave every real card unchanged. Task 1 tests that a double score gives the same result and that real card fields are untouched.
2. DNA drawing a copy into the hand mid-play must never misplace the selection or leave the hand with more than hand size + 1 cards. Task 1 tests that the played cards are removed by identity before any draw.
3. Creating consumables (8 Ball, Cartomancer, Séance...) never exceeds the slots, even with several creators in one action. Task 2 tests pending-room accounting.
4. Disabling the boss mid-blind (Gladiator's Medallion) restores the hands and discards the boss took away, lifts every debuff at once, and never changes the target. Task 2 tests it.
5. A v5 save loaded mid-blind or mid-shop works: `usage`, `cardLog`, `bossDisabled` and `startDeckSize` get defaults. Task 2 tests it.

---

### Task 1: Scoring side effects — scratch cards, card changes, creations, Lucky hook, boss trigger

**Files:**
- Modify:
  - `AzerothAnte/Core/Scoring.lua`
  - `AzerothAnte/Core/Run.lua` (`play`)
  - `AzerothAnte/Core/Cards.lua` (`chipValue` + `bonusChips`)
  - `AzerothAnte/Core/Deck.lua` (`copy` keeps `bonusChips`)
  - `AzerothAnte/Data/Trinkets.lua` (header: new hooks and fields)
- Test: `tests/test_trinket_cards.lua` (new)

**Interfaces:**
- **Scratch cards.** `Scoring.score` deep-copies `ctx.cards` and `ctx.held`; hooks see only the copies.
  - `before` hooks may change scratch cards: set `card.enh` (including nil) or `card.bonusChips`.
  - Changes made in `before` apply to this hand's scoring: Vampire's stripped cards score unenhanced.
  - `onCard` changes (Hiker) apply to later triggers in the same hand.
- **Result additions:**
  - `cardsAfter = { [cardId] = { enh=, bonusChips=, seal=, ed= } }`, for changed cards only;
  - `sideEffects = { {kind="createCard", card={rank,suit,enh,ed,seal,bonusChips}, toHand=bool}, {kind="createConsumable", consumableKind="scroll"|"relic"|"tome", id=nil}, {kind="destroyCard", id=} }`;
  - `bossTriggered = bool`;
  - `luckyTriggers = n`.
- **Effect fields** usable in scoring hooks (before, onCard, onHand, after): `createCard`, `createConsumable` (`kind` and optional `id`), `destroyCard = cardId`, `changeCard`. Each is appended to `sideEffects` (or `cardsAfter`).
- **`onLucky(ctx, self, card, isCopy)`** is called once per successful Lucky card trigger, for the mult roll and the money roll separately.
- **New ctx fields** (Run.play supplies them):
  - `deckCards` (read-only `run.deck`);
  - `startDeckSize`;
  - `firstHandOfRound` (`run.handsPlayedRound == 0`);
  - `gold` (at play time);
  - `consumableRoom = Consumables.slots(run) - #run.consumables`.
- **`bossTriggered`.** Scoring sets it when an active boss debuffs a played card, applies `halveBase`, or has `mustPlay`.
- **`Run.play` order:**
  1. Capture the played cards by identity.
  2. Score.
  3. Remove the played cards from `run.hand` by identity.
  4. Inside one `Run.withMods`:
     - commit `trinketsAfter`;
     - apply `cardsAfter` to the real deck cards by id;
     - apply the side effects in order:
       - `createCard`: `Deck.add`, and into `run.hand` if `toHand`;
       - `createConsumable`: only while room is left, counting earlier creations;
       - `destroyCard`: `Deck.destroy`.
     - then the level-ups.
  5. Glass destruction, the win check and refill as before.
- `Cards.chipValue(card)` adds `card.bonusChips or 0`; Stone stays at 0, plus its bonusChips. `Deck.copy` keeps `bonusChips`.

- [ ] **Step 1: Write failing tests** in `tests/test_trinket_cards.lua` (stub trinkets via `H.stub`):
  - `scratch_cards_pure`:
    - a `before` stub strips enhancements and an `onCard` stub adds `bonusChips = 5`;
    - scoring twice gives equal results;
    - the real cards are unchanged;
    - `cardsAfter` holds both changes.
  - `before_change_affects_this_hand`: a stripped Glass card scores without ×2.
  - `oncard_bonus_seen_by_retrigger`: a Red seal card with +5 per trigger gets 5 extra on its second trigger.
  - `play_commits_card_changes`: after `Run.play`, the real deck card has the new `enh` and `bonusChips`.
  - `create_card_to_hand_keeps_selection`:
    - a stub creates a card into the hand during a 1-card play;
    - the played card is gone;
    - the created card is in the hand and in the deck;
    - the hand holds at most `handSize`, plus that card if the refill would overflow;
    - no other card is lost.
  - `create_consumable_room`: two `createConsumable` effects with 1 room create exactly 1.
  - `destroy_card_effect`.
  - `lucky_hook_counts`: with a forced rng, both Lucky rolls hit, so `onLucky` is called twice.
  - `boss_triggered_flag`: a suit-debuff boss with a debuffed played card sets it to true; no debuff gives false.
  - `chipvalue_bonus`: an A with `bonusChips` 10 gives 21.
- [ ] **Step 2:** Run `luajit tests/run.lua trinket_cards`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: scoring card side effects, scratch cards, lucky hook, boss trigger`.

### Task 2: Lifecycle side — usage counters, card log, new hooks, boss disable, save v6

**Files:**
- Modify:
  - `AzerothAnte/Core/TrinketEngine.lua`
  - `AzerothAnte/Core/Run.lua`
  - `AzerothAnte/Core/Deck.lua`
  - `AzerothAnte/Core/Consumables.lua`
  - `AzerothAnte/Core/Packs.lua`
  - `AzerothAnte/Core/Save.lua`
  - `AzerothAnte/Data/Bosses.lua` (comment)
  - `AzerothAnte/UI/ConsumableRow.lua` (carried note: `busy()` includes `ns.UI.Lifecycle.IsBusy()`)
- Test: `tests/test_trinket_deck.lua` (new), `tests/test_save.lua`

**Interfaces:**
- **Run fields:**
  - `run.usage = { scroll = 0, tome = 0, relic = 0, tomeIds = {} }`;
  - `run.cardLog = { added = {}, destroyed = {} }`;
  - `run.bossDisabled = false`, reset in `startBlind`;
  - `run.startDeckSize = #run.deck` at `Run.new`;
  - `run.handsPlayedRound`, reset in `startBlind` and incremented in `play`.
- `Deck.add` and `Deck.destroy` append the card (a copy for destroyed cards) to `run.cardLog`.
- `TrinketEngine.flushCards(run)`:
  - if the log is non-empty, fires `onCardsAdded(run, self, cards, isCopy)` and `onCardsDestroyed(run, self, cards, isCopy)`, then clears the log;
  - called at the end of `Run.play`, `Run.discard`, `Run.startBlind`, `Consumables.use`/`apply`, `Packs.pick`, `Shop.buy` and any fire that destroys a card.
- **New hooks** (lifecycle effects):
  - `onConsumableUsed(run, self, item, isCopy)`: fired by `Consumables.use` and pack picks that apply a consumable, after `run.usage` is incremented (`usage.tomeIds[id] = true` for Tomes).
  - `onPackOpened(run, self, pack, isCopy)`: fired by `Packs.open`.
  - `onFirstDraw(run, self, isCopy)`: fired at the end of `startBlind`, after the first draw.
- **More lifecycle effect fields:**
  - `createCard = { card, toHand }`, with `toHand` honoured only in phase play;
  - `createConsumable = { kind, id }`, room permitting;
  - `disableBoss = true`.
- **Boss:**
  - `Run.activeBoss(run) -> def|nil` returns nil when `run.bossDisabled`.
  - Scoring debuffs, `halveBase`, `mustPlay`, `blindHands`/`blindDiscards` boss overrides, `Run.discard`'s and `winBlind`'s debuff checks, and HandView's debuff display all use it.
  - On `disableBoss` in play, `handsLeft` and `discardsLeft` gain the difference between the deck's normal values (plus mods) and the boss's override, when positive.
  - The target is unchanged.
- **Consumable room.** `TrinketEngine.apply`'s `createConsumable` uses `Consumables.slots(run) - #run.consumables`.
  - Rolls use `Consumables.random(run, kind)`.
  - Relics use the Spectral-equivalent pool.
- `Save.VERSION = 6`. The migration adds `usage`, `cardLog`, `bossDisabled = false`, `startDeckSize = 52` (or the deck's starting size if known) and `handsPlayedRound = 0`.

- [ ] **Step 1: Write failing tests:**
  - `usage_counters`.
  - `card_log_flush_once_per_action`: a Standard pack pick adds 1 card, so `onCardsAdded` gets 1 card once.
  - `cards_destroyed_by_glass_fire_hook`.
  - `pack_opened_hook`.
  - `first_draw_after_draw`: the hook sees a full hand.
  - `create_consumable_room_lifecycle`.
  - `disable_boss_restores`: on Mutanus (0 discards), disabling mid-blind gives the deck's discards; Hogger's face debuff is lifted for the next play; the target is unchanged.
  - `v5_save_migrates`.
  - A smoke step in `tests/smoke_ui.lua`: `consumable_sell_locked_during_drain`.
- [ ] **Step 2:** Run `luajit tests/run.lua trinket_deck`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: deck and consumable hooks, boss disable, save v6`.

### Task 3: UI — card changes, created cards and consumables, boss disabled

**Files:**
- Modify:
  - `AzerothAnte/UI/Tally.lua`
  - `AzerothAnte/UI/Lifecycle.lua`
  - `AzerothAnte/UI/HandView.lua`
  - `AzerothAnte/UI/ConsumableRow.lua`
  - `AzerothAnte/UI/Sidebar.lua`
  - `AzerothAnte/UI/CardWidget.lua` (bonus-chips tooltip line)
- Test: `tests/smoke_ui.lua`

**Interfaces:**
- **Tally**, after `total`, in order:
  - `cardsAfter` changes flash the changed card: Gold tint for Midas, a desaturate flash for Vampire's strip, "+5" chips for Hiker.
  - `createCard` with `toHand` flies a new card widget from the deck button into the hand.
  - Other created cards pulse the Deck button.
  - Created consumables pop into the consumable row (scale 0.6 to 1, 0.2s).
- **Lifecycle playback** handles the new lifecycle effects the same way: card created, consumable created, boss disabled.
- **Boss disabled:**
  - the sidebar boss panel shows "Disabled" with the boss name struck dim;
  - debuff markers on cards disappear immediately;
  - a float "Boss disabled!".
- **Tooltip:** a card with `bonusChips > 0` shows "+N chips" in its tooltip.

- [ ] **Step 1: Write failing smoke steps:**
  - `midas_gold_flash`;
  - `dna_card_flies_to_hand`;
  - `consumable_created_pops`;
  - `boss_disabled_display`;
  - `bonus_chips_tooltip`.
- [ ] **Step 2:** Run `luajit tests/smoke_ui.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites plus the SMOKE_SEED 1..30 sweep. Expected: green, with no fails.
- [ ] **Step 5:** Commit: `feat: UI for card changes, created cards and consumables, boss disable`.

### Task 4: D trinkets, part A (rows 24–76)

**Files:**
- Create: `AzerothAnte/Data/TrinketsD.lua` (TOC after `Data\TrinketsE.lua`)
- Test: `tests/test_trinkets_d.lua` (new)

**Scope:** rows 24, 26, 32, 51, 54, 55, 56, 59, 66, 68, 70, 71, 76 (13 trinkets).

**Behaviour pins** [Balatro]:
- **Marble Joker:** `onBlindSelect` returns `createCard = { card = {rank=random, suit=random, enh="STONE"}, toHand = false }`, added to the deck before the draw, so it can be drawn this round.
- **8 Ball:** `onCard` on a scored 8 (non-Stone), on `Prob.roll` 1 in 4, gives `createConsumable = { kind = "scroll" }`.
- **Steel Joker:**
  - `onHand` gives `xmult = 1 + 0.2 × steel cards in ctx.deckCards` when > 1;
  - `inPool`: the deck has a STEEL card;
  - `status` gives "Currently ×N".
- **DNA:** `before` when `ctx.firstHandOfRound` and `#ctx.cards == 1` gives `createCard = { card = copy of cards[1], toHand = true }`, with msg "Copied!".
- **Sixth Sense:** `before` when `firstHandOfRound`, a single card of rank 6 and `ctx.consumableRoom > 0` gives `destroyCard = id, createConsumable = { kind = "relic" }`. If there's no room, it still destroys the card (Balatro destroys regardless).
- **Constellation:** `onConsumableUsed` with a tome, not a copy: `state.x += 0.1`. `onHand` gives `xmult` when > 1.
- **Hiker:** `onCard`, not a copy: the scratch card's `bonusChips += 5`, and `changeCard` is recorded.
- **Superposition:** `before` when `ctx.contains.STRAIGHT` and any played card has rank 14 gives `createConsumable = { kind = "scroll" }`.
- **Séance:** `before` when `ctx.handId == "STRAIGHT_FLUSH"` gives `createConsumable = { kind = "relic" }`.
- **Vampire:**
  - `before`, not a copy: each scoring card with `enh` that isn't debuffed has its `enh` stripped (scratch) and adds `state.x += 0.1`.
  - `onHand` gives `xmult` when > 1.
- **Hologram:** `onCardsAdded`, not a copy: `state.x += 0.25 × #cards`. `onHand` gives `xmult` when > 1.
- **Vagabond:** `before` when `ctx.gold <= 4` gives `createConsumable = { kind = "scroll" }`.
- **Midas Mask:** `before` turns each scoring face card (rules-aware) into a Gold card in scratch, so it doesn't score as Gold this hand.

- [ ] **Step 1: Write failing tests**, one `<ID>_effect` per trinket asserting the exact effect. Plus:
  - `marble_stone_drawable_same_round`;
  - `dna_only_first_hand_single_card`;
  - `vampire_strips_before_scoring` (a stripped Glass card gives no ×2);
  - `hiker_permanent_across_hands`;
  - `steel_pool_gate`.
- [ ] **Step 2:** Run `luajit tests/run.lua trinkets_d`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: wave 3 trinkets part A (rows 24-76)`.

### Task 5: D trinkets, part B (rows 77–142)

**Files:**
- Modify: `AzerothAnte/Data/TrinketsD.lua`, `tests/test_trinkets_d.lua`

**Scope:** rows 77, 81, 85, 86, 89, 91, 106, 112, 120, 129, 139, 141, 142 (13 trinkets).

**Behaviour pins** [Balatro]:
- **Luchador:** `onSelfSold` when phase is play and `run.blind == 3` (a boss) gives `disableBoss = true`, with msg "Boss disabled!". Otherwise nothing.
- **Erosion:** `onHand` gives `mult = 4 × max(0, ctx.startDeckSize - #ctx.deckCards)` when > 0.
- **Hallucination:** `onPackOpened`, on `Prob.roll` 1 in 2, gives `createConsumable = { kind = "scroll" }`.
- **Fortune Teller:** `onHand` gives `mult = run.usage.scroll` (via `ctx.usage`) when > 0. Supply `ctx.usage` in Run.play.
- **Stone Joker:** `onHand` gives `chips = 25 ×` Stone cards in the deck. `inPool`: the deck has a STONE card.
- **Lucky Cat:**
  - `onLucky`, not a copy: `state.x += 0.25`.
  - `onHand` gives `xmult` when > 1.
  - `inPool`: the deck has a LUCKY card.
- **Golden Ticket:** `onCard` on a scored GOLD card gives `gold = 4`. `inPool`: the deck has a GOLD card.
- **Certificate:** `onFirstDraw` gives `createCard = { card = random rank/suit with seal random of GOLD/RED/BLUE/PURPLE, toHand = true }`.
- **Glass Joker:**
  - `onCardsDestroyed`, not a copy: `state.x += 0.75 ×` destroyed cards with `enh == "GLASS"`.
  - `onHand` gives `xmult` when > 1.
  - `inPool`: the deck has a GLASS card.
- **Matador:** `after` when `ctx.bossTriggered` gives `gold = 8`.
- **Satellite:** `onRoundEnd` returns the count of keys in `run.usage.tomeIds`.
- **Driver's License:** `onHand` gives `xmult = 3` when at least 16 cards in `ctx.deckCards` have an `enh`.
- **Cartomancer:** `onBlindSelect` gives `createConsumable = { kind = "scroll" }`.

- [ ] **Step 1: Write failing tests**, one `<ID>_effect` per trinket. Plus:
  - `luchador_only_in_boss`;
  - `glass_joker_counts_breaks`;
  - `certificate_card_permanent`;
  - `matador_only_when_triggered`;
  - `satellite_unique_tomes`.
- [ ] **Step 2:** Run `luajit tests/run.lua trinkets_d`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: wave 3 trinkets part B (rows 77-142)`.

### Task 6: Integration — sim, README, version

**Files:**
- Modify: `tools/sim/bot.lua`, `README.md`, `AzerothAnte/AzerothAnte.toc` (`## Version: 0.6.0`)
- Test: `tests/test_content.lua` (the catalog is now 143; derived)

- [ ] **Step 1: Write a failing test:** `full_catalog` asserts 143 trinkets and that every spec row except 94 and 114 (Diet Cola, Throwback) has a registered id.
- [ ] **Step 2:** Run `luajit tests/run.lua content`. Expected: FAIL until data is complete, then PASS.
- [ ] **Step 3: Implement.**
  - The bot survives every new hook and never uses consumables it can't.
  - Run `luajit tools/sim/sim.lua 200 <deck> 1` for ROGUE, WARRIOR, GOBLIN, MONK and WARLOCK. Expected: no errors, and every deck between 8% and 45%. If any deck is outside the band, report the rates and **don't** change targets; the controller rules.
  - README: 143 trinkets (all but the two skip-tag ones), card creation and change, boss disable, and the rates.
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `chore: wave 3 integration, full trinket set, sim, v0.6.0`.
