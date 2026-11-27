# Changelog

All notable changes to Azeroth Ante. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.8.0] - 2026-11-27

### Changed
- Packs, Tomes and many Scrolls, Relics, vouchers and trinkets have Warcraft names: Scribe's Satchel, Archivist's Crate, Darkmoon Card Bundle, Trinket Lockbox and Relic Cache (Large and Heavy sizes); Tomes are named for worlds such as Argus and Draenor; Netherweave Bag, Titan Orrery, Kezan Gold Bar, Windfury Weapon and more.
- Blind targets now follow Balatro's curve (300, 800, 2000, 5000, 11000, 20000, 35000, 50000), up from a flatter curve that topped out at 16000. Later antes need a built deck, so trinkets and new cards matter.
- The Relic of the Twisting Nether (Black Hole) and the Heart of Azeroth (The Soul) are hidden again, as in Balatro: never rolled at random, only a 0.3% chance per card in Archivist's Crates, Scribe's Satchels and Relic Caches (the Twisting Nether also in Scribe's Satchels with the Orb of the Kirin Tor). They were turning up about 18 times too often.
- Bosses respect Balatro's minimum antes (Hogger from ante 4; Mutanus, Rivendare and Onyxia from ante 2), and each ante draws among the least-seen bosses.
- Onyxia always leaves exactly one hand and Mutanus exactly no discards; extra-hand and extra-discard vouchers and trinkets no longer undo them.
- The first shop of a run always has a Trinket Lockbox.
- The shop no longer offers a Scroll or Tome you hold (unless you have Showman) or one another slot already shows.
- Shop playing cards cost 1g plus their edition; enhancements are free and shop cards never carry a seal. With Illusion, 40% are enhanced and 20% get an edition.
- Edition odds follow Balatro: Standard pack cards roll at double odds (about 8% instead of 4%), and Hone and Glow Up raise Polychrome correctly.
- Discounts round half down (10g at 25% off is 7g).
- Baron Rivendare rounds halved chips and mult up, like The Flint.
- Mirror Image also retriggers end-of-round held effects: Gold cards pay again and Blue seals make another Tome.
- Playing cards are 20% larger (96x134), so ranks, suits and court figures read better; a full hand overlaps slightly, as in Balatro.

### Added
- Fifteen new bosses, each playing as a Balatro boss with its rule, target and minimum ante: Captain Greenskin, Bazil Thredd, Targorr the Dread, Archaedas, Moroes, Patchwerk, Mekgineer Thermaplugg, Ras Frostwhisper, Morogrim Tidewalker, Gluth, The Prophet Skeram, Shade of Aran, Baron Revilgaz, Hakkar the Soulflayer and Gruul the Dragonkiller; and four new ante 8 finishers beside Ragnaros: C'Thun, Yogg-Saron, Xavius and Kel'Thuzad. Face-down cards show their back and flip when played.
- Gluth and Shade of Aran work like The Mouth and The Eye: a hand type they do not allow can still be played, but it scores nothing ("Not allowed!") and uses up the hand.
- Skip the small or big blind for its tag, shown under each blind. Skipping forgoes the reward and interest and goes straight to the next blind with no shop; the boss blind cannot be skipped. Twenty-four tags: free Uncommon, Rare, Negative, Foil, Holographic or Polychrome trinkets in the next shop, free gift packs that open on the blind screen (Scribe's Gift, Archivist's Gift, Darkmoon Card Gift, Lockbox Key, Relic Hunter's Gift), Goblin Investment (25g after the next boss), Vendor Restock (an extra voucher), Wanted Poster (a free boss reroll), Bonus Roll (copies the next tag), Flight Master's Whistle (5g per blind skipped), Auction House Flip (doubles your gold, up to +40g), Heirloom Dice, Algalon's Insight, Recruit-a-Friend and more.
- The ante 8 finishers each have their own rule: Ragnaros the Firelord disables one random trinket each hand, C'Thun has a ×6 target and no rule (disabled, it drops to the usual ×2, as Patchwerk does), Yogg-Saron flips your trinkets face down and shuffles them, Xavius debuffs every card until you sell a trinket, and Kel'Thuzad always forces one card into your selection.
- New painted card backs in the court-card style: a compass for the default deck, Ravenholdt daggers for Rogue, a Horde war banner for Warrior, coins and gears for Goblin, a jade lotus for Monk and a fel eye for Warlock.
- Jacks, Queens and Kings are double-ended court cards of Warcraft characters: Sir Finley, Azshara and King Mrgl-Mrgl on Spades; Arthas, Jaina and Varian on Hearts; Garrosh, Sylvanas and Durotan on Clubs; Gazlowe, Sassy Hardwrench and Gallywix on Diamonds, each framed like a real playing card on the card's own parchment. A Stone court card still shows no art.
- Five legendary trinkets, as Balatro's legendary jokers: Frostmourne (gains ×1 Mult per face card destroyed), Shalamayne (played Kings and Queens give ×2 Mult), Shadowmourne (gains ×1 Mult every 23 cards discarded), Ashbringer (disables every boss) and Dragonwrath (leaving the shop makes a Negative copy of a held consumable; a Negative consumable brings its own slot). They never appear in the shop or packs: the Heart of Azeroth now creates one.
- Darkmoon Fizz (sell for a free Bonus Roll) and Timewalking Badge (×0.25 Mult per blind skipped), completing the Balatro joker set at 150 trinkets.
- Stakes: Balatro's eight difficulty levels, chosen under the deck on the deck screen. Each adds to those below it: Red (no small blind reward), Green (faster-scaling targets), Black (Eternal trinkets that can't be sold or destroyed), Blue (-1 discard), Purple (faster still, 200,000 at ante 8), Orange (Perishable trinkets, debuffed after 5 rounds) and Gold (Rental trinkets: 1g to buy, -3g each round). Every deck starts on White; winning at a stake unlocks the next one for that deck.
- Ten more decks, completing Balatro's fifteen, each with its own painted back: Mage (Dalaran Crystal Ball and 2 Scrolls of Echoes), Draenei (Titan Orrery, one consumable slot fewer), Death Knight (Relics in the shop, start with a Relic of Hexes), Forsaken (no face cards), Alliance (26 Spades and 26 Hearts), Trade Prince (three shop vouchers), Hunter (+2 hand size, one trinket slot fewer), Evoker (a Bonus Roll after each boss), Balance Druid (Chips and Mult are balanced; targets doubled) and Gnome (random ranks and suits). They unlock in turn as you discover more items.

### Fixed
- A trinket Ragnaros disabled for the last hand no longer pays out or updates at the end of the round; it is back on for interest and the shop.
- Ragnaros never picks a Perishable trinket that has already perished, and no longer brings one back.
- Algalon's Insight picks its hand when it is rolled, and the blind screen's tooltip names it.
- Two Vendor Restocks in one shop give two extra vouchers: the second fills the extra tile once the first is bought.
- A hand Gluth or Shade of Aran does not allow still counts down trinkets such as Tigule's Ice Cream and Morning Glory Dew.
- Ashbringer disables a boss already in play however it arrives, not only from the Heart of Azeroth.

## [0.7.0] - 2026-11-09

### Added
- The window opens when you take a flight path and closes when you land. An "Open on flight paths" option (on by default) under Options > AddOns > Azeroth Ante turns it off.

## [0.6.2] - 2026-11-06

### Changed
- Supports Retail 12.1.7 (interface 120107), so the addon is no longer marked out of date on the current Retail patch.

## [0.6.1] - 2026-11-06

### Added
- Releases now ship for Retail as well as Forever: a plain `.zip` asset for Retail alongside the `-forever.zip`, and the CurseForge file is tagged with the Retail patches from the TOC.

## [0.6.0] - 2026-11-06

First public release.

### Added
- The full trinket set: 143 trinkets, every non-legendary Balatro joker except the two that need skip tags.
- Trinkets that change cards (Gilded Mask, Vampiric Embrace, Pilgrim's Bounty) and create them (Gnomish Cloning Device, Letter of Commendation, Stoneform), with card flashes and cards flying into the hand.
- Trinkets that create Scrolls and Relics, popping into the consumable row.
- Gladiator's Medallion: sell it during a boss blind to disable the boss.
- Deck- and usage-based trinkets (Ironforge Anvil, Earthen Ring, Master Riding, Sandstorm, Seer, Mage Tower, Glass Cannon, Fortune Cat).
- Addon icon in the addon list, and the same art as the README logo.
- CI: luacheck lint, the unit, UI smoke (30 seeds), syntax and media test suites, and a tag-driven release workflow that builds the `-forever` zip, publishes a GitHub release and uploads to CurseForge. Wago imports releases through a GitHub webhook.
- MIT licence, contributing guide, issue and pull request templates.

### Changed
- Save version 6; older saves migrate.

### Fixed
- The title-bar Abandon Run button now takes clicks (the window's drag handle was covering it).

## [0.5.0] - 2026-11-06

### Added
- 37 economy and lifecycle trinkets (blind select, discards, round end, boss defeated, shop rerolls, pack skips, selling).
- Sell trinkets during a blind.
- Trinkets that change hands, discards and hand size, live.
- Soulstone saves a lost blind; Credit Card debt, Chaos free rerolls, Astronomer and Showman.

### Changed
- Score targets eased to 300 to 16000.
- Save version 5.

## [0.4.0] - 2026-11-06

### Added
- Trinket engine: per-trinket state, retriggers, rule trinkets (Four Fingers, Shortcut, Smeared, Splash, Pareidolia), shared probability rolls, Blueprint and Brainstorm copying.
- 80 scoring trinkets; the original 20 take their Balatro equivalents' effects.
- Drag trinkets to reorder them; live tooltips; per-trinket round-end gold lines.
- Deck unlock thresholds scale with the size of the collection.

### Changed
- Save version 4.

## [0.3.0] - 2026-11-06

### Added
- 32 vouchers, bought in the shop.
- 16 addon-internal achievements that unlock the upgraded vouchers.
- Deck unlocks (Warrior, Goblin, Monk, Warlock) with a deck-select carousel.
- Polished WoW window theme, Balatro-style blind select, title-bar Abandon Run.

## [0.2.0] - 2026-11-05

### Added
- Deck building: enhancements, editions and seals; Scrolls, Tomes and Relics; booster packs; a persistent deck.
- Secret hands; Wild and Stone cards.

## [0.1.0] - 2026-11-05

First release.

### Added
- A Balatro-style poker roguelike with a World of Warcraft skin, for Retail and WoW Forever.
- Opens while you wait in a queue and hides when the queue pops or combat starts. `/ante` toggles the window.
- Eight stages of three blinds with dungeon and raid bosses, a shop and trinkets.
- Save and resume across sessions.
