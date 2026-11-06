local _, ns = ...

local function debuffed(ctx, card)
  local boss = ctx.bossId and ns.Bosses.def[ctx.bossId]
  return boss and boss.debuff and boss.debuff(card, ctx.rules)
end

local function steelMult(cards)
  local n = 0
  for _, card in ipairs(cards or {}) do
    if card.enh == "STEEL" then n = n + 1 end
  end
  return 1 + 0.2 * n
end

local function initMult(self) self.state.x = 1 end
local function scaledMult(_, self)
  if (self.state.x or 1) > 1 then return { xmult = self.state.x } end
end
local function multStatus(self) return "Currently ×" .. (self.state.x or 1) .. " Mult" end

-- 24: Stoneform.
ns.Trinkets.add {
  id = "STONEFORM", name = "Stoneform", rarity = "uncommon", cost = 6,
  desc = "On blind select, add a Stone card to deck",
  icon = "Interface\\Icons\\Spell_Shadow_UnholyStrength",
  onBlindSelect = function(run)
    return { createCard = { card = { rank = ns.RNG.int(run.rng, 2, 14),
      suit = ns.RNG.pick(run.rng, ns.Cards.SUITS), enh = "STONE" }, toHand = false } }
  end,
}

-- 26: Fortune Card.
ns.Trinkets.add {
  id = "FORTUNE_CARD", name = "Fortune Card", rarity = "common", cost = 5,
  desc = "{1} in 4 per played 8 to create a Scroll (needs room)",
  icon = "Interface\\Icons\\INV_Misc_Ticket_Tarot_Maelstrom_01",
  onCard = function(ctx, _, card)
    if not ns.Cards.isStone(card) and card.rank == 8
      and ns.Prob.roll(ctx.rng, ctx.trinkets, 1, 4) then
      return { createConsumable = { kind = "scroll" } }
    end
  end,
}

-- 32: Ironforge Anvil.
ns.Trinkets.add {
  id = "IRONFORGE_ANVIL", name = "Ironforge Anvil", rarity = "uncommon", cost = 7,
  desc = "×0.2 Mult per Steel card in full deck (base ×1)",
  icon = "Interface\\Icons\\Trade_BlackSmithing",
  inPool = function(run) return steelMult(run.deck) > 1 end,
  onHand = function(ctx)
    local x = steelMult(ctx.deckCards)
    if x > 1 then return { xmult = x } end
  end,
  status = function(_, ctx) return "Currently ×" .. steelMult(ctx.deckCards or ctx.deck) end,
}

-- 51: Gnomish Cloning Device.
ns.Trinkets.add {
  id = "CLONING_DEVICE", name = "Gnomish Cloning Device", rarity = "rare", cost = 8,
  desc = "First hand of round is 1 card: add a permanent copy to deck and draw it",
  icon = "Interface\\Icons\\INV_Gizmo_02",
  before = function(ctx)
    if ctx.firstHandOfRound and #ctx.cards == 1 then
      local card = ctx.cards[1]
      return { msg = "Copied!", createCard = { toHand = true, card = {
        rank = card.rank, suit = card.suit, enh = card.enh, ed = card.ed,
        seal = card.seal, bonusChips = card.bonusChips,
      } } }
    end
  end,
}

-- 54: Divination.
ns.Trinkets.add {
  id = "DIVINATION", name = "Divination", rarity = "uncommon", cost = 6,
  desc = "First hand of round is a single 6: destroy it, create a Relic",
  icon = "Interface\\Icons\\Spell_Holy_DivineIntervention",
  copyable = false,
  before = function(ctx, _, isCopy)
    if isCopy or not ctx.firstHandOfRound or #ctx.cards ~= 1 then return end
    local card = ctx.cards[1]
    if not ns.Cards.isStone(card) and card.rank == 6 then
      return { destroyCard = card.id,
        createConsumable = ctx.consumableRoom > 0 and { kind = "relic" } or nil }
    end
  end,
}

-- 55: Starlight Codex.
ns.Trinkets.add {
  id = "STARLIGHT_CODEX", name = "Starlight Codex", rarity = "uncommon", cost = 6,
  desc = "Gains ×0.1 Mult per Tome used",
  icon = "Interface\\Icons\\INV_Misc_Book_09",
  init = initMult,
  onConsumableUsed = function(_, self, item, isCopy)
    if not isCopy and item.kind == "tome" then self.state.x = (self.state.x or 1) + 0.1 end
  end,
  onHand = scaledMult, status = multStatus,
}

-- 56: Pilgrim's Bounty.
ns.Trinkets.add {
  id = "PILGRIM", name = "Pilgrim's Bounty", rarity = "uncommon", cost = 5,
  desc = "Every played card permanently gains +5 Chips when scored",
  icon = "Interface\\Icons\\INV_Boots_05",
  onCard = function(_, _, card)
    card.bonusChips = (card.bonusChips or 0) + 5
    return { changeCard = { id = card.id, bonusChips = card.bonusChips } }
  end,
}

