# Deck Building & Card Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Balatro's deck building to Azeroth Ante: consumables (Scrolls/Tomes/Relics), card enhancements, editions and seals, packs, a mutable deck and the secret hands, with Balatro's effects and WoW names.

**Architecture:**
- The run gains a persistent `run.deck` of card tables. The hand and pile reference the same tables, and `Deck.relink` restores that identity after a load.
- Scoring is extended in place and still emits one event stream for the tally.
- Consumable effects are data-driven functions in `Data/`, run by a single `Core/Consumables.lua`.
- The shop is rewritten around generic card and pack slots.
- The UI extends the existing widgets and the smoke harness.

**Tech Stack:** Lua 5.1 (LuaJIT for tests), WoW Mainline FrameXML API (Retail + Forever 16001), Python 3 stdlib for textures.

**Spec:** `docs/superpowers/specs/2026-11-05-deck-building-design.md`. Effect tables, values, odds and prices are taken from it verbatim. When a task says "spec §X", copy those exact values.

## Global Constraints

- Lua 5.1 only:
  - no `goto`, no `//`, no bitwise ops;
  - use `unpack`, not `table.unpack`;
  - every file starts with `local _, ns = ...` and attaches to `ns`.
- Only these globals are allowed: `AzerothAnteDB`, `SLASH_AZEROTHANTE1`, `SlashCmdList.AZEROTHANTE`.
- `Core/` and `Data/` never call the WoW API. All randomness goes through `ns.RNG` with `run.rng`.
- Run state is plain data (no functions or metatables) and is saved whole. `Save.VERSION = 2`; a v1 save fails to load and the player starts fresh.
- Effects copy Balatro exactly. If WoW can't do something, only the visual is approximated, never the rules.
- Mouse only. The only shipped textures are our own power-of-two TGAs. Blizzard icons are referenced by path.
- The anti-goal is clunky interaction: everything is animated, with no stuck states and no ambiguity about what a card will affect.
- Every change keeps `luajit tests/run.lua`, `luajit tests/smoke_ui.lua`, `luajit tests/syntax.lua` and `python3 tests/test_media.py` green.

## Review Focus

1. **Reloading with a pack open (including an Arcana hand):** the same choices and hand come back, so there's no reroll. Pinned in Task 7 by `open_pack_survives_save`.
2. **A Scroll used after a reload:** it must change the deck as well as the hand, so card identity holds across a save. Pinned in Task 4 by `relink_after_load_shares_tables`.
3. **A deck destroyed down below hand size:** draw what's left, keep the blind playable, never crash. Pinned in Task 4 by `tiny_deck_draws_available`.
4. **A Relic overfilling the hand (more than handSize cards):** the selection rule (1–5) still holds, and refills never overdraw. Pinned in Task 6 by `relic_overfills_hand`.
5. **Consumable slots full when something creates one** (Blue/Purple seal, Knowledge, Stars): skip silently, and Use is disabled with a reason. Pinned in Task 5 by `creator_respects_slots`.

---

### Task 1: Card model v2, Deck module, Stone/Wild-aware Cards

**Files:**
- Create `Core/Deck.lua` and `tests/test_deck.lua`.
- Modify `Core/Cards.lua`, `tests/test_cards.lua` and `AzerothAnte.toc` (put `Core\Deck.lua` after `Core\Cards.lua`).

**Interfaces:**
- Produces:
  - Card shape: `{id, rank?, suit?, enh?, ed?, seal?}`. `rank` is nil for Stone (`enh == "STONE"`), and `suit` is nil only for Stone.
  - `Cards.hasSuit(card, suit) -> bool`. Wild is true for every suit; Stone is always false.
  - `Cards.isStone(card)`.
  - `Cards.chipValue(card)`: Stone gives 0.
  - `Cards.isFace(card)`: Stone gives false.
  - `Cards.sort(list, mode)`: Stone cards sort last.
  - `Cards.label(card)`: Stone gives `""`.
  - `Deck.new() -> list of 52` with ids 1..52.
  - `Deck.add(run, card) -> card`: assigns `card.id = run.nextCardId`, increments it and appends to `run.deck`.
  - `Deck.copy(run, card) -> card`: a new id with the same rank, suit, enh, ed and seal; added to the deck.
  - `Deck.find(run, id)`.
  - `Deck.destroy(run, id)`: removes the card from `run.deck`, `run.hand` and `run.pile`.
  - `Deck.shuffledPile(run) -> list`: references to `run.deck` entries, shuffled with `run.rng`.
  - `Deck.relink(run)`: replaces every `run.hand`/`run.pile` entry with the `run.deck` table that has the same id.
  - `Deck.handSize(run) -> number`: `run.baseHandSize + run.handSizeMod + (count of NEGATIVE playing cards in run.deck)`.
