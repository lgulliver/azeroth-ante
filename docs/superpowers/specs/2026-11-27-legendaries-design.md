# Legendary trinkets, Diet Cola and Throwback

Status: approved [Liam, 2026-11-27: "names are good, go ahead"]. Completes the Balatro (1.0.1) joker set: the last two non-legendary jokers, which needed skip tags, and the five legendaries with The Soul.

## Trinkets

| Balatro | Id | Name | Rarity | Cost | Effect |
|---|---|---|---|---|---|
| Diet Cola | DARKMOON_FIZZ | Darkmoon Fizz | uncommon | 6 | Sell to create a free Bonus Roll (Double tag) |
| Throwback | TIMEWALKING_BADGE | Timewalking Badge | uncommon | 6 | ×0.25 Mult per blind skipped this run |
| Canio | FROSTMOURNE | Frostmourne | legendary | 20 | Gains ×1 Mult when a face card is destroyed |
| Triboulet | SHALAMAYNE | Shalamayne | legendary | 20 | Played Kings and Queens each give ×2 Mult when scored |
| Yorick | SHADOWMOURNE | Shadowmourne | legendary | 20 | Gains ×1 Mult every 23 cards discarded |
| Chicot | ASHBRINGER | Ashbringer | legendary | 20 | Disables every boss blind |
| Perkeo | DRAGONWRATH | Dragonwrath | legendary | 20 | Leaving the shop: a Negative copy of 1 random held consumable |

## Rules

- **Legendaries never roll at random.** Shop, Trinket Lockbox, Scroll of Summoning and the rarity tags skip them (`Trinkets.inPool` is false for legendary). Only Heart of Azeroth (The Soul) makes one.
- **Heart of Azeroth** creates a random legendary not already owned (Showman allows dupes), with the usual random edition. With none left it falls back to the rarest available trinket, as now.
- **Ashbringer** disables the boss when the blind starts, and at once if it arrives during a boss blind (Heart of Azeroth used mid-blind).
- **Negative consumables.** A Negative consumable adds a consumable slot, so the copy always fits. It shows the Negative edition and a tooltip line. Copying a Negative consumable gives another Negative one.
- Dragonwrath fires on a new `onShopExit` trinket hook, run by `Run.nextBlind` before leaving the shop.

## Approaches

Names: legendary weapons matched to each effect (picked), versus characters like the court cards. Random-pool exclusion: one `inPool` gate (picked) instead of guarding each roller.

## Out of scope

Legendary-specific art (they use WoW item icons like every trinket), stakes, endless, the other decks.
