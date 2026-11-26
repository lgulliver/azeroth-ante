local _, ns = ...

-- One Tome per hand type, named for a world of the Warcraft cosmos as Balatro names its
-- planets. A Tome id is its handId; its description names the hand it levels.
local Tomes = { order = {}, def = {} }
local WORLDS = {
  HIGH_CARD = "the Blue Child", PAIR = "the White Lady", TWO_PAIR = "Draenor", THREE_KIND = "Argus",
  STRAIGHT = "K'aresh", FLUSH = "Xoroth", FULL_HOUSE = "Azeroth", FOUR_KIND = "Mardum",
  STRAIGHT_FLUSH = "Niskara", FIVE_KIND = "Ny'alotha", FLUSH_HOUSE = "Oribos", FLUSH_FIVE = "the Emerald Dream",
}

for i, handId in ipairs(ns.Hands.order) do
  Tomes.order[i] = handId
  Tomes.def[handId] = {
    id = handId, handId = handId, name = "Tome of " .. WORLDS[handId],
  }
end

ns.Tomes = Tomes
