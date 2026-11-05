# Azeroth Ante Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a WoW addon that plays a complete Balatro-style poker roguelike run (8 stages × 3 blinds) with a WoW skin, resumable across queue waits.

**Architecture:** A pure-Lua game core (`Core/`, `Data/`) with no WoW API calls. All run state is plain tables, so it saves straight into SavedVariables and is unit-tested under LuaJIT. A WoW UI layer (`UI/`) renders the run state and animates scoring from an event list that the core returns. A thin `Queue.lua` maps WoW queue events onto a pure `QueueState` machine.

**Tech Stack:** Lua 5.1 (WoW; tested with LuaJIT 2.1), WoW FrameXML API (frames, AnimationGroups, GameTooltip), Python 3 (stdlib only) to generate TGA textures.

**Spec:** `docs/superpowers/specs/2026-11-05-azeroth-ante-design.md`

## Global Constraints

- Lua 5.1 only: no `goto`, no `//`, no bitwise operators, `unpack` not `table.unpack`.
- Every addon file starts with `local _, ns = ...` and attaches its module to `ns` (e.g. `ns.Cards = Cards`). The only globals are `AzerothAnteDB`, `SLASH_AZEROTHANTE1` and `SlashCmdList.AZEROTHANTE`.
- `Core/` and `Data/` must not call any WoW API, so they run under `luajit tests/run.lua`.
- Run state is plain data: numbers, strings, booleans and tables only. No functions and no metatables. It is stored directly in `AzerothAnteDB`.
- All randomness goes through `ns.RNG` with `run.rng`. Never call `math.random` in `Core/` or `Data/`.
- Mouse only, with no key bindings.
- Blizzard art is referenced by path (`Interface\\Icons\\...`) and never copied into the repo. The only shipped textures are our own TGAs in `Media/`, with power-of-two dimensions.
- Name: "Azeroth Ante". Slash command: `/ante`.
- Targets Retail and WoW Forever (Mainline API).
- Five-of-a-kind, Flush House and Flush Five are omitted, because the fixed 52-card deck makes them impossible.

## Review Focus

1. **Resuming a save made right after a hand.** The UI must render from state without replaying or re-scoring. Pinned in Task 8 (`save_roundtrip_mid_round`).
2. **Play or Discard with 0 or more than 5 cards selected.** It must be rejected, not crash. Pinned in Task 6 (`can_play_rejects_bad_selection`).
3. **Boss rules that block input** (Herod needs exactly 5 cards; Mutanus allows 0 discards). The buttons must be disabled, not just fail silently. Pinned in Task 6 (`herod_requires_five`, `mutanus_no_discards`).
4. **Drawing from an empty draw pile.** It draws what's left with no error. Pinned in Task 2 (`draw_past_empty`).
5. **Corrupt or old-version SavedVariables.** `Save.load` returns nil and a fresh run starts. Pinned in Task 8 (`load_rejects_bad_version`).

---

### Task 1: Test harness, addon skeleton, RNG

**Files:**
- Create: `AzerothAnte/AzerothAnte.toc`, `AzerothAnte/Core/RNG.lua`, `tests/run.lua`, `tests/syntax.lua`, `tests/test_rng.lua`

**Interfaces:**
- Produces:
  - `luajit tests/run.lua [pattern]`. It reads `AzerothAnte/AzerothAnte.toc`, loads every listed file under `Core/` or `Data/` in TOC order via `loadfile(path)("AzerothAnte", ns)`, then runs each `tests/test_*.lua` whose name contains `pattern`. Each test file is called as `chunk(ns, T)`, where `T.test(name, fn)`, `T.eq(actual, expected, msg)` (deep equality) and `T.ok(cond, msg)`. The runner prints a pass/fail line per test and calls `os.exit(1)` on any failure.
  - `luajit tests/syntax.lua` compiles every `.lua` under `AzerothAnte/` with `loadfile` and exits 1 on any error.
  - RNG, where `r = {s = number}` is plain data:
    - `ns.RNG.new(seed) -> r`
    - `ns.RNG.next(r) -> float in [0,1)`
    - `ns.RNG.int(r, lo, hi) -> int` (inclusive)
    - `ns.RNG.shuffle(r, list)` (in place, Fisher–Yates)
    - `ns.RNG.pick(r, list) -> element`
- TOC header:
  - `## Interface: 120000` is a placeholder. Liam replaces it with the real Retail and Forever numbers from `/dump select(4, GetBuildInfo())`, comma-separated.
  - `## Title: Azeroth Ante`
  - `## Notes: Poker roguelike for queue waits`
  - `## SavedVariables: AzerothAnteDB`
  - `## Version: 0.1.0`

- [ ] **Step 1: Write `tests/test_rng.lua`**
  - `same_seed_same_sequence`: two `RNG.new(42)` give identical `next` values 10 times.
  - `int_in_range`: 1000 calls of `int(r,1,6)` all fall within 1..6, and every value 1..6 appears.
  - `shuffle_is_permutation`: shuffling `{1..52}` gives the same multiset, and the order differs from the identity.
  - `state_is_plain`: `type(r.s) == "number"` and `getmetatable(r) == nil`.
