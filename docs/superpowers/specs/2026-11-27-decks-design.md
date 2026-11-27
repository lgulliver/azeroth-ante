# The other ten decks

Status: approved 2026-11-27. Adds Balatro's (1.0.1) ten remaining starting decks with WoW names, each with a painted back in the style of the existing five.

| Balatro | Id | Name | Rule |
|---|---|---|---|
| Magic | MAGE | Mage Deck | Start with Dalaran Crystal Ball and 2 Scrolls of Echoes (The Fool) |
| Nebula | DRAENEI | Draenei Deck | Start with Titan Orrery; -1 consumable slot |
| Ghost | DEATHKNIGHT | Death Knight Deck | Relics can appear in the shop (weight 2); start with a Relic of Hexes |
| Abandoned | FORSAKEN | Forsaken Deck | No face cards (40 cards) |
| Checkered | ALLIANCE | Alliance Deck | 26 Spades and 26 Hearts |
| Zodiac | TRADEPRINCE | Trade Prince Deck | Start with Scribe's Stall, Karazhan Library Cart and Bulging Saddlebags |
| Painted | HUNTER | Hunter Deck | +2 hand size, -1 trinket slot |
| Anaglyph | EVOKER | Evoker Deck | A Bonus Roll (Double tag) after each boss |
| Plasma | DRUID | Balance Druid Deck | Chips and Mult become their average before the total; blind targets x2 |
| Erratic | GNOME | Gnome Deck | Every card's rank and suit is random (seeded) |

## Decisions

- **Order and unlocks:** Balatro's deck order, continuing the discovery ladder (fractions 0.38 to 0.74, rising by 0.04).
- **Backs:** painted by Codex from the existing backs as style references; the Alliance back is the earlier unused one, the counterpart of the Horde back on Warrior.
- **Starting vouchers** count as owned (never offered in the shop) and act exactly as if bought.

## Approaches

Codex art for all ten (picked) versus the default compass back for now. Deck rules as data fields read by Run, Shop and Scoring (picked) versus per-deck hook functions (more than these rules need).