- `Cards.newDeck` and `Cards.shuffledDeck` stay as thin wrappers (`Deck.new` and a shuffled `Deck.new`) so the suite stays green. Task 4 removes them.

- [ ] **Step 1:** Write the tests.
  - `cards_stone_and_wild`:
    - Stone: `hasSuit(stone, "S") == false`, `chipValue(stone) == 0`, `isFace(stone) == false`.
    - Wild: `hasSuit(wild, "H")` and `hasSuit(wild, "S")` are both true.
    - Sorting `{stone, 2♠, A♥}` by rank gives `A, 2, stone`.
  - `deck_new_ids`: ids are 1..52 and unique.
  - `deck_add_copy_destroy`:
    - `add` gives id 53 and the deck has 53 cards.
    - `copy` gives id 54 with the same `enh`.
    - `destroy(54)` removes the card from `deck`, `hand` and `pile`.
  - `deck_relink`: after deep-copying `hand` (simulating a load), `relink` makes `run.hand[1] == Deck.find(run, run.hand[1].id)`, compared with rawequal.
  - `hand_size_negative`: base 8, mod −1, plus two NEGATIVE cards gives 9.
- [ ] **Step 2:** Run `luajit tests/run.lua deck` and `luajit tests/run.lua cards`. Expected: FAIL.
- [ ] **Step 3:** Implement `Core/Deck.lua` and the Cards changes.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: everything PASSES.
- [ ] **Step 5:** Commit `feat: card model v2 and Deck module`.

### Task 2: Secret hands and Wild/Stone-aware HandEval

**Files:** Modify `Data/Hands.lua`, `Core/HandEval.lua` and `tests/test_handeval.lua`.

**Interfaces:**
- Produces:
  - `Hands.order` appends `FIVE_KIND`, `FLUSH_HOUSE`, `FLUSH_FIVE` in that order, with values from spec §Hands. Each new def has `secret = true` (FIVE_KIND 120×12 +35/+3; FLUSH_HOUSE 140×14 +40/+4; FLUSH_FIVE 160×16 +50/+3).
  - `Hands.visible(run) -> list of ids`: non-secret hands, plus secret ones where `run.seenHands[id]`.
  - `HandEval.evaluate(cards) -> handId, scoringIdx`:
    - Stone cards never form part of a hand, but are always included in `scoringIdx`.
    - A Wild card counts toward a flush in any suit.
    - Precedence, highest first: FLUSH_FIVE, FLUSH_HOUSE, FIVE_KIND, STRAIGHT_FLUSH, then the v1 order.
  - `HandEval.contains(cards)`: FIVE_KIND contains FOUR_KIND, THREE_KIND and PAIR. FLUSH_HOUSE contains FULL_HOUSE, FLUSH, THREE_KIND, TWO_PAIR and PAIR. FLUSH_FIVE contains FIVE_KIND, FLUSH and everything FIVE_KIND contains.

- [ ] **Step 1:** Write the tests.
  - `five_kind`: five 9s.
  - `flush_house`: K♥ K♥ K♥ 4♥ 4♥.
  - `flush_five`: 5×7♠.
  - `wild_completes_flush`: four hearts plus a Wild spade gives FLUSH.
  - `stone_always_scores`: Pair of K plus a Stone gives PAIR, and `scoringIdx` includes the Stone's index.
  - `stone_breaks_straight`: 4 consecutive cards plus a Stone is not a STRAIGHT.
  - `secret_hidden_until_seen`: `#Hands.visible({seenHands={}}) == 9`, and 10 once `FIVE_KIND` is seen.
