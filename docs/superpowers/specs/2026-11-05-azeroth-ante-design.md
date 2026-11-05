# Azeroth Ante: Design

Date: 2026-11-05. Status: draft for approval.

Legend: **[Liam]** = decided by Liam. **[Call]** = my call, not yet confirmed. Change any of them freely.

## Intent

A World of Warcraft addon that gives the player something to play while they wait in a dungeon (or other) queue. It is a clone of Balatro, a poker-based roguelike where you score chips × mult against a target, buy modifiers between rounds and chain through boss fights, with a WoW skin. [Liam]

The reason it exists: queue waits are dead time. A run is too long for one wait, so it must be resumable across several. [Liam]

## Goals

1. **A complete run, start to finish.** This is the v1 priority. [Liam] The player picks a starting deck, plays blinds, shops, fights bosses, and wins or loses.
2. **Smooth, not clunky.** It should feel as smooth as Balatro. [Liam] See "Feel" below.
3. **Runs span several queues.** The game saves between rounds and resumes instantly from the last saved round. [Liam]
4. **Mouse only.** No keyboard shortcuts. [Liam]
5. **Self-contained and free.** It runs inside WoW's Lua addon sandbox, with no external network or file access. Saved state uses SavedVariables. [Call] Free and open source, to stay within Blizzard's addon policy. [Call]

## Non-goals (v1)

- Unlocks or meta-progression between runs. [Call]
- Extra card types (tarot-style consumables, enhanced cards), editions (foil, holographic) beyond a cheap overlay, and vouchers. [Call]
- Multiplayer, or playing against party members. [Call]
- Keyboard input. [Liam]
- Shader-level effects (CRT warp, screen distortion). WoW's UI can't do them. [Call]

## Anti-goals

- **Clunky interaction.** This is the one Liam named as the thing that would make it a failure. [Liam] Stuck selections, laggy hover, instant (unanimated) deals and score tallies, or unclear click targets all count.
- Anything that automates gameplay or touches real game state. The addon only reads queue events and never affects the player's character. [Call]

## The game

**Poker is real poker with a WoW skin.** [Liam] Standard hands (high card up to straight flush, five of a kind and flush house as in Balatro), each with base chips and mult. Hands level up through shop upgrades. [Call]

- **Deck:** 52 cards, standard suits and ranks. Suits get four custom icons with a WoW flavour. [Call] Ranks use normal numerals.
- **Round (blind):** reach a target score within a fixed number of hands and discards. Play up to five cards per hand, discard and redraw. [Call, modelled on Balatro]
- **Run structure:** 8 stages of 3 blinds, ending in a boss blind. Fail a blind and the run ends. [Call, modelled on Balatro] Bosses are dungeon or raid bosses, with a modifier each. [Call]
- **Trinkets (jokers):** passive modifiers shown in a row of slots, with WoW-style procs. About 15–20 in v1. [Call]
- **Shop:** a vendor between rounds. Buy trinkets and hand upgrades with gold. [Call]
- **Starting decks:** a few simple variants. [Call]
- **Naming:** Azeroth Ante. [Liam] The Blizzard policy on using the "Azeroth" name has not been checked yet. See open items.

## Screen

Layout A, Balatro-faithful. [Liam]

- Draggable, resizable WoW frame.
- **Left sidebar:** boss, target score, current score, chips × mult, hands left, discards left, gold.
- **Top row:** trinket slots.
- **Middle:** play area.
- **Bottom row:** the 8-card hand.

Look is WoW's built-in frames and icons for trinkets and borders, plus the custom suit textures. [Call]

## Feel

Smoothness is the main quality bar. [Liam] What I'd build to get there: [Call]

- Cards lift on hover. Select with a click, deselect with a click. No stuck states.
- Dealing, discarding and sorting are animated.
- The score tally counts up in steps: each card's chips tick in, the mult pops, the total lands. Trinkets that fire get a short pulse.
- Light card tilt and idle sway if testing shows they hold up.
- Honest limit: WoW can do animation, scaling, rotation and fades, not shaders. Foil-style effects are faked with overlays.

## Queue behaviour

Proposed, not yet confirmed by Liam: [Call]

- The window opens when the player joins a queue.
- It pauses on the ready check.
- It plays a sound when the queue pops.
- It autosaves between rounds, and the player can also open it manually at any time.

## Constraints

- WoW addon: Lua, a `.toc` file, standard frames and animation groups. SavedVariables for saves.
- Addon-owned art ships as TGA or BLP textures with power-of-two dimensions. Placeholder suit art is made by me and must be easy to swap. [Liam: "you can do it for now"]
- No external network or file access.

## Repository

`/home/lgulliver/repos/azeroth-ante`, git on `main`. Addon source in `AzerothAnte/` (`Core/`, `UI/`, `Data/`, `Media/`). Specs in `docs/superpowers/specs/`. [Liam]

## Calls made after review

All [Call]. Each one is easy to reverse.

- **Fixed deck in v1.** 52 cards, 8-card hand (Balatro's default). The shop sells trinkets and hand upgrades only, with no card add, remove or edit. The save stores the deck order, RNG state and round state, with no per-card state. "Starting deck variants" vary only hands, discards and starting gold, never the card set.
- **Pacing.** Target about 3 minutes per blind and a full run of roughly 60–75 minutes, spread over several queues. Autosave at round boundaries and again after each hand, so a closed window loses at most the hand in progress. A queue wait can end mid-round, so resume lands on a clean state.
- **Queue handling.** Hook dungeon, raid-finder, scenario and Delve queues (LFG events) and PvP queues. On a pop, the window pauses with a visible overlay and a sound. On accept it hides, and it stays hidden until the player opens it again. It hides on entering combat and can be opened manually any time. The game uses no secure frames, so combat taint is not a concern, but the window still hides in combat.
- **Seeded RNG.** Shuffles, draws and shop rolls come from a seeded RNG whose state is saved, so reloading can't reroll a bad draw.
- **Art.** Built-in Blizzard icons are referenced by path (`Interface\Icons\...`) and never bundled. Only our own suit and card-back textures ship in the addon.
- **Performance.** Prefer animation groups for fixed motions, and keep any `OnUpdate` tweening to the cards that are moving. Do no per-frame work while the window is idle or hidden. No numeric frame budget in v1, but the builder should measure addon CPU and keep it modest.

## Left to the builder

- Lua architecture, file layout and module boundaries.
- Exact scoring formulas, hand levels, blind targets and economy numbers. Aim for it to be winnable and to have a real difficulty curve.
- The actual list of 15–20 trinkets, boss modifiers and starting decks.
- Animation implementation (animation groups vs `OnUpdate` tweening).
- Exact queue events to hook, and the current Interface version number.

## Open items

- **Game version.** Targets Retail and WoW Forever. [Liam] Per web search (not verified in-client), Forever uses the Mainline API with Midnight's addon restrictions, and installs to `_forever_/Interface/AddOns`. So this should be one codebase with both Interface numbers in the `.toc`. The builder must read the real numbers from each client (`/dump select(4, GetBuildInfo())`), since the search didn't find Forever's. This addon touches no combat data, so the restrictions shouldn't matter.
- **Blizzard policy check** on the name and on shipping Blizzard icons. Not yet done.
- **Save granularity.** I'm assuming autosave at round boundaries, so a mid-round close loses only that round's current hand. [Call]
