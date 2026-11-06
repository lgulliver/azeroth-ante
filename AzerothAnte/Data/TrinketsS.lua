local _, ns = ...

-- 8: Twin Fangs.
ns.Trinkets.add {
  id = "TWIN_FANGS", name = "Twin Fangs", rarity = "common", cost = 4,
  desc = "+10 Mult if Two Pair",
  icon = "Interface\\Icons\\Ability_DualWield",
  onHand = function(ctx)
    if ctx.contains.TWO_PAIR then return { mult = 10 } end
  end,
}

-- 11: Pickpocket.
ns.Trinkets.add {
  id = "PICKPOCKET", name = "Pickpocket", rarity = "common", cost = 3,
  desc = "+50 Chips if Pair",
  icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
  onHand = function(ctx)
    if ctx.contains.PAIR then return { chips = 50 } end
  end,
}

-- 12: Tricks of the Trade.
ns.Trinkets.add {
  id = "TRICKS_TRADE", name = "Tricks of the Trade", rarity = "common", cost = 4,
  desc = "+100 Chips if Three of a Kind",
  icon = "Interface\\Icons\\Ability_Warrior_Cleave",
  onHand = function(ctx)
    if ctx.contains.THREE_KIND then return { chips = 100 } end
  end,
}

-- 13: Double Agent.
ns.Trinkets.add {
  id = "DOUBLE_AGENT", name = "Double Agent", rarity = "common", cost = 4,
  desc = "+80 Chips if Two Pair",
  icon = "Interface\\Icons\\INV_Misc_Gem_01",
  onHand = function(ctx)
    if ctx.contains.TWO_PAIR then return { chips = 80 } end
  end,
}

-- 14: Shadowstep.
ns.Trinkets.add {
  id = "SHADOWSTEP", name = "Shadowstep", rarity = "common", cost = 4,
  desc = "+100 Chips if Straight",
  icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
  onHand = function(ctx)
    if ctx.contains.STRAIGHT then return { chips = 100 } end
  end,
}

-- 15: Totemic Recall.
ns.Trinkets.add {
  id = "TOTEMIC_RECALL", name = "Totemic Recall", rarity = "common", cost = 4,
  desc = "+80 Chips if Flush",
  icon = "Interface\\Icons\\Spell_Nature_LightningShield",
  onHand = function(ctx)
    if ctx.contains.FLUSH then return { chips = 80 } end
  end,
}

-- 16: Gnomish Shrink Ray.
ns.Trinkets.add {
  id = "SHRINK_RAY", name = "Gnomish Shrink Ray", rarity = "common", cost = 5,
  desc = "+20 Mult if played hand has 3 or fewer cards",
  icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
  onHand = function(ctx)
    if #ctx.cards <= 3 then return { mult = 20 } end
  end,
}

-- 17: Spirit Healer.
ns.Trinkets.add {
  id = "SPIRIT_HEALER", name = "Spirit Healer", rarity = "uncommon", cost = 8,
  desc = "×1 Mult per empty trinket slot (Stencil counts as empty)",
  icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
  onHand = function(ctx)
    local empty = ctx.trinketSlots - #ctx.trinkets
    for _, trinket in ipairs(ctx.trinkets) do
      if trinket.id == "SPIRIT_HEALER" then empty = empty + 1 end
    end
    if empty > 1 then return { xmult = empty } end
  end,
}

-- 18: Sleight of Hand.
ns.Trinkets.add {
  id = "SLEIGHT_HAND", name = "Sleight of Hand", rarity = "uncommon", cost = 7,
  desc = "Flushes and Straights can be made with 4 cards",
  icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
  copyable = false, rule = "FOUR_FINGERS",
}

-- 19: Mirror Image.
ns.Trinkets.add {
  id = "MIRROR_IMAGE", name = "Mirror Image", rarity = "uncommon", cost = 5,
  desc = "Retrigger all held-in-hand abilities",
  icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
  heldRetrigger = function() return 1 end,
}

-- 23: Mount Hyjal.
ns.Trinkets.add {
  id = "MOUNT_HYJAL", name = "Mount Hyjal", rarity = "common", cost = 5,
  desc = "+15 Mult when 0 discards remaining",
  icon = "Interface\\Icons\\Spell_Nature_LightningShield",
  onHand = function(ctx)
    if ctx.discardsLeft == 0 then return { mult = 15 } end
  end,
}

-- 28: Eventide.
ns.Trinkets.add {
  id = "EVENTIDE", name = "Eventide", rarity = "uncommon", cost = 5,
  desc = "Retrigger all played cards in final hand of round",
  icon = "Interface\\Icons\\Spell_Holy_AvenginWrath",
  retrigger = function(ctx)
    if ctx.isLastHand then return 1 end
  end,
}

-- 29: Fist of Justice.
ns.Trinkets.add {
  id = "FIST_JUSTICE", name = "Fist of Justice", rarity = "common", cost = 5,
  desc = "Adds double the nominal value of the lowest held card to Mult (Ace 11, faces 10)",
  icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
  onHeld = function(ctx, _, card, heldIndex)
    local lowest, lowestIndex
    for i, held in ipairs(ctx.held) do
      if not ns.Cards.isStone(held) then
        local value = ns.Cards.chipValue(held)
        if not lowest or value <= lowest then lowest, lowestIndex = value, i end
      end
    end
    if heldIndex == lowestIndex then return { mult = 2 * ns.Cards.chipValue(card) } end
  end,
}