- [ ] **Step 2:** Write `tests/run.lua` and `tests/syntax.lua`. Then run `luajit tests/run.lua rng`. Expected: FAIL (RNG missing).
- [ ] **Step 3: Implement the RNG with Park–Miller (minimal standard).**
  - `s = (seed % 2147483646) + 1`
  - `s = (16807 * s) % 2147483647`
  - `next = (s - 1) / 2147483646`
  - All of this is exact in doubles.
  - Add `Core/RNG.lua` to the `.toc`.
- [ ] **Step 4:** Run `luajit tests/run.lua rng && luajit tests/syntax.lua`. Expected: all pass, exit 0.
- [ ] **Step 5:** Commit with the message `feat: test harness, toc, seeded RNG`.

### Task 2: Cards and deck

**Files:** Create `AzerothAnte/Core/Cards.lua`, `tests/test_cards.lua`. Modify `.toc`.

**Interfaces:**
- Consumes: `ns.RNG`.
- Produces: a card is `{rank = 2..14, suit = "S"|"H"|"C"|"D", id = 1..52}`, where 11=J, 12=Q, 13=K, 14=A.
  - `Cards.newDeck() -> list of 52`
  - `Cards.shuffledDeck(r) -> list`
  - `Cards.draw(pile, hand, n)`: moves up to n cards from the end of `pile` into `hand`, and returns the number drawn.
  - `Cards.chipValue(card) -> number`: 2–10 = face value, J/Q/K = 10, A = 11.
  - `Cards.isFace(card) -> bool`: ranks 11–13.
  - `Cards.sort(list, mode)`: `mode` is `"rank"` (rank desc, then suit order S,H,C,D) or `"suit"` (suit order, then rank desc).
  - `Cards.label(card) -> "2".."10","J","Q","K","A"`.
  - `Cards.SUITS = {"S","H","C","D"}`; `Cards.SUIT_NAMES = {S="Spades",H="Hearts",C="Clubs",D="Diamonds"}`.

- [ ] **Step 1: Write the tests.**
  - `new_deck_52_unique`: 52 cards with unique ids, and 13 of each suit.
  - `chip_values`: rank 2 = 2, rank 10 = 10, rank 12 = 10, rank 14 = 11.
  - `is_face`: 11, 12 and 13 are true; 10 and 14 are false.
  - `sort_rank`: `A♠, 2♥, K♣` sorts to `A,K,2`.
  - `draw_past_empty`: drawing 8 from a 3-card pile returns 3, the hand has 3 cards and the pile is empty.
- [ ] **Step 2:** Run `luajit tests/run.lua cards`. Expected: FAIL.
- [ ] **Step 3:** Implement `Cards.lua` and add it to the `.toc` after RNG.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit with the message `feat: cards and deck`.

### Task 3: Hand data and hand evaluation

**Files:** Create `AzerothAnte/Data/Hands.lua`, `AzerothAnte/Core/HandEval.lua`, `tests/test_handeval.lua`. Modify `.toc` (Data/Hands before Core/HandEval).

