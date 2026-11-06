local _, ns = ...

-- Hooks (all optional; isCopy is true when Blueprint/Brainstorm is running the hook; see
-- Core/TrinketEngine.lua): before(ctx, self, isCopy), onCard(ctx, self, card, index, isCopy),
-- retrigger(ctx, self, card, index, isCopy), onHeld(ctx, self, card, heldIndex, isCopy),
-- heldRetrigger(...), onHand(ctx, self, isCopy), otherTrinket(ctx, self, otherDef, isCopy),
-- after(ctx, self, isCopy) -> effect|nil, onRoundEnd(run, self, isCopy) -> gold|nil.
-- An effect is { chips?, mult?, xmult?, gold?, msg?, levelHand?, destroySelf? }.
-- Lifecycle update hooks (fired by TrinketEngine.fire; isCopy last, return an effect or nil):
-- onBlindSelect(run, self, isCopy), onDiscard(run, self, cards, isCopy), roundUpdate(run, self, isCopy),
-- onBossDefeated(run, self, isCopy), onLose(run, self, isCopy). onRoundEnd stays payout-only.
-- Lifecycle effect fields: gold, msg, destroySelf, destroyTrinket (uid), createTrinkets { rarity, n },
-- sellBonusAll (n), handsDelta (n), discardsSet (n), levelHand (handId), destroyCard (cardId), save.
-- Defs may also set copyable (default true), copies ("right"|"leftmost"), rule, status(self, ctx).
local Trinkets = { order = {}, def = {} }