-- 31: Titanic Ratio.
ns.Trinkets.add {
  id = "TITANIC_RATIO", name = "Titanic Ratio", rarity = "uncommon", cost = 8,
  desc = "Played A, 2, 3, 5, 8 give +8 Mult",
  icon = "Interface\\Icons\\INV_Misc_Gem_01",
  onCard = function(_, _, card)
    local rank = card.rank
    if not ns.Cards.isStone(card) and (rank == 14 or rank == 2 or rank == 3 or rank == 5 or rank == 8) then
      return { mult = 8 }
    end
  end,
}

-- 36: Hack and Slash.
ns.Trinkets.add {
  id = "HACK_SLASH", name = "Hack and Slash", rarity = "uncommon", cost = 6,
  desc = "Retrigger played 2, 3, 4, 5",
  icon = "Interface\\Icons\\Ability_Warrior_Cleave",
  retrigger = function(_, _, card)
    if not ns.Cards.isStone(card) and card.rank >= 2 and card.rank <= 5 then return 1 end
  end,
}

-- 37: Mind Vision.
ns.Trinkets.add {
  id = "MIND_VISION", name = "Mind Vision", rarity = "uncommon", cost = 5,
  desc = "All cards count as face cards",
  icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
  copyable = false, rule = "PAREIDOLIA",
}

-- 39: Balance of Power.
ns.Trinkets.add {
  id = "BALANCE_POWER", name = "Balance of Power", rarity = "common", cost = 4,
  desc = "Played 10, 8, 6, 4, 2 give +4 Mult",
  icon = "Interface\\Icons\\Spell_Nature_LightningShield",
  onCard = function(_, _, card)
    if not ns.Cards.isStone(card) and card.rank >= 2 and card.rank <= 10 and card.rank % 2 == 0 then
      return { mult = 4 }
    end
  end,
}

-- 40: Odd Goblin.
ns.Trinkets.add {
  id = "ODD_GOBLIN", name = "Odd Goblin", rarity = "common", cost = 4,
  desc = "Played A, 9, 7, 5, 3 give +31 Chips",
  icon = "Interface\\Icons\\INV_Misc_Coin_01",
  onCard = function(_, _, card)
    local rank = card.rank
    if not ns.Cards.isStone(card) and (rank == 14 or rank == 3 or rank == 5 or rank == 7 or rank == 9) then
      return { chips = 31 }
    end
  end,
}

-- 42: Trade Prince Card.
ns.Trinkets.add {
  id = "TRADE_PRINCE", name = "Trade Prince Card", rarity = "common", cost = 4,
  desc = "Played face cards 1 in 2 to give 2g",
  icon = "Interface\\Icons\\INV_Misc_Coin_01",
  onCard = function(ctx, _, card)
    if ns.Cards.isFace(card, ctx.rules) and ns.Prob.roll(ctx.rng, ctx.trinkets, 1, 2) then
      return { gold = 2 }
    end
  end,
}

-- 43: Starfall.
ns.Trinkets.add {
  id = "STARFALL", name = "Starfall", rarity = "common", cost = 5,
  desc = "+Mult equal to times this hand type played this run",
  icon = "Interface\\Icons\\Spell_Nature_LightningShield",
  onHand = function(ctx) return { mult = (ctx.handPlays[ctx.handId] or 0) + 1 } end,
}

-- 44: Flight Path.
ns.Trinkets.add {
  id = "FLIGHT_PATH", name = "Flight Path", rarity = "common", cost = 6,
  desc = "+1 Mult per consecutive hand without a scoring face card (resets)",
  icon = "Interface\\Icons\\INV_Misc_Rune_01",
  init = function(self) self.state.mult = 0 end,
  before = function(ctx, self, isCopy)
    if isCopy then return end
    for _, i in ipairs(ctx.scoringIdx) do
      if ns.Cards.isFace(ctx.cards[i], ctx.rules) then
        self.state.mult = 0
        return
      end
    end
    self.state.mult = (self.state.mult or 0) + 1
  end,
  onHand = function(_, self)
    if (self.state.mult or 0) > 0 then return { mult = self.state.mult } end
  end,
  status = function(self) return "Currently +" .. (self.state.mult or 0) .. " Mult" end,
}

-- 45: Twisting Nether.
ns.Trinkets.add {
  id = "TWISTING_NETHER", name = "Twisting Nether", rarity = "uncommon", cost = 5,
  desc = "1 in 4 to level up played hand",
  icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
  before = function(ctx)
    if ns.Prob.roll(ctx.rng, ctx.trinkets, 1, 4) then return { levelHand = true } end
  end,
}

-- 52: Arcane Explosion.
ns.Trinkets.add {
  id = "ARCANE_EXPLOSION", name = "Arcane Explosion", rarity = "common", cost = 3,
  desc = "Every played card counts in scoring",
  icon = "Interface\\Icons\\Spell_Nature_LightningShield",
  copyable = false, rule = "SPLASH",
}