- [ ] **Step 2:** Run `luajit tests/run.lua handeval`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `luajit tests/run.lua handeval`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: secret hands, Wild and Stone in hand evaluation`.

### Task 3: Card-type data and Scoring v2

**Files:**
- Create `Data/CardTypes.lua` and put it in `.toc` after `Data\Hands.lua`.
- Modify `Core/Scoring.lua`, `Data/Trinkets.lua` (the trinket instance gains `ed`, and suit checks move to `hasSuit`), `Data/Bosses.lua` (suit debuffs move to `hasSuit`) and `tests/test_scoring.lua`.

**Interfaces:**
- Produces:
  - `ns.CardTypes.enh[id]`, `.ed[id]` and `.seal[id]`. Each is `{name, desc}` with the spec §Card types text and Balatro names.
  - `ns.CardTypes.ED_COST = {FOIL=2, HOLO=3, POLY=5, NEGATIVE=5}`.
  - `ns.CardTypes.ED_ODDS = {FOIL=0.02, HOLO=0.014, POLY=0.003, NEGATIVE=0.003}`.
  - `ns.CardTypes.AURA_WEIGHTS = {FOIL=50, HOLO=35, POLY=15}`.
  - `ns.CardTypes.rollEdition(r, allowNegative) -> id|nil`, using ED_ODDS.
  - `ns.CardTypes.rollAura(r) -> id`.
- `Scoring.score(ctx)` gains:
  - inputs `ctx.held` (cards in hand that weren't played) and `ctx.goldRef = {gold=n}` (mutable, so mid-hand gold is visible to trinkets);
  - outputs `result.gold` (gold gained this hand) and `result.destroyed` (list of card ids).
- Scoring order is exactly spec §Scoring order:
  - A debuffed card emits only `debuff`.
  - A Red seal re-runs the card's full step with a `{kind="retrigger", index}` event first.
  - Held Steel cards give ×1.5 each. A Red seal on a held Steel card applies it twice.
  - For trinket editions, Foil and Holo apply before the trinket's effect and Poly after.
- New event kinds. Each carries `runChips` and `runMult`; `index` refers to played cards, `heldIndex` to `ctx.held`:
  - `{kind="enh", index, enh, chips?, mult?, xmult?}`
  - `{kind="edition", index? | slot?, ed, chips?, mult?, xmult?}`
  - `{kind="seal", index, seal="GOLD", gold=3}`
  - `{kind="money", index, gold=20}` (Lucky)
  - `{kind="held", heldIndex, xmult=1.5}`
  - `{kind="retrigger", index}`
  - `{kind="destroy", index}` (Glass broke; emitted after `total`)
- Lucky rolls use `RNG.next(ctx.rng)`: `< 1/5` gives +20 mult, then a separate roll `< 1/15` gives $20. Glass breaks on `RNG.next(ctx.rng) < 0.25`.
- Backward compatibility: when `ctx.held` is nil, treat it as `{}`. When `ctx.goldRef` is nil, create it from `ctx.gold`. The v1 Run therefore keeps working until Task 4.
- Wild and Stone in v1 content (spec §Calls):
  - The four suit trinkets in `Data/Trinkets.lua` and the suit-debuff bosses in `Data/Bosses.lua` switch from `card.suit == X` to `ns.Cards.hasSuit(card, X)`. Wild matches every suit and is debuffed by every suit boss. Stone matches none.
  - Hogger's face rule uses `Cards.isFace`, which is already Stone-safe.

- [ ] **Step 1:** Write the tests. Use stubbed RNG seeds found by search, the same approach as the existing Lucky Charm test.
  - `bonus_mult_stone`: Pair of K, one with BONUS, plus a Stone. Chips = 10 + 10 + 10 + 30 + 50 = 110, mult 2.
  - `glass_x2_and_break`: a Glass card gives ×2. With a breaking seed, `result.destroyed` holds its id and a `destroy` event follows `total`.
  - `steel_held`: one held Steel card gives final mult ×1.5. With a Red seal it gives ×2.25.
  - `red_seal_retrigger`: a Red-sealed K in a Pair scores its 10 chips twice, with a `retrigger` event.
  - `editions_card`: Foil gives +50 chips, Holo +10 mult, Poly ×1.5, in that order relative to the enhancement.
  - `trinket_poly_after_effect`: an Arcane Intellect trinket (+4 mult) with POLY on a Pair gives (2+4)×1.5 = 9.
  - `lucky_gold_visible_to_goblin_bank`: Lucky pays $20 mid-hand and Goblin Bank sees `goldRef.gold` raised.
  - `gold_seal_pays`: `result.gold == 3`.
  - `debuffed_loses_all`: a debuffed Glass card with a Red seal emits only `debuff`.
  - `wild_matches_suit_trinket_and_boss`: a Wild card triggers Whetstone, and VanCleef debuffs it. A Stone triggers neither.
- [ ] **Step 2:** Run `luajit tests/run.lua scoring`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `luajit tests/run.lua scoring` and `luajit tests/run.lua content`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: enhancements, editions and seals in scoring`.

### Task 4: Run v2 (persistent deck, round-end effects, Save v2)

**Files:** Modify `Core/Run.lua`, `Core/Save.lua`, `Core/Shop.lua` (only the callers of the removed Cards functions), `tests/test_run.lua` and `tests/test_save.lua`.

