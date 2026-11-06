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
  desc = "Played face cards {1} in 2 to give 2g",
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
  desc = "{1} in 4 to level up played hand",
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

-- Round targets are rolled only on acquisition and real round-end hooks.
local function rollAncientSuit(self, run)
  self.state.suit = ns.RNG.pick(run.rng, ns.Cards.SUITS)
end

local function rollIdolCard(self, run)
  local eligible = {}
  for _, card in ipairs(run.deck) do
    if not ns.Cards.isStone(card) then eligible[#eligible + 1] = card end
  end
  local card = #eligible > 0 and ns.RNG.pick(run.rng, eligible) or nil
  self.state.rank, self.state.suit = card and card.rank or nil, card and card.suit or nil
end

-- 48: Dark Pact.
ns.Trinkets.add {
  id = "DARK_PACT", name = "Dark Pact", rarity = "uncommon", cost = 6,
  desc = "×3 Mult if all held cards are Spades or Clubs",
  icon = "Interface\\Icons\\Spell_Shadow_DeathPact",
  onHand = function(ctx)
    for _, card in ipairs(ctx.held) do
      if not ns.Cards.hasSuit(card, "S", ctx.rules) and not ns.Cards.hasSuit(card, "C", ctx.rules) then return end
    end
    return { xmult = 3 }
  end,
}

-- 49: Sprint.
ns.Trinkets.add {
  id = "SPRINT", name = "Sprint", rarity = "common", cost = 5,
  desc = "Gains +15 Chips if hand contains a Straight",
  icon = "Interface\\Icons\\Ability_Rogue_Sprint",
  init = function(self) self.state.chips = 0 end,
  before = function(ctx, self, isCopy)
    if not isCopy and ctx.contains.STRAIGHT then self.state.chips = self.state.chips + 15 end
  end,
  onHand = function(_, self) return { chips = self.state.chips } end,
  status = function(self) return "Currently +" .. self.state.chips .. " Chips" end,
}

-- 50: Tigule's Ice Cream.
ns.Trinkets.add {
  id = "TIGULES", name = "Tigule's Ice Cream", rarity = "common", cost = 5,
  desc = "+100 Chips; -5 per hand played; melts at 0",
  icon = "Interface\\Icons\\INV_Misc_Food_11",
  init = function(self) self.state.chips = 100 end,
  onHand = function(_, self) return { chips = self.state.chips } end,
  after = function(_, self, isCopy)
    if isCopy then return end
    self.state.chips = self.state.chips - 5
    if self.state.chips <= 0 then return { destroySelf = true, msg = "Melted!" } end
  end,
  status = function(self) return "Currently +" .. self.state.chips .. " Chips" end,
}

-- 65: Four Winds.
ns.Trinkets.add {
  id = "FOUR_WINDS", name = "Four Winds", rarity = "common", cost = 4,
  desc = "Gains +4 Chips if hand has exactly 4 cards",
  icon = "Interface\\Icons\\Spell_Nature_LightningShield",
  init = function(self) self.state.chips = 0 end,
  before = function(ctx, self, isCopy)
    if not isCopy and #ctx.cards == 4 then self.state.chips = self.state.chips + 4 end
  end,
  onHand = function(_, self) return { chips = self.state.chips } end,
  status = function(self) return "Currently +" .. self.state.chips .. " Chips" end,
}

-- 69: Portal.
ns.Trinkets.add {
  id = "PORTAL", name = "Portal", rarity = "uncommon", cost = 7,
  desc = "Straights may skip one rank",
  icon = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
  copyable = false, rule = "SHORTCUT",
}

-- 72: Crown of the Kings.
ns.Trinkets.add {
  id = "CROWN_KINGS", name = "Crown of the Kings", rarity = "rare", cost = 8,
  desc = "Held Kings ×1.5 Mult each",
  icon = "Interface\\Icons\\INV_Crown_01",
  onHeld = function(_, _, card)
    if not ns.Cards.isStone(card) and card.rank == 13 then return { xmult = 1.5 } end
  end,
}

-- 75: Titan Obelisk.
ns.Trinkets.add {
  id = "OBELISK", name = "Titan Obelisk", rarity = "rare", cost = 8,
  desc = "Gains ×0.2 Mult per consecutive hand not of your most played type (resets)",
  icon = "Interface\\Icons\\INV_Misc_Rune_01",
  init = function(self) self.state.x = 1 end,
  before = function(ctx, self, isCopy)
    if isCopy then return end
    local played = (ctx.handPlays[ctx.handId] or 0) + 1
    local greatest = true
    for id, count in pairs(ctx.handPlays) do
      if id ~= ctx.handId and count >= played then greatest = false; break end
    end
    self.state.x = greatest and 1 or (self.state.x + 0.2)
  end,
  onHand = function(_, self) return { xmult = self.state.x } end,
  status = function(self) return "Currently ×" .. self.state.x .. " Mult" end,
}

-- 78: S.E.L.F.I.E. Camera.
ns.Trinkets.add {
  id = "SELFIE_CAMERA", name = "S.E.L.F.I.E. Camera", rarity = "common", cost = 5,
  desc = "First scoring face card ×2 Mult",
  icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
  onCard = function(ctx, _, card, index)
    if not ns.Cards.isFace(card, ctx.rules) then return end
    for _, i in ipairs(ctx.scoringIdx) do
      if ns.Cards.isFace(ctx.cards[i], ctx.rules) then
        if i == index then return { xmult = 2 } end
        return
      end
    end
  end,
}

-- 82: Stable Master.
ns.Trinkets.add {
  id = "STABLE_MASTER", name = "Stable Master", rarity = "common", cost = 6,
  desc = "Held face cards {1} in 2 to give 1g",
  icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
  onHeld = function(ctx, _, card)
    if ns.Cards.isFace(card, ctx.rules) and ns.Prob.roll(ctx.rng, ctx.trinkets, 1, 2) then
      return { gold = 1 }
    end
  end,
}

-- 92: Guild Charter.
ns.Trinkets.add {
  id = "GUILD_CHARTER", name = "Guild Charter", rarity = "rare", cost = 8,
  desc = "Uncommon trinkets each ×1.5 Mult",
  icon = "Interface\\Icons\\INV_Misc_Note_01",
  otherTrinket = function(_, _, otherDef)
    if otherDef.rarity == "uncommon" then return { xmult = 1.5 } end
  end,
}

-- 93: Tauren Charge.
ns.Trinkets.add {
  id = "TAUREN_CHARGE", name = "Tauren Charge", rarity = "uncommon", cost = 6,
  desc = "+2 Chips per 1g held",
  icon = "Interface\\Icons\\Ability_Warrior_Charge",
  onHand = function(ctx) return { chips = 2 * math.max(0, ctx.goldRef.gold) } end,
}

-- 98: Spare Tabard.
ns.Trinkets.add {
  id = "SPARE_TABARD", name = "Spare Tabard", rarity = "uncommon", cost = 6,
  desc = "Gains +2 Mult if hand contains Two Pair",
  icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
  init = function(self) self.state.mult = 0 end,
  before = function(ctx, self, isCopy)
    if not isCopy and ctx.contains.TWO_PAIR then self.state.mult = self.state.mult + 2 end
  end,
  onHand = function(_, self) return { mult = self.state.mult } end,
  status = function(self) return "Currently +" .. self.state.mult .. " Mult" end,
}

-- 99: Titan Relic.
ns.Trinkets.add {
  id = "TITAN_RELIC", name = "Titan Relic", rarity = "rare", cost = 8,
  desc = "Played [suit] ×1.5 Mult; suit changes each round",
  icon = "Interface\\Icons\\INV_Misc_Rune_01",
  init = rollAncientSuit,
  onCard = function(ctx, self, card)
    if ns.Cards.hasSuit(card, self.state.suit, ctx.rules) then return { xmult = 1.5 } end
  end,
  onRoundEnd = function(run, self, isCopy)
    if not isCopy then rollAncientSuit(self, run) end
  end,
  status = function(self) return "Suit: " .. ns.Cards.SUIT_NAMES[self.state.suit] end,
}

-- 101: Goblin Radio.
ns.Trinkets.add {
  id = "GOBLIN_RADIO", name = "Goblin Radio", rarity = "common", cost = 4,
  desc = "Played 10s and 4s +10 Chips +4 Mult",
  icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
  onCard = function(_, _, card)
    if not ns.Cards.isStone(card) and (card.rank == 10 or card.rank == 4) then
      return { chips = 10, mult = 4 }
    end
  end,
}

-- 102: Morning Glory Dew.
ns.Trinkets.add {
  id = "MORNING_DEW", name = "Morning Glory Dew", rarity = "uncommon", cost = 6,
  desc = "Retrigger all played cards for next 10 hands",
  icon = "Interface\\Icons\\INV_Drink_18",
  init = function(self) self.state.left = 10 end,
  retrigger = function() return 1 end,
  after = function(_, self, isCopy)
    if isCopy then return end
    self.state.left = self.state.left - 1
    if self.state.left <= 0 then return { destroySelf = true, msg = "Drunk!" } end
  end,
  status = function(self) return self.state.left .. " hands remaining" end,
}

-- 104: Cheerful Gnome.
ns.Trinkets.add {
  id = "CHEERFUL_GNOME", name = "Cheerful Gnome", rarity = "common", cost = 4,
  desc = "Played face cards +5 Mult",
  icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
  onCard = function(ctx, _, card)
    if ns.Cards.isFace(card, ctx.rules) then return { mult = 5 } end
  end,
}

-- 109: Court Jester.
ns.Trinkets.add {
  id = "COURT_JESTER", name = "Court Jester", rarity = "uncommon", cost = 6,
  desc = "Retrigger played face cards",
  icon = "Interface\\Icons\\INV_Misc_Mask_01",
  retrigger = function(ctx, _, card)
    if ns.Cards.isFace(card, ctx.rules) then return 1 end
  end,
}

-- 110: Bloodsail Buccaneer.
ns.Trinkets.add {
  id = "BLOODSAIL", name = "Bloodsail Buccaneer", rarity = "common", cost = 4,
  desc = "+Mult equal to total sell value of other trinkets",
  icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
  onHand = function(ctx, self)
    local mult = 0
    for _, trinket in ipairs(ctx.trinkets) do
      if trinket ~= self then mult = mult + ns.Shop.sellValue(trinket) end
    end
    return { mult = mult }
  end,
}

-- 113: Murky Ink.
ns.Trinkets.add {
  id = "MURKY_INK", name = "Murky Ink", rarity = "uncommon", cost = 7,
  desc = "Hearts=Diamonds, Spades=Clubs",
  icon = "Interface\\Icons\\INV_Inscription_InkBlack01",
  copyable = false, rule = "SMEARED",
}

-- 115: Echo of Doom.
ns.Trinkets.add {
  id = "ECHO_DOOM", name = "Echo of Doom", rarity = "common", cost = 4,
  desc = "Retrigger first scoring card 2 more times",
  icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
  retrigger = function(ctx, _, _, index)
    if index == ctx.scoringIdx[1] then return 2 end
  end,
}

-- 116: Uncut Gem.
ns.Trinkets.add {
  id = "UNCUT_GEM", name = "Uncut Gem", rarity = "uncommon", cost = 7,
  desc = "Played Diamonds give 1g",
  icon = "Interface\\Icons\\INV_Misc_Gem_01",
  onCard = function(ctx, _, card)
    if ns.Cards.hasSuit(card, "D", ctx.rules) then return { gold = 1 } end
  end,
}

-- 117: Bloodstone.
ns.Trinkets.add {
  id = "BLOODSTONE", name = "Bloodstone", rarity = "uncommon", cost = 7,
  desc = "Played Hearts {1} in 2 for ×1.5 Mult",
  icon = "Interface\\Icons\\INV_Misc_Gem_Bloodstone_01",
  onCard = function(ctx, _, card)
    if ns.Cards.hasSuit(card, "H", ctx.rules) and ns.Prob.roll(ctx.rng, ctx.trinkets, 1, 2) then
      return { xmult = 1.5 }
    end
  end,
}

-- 118: Rugged Arrowhead.
ns.Trinkets.add {
  id = "ARROWHEAD", name = "Rugged Arrowhead", rarity = "uncommon", cost = 7,
  desc = "Played Spades +50 Chips",
  icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
  onCard = function(ctx, _, card)
    if ns.Cards.hasSuit(card, "S", ctx.rules) then return { chips = 50 } end
  end,
}

-- 119: Shadowgem.
ns.Trinkets.add {
  id = "SHADOWGEM", name = "Shadowgem", rarity = "uncommon", cost = 7,
  desc = "Played Clubs +7 Mult",
  icon = "Interface\\Icons\\INV_Misc_Gem_01",
  onCard = function(ctx, _, card)
    if ns.Cards.hasSuit(card, "C", ctx.rules) then return { mult = 7 } end
  end,
}

-- 122: Peacebloom Pot.
ns.Trinkets.add {
  id = "PEACEBLOOM", name = "Peacebloom Pot", rarity = "uncommon", cost = 6,
  desc = "×3 Mult if hand has a Diamond, Club, Heart and Spade scoring",
  icon = "Interface\\Icons\\INV_Misc_Flower_02",
  onHand = function(ctx)
    local suits, wilds, count = {}, 0, 0
    for _, i in ipairs(ctx.scoringIdx) do
      local card = ctx.cards[i]
      if not ns.Cards.isStone(card) then
        if card.enh == "WILD" then
          wilds = wilds + 1
        else
          local suit = card.suit
          if not suits[suit] then
            suits[suit], count = true, count + 1
          else
            for _, missing in ipairs(ns.Cards.SUITS) do
              if not suits[missing] and ns.Cards.hasSuit(card, missing, ctx.rules) then
                suits[missing], count = true, count + 1
                break
              end
            end
          end
        end
      end
    end
    if count + wilds >= 4 then return { xmult = 3 } end
  end,
}

-- 123: Engineering Schematic.
ns.Trinkets.add {
  id = "SCHEMATIC", name = "Engineering Schematic", rarity = "rare", cost = 10,
  desc = "Copies trinket to the right",
  icon = "Interface\\Icons\\INV_Misc_Enggizmos_01",
  copies = "right",
}

-- 124: Tiny Gnome.
ns.Trinkets.add {
  id = "TINY_GNOME", name = "Tiny Gnome", rarity = "rare", cost = 8,
  desc = "Gains +8 Chips per played 2 scored",
  icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
  init = function(self) self.state.chips = 0 end,
  onCard = function(_, self, card, _, isCopy)
    if not isCopy and not ns.Cards.isStone(card) and card.rank == 2 then
      self.state.chips = self.state.chips + 8
      return { msg = "Upgrade!" }
    end
  end,
  onHand = function(_, self) return { chips = self.state.chips } end,
  status = function(self) return "Currently +" .. self.state.chips .. " Chips" end,
}

-- 126: Loaded Dice.
ns.Trinkets.add {
  id = "LOADED_DICE", name = "Loaded Dice", rarity = "uncommon", cost = 4,
  desc = "Doubles all listed probabilities",
  icon = "Interface\\Icons\\INV_Misc_Coin_01",
  copyable = false, rule = "OOPS",
}

-- 127: Zandalari Idol.
ns.Trinkets.add {
  id = "ZANDALARI_IDOL", name = "Zandalari Idol", rarity = "uncommon", cost = 6,
  desc = "Played [rank] of [suit] ×2 Mult; changes each round",
  icon = "Interface\\Icons\\INV_Misc_Rune_01",
  init = rollIdolCard,
  onCard = function(ctx, self, card)
    if self.state.rank and not ns.Cards.isStone(card) and card.rank == self.state.rank
      and ns.Cards.hasSuit(card, self.state.suit, ctx.rules) then return { xmult = 2 } end
  end,
  onRoundEnd = function(run, self, isCopy)
    if not isCopy then rollIdolCard(self, run) end
  end,
  status = function(self)
    if not self.state.rank then return "Card: None" end
    return "Card: " .. ns.Cards.label(self.state) .. " of " .. ns.Cards.SUIT_NAMES[self.state.suit]
  end,
}

-- 128: Double Vision.
ns.Trinkets.add {
  id = "DOUBLE_VISION", name = "Double Vision", rarity = "uncommon", cost = 6,
  desc = "×2 Mult if scoring has a Club and a non-Club",
  icon = "Interface\\Icons\\Ability_DualWield",
  onHand = function(ctx)
    for _, i in ipairs(ctx.scoringIdx) do
      if ns.Cards.hasSuit(ctx.cards[i], "C", ctx.rules) then
        for _, j in ipairs(ctx.scoringIdx) do
          local card = ctx.cards[j]
          if i ~= j and (ns.Cards.hasSuit(card, "S", ctx.rules)
            or ns.Cards.hasSuit(card, "H", ctx.rules) or ns.Cards.hasSuit(card, "D", ctx.rules)) then
            return { xmult = 2 }
          end
        end
      end
    end
  end,
}

-- 131: The Twin Val'kyr.
ns.Trinkets.add {
  id = "TWIN_VALKYR", name = "The Twin Val'kyr", rarity = "rare", cost = 8,
  desc = "×2 Mult if Pair",
  icon = "Interface\\Icons\\Ability_DualWield",
  onHand = function(ctx)
    if ctx.contains.PAIR then return { xmult = 2 } end
  end,
}

-- 132: Council of Three.
ns.Trinkets.add {
  id = "COUNCIL_THREE", name = "Council of Three", rarity = "rare", cost = 8,
  desc = "×3 Mult if Three of a Kind",
  icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
  onHand = function(ctx)
    if ctx.contains.THREE_KIND then return { xmult = 3 } end
  end,
}

-- 133: The Four Horsemen.
ns.Trinkets.add {
  id = "FOUR_HORSEMEN", name = "The Four Horsemen", rarity = "rare", cost = 8,
  desc = "×4 Mult if Four of a Kind",
  icon = "Interface\\Icons\\Ability_Warrior_Cleave",
  onHand = function(ctx)
    if ctx.contains.FOUR_KIND then return { xmult = 4 } end
  end,
}

-- 134: The Silver Hand.
ns.Trinkets.add {
  id = "SILVER_HAND", name = "The Silver Hand", rarity = "rare", cost = 8,
  desc = "×3 Mult if Straight",
  icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
  onHand = function(ctx)
    if ctx.contains.STRAIGHT then return { xmult = 3 } end
  end,
}

-- 135: The Horde.
ns.Trinkets.add {
  id = "THE_HORDE", name = "The Horde", rarity = "rare", cost = 8,
  desc = "×2 Mult if Flush",
  icon = "Interface\\Icons\\INV_Shield_06",
  onHand = function(ctx)
    if ctx.contains.FLUSH then return { xmult = 2 } end
  end,
}

-- 138: Mind Control.
ns.Trinkets.add {
  id = "MIND_CONTROL", name = "Mind Control", rarity = "rare", cost = 10,
  desc = "Copies leftmost trinket",
  icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate",
  copies = "leftmost",
}

-- 140: Moonfire.
ns.Trinkets.add {
  id = "MOONFIRE", name = "Moonfire", rarity = "common", cost = 5,
  desc = "Held Queens +13 Mult each",
  icon = "Interface\\Icons\\Spell_Nature_StarFall",
  onHeld = function(_, _, card)
    if not ns.Cards.isStone(card) and card.rank == 12 then return { mult = 13 } end
  end,
}
