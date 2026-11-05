# Azeroth Ante: Deck Building & Card Types (v2)

Date: 2026-11-05. Status: draft for approval.
Builds on `2026-11-05-azeroth-ante-design.md` (v1, shipped on `feat/azeroth-ante`).

Legend: **[Liam]** decided by Liam. **[Call]** my call, not yet confirmed. **[Balatro]** copied from Balatro.

## Intent

v1 has one upgrade type (trinkets, i.e. jokers) plus a weak hand-level upgrade (one Tome per shop), and a fixed 52-card deck. Balatro's depth comes from changing your deck during a run. v2 adds that: consumable cards that modify your playing cards, plus card types (enhancements, editions and seals). **[Liam]**

Rule: **keep Balatro's effects exactly, and reskin the names to WoW.** **[Liam]**

## Goals

1. **Consumables:** two held slots. Three kinds: Scrolls (Balatro tarot), Tomes (Balatro planets) and Relics (Balatro spectral). **[Liam: deck building]** The names are **[Call]**.
2. **Card types on playing cards:** 8 enhancements, 4 editions and 4 seals, with Balatro's effects. **[Liam]**
3. **Editions on trinkets** as well (Foil, Holo, Polychrome, Negative). **[Balatro]**
4. **Booster packs in the shop:** open one, then pick from it. **[Balatro]**
5. **The deck changes during a run.** Cards can be added, destroyed, duplicated, re-suited or re-ranked. **[Liam]**
6. **The extra poker hands come back**, because a changing deck makes them possible: Five of a Kind, Flush House and Flush Five. They are hidden ("secret") until first played, as in Balatro. **[Balatro]**
7. **Deck view:** a button that shows your current deck, with its types. **[Call]**

## Non-goals (v2)

- Vouchers, skip-blind tags, stakes, deck unlocks and the other Balatro decks. These come later. **[Liam: order chosen]**
- Legendary trinkets (The Soul) and Balatro's 150-joker pool. Relics that "create a legendary/rare trinket" use our pool's rarest available trinket. **[Call]**
- New trinkets beyond those needed for v2 effects. **[Call]**

## Anti-goals

- Clunky interaction, unchanged from v1. Using a consumable on selected cards, opening packs and viewing the deck must all be smooth: animated, with no stuck states and no ambiguity about what a card will affect. **[Liam, v1]**
- Effects that silently differ from Balatro's. If WoW can't do something (e.g. a shader), it gets an approximation of the visual only, never of the rules. **[Liam]**

## Card model change

v1 card: `{rank, suit, id}`, with the deck rebuilt as 52 fresh cards each blind.
v2 card: `{id, rank, suit, enh?, ed?, seal?}`.
- `rank` is 2..14, or nil for Stone.
- `enh` is one of BONUS, MULT, WILD, GLASS, STEEL, STONE, GOLD or LUCKY.
- `ed` is one of FOIL, HOLO, POLY or NEGATIVE.
- `seal` is one of GOLD, RED, BLUE or PURPLE.

`run.deck` is the persistent card list for the run: plain data, saved, and with unique ids from `run.nextCardId`. Each blind shuffles a copy of `run.deck` into the pile. Destroyed cards leave `run.deck`, and added cards join it. **[Balatro]**

## Card types [Balatro]

**Enhancements**, at most one per card:

| Id | Name | Effect |
|---|---|---|
| BONUS | Bonus | +30 chips when scored |
| MULT | Mult | +4 mult when scored |
| WILD | Wild | Counts as every suit |
| GLASS | Glass | ×2 mult when scored; 1 in 4 chance to be destroyed after scoring |
| STEEL | Steel | ×1.5 mult while held in hand (not played) |
| STONE | Stone | +50 chips; no rank or suit; always scores |
| GOLD | Gold | $3 if held in hand at end of round |
| LUCKY | Lucky | When scored: 1 in 5 chance of +20 mult, 1 in 15 chance of $20 |

**Editions** (cards and trinkets):

| Id | Name | Effect |
|---|---|---|
| FOIL | Foil | +50 chips |
| HOLO | Holographic | +10 mult |
| POLY | Polychrome | ×1.5 mult |
| NEGATIVE | Negative | On a trinket: +1 trinket slot. On a playing card: +1 hand size while it's in the deck. |