**Interfaces:**
- Consumes Task 1 (Deck), Task 2 (`Hands.visible`) and Task 3 (Scoring v2).
- Produces:
  - New run fields:
    - `deck = Deck.new()`, `nextCardId = 53`
    - `baseHandSize = 8`, `handSizeMod = 0`
    - `consumables = {}`, `maxConsumables = 2`
    - `seenHands = {}`, `lastHandId = nil`, `lastConsumable = nil`
  - `run.handSize` is removed. Use `Deck.handSize(run)` everywhere, including the UI (grep `handSize`).
  - `Run.trinketSlots(run)`: `run.maxTrinkets` plus the number of NEGATIVE trinkets.
  - `Run.startBlind`: the pile is `Deck.shuffledPile(run)` and it draws `Deck.handSize(run)` cards.
  - `Run.play`:
    - builds the ctx with `held` and `goldRef`;
    - after scoring, `run.gold = goldRef.gold`;
    - `Deck.destroy` runs on each id in `result.destroyed`;
    - sets `seenHands[handId] = true` and `lastHandId = handId`;
    - the refill draws only up to `Deck.handSize(run)` (never removes extras).
  - `Run.discard`: each discarded PURPLE-seal card creates a random Scroll via `ns.Consumables.add(run, ns.Consumables.random(run, "scroll"))` if there's room. Look up `ns.Consumables` at call time; it's built in Task 5. Until then the tests stub it.
  - `Run.winBlind`: payout gains a `held` field, $3 per GOLD-enhanced card held in hand (a Red seal doubles it). Each BLUE-seal card held creates the Tome for `run.lastHandId` if there's room.
  - `Save.VERSION = 2`. `Save.load` calls `ns.Deck.relink(run)` before returning.

- [ ] **Step 1:** Write the tests. Update the existing ones that used `run.handSize` or `Cards.shuffledDeck`.
  - `run_has_persistent_deck`: 52 cards; `startBlind` draws 8, and those are rawequal to `run.deck` entries.
  - `glass_destroyed_leaves_deck`: force a break; afterwards `#run.deck == 51`.
  - `relink_after_load_shares_tables`:
    1. Store, then load.
    2. Set `loaded.hand[1].enh = "MULT"`.
    3. `Deck.find(loaded, loaded.hand[1].id).enh == "MULT"`.
  - `tiny_deck_draws_available`: destroy cards down to 3 left; `startBlind` deals 3, plays 1 card fine and doesn't error.
  - `gold_enh_pays_held`: a held GOLD card gives `payout.held == 3`.
  - `blue_seal_creates_tome`: with the stub, the tome for `lastHandId` is added.
  - `purple_seal_discard_creates_scroll`: with the stub.
  - `negative_card_grows_hand`: a NEGATIVE card in the deck makes the draw 9.
  - `load_rejects_v1`: `{version=1, run=...}` gives nil.
- [ ] **Step 2:** Run `luajit tests/run.lua run` and `luajit tests/run.lua save`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: everything PASSES, including the Task 1–3 tests that were left red.
- [ ] **Step 5:** Commit `feat: persistent deck, round-end card effects, save v2`.

### Task 5: Consumables core, Tomes and Scrolls

**Files:**
- Create `Data/Tomes.lua`, `Data/Scrolls.lua`, `Core/Consumables.lua`, `tests/test_consumables.lua` and `tests/test_scrolls.lua`.
- `.toc`: the Data files go after `Data\Decks.lua`; `Core\Consumables.lua` goes after `Core\Scoring.lua`.

**Interfaces:**
- Produces:
  - Consumable instance: `{kind = "tome"|"scroll"|"relic", id}`.
  - `ns.Tomes.order` and `ns.Tomes.def[id] = {id, name, handId}`. There are 12, one per `Hands.order` entry, named `"Tome of <Hand name>"`. A Tome id is its handId.
  - `ns.Scrolls.order` and `ns.Scrolls.def[id] = {id, name, desc, icon, select = {min, max}|nil, untargeted = bool, creates = bool, use = function(run, cards, api) -> nil}`.
    - There are 22. Use the ids and names from spec §Scrolls in table order, e.g. `ECHOES`, `FORTUNE`, `STARS`, … `BLADES`.
    - `cards` is the list of selected card tables, in left-to-right order.
  - Cost constants: `Consumables.COST = {tome=3, scroll=3, relic=4}`. Sell value is half, floored.
  - `api` is passed to each `use`:
    - `api.add(item)`: respects slots and returns ok.
    - `api.randomId(kind)`.
    - `api.addCard(card)`: `Deck.add`, and also into `run.hand` when in play.
    - `api.destroy(card)`.
    - `api.changed(card)`.
    - `api.gold(delta)`.
    - `api.trinkets()`.
    - `api.rng`.
  - `Consumables.add(run, item) -> ok`: false if `#run.consumables >= run.maxConsumables`.
  - `Consumables.random(run, kind) -> item`. Hidden secret-hand Tomes are excluded.
  - `Consumables.targetCards(run) -> list|nil`: `run.hand` when `phase == "play"`, `run.shop.openPack.hand` when a pack with a hand is open, otherwise nil.
  - `Consumables.canUse(run, slot, idx) -> ok, reason`:
    - **Targeted:** needs `targetCards`, and `#idx` must be within `select.min..max`.
    - **Untargeted:** allowed in the play, shop and blind phases.
    - **Creators** (`creates = true`): count their own slot as free; disabled with "No room" if nothing can be created.
    - **Trinket-needing effects:** reason "No trinket slot" or "No eligible trinket".
  - `Consumables.use(run, slot, idx) -> outcome = {changed = {ids}, destroyed = {ids}, created = {items}, added = {card ids}, gold = delta}`:
    - removes the used consumable first;
    - sets `run.lastConsumable` for scrolls and tomes, except Echoes;
    - Tomes level their hand.
  - `Consumables.sell(run, slot) -> gained`.
