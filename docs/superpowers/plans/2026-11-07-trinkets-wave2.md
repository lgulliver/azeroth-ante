# Trinkets Wave 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the lifecycle engine (blind select, discard, round end, boss defeated, sell, reroll, pack skip, loss prevention), trinket-derived hands, discards and hand size, selling during a blind, the CREDIT_CARD, CHAOS, SHOWMAN and ASTRONOMER rules, and all 37 **E** trinkets from the spec.

**Architecture:**
- `TrinketEngine.fire(run, hook, ...)` runs update hooks outside scoring, copy-aware. Effects are collected first and applied afterwards through one applier, so removals never shift slots mid-loop.
- Round end becomes three passes:
  1. `roundUpdate`, for every trinket;
  2. `onBossDefeated` (boss blinds only);
  3. `onRoundEnd` payouts.
- Hands, discards and hand size from trinkets are derived from owned trinkets, like vouchers.

**Tech Stack:** Lua 5.1 (LuaJIT tests), WoW UI API (Retail 120100/120105, Forever 16001).

**Spec:** `docs/superpowers/specs/2026-11-07-trinkets-design.md`. Read "Engine", "Calls made after the builder check" (calls 2, 4, 5, 6, 10) and "Notes carried from wave 1". The calls and notes take precedence.

## Global Constraints

- Lua 5.1. Every file starts with `local _, ns = ...`. No new globals.
- `Core/` and `Data/` never call the WoW API or reference `AzerothAnteDB`.
- All randomness goes through `run.rng`. Every listed chance goes through `ns.Prob.roll(rng, run.trinkets, num, den)`, which always draws exactly once.
- Run state is plain data. Bump to `Save.VERSION = 5`; v2–v4 saves migrate and are never invalidated.
- Mouse only. Never the global `MouseIsOver`. All new UI uses the Theme helpers and Tween.
- Strings are ASCII plus "×", with gold written "Ng" and negative gold written "-Ng".
- Trinket name, id, rarity, cost and effect come **verbatim** from the spec table. Use the `{N}` odds tokens rendered by `ns.Trinkets.describe(def, run)`.
- Copyable defaults to true. These are `copyable = false` (spec call 2 plus the wave 1 notes): CREDIT_CARD (VENTURE_LOAN), CHAOS (DARKMOON_TICKET), DELAYED_GRAT (INNER_PEACE), EGG (WHELP_EGG), GIFT_CARD (WINTER_VEIL), TURTLE_BEAN (FERTILE_SEED), CLOUD_9 (SKY_GOLEM), ROCKET (GOBLIN_ROCKET), TO_THE_MOON (GOBLIN_INVEST), JUGGLER (REAGENT_BAG), DRUNKARD (DWARVEN_STOUT), MR_BONES (SOULSTONE), TROUBADOUR (MINSTREL), SHOWMAN (SILAS), MERRY_ANDY (BRAWLER), INVISIBLE (INVIS_POTION), ASTRONOMER (STARGAZER). Hand-size, hand and discard modifiers are never copied, even on a copyable def such as Stuntman's chips.
- Commit trailers:
  - Sonnet: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` + `Claude-Session: https://claude.ai/code/session_0111s9FDrYc6V71XhuzMRHhc`
  - Codex output is committed by the controller.
- Suites that must stay green: `luajit tests/run.lua`, `luajit tests/smoke_ui.lua`, `luajit tests/syntax.lua`, `python3 tests/test_media.py`.

## Review Focus

1. A trinket destroying itself or another trinket inside `fire` (Gros Michel, Ceremonial Dagger, Madness) must never skip, double-run or crash on the next slot. Task 1 tests a destroy of slot 1 and of the slot to the right during one `fire`.
2. Selling Juggler, Drunkard or Merry Andy mid-blind must change the live hand size and discards immediately and never leave a negative count or an empty hand. Task 2 tests sell-mid-blind clamps.
3. With Credit Card, gold may go negative, but interest and Bull/Bootstraps never go negative. Selling Credit Card while in debt keeps the debt. Task 2 tests these.
4. Mr. Bones must save only once, only on a real loss, and only when score ≥ 25% of target. A saved blind goes to the shop, not "lost". Task 1 tests the boundaries.
5. Loading a v4 save mid-blind must keep working: `discardsUsedRound`, `flags` and `shop.freeRerolls` get defaults. Task 1 tests it.