-- 59: Chronomancy.
ns.Trinkets.add {
  id = "CHRONOMANCY", name = "Chronomancy", rarity = "common", cost = 4,
  desc = "Create a Scroll if hand contains an Ace and a Straight",
  icon = "Interface\\Icons\\Spell_Nature_TimeStop",
  before = function(ctx)
    if not ctx.contains.STRAIGHT then return end
    for _, i in ipairs(ctx.scoringIdx) do
      local card = ctx.cards[i]
      if not ns.Cards.isStone(card) and card.rank == 14 then
        return { createConsumable = { kind = "scroll" } }
      end
    end
  end,
}

-- 66: Speak with Dead.
ns.Trinkets.add {
  id = "SPEAK_DEAD", name = "Speak with Dead", rarity = "uncommon", cost = 6,
  desc = "Straight Flush: create a random Relic",
  icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
  before = function(ctx)
    if ctx.handId == "STRAIGHT_FLUSH" then return { createConsumable = { kind = "relic" } } end
  end,
}

-- 68: Vampiric Embrace.
ns.Trinkets.add {
  id = "VAMPIRIC", name = "Vampiric Embrace", rarity = "uncommon", cost = 7,
  desc = "Gains ×0.1 Mult per scoring enhanced card; removes the enhancement",
  icon = "Interface\\Icons\\Spell_Shadow_UnsummonBuilding",
  init = initMult,
  before = function(ctx, self, isCopy)
    if isCopy then return end
    for _, i in ipairs(ctx.scoringIdx) do
      local card = ctx.cards[i]
      if card.enh and not debuffed(ctx, card) then
        card.enh = nil
        self.state.x = (self.state.x or 1) + 0.1
      end
    end
  end,
  onHand = scaledMult, status = multStatus,
}

-- 70: Phantasm.
ns.Trinkets.add {
  id = "PHANTASM", name = "Phantasm", rarity = "uncommon", cost = 7,
  desc = "Gains ×0.25 Mult per playing card added to deck",
  icon = "Interface\\Icons\\Spell_Frost_MirrorImage",
  init = initMult,
  onCardsAdded = function(_, self, cards, isCopy)
    if not isCopy then self.state.x = (self.state.x or 1) + 0.25 * #cards end
  end,
  onHand = scaledMult, status = multStatus,
}

-- 71: Wandering Peddler.
ns.Trinkets.add {
  id = "PEDDLER", name = "Wandering Peddler", rarity = "rare", cost = 8,
  desc = "Create a Scroll if hand played with 4g or less",
  icon = "Interface\\Icons\\INV_Misc_Bag_10",
  before = function(ctx)
    if ctx.gold <= 4 then return { createConsumable = { kind = "scroll" } } end
  end,
}

-- 76: Gilded Mask.
ns.Trinkets.add {
  id = "GILDED_MASK", name = "Gilded Mask", rarity = "uncommon", cost = 7,
  desc = "Played face cards become Gold when scored",
  icon = "Interface\\Icons\\INV_Helmet_31",
  copyable = false,
  before = function(ctx, _, isCopy)
    if isCopy then return end
    for _, i in ipairs(ctx.scoringIdx) do
      local card = ctx.cards[i]
      if ns.Cards.isFace(card, ctx.rules) and not debuffed(ctx, card) then card.enh = "GOLD" end
    end
  end,
}

-- 77: Gladiator's Medallion.
ns.Trinkets.add {
  id = "GLAD_MEDALLION", name = "Gladiator's Medallion", rarity = "uncommon", cost = 5,
  desc = "Sell to disable current boss",
  icon = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01",
  copyable = false,
  onSelfSold = function(run)
    if run.phase == "play" and run.blind == 3 then
      return { disableBoss = true, msg = "Boss disabled!" }
    end
  end,
}

