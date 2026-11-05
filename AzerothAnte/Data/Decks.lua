local _, ns = ...

local Decks = {}

Decks.order = { "ADVENTURER", "WARRIOR", "ROGUE", "GOBLIN" }

Decks.def = {
  ADVENTURER = {
    id = "ADVENTURER", name = "Adventurer", hands = 4, discards = 3, gold = 4,
    desc = "The balanced starting deck.",
  },
  WARRIOR = {
    id = "WARRIOR", name = "Warrior", hands = 5, discards = 3, gold = 4,
    desc = "An extra hand each round.",
  },
  ROGUE = {
    id = "ROGUE", name = "Rogue", hands = 4, discards = 4, gold = 4,
    desc = "An extra discard each round.",
  },
  GOBLIN = {
    id = "GOBLIN", name = "Goblin", hands = 4, discards = 3, gold = 10,
    desc = "Starts with extra gold.",
  },
}

ns.Decks = Decks