- Every Scroll effect is exactly as in spec §Scrolls.
  - Strength: A wraps to 2, and Stone is unaffected.
  - Death: the left card becomes a copy of the right, keeping its own id.

- [ ] **Step 1:** Write the tests.
  - In `test_consumables`:
    - `add_respects_slots`
    - `creator_respects_slots`: two slots both full. Knowledge (Emperor) can be used, because its own slot frees, and it creates 1. With Stars plus 2 other cards, it creates 1.
    - `targeted_needs_hand`: a targeted scroll in the shop phase with no open pack gives false, "Select cards in a hand".
    - `tome_levels`
    - `sell_half`
    - `echoes_repeats_last`
    - `random_excludes_hidden_tomes`
  - In `test_scrolls`, one test per Scroll asserting its exact effect on concrete cards and gold. For example:
    - `greed_caps_20`: gold 30 gives 50.
    - `thrift_caps_50`.
    - `undeath_left_copies_right`.
    - `strength_ace_wraps`.
    - `sacrifice_destroys_two`: removed from `run.deck`.
- [ ] **Step 2:** Run `luajit tests/run.lua consumables` and `luajit tests/run.lua scrolls`. Expected: FAIL.
- [ ] **Step 3:** Implement. Replace Task 4's stub usage with the real module, and remove the stubs from `test_run`.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: consumables core, Tomes and Scrolls`.

### Task 6: Relics

**Files:** Create `Data/Relics.lua` (put it in `.toc` after `Data\Scrolls.lua`) and `tests/test_relics.lua`.

**Interfaces:**
- Consumes Task 5's `api` and def shape.
- Produces `ns.Relics.order` and `ns.Relics.def`: 18 relics with ids from spec §Relics (e.g. `COURT`, `ACES`, … `COSMOS`), with each effect exactly as specified there, plus the spec §Calls rulings:
  - Court, Aces and Numbers never roll Stone.
  - Lich creates a rare trinket and sets gold to 0.
  - Void and Hexes target only trinkets with no edition.
  - Rebirth's copy loses NEGATIVE.
  - Whispers and Void apply `handSizeMod -= 1`.
  - Legends creates the rarest available trinket.
  - Cosmos levels every *visible* hand.
- Effects that destroy random cards in hand pick with `run.rng`. Added cards go into the hand and the deck via `api.addCard`.

- [ ] **Step 1:** Write the tests: one per Relic.
  - `relic_overfills_hand`: Court on an 8-card hand gives 10 cards in hand. `canPlay` with 6 selected is still false. After a play, the refill doesn't draw while `#hand >= handSize`.
  - `flame_destroys_five_gains_20`.
  - `lich_gold_zero`.
  - `hexes_destroys_others`.
  - `void_needs_editionless`: false with the reason when none qualify.
