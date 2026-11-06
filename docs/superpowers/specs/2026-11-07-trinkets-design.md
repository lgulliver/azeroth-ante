# Azeroth Ante: Full Trinket Set (Balatro jokers)

Date: 2026-11-07. Status: draft for approval.
Builds on v0.3.0 (vouchers and achievements, on `main`).

Legend:
- **[Liam]**: decided by Liam.
- **[Call]**: my call.
- **[Balatro]**: copied from Balatro. Values are from memory, so the builder flags anything they believe differs.

## Intent

Trinkets are our jokers. Balatro has 150 jokers and we have 20, and the joker variety is what makes Balatro runs feel different from each other. Port the whole non-legendary set: 145 jokers, of which 143 now and 2 (Diet Cola, Throwback) with skip tags. Each gets a WoW name and Balatro's exact effect. **[Liam: "full set, in waves"; standing rule "reskin with WoW names, keep Balatro effects"]**

## Goals

- All 143 non-legendary, non-tag Balatro jokers as trinkets, with Balatro rarity, cost and effect.
- The engine support they need: per-trinket state, the new trigger points, rule changes, copying, and a shared probability roll.
- The existing 20 trinkets keep their WoW name and id, but take on the exact effect of the Balatro joker they're closest to (see the remap column).
- Order matters, as in Balatro. Trinkets can be reordered by dragging them in the trinket row.
- Delivery in three waves. Each wave is shippable and playable in game.

## Non-goals

- **Legendary jokers and The Soul.** Canio, Triboulet, Yorick, Chicot and Perkeo are the next roadmap item.
- **Diet Cola and Throwback.** They depend on skip-blind tags. They're added in the skip-tags feature, and stay out of the pool until then.
- **Balatro's per-joker unlock conditions.** Many jokers start locked in Balatro. That would be a later achievements pass. **[Call]** Here, everything is in the pool from the start.
- **Stickers** (Eternal, Perishable, Rental). These belong to stakes.

## Anti-goals

- **Clunky interaction** **[Liam]**:
  - Every trinket trigger animates on its slot in order: the slot juices and a +chips, +mult or ×mult popup appears.
  - State changes show a short message on the slot ("Upgrade!", "+1 Mult", "Extinct!", "Saved!").
  - Trinkets that get destroyed or created animate out and in.
  - Dragging to reorder is smooth and never drops a trinket.
- **Effects that silently differ from Balatro.** If WoW can't show something, only the visual is approximated, never the rule. **[Liam]**

## Engine

### Trinket instance

`run.trinkets[i] = { id, ed, paid, sellBonus = 0, state = {} }`.
- Plain data, saved as is.
- `state` holds counters such as current mult, ×mult, hands left or the chosen suit.
- Save version 4 migrates v3 saves by adding `sellBonus = 0` and `state = {}`, and initialising remapped trinkets' state.

### Hook kinds

Every hook is optional on a trinket def.

- **Effect hooks** return `{chips=, mult=, xmult=, gold=, retriggers=, msg=}` or nil.
  - They're pure functions of their context and the instance they're given.
  - Blueprint and Brainstorm call the source trinket's effect hooks, passing the source's instance.
- **Update hooks** mutate `self.state` or the run.
  - They're called once, only for the trinket itself, and never through a copy.

This split is how copying works without double-counting scaling. **[Call]**

### When hooks run, mirroring Balatro's scoring order

1. **`before` (update).**
   - Runs left to right after the hand type is known and before any card scores.
   - Examples: Ride the Bus, Runner, Square, Green Joker, Spare Trousers, Obelisk, Vampire, Midas Mask, Space Joker, DNA, To Do List, Superposition, Séance and Sixth Sense.
2. **Scoring cards, left to right.** Each card goes through: card chips, then enhancement, edition and seal (as now), then each trinket's `onCard` effect.
   - Retriggers: the total is the sum of `retrigger(ctx, self, card)` effect hooks, plus a Red seal.
   - Examples: Hack, Sock and Buskin, Dusk, Seltzer and Hanging Chad.
   - Each retrigger replays the whole card step.
3. **Held cards, left to right.** Each held card gets the Steel effect, then each trinket's `onHeld` effect (Baron, Shoot the Moon, Raised Fist, Reserved Parking).
   - Retriggers come from a Red seal plus Mime.
4. **Trinkets, left to right.** Each trinket applies its edition pre-effect, then its `onHand` effect, then its edition post-effect.
   - Baseball Card adds its ×1.5 after each Uncommon trinket.
5. **Observatory** (unchanged), then the total.
6. **`after` (update).** Runs after scoring: Ice Cream, Seltzer and Ramen decay, Glass destruction, Mr. Bones.

### Other trigger points (update hooks)