-- Instances: { id, ed, paid, sellBonus, state, uid }. Defs may set rule (a TrinketRules key),
-- init(instance, run) and inPool(run).
function Trinkets.add(def)
  assert(not Trinkets.def[def.id], "duplicate trinket id " .. tostring(def.id))
  Trinkets.order[#Trinkets.order + 1] = def.id
  Trinkets.def[def.id] = def
end

-- Does not insert into run.trinkets or call onObtain; callers do both.
function Trinkets.create(run, id, ed, paid)
  local instance = { id = id, ed = ed, paid = paid, sellBonus = 0, state = {},
    uid = run.nextTrinketUid }
  run.nextTrinketUid = run.nextTrinketUid + 1
  local def = Trinkets.def[id]
  if def and def.init then def.init(instance, run) end
  return instance
end

-- A copy that keeps the original's state (Relic of Rebirth). Unlike create it never calls init,
-- so a Zandalari Idol keeps its card and no RNG is drawn.
local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

function Trinkets.duplicate(run, instance, ed)
  local copy = { id = instance.id, ed = ed, paid = nil, sellBonus = instance.sellBonus or 0,
    state = deepCopy(instance.state or {}), uid = run.nextTrinketUid }
  run.nextTrinketUid = run.nextTrinketUid + 1
  return copy
end

-- Description with "{N}" tokens replaced by N times the owner's probability multiplier
-- (Loaded Dice), so "{1} in 2" reads "2 in 2" with one owned.
function Trinkets.describe(def, run)
  local trinkets = run and run.trinkets
  return ((def.desc or ""):gsub("{(%d+)}", function(n) return tostring(ns.Prob.odds(trinkets, tonumber(n))) end))
end

-- An unowned (unless Showman is owned), in-pool id of `rarity`, drawn with run.rng; nil if none.
function Trinkets.rollOfRarity(run, rarity)
  local dupes = ns.TrinketRules.has(run.trinkets, "SHOWMAN")
  local owned = {}
  for _, t in ipairs(run.trinkets) do owned[t.id] = true end
  local pool = {}
  for _, id in ipairs(Trinkets.order) do
    if Trinkets.def[id].rarity == rarity and (dupes or not owned[id]) and Trinkets.inPool(run, id) then
      pool[#pool + 1] = id
    end
  end
  if #pool == 0 then return nil end
  return ns.RNG.pick(run.rng, pool)
end

function Trinkets.inPool(run, id)
  local def = Trinkets.def[id]
  if def and def.inPool then return def.inPool(run) and true or false end
  return true
end

local LEGACY_ORDER = {
  "BLOODLUST", "ARCANE_INTELLECT", "FORTITUDE", "WHETSTONE", "HEALTHSTONE",
  "OGRE_CUDGEL", "JEWELERS_KIT", "HEARTHSTONE", "LUCKY_CHARM", "EXECUTE",
  "COMBO_POINTS", "TWIN_BLADES", "CLEAVE", "MULTI_SHOT", "ELEMENTAL",
  "ROYAL_GUARD", "BATTLE_SHOUT", "GOBLIN_BANK", "AVENGING_WRATH", "HUNTERS_MARK",
}

local LEGACY_DEFS = {
  BLOODLUST = {
    id = "BLOODLUST", name = "Drums of Bloodlust", rarity = "uncommon", cost = 5,
    desc = "×4 Mult every 6 hands played (shows countdown)",
    icon = "Interface\\Icons\\Spell_Nature_BloodLust",
    init = function(self) self.state.hands = 0 end,
    before = function(_, self, isCopy)
      if not isCopy then self.state.hands = (self.state.hands or 0) + 1 end
    end,
    onHand = function(_, self)
      if (self.state.hands or 0) % 6 == 0 then return { xmult = 4 } end
    end,
    status = function(self) return (6 - (self.state.hands or 0) % 6) .. " remaining" end,
  },
  ARCANE_INTELLECT = {
    id = "ARCANE_INTELLECT", name = "Arcane Intellect", rarity = "common", cost = 2,
    desc = "+4 Mult",
    icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    onHand = function() return { mult = 4 } end,
  },
  FORTITUDE = {
    id = "FORTITUDE", name = "Power Word: Fortitude", rarity = "common", cost = 5,
    desc = "+2 Chips per card remaining in the draw pile",
    icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    onHand = function(ctx) return { chips = 2 * ctx.pileCount } end,
  },
  WHETSTONE = {
    id = "WHETSTONE", name = "Whetstone", rarity = "common", cost = 5,
    desc = "Spades +3 Mult",
    icon = "Interface\\Icons\\INV_Stone_SharpeningStone_01",
    onCard = function(ctx, _, card)
      if ns.Cards.hasSuit(card, "S", ctx.rules) then return { mult = 3 } end
    end,
  },
  HEALTHSTONE = {
    id = "HEALTHSTONE", name = "Healthstone", rarity = "common", cost = 5,
    desc = "Hearts +3 Mult",
    icon = "Interface\\Icons\\INV_Stone_04",
    onCard = function(ctx, _, card)
      if ns.Cards.hasSuit(card, "H", ctx.rules) then return { mult = 3 } end
    end,
  },
  OGRE_CUDGEL = {
    id = "OGRE_CUDGEL", name = "Ogre Cudgel", rarity = "common", cost = 5,
    desc = "Clubs +3 Mult",
    icon = "Interface\\Icons\\INV_Mace_01",
    onCard = function(ctx, _, card)
      if ns.Cards.hasSuit(card, "C", ctx.rules) then return { mult = 3 } end
    end,
  },
  JEWELERS_KIT = {
    id = "JEWELERS_KIT", name = "Jeweler's Kit", rarity = "common", cost = 5,
    desc = "Played Diamonds +3 Mult when scored",
    icon = "Interface\\Icons\\INV_Misc_Gem_01",
    onCard = function(ctx, _, card)
      if ns.Cards.hasSuit(card, "D", ctx.rules) then return { mult = 3 } end
    end,
  },
  HEARTHSTONE = {
    id = "HEARTHSTONE", name = "Hearthstone", rarity = "common", cost = 6,
    desc = "4g at round end",
    icon = "Interface\\Icons\\INV_Misc_Rune_01",
    copyable = false,
    onRoundEnd = function() return 4 end,
  },
  LUCKY_CHARM = {
    id = "LUCKY_CHARM", name = "Gnomish Luck Charm", rarity = "common", cost = 4,
    desc = "+0 to 23 Mult (random)",
    icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
    onHand = function(ctx)
      return { mult = math.floor(ns.RNG.next(ctx.rng) * 24) }
    end,
  },
  EXECUTE = {
    id = "EXECUTE", name = "Execute", rarity = "uncommon", cost = 6,
    desc = "×3 Mult on final hand of round",
    icon = "Interface\\Icons\\Ability_Warrior_Decisivestrike",
    onHand = function(ctx)
      if ctx.isLastHand then return { xmult = 3 } end
    end,
  },
  COMBO_POINTS = {
    id = "COMBO_POINTS", name = "Combo Points", rarity = "common", cost = 5,
    desc = "+30 Chips per remaining discard",
    icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
    onHand = function(ctx) return { chips = 30 * ctx.discardsLeft } end,
  },
  TWIN_BLADES = {
    id = "TWIN_BLADES", name = "Twin Blades", rarity = "common", cost = 3,
    desc = "+8 Mult if hand contains a Pair",
    icon = "Interface\\Icons\\Ability_DualWield",
    onHand = function(ctx)
      if ctx.contains.PAIR then return { mult = 8 } end
    end,
  },
  CLEAVE = {
    id = "CLEAVE", name = "Cleave", rarity = "common", cost = 4,
    desc = "+12 Mult if Three of a Kind",
    icon = "Interface\\Icons\\Ability_Warrior_Cleave",
    onHand = function(ctx)
      if ctx.contains.THREE_KIND then return { mult = 12 } end
    end,
  },
  MULTI_SHOT = {
    id = "MULTI_SHOT", name = "Multi-Shot", rarity = "common", cost = 4,
    desc = "+12 Mult if Straight",
    icon = "Interface\\Icons\\Ability_UpgradeMoonGlaive",
    onHand = function(ctx)
      if ctx.contains.STRAIGHT then return { mult = 12 } end
    end,
  },
  ELEMENTAL = {
    id = "ELEMENTAL", name = "Elemental Attunement", rarity = "common", cost = 4,
    desc = "+10 Mult if Flush",
    icon = "Interface\\Icons\\Spell_Nature_LightningShield",
    onHand = function(ctx)
      if ctx.contains.FLUSH then return { mult = 10 } end
    end,
  },
  ROYAL_GUARD = {
    id = "ROYAL_GUARD", name = "Royal Guard", rarity = "common", cost = 4,
    desc = "Played face cards +30 Chips",
    icon = "Interface\\Icons\\INV_Shield_06",
    onCard = function(ctx, _, card)
      if ns.Cards.isFace(card, ctx.rules) then return { chips = 30 } end
    end,
  },
  BATTLE_SHOUT = {
    id = "BATTLE_SHOUT", name = "Battle Shout", rarity = "common", cost = 4,
    desc = "+3 Mult per trinket",
    icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
    onHand = function(ctx) return { mult = 3 * #ctx.trinkets } end,
  },
  GOBLIN_BANK = {
    id = "GOBLIN_BANK", name = "Goblin Bank", rarity = "uncommon", cost = 7,
    desc = "+2 Mult per 5g held",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    onHand = function(ctx) return { mult = 2 * math.floor(((ctx.goldRef and ctx.goldRef.gold) or ctx.gold) / 5) } end,
  },
  AVENGING_WRATH = {
    id = "AVENGING_WRATH", name = "Avenging Wrath", rarity = "uncommon", cost = 6,
    desc = "×3 Mult if this hand type was already played this round",
    icon = "Interface\\Icons\\Spell_Holy_AvenginWrath",
    onHand = function(ctx)
      if (ctx.roundHandPlays[ctx.handId] or 0) >= 1 then return { xmult = 3 } end
    end,
  },
  HUNTERS_MARK = {
    id = "HUNTERS_MARK", name = "Hunter's Mark", rarity = "common", cost = 4,
    desc = "Played Aces +20 Chips and +4 Mult",
    icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
    onCard = function(ctx, _, card)
      if not ns.Cards.isStone(card) and card.rank == 14 then return { chips = 20, mult = 4 } end
    end,
  },
}

for _, id in ipairs(LEGACY_ORDER) do Trinkets.add(LEGACY_DEFS[id]) end

ns.Trinkets = Trinkets
