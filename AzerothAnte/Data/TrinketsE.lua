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

-- True when the current boss debuffs the card: debuffed discards trigger nothing (like the Purple seal).
local function debuffed(run, card, rules)
  local boss = ns.Run.activeBoss(run)
  return boss and boss.debuff and boss.debuff(card, rules) and true or false
end

-- 57: Faceless One.
ns.Trinkets.add {
  id = "FACELESS_ONE", name = "Faceless One", rarity = "common", cost = 4,
  desc = "5g if 3+ face cards discarded at once",
  icon = "Interface\\Icons\\Spell_Shadow_DeathPact",
  onDiscard = function(run, _, cards)
    local n, rules = 0, ns.TrinketRules.set(run.trinkets)
    for _, card in ipairs(cards) do
      if ns.Cards.isFace(card, rules) and not debuffed(run, card, rules) then n = n + 1 end
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

-- 73: Sky Golem.
ns.Trinkets.add {
  id = "SKY_GOLEM", name = "Sky Golem", rarity = "uncommon", cost = 7,
  desc = "1g per 9 in full deck at round end",
  icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
  copyable = false,
  onRoundEnd = function(run)
    local n = 0
    for _, card in ipairs(run.deck) do
      if not ns.Cards.isStone(card) and card.rank == 9 then n = n + 1 end
    end
    return n
  end,
}

-- 74: Goblin Rocket.
ns.Trinkets.add {
  id = "GOBLIN_ROCKET", name = "Goblin Rocket", rarity = "uncommon", cost = 6,
  desc = "1g at round end; +2g payout per boss defeated",
  icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
  copyable = false,
  init = function(self) self.state.pay = 1 end,
  onBossDefeated = function(_, self, isCopy)
    if isCopy then return end
    self.state.pay = self.state.pay + 2
    return { msg = "Upgrade!" }
  end,
  onRoundEnd = function(_, self) return self.state.pay end,
  status = function(self) return "Currently " .. self.state.pay .. "g" end,
}

-- 79: Winter Veil Gift.
ns.Trinkets.add {
  id = "WINTER_VEIL", name = "Winter Veil Gift", rarity = "uncommon", cost = 6,
  desc = "+1g sell value to every trinket and consumable at round end",
  icon = "Interface\\Icons\\INV_Misc_Bag_08",
  copyable = false,
  roundUpdate = function(_, _, isCopy)
    if not isCopy then return { sellBonusAll = 1 } end
  end,
}

-- 80: Fertile Seed.
ns.Trinkets.add {
  id = "FERTILE_SEED", name = "Fertile Seed", rarity = "uncommon", cost = 6,
  desc = "+5 hand size, -1 per round",
  icon = "Interface\\Icons\\Spell_Nature_LightningShield",
  copyable = false,
  init = function(self) self.state.n = 5 end,
  handSize = function(self) return self.state.n end,
  roundUpdate = function(_, self, isCopy)
    if isCopy then return end
    self.state.n = self.state.n - 1
    if self.state.n <= 0 then return { destroySelf = true, msg = "Eaten!" } end
  end,
  status = function(self) return "Currently +" .. self.state.n .. " hand size" end,
}

local function pickMailRank(self, run)
  local pool = {}
  for _, card in ipairs(run.deck) do
    if not ns.Cards.isStone(card) then pool[#pool + 1] = card end
  end
  self.state.rank = #pool > 0 and ns.RNG.pick(run.rng, pool).rank or nil
end

-- 83: Postmaster's Rebate.
ns.Trinkets.add {
  id = "POSTMASTER", name = "Postmaster's Rebate", rarity = "common", cost = 4,
  desc = "5g per discarded [rank]; rank changes each round",
  icon = "Interface\\Icons\\INV_Misc_Note_01",
  init = pickMailRank,
  roundUpdate = function(run, self, isCopy)
    if not isCopy then pickMailRank(self, run) end
  end,
  onDiscard = function(run, self, cards)
    local n, rules = 0, ns.TrinketRules.set(run.trinkets)
    for _, card in ipairs(cards) do
      if not ns.Cards.isStone(card) and card.rank == self.state.rank and not debuffed(run, card, rules) then
        n = n + 1
      end
    end
    if n > 0 then return { gold = 5 * n } end
  end,
  status = function(self)
    return "Rank: " .. (self.state.rank and ns.Cards.label { rank = self.state.rank } or "None")
  end,
}

-- 84: Goblin Investment.
ns.Trinkets.add {
  id = "GOBLIN_INVEST", name = "Goblin Investment", rarity = "uncommon", cost = 5,
  desc = "+1g interest per 5g held",
  icon = "Interface\\Icons\\INV_Misc_Coin_01",
  copyable = false, interestBonus = 1,
}

-- 87: Reagent Bag.
ns.Trinkets.add {
  id = "REAGENT_BAG", name = "Reagent Bag", rarity = "common", cost = 4,
  desc = "+1 hand size",
  icon = "Interface\\Icons\\INV_Misc_Bag_08",
  copyable = false, handSize = 1,
}

-- 88: Dwarven Stout.
ns.Trinkets.add {
  id = "DWARVEN_STOUT", name = "Dwarven Stout", rarity = "common", cost = 4,
  desc = "+1 discard each round",
  icon = "Interface\\Icons\\INV_Drink_03",
  copyable = false, discards = 1,
}

-- 95: Trading Post.
ns.Trinkets.add {
  id = "TRADING_POST", name = "Trading Post", rarity = "uncommon", cost = 6,
  desc = "First discard of round is 1 card: destroy it, 3g",
  icon = "Interface\\Icons\\INV_Misc_Note_01",
  copyable = false, -- Balatro's Trading Card is not Blueprint-compatible.
  onDiscard = function(run, _, cards)
    if run.discardsUsedRound == 0 and #cards == 1 then
      return { destroyCard = cards[1].id, gold = 3 }
    end
  end,
}

-- 96: Flash Heal.
ns.Trinkets.add {
  id = "FLASH_HEAL", name = "Flash Heal", rarity = "uncommon", cost = 5,
  desc = "Gains +2 Mult per shop reroll",
  icon = "Interface\\Icons\\Spell_Holy_FlashHeal",
  init = function(self) self.state.mult = 0 end,
  onShopReroll = function(_, self, isCopy)
    if isCopy then return end
    self.state.mult = self.state.mult + 2
    return { msg = "Upgrade!" }
  end,
  onHand = function(_, self) return { mult = self.state.mult } end,
  status = function(self) return "Currently +" .. self.state.mult .. " Mult" end,
}

-- 97: Darkmoon Popcorn.
ns.Trinkets.add {
  id = "POPCORN", name = "Darkmoon Popcorn", rarity = "common", cost = 5,
  desc = "+20 Mult; -4 per round; eaten at 0",
  icon = "Interface\\Icons\\INV_Misc_Food_11",
  init = function(self) self.state.mult = 20 end,
  onHand = function(_, self) return { mult = self.state.mult } end,
  roundUpdate = function(_, self, isCopy)
    if isCopy then return end
    self.state.mult = self.state.mult - 4
    if self.state.mult <= 0 then return { destroySelf = true, msg = "Eaten!" } end
  end,
  status = function(self) return "Currently +" .. self.state.mult .. " Mult" end,
}

-- 100: Pandaren Noodles.
ns.Trinkets.add {
  id = "NOODLES", name = "Pandaren Noodles", rarity = "uncommon", cost = 6,
  desc = "×2 Mult; -×0.01 per card discarded; eaten at ×1",
  icon = "Interface\\Icons\\INV_Misc_Food_11",
  init = function(self) self.state.x = 2 end,
  onHand = function(_, self) return { xmult = self.state.x } end,
  onDiscard = function(_, self, cards, isCopy)
    if isCopy then return end
    self.state.x = math.floor((self.state.x - 0.01 * #cards) * 100 + 0.5) / 100
    if self.state.x <= 1 then return { destroySelf = true, msg = "Eaten!" } end
  end,
  status = function(self) return "Currently ×" .. self.state.x .. " Mult" end,
}

-- The suit of a random non-Stone deck card, never the current suit unless the deck has no other.
local function pickCastleSuit(self, run)
  local other, any = {}, {}
  for _, card in ipairs(run.deck) do
    if not ns.Cards.isStone(card) then
      any[#any + 1] = card.suit
      if card.suit ~= self.state.suit then other[#other + 1] = card.suit end
    end
  end
  local pool = #other > 0 and other or any
  if #pool == 0 then pool = ns.Cards.SUITS end
  self.state.suit = ns.RNG.pick(run.rng, pool)
end

-- 103: Stormwind Keep.
ns.Trinkets.add {
  id = "STORMWIND_KEEP", name = "Stormwind Keep", rarity = "uncommon", cost = 6,
  desc = "Gains +3 Chips per discarded [suit]; suit changes each round",
  icon = "Interface\\Icons\\INV_Shield_06",
  init = function(self, run) self.state.chips = 0; pickCastleSuit(self, run) end,
  roundUpdate = function(run, self, isCopy)
    if not isCopy then pickCastleSuit(self, run) end
  end,
  onDiscard = function(run, self, cards, isCopy)
    if isCopy then return end
    local rules, gained = ns.TrinketRules.set(run.trinkets), 0
    for _, card in ipairs(cards) do
      if ns.Cards.hasSuit(card, self.state.suit, rules) and not debuffed(run, card, rules) then gained = gained + 3 end
    end
    if gained > 0 then
      self.state.chips = self.state.chips + gained
      return { msg = "Upgrade!" }
    end
  end,
  onHand = function(_, self) return { chips = self.state.chips } end,
  status = function(self) return "Suit: " .. ns.Cards.SUIT_NAMES[self.state.suit] end,
}

-- 105: Cooking Fire.
ns.Trinkets.add {
  id = "COOKING_FIRE", name = "Cooking Fire", rarity = "rare", cost = 9,
  desc = "Gains ×0.25 Mult per card sold; resets on boss defeat",
  icon = "Interface\\Icons\\Spell_Fire_Fire",
  init = function(self) self.state.x = 1 end,
  onSell = function(_, self, _, isCopy)
    if isCopy then return end
    self.state.x = self.state.x + 0.25
    return { msg = "Upgrade!" }
  end,
  onBossDefeated = function(_, self, isCopy)
    if isCopy then return end
    local grown = self.state.x > 1
    self.state.x = 1
    if grown then return { msg = "Reset" } end
  end,
  onHand = function(_, self)
    if self.state.x > 1 then return { xmult = self.state.x } end
  end,
  status = function(self) return "Currently ×" .. self.state.x .. " Mult" end,
}

-- 107: Soulstone.
ns.Trinkets.add {
  id = "SOULSTONE", name = "Soulstone", rarity = "uncommon", cost = 5,
  desc = "Prevents loss if score >= 25% of target; destroyed",
  icon = "Interface\\Icons\\Spell_Shadow_SoulGem",
  copyable = false,
  onLose = function(run, self)
    -- Claims the save inside the hook: hooks run before effects apply, so a second stone would also see it unclaimed.
    if run.savedBy or run.score < 0.25 * run.target then return end
    run.savedBy, run.savedById = self.uid, self.id
    return { save = true, destroySelf = true, msg = "Saved!" }
  end,
}

-- 111: Wandering Minstrel.
ns.Trinkets.add {
  id = "MINSTREL", name = "Wandering Minstrel", rarity = "uncommon", cost = 6,
  desc = "+2 hand size, -1 hand each round",
  icon = "Interface\\Icons\\INV_Misc_Note_01",
  copyable = false, handSize = 2, hands = -1,
}

-- 121: Ringmaster Silas.
ns.Trinkets.add {
  id = "SILAS", name = "Ringmaster Silas", rarity = "uncommon", cost = 5,
  desc = "Trinkets and consumables may repeat",
  icon = "Interface\\Icons\\INV_Crown_01",
  copyable = false, rule = "SHOWMAN",
}

-- 125: Drunken Brawler.
ns.Trinkets.add {
  id = "BRAWLER", name = "Drunken Brawler", rarity = "uncommon", cost = 7,
  desc = "+3 discards, -1 hand size",
  icon = "Interface\\Icons\\INV_Drink_03",
  copyable = false, discards = 3, handSize = -1,
}

-- 130: Mount Up.
ns.Trinkets.add {
  id = "MOUNT_UP", name = "Mount Up", rarity = "rare", cost = 8,
  desc = "Gains ×0.5 Mult per Jack discarded this round (resets)",
  icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
  init = function(self) self.state.x = 1 end,
  onDiscard = function(run, self, cards, isCopy)
    if isCopy then return end
    local rules, gained = ns.TrinketRules.set(run.trinkets), 0
    for _, card in ipairs(cards) do
      if not ns.Cards.isStone(card) and card.rank == 11 and not debuffed(run, card, rules) then gained = gained + 0.5 end
    end
    if gained > 0 then
      self.state.x = self.state.x + gained
      return { msg = "Upgrade!" }
    end
  end,
  roundUpdate = function(_, self, isCopy)
    if isCopy then return end
    local grown = self.state.x > 1
    self.state.x = 1
    if grown then return { msg = "Reset" } end
  end,
  onHand = function(_, self)
    if self.state.x > 1 then return { xmult = self.state.x } end
  end,
  status = function(self) return "Currently ×" .. self.state.x .. " Mult" end,
}

-- 136: Leeroy Jenkins.
ns.Trinkets.add {
  id = "LEEROY", name = "Leeroy Jenkins", rarity = "rare", cost = 7,
  desc = "+250 Chips, -2 hand size",
  icon = "Interface\\Icons\\Ability_Warrior_Charge",
  handSize = -2,
  onHand = function() return { chips = 250 } end,
}

-- 137: Invisibility Potion.
ns.Trinkets.add {
  id = "INVIS_POTION", name = "Invisibility Potion", rarity = "rare", cost = 8,
  desc = "After 2 rounds, sell to duplicate a random trinket",
  icon = "Interface\\Icons\\INV_Potion_18",
  copyable = false,
  init = function(self) self.state.rounds = 0 end,
  roundUpdate = function(_, self, isCopy)
    if not isCopy then self.state.rounds = self.state.rounds + 1 end
  end,
  onSelfSold = function(run, self)
    if self.state.rounds < 2 then return end
    local pool = {}
    for _, instance in ipairs(run.trinkets) do
      if instance.uid ~= self.uid then pool[#pool + 1] = instance end
    end
    if #pool == 0 then return end
    local original = ns.RNG.pick(run.rng, pool)
    local ed = original.ed ~= "NEGATIVE" and original.ed or nil
    local copy = ns.Trinkets.duplicate(run, original, ed)
    run.trinkets[#run.trinkets + 1] = copy
    if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain("trinket", copy.id) end
    run.lifecycleEvents = run.lifecycleEvents or {}
    run.lifecycleEvents[#run.lifecycleEvents + 1] =
      { kind = "trinketCreated", uid = copy.uid, slot = #run.trinkets - 1, id = copy.id, by = self.uid }
    -- The sold potion's own slot is gone by now, so the message rides on the copy.
    run.lifecycleEvents[#run.lifecycleEvents + 1] =
      { kind = "trinketMsg", uid = copy.uid, slot = #run.trinkets - 1, text = "Duplicated!" }
  end,
  status = function(self)
    return self.state.rounds >= 2 and "Ready!" or self.state.rounds .. "/2 rounds"
  end,
}

-- 143: Stargazer.
ns.Trinkets.add {
  id = "STARGAZER", name = "Stargazer", rarity = "uncommon", cost = 8,
  desc = "Tomes and Celestial packs in shop are free",
  icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
  copyable = false, rule = "ASTRONOMER",
}

-- 144: Burnt Offering.
ns.Trinkets.add {
  id = "BURNT_OFFERING", name = "Burnt Offering", rarity = "rare", cost = 8,
  desc = "Level up the first discarded hand type each round",
  icon = "Interface\\Icons\\Spell_Fire_Fire",
  onDiscard = function(run, _, cards)
    if run.discardsUsedRound == 0 then
      return { levelHand = ns.HandEval.evaluate(cards, ns.TrinketRules.set(run.trinkets)) }
    end
  end,
}