- `onBlindSelect(run, self)`
- `onDiscard(run, self, cards)`, called once per discard action, in addition to per-card effects
- `onRoundEnd(run, self) -> gold`
- `onBossDefeated`
- `onShopReroll`
- `onSell(run, self, soldThing)`, fired for every trinket when anything is sold
- `onSelfSold`
- `onPackOpened`
- `onPackSkipped`
- `onConsumableUsed(run, self, item)`
- `onCardAdded(run, self, card)`
- `onCardDestroyed(run, self, card)`
- `onLuckyTrigger`

### Rule switches

`ns.TrinketRules.has(run, "FOUR_FINGERS")` and similar, consulted by:
- **HandEval:** FOUR_FINGERS, SHORTCUT and SMEARED (Smeared applies to suit checks everywhere)
- **Cards.isFace:** PAREIDOLIA
- **Scoring:** SPLASH (every played card scores)
- **Shop:** SHOWMAN (duplicates allowed), CHAOS (one free reroll per shop) and ASTRONOMER (Tomes and Celestial packs are free)
- **Run:** CREDIT_CARD (gold may go down to -20)

Rule trinkets aren't copyable, as in Balatro.

### Probability

`ns.Prob.roll(rng, run, num, den)` returns whether `rng < num * mult / den`, where mult = 2 per Oops! All 6s owned.
- Every listed chance goes through it: Lucky cards, Glass breaks, relic chances (e.g. Wheel of Fortune), and trinket chances.
- Descriptions show the effective odds ("2 in 4").

### Copying

- **Blueprint** copies the trinket to its right.
- **Brainstorm** copies the leftmost trinket.
- Copying a copier follows the chain with a cycle guard.
- Copying a non-copyable trinket does nothing, and the tooltip says "incompatible".

### Gold

- Effects can return `gold`.
- Scoring gold keeps using `goldRef`, so it appears mid-tally as it does now.
- Round-end gold appears as its own payout line per trinket ("Golden Joker +4g"), not lumped together.

### Sell value

- Sell value = `max(1, floor(paid / 2)) + sellBonus`.
- Egg and Gift Card raise `sellBonus`.

### Pool gating

An optional `inPool(run)` on a def controls when it can appear:
- Cavendish appears only after Gros Michel has gone extinct this run.
- Gros Michel is out once it's extinct.
- Steel Joker needs a Steel card, Stone Joker a Stone card, Lucky Cat a Lucky card and Golden Ticket a Gold card in the deck.
- Glass Joker needs a Glass card in the deck.

Existing behaviour stays: rarities are 70/25/5, owned trinkets are excluded, and Showman lifts that exclusion.

### Live text

- `status(self, run)` returns a string for the tooltip, such as "Currently +12 Mult" or "Suit: Hearts".
- Trinkets that pick something per round (To Do List, Mail-In Rebate, Castle, Ancient Joker, The Idol) roll it on purchase and at each round end, using run.rng.

### Card fields

- Played cards can carry `bonusChips` (Hiker), which is persisted. Cards.chipValue adds it.
- Created cards use `run.nextCardId`.

## UI

- **Reorder:** drag a trinket left or right in the trinket row. It slides into place with Tween and the others shift over. Allowed in the shop and between hands; it's locked while a hand is tallying.
- **Tooltips:** name, rarity, effect with live values, `status`, sell value, and "Copies: <name>" or "incompatible" for Blueprint and Brainstorm.
- **Tally:** new event kinds animate on the right slot: `retrigger` from a trinket ("Again!"), `trinketMsg`, `trinketDestroyed` and `cardCreated`. Created cards fly into the hand or the deck.
- **Shop and Buffoon packs:** no layout change. Rarity shows as a small coloured label (Common grey, Uncommon green, Rare blue, using WoW item-quality colours). **[Call]**

## The 145

Hook groups (these set the waves):
- **S:** scoring only, plus rules and copying. **Wave 1.**
- **E:** economy and lifecycle (gold, discards, blind select, round end, shop, sell, hand size). **Wave 2.**
- **D:** creates or changes cards or consumables, boss interaction, deck-wide conditions. **Wave 3.**
- **X:** deferred to skip tags.

In the table, ★ means a remap of one of the existing 20 (keep its id). Cost is in gold. WoW names are proposed; the builder may fix clashes.