-- 81: Sandstorm.
ns.Trinkets.add {
  id = "SANDSTORM", name = "Sandstorm", rarity = "uncommon", cost = 6,
  desc = "+4 Mult per card below the starting deck size",
  icon = "Interface\\Icons\\Spell_Nature_Cyclone",
  onHand = function(ctx)
    local n = math.max(0, ctx.startDeckSize - #ctx.deckCards)
    if n > 0 then return { mult = 4 * n } end
  end,
}

-- 85: Dreamwalker.
ns.Trinkets.add {
  id = "DREAMWALKER", name = "Dreamwalker", rarity = "common", cost = 4,
  desc = "{1} in 2 to create a Scroll when any pack opened",
  icon = "Interface\\Icons\\Spell_Nature_Sleep",
  onPackOpened = function(run)
    -- No room: don't roll at all (Balatro order), so the rng stream is untouched.
    if ns.Consumables.slots(run) - #run.consumables < 1 then return end
    if ns.Prob.roll(run.rng, run.trinkets, 1, 2) then
      return { createConsumable = { kind = "scroll" } }
    end
  end,
}

-- 86: Seer.
ns.Trinkets.add {
  id = "SEER", name = "Seer", rarity = "common", cost = 6,
  desc = "+1 Mult per Scroll used this run",
  icon = "Interface\\Icons\\Spell_Nature_FarSight",
  onHand = function(ctx)
    local n = ctx.usage.scroll
    if n > 0 then return { mult = n } end
  end,
}

local function enhancedCount(cards, enh)
  local n = 0
  for _, card in ipairs(cards) do
    if card.enh and (not enh or card.enh == enh) then n = n + 1 end
  end
  return n
end

-- 89: Earthen Ring.
ns.Trinkets.add {
  id = "EARTHEN_RING", name = "Earthen Ring", rarity = "uncommon", cost = 6,
  desc = "+25 Chips per Stone card in full deck",
  icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
  inPool = function(run) return enhancedCount(run.deck, "STONE") > 0 end,
  onHand = function(ctx)
    local n = enhancedCount(ctx.deckCards, "STONE")
    if n > 0 then return { chips = 25 * n } end
  end,
}

-- 91: Fortune Cat.
ns.Trinkets.add {
  id = "FORTUNE_CAT", name = "Fortune Cat", rarity = "uncommon", cost = 6,
  desc = "Gains ×0.25 Mult per Lucky card trigger",
  icon = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
  init = initMult,
  inPool = function(run) return enhancedCount(run.deck, "LUCKY") > 0 end,
  onLucky = function(_, self, _, isCopy)
    if not isCopy then
      self.state.x = (self.state.x or 1) + 0.25
      return { msg = "Upgrade!" }
    end
  end,
  onHand = scaledMult, status = multStatus,
}

-- 106: Golden Ticket.
ns.Trinkets.add {
  id = "GOLDEN_TICKET", name = "Golden Ticket", rarity = "common", cost = 5,
  desc = "Played Gold cards give 4g",
  icon = "Interface\\Icons\\INV_Misc_Coin_02",
  inPool = function(run) return enhancedCount(run.deck, "GOLD") > 0 end,
  onCard = function(_, _, card)
    if card.enh == "GOLD" then return { gold = 4 } end
  end,
}

-- 112: Letter of Commendation.
ns.Trinkets.add {
  id = "COMMENDATION", name = "Letter of Commendation", rarity = "uncommon", cost = 6,
  desc = "Round start: add a random card with a random seal to hand (permanent)",
  icon = "Interface\\Icons\\INV_Letter_15",
  onFirstDraw = function(run)
    return { createCard = { card = { rank = ns.RNG.int(run.rng, 2, 14),
      suit = ns.RNG.pick(run.rng, ns.Cards.SUITS),
      seal = ns.RNG.pick(run.rng, { "GOLD", "RED", "BLUE", "PURPLE" }) }, toHand = true } }
  end,
}

-- 120: Glass Cannon.
ns.Trinkets.add {
  id = "GLASS_CANNON", name = "Glass Cannon", rarity = "uncommon", cost = 6,
  desc = "Gains ×0.75 Mult per Glass card destroyed",
  icon = "Interface\\Icons\\INV_Misc_Gem_Crystal_02",
  init = initMult,
  inPool = function(run) return enhancedCount(run.deck, "GLASS") > 0 end,
  onCardsDestroyed = function(_, self, cards, isCopy)
    if isCopy then return end
    local n = enhancedCount(cards, "GLASS")
    if n > 0 then
      self.state.x = (self.state.x or 1) + 0.75 * n
      return { msg = "Upgrade!" }
    end
  end,
  onHand = scaledMult, status = multStatus,
}

-- 129: Arena Champion.
ns.Trinkets.add {
  id = "ARENA_CHAMPION", name = "Arena Champion", rarity = "uncommon", cost = 7,
  desc = "8g if hand triggers the boss ability",
  icon = "Interface\\Icons\\Ability_Warrior_VictoryRush",
  after = function(ctx)
    if ctx.bossTriggered then return { gold = 8 } end
  end,
}

-- 139: Mage Tower.
ns.Trinkets.add {
  id = "MAGE_TOWER", name = "Mage Tower", rarity = "uncommon", cost = 6,
  desc = "1g per unique Tome used this run at round end",
  icon = "Interface\\Icons\\Spell_Arcane_PortalDalaran",
  copyable = false,
  onRoundEnd = function(run)
    local n = 0
    for _ in pairs(run.usage.tomeIds) do n = n + 1 end
    return n
  end,
}

-- 141: Master Riding.
ns.Trinkets.add {
  id = "MASTER_RIDING", name = "Master Riding", rarity = "rare", cost = 7,
  desc = "×3 Mult if 16+ enhanced cards in full deck",
  icon = "Interface\\Icons\\Ability_Mount_Gryphon_01",
  onHand = function(ctx)
    if enhancedCount(ctx.deckCards) >= 16 then return { xmult = 3 } end
  end,
}

-- 142: Inscriptionist.
ns.Trinkets.add {
  id = "INSCRIPTIONIST", name = "Inscriptionist", rarity = "uncommon", cost = 6,
  desc = "On blind select, create a Scroll (needs room)",
  icon = "Interface\\Icons\\INV_Inscription_Tradeskill01",
  onBlindSelect = function() return { createConsumable = { kind = "scroll" } } end,
}