**Seals:**

| Id | Effect |
|---|---|
| GOLD | $3 when this card is played and scores |
| RED | Retrigger this card (scoring, and held-in-hand effects) once |
| BLUE | If held in hand at end of round, create the Tome for the final hand played that round (needs a free slot) |
| PURPLE | When discarded, create a random Scroll (needs a free slot) |

Display names for card types keep Balatro's names, since Liam refers to them that way (foil, glass, stone). **[Call]**

## Scoring order [Balatro]

1. Base hand chips × mult from the hand level.
2. For each scoring card, left to right, twice if it has a Red seal:
   - card chips (Stone: +50, no rank chips);
   - enhancement (Bonus, Mult, Glass ×2, Lucky rolls);
   - edition (Foil, Holo, Poly);
   - Gold seal $3;
   - each trinket's onCard, left to right.
3. For each card held in hand, left to right (Red seal retriggers): Steel ×1.5.
4. Each trinket, left to right: its edition's Foil and Holo apply before its effect, its Polychrome ×1.5 after.
5. Total = floor(chips × mult).
6. After scoring: Glass breaks roll (destroyed cards are removed from `run.deck`), and Lucky money is paid out.

At end of round: Gold-enhanced cards held pay $3, and Blue seals held create Tomes.

The scoring event stream gains new event kinds so the tally can show them: `enh`, `edition`, `seal`, `held`, `retrigger`, `destroy`, `money`. Every event still carries `runChips` and `runMult`.

## Hands

Add these three, using Balatro's base values and level steps:
- FIVE_KIND: 120 × 12, +35 / +3 per level
- FLUSH_HOUSE: 140 × 14, +40 / +4 per level
- FLUSH_FIVE: 160 × 16, +50 / +3 per level

They stay hidden in hand lists and Tome pools until first played. Wild cards count toward flushes, and Stone cards toward no hand. **[Balatro]**

## Consumables [Balatro effects, Call names]

There are 2 slots, shown next to the trinket row. Click a consumable to see its tooltip and a Use button. Use is enabled only when the selection is valid. Selling it gives half its cost.

**Tomes** (planets): one per hand type, 12 in total, each levelling its hand once. The v1 "Tome of X" naming stays. Price $3.

**Scrolls** (the 22 tarots):

| Balatro | Our name | Effect |
|---|---|---|
| The Fool | Scroll of Echoes | Create a copy of the last Scroll or Tome used this run (not itself) |
| The Magician | Scroll of Fortune | Up to 2 selected cards become Lucky |
| The High Priestess | Scroll of the Stars | Create up to 2 random Tomes |
| The Empress | Scroll of Fury | Up to 2 selected cards become Mult |
| The Emperor | Scroll of Knowledge | Create up to 2 random Scrolls |
| The Hierophant | Scroll of Blessing | Up to 2 selected cards become Bonus |
| The Lovers | Scroll of Wildgrowth | 1 selected card becomes Wild |
| The Chariot | Scroll of Thorium | 1 selected card becomes Steel |
| Justice | Scroll of Crystal | 1 selected card becomes Glass |
| The Hermit | Scroll of Greed | Double your gold (max +$20) |
| The Wheel of Fortune | Scroll of Chance | 1 in 4 chance: a random trinket with no edition gains Foil, Holo or Polychrome |
| Strength | Scroll of Strength | Raise the rank of up to 2 selected cards by 1 (A wraps to 2) |
| The Hanged Man | Scroll of Sacrifice | Destroy up to 2 selected cards |
| Death | Scroll of Undeath | Select 2 cards: the left becomes a copy of the right |
| Temperance | Scroll of Thrift | Gain the total sell value of your trinkets (max $50) |
| The Devil | Scroll of the Fel | 1 selected card becomes Gold |
| The Tower | Scroll of Earth | 1 selected card becomes Stone |
| The Star | Scroll of Gems | Up to 3 selected cards become Diamonds |
| The Moon | Scroll of the Grove | Up to 3 selected cards become Clubs |
| The Sun | Scroll of Light | Up to 3 selected cards become Hearts |
| Judgement | Scroll of Summoning | Create a random trinket (needs a free slot) |
| The World | Scroll of Blades | Up to 3 selected cards become Spades |