| # | Balatro | Rar | $ | Effect | Grp | WoW name (id) |
|---|---|---|---|---|---|---|
| 1 | Joker | C | 2 | +4 Mult | S | ★ Arcane Intellect (ARCANE_INTELLECT) |
| 2 | Greedy Joker | C | 5 | Played Diamonds +3 Mult when scored | S | ★ Jeweler's Kit (JEWELERS_KIT) |
| 3 | Lusty Joker | C | 5 | Hearts +3 Mult | S | ★ Healthstone (HEALTHSTONE) |
| 4 | Wrathful Joker | C | 5 | Spades +3 Mult | S | ★ Whetstone (WHETSTONE) |
| 5 | Gluttonous Joker | C | 5 | Clubs +3 Mult | S | ★ Ogre Cudgel (OGRE_CUDGEL) |
| 6 | Jolly Joker | C | 3 | +8 Mult if hand contains a Pair | S | ★ Twin Blades (TWIN_BLADES) |
| 7 | Zany Joker | C | 4 | +12 Mult if Three of a Kind | S | ★ Cleave (CLEAVE) |
| 8 | Mad Joker | C | 4 | +10 Mult if Two Pair | S | Twin Fangs (TWIN_FANGS) |
| 9 | Crazy Joker | C | 4 | +12 Mult if Straight | S | ★ Multi-Shot (MULTI_SHOT) |
| 10 | Droll Joker | C | 4 | +10 Mult if Flush | S | ★ Elemental Attunement (ELEMENTAL) |
| 11 | Sly Joker | C | 3 | +50 Chips if Pair | S | Pickpocket (PICKPOCKET) |
| 12 | Wily Joker | C | 4 | +100 Chips if Three of a Kind | S | Tricks of the Trade (TRICKS_TRADE) |
| 13 | Clever Joker | C | 4 | +80 Chips if Two Pair | S | Double Agent (DOUBLE_AGENT) |
| 14 | Devious Joker | C | 4 | +100 Chips if Straight | S | Shadowstep (SHADOWSTEP) |
| 15 | Crafty Joker | C | 4 | +80 Chips if Flush | S | Totemic Recall (TOTEMIC_RECALL) |
| 16 | Half Joker | C | 5 | +20 Mult if played hand has 3 or fewer cards | S | Gnomish Shrink Ray (SHRINK_RAY) |
| 17 | Joker Stencil | U | 8 | ×1 Mult per empty trinket slot (Stencil counts as empty) | S | Spirit Healer (SPIRIT_HEALER) |
| 18 | Four Fingers | U | 7 | Flushes and Straights can be made with 4 cards | S | Sleight of Hand (SLEIGHT_HAND) |
| 19 | Mime | U | 5 | Retrigger all held-in-hand abilities | S | Mirror Image (MIRROR_IMAGE) |
| 20 | Credit Card | C | 1 | Go up to -20g in debt | E | Venture Co. Loan (VENTURE_LOAN) |
| 21 | Ceremonial Dagger | U | 6 | On blind select, destroy trinket to the right; add double its sell value to this Mult | E | Soul Harvest (SOUL_HARVEST) |
| 22 | Banner | C | 5 | +30 Chips per remaining discard | S | ★ Combo Points (COMBO_POINTS) |
| 23 | Mystic Summit | C | 5 | +15 Mult when 0 discards remaining | S | Mount Hyjal (MOUNT_HYJAL) |
| 24 | Marble Joker | U | 6 | On blind select, add a Stone card to deck | D | Stoneform (STONEFORM) |
| 25 | Loyalty Card | U | 5 | ×4 Mult every 6 hands played (shows countdown) | S | ★ Drums of Bloodlust (BLOODLUST) |
| 26 | 8 Ball | C | 5 | 1 in 4 per played 8 to create a Scroll (needs room) | D | Fortune Card (FORTUNE_CARD) |
| 27 | Misprint | C | 4 | +0 to 23 Mult (random) | S | ★ Gnomish Luck Charm (LUCKY_CHARM) |
| 28 | Dusk | U | 5 | Retrigger all played cards in final hand of round | S | Eventide (EVENTIDE) |
| 29 | Raised Fist | C | 5 | Adds double the nominal value of the lowest held card to Mult (Ace 11, faces 10) | S | Fist of Justice (FIST_JUSTICE) |
| 30 | Chaos the Clown | C | 4 | 1 free reroll per shop | E | Darkmoon Ticket (DARKMOON_TICKET) |
| 31 | Fibonacci | U | 8 | Played A, 2, 3, 5, 8 give +8 Mult | S | Titanic Ratio (TITANIC_RATIO) |
| 32 | Steel Joker | U | 7 | ×0.2 Mult per Steel card in full deck (base ×1) | D | Ironforge Anvil (IRONFORGE_ANVIL) |
| 33 | Scary Face | C | 4 | Played face cards +30 Chips | S | ★ Royal Guard (ROYAL_GUARD) |
| 34 | Abstract Joker | C | 4 | +3 Mult per trinket | S | ★ Battle Shout (BATTLE_SHOUT) |
| 35 | Delayed Gratification | C | 4 | 2g per discard left at round end if none used | E | Inner Peace (INNER_PEACE) |
| 36 | Hack | U | 6 | Retrigger played 2, 3, 4, 5 | S | Hack and Slash (HACK_SLASH) |
| 37 | Pareidolia | U | 5 | All cards count as face cards | S | Mind Vision (MIND_VISION) |
| 38 | Gros Michel | C | 5 | +15 Mult; 1 in 6 chance destroyed at round end | E | Ripe Banana (RIPE_BANANA) |
| 39 | Even Steven | C | 4 | Played 10, 8, 6, 4, 2 give +4 Mult | S | Balance of Power (BALANCE_POWER) |
| 40 | Odd Todd | C | 4 | Played A, 9, 7, 5, 3 give +31 Chips | S | Odd Goblin (ODD_GOBLIN) |
| 41 | Scholar | C | 4 | Played Aces +20 Chips and +4 Mult | S | ★ Hunter's Mark (HUNTERS_MARK) |
| 42 | Business Card | C | 4 | Played face cards 1 in 2 to give 2g | S | Trade Prince Card (TRADE_PRINCE) |
| 43 | Supernova | C | 5 | +Mult equal to times this hand type played this run | S | Starfall (STARFALL) |
| 44 | Ride the Bus | C | 6 | +1 Mult per consecutive hand without a scoring face card (resets) | S | Flight Path (FLIGHT_PATH) |
| 45 | Space Joker | U | 5 | 1 in 4 to level up played hand | S | Twisting Nether (TWISTING_NETHER) |
| 46 | Egg | C | 4 | +3g sell value at round end | E | Whelpling Egg (WHELP_EGG) |
| 47 | Burglar | U | 6 | On blind select, +3 hands and lose all discards | E | SI:7 Agent (SI7_AGENT) |
| 48 | Blackboard | U | 6 | ×3 Mult if all held cards are Spades or Clubs | S | Dark Pact (DARK_PACT) |
| 49 | Runner | C | 5 | Gains +15 Chips if hand contains a Straight | S | Sprint (SPRINT) |
| 50 | Ice Cream | C | 5 | +100 Chips; -5 per hand played; melts at 0 | S | Tigule's Ice Cream (TIGULES) |
| 51 | DNA | R | 8 | First hand of round is 1 card: add a permanent copy to deck and draw it | D | Gnomish Cloning Device (CLONING_DEVICE) |
| 52 | Splash | C | 3 | Every played card counts in scoring | S | Arcane Explosion (ARCANE_EXPLOSION) |
| 53 | Blue Joker | C | 5 | +2 Chips per card remaining in the draw pile | S | ★ Power Word: Fortitude (FORTITUDE) |
| 54 | Sixth Sense | U | 6 | First hand of round is a single 6: destroy it, create a Relic | D | Divination (DIVINATION) |
| 55 | Constellation | U | 6 | Gains ×0.1 Mult per Tome used | D | Starlight Codex (STARLIGHT_CODEX) |
| 56 | Hiker | U | 5 | Every played card permanently gains +5 Chips when scored | D | Pilgrim's Bounty (PILGRIM) |
| 57 | Faceless Joker | C | 4 | 5g if 3+ face cards discarded at once | E | Faceless One (FACELESS_ONE) |
| 58 | Green Joker | C | 4 | +1 Mult per hand played, -1 per discard | E | Fel Infusion (FEL_INFUSION) |
| 59 | Superposition | C | 4 | Create a Scroll if hand contains an Ace and a Straight | D | Chronomancy (CHRONOMANCY) |
| 60 | To Do List | C | 4 | 4g if hand is [hand type]; changes each round | E | Daily Quest (DAILY_QUEST) |
| 61 | Cavendish | C | 4 | ×3 Mult; 1 in 1000 destroyed at round end | E | Golden Banana (GOLDEN_BANANA) |
| 62 | Card Sharp | U | 6 | ×3 Mult if this hand type was already played this round | S | ★ Avenging Wrath (AVENGING_WRATH) |
| 63 | Red Card | C | 5 | Gains +3 Mult per pack skipped | E | Pack Rat (PACK_RAT) |
| 64 | Madness | U | 7 | Small/Big blind select: gain ×0.5 Mult, destroy a random other trinket | E | Whispers of the Old Gods (OLD_GODS) |
| 65 | Square Joker | C | 4 | Gains +4 Chips if hand has exactly 4 cards | S | Four Winds (FOUR_WINDS) |
| 66 | Séance | U | 6 | Straight Flush: create a random Relic | D | Speak with Dead (SPEAK_DEAD) |
| 67 | Riff-Raff | C | 6 | On blind select, create 2 Common trinkets (needs room) | E | Call to Arms (CALL_TO_ARMS) |
| 68 | Vampire | U | 7 | Gains ×0.1 Mult per scoring enhanced card; removes the enhancement | D | Vampiric Embrace (VAMPIRIC) |
| 69 | Shortcut | U | 7 | Straights may skip one rank | S | Portal (PORTAL) |
| 70 | Hologram | U | 7 | Gains ×0.25 Mult per playing card added to deck | D | Phantasm (PHANTASM) |
| 71 | Vagabond | R | 8 | Create a Scroll if hand played with 4g or less | D | Wandering Peddler (PEDDLER) |
| 72 | Baron | R | 8 | Held Kings ×1.5 Mult each | S | Crown of the Kings (CROWN_KINGS) |
| 73 | Cloud 9 | U | 7 | 1g per 9 in full deck at round end | E | Sky Golem (SKY_GOLEM) |
| 74 | Rocket | U | 6 | 1g at round end; +2g payout per boss defeated | E | Goblin Rocket (GOBLIN_ROCKET) |
| 75 | Obelisk | R | 8 | Gains ×0.2 Mult per consecutive hand not of your most played type (resets) | S | Titan Obelisk (OBELISK) |
| 76 | Midas Mask | U | 7 | Played face cards become Gold when scored | D | Gilded Mask (GILDED_MASK) |
| 77 | Luchador | U | 5 | Sell to disable current boss | D | Gladiator's Medallion (GLAD_MEDALLION) |
| 78 | Photograph | C | 5 | First scoring face card ×2 Mult | S | S.E.L.F.I.E. Camera (SELFIE_CAMERA) |
| 79 | Gift Card | U | 6 | +1g sell value to every trinket and consumable at round end | E | Winter Veil Gift (WINTER_VEIL) |
| 80 | Turtle Bean | U | 6 | +5 hand size, -1 per round | E | Fertile Seed (FERTILE_SEED) |
| 81 | Erosion | U | 6 | +4 Mult per card below the starting deck size | D | Sandstorm (SANDSTORM) |
| 82 | Reserved Parking | C | 6 | Held face cards 1 in 2 to give 1g | S | Stable Master (STABLE_MASTER) |
| 83 | Mail-In Rebate | C | 4 | 5g per discarded [rank]; rank changes each round | E | Postmaster's Rebate (POSTMASTER) |
| 84 | To the Moon | U | 5 | +1g interest per 5g held | E | Goblin Investment (GOBLIN_INVEST) |
| 85 | Hallucination | C | 4 | 1 in 2 to create a Scroll when any pack opened | D | Dreamwalker (DREAMWALKER) |
| 86 | Fortune Teller | C | 6 | +1 Mult per Scroll used this run | D | Seer (SEER) |
| 87 | Juggler | C | 4 | +1 hand size | E | Reagent Bag (REAGENT_BAG) |
| 88 | Drunkard | C | 4 | +1 discard each round | E | Dwarven Stout (DWARVEN_STOUT) |
| 89 | Stone Joker | U | 6 | +25 Chips per Stone card in full deck | D | Earthen Ring (EARTHEN_RING) |
| 90 | Golden Joker | C | 6 | 4g at round end | E | ★ Hearthstone (HEARTHSTONE) |
| 91 | Lucky Cat | U | 6 | Gains ×0.25 Mult per Lucky card trigger | D | Fortune Cat (FORTUNE_CAT) |
| 92 | Baseball Card | R | 8 | Uncommon trinkets each ×1.5 Mult | S | Guild Charter (GUILD_CHARTER) |
| 93 | Bull | U | 6 | +2 Chips per 1g held | S | Tauren Charge (TAUREN_CHARGE) |
| 94 | Diet Cola | U | 6 | Sell to create a Double Tag | X | (skip tags) |
| 95 | Trading Card | U | 6 | First discard of round is 1 card: destroy it, 3g | E | Trading Post (TRADING_POST) |
| 96 | Flash Card | U | 5 | Gains +2 Mult per shop reroll | E | Flash Heal (FLASH_HEAL) |
| 97 | Popcorn | C | 5 | +20 Mult; -4 per round; eaten at 0 | E | Darkmoon Popcorn (POPCORN) |
| 98 | Spare Trousers | U | 6 | Gains +2 Mult if hand contains Two Pair | S | Spare Tabard (SPARE_TABARD) |
| 99 | Ancient Joker | R | 8 | Played [suit] ×1.5 Mult; suit changes each round | S | Titan Relic (TITAN_RELIC) |
| 100 | Ramen | U | 6 | ×2 Mult; -×0.01 per card discarded; eaten at ×1 | E | Pandaren Noodles (NOODLES) |
| 101 | Walkie Talkie | C | 4 | Played 10s and 4s +10 Chips +4 Mult | S | Goblin Radio (GOBLIN_RADIO) |
| 102 | Seltzer | U | 6 | Retrigger all played cards for next 10 hands | S | Morning Glory Dew (MORNING_DEW) |
| 103 | Castle | U | 6 | Gains +3 Chips per discarded [suit]; suit changes each round | E | Stormwind Keep (STORMWIND_KEEP) |
| 104 | Smiley Face | C | 4 | Played face cards +5 Mult | S | Cheerful Gnome (CHEERFUL_GNOME) |
| 105 | Campfire | R | 9 | Gains ×0.25 Mult per card sold; resets on boss defeat | E | Cooking Fire (COOKING_FIRE) |
| 106 | Golden Ticket | C | 5 | Played Gold cards give 4g | D | Golden Ticket (GOLDEN_TICKET) |
| 107 | Mr. Bones | U | 5 | Prevents loss if score ≥ 25% of target; destroyed | E | Soulstone (SOULSTONE) |
| 108 | Acrobat | U | 6 | ×3 Mult on final hand of round | S | ★ Execute (EXECUTE) |
| 109 | Sock and Buskin | U | 6 | Retrigger played face cards | S | Court Jester (COURT_JESTER) |
| 110 | Swashbuckler | C | 4 | +Mult equal to total sell value of other trinkets | S | Bloodsail Buccaneer (BLOODSAIL) |
| 111 | Troubadour | U | 6 | +2 hand size, -1 hand each round | E | Wandering Minstrel (MINSTREL) |
| 112 | Certificate | U | 6 | Round start: add a random card with a random seal to hand (permanent) | D | Letter of Commendation (COMMENDATION) |
| 113 | Smeared Joker | U | 7 | Hearts=Diamonds, Spades=Clubs | S | Murky Ink (MURKY_INK) |
| 114 | Throwback | U | 6 | ×0.25 Mult per blind skipped | X | (skip tags) |
| 115 | Hanging Chad | C | 4 | Retrigger first scoring card 2 more times | S | Echo of Doom (ECHO_DOOM) |
| 116 | Rough Gem | U | 7 | Played Diamonds give 1g | S | Uncut Gem (UNCUT_GEM) |
| 117 | Bloodstone | U | 7 | Played Hearts 1 in 2 for ×1.5 Mult | S | Bloodstone (BLOODSTONE) |
| 118 | Arrowhead | U | 7 | Played Spades +50 Chips | S | Rugged Arrowhead (ARROWHEAD) |
| 119 | Onyx Agate | U | 7 | Played Clubs +7 Mult | S | Shadowgem (SHADOWGEM) |
| 120 | Glass Joker | U | 6 | Gains ×0.75 Mult per Glass card destroyed | D | Glass Cannon (GLASS_CANNON) |
| 121 | Showman | U | 5 | Trinkets and consumables may repeat | E | Ringmaster Silas (SILAS) |
| 122 | Flower Pot | U | 6 | ×3 Mult if hand has a Diamond, Club, Heart and Spade scoring | S | Peacebloom Pot (PEACEBLOOM) |
| 123 | Blueprint | R | 10 | Copies trinket to the right | S | Engineering Schematic (SCHEMATIC) |
| 124 | Wee Joker | R | 8 | Gains +8 Chips per played 2 scored | S | Tiny Gnome (TINY_GNOME) |
| 125 | Merry Andy | U | 7 | +3 discards, -1 hand size | E | Drunken Brawler (BRAWLER) |
| 126 | Oops! All 6s | U | 4 | Doubles all listed probabilities | S | Loaded Dice (LOADED_DICE) |
| 127 | The Idol | U | 6 | Played [rank] of [suit] ×2 Mult; changes each round | S | Zandalari Idol (ZANDALARI_IDOL) |
| 128 | Seeing Double | U | 6 | ×2 Mult if scoring has a Club and a non-Club | S | Double Vision (DOUBLE_VISION) |
| 129 | Matador | U | 7 | 8g if hand triggers the boss ability | D | Arena Champion (ARENA_CHAMPION) |
| 130 | Hit the Road | R | 8 | Gains ×0.5 Mult per Jack discarded this round (resets) | E | Mount Up (MOUNT_UP) |
| 131 | The Duo | R | 8 | ×2 Mult if Pair | S | The Twin Val'kyr (TWIN_VALKYR) |
| 132 | The Trio | R | 8 | ×3 Mult if Three of a Kind | S | Council of Three (COUNCIL_THREE) |
| 133 | The Family | R | 8 | ×4 Mult if Four of a Kind | S | The Four Horsemen (FOUR_HORSEMEN) |
| 134 | The Order | R | 8 | ×3 Mult if Straight | S | The Silver Hand (SILVER_HAND) |
| 135 | The Tribe | R | 8 | ×2 Mult if Flush | S | The Horde (THE_HORDE) |
| 136 | Stuntman | R | 7 | +250 Chips, -2 hand size | E | Leeroy Jenkins (LEEROY) |
| 137 | Invisible Joker | R | 8 | After 2 rounds, sell to duplicate a random trinket | E | Invisibility Potion (INVIS_POTION) |
| 138 | Brainstorm | R | 10 | Copies leftmost trinket | S | Mind Control (MIND_CONTROL) |
| 139 | Satellite | U | 6 | 1g per unique Tome used this run at round end | D | Mage Tower (MAGE_TOWER) |
| 140 | Shoot the Moon | C | 5 | Held Queens +13 Mult each | S | Moonfire (MOONFIRE) |
| 141 | Driver's License | R | 7 | ×3 Mult if 16+ enhanced cards in full deck | D | Master Riding (MASTER_RIDING) |
| 142 | Cartomancer | U | 6 | On blind select, create a Scroll (needs room) | D | Inscriptionist (INSCRIPTIONIST) |
| 143 | Astronomer | U | 8 | Tomes and Celestial packs in shop are free | E | Stargazer (STARGAZER) |
| 144 | Burnt Joker | R | 8 | Level up the first discarded hand type each round | E | Burnt Offering (BURNT_OFFERING) |
| 145 | Bootstraps | U | 7 | +2 Mult per 5g held | S | ★ Goblin Bank (GOBLIN_BANK) |

