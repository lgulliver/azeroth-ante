local _, ns = ...

local Decks = {}

-- unlock.fraction is the share of all discoverable items; Profile.unlockThreshold turns it into a count.
-- In Balatro's order: Red, Blue, Yellow, Green, Black, Magic, Nebula, Ghost, Abandoned, Checkered,
-- Zodiac, Painted, Anaglyph, Plasma, Erratic.
-- Optional rule fields: vouchers / consumables (owned from the start), consumableSlots and
-- extraTrinketSlots (deltas), handSize (delta), cards ("NO_FACES" | "CHECKERED" | "ERRATIC", see
-- Deck.new), relicWeight (Relics in the shop), bossTag (a tag after each boss), balance (Chips and
-- Mult are averaged before the total) and targetMult (blind targets).
Decks.order = { "ROGUE", "WARRIOR", "GOBLIN", "MONK", "WARLOCK", "MAGE", "DRAENEI", "DEATHKNIGHT",
  "FORSAKEN", "ALLIANCE", "TRADEPRINCE", "HUNTER", "EVOKER", "DRUID", "GNOME" }

Decks.def = {
  ADVENTURER = {
    id = "ADVENTURER", name = "Adventurer Deck", hands = 4, discards = 3, gold = 4,
    desc = "The balanced starting deck.", flavour = "Every hero starts somewhere.",
  },
  ROGUE = {
    id = "ROGUE", name = "Rogue Deck", hands = 4, discards = 4, gold = 4,
    desc = "+1 discard every round", flavour = "Another trick up a leather sleeve.",
  },
  WARRIOR = {
    id = "WARRIOR", name = "Warrior Deck", hands = 5, discards = 3, gold = 4,
    desc = "+1 hand every round", flavour = "For the Horde, one more swing.",
    unlock = { fraction = 0.067 },
  },
  GOBLIN = {
    id = "GOBLIN", name = "Goblin Deck", hands = 4, discards = 3, gold = 14,
    desc = "Start with +10g", flavour = "Time is money, friend.",
    unlock = { fraction = 0.163 },
  },
  MONK = {
    id = "MONK", name = "Monk Deck", hands = 4, discards = 3, gold = 4,
    noInterest = true, goldPerHand = 2, goldPerDiscard = 1,
    desc = "No interest. +2g per unused hand and +1g per unused discard at the end of each round",
    flavour = "Patience fills the cup in Pandaria.", unlock = { fraction = 0.25 },
  },
  WARLOCK = {
    id = "WARLOCK", name = "Warlock Deck", hands = 3, discards = 3, gold = 4,
    extraTrinketSlots = 1,
    desc = "+1 trinket slot, -1 hand every round", flavour = "Power always demands a sacrifice.",
    unlock = { fraction = 0.337 },
  },
  MAGE = {
    id = "MAGE", name = "Mage Deck", hands = 4, discards = 3, gold = 4,
    vouchers = { "CRYSTAL_BALL" }, consumables = { { kind = "scroll", id = "ECHOES" }, { kind = "scroll", id = "ECHOES" } },
    desc = "Start with Dalaran Crystal Ball and 2 Scrolls of Echoes", flavour = "Dalaran's finest, at your service.",
    unlock = { fraction = 0.38 },
  },
  DRAENEI = {
    id = "DRAENEI", name = "Draenei Deck", hands = 4, discards = 3, gold = 4,
    vouchers = { "TELESCOPE" }, consumableSlots = -1,
    desc = "Start with Titan Orrery. -1 consumable slot", flavour = "The stars remember Argus.",
    unlock = { fraction = 0.42 },
  },
  DEATHKNIGHT = {
    id = "DEATHKNIGHT", name = "Death Knight Deck", hands = 4, discards = 3, gold = 4,
    relicWeight = 2, consumables = { { kind = "relic", id = "HEXES" } },
    desc = "Relics may appear in the shop. Start with a Relic of Hexes", flavour = "Rise, and serve once more.",
    unlock = { fraction = 0.46 },
  },
  FORSAKEN = {
    id = "FORSAKEN", name = "Forsaken Deck", hands = 4, discards = 3, gold = 4, cards = "NO_FACES",
    desc = "Start with no face cards", flavour = "We are the Forsaken. We need no kings.",
    unlock = { fraction = 0.5 },
  },
  ALLIANCE = {
    id = "ALLIANCE", name = "Alliance Deck", hands = 4, discards = 3, gold = 4, cards = "CHECKERED",
    desc = "Start with 26 Spades and 26 Hearts", flavour = "For the Alliance, shoulder to shoulder.",
    unlock = { fraction = 0.54 },
  },
  TRADEPRINCE = {
    id = "TRADEPRINCE", name = "Trade Prince Deck", hands = 4, discards = 3, gold = 4,
    vouchers = { "TAROT_MERCHANT", "PLANET_MERCHANT", "OVERSTOCK" },
    desc = "Start with Scribe's Stall, Karazhan Library Cart and Bulging Saddlebags",
    flavour = "Every market on Azeroth pays tribute.", unlock = { fraction = 0.58 },
  },
  HUNTER = {
    id = "HUNTER", name = "Hunter Deck", hands = 4, discards = 3, gold = 4, handSize = 2, extraTrinketSlots = -1,
    desc = "+2 hand size, -1 trinket slot", flavour = "A keen eye sees every card.",
    unlock = { fraction = 0.62 },
  },
  EVOKER = {
    id = "EVOKER", name = "Evoker Deck", hands = 4, discards = 3, gold = 4, bossTag = "DOUBLE",
    desc = "Gain a Bonus Roll after each boss", flavour = "Two heads, one breath.",
    unlock = { fraction = 0.66 },
  },
  DRUID = {
    id = "DRUID", name = "Balance Druid Deck", hands = 4, discards = 3, gold = 4, balance = true, targetMult = 2,
    desc = "Chips and Mult are balanced when scoring. Blind targets are doubled",
    flavour = "Sun and moon, in perfect measure.", unlock = { fraction = 0.7 },
  },
  GNOME = {
    id = "GNOME", name = "Gnome Deck", hands = 4, discards = 3, gold = 4, cards = "ERRATIC",
    desc = "Every card's rank and suit is random", flavour = "It worked in the simulations.",
    unlock = { fraction = 0.74 },
  },
}

ns.Decks = Decks
