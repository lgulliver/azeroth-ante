local _, ns = ...

-- Stages 1-7 each draw a boss from pool (see Run.new); stage 8 draws one of FINALS. minStage is the
-- earliest stage a boss can appear, from the Balatro boss it plays as (absent means any).
-- onDraw(run, card, why) -> bool: true draws the card face down (why: "start", "play" or "discard").
-- A trinket may disable the boss (run.bossDisabled): read its rules through Run.activeBoss, not Bosses.def[Run.bossId].
-- debuff(card, rules, info) -> bool (rules: TrinketRules.set, so Smeared/Pareidolia count; info: the run or scoring ctx,
-- whose playedThisAnte is a set of card ids): a debuffed card scores no chips and no trinket effects.
-- handSize (number) is added to the hand size while the boss is active.
local Bosses = {}

Bosses.pool = {
  "HOGGER", "VANCLEEF", "ARUGAL", "MUTANUS", "HEROD", "RIVENDARE", "ONYXIA", "VAELASTRASZ",
  "MOROES", "THERMAPLUGG", "MOROGRIM", "SKERAM", "THREDD", "TARGORR", "PATCHWERK", "ARCHAEDAS",
}

Bosses.FINALS = { "RAGNAROS", "CTHUN", "YOGG", "XAVIUS", "KELTHUZAD" }

local finalSet = {}
for _, id in ipairs(Bosses.FINALS) do finalSet[id] = true end

function Bosses.isFinal(id) return finalSet[id] == true end

Bosses.def = {
  HOGGER = {
    id = "HOGGER", name = "Hogger", targetMult = 2, minStage = 4, -- The Plant
    desc = "Face cards are debuffed.",
    debuff = function(card, rules) return ns.Cards.isFace(card, rules) and true or false end,
  },
  VANCLEEF = {
    id = "VANCLEEF", name = "Edwin VanCleef", targetMult = 2, minStage = 1, -- The Goad
    desc = "Spades are debuffed.",
    debuff = function(card, rules) return ns.Cards.hasSuit(card, "S", rules) end,
  },
  ARUGAL = {
    id = "ARUGAL", name = "Archmage Arugal", targetMult = 2, minStage = 1, -- The Head
    desc = "Hearts are debuffed.",
    debuff = function(card, rules) return ns.Cards.hasSuit(card, "H", rules) end,
  },
  VAELASTRASZ = {
    id = "VAELASTRASZ", name = "Vaelastrasz the Corrupt", targetMult = 2, minStage = 1, -- The Window
    desc = "Diamonds are debuffed.",
    debuff = function(card, rules) return ns.Cards.hasSuit(card, "D", rules) end,
  },
  MUTANUS = {
    id = "MUTANUS", name = "Mutanus the Devourer", targetMult = 2, minStage = 2, -- The Water
    desc = "No discards this round.",
    discards = 0,
  },
  HEROD = {
    id = "HEROD", name = "Herod", targetMult = 2, minStage = 1, -- The Psychic
    desc = "You must play exactly 5 cards.",
    mustPlay = 5,
  },
  RIVENDARE = {
    id = "RIVENDARE", name = "Baron Rivendare", targetMult = 2, minStage = 2, -- The Flint
    desc = "Base chips and mult of every hand are halved.",
    halveBase = true,
  },
  ONYXIA = {
    id = "ONYXIA", name = "Onyxia", targetMult = 1, minStage = 2, -- The Needle
    desc = "One hand only, and a lower target.",
    hands = 1,
  },
  MOROES = {
    id = "MOROES", name = "Moroes", targetMult = 2, minStage = 2, -- The House
    desc = "The first hand is drawn face down.",
    onDraw = function(run, _, why) return why == "start" and run.handsPlayedRound == 0 end,
  },
  THERMAPLUGG = {
    id = "THERMAPLUGG", name = "Mekgineer Thermaplugg", targetMult = 2, minStage = 2, -- The Wheel
    desc = "1 in 7 cards is drawn face down.",
    onDraw = function(run) return ns.RNG.next(run.rng) < 1 / 7 end,
  },
  MOROGRIM = {
    id = "MOROGRIM", name = "Morogrim Tidewalker", targetMult = 2, minStage = 2, -- The Fish
    desc = "Cards drawn after each hand are face down.",
    onDraw = function(_, _, why) return why == "play" end,
  },
  SKERAM = {
    id = "SKERAM", name = "The Prophet Skeram", targetMult = 2, minStage = 2, -- The Mark
    desc = "Face cards are drawn face down.",
    onDraw = function(run, card)
      return ns.Cards.isFace(card, ns.TrinketRules.set(run.trinkets)) and true or false
    end,
  },
  THREDD = {
    id = "THREDD", name = "Bazil Thredd", targetMult = 2, minStage = 1, -- The Club
    desc = "Clubs are debuffed.",
    debuff = function(card, rules) return ns.Cards.hasSuit(card, "C", rules) end,
  },
  TARGORR = {
    id = "TARGORR", name = "Targorr the Dread", targetMult = 2, minStage = 1, -- The Manacle
    desc = "-1 hand size.",
    handSize = -1,
  },
  PATCHWERK = {
    id = "PATCHWERK", name = "Patchwerk", targetMult = 4, minStage = 2, -- The Wall
    desc = "A very high target.",
  },
  ARCHAEDAS = {
    id = "ARCHAEDAS", name = "Archaedas", targetMult = 2, minStage = 1, -- The Pillar
    desc = "Cards played earlier this ante are debuffed.",
    debuff = function(card, _, info)
      return info and info.playedThisAnte and info.playedThisAnte[card.id] and true or false
    end,
  },
  RAGNAROS = {
    id = "RAGNAROS", name = "Ragnaros the Firelord", targetMult = 2,
    desc = "The final boss of the run.",
  },
  CTHUN = {
    id = "CTHUN", name = "C'Thun", targetMult = 6, -- Violet Vessel
    desc = "A colossal target.",
  },
  YOGG = {
    id = "YOGG", name = "Yogg-Saron", targetMult = 2, -- Amber Acorn
    desc = "Flips your trinkets face down and shuffles them.",
  },
  XAVIUS = {
    id = "XAVIUS", name = "Xavius", targetMult = 2, -- Verdant Leaf
    desc = "All cards are debuffed until you sell a trinket.",
  },
  KELTHUZAD = {
    id = "KELTHUZAD", name = "Kel'Thuzad", targetMult = 2, -- Cerulean Bell
    desc = "One card is always forced into your selection.",
  },
}

ns.Bosses = Bosses
