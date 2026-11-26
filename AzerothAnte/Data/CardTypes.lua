local _, ns = ...

-- Enhancements, editions and seals. Names follow Balatro.
local CardTypes = {}

CardTypes.enh = {
  BONUS = { name = "Bonus", desc = "+30 chips when scored." },
  MULT = { name = "Mult", desc = "+4 mult when scored." },
  WILD = { name = "Wild", desc = "Counts as every suit." },
  GLASS = { name = "Glass", desc = "x2 mult when scored. {1} in 4 chance to be destroyed after scoring." },
  STEEL = { name = "Steel", desc = "x1.5 mult while held in hand." },
  STONE = { name = "Stone", desc = "+50 chips. No rank or suit. Always scores." },
  GOLD = { name = "Gold", desc = "3g if held in hand at end of round." },
  LUCKY = { name = "Lucky", desc = "When scored: {1} in 5 chance of +20 mult, {1} in 15 chance of 20g." },
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
CardTypes.AURA_WEIGHTS = { FOIL = 50, HOLO = 35, POLY = 15 }

local AURA_ORDER = { "FOIL", "HOLO", "POLY" }

-- Balatro's poll_edition: one roll against cumulative bands, rarest first. Negative's
-- band is 0.3% x mod; Polychrome, Holographic and Foil end at 0.6%, 2% and 4% x mod x
-- rate (Hone 2, Glow Up 4). Without Negative, Polychrome keeps its whole 0.6% band.
-- Standard pack cards use mod 2. Returns an edition id or nil.
function CardTypes.pollEdition(r, mod, rate, allowNegative)
  local x = ns.RNG.next(r)
  if allowNegative and x < 0.003 * mod then return "NEGATIVE" end
  if x < 0.006 * mod * rate then return "POLY" end
  if x < 0.02 * mod * rate then return "HOLO" end
  if x < 0.04 * mod * rate then return "FOIL" end
  return nil
end

-- A base-odds roll (trinkets and anything created outside the shop).
function CardTypes.rollEdition(r, allowNegative)
  return CardTypes.pollEdition(r, 1, 1, allowNegative)
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
