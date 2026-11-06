# Changelog

All notable changes to Azeroth Ante. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
