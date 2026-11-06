local _, ns = ...

local Decks = {}

Decks.order = { "ROGUE", "WARRIOR", "GOBLIN", "MONK", "WARLOCK" }

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
    unlock = { discovered = 7 },
  },
  GOBLIN = {
    id = "GOBLIN", name = "Goblin Deck", hands = 4, discards = 3, gold = 14,
    desc = "Start with +$10", flavour = "Time is money, friend.",
    unlock = { discovered = 17 },
  },
  MONK = {
    id = "MONK", name = "Monk Deck", hands = 4, discards = 3, gold = 4,
    noInterest = true, goldPerHand = 2, goldPerDiscard = 1,
    desc = "No interest. +$2 per unused hand and +$1 per unused discard at the end of each round",
    flavour = "Patience fills the cup in Pandaria.", unlock = { discovered = 26 },
  },
  WARLOCK = {
    id = "WARLOCK", name = "Warlock Deck", hands = 3, discards = 3, gold = 4,
    extraTrinketSlots = 1,
    desc = "+1 trinket slot, −1 hand every round", flavour = "Power always demands a sacrifice.",
    unlock = { discovered = 35 },
  },
}

ns.Decks = Decks
