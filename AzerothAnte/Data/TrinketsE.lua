local _, ns = ...

-- 20: Venture Co. Loan.
ns.Trinkets.add {
  id = "VENTURE_LOAN", name = "Venture Co. Loan", rarity = "common", cost = 1,
  desc = "Go up to -20g in debt",
  icon = "Interface\\Icons\\INV_Misc_Coin_01",
  rule = "CREDIT_CARD", copyable = false,
}

-- 21: Soul Harvest.
ns.Trinkets.add {
  id = "SOUL_HARVEST", name = "Soul Harvest", rarity = "uncommon", cost = 6,
  desc = "On blind select, destroy trinket to the right; add double its sell value to this Mult",
  icon = "Interface\\Icons\\Spell_Shadow_DeathPact",
  init = function(self) self.state.mult = 0 end,
  onBlindSelect = function(run, self, isCopy)
    if isCopy then return end
    for slot, instance in ipairs(run.trinkets) do
      if instance.uid == self.uid then
        local victim = run.trinkets[slot + 1]
        if not victim or ns.TrinketEngine.isMarked(run, victim.uid) then return end
        local gain = 2 * ns.Shop.sellValue(victim)
        self.state.mult = (self.state.mult or 0) + gain
        return { destroyTrinket = victim.uid, msg = "+" .. gain .. " Mult" }
      end
    end
  end,
  onHand = function(_, self)
    if (self.state.mult or 0) > 0 then return { mult = self.state.mult } end
  end,
  status = function(self) return "Currently +" .. (self.state.mult or 0) .. " Mult" end,
}

-- 30: Darkmoon Ticket.
ns.Trinkets.add {
  id = "DARKMOON_TICKET", name = "Darkmoon Ticket", rarity = "common", cost = 4,
  desc = "1 free reroll per shop",
  icon = "Interface\\Icons\\INV_Misc_Note_01",
  rule = "CHAOS", copyable = false,
}

-- 35: Inner Peace.
ns.Trinkets.add {
  id = "INNER_PEACE", name = "Inner Peace", rarity = "common", cost = 4,
  desc = "2g per discard left at round end if none used",
  icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
  copyable = false,
  onRoundEnd = function(run)
    if run.discardsUsedRound == 0 and run.discardsLeft > 0 then return 2 * run.discardsLeft end
  end,
}

-- 38: Ripe Banana.
ns.Trinkets.add {
  id = "RIPE_BANANA", name = "Ripe Banana", rarity = "common", cost = 5,
  desc = "+15 Mult; {1} in 6 chance destroyed at round end",
  icon = "Interface\\Icons\\INV_Misc_Food_24",
  onHand = function() return { mult = 15 } end,
  roundUpdate = function(run, _, isCopy)
    if not isCopy and ns.Prob.roll(run.rng, run.trinkets, 1, 6) then
      run.flags.grosMichelExtinct = true
      return { destroySelf = true, msg = "Extinct!" }
    end
  end,
  inPool = function(run) return not run.flags.grosMichelExtinct end,
}

-- 46: Whelpling Egg.
ns.Trinkets.add {
  id = "WHELP_EGG", name = "Whelpling Egg", rarity = "common", cost = 4,
  desc = "+3g sell value at round end",
  icon = "Interface\\Icons\\INV_Egg_01",
  copyable = false,
  roundUpdate = function(_, self, isCopy)
    if isCopy then return end
    self.sellBonus = (self.sellBonus or 0) + 3
    return { msg = "Value up!" }
  end,
}

-- 47: SI:7 Agent.
ns.Trinkets.add {
  id = "SI7_AGENT", name = "SI:7 Agent", rarity = "uncommon", cost = 6,
  desc = "On blind select, +3 hands and lose all discards",
  icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
  onBlindSelect = function() return { handsDelta = 3, discardsSet = 0 } end,
}

-- 57: Faceless One.
ns.Trinkets.add {
  id = "FACELESS_ONE", name = "Faceless One", rarity = "common", cost = 4,
  desc = "5g if 3+ face cards discarded at once",
  icon = "Interface\\Icons\\Spell_Shadow_DeathPact",
  onDiscard = function(run, _, cards)
    local n, rules = 0, ns.TrinketRules.set(run.trinkets)
    for _, card in ipairs(cards) do
      if ns.Cards.isFace(card, rules) then n = n + 1 end
    end
    if n >= 3 then return { gold = 5 } end
  end,
}

