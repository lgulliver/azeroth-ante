local _, ns = ...

local Vouchers = ns.Vouchers

function Vouchers.owns(run, id)
  return run.vouchers[id] == true
end

local function count(run, id)
  return Vouchers.owns(run, id) and 1 or 0
end

local function tierValue(run, base, upgrade, initial, first, second)
  if Vouchers.owns(run, upgrade) then return second end
  if Vouchers.owns(run, base) then return first end
  return initial
end

function Vouchers.shopCardSlots(run)
  return 2 + count(run, "OVERSTOCK") + count(run, "OVERSTOCK_PLUS")
end

function Vouchers.discount(run)
  return tierValue(run, "CLEARANCE_SALE", "LIQUIDATION", 0, 0.25, 0.5)
end

function Vouchers.price(run, cost)
  return math.max(1, math.floor(cost * (1 - Vouchers.discount(run)) + 0.5))
end

function Vouchers.rerollDelta(run)
  return 2 * (count(run, "REROLL_SURPLUS") + count(run, "REROLL_GLUT"))
end

function Vouchers.editionMult(run)
  return tierValue(run, "HONE", "GLOW_UP", 1, 2, 4)
end

function Vouchers.scrollWeight(run)
  return tierValue(run, "TAROT_MERCHANT", "TAROT_TYCOON", 4, 9.6, 32)
end

function Vouchers.tomeWeight(run)
  return tierValue(run, "PLANET_MERCHANT", "PLANET_TYCOON", 4, 9.6, 32)
end

function Vouchers.interestCap(run)
  return tierValue(run, "SEED_MONEY", "MONEY_TREE", 5, 10, 20)
end

function Vouchers.extraHands(run)
  return count(run, "GRABBER") + count(run, "NACHO_TONG") - count(run, "HIEROGLYPH")
end

function Vouchers.extraDiscards(run)
  return count(run, "WASTEFUL") + count(run, "RECYCLOMANCY") - count(run, "PETROGLYPH")
end

function Vouchers.extraHandSize(run)
  return count(run, "PAINT_BRUSH") + count(run, "PALETTE")
end

function Vouchers.extraConsumables(run)
  return count(run, "CRYSTAL_BALL")
end

function Vouchers.extraTrinkets(run)
  return count(run, "ANTIMATTER")
end

function Vouchers.playingCardsInShop(run)
  return Vouchers.owns(run, "MAGIC_TRICK")
end

function Vouchers.illusion(run)
  return Vouchers.owns(run, "ILLUSION")
end

function Vouchers.omenGlobe(run)
  return Vouchers.owns(run, "OMEN_GLOBE")
end

function Vouchers.telescope(run)
  return Vouchers.owns(run, "TELESCOPE")
end

function Vouchers.observatory(run)
  return Vouchers.owns(run, "OBSERVATORY")
end

function Vouchers.bossRerolls(run)
  return tierValue(run, "DIRECTORS_CUT", "RETCON", 0, 1, math.huge)
end

function Vouchers.onBuy(run, id)
  if id == "HIEROGLYPH" or id == "PETROGLYPH" then
    run.stage = math.max(1, run.stage - 1)
  end
end