- [ ] **Step 2:** Run `luajit tests/run.lua relics`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: relics`.

### Task 7: Shop v2 and Packs

**Files:**
- Create `Core/Packs.lua` (in `.toc` after `Core\Consumables.lua`) and `tests/test_packs.lua`.
- Rewrite `Core/Shop.lua` and `tests/test_shop.lua`.

**Interfaces:**
- Produces:
  - Shop state:
    ```
    run.shop = {
      cards = {item|false, item|false},
      packs = {pack|false, pack|false},
      rerollCost = 5,
      openPack = nil|{...},
    }
    ```
  - Shop card item: `{type = "trinket"|"scroll"|"tome", id, ed?, cost}`.
    - The type is weighted 20/4/4.
    - Trinkets roll `CardTypes.rollEdition(r, true)`, and the cost is the def cost plus `ED_COST`.
    - Trinkets are distinct, and owned ones are excluded.
  - Pack: `{type = "ARCANA"|"CELESTIAL"|"SPECTRAL"|"BUFFOON"|"STANDARD", size = "normal"|"jumbo"|"mega", cost = 4|6|8}`.
  - `Packs.SIZES` and the show/pick counts are from spec §Shop.
  - `Packs.WEIGHTS` (implementer's choice per the spec): normal Arcana/Celestial/Standard 4, jumbo 2, mega 0.5; Buffoon 1.2/0.6/0.15; Spectral 0.6/0.3/0.07.
  - `Shop.open(run)`, `Shop.buy(run, i) -> ok, err` (`"gold"|"slots"|"gone"`; scrolls and tomes go to consumables, trinkets to trinkets with `ed`), `Shop.sellTrinket(run, slot) -> gained` (half of def cost plus edition surcharge), `Shop.reroll(run)` (cards only, not packs).
  - `Packs.open(run, i) -> ok, err`:
    - charges the cost;
    - sets `run.shop.openPack = {type, size, choices = {...}, picksLeft, hand = {cards}|nil}`;
    - Arcana and Spectral get `hand`, which is `Deck.handSize(run)` cards drawn from `Deck.shuffledPile(run)`;
    - choices for Standard are new card tables, not yet in the deck, rolled per spec §Calls (40% enh, 20% seal, edition odds without Negative).
  - `Packs.pick(run, c, idx) -> ok, err, outcome`:
    - Scrolls and Relics are used immediately on the pack hand with `idx`, via `Consumables` internals with the item not slotted.
    - Tomes level their hand immediately.
    - Trinkets need a slot.
    - Standard cards go through `Deck.add`.
    - Each pick decrements `picksLeft`; at 0 the pack closes (`openPack = nil`).
  - `Packs.skip(run)`.
  - While a pack is open, Shop buy, reroll and next are refused with `"pack"`.

- [ ] **Step 1:** Write the tests.
  - `shop_two_cards_two_packs`
  - `card_type_weights`: over 3000 opens, trinkets 60–80%.
  - `edition_cost_added`: force a Foil, and the cost is def + 2.
  - `sell_includes_edition`
  - `reroll_cards_only`: packs unchanged.
  - `open_pack_charges_and_sizes`: mega Arcana gives 5 choices, 2 picks and a hand.
  - `pick_scroll_uses_on_pack_hand`
  - `pick_standard_adds_to_deck`
  - `skip_closes`
  - `open_pack_survives_save`: open Arcana, store/load, and `openPack` choices and hand deep-equal (relinked).
  - `shop_locked_while_pack_open`
- [ ] **Step 2:** Run `luajit tests/run.lua shop` and `luajit tests/run.lua packs`. Expected: FAIL.
- [ ] **Step 3:** Implement. Update `Run.winBlind`'s `Shop.open` call if the signature changed (it shouldn't).
- [ ] **Step 4:** Run `luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: shop v2 and booster packs`.

### Task 8: Balance simulator and curve retune

**Files:** Create `tools/sim/sim.lua` and `tools/sim/bot.lua`. Modify `Core/Run.lua:5` (`BASE_TARGETS`), `Data/Bosses.lua` (RAGNAROS `targetMult`), the tests that pin those values, and `README.md`.

**Interfaces:**
- `luajit tools/sim/sim.lua [runs=200] [deckId=ROGUE] [seed=1]`:
  - loads Core and Data the same way `tests/run.lua` does (from the .toc), with no WoW;
  - prints `wins N/runs (pct)`, a stage-reached histogram and the mean final gold.
- What the bot does each turn:
  - **Play:** pick the best-scoring 1–5 card combination by calling `Scoring.score` on copies. Use a copied RNG so the run's RNG isn't advanced.
  - **Discard:** throw away the cards outside the best hand when it scores under 40% of the blind's need-per-hand.
  - **Shop:** buy trinkets it can afford (prefer ×mult, then +mult), always buy Tomes for its most-played hand, open Arcana or Celestial packs when gold ≥ 8, and use Scrolls targeting its highest-rank cards.
  - **Relics:** use when they're untargeted.
- Retune: pick `BASE_TARGETS` and the Ragnaros mult so the ROGUE deck at 200 runs and seed 1 wins **10–25%**. Start from Balatro's curve `{300,800,2000,5000,11000,20000,35000,50000}` with Ragnaros ×2 and flatten until it's in range.

- [ ] **Step 1:** Write the bot and the sim. Check it runs: `luajit tools/sim/sim.lua 20`.
- [ ] **Step 2:** Iterate on the curve until it's in range, recording each attempt in the commit body.
- [ ] **Step 3:** Update the pinned tests (`tests/test_run.lua` targets, `tests/test_content.lua` Ragnaros), add the sim command to the README, and run the full suite.
- [ ] **Step 4:** Commit `feat: deck-building balance sim and retuned curve` (the commit body includes the final win rate).

### Task 9: Media for card types

**Files:** Modify `tools/gen_media.py` and `tests/test_media.py`, and generate the new files under `Media/`.

**Interfaces:**
- Produces textures, all 32-bit BGRA TGA, power-of-two, with the existing header conventions:
  - `Media/Face_<ENH>.tga` (128×256): one card-face background per enhancement. Stone is a slab with no space for a rank; Glass is translucent cyan with a light alpha; Steel is brushed grey; Gold is gilded; Bonus has a blue tint frame; Mult a red tint frame; Wild a rainbow border; Lucky a green clover corner.
  - `Media/Face_Plain.tga`: a parchment face.
  - `Media/Seal_<SEAL>.tga` (32×32): coloured wax-seal emblems.
  - `Media/Ed_Sheen.tga` (128×256): a diagonal white sheen gradient for the Foil sweep.
  - `Media/Ed_Holo.tga` (128×256): a rainbow diagonal band.
  - `Media/Consumable_Scroll.tga`, `Consumable_Tome.tga`, `Consumable_Relic.tga` (128×256): card frames for each consumable kind.
  - `Media/Pack.tga` (128×256): a pack wrapper.

- [ ] **Step 1:** Extend the tests to cover every new file: header, size, power of two and an alpha range.
- [ ] **Step 2:** Run `python3 tests/test_media.py`. Expected: FAIL.
- [ ] **Step 3:** Generate the textures and preview them as PNGs in the scratchpad.
- [ ] **Step 4:** Run `python3 tests/test_media.py`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: card type, seal, edition and consumable textures`.