---

### Task 1: Lifecycle engine, round-end passes, Mr. Bones, save v5

**Files:**
- Modify:
  - `AzerothAnte/Core/TrinketEngine.lua`
  - `AzerothAnte/Core/Run.lua` (`startBlind`, `discard`, `winBlind`, `lose`, `checkHand`, `play`, `new`)
  - `AzerothAnte/Core/Save.lua`
  - `AzerothAnte/Data/TrinketsS.lua`: port TITAN_RELIC and ZANDALARI_IDOL rerolls from `onRoundEnd` to `roundUpdate`
  - `AzerothAnte/Data/Trinkets.lua`: header comment listing the new hooks and effect fields
- Test: `tests/test_trinket_lifecycle.lua` (new), `tests/test_save.lua`

**Interfaces:**
- **New update hooks.** Each receives `isCopy` last and returns a lifecycle effect or nil:
  - `onBlindSelect(run, self, isCopy)`: called at the end of `Run.startBlind`, after hands and discards are set.
  - `onDiscard(run, self, cards, isCopy)`: called once per discard action, before the discarded cards leave the hand. `cards` is the list of discarded cards.
  - `roundUpdate(run, self, isCopy)`: state changes and decay at round end.
  - `onBossDefeated(run, self, isCopy)`.
  - `onLose(run, self, isCopy) -> effect`: `{ save = true }` prevents the loss.
  - `onRoundEnd(run, self, isCopy) -> gold|nil`: unchanged, payout only.
- **Lifecycle effect fields:**
  - `gold`, `msg`
  - `destroySelf`
  - `destroyTrinket = uid`
  - `createTrinkets = { rarity = "common", n = 2 }`, room permitting
  - `sellBonusAll = n`, for trinkets and consumables
  - `handsDelta = n`, `discardsSet = n`
  - `levelHand = handId`
  - `destroyCard = cardId`
  - `save = true`
- `TrinketEngine.fire(run, hook, ...) -> events`:
  - Calls the hook through `each` on the **real** instances.
  - Collects effects, then applies them in slot order via `TrinketEngine.apply(run, slot, uid, effect, isCopy)`.
  - `destroySelf` is ignored for copies.
  - Destructions are applied after all hooks have run; already-destroyed uids are skipped.
  - Returns `events = { {kind=, uid=, slot=, ...} }`, with kinds `trinketMsg`, `money`, `trinketDestroyed`, `trinketCreated`, `levelUp` and `cardDestroyed`.
  - Appends the events to `run.lifecycleEvents`, a list the UI drains.
- `Trinkets.rollOfRarity(run, rarity) -> id|nil` in Data/Trinkets.lua: an unowned (unless SHOWMAN is owned), `inPool` id of that rarity, chosen with `run.rng`.
- **Run fields:**
  - `run.discardsUsedRound`, reset in `startBlind` and incremented in `discard`.
  - `run.flags = {}`, e.g. `flags.grosMichelExtinct`.
  - `run.lifecycleEvents = {}`.
  - `run.savedBy`: the uid of the trinket that saved the blind, cleared at the next `startBlind`.
- **Round end in `Run.winBlind`:**
  1. `fire(run, "roundUpdate")`.
  2. If blind 3, `fire(run, "onBossDefeated")`.
  3. Payouts via `onRoundEnd` on the post-update instances, building `trinketLines`.
  4. Interest and the rest, as today.
