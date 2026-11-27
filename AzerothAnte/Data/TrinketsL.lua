local _, ns = ...

-- The skip-tag jokers (Diet Cola, Throwback) and the five legendaries. Legendaries never roll at
-- random (Trinkets.inPool); Heart of Azeroth creates them.

local function initMult(self) self.state.x = 1 end
local function scaledMult(_, self)
  if (self.state.x or 1) > 1 then return { xmult = self.state.x } end
end
local function multStatus(self) return "Currently ×" .. (self.state.x or 1) .. " Mult" end

-- 94: Diet Cola.
ns.Trinkets.add {
  id = "DARKMOON_FIZZ", name = "Darkmoon Fizz", rarity = "uncommon", cost = 6,
  desc = "Sell to create a free Bonus Roll",
  icon = "Interface\\Icons\\INV_Drink_04",
  copyable = false,
  onSelfSold = function(run)
    ns.Tags.add(run, "DOUBLE")
    return { msg = "Bonus Roll!" }
  end,
}

-- 114: Throwback.
ns.Trinkets.add {
  id = "TIMEWALKING_BADGE", name = "Timewalking Badge", rarity = "uncommon", cost = 6,
  desc = "×0.25 Mult per blind skipped this run",
  icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  onHand = function(ctx)
    local skips = ctx.skips or 0
    if skips > 0 then return { xmult = 1 + 0.25 * skips } end
  end,
  status = function(_, run) return "Currently ×" .. (1 + 0.25 * (run.skips or 0)) .. " Mult" end,
}

-- Canio.
ns.Trinkets.add {
  id = "FROSTMOURNE", name = "Frostmourne", rarity = "legendary", cost = 20,
  desc = "Gains ×1 Mult when a face card is destroyed",
  icon = "Interface\\Icons\\INV_Sword_122",
  init = initMult,
  onCardsDestroyed = function(run, self, cards, isCopy)
    if isCopy then return end
    local rules, n = ns.TrinketRules.set(run.trinkets), 0
    for _, card in ipairs(cards) do
      if ns.Cards.isFace(card, rules) then n = n + 1 end
    end
    if n > 0 then
      self.state.x = (self.state.x or 1) + n
      return { msg = "Upgrade!" }
    end
  end,
  onHand = scaledMult, status = multStatus,
}

-- Triboulet.
ns.Trinkets.add {
  id = "SHALAMAYNE", name = "Shalamayne", rarity = "legendary", cost = 20,
  desc = "Played Kings and Queens each give ×2 Mult",
  icon = "Interface\\Icons\\INV_Sword_27",
  onCard = function(_, _, card)
    if not ns.Cards.isStone(card) and (card.rank == 12 or card.rank == 13) then return { xmult = 2 } end
  end,
}

-- Yorick: counts down from 23 cards discarded, then gains ×1 and starts again.
local SOULS = 23
ns.Trinkets.add {
  id = "SHADOWMOURNE", name = "Shadowmourne", rarity = "legendary", cost = 20,
  desc = "Gains ×1 Mult every 23 cards discarded",
  icon = "Interface\\Icons\\INV_Axe_113",
  init = function(self) self.state.x, self.state.left = 1, SOULS end,
  onDiscard = function(_, self, cards, isCopy)
    if isCopy then return end
    local left, gained = (self.state.left or SOULS) - #cards, 0
    while left <= 0 do
      left, gained = left + SOULS, gained + 1
    end
    self.state.left = left
    if gained > 0 then
      self.state.x = (self.state.x or 1) + gained
      return { msg = "Upgrade!" }
    end
  end,
  onHand = scaledMult,
  status = function(self)
    return multStatus(self) .. " (" .. (self.state.left or SOULS) .. " to go)"
  end,
}

-- Chicot. Also disables a boss already in play when Heart of Azeroth creates it (see Relics LEGENDS).
ns.Trinkets.add {
  id = "ASHBRINGER", name = "Ashbringer", rarity = "legendary", cost = 20,
  desc = "Disables every boss blind",
  icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
  onBlindSelect = function(run)
    if ns.Run.bossId(run) then return { disableBoss = true } end
  end,
}

-- Perkeo.
ns.Trinkets.add {
  id = "DRAGONWRATH", name = "Dragonwrath", rarity = "legendary", cost = 20,
  desc = "Leaving the shop: a Negative copy of 1 random held consumable",
  icon = "Interface\\Icons\\Spell_Fire_Fireball02",
  onShopExit = function(run)
    if #run.consumables == 0 then return end
    local item = ns.RNG.pick(run.rng, run.consumables)
    return { createConsumable = { kind = item.kind, id = item.id, ed = "NEGATIVE" } }
  end,
}
