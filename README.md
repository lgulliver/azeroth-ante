# Azeroth Ante

## What it is

A Balatro-style poker roguelike with a World of Warcraft skin, for Retail and
WoW Forever on the modern Mainline API. Play while waiting in queues: joining
opens the window, a queue pop shows an overlay and plays a sound, and accepting
or entering combat hides it. Use `/ante` to toggle the window at any time.
Mouse controls only; no key bindings.

## Install

Copy or symlink the `AzerothAnte/` folder into your client's add-on directory:

- Retail: `World of Warcraft/_retail_/Interface/AddOns/`
- Forever: `World of Warcraft/_forever_/Interface/AddOns/`

The resulting path must end in `Interface/AddOns/AzerothAnte/AzerothAnte.toc`.
Enable Azeroth Ante in the character selection screen's AddOns menu.

## Set the Interface version

In each client, run:

```text
/dump select(4, GetBuildInfo())
```

Set `## Interface` in `AzerothAnte/AzerothAnte.toc` to the returned number.
The shipped line is `## Interface: 120100, 120105, 16001`. If your client returns a
number that isn't listed, add it to that comma-separated list (or replace the
list with your number).

If `## Interface` doesn't match your client, enable "Load out of date AddOns"
on the character-select AddOns screen until you set the right number.

## How to play

1. Choose a deck, then start a blind and reach its target score.
2. Select one to five cards to play a poker hand; stronger hands score more.
3. Score chips × multiplier, and discard unwanted cards within your limits.
4. Spend gold in the shop on trinkets, consumables and packs to improve future hands.
5. Beat three blinds per stage across eight stages. You lose when you run out of
   hands, or when your hand and deck are both empty with the blind still unbeaten.

**Trinkets** come in 143 kinds (common, uncommon and rare): every non-legendary Balatro joker except the two that need skip tags.
They score left to right, so order matters: drag a trinket left or right in the trinket row to reorder it. Engineering Schematic copies the
trinket to its right and Mind Control copies the leftmost one; rule trinkets can't be copied.
Hover a trinket for its live values and sell price. You can sell trinkets during a blind as well as
in the shop; a bigger hand size draws cards at once, a smaller one applies from the next deal, and
the counts of hands and discards change at once.

Trinkets can also change and create cards (Gilded Mask, Vampiric Embrace, Pilgrim's Bounty, Gnomish Cloning Device, Letter of Commendation and Stoneform),
create consumables, and disable a boss's effect (Gladiator's Medallion).

**Consumables** sit in slots beside your trinkets. Click one to Use or Sell it.

- Scrolls change cards. Select the cards first; the popover shows what will be affected.
- Tomes level up a poker hand. Hand levels stay visible: the sidebar shows e.g.
  "Pair Lv 3" for your selection, and a Tome's tooltip shows "Pair: Lv 2 -> 3".
- Relics are powerful one-offs with a cost, such as adding cards or creating a trinket.

**Card types** come from Scrolls and packs, and show on the card and in its tooltip.

- Enhancements change how a card scores (Bonus, Mult, Wild, Glass, Steel, Stone, Gold, Lucky).
- Editions add a shimmer and a bonus: Foil, Holographic, Polychrome or Negative.
- Seals (Gold, Red, Blue, Purple) trigger when a card is played, held or discarded.

**Packs** are bought in the shop. Opening one shows a choice; pick from it, or Skip.
Arcana and Spectral packs also show a hand to aim Scrolls at. A pack left open survives `/reload`.

**Deck view**: the Deck button in the sidebar lists every card you own, with its
types, grouped by suit. Hover a card for details.

**Vouchers**: each stage's shop offers one voucher in its own tile. Buying one is a
permanent upgrade for the rest of the run (extra hands, discards or hand size, cheaper
or bigger shops, higher interest caps, and more). Most vouchers are upgrades; the two
hourglasses trade off (a stage back, and a hand or discard fewer each round). Each of the 16 base vouchers has a
stronger tier-two upgrade that can only appear once you own the base voucher and have
earned its achievement. The voucher changes after each stage's boss. Discounts never
apply to rerolls or the boss reroll.

**Boss reroll**: the Bounty Board voucher lets you reroll the upcoming boss once per
stage for 10g; its upgrade, Infinite Bounty, removes the limit. It is only offered on the
blind screen, and never at the final stage.