- **Loss:** `lose(run)` first runs `fire(run, "onLose")`. If any effect has `save`:
  - set `run.savedBy`;
  - call `Run.winBlind(run, { saved = true })`, where `payout.reward = 0` and `payout.saved = uid`.
  - [Balatro: Mr. Bones' cash-out shows "Saved by Mr. Bones" in place of the blind reward. Unverified, so flag it if you know otherwise.]
- `Save.VERSION = 5`. The v2–v4 migration adds `discardsUsedRound = 0`, `flags = {}`, `lifecycleEvents = {}` and, if `run.shop`, `shop.freeRerolls = shop.freeRerolls or 0`.

- [ ] **Step 1: Write failing tests** in `tests/test_trinket_lifecycle.lua`, using `H` from `tests/trinket_helper.lua` plus stubs:
  - `fire_destroy_self_no_skip`: three stubs where slot 1's `onBlindSelect` returns `destroySelf`. Slots 2 and 3 still run, and the row ends as `[2,3]`.
  - `fire_destroy_right`: slot 1 returns `destroyTrinket = uid of slot 2`. Slot 2's hook still runs this time (it runs before the apply), it is gone afterwards, and `trinketDestroyed` carries its uid.
  - `fire_copy_no_destroy_self`: Schematic copying a destroySelf stub. Only the original is destroyed, once.
  - `create_trinkets_room`: `createTrinkets {common, 2}` with 1 free slot creates 1, uses `Trinkets.create`, and emits `trinketCreated`.
  - `round_passes_order`: a stub whose `roundUpdate` sets `state.pay = 9` and whose `onRoundEnd` returns `state.pay`, beside a Schematic copying it. Payout is 9 + 9, and the update ran once.
  - `boss_defeated_only_on_boss`.
  - `discard_hook_once_per_action`: receives the 2 discarded cards, and `discardsUsedRound` increments.
  - `on_lose_save_boundary`:
    - target 300, score 74 gives a loss; score 75 gives a save into the shop with `payout.reward == 0`;
    - a second loss in a later blind without the trinket is a real loss.
  - `titan_idol_roll_in_round_update`: the existing reroll behaviour is unchanged under the new hook.
  - In `test_save.lua`, `v4_save_migrates_lifecycle_fields`.
- [ ] **Step 2:** Run `luajit tests/run.lua lifecycle`. Expected: FAIL.
- [ ] **Step 3: Implement.** Port `Run.discard`'s Purple-seal logic unchanged, firing `onDiscard` before `removeSelected`.
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: trinket lifecycle engine, round-end passes, loss prevention, save v5`.

### Task 2: Selling, rerolls, packs, derived modifiers, economy rules

**Files:**
- Modify:
  - `AzerothAnte/Core/Run.lua`
  - `AzerothAnte/Core/Shop.lua`
  - `AzerothAnte/Core/Packs.lua`
  - `AzerothAnte/Core/Consumables.lua`
  - `AzerothAnte/Core/Deck.lua`
  - `AzerothAnte/Core/TrinketRules.lua`
  - `AzerothAnte/Data/Trinkets.lua`
- Test: `tests/test_trinket_economy.lua` (new)

**Interfaces:**
- Consumes: `TrinketEngine.fire` and `apply` (Task 1).
- **More update hooks:**
  - `onSell(run, self, sold, isCopy)`, where `sold = { kind = "trinket" | "consumable", item = instanceOrItem }`. It fires on every **other** owned trinket after the sale.
  - `onSelfSold(run, self) -> effect`: original only, before removal.
  - `onShopReroll(run, self, isCopy)`.
  - `onPackSkipped(run, self, isCopy)`.
- `Run.sellTrinket(run, slot) -> gained|nil, reason`:
  - Allowed when `run.phase` is `"shop"` or `"play"`.
  - Fires `onSelfSold`, removes the instance, adds `Shop.sellValue` gold, fires `onSell`, then calls `Run.applyMods(run, before)`.
  - `Shop.sellTrinket` delegates to it.
  - `Consumables.sell` fires `onSell` with kind `consumable`, and `Consumables.sellValue` adds `item.sellBonus or 0`.
- **Modifiers.** Defs may set `handSize`, `hands` and `discards` (a number, or `function(self, run) -> number`).
  - `Trinkets.mods(run) -> { handSize, hands, discards }` sums them over owned instances. It ignores copies, because copiers have no mods.
  - `Deck.handSize` adds `mods.handSize`. `Run.blindHands` and `Run.blindDiscards` add `mods.hands` and `mods.discards`, with the existing clamps.
  - `Run.applyMods(run, before)`, called after any acquire, sell or destroy (shop buy, pack pick, create, destroy, sell):
    - In phase `"play"`: `handsLeft += Δhands` (min 1) and `discardsLeft += Δdiscards` (min 0).
    - A hand-size increase draws up to the new size immediately. A decrease never discards cards from the hand.
- **Rules** (TrinketRules keys `CREDIT_CARD`, `CHAOS`, `SHOWMAN`, `ASTRONOMER`):
  - `Run.goldFloor(run)` is -20 with CREDIT_CARD, else 0.
  - `Run.canAfford(run, cost)` is `run.gold - cost >= Run.goldFloor(run)`. Use it in Shop.buy, Shop.buyVoucher, Shop.reroll, Packs.open and Run.rerollBoss, in place of `run.gold < cost`.
  - Interest uses `max(0, gold)`.
  - CHAOS: `Shop.open` sets `shop.freeRerolls` to the number of CHAOS instances. `Shop.reroll` spends a free reroll first: cost 0, and `rerollCost` doesn't increase.
  - SHOWMAN: `Shop.rollTrinket`, Buffoon packs, `Trinkets.rollOfRarity` and consumable rolls allow already-owned or held ids.
  - ASTRONOMER: Tome offers and CELESTIAL pack offers cost 0, set at generation and refreshed by `Shop.open` and reroll.
- **Interest.** Defs may set `interestBonus = n`. Interest = `min(cap, floor(max(0, gold)/5)) * (1 + Σ interestBonus)`.
- `Shop.reroll` fires `onShopReroll`. `Packs.skip` fires `onPackSkipped` only when the pack had picks left.

- [ ] **Step 1: Write failing tests:**
  - `sell_in_play_allowed`; `sell_in_blind_select_refused`.
  - `sell_fires_on_sell_others_only`.
  - `self_sold_before_removal`.
  - `mods_hand_size_live`: buy a +1 hand-size stub in the shop; the next blind draws 9. Selling it mid-blind keeps 9 cards in hand, and the next draw tops up to 8.
  - `mods_discards_clamp`: sell a +1 discards stub with 0 discards left; `discardsLeft` stays 0.
  - `mods_hands_min1`.
  - `credit_card_floor`: gold 5 can buy a cost-20 item, giving -15, but can't buy cost 30. Interest at -15 is 0. Selling the Credit Card trinket at -15 leaves the gold at -15 + sell value.
  - `chaos_free_reroll_once_per_shop`.
  - `showman_allows_duplicates`.
  - `astronomer_free_tomes_and_celestial`.
  - `interest_bonus_stacks`: cap 5, gold 25, two bonus stubs: 5 × 3 = 15.
  - `pack_skip_fires_only_with_picks_left`.
  - `consumable_sell_bonus`.
- [ ] **Step 2:** Run `luajit tests/run.lua economy`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: trinket selling anywhere, derived modifiers, economy rules`.

### Task 3: UI — selling in a blind, lifecycle event playback

**Files:**
- Modify:
  - `AzerothAnte/UI/Screens.lua` (sell mode in play; payout "Saved" line; free-reroll label; negative gold)
  - `AzerothAnte/UI/TrinketRow.lua`
  - `AzerothAnte/UI/Tally.lua` (or a new `UI/Lifecycle.lua` in the TOC after Tally)
  - `AzerothAnte/UI/Sidebar.lua` (negative gold display)
- Test: `tests/smoke_ui.lua`

**Interfaces:**
- Consumes: `run.lifecycleEvents`, `Run.sellTrinket`, `payout.saved`, `shop.freeRerolls`.
- **Sell in play:**
  - The trinket row's sell buttons are available in phase play. They're disabled while `Tally.IsBusy()` or a HandView animation is running.
  - Selling calls `Run.sellTrinket`, then re-renders the row, sidebar and hand (hand size may change).
- **Playback:**
  - After any action that can fire lifecycle hooks (blind start, discard, sell, reroll, pack skip, round end), the UI drains `run.lifecycleEvents` in order, 0.25s apart:
    - `trinketMsg` floats over the uid's slot;
    - `money` floats "+Ng" over the slot;
    - `trinketDestroyed` fades and shrinks the slot (0.3s);
    - `trinketCreated` pops the new slot in (scale 0.6 to 1, 0.2s);
    - `levelUp` floats "Level up!";
    - `cardDestroyed` uses the existing destroy animation.
  - The row re-renders after draining.
  - Draining never blocks input for more than the queue length × 0.25s, and clicking speeds it up as the Tally does.
- **Payout panel:**
  - `payout.saved` shows "Saved by <name>" in place of the blind reward line.
  - The reroll button shows "Reroll (free)" when `shop.freeRerolls > 0`.
  - Gold below 0 shows as "-Ng" in red.

- [ ] **Step 1: Write failing smoke steps:**
  - `sell_trinket_mid_blind`: gold rises, the slot is gone, and hand size updates.
  - `sell_locked_during_tally`.
  - `blind_select_destroy_and_create`: stubs that destroy the right-hand slot and create 2 commons. The events drain, the row ends correct, and there is no error.
  - `saved_payout_line`.
  - `free_reroll_label`.
  - `negative_gold_display`.
- [ ] **Step 2:** Run `luajit tests/smoke_ui.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites plus `for s in $(seq 1 30); do SMOKE_SEED=$s luajit tests/smoke_ui.lua >/dev/null || echo fail $s; done`. Expected: green, with no fails.
- [ ] **Step 5:** Commit: `feat: sell trinkets during a blind, lifecycle event playback`.

### Task 4: E trinkets, part A (rows 20–67)

**Files:**
- Create: `AzerothAnte/Data/TrinketsE.lua` (TOC after `Data\TrinketsS.lua`)
- Test: `tests/test_trinkets_e.lua` (new)

**Scope:** rows 20, 21, 30, 35, 38, 46, 47, 57, 58, 60, 61, 63, 64, 67 (14 trinkets).

**Behaviour pins** [Balatro]:
- **Credit Card:** `rule = "CREDIT_CARD"`.
- **Ceremonial Dagger:**
  - `onBlindSelect`, not a copy: if a trinket exists at slot+1, destroy it (`destroyTrinket`) and add `2 * Shop.sellValue(it)` to `state.mult`, with msg "+N Mult".
  - `onHand` gives `mult = state.mult` when it's > 0.
- **Chaos:** `rule = "CHAOS"`.
- **Delayed Gratification:** `onRoundEnd` returns `2 * run.discardsLeft` when `run.discardsUsedRound == 0` and `discardsLeft > 0`.
- **Gros Michel:**
  - `onHand` gives +15 mult.
  - `roundUpdate`, not a copy: `Prob.roll` 1 in 6 gives `destroySelf`, msg "Extinct!", and sets `run.flags.grosMichelExtinct = true`.
  - `inPool`: `not run.flags.grosMichelExtinct`.
- **Cavendish:**
  - ×3.
  - `roundUpdate`: 1 in 1000 gives `destroySelf`, msg "Extinct!".
  - `inPool`: `run.flags.grosMichelExtinct`.
- **Egg:** `roundUpdate`, not a copy: `self.sellBonus += 3`, msg "Value up!".
- **Burglar:** `onBlindSelect` returns `handsDelta = 3, discardsSet = 0`.
- **Faceless:** `onDiscard` gives `gold = 5` if at least 3 discarded cards are face cards (rules-aware).
- **Green Joker:**
  - `before` (scoring), not a copy: `state.mult += 1`.
  - `onDiscard`, not a copy: `state.mult = max(0, state.mult - 1)`.
  - `onHand` gives `mult = state.mult` when > 0.
- **To Do List:**
  - `init` and `roundUpdate` pick a random hand id from `ns.Hands.order`, excluding the current one and the secret hands (FIVE_KIND, FLUSH_HOUSE, FLUSH_FIVE) unless `run.seenHands[id]`.
  - `before` returns `gold = 4` when `ctx.handId == state.hand`.
  - `status` gives "Hand: <name>".
- **Red Card:** `onPackSkipped`: `state.mult += 3`. `onHand` gives that mult.
- **Madness:**
  - `onBlindSelect` when `run.blind ~= 3`, not a copy: `state.x += 0.5`, and destroy a random other trinket (via `run.rng`) if one exists.
  - `onHand` gives `xmult = state.x` when > 1. `init` sets `state.x = 1`.
- **Riff-Raff:** `onBlindSelect` returns `createTrinkets = { rarity = "common", n = 2 }`.

- [ ] **Step 1: Write failing tests**, one `<ID>_effect` per trinket asserting the exact pinned effect via `Run.startBlind`, `Run.discard`, `Run.winBlind`, `Packs.skip` or `H.score`. Plus:
  - `gros_michel_extinct_unlocks_cavendish` (forced rng);
  - `dagger_eats_right_neighbour_doubles_sell`;
  - `madness_skips_boss_blind`;
  - `riff_raff_respects_room`;
  - `green_joker_never_negative`.
- [ ] **Step 2:** Run `luajit tests/run.lua trinkets_e`. Expected: FAIL.
- [ ] **Step 3: Implement** the defs (name, id, rarity, cost and desc verbatim; real icons).
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: wave 2 trinkets part A (rows 20-67)`.

### Task 5: E trinkets, part B (rows 73–144)

**Files:**
- Modify: `AzerothAnte/Data/TrinketsE.lua`, `tests/test_trinkets_e.lua`

**Scope:** rows 73, 74, 79, 80, 83, 84, 87, 88, 95, 96, 97, 100, 103, 105, 107, 111, 121, 125, 130, 136, 137, 143, 144 (23 trinkets).

**Behaviour pins** [Balatro]:
- **Cloud 9:** `onRoundEnd` returns the count of rank-9 non-Stone cards in `run.deck`.
- **Rocket:** `init` sets `state.pay = 1`. `onBossDefeated`, not a copy: `state.pay += 2`. `onRoundEnd` returns `state.pay`.
- **Gift Card:** `roundUpdate` returns `sellBonusAll = 1`.
- **Turtle Bean:**
  - `init` sets `state.n = 5`; `handSize = function(self) return self.state.n end`.
  - `roundUpdate`, not a copy: `n -= 1`, and at 0 `destroySelf` with msg "Eaten!".
- **Mail-In Rebate:**
  - `init` and `roundUpdate` pick the rank of a random non-Stone deck card.
  - `onDiscard` gives `gold = 5 ×` the discarded cards of that rank.
  - `status` gives "Rank: <label>".
- **To the Moon:** `interestBonus = 1`.
- **Juggler:** `handSize = 1`. **Drunkard:** `discards = 1`.
- **Trading Card:** `onDiscard` when `run.discardsUsedRound == 0` (before the increment) and `#cards == 1` returns `destroyCard = cards[1].id, gold = 3`.
- **Flash Card:** `onShopReroll`: `state.mult += 2`. `onHand` gives that mult.
- **Popcorn:**
  - `init` sets `state.mult = 20`; `onHand` gives that mult.
  - `roundUpdate`, not a copy: `-= 4`, and at ≤ 0 `destroySelf` with msg "Eaten!".
- **Ramen:**
  - `init` sets `state.x = 2`; `onHand` gives `xmult = state.x`.
  - `onDiscard`, not a copy: `x -= 0.01 × #cards`, and at ≤ 1 `destroySelf` with msg "Eaten!".
- **Castle:**
  - `init` and `roundUpdate` pick a random suit, different from the current one.
  - `onDiscard`: `state.chips += 3 ×` discarded cards with `hasSuit` of that suit.
  - `onHand` gives those chips.
- **Campfire:**
  - `onSell`, not a copy: `state.x += 0.25`.
  - `onBossDefeated`: reset to 1.
  - `onHand` gives `xmult` when > 1.
- **Mr. Bones:** `onLose` returns `{ save = true, destroySelf = true, msg = "Saved!" }` when `run.score >= 0.25 * run.target`.
- **Troubadour:** `handSize = 2, hands = -1`. **Merry Andy:** `discards = 3, handSize = -1`. **Stuntman:** `handSize = -2`, and `onHand` gives `chips = 250`.
- **Showman:** `rule = "SHOWMAN"`. **Astronomer:** `rule = "ASTRONOMER"`.
- **Hit the Road:**
  - `onDiscard`, not a copy: `state.x += 0.5` per discarded Jack.
  - `roundUpdate`: reset to 1.
  - `onHand` gives `xmult` when > 1.
- **Invisible Joker:**
  - `roundUpdate`, not a copy: `state.rounds += 1`.
  - `onSelfSold` when `rounds >= 2` and another trinket exists: duplicate a random other trinket via `Trinkets.duplicate(run, inst, ed)`, where `ed` is the original's edition with NEGATIVE removed.
  - `status` gives "N/2 rounds" or "Ready!".
- **Burnt Joker:** `onDiscard` when `run.discardsUsedRound == 0`: `levelHand = HandEval.evaluate(cards, TrinketRules.set(run.trinkets))`.

- [ ] **Step 1: Write failing tests**, one `<ID>_effect` per trinket. Plus:
  - `turtle_bean_decays_and_shrinks_hand`;
  - `ramen_eaten_at_one`;
  - `campfire_resets_on_boss`;
  - `invisible_needs_two_rounds`;
  - `mr_bones_saves_once`;
  - `stuntman_chips_copyable_hand_size_not` (Schematic next to Leeroy gives +250 chips and no hand-size change);
  - `to_the_moon_interest`.
- [ ] **Step 2:** Run `luajit tests/run.lua trinkets_e`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `feat: wave 2 trinkets part B (rows 73-144)`.

### Task 6: Integration — carried parity fixes, sim, README, version

**Files:**
- Modify:
  - `AzerothAnte/Data/TrinketsS.lua`: Ancient excludes the current suit on reroll; Raised Fist compares by rank
  - `AzerothAnte/Data/Trinkets.lua`: Loyalty status "N remaining" counting down 5..1, then "Active!"
  - `AzerothAnte/Data/Scrolls.lua` and `AzerothAnte/Data/CardTypes.lua`: Scroll of Chance, Glass and Lucky texts use `{N}` odds via the describe helper
  - `tools/sim/bot.lua`
  - `README.md`
  - `AzerothAnte/AzerothAnte.toc` (`## Version: 0.5.0`)
- Test: `tests/test_trinkets_s.lua`, `tests/test_content.lua`

**Interfaces:**
- The bot keeps buying by rarity and never sells or reorders. It must survive every new hook. When a choice would leave it with negative gold, it never takes it, even with Credit Card.

- [ ] **Step 1: Write failing tests:**
  - `ancient_reroll_excludes_current`;
  - `raised_fist_rank_tie`;
  - `loyalty_status_countdown` ("5 remaining" just after buying, "Active!" on the 6th hand);
  - `chance_texts_show_effective_odds`.
- [ ] **Step 2:** Run `luajit tests/run.lua`. Expected: FAIL on the new tests.
- [ ] **Step 3: Implement.** Then run `luajit tools/sim/sim.lua 200 <deck>` for all five decks. Expected: no errors, and every deck between 8% and 45%. If any deck is outside the band, report the rates and **don't** change targets; the controller rules. Put the rates in the README Balance note and update the README trinket count (117) and features (selling during a blind).
- [ ] **Step 4:** Run all four suites. Expected: green.
- [ ] **Step 5:** Commit: `chore: wave 2 integration, parity fixes, sim, v0.5.0`.
