local _, ns = ...

-- Hooks: onCard(ctx, card) -> {chips=,mult=,xmult=}|nil, onHand(ctx) -> effect|nil,
-- onRoundEnd(run) -> goldDelta|nil.
local Trinkets = {}

Trinkets.order = {
  "BLOODLUST", "ARCANE_INTELLECT", "FORTITUDE", "WHETSTONE", "HEALTHSTONE",
  "OGRE_CUDGEL", "JEWELERS_KIT", "HEARTHSTONE", "LUCKY_CHARM", "EXECUTE",
  "COMBO_POINTS", "TWIN_BLADES", "CLEAVE", "MULTI_SHOT", "ELEMENTAL",
  "ROYAL_GUARD", "BATTLE_SHOUT", "GOBLIN_BANK", "AVENGING_WRATH", "HUNTERS_MARK",
}

Trinkets.def = {
  BLOODLUST = {
    id = "BLOODLUST", name = "Drums of Bloodlust", rarity = "rare", cost = 8,
    desc = "Hands played: x3 mult on every 5th hand.",
    icon = "Interface\\Icons\\Spell_Nature_BloodLust",
    onHand = function(ctx)
      if ctx.handsPlayedTotal % 5 == 0 then return { xmult = 3 } end
    end,
  },
  ARCANE_INTELLECT = {
    id = "ARCANE_INTELLECT", name = "Arcane Intellect", rarity = "common", cost = 4,
    desc = "+4 mult.",
    icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    onHand = function() return { mult = 4 } end,
  },
  FORTITUDE = {
    id = "FORTITUDE", name = "Power Word: Fortitude", rarity = "common", cost = 4,
    desc = "+50 chips.",
    icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    onHand = function() return { chips = 50 } end,
  },
  WHETSTONE = {
    id = "WHETSTONE", name = "Whetstone", rarity = "common", cost = 5,
    desc = "Each scoring Spade gives +3 mult.",
    icon = "Interface\\Icons\\INV_Stone_Sharpening_Dwarven",
    onCard = function(_, card)
      if card.suit == "S" then return { mult = 3 } end
    end,
  },
  HEALTHSTONE = {
    id = "HEALTHSTONE", name = "Healthstone", rarity = "common", cost = 5,
    desc = "Each scoring Heart gives +3 mult.",
    icon = "Interface\\Icons\\INV_Stone_04",
    onCard = function(_, card)
      if card.suit == "H" then return { mult = 3 } end
    end,
  },
  OGRE_CUDGEL = {
    id = "OGRE_CUDGEL", name = "Ogre Cudgel", rarity = "common", cost = 5,
    desc = "Each scoring Club gives +3 mult.",
    icon = "Interface\\Icons\\INV_Mace_01",
    onCard = function(_, card)
      if card.suit == "C" then return { mult = 3 } end
    end,
  },
  JEWELERS_KIT = {
    id = "JEWELERS_KIT", name = "Jeweler's Kit", rarity = "common", cost = 5,
    desc = "Each scoring Diamond gives +3 mult.",
    icon = "Interface\\Icons\\INV_Misc_Gem_01",
    onCard = function(_, card)
      if card.suit == "D" then return { mult = 3 } end
    end,
  },
  HEARTHSTONE = {
    id = "HEARTHSTONE", name = "Hearthstone", rarity = "common", cost = 5,
    desc = "+3 gold at the end of each round.",
    icon = "Interface\\Icons\\INV_Misc_Rune_01",
    onRoundEnd = function() return 3 end,
  },
  LUCKY_CHARM = {
    id = "LUCKY_CHARM", name = "Gnomish Luck Charm", rarity = "uncommon", cost = 6,
    desc = "25% chance for +20 mult each hand.",
    icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
    onHand = function(ctx)
      if ns.RNG.next(ctx.rng) < 0.25 then return { mult = 20 } end
    end,
  },
  EXECUTE = {
    id = "EXECUTE", name = "Execute", rarity = "uncommon", cost = 7,
    desc = "x3 mult on your last hand of the round.",
    icon = "Interface\\Icons\\Ability_Warrior_Decisivestrike",
    onHand = function(ctx)
      if ctx.isLastHand then return { xmult = 3 } end
    end,
  },
  COMBO_POINTS = {
    id = "COMBO_POINTS", name = "Combo Points", rarity = "common", cost = 5,
    desc = "+20 chips for each unused discard.",
    icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
    onHand = function(ctx) return { chips = 20 * ctx.discardsLeft } end,
  },
  TWIN_BLADES = {
    id = "TWIN_BLADES", name = "Twin Blades", rarity = "common", cost = 4,
    desc = "+8 mult if the hand contains a Pair.",
    icon = "Interface\\Icons\\Ability_DualWield",
    onHand = function(ctx)
      if ctx.contains.PAIR then return { mult = 8 } end
    end,
  },
  CLEAVE = {
    id = "CLEAVE", name = "Cleave", rarity = "common", cost = 5,
    desc = "+12 mult if the hand contains Three of a Kind.",
    icon = "Interface\\Icons\\Ability_Warrior_Cleave",
    onHand = function(ctx)
      if ctx.contains.THREE_KIND then return { mult = 12 } end
    end,
  },
  MULTI_SHOT = {
    id = "MULTI_SHOT", name = "Multi-Shot", rarity = "uncommon", cost = 6,
    desc = "+12 mult if the hand contains a Straight.",
    icon = "Interface\\Icons\\Ability_Hunter_MultiShot",
    onHand = function(ctx)
      if ctx.contains.STRAIGHT then return { mult = 12 } end
    end,
  },
  ELEMENTAL = {
    id = "ELEMENTAL", name = "Elemental Attunement", rarity = "uncommon", cost = 6,
    desc = "+10 mult if the hand contains a Flush.",
    icon = "Interface\\Icons\\Spell_Nature_LightningShield",
    onHand = function(ctx)
      if ctx.contains.FLUSH then return { mult = 10 } end
    end,
  },
  ROYAL_GUARD = {
    id = "ROYAL_GUARD", name = "Royal Guard", rarity = "common", cost = 5,
    desc = "Each scoring face card gives +30 chips.",
    icon = "Interface\\Icons\\INV_Shield_06",
    onCard = function(_, card)
      if ns.Cards.isFace(card) then return { chips = 30 } end
    end,
  },
  BATTLE_SHOUT = {
    id = "BATTLE_SHOUT", name = "Battle Shout", rarity = "uncommon", cost = 6,
    desc = "+3 mult for each trinket you own.",
    icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
    onHand = function(ctx) return { mult = 3 * #ctx.trinkets } end,
  },
  GOBLIN_BANK = {
    id = "GOBLIN_BANK", name = "Goblin Bank", rarity = "uncommon", cost = 6,
    desc = "+1 mult for every 5 gold you hold.",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    onHand = function(ctx) return { mult = math.floor(ctx.gold / 5) } end,
  },
  AVENGING_WRATH = {
    id = "AVENGING_WRATH", name = "Avenging Wrath", rarity = "rare", cost = 8,
    desc = "x2 mult.",
    icon = "Interface\\Icons\\Spell_Holy_AvengingWrath",
    onHand = function() return { xmult = 2 } end,
  },
  HUNTERS_MARK = {
    id = "HUNTERS_MARK", name = "Hunter's Mark", rarity = "rare", cost = 8,
    desc = "Each scoring Ace gives x1.5 mult.",
    icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
    onCard = function(_, card)
      if card.rank == 14 then return { xmult = 1.5 } end
    end,
  },
}

ns.Trinkets = Trinkets