Price $3.

**Relics** (the 18 spectrals):

| Balatro | Our name | Effect |
|---|---|---|
| Familiar | Relic of the Court | Destroy 1 random card in hand; add 3 random enhanced face cards |
| Grim | Relic of Aces | Destroy 1 random card in hand; add 2 random enhanced Aces |
| Incantation | Relic of Numbers | Destroy 1 random card in hand; add 4 random enhanced numbered cards |
| Talisman | Relic of Gold | Add a Gold seal to 1 selected card |
| Aura | Relic of Radiance | Add Foil, Holo or Polychrome to 1 selected card |
| Wraith | Relic of the Lich | Create a rare trinket; set gold to $0 |
| Sigil | Relic of Unity | Every card in hand becomes one random suit |
| Ouija | Relic of Whispers | Every card in hand becomes one random rank; −1 hand size |
| Ectoplasm | Relic of the Void | A random trinket becomes Negative; −1 hand size |
| Immolate | Relic of Flame | Destroy 5 random cards in hand; gain $20 |
| Ankh | Relic of Rebirth | Copy a random trinket and destroy the others (Negative is removed from the copy) |
| Deja Vu | Relic of Recurrence | Add a Red seal to 1 selected card |
| Hex | Relic of Hexes | A random trinket becomes Polychrome; destroy the others |
| Trance | Relic of Insight | Add a Blue seal to 1 selected card |
| Medium | Relic of Spirits | Add a Purple seal to 1 selected card |
| Cryptid | Relic of Mirrors | Add 2 copies of 1 selected card to the deck |
| The Soul | Relic of Legends | Create the rarest trinket available (no legendaries in v2) |
| Black Hole | Relic of the Cosmos | Level up every hand type once |

Relics are not sold as single cards, only in packs. **[Balatro]**

## Shop [Balatro]

- **2 card slots.** Each rolls a trinket (weight 20), Scroll (4) or Tome (4). Trinkets roll an edition at Balatro's odds: Foil 2%, Holo 1.4%, Poly 0.3% and Negative 0.3%, with the edition adding its cost.
- **2 pack slots.** Prices are base $4, Jumbo $6 and Mega $8.
  - Arcana (Scrolls): choose 1 of 3; Jumbo 1 of 5; Mega 2 of 5.
  - Celestial (Tomes): choose 1 of 3; Jumbo 1 of 5; Mega 2 of 5.
  - Spectral (Relics): choose 1 of 2; Jumbo 1 of 4; Mega 2 of 4.
  - Buffoon (trinkets): choose 1 of 2; Jumbo 1 of 4; Mega 2 of 4.
  - Standard (playing cards with random types): choose 1 of 3; Jumbo 1 of 5; Mega 2 of 5.
  - Pack-type weights follow Balatro's. Arcana and Celestial are common; Spectral and Mega packs are rarer.
- **Opening Arcana or Spectral packs:** draws a hand of `handSize` cards from the deck, so Scrolls and Relics that need selected cards can be used immediately. Skipping is allowed.
- **Reroll:** re-rolls only the 2 card slots, not the packs, at $5 plus 1 per reroll. Unchanged from v1. **[Balatro]**
- v1's single Tome slot is replaced by the above.

## UI

- **Consumable slots:** to the right of the trinket row. They pulse when used.
- **Card faces:**
  - Enhancements change the card face texture: Stone looks like a stone slab, Glass is translucent, Gold has a gold tint, and so on.
  - The seal is a small coloured emblem in a corner.
  - Editions are animated overlays: Foil is a moving sheen, Holo a rainbow shimmer, Polychrome a hue cycle, and Negative inverted/dark.
  - These are new generated textures in `tools/gen_media.py`, plus tweens.
- **Pack opening:** an overlay panel with the choices fanned out. Click to pick. It shows the drawn hand for Arcana and Spectral packs. A Skip button closes it.
- **Deck view:** a button on the sidebar opens a panel grid of every card, grouped by suit, with type markers and counts.
- **Tally:** shows the new event kinds with floats: "+30", "×2", "Again!" for a retrigger, a shatter for Glass, and "$3".
- **Tooltips:** every card with a type shows a tooltip listing its enhancement, edition and seal.