### Task 10: Card widget v2, wide hands, deck view

**Files:** Modify `UI/CardWidget.lua`, `UI/HandView.lua`, `UI/Sidebar.lua`, `tests/wowstub.lua` (if needed) and `tests/smoke_ui.lua`. Create `UI/EditionFX.lua` and `UI/DeckView.lua` (both in `.toc` after `UI\CardWidget.lua`).

**Interfaces:**
- `w:SetCard(card)`:
  - picks `Face_<enh>` or `Face_Plain`;
  - hides rank and suit for Stone;
  - shows the seal emblem in the top-right corner;
  - calls `EditionFX.Attach(w.face, card.ed)`.
- Tooltip on hover: the `CardTypes` names and descs for enh, ed and seal, with a short delay. It must not fight hover lift.
- `EditionFX.Attach(frame, ed)` and `EditionFX.Detach(frame)`:
  - Foil: the sheen texture sweeps across every 2.5s.
  - Holo: a holo band with slow alpha pulse and offset drift.
  - Poly: a vertex-colour hue cycle.
  - Negative: a darkened, inverted-look tint.
  - One shared OnUpdate driver runs only while at least one *visible* attached frame exists.
  - It's also used by TrinketRow for trinket editions.
- HandView lays out up to 12 cards (spec §Calls), compressing the spacing. Cards never overflow `.handArea`.
- `DeckView.Toggle(run)`: a panel over the play area listing every `run.deck` card as a mini widget in a grid by suit (Stone in its own row), with counts per suit and per type. A "Deck (N)" button on the sidebar opens it.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Extend the smoke run:
  - give a card BONUS, FOIL and RED, and assert the widget's face texture path and seal visibility;
  - open DeckView and assert the count text;
  - add 4 cards via `Deck.add` plus `HandView.Update`, and assert the widgets fit within `handArea` bounds;
  - assert that hiding the window stops the EditionFX driver.
- [ ] **Step 3:** Run `luajit tests/smoke_ui.lua && luajit tests/run.lua && luajit tests/syntax.lua`. Expected: PASS.
- [ ] **Step 4:** Commit `feat: card type visuals, edition FX, wide hands, deck view`.

### Task 11: Consumable row and use flow

**Files:** Create `UI/ConsumableRow.lua` (in `.toc` after `UI\TrinketRow.lua`). Modify `UI/MainFrame.lua` (the region to the right of the trinket row), `UI/HandView.lua`, `UI/TrinketRow.lua` (edition FX and Negative slot count via `Run.trinketSlots`) and `tests/smoke_ui.lua`.

**Interfaces:**
- `ConsumableRow.Update(run)` shows `run.maxConsumables` slots with the consumable frame texture, the name and a tooltip.
- Clicking a slot toggles a small popover with **Use** and **Sell (Ng)**.
  - Use is enabled per `Consumables.canUse(run, slot, HandView.Selected())`, and is re-evaluated whenever the selection changes. When disabled, its reason shows on hover.
- **Use flow:**
  1. Lock input (HandView busy).
  2. Call `Consumables.use`.
  3. Animate the outcome:
     - changed cards flip (scale X 1 → 0 → 1 with the face swap at 0, 0.25s);
     - destroyed cards shatter (scale up, fade, 0.3s);
     - added cards deal in from the deck;
     - created consumables pop into their slots;
     - gold floats.
  4. Re-render and unlock.
  5. Call `ns.UI.OnRunChanged()`.
