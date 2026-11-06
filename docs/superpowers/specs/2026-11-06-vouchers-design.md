# Azeroth Ante: Vouchers & Achievements

Date: 2026-11-06. Status: draft for approval.
Builds on v2 (deck building) and deck unlocks (branch `feat/deck-unlocks`).

Legend: **[Liam]** decided by Liam. **[Call]** my call. **[Balatro]** copied from Balatro; values are from memory, since reference sites couldn't be fetched, so the builder should flag anything they believe differs.

## Intent

Add Balatro's vouchers, which are permanent upgrades for the rest of a run, bought in the shop. Gate each upgraded voucher behind its own achievement, as Balatro does. **[Liam]**

Achievements are internal to the addon. They're stored in `AzerothAnteDB.profile`, never touch WoW's own achievement system, and send nothing anywhere, so they stay within the ToS. **[Liam: "if we can do achievements and not break ToS"]**

## Shop behaviour [Balatro]

- The shop has a voucher section with 1 voucher, at a base cost of $10.
- The voucher offered is fixed for the whole stage. It's rolled the first time a shop opens in a stage, and stays until it's bought or the boss is beaten. After a boss, the next stage rolls a new one.
- Once bought, a voucher stays on the run (`run.vouchers = { [id] = true }`) and its effect applies immediately. Already-owned vouchers are never offered again.
- An upgraded voucher can only be offered if its base is owned in this run AND its achievement is unlocked in the profile.
- Rerolling doesn't change the voucher.
- The voucher counts toward discovery once bought. The deck-unlock thresholds rescale, because there are now 72 + 32 = 104 discoverable items:
  - Warrior: 7
  - Goblin: 17
  - Monk: 26
  - Warlock: 35
  These keep Balatro's 20/50/75/100 proportions against its roughly 300-item collection. **[Call]**

## The 32 vouchers [Balatro effects, Call WoW names]