Mapping our terms to Balatro's:
- Scroll = Tarot
- Tome = Planet
- Relic = Spectral
- Celestial pack = Planet pack
- "Round" = blind

## Waves

Each wave gets its own plan, passes SDD, and ends on `main` after your OK.

| Wave | Content | Done when |
|---|---|---|
| 1 | Full engine and UI (instances, hooks, scoring order, retriggers, rules, Prob, copying, reorder, live tooltips, tally events, save v4) plus every **S** trinket (79, including 19 of the remaps) and Hearthstone (round-end gold) | Playable, sim green |
| 2 | Every **E** trinket (gold, discards, blind select, round end, shop, sell, hand size, Mr. Bones) | Playable, sim green |
| 3 | Every **D** trinket (card creation and change, consumables, boss disable and trigger), discovery totals, deck-unlock rescale, final balance pass | Playable, sim green |

## Discovery and deck unlocks

- `Profile.totalDiscoverable` is computed from the data counts instead of hard-coded.
- Deck-unlock thresholds become fixed fractions of the total. Today's 7/17/26/35 of 104 ≈ 6.7%/16.3%/25%/33.7%, rounded down.
- Unlocks stay persistent and grandfathered.

## Balance

- `tools/sim` must run every trinket. The bot buys by a simple value heuristic, and its rules are left to the builder.
- After each wave, no deck should be below 8% or above 45% wins over 200 runs at the current curve.
- Keep the existing targets unless a wave pushes rates out of that band. **[Call]**