- This works in play, in the shop or blind screens (untargeted only), and inside the pack overlay (Task 13 wires that).

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Extend the smoke run:
  - put Fury (Empress) in a slot, select 2 hand cards, click Use, advance, and assert both cards' `enh == "MULT"` and that their widgets show `Face_MULT`;
  - put Greed in a slot on the blind screen, Use it, and assert gold doubled;
  - try Use with 3 cards selected for Fury and assert it is disabled with a reason.
- [ ] **Step 3:** Run `luajit tests/smoke_ui.lua && luajit tests/run.lua && luajit tests/syntax.lua`. Expected: PASS.
- [ ] **Step 4:** Commit `feat: consumable slots and use animations`.

### Task 12: Tally v2

**Files:** Modify `UI/Tally.lua` and `tests/smoke_ui.lua`.

**Interfaces:**
- `Tally.Play` handles the Task 3 event kinds:
  - `enh` and `edition` float their delta in the chips or mult colour, and pop the card. For a trinket-slot edition, pulse the slot.
  - `seal` and `money` float `$N` in gold.
  - `held` pops the held card's widget (map `heldIndex` to the HandView widget for `ctx.held` order). Expose `HandView.HeldWidgets()` returning the widgets in held order.
  - `retrigger` floats "Again!" over the card.
  - `destroy` shatters the card (same animation as Task 11), and the card is removed from the played set before slide-away.
- Every event kind counts toward the pacing formula, and the no-op skip rule still applies.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Extend the smoke run:
  - play a hand containing a Glass, a Red-sealed card and a held Steel card, with the seed forcing the Glass to break;
  - advance and assert no busy state;
  - assert the deck count dropped by 1;
  - assert the tally reached `total`.
- [ ] **Step 3:** Run `luajit tests/smoke_ui.lua && luajit tests/run.lua`. Expected: PASS.
- [ ] **Step 4:** Commit `feat: tally shows card types, held effects and retriggers`.

### Task 13: Shop and pack screens

**Files:** Modify `UI/Screens.lua` (the shop section). Create `UI/PackView.lua` (in `.toc` after `UI\Screens.lua`). Modify `tests/smoke_ui.lua`.

**Interfaces:**
- The shop screen shows the payout breakdown (unchanged) plus:
  - 2 card slots: the item card (trinket icon with edition FX, or the consumable frame), name, cost and Buy;
  - 2 pack slots: the pack texture tinted by type, a label like "Mega Arcana Pack", cost and Open;
  - Reroll and Next Blind;
  - Abandon (unchanged).
- Buy, Open and Reroll keep the v1 behaviour: disabled reasons, error text and saving after each action.
- `PackView.Show(run)` is an overlay over the play and hand areas while `run.shop.openPack` exists:
  - The choices are fanned out. Click one to select it, then Pick, which is enabled per type: trinket slot free, or for Scrolls and Relics a valid selection on the pack hand.
  - "Picks left: N" and Skip.
  - Arcana and Spectral packs also show the drawn hand as card widgets with HandView-style selection.
  - Picking runs the same outcome animations as Task 11.
  - It closes when `openPack` becomes nil.
  - Main.Render shows it whenever `openPack` is set, which also restores an open pack after a reload.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Extend the smoke run:
  - force a shop with a Mega Arcana pack; Open it, select 2 pack-hand cards, pick the Fury choice and assert the cards changed; then Skip;
  - reload mid-pack (fresh world) and assert PackView shows with the same choices;
  - buy a Scroll card into a consumable slot;
  - make the Buy button disabled when consumable slots are full.
- [ ] **Step 3:** Run `luajit tests/smoke_ui.lua && luajit tests/run.lua && luajit tests/syntax.lua`. Expected: PASS.
- [ ] **Step 4:** Commit `feat: shop v2 and pack opening screens`.

### Task 14: Integration, README, version

**Files:** Modify `README.md`, `AzerothAnte.toc` (`## Version: 0.2.0`) and `tests/smoke_ui.lua`.

- [ ] **Step 1:** Add a smoke run of a full scripted run in which the bot from Task 8 drives the UI through at least 6 blinds (or until it loses), with consumables, packs and the deck view used along the way. Assert no busy hang, no errors and that saves happen.
- [ ] **Step 2:** Update the README:
  - "How to play": consumables, card types, packs, deck view.
  - In-game checklist items:
    - edition shimmer visible and smooth;
    - Glass shatter;
    - Use on cards in play and in a pack;
    - `/reload` with a pack open;
    - hand over 8 cards still fits;
    - deck view.
  - The sim command.
- [ ] **Step 3:** Run all four suites.
- [ ] **Step 4:** Commit `chore: v0.2.0 deck building`.
