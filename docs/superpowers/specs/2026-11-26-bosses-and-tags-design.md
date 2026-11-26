# Bosses and skip tags

Status: approved [Liam, 2026-11-26]. Brings the boss roster and blind skipping up to vanilla Balatro (1.0.1), checked against balatrowiki.org.

## Goals

- Every Balatro boss blind has a Warcraft counterpart with the same rule, target multiplier and minimum ante.
- The final ante draws one of five finisher bosses instead of a plain Ragnaros.
- The small and big blinds can be skipped for a tag, as in Balatro, with all 24 tags.
- Numbers are Balatro's. Names and flavour are Warcraft's.

Out of scope: stakes, endless mode, legendary trinkets, the other ten decks, Diet Cola and Throwback (they need tags, so they can follow this spec).

## Bosses

### Roster

Existing bosses keep their ids and gain the Balatro boss they already play as. The new ones:

| Balatro | Id | Name | Min ante | Target | Rule |
|---|---|---|---|---|---|
| The Hook | GREENSKIN | Captain Greenskin | 1 | ×2 | After each hand, discard 2 random held cards |
| The Club | THREDD | Bazil Thredd | 1 | ×2 | Clubs are debuffed |
| The Manacle | TARGORR | Targorr the Dread | 1 | ×2 | −1 hand size |
| The Pillar | ARCHAEDAS | Archaedas | 1 | ×2 | Cards played earlier this ante are debuffed |
| The House | MOROES | Moroes | 2 | ×2 | The first hand is drawn face down |
| The Wall | PATCHWERK | Patchwerk | 2 | ×4 | No rule; a much bigger target |
| The Wheel | THERMAPLUGG | Mekgineer Thermaplugg | 2 | ×2 | 1 in 7 cards is drawn face down |
| The Arm | FROSTWHISPER | Ras Frostwhisper | 2 | ×2 | The played hand loses a level (not below 1) |
| The Fish | MOROGRIM | Morogrim Tidewalker | 2 | ×2 | Cards drawn after each hand are face down |
| The Mouth | GLUTH | Gluth | 2 | ×2 | Only the first hand type played this round can be played |
| The Mark | SKERAM | The Prophet Skeram | 2 | ×2 | Face cards are drawn face down |
| The Eye | ARAN | Shade of Aran | 3 | ×2 | No hand type can be repeated this round |
| The Tooth | REVILGAZ | Baron Revilgaz | 3 | ×2 | Lose 1g per card played |
| The Serpent | HAKKAR | Hakkar the Soulflayer | 5 | ×2 | After a play or discard, always draw exactly 3 |
| The Ox | GRUUL | Gruul the Dragonkiller | 6 | ×2 | Playing your most-played hand sets gold to 0 |

Finisher bosses (ante 8 only, reward 8g):

| Balatro | Id | Name | Target | Rule |
|---|---|---|---|---|
| Crimson Heart | RAGNAROS | Ragnaros the Firelord | ×2 | One random trinket is disabled each hand |
| Violet Vessel | CTHUN | C'Thun | ×6 | No rule; a huge target |
| Amber Acorn | YOGG | Yogg-Saron | ×2 | Flips your trinkets face down and shuffles them |
| Verdant Leaf | XAVIUS | Xavius | ×2 | All cards are debuffed until you sell a trinket |
| Cerulean Bell | KELTHUZAD | Kel'Thuzad | ×2 | One card is always forced into your selection |

### Draw

- Stages 1–7 draw as now (fewest appearances among bosses whose minimum ante allows the stage).
- Stage 8 draws one finisher at random. Director's Cut and Retcon can reroll a finisher into another finisher (removes today's "the final boss cannot be rerolled").
- Achievement RETCON ("fight every boss") counts the whole roster.

### New mechanics

- **Face-down cards.** A card can be drawn face down (`card.faceDown`), shown as its deck back. It still plays and scores normally; the player just can't see it. Face-down cards turn face up when played, at the end of the blind, and when the boss is disabled. Hand evaluation preview hides the hand name while any selected card is face down.
- **Boss hooks.** Boss defs gain optional hooks, called from `Run` and `Scoring`:
  - `onDraw(run, card)` → face down or not (House, Wheel, Fish, Mark).
  - `canPlayHand(run, handId)` → false plus a reason (Mouth, Eye).
  - `afterPlay(run, played, handId)` (Hook, Arm, Tooth, Ox).
  - `drawCount(run)` (Serpent).
  - `handSize` (Manacle), and `debuff(card, rules, run)` gains `run` (Pillar).
  - Finishers: `beforeHand(run)` (Crimson Heart), `onStart(run)` (Amber Acorn, Cerulean Bell), `onSell(run)` (Verdant Leaf).