## Calls made after the builder check

All of these are [Call] decisions mirroring Balatro. Where they conflict with the sections above, they take precedence.

1. **Scoring stays pure.**
   - `Scoring.score` works on scratch copies of the trinket instances. Update hooks change those copies, so a scaling trinket's new value counts in the hand that triggered it.
   - It returns `result.trinketsAfter` plus a list of side effects: `levelHand`, `createCard`, `createConsumable`, `destroyTrinket{uid}`, `destroyCard`, `gold`. Only `Run.play` applies them.
   - The bot's speculative scoring and the tests never change run state.
   - `Cards.isFace(card, rules)` and `Cards.hasSuit(card, suit, rules)` take an optional rules argument for Pareidolia and Smeared.
2. **Copying follows Balatro's `context.blueprint`.**
   - Every hook receives `isCopy`. Effects, including gold, creation and round-end payouts, fire for copies.
   - Scaling and state changes happen only when `not isCopy`.
   - Each def has `copyable` (default true). It's false for the rule trinkets and for:
     - Juggler, Drunkard, Turtle Bean, Troubadour, Merry Andy and Stuntman;
     - Egg and Gift Card;
     - Mr. Bones, Invisible, Luchador, Credit Card, Chaos, Showman, Astronomer and To the Moon;
     - any others Balatro marks incompatible (builder flags differences).
