# Stakes

Status: approved 2026-11-27. Balatro's (1.0.1) eight stakes, each adding to all below it, unlocked per deck as Balatro does.

## Ladder

| # | Stake | Adds |
|---|---|---|
| 1 | White | Base game |
| 2 | Red | Small blind gives no reward |
| 3 | Green | Ante targets scale faster: 300, 900, 2600, 8000, 20000, 36000, 60000, 100000 |
| 4 | Black | Shop and pack trinkets can be Eternal (30%) |
| 5 | Blue | −1 discard |
| 6 | Purple | Ante targets scale faster still: 300, 1000, 3200, 9000, 25000, 60000, 110000, 200000 |
| 7 | Orange | Shop and pack trinkets can be Perishable (30%) |
| 8 | Gold | Shop and pack trinkets can be Rental (30%) |

Unlocking: every deck starts with White. Winning a deck at a stake unlocks the next stake for that deck (`profile.stakeWon[deckId]` holds the highest won). The deck screen picks the stake under the deck card, defaulting to the highest unlocked.

## Stickers

Rolled on trinket offers in the shop (including rarity-tag offers) and in Trinket Lockboxes, as Balatro's `create_card` does: one roll r; r > 0.7 Eternal (Black+), else 0.4 < r ≤ 0.7 Perishable (Orange+); a separate roll > 0.7 Rental (Gold). Not on trinkets from Scrolls, Relics, Recruit-a-Friend or other trinkets.

- **Eternal:** can't be sold or destroyed (Soul Harvest and Whispers of the Old Gods skip it, Relics of Rebirth and Hexes spare it). Not on trinkets whose Balatro joker has `eternal_compat = false` (they sell or destroy themselves).
- **Perishable:** after 5 rounds it is debuffed for the rest of the run (as Ragnaros's disable, but permanent). Not on trinkets whose joker has `perishable_compat = false` (the ones that grow).
- **Rental:** costs 1g in the shop (a tag-freed one is still free); loses 3g at the end of each round, taken before interest and shown on the payout.

## Approaches

Per-deck ladder (picked) versus every stake open. Compat flags as two lists in `Data/Stakes.lua` (`NO_ETERNAL`, `NO_PERISHABLE`) copied from Balatro's joker table, versus deriving them from hooks (rejected: misses jokers like Luchador and Hologram).

## Out of scope

Stake-specific achievements, a stake sticker on the deck card art.