**Achievements** are addon-internal. They are tracked and stored in the addon's own
SavedVariables (`AzerothAnteDB`) and are never WoW achievements: they do not touch
your character's Blizzard achievements. Each unlocks a tier-two voucher, shows a toast
when earned, and is listed with its progress in the Achievements view. Progress is
kept across runs, and saves from before vouchers existed are upgraded, not discarded.

## Running the tests

From the repository root, with LuaJIT and Python 3 installed:

```sh
luajit tests/run.lua
luajit tests/smoke_ui.lua   # headless UI run against a WoW API stub (catches Lua errors only)
luajit tests/syntax.lua
python3 tests/test_media.py
```

## Balance simulator

A greedy bot plays whole runs headless and reports the win rate:

```sh
luajit tools/sim/sim.lua [runs=200] [deckId=ROGUE] [seed=1]
```

The bot also buys the vouchers it likes (extra hands, discards, hand size, interest and
shop slots) and, with room, the highest-rarity trinket it can afford. It never reorders
trinkets. It prints wins, where runs ended, and mean final gold.

Wave 1 (80 trinkets) win rates at 200 runs and seed 1: ROGUE 22.0%, WARRIOR 30.0%,
GOBLIN 31.0%, MONK 25.0%, WARLOCK 9.5%. All sat inside the intended 8-45% band; the target
curve in `Core/Run.lua` (`BASE_TARGETS`) was retuned for the bigger trinket pool.

Wave 2 (117 trinkets) win rates at 200 runs and seed 1, with `BASE_TARGETS` retuned to
`{300, 700, 1400, 2800, 5000, 8000, 11500, 16000}`: ROGUE 18.0%, WARRIOR 30.5%, GOBLIN 23.0%,
MONK 28.0%, WARLOCK 10.5%. All sit inside the intended 8-45% band. The bot never goes into debt,
even with Credit Card.

Wave 3 (143 trinkets) win rates, mean of 4 seeds (seeds 1-4, 200 runs each, 800 runs per deck), with the
same `BASE_TARGETS`: ROGUE 19.0%, WARRIOR 26.5%, GOBLIN 20.9%, MONK 23.3%, WARLOCK 7.4%. Single seeds
swing a lot (WARLOCK ranged 4.0% to 11.0%, ROGUE 13.5% to 24.5%), so judge by the mean. The bot scores
trinket offers as rarity plus 3 for any scoring hook, and skips rule, interest and round-end trinkets while a
scoring one is affordable. Four decks sit inside the intended 8-45% band; WARLOCK's mean of 7.4% is just
below it, and is accepted on purpose: Warlock unlocks last, so it is meant to be the hardest deck.

## In-game test checklist

Run these checks in Retail and Forever:

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
- [ ] No trinket icon is blank or a question mark (check Avenging Wrath, Multi-Shot, Whetstone and Hunter's Mark especially).
- [ ] `/reload` in the shop resumes on the shop screen.
- [ ] `/reload` on the blind screen resumes on the blind screen.
- [ ] A queue pop during combat plays the sound only; the window opens after combat.
- [ ] A PvP queue (battleground) opens the window, and the pop shows the overlay.
- [ ] One full run to the win or lose screen.
- [ ] Edition shimmer (Foil, Holographic, Polychrome, Negative) is visible and smooth.
- [ ] A Glass card shatters when it breaks.
- [ ] Use works on cards in play and on cards in a pack.
- [ ] `/reload` with a pack open resumes on the same pack and choices.
- [ ] A hand of more than 8 cards still fits the play area.
- [ ] The deck view opens, shows every card and its types, and closes.
- [ ] Buying the shop's voucher works: the tile stamps BOUGHT, then reads "Sold out this stage", and its effect applies.
- [ ] The boss reroll works (with the Bounty Board voucher) and is limited as described.
- [ ] Earning an achievement shows a toast.
- [ ] The Achievements view opens, lists every achievement with progress, and closes.
- [ ] `/reload` mid-run after updating the addon keeps the run (the old save migrates).
- [ ] Abandon Run asks for a second click (and reverts after 3 seconds), then returns to the deck screen.

## Art

Art is placeholder and generated by `tools/gen_media.py`. Blizzard icons are
referenced from the game rather than bundled.