3. **Probability.**
   - Each Oops! All 6s doubles the chance, so the multiplier is 2^n.
   - `Prob.roll` always consumes exactly one RNG draw, even at 100%, so runs stay deterministic.
   - This covers Gros Michel and Cavendish too.
4. **To the Moon** raises gold per interest unit by 1 per copy. The cap still limits the number of units (floor(gold/5) capped), so one copy doubles the maximum.
5. **Hands, discards and hand size from trinkets are derived** from owned trinkets, like vouchers.
   - `Deck.handSize`, `Run.blindHands` and `Run.blindDiscards` include them.
   - Buying or selling mid-round changes the current round immediately (hand size, and remaining hands and discards), clamped as before.
   - Turtle Bean and Troubadour decay is held in `state`.
   - Burglar runs after `startBlind` sets hands and discards.
6. **Selling outside the shop.**
   - Trinkets and consumables can be sold during a blind, except while a hand is tallying. The trinket row's sell mode is available in play.
   - Campfire counts every trinket and consumable sold.
   - `sellBonus` applies to consumables too (Gift Card).
7. **HandEval is rule-aware (wave 1).**
   - Four Fingers lets 4-card straights and flushes form from 4 or 5 played cards. Only the cards forming the hand score, except under Splash.
   - Shortcut allows one-rank gaps, with A-low wheels still valid.
   - Smeared merges suits for flushes and for suit checks.
   - Existing HandEval tests are updated where the rules change results.
