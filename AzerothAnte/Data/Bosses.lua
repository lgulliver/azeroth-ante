local _, ns = ...

-- Stages 1-7 each draw 7 distinct ids from pool. FINAL is stage 8.
-- debuff(card, rules) -> bool (rules: TrinketRules.set, so Smeared/Pareidolia count): a debuffed card scores no chips and no trinket effects.
local Bosses = {}

Bosses.pool = {
  "HOGGER", "VANCLEEF", "ARUGAL", "MUTANUS", "HEROD", "RIVENDARE", "ONYXIA", "VAELASTRASZ",
}

Bosses.FINAL = "RAGNAROS"

Bosses.def = {
  HOGGER = {
    id = "HOGGER", name = "Hogger", targetMult = 2,
    desc = "Face cards are debuffed.",
    debuff = function(card, rules) return ns.Cards.isFace(card, rules) and true or false end,
  },
  VANCLEEF = {
    id = "VANCLEEF", name = "Edwin VanCleef", targetMult = 2,
    desc = "Spades are debuffed.",
    debuff = function(card, rules) return ns.Cards.hasSuit(card, "S", rules) end,
  },
  ARUGAL = {
    id = "ARUGAL", name = "Archmage Arugal", targetMult = 2,
    desc = "Hearts are debuffed.",
    debuff = function(card, rules) return ns.Cards.hasSuit(card, "H", rules) end,
  },
  VAELASTRASZ = {
    id = "VAELASTRASZ", name = "Vaelastrasz the Corrupt", targetMult = 2,
    desc = "Diamonds are debuffed.",
    debuff = function(card, rules) return ns.Cards.hasSuit(card, "D", rules) end,
  },
  MUTANUS = {
    id = "MUTANUS", name = "Mutanus the Devourer", targetMult = 2,
    desc = "No discards this round.",
    discards = 0,
  },
  HEROD = {
    id = "HEROD", name = "Herod", targetMult = 2,
    desc = "You must play exactly 5 cards.",
    mustPlay = 5,
  },
  RIVENDARE = {
    id = "RIVENDARE", name = "Baron Rivendare", targetMult = 2,
    desc = "Base chips and mult of every hand are halved.",
    halveBase = true,
  },
  ONYXIA = {
    id = "ONYXIA", name = "Onyxia", targetMult = 1,
    desc = "One hand only, and a lower target.",
    hands = 1,
  },
  RAGNAROS = {
    id = "RAGNAROS", name = "Ragnaros the Firelord", targetMult = 2,
    desc = "The final boss of the run.",
  },
}

ns.Bosses = Bosses
