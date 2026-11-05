local _, ns = ...

local Hands = {}

Hands.order = {
  "HIGH_CARD", "PAIR", "TWO_PAIR", "THREE_KIND", "STRAIGHT",
  "FLUSH", "FULL_HOUSE", "FOUR_KIND", "STRAIGHT_FLUSH",
}

Hands.def = {
  HIGH_CARD = { name = "High Card", chips = 5, mult = 1, lvlChips = 10, lvlMult = 1 },
  PAIR = { name = "Pair", chips = 10, mult = 2, lvlChips = 15, lvlMult = 1 },
  TWO_PAIR = { name = "Two Pair", chips = 20, mult = 2, lvlChips = 20, lvlMult = 1 },
  THREE_KIND = { name = "Three of a Kind", chips = 30, mult = 3, lvlChips = 20, lvlMult = 2 },
  STRAIGHT = { name = "Straight", chips = 30, mult = 4, lvlChips = 30, lvlMult = 3 },
  FLUSH = { name = "Flush", chips = 35, mult = 4, lvlChips = 15, lvlMult = 2 },
  FULL_HOUSE = { name = "Full House", chips = 40, mult = 4, lvlChips = 25, lvlMult = 2 },
  FOUR_KIND = { name = "Four of a Kind", chips = 60, mult = 7, lvlChips = 30, lvlMult = 3 },
  STRAIGHT_FLUSH = { name = "Straight Flush", chips = 100, mult = 8, lvlChips = 40, lvlMult = 4 },
}

function Hands.base(id, level)
  local def = Hands.def[id]
  return def.chips + (level - 1) * def.lvlChips, def.mult + (level - 1) * def.lvlMult
end

ns.Hands = Hands