- Disabling a boss (Chicot-style trinkets, Luchador) switches every hook off and turns face-down cards up.

## Skip blinds and tags

### Flow

- On the blind-select screen, the small and big blinds show a **Skip** button and the tag skipping would give. The boss blind cannot be skipped.
- Skipping gives no blind reward and no interest, adds the tag, and moves to the next blind. The run counts blinds skipped (Speed tag, and later Throwback).
- Each blind's tag is rolled when the ante starts, so it's visible before choosing. Tags with a minimum ante are not rolled earlier.
- Held tags show as small icons beside the sidebar, with a tooltip.

### Tags

| Balatro | Id | Name | Min ante | Effect |
|---|---|---|---|---|
| Uncommon | UNCOMMON | Uncommon Quest Reward | 1 | Next shop has a free uncommon trinket |
| Rare | RARE | Rare Quest Reward | 1 | Next shop has a free rare trinket |
| Negative | NEGATIVE | Void-Touched Reward | 2 | Next base-edition shop trinket becomes Negative and free |
| Foil | FOIL | Gilded Reward | 1 | Next base-edition shop trinket becomes Foil and free |
| Holographic | HOLO | Prismatic Reward | 1 | …Holographic and free |
| Polychrome | POLY | Titanforged Reward | 1 | …Polychrome and free |
| Investment | INVESTMENT | Goblin Investment | 1 | Gain 25g after defeating the next boss |
| Voucher | VOUCHER | Vendor Restock | 1 | Adds a voucher to the next shop |
| Boss | BOSS | Wanted Poster | 1 | Rerolls the boss blind |
| Standard | STANDARD | Darkmoon Card Gift | 2 | Free Heavy Darkmoon Card Bundle |
| Charm | CHARM | Scribe's Gift | 1 | Free Heavy Scribe's Satchel |
| Meteor | METEOR | Archivist's Gift | 2 | Free Heavy Archivist's Crate |
| Buffoon | BUFFOON | Lockbox Key | 2 | Free Heavy Trinket Lockbox |
| Ethereal | ETHEREAL | Relic Hunter's Gift | 2 | Free Relic Cache |
| Handy | HANDY | Veteran's Pay | 2 | 1g per hand played this run |
| Garbage | GARBAGE | Scrapper's Pay | 2 | 1g per unused discard this run |
| Coupon | COUPON | Darkmoon Faire Coupon | 1 | Initial cards and packs in the next shop are free |
| Double | DOUBLE | Bonus Roll | 1 | Copies the next tag taken (not another Bonus Roll) |
| Juggle | JUGGLE | Juggler's Gloves | 1 | +3 hand size next round |
| D6 | D6 | Heirloom Dice | 1 | Rerolls in the next shop start at 0g |
| Top-up | TOPUP | Recruit-a-Friend | 2 | Create up to 2 common trinkets (needs free slots) |
| Speed | SPEED | Flight Master's Whistle | 1 | 5g per blind skipped this run |
| Orbital | ORBITAL | Algalon's Insight | 2 | Levels up a random hand three times |
| Economy | ECONOMY | Auction House Flip | 1 | Doubles your gold (max +40g) |

Pack tags open the pack immediately, free, as Balatro does. Shop tags wait for the next shop.

### Interactions

- Trinkets that care about skipping (Red Card already counts pack skips; Diet Cola and Throwback come later) hook the same `onSkip` event.
- Saves gain `run.tags`, `run.blindTags` and `run.skips`; older saves load with none.

## Testing

- Unit tests per boss rule and per tag, plus the draw rules (minimum ante, finishers only at ante 8).
- Smoke test: skip button, tag display, face-down cards render as backs and flip on play.
- Re-run the simulator; teach the bot to skip when the tag is a free pack or economy tag, so the curve check stays meaningful.

## Build order

1. Face-down cards and boss hooks, then the 15 regular bosses.
2. Finishers and the ante-8 draw.
3. Skip flow and tag state (save/load, UI).
4. The 24 tags.