8. **Order within one trinket:** edition pre (Foil, Holo), then its effect, then Baseball Card's ×1.5 if it's Uncommon (once per Baseball or Baseball copy, wherever it sits), then edition post (Poly).
9. **Stable ids.**
   - Each instance gets `uid` from `run.nextTrinketUid`.
   - Scoring events name `uid` as well as `slot`.
   - Destruction and creation apply after scoring and animate when the tally ends; then the row re-renders.
10. **One constructor.**
    - `Trinkets.create(run, id, ed, paid)` builds every instance: shop, Buffoon packs, Riff-Raff, Relics (Judgement, Wraith, Soul), Ankh copies and Invisible duplicates.
    - `inPool` applies to every random source, but not to duplicating an owned trinket.
11. **Wave contents.**
    - Wave 1 brings the hooks its trinkets need: round-end gold, hand levelling and trinket destruction.
    - Rule switches whose trinkets are in later waves are wired in those waves.
12. **Remaps accepted.**
    - The 20 remapped trinkets take Balatro's rarity, cost and effect, and a run in progress uses the new effects after the update.
    - Per-instance counters (Loyalty Card and others) start fresh.
13. **Small ones.**
    - Raised Fist uses nominal value.
    - Wild cards satisfy any suit and, for Flower Pot and Seeing Double, are assigned to the missing suits first (Balatro order).
    - `Deck.copy` keeps `bonusChips`, enhancement, edition and seal.