## Difficulty

v1 flattened the target curve because the deck couldn't scale. With deck building, rerun the simulator and move the curve back toward Balatro's (300 … 50000, final boss ×2). The target is a greedy-bot win rate of roughly 10–25%. **[Call]**

## Constraints

Unchanged from v1:
- Lua 5.1 only.
- Core has no WoW API calls.
- Plain-data run state.
- All randomness goes through `run.rng`.
- Mouse only.
- Only our own textures are shipped.
- Retail plus Forever (Interface 16001).

Save version bumps to 2. A v1 save fails to load and the player starts fresh. **[Call]**

## Calls made after review

All [Call]. Each mirrors Balatro unless noted.

- **Simulator:** make the v1 review's throwaway balance bot a committed tool, `tools/sim/`. It plays a deck-building strategy: it buys and uses Scrolls and Tomes, opens packs and favours cheap enhancements, so it measures the v2 curve rather than v1's. The 10–25% target applies to it.
- **Mid-blind card changes:** cards added in a blind go to the hand and to `run.deck`, so the hand can temporarily exceed `handSize`. Destroyed cards leave a gap that's filled on the next draw. HandView must lay out up to about 12 cards by compressing the spacing further.
- **Where consumables can be used:**
  - Targeted Scrolls and Relics work during play, and while an Arcana or Spectral pack is open (on its drawn hand).
  - Untargeted ones (Greed, Summoning, Thrift, Chance, Cosmos, Stars, Knowledge and so on) also work in the shop and on the blind screen.
  - A consumable that creates consumables frees its own slot first.
  - If a "needs a free slot" effect still can't be met, the Use button is disabled and shows the reason.
- **Saving open packs:** the pack's contents, drawn hand and picks left are generated when it opens and stored in `run.shop.openPack`. A reload restores the same pack, so there's no rerolling a bad pack.
- **Stone and Wild with v1 systems:**
  - Wild counts as every suit, for suit trinkets, flushes and suit-debuff bosses alike.
  - Stone has no rank or suit, counts toward no hand, isn't a face card and is never suit-debuffed. It always scores its +50.
  - Scroll of Strength on a Stone card does nothing.
  - A debuffed card loses everything: chips, enhancement, edition, seal, retrigger and trinket onCard effects.
  - `Cards.*` and `HandEval` must handle a nil rank or suit.
- **Random rolls:**
  - Relics of the Court, Aces and Numbers never roll Stone enhancements.
  - Standard-pack cards: 40% chance of an enhancement (Stone allowed), 20% chance of a seal, and editions at the trinket edition odds, minus Negative.
  - Scroll of Chance and Relic of Radiance roll Foil 50%, Holo 35% or Poly 15%.
  - A Negative playing card only arises by copying one.
- **Trinket targets:**
  - Relic of the Void, Relic of Hexes and Scroll of Chance only pick trinkets with no edition, and Use is disabled if none qualify.
  - Relic of Rebirth copies any trinket.
  - Edition surcharges are Foil +$2, Holo +$3, Poly +$5 and Negative +$5. They're included in the cost, so sell value is half the total, which Scroll of Thrift uses.
- **Lucky gold:** paid when the card triggers, mid-hand, so trinkets that read gold (Goblin Bank) see it.
- **Relic price:** $4 (sells for $2). Scrolls and Tomes cost $3.
- **New-run defaults:** 2 consumable slots and 5 trinket slots, with no per-deck changes in v2.
- **Branching:** build on a branch off `feat/azeroth-ante`'s HEAD.

## Left to the builder

- Module layout (e.g. `Core/Consumables.lua`, `Core/Packs.lua`, `Data/Scrolls.lua`, `Data/Relics.lua`, `Data/Tomes.lua`, `Data/CardTypes.lua`).
- Exact pack-type weights. Use Balatro's if known, otherwise sensible values that keep Spectral rare.
- The overlay animation technique for editions.
- Deck view layout.

## Open items

- The Balatro effect values above are from memory. Every source fetch failed (403/410/402). The builder should cross-check against a Balatro reference before final review, and flag any mismatch.
- This sits on `feat/azeroth-ante`, which isn't merged yet. Liam still has to choose between merging and keeping the branch.