| Base (WoW name) | Effect | Upgrade (WoW name) | Effect | Upgrade unlock achievement |
|---|---|---|---|---|
| Overstock (Bulging Saddlebags) | +1 shop card slot | Overstock Plus (Bottomless Bags) | +1 more | Spend $2500 in shops (lifetime) |
| Clearance Sale (Goblin Discount) | Shop items 25% off | Liquidation (Auction House Crash) | 50% off | Buy 10 vouchers (lifetime) **[Call: Balatro's exact condition unverified]** |
| Hone (Enchanter's Whetstone) | Foil/Holo/Poly appear 2× | Glow Up (Arcane Infusion) | 4× | Have 5 trinkets with an edition at once |
| Reroll Surplus (Lucky Coin) | Rerolls $2 cheaper | Reroll Glut (Gambler's Charm) | another $2 cheaper | Reroll the shop 100 times (lifetime) |
| Crystal Ball (Scrying Orb) | +1 consumable slot | Omen Globe (Seer's Orb) | Relics can appear in Arcana packs | Use 25 Scrolls from Arcana packs (lifetime) |
| Telescope (Astrolabe) | Celestial packs always include the Tome of your most-played hand | Observatory (Observatory of the Stars) | Tomes held in consumable slots give ×1.5 mult when their hand is played | Use 25 Tomes from Celestial packs (lifetime) |
| Grabber (Extra Ammo Pouch) | +1 hand per round | Nacho Tong (Quiver of Plenty) | +1 more | Play 2500 cards (lifetime) |
| Wasteful (Scavenger's Sack) | +1 discard per round | Recyclomancy (Junk Golem) | +1 more | Discard 2500 cards (lifetime) |
| Tarot Merchant (Scribe's Stall) | Scrolls appear more often in the shop (weight 4 → 9.6) | Tarot Tycoon (Inscription Guild) | weight → 32 | Buy 50 Scrolls from the shop (lifetime) |
| Planet Merchant (Librarian's Cart) | Tomes appear more often (weight 4 → 9.6) | Planet Tycoon (Grand Library) | weight → 32 | Buy 50 Tomes from the shop (lifetime) |
| Seed Money (Savings Pouch) | Interest cap $5 → $10 | Money Tree (Goblin Vault) | → $20 | Earn the maximum interest 10 rounds in a row |
| Blank (Empty Gem Socket) | Does nothing | Antimatter (Void Socket) | +1 trinket slot | Buy Empty Gem Socket 10 times (lifetime) |
| Magic Trick (Card Sharp's Sleeve) | Playing cards can appear in the shop (card slot type weight 4) | Illusion (Illusionist's Deck) | Shop playing cards may carry an enhancement, edition or seal | Buy 20 playing cards from the shop (lifetime) |
| Hieroglyph (Chronomancer's Hourglass) | −1 stage (repeat a stage), −1 hand per round | Petroglyph (Bronze Hourglass) | −1 stage, −1 discard per round | Win a run having bought Hieroglyph **[Call: Balatro's "reach ante 12" can't happen with 8 stages]** |
| Director's Cut (Bounty Board) | Reroll the boss once per stage, $10 | Retcon (Infinite Bounty) | Unlimited boss rerolls, $10 each | Encounter every boss at least once (lifetime) |
| Paint Brush (Bag of Holding) | +1 hand size | Palette (Greater Bag of Holding) | +1 more | Play a blind with hand size of 5 or less **[Balatro: "reduce your hand size down to 5"]** |

Upgraded vouchers cost $10, like the base. **[Balatro]**

## Effect wiring (where each effect lives)

- **Shop:** card-slot count, discount (rounded the Balatro way: `floor(cost * (1 - d))`, minimum $1), reroll cost, edition odds multiplier, Scroll/Tome weight multipliers, playing cards as a fourth shop type (weight 4) with Illusion rolls.
- **Run:** hands, discards, hand size (`handSizeMod`), trinket slots, consumable slots and the interest cap.
- **Hieroglyph/Petroglyph:** stage −1 immediately when bought; it can't go below 1. The current blind progress stays the same. **[Call]**
- **Director's Cut/Retcon:** a "Reroll Boss ($10)" button on the blind-select boss panel while the boss is upcoming. It re-draws the boss for this stage from the pool, excluding the current one, using run.rng. Director's Cut allows it once per stage; Retcon allows it unlimited times.
- **Packs:** Omen Globe lets Arcana pack choices include Relics (Balatro: 20% chance per slot **[Balatro, unverified]**). Telescope makes the first Celestial choice the Tome of your most-played hand.
- **Observatory:** in Scoring, ×1.5 mult per Tome held in consumable slots whose hand equals the played hand. Applied after trinkets, as its own event kind `voucher`.

## Achievements

- The profile gains `counters` (lifetime: shop spend, rerolls, cards played, cards discarded, Scrolls from Arcana packs used, Tomes from Celestial packs used, Scrolls bought, Tomes bought, Blank bought, playing cards bought, vouchers bought, bosses seen as a set) and `achievements = { [id] = true }`.
- Each upgraded voucher's achievement unlocks when its condition is met, checked when the counter updates.
- Cross-run conditions (lifetime counters) and in-run conditions (5 edition trinkets at once, max interest 10 rounds in a row, a hand size of 5 or less, a win with Hieroglyph) are both supported.
- An "Achievement unlocked: <voucher>" toast shows in-game using the existing float or flourish style, with no sound spam: one soft sound.
- A small **Achievements** view (a sidebar button on the deck-select screen) lists all 16 upgrade achievements, showing locked/unlocked, progress (e.g. "1240 / 2500 cards played") and what each unlocks. **[Call]**

## UI

- **Shop:** a voucher section alongside Cards and Packs. A voucher is drawn as a voucher ticket (a new generated texture: a parchment coupon with a gold seal) with its name, effect, cost and a Buy button with the disabled reasons.
- **Owned vouchers:** shown as a small row of ticket icons with tooltips (in the sidebar during play, or under the trinket row). **[Call]**
- **Achievements view:** as above.

## Calls made after review

All [Call]; they mirror Balatro unless noted.

1. **Deck unlocks are permanent.** The profile persists `unlockedDecks`. A deck stays unlocked once reached, and decks unlocked under the old thresholds are grandfathered on migration, so raising the thresholds never re-locks anything.
2. **Boss reroll:**
   - The new boss is drawn from the 8-boss pool, excluding the current boss and bosses already fought this run, using run.rng.
   - If no candidates remain, it may pick any pool boss except the current one.
   - Ragnaros (stage 8) can never be rerolled. The button is hidden there.
   - "Encountered" means a boss you actually started a blind against; a rerolled-away boss doesn't count.
   - "Every boss" for the Retcon achievement means all 9: the 8 pool bosses plus Ragnaros.
3. **Hieroglyph/Petroglyph:**
   - The offered voucher is stored on the run (`run.shopVoucher`), not keyed by stage. It's re-rolled only after a boss is beaten.
   - Buying Hieroglyph sets stage = max(1, stage − 1). The cost is still charged and the hand or discard penalty still applies at stage 1.
   - Replaying a stage gives no extra voucher until its boss falls.
4. **Blank → Antimatter:** redeem Blank **10** times (lifetime). (Corrected; Balatro uses 10.)
5. **Discount:**
   - It applies to shop cards, packs and vouchers, but not to rerolls or the boss reroll.
   - Price = `max(1, floor(cost * (1 - d) + 0.5))`.
   - Sell value is `floor(price paid / 2)`, so the price paid is stored on the item.
6. **Counters:**
   - Lifetime counters update live through a Core hook, `ns.Profile.onEvent(name, amount)`, bound in the UI like `onObtain`. They include abandoned and lost runs.
   - In-run streaks (consecutive max-interest rounds, Hieroglyph owned) live on the run.
   - Save version 3 *migrates* v2 saves by adding defaults. It doesn't invalidate them, so an in-progress run survives the update.
7. **Telescope:**
   - The run tracks `handPlays[handId]`.
   - Most-played ties go to the higher-ranked hand.
   - With zero plays, the first Celestial choice is a random visible Tome.
8. **Merchant weights (corrected):**
   - The Scroll/Tome shop weight goes 4 → **9.6** with Merchant and → **32** with Tycoon.
   - Hone and Glow Up edition odds go ×2 and ×4.

## Non-goals

- Skip-blind tags.
- Stakes.
- The other 10 Balatro decks.
- Legendary trinkets.

## Constraints

Same as before:
- Lua 5.1; Core free of WoW API calls; plain data; all randomness through run.rng; Save version bump.
- Mouse only.
- Own textures only.
- Retail plus Forever, with optional APIs feature-guarded.
- Never the global MouseIsOver.
- Theme helpers for all new UI.

## Left to the builder

- Module layout (suggested: Data/Vouchers.lua, Core/Vouchers.lua, Core/Achievements.lua, UI/VoucherShop and UI/AchievementsView).
- Exact toast styling.
- Voucher icon art details.