-- 58: Fel Infusion.
ns.Trinkets.add {
  id = "FEL_INFUSION", name = "Fel Infusion", rarity = "common", cost = 4,
  desc = "+1 Mult per hand played, -1 per discard",
  icon = "Interface\\Icons\\Spell_Shadow_DeathPact",
  init = function(self) self.state.mult = 0 end,
  before = function(_, self, isCopy)
    if not isCopy then
      self.state.mult = (self.state.mult or 0) + 1
      return { msg = "+1 Mult" }
    end
  end,
  onDiscard = function(_, self, _, isCopy)
    if not isCopy then self.state.mult = math.max(0, (self.state.mult or 0) - 1) end
  end,
  onHand = function(_, self)
    if (self.state.mult or 0) > 0 then return { mult = self.state.mult } end
  end,
  status = function(self) return "Currently +" .. (self.state.mult or 0) .. " Mult" end,
}

local function pickHand(self, run)
  local pool = {}
  for _, id in ipairs(ns.Hands.order) do
    if id ~= self.state.hand and (not ns.Hands.def[id].secret or run.seenHands[id]) then
      pool[#pool + 1] = id
    end
  end
  self.state.hand = ns.RNG.pick(run.rng, pool)
end

-- 60: Daily Quest.
ns.Trinkets.add {
  id = "DAILY_QUEST", name = "Daily Quest", rarity = "common", cost = 4,
  desc = "4g if hand is [hand type]; changes each round",
  icon = "Interface\\Icons\\INV_Misc_Note_01",
  init = pickHand,
  roundUpdate = function(run, self, isCopy)
    if not isCopy then pickHand(self, run) end
  end,
  before = function(ctx, self)
    if ctx.handId == self.state.hand then return { gold = 4 } end
  end,
  status = function(self) return "Hand: " .. ns.Hands.def[self.state.hand].name end,
}

-- 61: Golden Banana.
ns.Trinkets.add {
  id = "GOLDEN_BANANA", name = "Golden Banana", rarity = "common", cost = 4,
  desc = "×3 Mult; {1} in 1000 destroyed at round end",
  icon = "Interface\\Icons\\INV_Misc_Food_24",
  onHand = function() return { xmult = 3 } end,
  roundUpdate = function(run, _, isCopy)
    if not isCopy and ns.Prob.roll(run.rng, run.trinkets, 1, 1000) then
      return { destroySelf = true, msg = "Extinct!" }
    end
  end,
  inPool = function(run) return run.flags.grosMichelExtinct end,
}

-- 63: Pack Rat.
ns.Trinkets.add {
  id = "PACK_RAT", name = "Pack Rat", rarity = "common", cost = 5,
  desc = "Gains +3 Mult per pack skipped",
  icon = "Interface\\Icons\\INV_Misc_Bag_08",
  init = function(self) self.state.mult = 0 end,
  onPackSkipped = function(_, self, isCopy)
    if not isCopy then
      self.state.mult = (self.state.mult or 0) + 3
      return { msg = "+3 Mult" }
    end
  end,
  onHand = function(_, self)
    if (self.state.mult or 0) > 0 then return { mult = self.state.mult } end
  end,
  status = function(self) return "Currently +" .. (self.state.mult or 0) .. " Mult" end,
}

-- 64: Whispers of the Old Gods.
ns.Trinkets.add {
  id = "OLD_GODS", name = "Whispers of the Old Gods", rarity = "uncommon", cost = 7,
  desc = "Small/Big blind select: gain ×0.5 Mult, destroy a random other trinket",
  icon = "Interface\\Icons\\Spell_Shadow_DeathPact",
  init = function(self) self.state.x = 1 end,
  onBlindSelect = function(run, self, isCopy)
    if isCopy or run.blind == 3 then return end
    self.state.x = (self.state.x or 1) + 0.5
    local pool = {}
    for _, instance in ipairs(run.trinkets) do
      if instance.uid ~= self.uid and not ns.TrinketEngine.isMarked(run, instance.uid) then
        pool[#pool + 1] = instance.uid
      end
    end
    return { msg = "Upgrade!", destroyTrinket = #pool > 0 and ns.RNG.pick(run.rng, pool) or nil }
  end,
  onHand = function(_, self)
    if (self.state.x or 1) > 1 then return { xmult = self.state.x } end
  end,
  status = function(self) return "Currently ×" .. (self.state.x or 1) .. " Mult" end,
}

-- 67: Call to Arms.
ns.Trinkets.add {
  id = "CALL_TO_ARMS", name = "Call to Arms", rarity = "common", cost = 6,
  desc = "On blind select, create 2 Common trinkets (needs room)",
  icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
  onBlindSelect = function() return { createTrinkets = { rarity = "common", n = 2 } } end,
}