## Constraints

Same as before:
- Lua 5.1.
- Core and Data free of WoW API calls.
- All randomness through run.rng (and `Prob`).
- Plain-data saves, with a version bump and migration (no invalidation).
- Mouse only.
- Retail plus Forever, with optional APIs feature-guarded.
- Never the global MouseIsOver.
- Theme helpers for all new UI.
- Icons: `Interface\\Icons\\*` paths that exist in the client. A missing icon shows the question-mark icon, so the builder checks names against known icons.

## Left to the builder

- Module layout. Suggested: `Core/TrinketEngine.lua`, `Core/Prob.lua`, `Core/TrinketRules.lua`, and splitting `Data/Trinkets*.lua` by wave.
- Exact popup wording.
- Icon choice.
- Sim bot heuristics.

## Notes carried from wave 1 (for the wave 2 and 3 plans)

- **Round-end hooks need a removal channel.** Gros Michel, Cavendish and Popcorn destroy themselves at round end. `onRoundEnd` needs a `destroySelf` return or deferred removal, because removing from `run.trinkets` inside `TrinketEngine.each` would shift slots mid-loop.
- **Updates before payouts.** All round-end state updates must run before any round-end payouts, as in Balatro, so copies and scaling payers such as Rocket pay consistently.
- **Card mutations go through the side-effect list.** Hiker, Vampire and Midas Mask must return a `changeCard` side effect from `Scoring.score`, never mutate cards in place. The bot scores speculatively, so in-place changes would leak.
- **Round-end payout trinkets are not copyable** (Balatro): Golden Joker/Hearthstone, Cloud 9, Rocket, Satellite and Delayed Gratification. **Stuntman (Leeroy Jenkins) IS copyable** (its chips copy; its hand size never does), which corrects the call 2 list. **Trading Card (Trading Post)** is not copyable.
- **Small parity items deferred from wave 1:**
  - Ancient Joker should exclude the current suit when it re-rolls.
  - Loyalty's status should read "5 remaining" / "Active!".
  - Raised Fist should compare by rank.
  - The Scroll of Chance, Glass and Lucky texts should show the effective odds under Loaded Dice.
- **Selling during a blind** (call 6) and **derived hand size** (call 5) land in wave 2.

## Notes carried from wave 2 (for the wave 3 plan)

- Blind-select hooks now fire **before** the first hand is drawn, as in Balatro. Marble Joker's Stone card can therefore be drawn in the same round.
- `UI/ConsumableRow.lua` `busy()` should include `ns.UI.Lifecycle.IsBusy()`. Today a second consumable sale during a drain is only a visual glitch.
- `Run.play` wraps the scoring commit in `Run.withMods`. If a scoring hook ever creates a trinket that raises hand size, the refill would run before `removeSelected` and reorder the hand. Move the hand removal before the settle if wave 3 adds such a trinket.
- Card mutations (Hiker, Vampire, Midas Mask) still need a `changeCard` side effect, never in-place changes.
- Score targets are now `300, 700, 1400, 2800, 5000, 8000, 11500, 16000`. Re-run the sim band check after wave 3.
