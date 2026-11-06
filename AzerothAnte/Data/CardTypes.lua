local _, ns = ...

-- Enhancements, editions and seals. Names follow Balatro.
local CardTypes = {}

CardTypes.enh = {
  BONUS = { name = "Bonus", desc = "+30 chips when scored." },
  MULT = { name = "Mult", desc = "+4 mult when scored." },
  WILD = { name = "Wild", desc = "Counts as every suit." },
  GLASS = { name = "Glass", desc = "x2 mult when scored. 1 in 4 chance to be destroyed after scoring." },
  STEEL = { name = "Steel", desc = "x1.5 mult while held in hand." },
  STONE = { name = "Stone", desc = "+50 chips. No rank or suit. Always scores." },
  GOLD = { name = "Gold", desc = "3g if held in hand at end of round." },
  LUCKY = { name = "Lucky", desc = "When scored: 1 in 5 chance of +20 mult, 1 in 15 chance of 20g." },
}

CardTypes.ed = {
  FOIL = { name = "Foil", desc = "+50 chips." },
  HOLO = { name = "Holographic", desc = "+10 mult." },
  POLY = { name = "Polychrome", desc = "x1.5 mult." },
  NEGATIVE = { name = "Negative",
    desc = "Trinket: +1 trinket slot. Card: +1 hand size while it is in the deck." },
}

CardTypes.seal = {
  GOLD = { name = "Gold Seal", desc = "3g when this card is played and scores." },
  RED = { name = "Red Seal", desc = "Retrigger this card once." },
  BLUE = { name = "Blue Seal",
    desc = "If held in hand at end of round, create the Tome for the final hand played (needs a free slot)." },
  PURPLE = { name = "Purple Seal", desc = "When discarded, create a random Scroll (needs a free slot)." },
}

CardTypes.ED_COST = { FOIL = 2, HOLO = 3, POLY = 5, NEGATIVE = 5 }
CardTypes.ED_ODDS = { FOIL = 0.02, HOLO = 0.014, POLY = 0.003, NEGATIVE = 0.003 }
CardTypes.AURA_WEIGHTS = { FOIL = 50, HOLO = 35, POLY = 15 }

local ROLL_ORDER = { "NEGATIVE", "POLY", "HOLO", "FOIL" }
local AURA_ORDER = { "FOIL", "HOLO", "POLY" }

-- One roll; rarest bands first. Returns an edition id or nil.
function CardTypes.rollEdition(r, allowNegative)
  local x = ns.RNG.next(r)
  local edge = 0
  for _, id in ipairs(ROLL_ORDER) do
    if id ~= "NEGATIVE" or allowNegative then
      edge = edge + CardTypes.ED_ODDS[id]
      if x < edge then return id end
    end
  end
  return nil
end

-- Weighted pick among Foil, Holographic and Polychrome.
function CardTypes.rollAura(r)
  local total = 0
  for _, id in ipairs(AURA_ORDER) do total = total + CardTypes.AURA_WEIGHTS[id] end
  local x = ns.RNG.next(r) * total
  local edge = 0
  for _, id in ipairs(AURA_ORDER) do
    edge = edge + CardTypes.AURA_WEIGHTS[id]
    if x < edge then return id end
  end
  return AURA_ORDER[#AURA_ORDER]
end

ns.CardTypes = CardTypes