**Interfaces:**
- Consumes: Card shape from Task 2.
- Produces:
  - `ns.Hands.order`: list of hand ids, weakest first:
    `HIGH_CARD, PAIR, TWO_PAIR, THREE_KIND, STRAIGHT, FLUSH, FULL_HOUSE, FOUR_KIND, STRAIGHT_FLUSH`.
  - `ns.Hands.def[id] = {name, chips, mult, lvlChips, lvlMult}`, with these values (Balatro's):

    | id | name | chips | mult | lvlChips | lvlMult |
    |---|---|---|---|---|---|
    | HIGH_CARD | High Card | 5 | 1 | 10 | 1 |
    | PAIR | Pair | 10 | 2 | 15 | 1 |
    | TWO_PAIR | Two Pair | 20 | 2 | 20 | 1 |
    | THREE_KIND | Three of a Kind | 30 | 3 | 20 | 2 |
    | STRAIGHT | Straight | 30 | 4 | 30 | 3 |
    | FLUSH | Flush | 35 | 4 | 15 | 2 |
    | FULL_HOUSE | Full House | 40 | 4 | 25 | 2 |
    | FOUR_KIND | Four of a Kind | 60 | 7 | 30 | 3 |
    | STRAIGHT_FLUSH | Straight Flush | 100 | 8 | 40 | 4 |

  - `ns.Hands.base(id, level) -> chips, mult`: `chips + (level-1)*lvlChips` and `mult + (level-1)*lvlMult`.
  - `HandEval.evaluate(cards) -> handId, scoringIdx`. `cards` is 1–5 cards and `scoringIdx` is a list of indices into `cards`, ascending. Straights and flushes need exactly 5 cards. A-2-3-4-5 counts as a straight. Which cards score:
    - High Card: the single highest card.
    - Pair, Two Pair, Three of a Kind, Four of a Kind: only the matched cards.
    - Straight, Flush, Full House, Straight Flush: all 5.
  - `HandEval.contains(cards) -> set`, e.g. `{PAIR=true, TWO_PAIR=true, HIGH_CARD=true}`. This follows Balatro's "contains" rules: Full House contains THREE_KIND, PAIR and TWO_PAIR; Straight Flush contains STRAIGHT and FLUSH; Four of a Kind contains THREE_KIND and PAIR; every hand contains HIGH_CARD.

- [ ] **Step 1: Write the tests.** Each of the 9 hand types has a case asserting both `handId` and `scoringIdx`. Also cover:
  - `ace_low_straight`: A,2,3,4,5 is a STRAIGHT.
  - `four_card_flush_not_flush`: 4 hearts is HIGH_CARD.
  - `pair_scoring_only_pair`: K,K,2,5,9 gives the indices of the two kings.
  - `full_house_contains`: the contains set includes PAIR, TWO_PAIR and THREE_KIND.
  - `base_levels`: `Hands.base("PAIR", 3)` is `40, 4`.
- [ ] **Step 2:** Run `luajit tests/run.lua handeval`. Expected: FAIL.
- [ ] **Step 3:** Implement both files and add them to the `.toc`.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit with the message `feat: hand data and evaluation`.

### Task 4: Scoring engine

**Files:** Create `AzerothAnte/Core/Scoring.lua`, `tests/test_scoring.lua`. Modify `.toc` (after Data files from Task 5's slot; for now place after HandEval).

**Interfaces:**
- Consumes: `HandEval`, `Hands`, `Cards`, `ns.Trinkets.def[id]` and `ns.Bosses.def[id]`. The two defs are defined in Task 5; tests inject stub defs into `ns.Trinkets.def` and `ns.Bosses.def`.
- Trinket def hooks (all optional):
  - `onCard(ctx, card) -> effect|nil`
  - `onHand(ctx) -> effect|nil`
  - `onRoundEnd(run) -> goldDelta|nil`
  - `effect = {chips=n, mult=n, xmult=n}`. Any field is optional.
- Boss def fields used here (all optional):
  - `debuff(card) -> bool`: a debuffed card scores no chips and triggers no `onCard`.
  - `halveBase = true`: base chips become `floor(chips/2)` and base mult becomes `max(1, floor(mult/2))`.
- Produces: `Scoring.score(ctx) -> result`.
  - `ctx` fields:
    - `cards`: the played cards.
    - `handLevels`: `{[handId] = level}`.
    - `trinkets`: list of `{id=}`.
    - `bossId`: string or nil.
    - `rng`.
    - `handsPlayedTotal`: includes this hand.
    - `isLastHand`: bool.
    - `discardsLeft`, `gold`.
  - `ctx.contains` is set by `score` from `HandEval.contains`.
  - `result = {handId, chips, mult, total, events}`, where `total = math.floor(chips * mult)`.
  - `events`, in order:
    - `{kind="base", handId, chips, mult}`
    - Per scoring card, left to right: either `{kind="card", index=i, chips=n}` or `{kind="debuff", index=i}`. Each card is followed by its `onCard` effects, trinkets left to right, as `{kind="trinket", slot=k, chips=, mult=, xmult=, index=i}`.
    - Then each `onHand` effect, trinkets left to right, as `{kind="trinket", slot=k, chips=, mult=, xmult=}`.
    - Finally `{kind="total", total}`.
  - Inside one effect, apply chips, then `+mult`, then `×xmult`. Every event carries the running `chips` and `mult` after it is applied, as `runChips` and `runMult`, so the UI can display without recomputing.

- [ ] **Step 1: Write the tests.**
  - `pair_of_kings_level1`: (10+10+10) × 2 = 60. The events are base, card, card, total.
  - `debuffed_card_scores_nothing`: with a boss that debuffs Spades, K♠ K♥ gives 10+10 chips and a debuff event at index 1.
  - `halve_base`: Rivendare-style boss with a Pair at level 1 gives base 5, mult 1.
  - `trinket_order`: stub A `onHand {mult=4}` and stub B `onHand {xmult=2}` give mult (2+4)×2 = 12. Swapping the order gives 2×2+4 = 8.
  - `oncard_per_scoring_card_only`: an `onCard {mult=1}` trinket with a pair plus 3 kickers adds +2 mult, not +5.
  - `events_carry_running_totals`: the last event's `runChips × runMult` floored equals `total`.
- [ ] **Step 2:** Run `luajit tests/run.lua scoring`. Expected: FAIL.
- [ ] **Step 3:** Implement `Scoring.lua`.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit with the message `feat: scoring engine with event stream`.

### Task 5: Content data (trinkets, bosses, decks)

**Files:** Create `AzerothAnte/Data/Trinkets.lua`, `AzerothAnte/Data/Bosses.lua`, `AzerothAnte/Data/Decks.lua`, `tests/test_content.lua`. Modify `.toc`: the Data files load before `Core/Scoring.lua`.

**Interfaces:**
- Consumes: the hook shapes from Task 4, plus `HandEval.contains` via `ctx.contains`, `Cards.isFace` and `RNG.next`.
- Produces:
  - `ns.Trinkets.order` (list of ids).
  - `ns.Trinkets.def[id] = {id, name, desc, icon, rarity="common"|"uncommon"|"rare", cost, onCard?, onHand?, onRoundEnd?}`. `icon` is a full `Interface\\Icons\\...` path. The implementer picks plausible existing icon names, which get checked in-game in Task 14.
  - The exact 20 trinkets:

| id | name | rarity/cost | effect |
|---|---|---|---|
| BLOODLUST | Drums of Bloodlust | rare 8 | onHand: ×3 mult when `handsPlayedTotal % 5 == 0` |
| ARCANE_INTELLECT | Arcane Intellect | common 4 | onHand: +4 mult |
| FORTITUDE | Power Word: Fortitude | common 4 | onHand: +50 chips |
| WHETSTONE | Whetstone | common 5 | onCard: Spade → +3 mult |
| HEALTHSTONE | Healthstone | common 5 | onCard: Heart → +3 mult |
| OGRE_CUDGEL | Ogre Cudgel | common 5 | onCard: Club → +3 mult |
| JEWELERS_KIT | Jeweler's Kit | common 5 | onCard: Diamond → +3 mult |
| HEARTHSTONE | Hearthstone | common 5 | onRoundEnd: +3 gold |
| LUCKY_CHARM | Gnomish Luck Charm | uncommon 6 | onHand: if `RNG.next(ctx.rng) < 0.25` → +20 mult |
| EXECUTE | Execute | uncommon 7 | onHand: ×3 mult if `ctx.isLastHand` |
| COMBO_POINTS | Combo Points | common 5 | onHand: +20 chips × `ctx.discardsLeft` |
| TWIN_BLADES | Twin Blades | common 4 | onHand: +8 mult if contains PAIR |
| CLEAVE | Cleave | common 5 | onHand: +12 mult if contains THREE_KIND |
| MULTI_SHOT | Multi-Shot | uncommon 6 | onHand: +12 mult if contains STRAIGHT |
| ELEMENTAL | Elemental Attunement | uncommon 6 | onHand: +10 mult if contains FLUSH |
| ROYAL_GUARD | Royal Guard | common 5 | onCard: face card → +30 chips |
| BATTLE_SHOUT | Battle Shout | uncommon 6 | onHand: +3 mult × `#ctx.trinkets` |
| GOBLIN_BANK | Goblin Bank | uncommon 6 | onHand: +1 mult per 5 gold (`floor(gold/5)`) |
| AVENGING_WRATH | Avenging Wrath | rare 8 | onHand: ×2 mult |
| HUNTERS_MARK | Hunter's Mark | rare 8 | onCard: Ace → ×1.5 mult |

- `ns.Bosses.pool` lists 8 ids (`HOGGER, VANCLEEF, ARUGAL, MUTANUS, HEROD, RIVENDARE, ONYXIA, VAELASTRASZ`). Each run draws 7 distinct ids from it for stages 1–7. `ns.Bosses.FINAL = "RAGNAROS"`.
- `ns.Bosses.def[id] = {id, name, desc, targetMult=2, debuff?, halveBase?, hands?, discards?, mustPlay?}`:

| id | name | rule |
|---|---|---|
| HOGGER | Hogger | debuff face cards |
| VANCLEEF | Edwin VanCleef | debuff Spades |
| ARUGAL | Archmage Arugal | debuff Hearts |
| VAELASTRASZ | Vaelastrasz the Corrupt | debuff Diamonds |
| MUTANUS | Mutanus the Devourer | `discards = 0` |
| HEROD | Herod | `mustPlay = 5` |
| RIVENDARE | Baron Rivendare | `halveBase = true` |
| ONYXIA | Onyxia | `hands = 1`, `targetMult = 1` |
| RAGNAROS | Ragnaros the Firelord | `targetMult = 4` (final boss, stage 8) |

- `ns.Decks.order` and `ns.Decks.def[id] = {id, name, desc, hands, discards, gold}`:
  - ADVENTURER: 4 hands, 3 discards, 4 gold
  - WARRIOR: 5, 3, 4
  - ROGUE: 4, 4, 4
  - GOBLIN: 4, 3, 10

- [ ] **Step 1: Write the tests.**
  - `twenty_trinkets_complete`: 20 ids. Each def has name, desc, an icon starting `Interface\\Icons\\`, a valid rarity, a numeric cost, and at least one hook.
  - One test per trinket, calling the hook directly with a minimal ctx and asserting the exact effect table, or nil when the condition fails.
  - `bosses_complete`: 8 in the pool, the FINAL def exists, and each has name and desc.
  - `decks_values`: exact numbers for all four decks.
- [ ] **Step 2:** Run `luajit tests/run.lua content`. Expected: FAIL.
- [ ] **Step 3:** Implement the three data files and add them to the `.toc` before `Core/Scoring.lua`.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS (including Task 4's scoring tests).
- [ ] **Step 5:** Commit with the message `feat: trinkets, bosses, decks`.

### Task 6: Run state machine

**Files:** Create `AzerothAnte/Core/Run.lua`, `tests/test_run.lua`. Modify `.toc` (after Scoring).

**Interfaces:**
- Consumes: Tasks 1–5, plus `Shop.open(run)` from Task 7. Until Task 7 lands, tests stub `ns.Shop = {open=function() end}`.
- Produces:
  - `Run.BASE_TARGETS = {300, 800, 2000, 5000, 11000, 20000, 35000, 50000}`
  - `Run.target(stage, blind, bossId)`: `floor(BASE[stage] × (1, 1.5, boss.targetMult)[blind])`.
  - `Run.new(seed, deckId) -> run`, with these fields:
    - `seed`, `rng`, `deckId`
    - `stage=1`, `blind=1` (1 small, 2 big, 3 boss)
    - `phase="blind"`
    - `gold` (from the deck)
    - `handSize=8`, `maxTrinkets=5`
    - `trinkets={}`
    - `handLevels` (every hand at 1)
    - `handsPlayedTotal=0`
    - `bosses` (7 drawn from the pool by RNG, then `"RAGNAROS"` at index 8)
    - `score=0`, `target`, `handsLeft`, `discardsLeft`
    - `pile={}`, `hand={}`
    - `lastResult=nil`, `lastPayout=nil`
  - `Run.bossId(run)`: the current boss id when `blind==3`, else nil.
  - `Run.startBlind(run)`:
    - Sets `phase="play"` and a fresh shuffled 52-card pile.
    - Draws `handSize` cards.
    - Sets hands and discards from the deck, with boss overrides applied.
    - Sets `score=0` and `target`.
  - `Run.canPlay(run, idx) -> ok, reason`. Requires 1–5 unique valid indices and `phase=="play"`. With `mustPlay`, it requires exactly that many.
  - `Run.canDiscard(run, idx) -> ok, reason`. Requires 1–5 cards and `discardsLeft > 0`.
  - `Run.play(run, idx) -> result`:
    1. Increments `handsPlayedTotal`.
    2. Scores via `Scoring.score`, with `isLastHand = (handsLeft == 1)`.
    3. Adds the total to `score` and decrements `handsLeft`.
    4. Removes the played cards and refills the hand to `handSize`.
    5. Sets `lastResult`.
    6. If `score >= target`, calls `Run.winBlind`; otherwise, if `handsLeft == 0`, sets `phase="lost"`.
  - `Run.discard(run, idx)`: removes the cards, decrements `discardsLeft` and refills the hand.
  - `Run.winBlind(run)`:
    - Payout is blind reward (3/4/5) + `handsLeft` × 1 + interest `min(5, floor(gold/5))` + each trinket's `onRoundEnd`.
    - Sets `lastPayout = {reward, hands, interest, trinkets, total}` and adds `total` to `gold`.
    - If stage 8 blind 3, sets `phase="won"`. Otherwise sets `phase="shop"` and calls `Shop.open(run)`.
  - `Run.nextBlind(run)`: from `"shop"`, advances blind (or stage plus blind 1) and sets `phase="blind"`.
  - `Run.sortHand(run, mode)`.

- [ ] **Step 1: Write the tests.**
  - `new_run_shape`: `phase=="blind"`, 8 bosses with `[8]=="RAGNAROS"`, no duplicate bosses, and the run deep-copies equal to itself with no functions.
  - `targets`: `target(1,1)==300`, `target(1,2)==450`, `target(2,3,"HOGGER")==1600`, `target(8,3,"RAGNAROS")==200000`.
  - `start_blind_deals_8`.
  - `can_play_rejects_bad_selection`: `{}`, six indices, a duplicate index and an out-of-range index are all rejected.
  - `herod_requires_five`: `canPlay` with 4 cards is false with a reason.
  - `mutanus_no_discards`: `discardsLeft==0` and `canDiscard` is false.
  - `play_reaches_target_goes_shop`: force the target to 1. After `play`, `phase=="shop"` and gold increases by `3 + handsLeft + interest`.
  - `run_out_of_hands_lost`.
  - `final_boss_win_is_won`.
  - `same_seed_same_run`: two runs with seed 7 play identical first hands.
- [ ] **Step 2:** Run `luajit tests/run.lua run`. Expected: FAIL.
- [ ] **Step 3:** Implement `Run.lua`.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit with the message `feat: run state machine`.

### Task 7: Shop

**Files:** Create `AzerothAnte/Core/Shop.lua`, `tests/test_shop.lua`. Modify `.toc` (before Run).

**Interfaces:**
- Consumes: `Run` fields, `Trinkets`, `Hands`, `RNG`.
- Produces:
  - `Shop.open(run)` sets `run.shop = {offers={{id=,cost=},{id=,cost=}}, tome={handId=,cost=3}, rerollCost=5}`.
    - Offers are distinct, not already owned, and drawn by rarity weight: common 70, uncommon 25, rare 5.
    - If fewer than 2 trinkets are eligible, offer fewer.
    - A bought slot becomes `false`, not `nil`, so the list stays dense for saving.
  - `Shop.buyTrinket(run, i) -> ok, err`. `err` is `"gold"`, `"slots"` or `"gone"`.
  - `Shop.buyTome(run) -> ok, err`. It levels `handLevels[handId]` by 1 and sets `tome = false`.
  - `Shop.sell(run, slot) -> gained`. `gained` is `floor(def.cost/2)`, and the trinket is removed from `run.trinkets`.
  - `Shop.reroll(run) -> ok, err`. It pays `rerollCost`, increments it by 1 and re-rolls the trinket offers only.
  - `Shop.tomeName(handId) -> "Tome of " .. Hands.def[handId].name`.

- [ ] **Step 1: Write the tests.**
  - `open_two_distinct_unowned`.
  - `buy_insufficient_gold`.
  - `buy_full_slots`.
  - `buy_ok_deducts_and_adds`.
  - `tome_levels_hand`.
  - `sell_half_cost`: Avenging Wrath gives 4.
  - `reroll_cost_increments`: 5 then 6.
  - `rarity_weights_roughly`: over 2000 opens with a fixed seed, commons are more than 55% and rares less than 12%.
- [ ] **Step 2:** Run `luajit tests/run.lua shop`. Expected: FAIL.
- [ ] **Step 3:** Implement `Shop.lua`. Remove the Shop stub from the Run tests.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit with the message `feat: shop`.

### Task 8: Save/resume and queue state machine

**Files:** Create `AzerothAnte/Core/Save.lua`, `AzerothAnte/Core/QueueState.lua`, `tests/test_save.lua`, `tests/test_queuestate.lua`. Modify `.toc`.

**Interfaces:**
- Produces:
  - `Save.VERSION = 1`
  - `Save.store(db, run)` deep-copies `run` into `db.run` and sets `db.version = Save.VERSION`.
  - `Save.load(db) -> run|nil`. It returns nil if `db` is nil, `db.version ~= VERSION`, `db.run` is not a table or `db.run.phase` is not a string. Otherwise it returns a deep copy.
  - `Save.clear(db)`.
  - `QueueState.new() -> qs = {queued=false, paused=false}`
  - `QueueState.handle(qs, ev) -> action|nil`, with the event-to-action mapping in this table:

| event | state change | returns |
|---|---|---|
| `"QUEUE_JOINED"` | when not queued: `queued=true` | `"show"` (nil if already queued) |
| `"QUEUE_LEFT"` | `queued=false`, `paused=false` | nil |
| `"PROPOSAL"` | `paused=true` | `"pause"` |
| `"PROPOSAL_FAILED"` | `paused=false` | `"resume"` |
| `"ACCEPTED"` | `queued=false`, `paused=false` | `"hide"` |
| `"COMBAT"` | none | `"hide"` |

- [ ] **Step 1: Write the tests.**
  - `save_roundtrip_mid_round`: start a blind, play one hand, then store and load. The loaded run deep-equals the original, playing the same indices on both gives identical results, and mutating the loaded run doesn't touch `db.run`.
  - `load_rejects_bad_version`: version 0, nil db, `run="x"` and a missing phase all return nil.
  - One QueueState test per row of the table.
  - `join_twice_shows_once`.
- [ ] **Step 2:** Run `luajit tests/run.lua save` and `luajit tests/run.lua queue`. Expected: FAIL.
- [ ] **Step 3:** Implement both files and add them to the `.toc`.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit with the message `feat: save/resume and queue state`.

### Task 9: Media (suit icons and card back)

**Files:** Create `tools/gen_media.py` and the generated `AzerothAnte/Media/Suit_S.tga`, `Suit_H.tga`, `Suit_C.tga`, `Suit_D.tga` (64×64) and `AzerothAnte/Media/CardBack.tga` (128×256). Also `tests/test_media.py`.

**Interfaces:**
- Produces: the texture paths `Interface\\AddOns\\AzerothAnte\\Media\\Suit_S` (no extension in Lua) and the same for the others.
- Suits are white silhouettes with an alpha channel, so the UI tints them with `SetVertexColor`. Each suit is a classic shape with a small WoW-flavour accent: a sword-hilt notch on Spades, a gem facet on Diamonds, and so on. That's the implementer's taste.
- The card back is dark with a gold border and an emblem.
- Format: uncompressed 32-bit BGRA TGA (image type 2), top-left origin (descriptor 0x28). Anti-alias by 4× supersampling. Python stdlib only.

- [ ] **Step 1:** Write `tests/test_media.py`. For each file it checks the TGA header (type 2, 32 bpp), the dimensions, that the alpha channel has both 0 and 255 pixels, and that the dimensions are powers of two.
- [ ] **Step 2:** Run `python3 tests/test_media.py`. Expected: FAIL (files missing).
- [ ] **Step 3:** Write `tools/gen_media.py` and run `python3 tools/gen_media.py`.
- [ ] **Step 4:** Run `python3 tests/test_media.py`. Expected: PASS. Then convert each TGA to PNG (stdlib zlib) in the scratchpad and look at it.
- [ ] **Step 5:** Commit with the message `feat: suit and card back textures`.

### Task 10: Main window and static views

**Files:** Create `AzerothAnte/UI/Theme.lua`, `AzerothAnte/UI/MainFrame.lua`, `AzerothAnte/UI/Sidebar.lua`, `AzerothAnte/UI/TrinketRow.lua`. Modify `.toc` (UI files after Core).

**Interfaces:**
- Consumes: `run` fields (Task 6), `Trinkets.def`, `Bosses.def`, `Hands.def`.
- Produces:
  - `ns.UI.Theme`: colours (`gold`, `parchment`, `bg`, `chips` blue, `mult` red), fonts and sizes.
  - `ns.UI.Main`:
    - `.Create()` builds layout A:
      - A `BackdropTemplate` frame named `AzerothAnteFrame`, 900×560 by default.
      - Movable, clamped to screen and resizable via a corner grip (`SetResizeBounds(720,450)`). Content scales with the frame.
      - Close button and title "Azeroth Ante".
      - Regions:
        - `.sidebar` on the left, at 28% of the width.
        - `.trinketRow` across the top right.
        - `.playArea` in the middle.
        - `.handArea` along the bottom.
        - `.buttons` (Play, Discard, Sort Rank, Sort Suit) below the hand.
    - `.Show()`, `.Hide()` and `.Toggle()`.
    - `.Render(run)` updates every view from state, with no animation.
    - `.SetRun(run)`.
    - The window position and size are saved in `AzerothAnteDB.window`.
  - `ns.UI.Sidebar.Update(run, chips, mult)` shows:
    - the boss name, or "Small Blind" / "Big Blind", plus the boss rule text
    - the target and score
    - chips × mult boxes
    - hands and discards left
    - gold
    - stage and blind
  - `ns.UI.TrinketRow.Update(run)` shows up to 5 slots with icon and a GameTooltip (name, desc, rarity). `TrinketRow.Pulse(slot)` is a short scale animation.

- [ ] **Step 1:** Implement the files in this order: Theme, MainFrame, Sidebar, TrinketRow.
- [ ] **Step 2:** Run `luajit tests/syntax.lua && luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 3:** Commit with the message `feat: main window, sidebar, trinket row`.

### Task 11: Cards and hand interaction

**Files:** Create `AzerothAnte/UI/CardWidget.lua`, `AzerothAnte/UI/HandView.lua`. Modify `.toc`, `UI/MainFrame.lua` (wire buttons).

**Interfaces:**
- Consumes: Task 10 regions, `Run.canPlay`, `Run.canDiscard`, `Run.play`, `Run.discard`, `Run.sortHand`, and the media paths.
- Produces:
  - `ns.UI.CardWidget.Acquire(parent) -> w` and `.Release(w)` (pooled). Each widget has:
    - `w:SetCard(card)`: parchment face, rank text top-left and bottom-right, suit texture tinted by suit, red for Hearts and Diamonds.
    - `w:SetSelected(bool)`: lifts by 24px.
    - `w:SetDebuffed(bool)`: grey overlay.
    - `w:Pop()`: score pop.
  - Hover raises the card by 8px with a 0.08s ease. Selected cards rise 24px.
  - `ns.UI.HandView.Update(run, animate)` lays out the hand in a fan-free row with tween-to-position. `animate=true` deals new cards from the deck position with a 0.04s stagger.
  - `HandView.Selected() -> idx list` and `HandView.ClearSelection()`.
  - Clicking toggles selection. A sixth click is refused with a small shake.
  - The Play and Discard buttons enable from `canPlay` / `canDiscard` after every selection change. A disabled button shows its reason in a tooltip.
  - Played cards animate into `.playArea` and stay there during the tally (Task 12). Discards slide off to the right and fade.
  - Sort buttons re-layout with a tween.
  - All motion uses one shared `OnUpdate` driver that runs only while tweens are active and unregisters itself when idle.

- [ ] **Step 1:** Implement `CardWidget.lua`.
- [ ] **Step 2:** Implement `HandView.lua` and wire the buttons in MainFrame.
- [ ] **Step 3:** Run `luajit tests/syntax.lua && luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 4:** Commit with the message `feat: card widgets and hand interaction`.

### Task 12: Score tally animation

**Files:** Create `AzerothAnte/UI/Tally.lua`. Modify `UI/HandView.lua` (call tally after play).

**Interfaces:**
- Consumes: `result.events` (Task 4), `Sidebar.Update`, `TrinketRow.Pulse`, `CardWidget:Pop`.
- Produces: `ns.UI.Tally.Play(result, playedWidgets, onDone)`. It steps through the events every 0.28s:
  - `base` sets the sidebar to the base chips × mult and shows the hand name.
  - `card` pops the card and floats a `+N` chip number in blue.
  - `debuff` shakes the card grey.
  - `trinket` pulses the slot and floats `+N` or `×N` mult in red.
  - `total` counts the score up over 0.5s.
- Each event shows `runChips` / `runMult`. Input is locked while it runs (`Tally.IsBusy()`). Clicking the play area speeds it up 4×. When it finishes, `onDone` is called, the played cards slide away, and the window re-renders for the new phase.

- [ ] **Step 1:** Implement `Tally.lua` and call it from HandView after `Run.play`.
- [ ] **Step 2:** Run `luajit tests/syntax.lua && luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 3:** Commit with the message `feat: animated score tally`.

### Task 13: Screens (new run, blind, shop, end)

**Files:** Create `AzerothAnte/UI/Screens.lua`. Modify `UI/MainFrame.lua` (`Render` dispatches on `run.phase`).

**Interfaces:**
- Consumes: `Run.new`, `Run.startBlind`, `Run.nextBlind`, all of `Shop.*`, `Decks`, `Bosses`, and `Save.store` / `Save.clear`.
- Produces: `ns.UI.Screens.Show(name, run)`, where `name` is one of:
  - `"newrun"`: pick one of four decks, then `Run.new(time()-based seed, deckId)`.
  - `"blind"`: shows the upcoming blind, target and boss rule, with a Start button that calls `Run.startBlind`.
  - `"shop"`: shows the payout breakdown from `lastPayout`, 2 trinket offers with costs, a tome offer, Reroll (cost), Next, and the owned trinkets with a Sell button for each. Buy errors show inline.
  - `"won"` / `"lost"`: a summary (stage reached, best hand) and a New Run button that calls `Save.clear`.
  - `"paused"`: an overlay over everything reading "Queue popped!" with a Resume button.
- `Main.Render` maps phases to screens: `nil` → newrun, `blind` → blind, `play` → the game view, `shop` → shop, `won` / `lost` → end.
- Every state-changing click ends with `Save.store(AzerothAnteDB, run)`. That covers after each hand and at round boundaries, as the spec requires.

- [ ] **Step 1:** Implement `Screens.lua` and the Render dispatch.
- [ ] **Step 2:** Run `luajit tests/syntax.lua && luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 3:** Commit with the message `feat: run, blind, shop and end screens`.

### Task 14: Queue wiring, bootstrap, README

**Files:** Create `AzerothAnte/Queue.lua`, `AzerothAnte/AzerothAnte.lua` and `README.md`. Modify the `.toc`; these two files are last.

**Interfaces:**
- Consumes: `QueueState`, `Save`, `UI.Main`, `UI.Screens`.
- Produces:
  - `AzerothAnte.lua`:
    - On `ADDON_LOADED` for this addon it initialises `AzerothAnteDB = AzerothAnteDB or {}`, loads the run via `Save.load` and creates the main frame.
    - `/ante` toggles the window.
  - `Queue.lua` registers the queue events and turns them into QueueState events. The implementer verifies the event names against the current API docs:
    - `LFG_UPDATE`, `LFG_QUEUE_STATUS_UPDATE` and `UPDATE_BATTLEFIELD_STATUS` are checked with `GetLFGMode(category)` (`"queued"`) across `LE_LFG_CATEGORY_*` and `GetBattlefieldStatus(i)` (`"queued"`). These produce `QUEUE_JOINED` / `QUEUE_LEFT`.
    - `LFG_PROPOSAL_SHOW`, or battlefield status `"confirm"`, produces `PROPOSAL`.
    - `LFG_PROPOSAL_FAILED` produces `PROPOSAL_FAILED`.
    - `LFG_PROPOSAL_SUCCEEDED`, or battlefield status `"active"`, produces `ACCEPTED`.
    - `PLAYER_REGEN_DISABLED` produces `COMBAT`.
  - Actions:
    - `show` shows the window.
    - `pause` shows the paused screen and calls `PlaySound(SOUNDKIT.READY_CHECK)`.
    - `resume` closes the overlay.
    - `hide` hides the window.
  - `README.md` covers:
    - what the addon is
    - install: symlink or copy `AzerothAnte/` into `Interface/AddOns` (Retail) or `_forever_/Interface/AddOns` (Forever)
    - setting the `## Interface` numbers from `/dump select(4, GetBuildInfo())`
    - running `luajit tests/run.lua`
    - the in-game test checklist below

- [ ] **Step 1:** Implement `Queue.lua` and `AzerothAnte.lua`, then write the README.
- [ ] **Step 2:** Run `luajit tests/syntax.lua && luajit tests/run.lua && python3 tests/test_media.py`. Expected: all pass.
- [ ] **Step 3:** Commit with the message `feat: queue integration, bootstrap, README`.
- [ ] **Step 4: In-game checklist** (Liam runs this; it isn't automated):
  - [ ] `/ante` opens it.
  - [ ] Drag and resize work.
  - [ ] Card hover and select feel smooth.
  - [ ] The tally plays.
  - [ ] Buying in the shop works.
  - [ ] `/reload` mid-round resumes on the same hand.
  - [ ] Joining a queue opens the window.
  - [ ] A queue pop shows the overlay and plays the sound.
  - [ ] Accepting hides the window.
  - [ ] Entering combat hides the window.
  - [ ] No trinket icon shows as a question mark.
