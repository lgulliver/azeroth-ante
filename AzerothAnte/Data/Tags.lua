local _, ns = ...

-- Skip tags: skipping a small or big blind gives that blind's tag (Run.skipBlind). Each stage rolls
-- one tag per skippable blind from the defs its minStage allows (Tags.roll in Core/Tags.lua).
-- Hooks (all optional; one returning true consumes the tag): onTake(run) when the tag is taken,
-- onShopOpen(run), onBlindStart(run), onBossDefeated(run), onGiftClosed(run), fired through Tags.fire.
local Tags = {}

local function gain(run, gold)
  run.gold = run.gold + gold
  return true
end

-- Recruit-a-Friend: up to two commons, each into a free slot (a Negative one makes its own).
local function topUp(run)
  local taken = {}
  for _ = 1, 2 do
    if #run.trinkets >= ns.Run.trinketSlots(run) then break end
    local item = ns.Shop.rollTrinket(run, taken, "common")
    if not item then break end
    run.trinkets[#run.trinkets + 1] = ns.Trinkets.create(run, item.id, item.ed)
    if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain("trinket", item.id) end
  end
  return true
end

Tags.order = {
  "UNCOMMON", "RARE", "NEGATIVE", "FOIL", "HOLO", "POLY", "INVESTMENT", "VOUCHER", "BOSS", "STANDARD",
  "CHARM", "METEOR", "BUFFOON", "ETHEREAL", "HANDY", "GARBAGE", "COUPON", "DOUBLE", "JUGGLE", "D6",
  "TOPUP", "SPEED", "ORBITAL", "ECONOMY",
}

Tags.def = {
  UNCOMMON = {
    id = "UNCOMMON", name = "Uncommon Quest Reward", minStage = 1, -- Uncommon
    desc = "Next shop has a free uncommon trinket",
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Green",
  },
  RARE = {
    id = "RARE", name = "Rare Quest Reward", minStage = 1, -- Rare
    desc = "Next shop has a free rare trinket",
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
  },
  NEGATIVE = {
    id = "NEGATIVE", name = "Void-Touched Reward", minStage = 2, -- Negative
    desc = "Next base-edition shop trinket becomes Negative and free",
    icon = "Interface\\Icons\\Spell_Shadow_SealOfKings",
  },
  FOIL = {
    id = "FOIL", name = "Gilded Reward", minStage = 1, -- Foil
    desc = "Next base-edition shop trinket becomes Foil and free",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
  },
  HOLO = {
    id = "HOLO", name = "Prismatic Reward", minStage = 1, -- Holographic
    desc = "Next base-edition shop trinket becomes Holographic and free",
    icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
  },
  POLY = {
    id = "POLY", name = "Titanforged Reward", minStage = 1, -- Polychrome
    desc = "Next base-edition shop trinket becomes Polychrome and free",
    icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
  },
  INVESTMENT = {
    id = "INVESTMENT", name = "Goblin Investment", minStage = 1, -- Investment
    desc = "Gain 25g after defeating the next boss",
    icon = "Interface\\Icons\\INV_Misc_Coin_17",
  },
  VOUCHER = {
    id = "VOUCHER", name = "Vendor Restock", minStage = 1, -- Voucher
    desc = "Adds a voucher to the next shop",
    icon = "Interface\\Icons\\INV_Misc_Note_02",
  },
  BOSS = {
    id = "BOSS", name = "Wanted Poster", minStage = 1, -- Boss
    desc = "Rerolls the boss blind",
    icon = "Interface\\Icons\\INV_Misc_Note_06",
    onTake = function(run) ns.Run.redrawBoss(run); return true end,
  },
  STANDARD = {
    id = "STANDARD", name = "Darkmoon Card Gift", minStage = 2, -- Standard
    desc = "Free Heavy Darkmoon Card Bundle",
    icon = "Interface\\Icons\\INV_Misc_Ticket_Tarot_Maelstrom_01",
  },
  CHARM = {
    id = "CHARM", name = "Scribe's Gift", minStage = 1, -- Charm
    desc = "Free Heavy Scribe's Satchel",
    icon = "Interface\\Icons\\INV_Inscription_Scroll",
  },
  METEOR = {
    id = "METEOR", name = "Archivist's Gift", minStage = 2, -- Meteor
    desc = "Free Heavy Archivist's Crate",
    icon = "Interface\\Icons\\INV_Misc_Book_09",
  },
  BUFFOON = {
    id = "BUFFOON", name = "Lockbox Key", minStage = 2, -- Buffoon
    desc = "Free Heavy Trinket Lockbox",
    icon = "Interface\\Icons\\INV_Misc_Key_03",
  },
  ETHEREAL = {
    id = "ETHEREAL", name = "Relic Hunter's Gift", minStage = 2, -- Ethereal
    desc = "Free Relic Cache",
    icon = "Interface\\Icons\\INV_Misc_Idol_02",
  },
  HANDY = {
    id = "HANDY", name = "Veteran's Pay", minStage = 2, -- Handy
    desc = "1g per hand played this run",
    icon = "Interface\\Icons\\INV_Gauntlets_04",
    onTake = function(run) return gain(run, run.handsPlayedTotal) end,
  },
  GARBAGE = {
    id = "GARBAGE", name = "Scrapper's Pay", minStage = 2, -- Garbage
    desc = "1g per unused discard this run",
    icon = "Interface\\Icons\\INV_Gizmo_02",
    onTake = function(run) return gain(run, run.discardsUnusedTotal) end,
  },
  COUPON = {
    id = "COUPON", name = "Darkmoon Faire Coupon", minStage = 1, -- Coupon
    desc = "Initial cards and packs in the next shop are free",
    icon = "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01",
  },
  DOUBLE = {
    id = "DOUBLE", name = "Bonus Roll", minStage = 1, -- Double
    desc = "Copies the next tag taken (not another Bonus Roll)",
    icon = "Interface\\Icons\\INV_Misc_Dice_01",
  },
  JUGGLE = {
    id = "JUGGLE", name = "Juggler's Gloves", minStage = 1, -- Juggle
    desc = "+3 hand size next round",
    icon = "Interface\\Icons\\INV_Gauntlets_17",
  },
  D6 = {
    id = "D6", name = "Heirloom Dice", minStage = 1, -- D6
    desc = "Rerolls in the next shop start at 0g",
    icon = "Interface\\Icons\\INV_Misc_Dice_02",
  },
  TOPUP = {
    id = "TOPUP", name = "Recruit-a-Friend", minStage = 2, -- Top-up
    desc = "Create up to 2 common trinkets (needs free slots)",
    icon = "Interface\\Icons\\Achievement_Reputation_01",
    onTake = topUp,
  },
  SPEED = {
    id = "SPEED", name = "Flight Master's Whistle", minStage = 1, -- Speed
    desc = "5g per blind skipped this run",
    icon = "Interface\\Icons\\Ability_Mount_Gryphon_01",
    onTake = function(run) return gain(run, 5 * run.skips) end,
  },
  ORBITAL = {
    id = "ORBITAL", name = "Algalon's Insight", minStage = 2, -- Orbital
    desc = "Levels up a random hand three times",
    icon = "Interface\\Icons\\Spell_Arcane_StarFire",
    onTake = function(run)
      local handId = ns.RNG.pick(run.rng, ns.Hands.visible(run))
      run.handLevels[handId] = run.handLevels[handId] + 3
      return true
    end,
  },
  ECONOMY = {
    id = "ECONOMY", name = "Auction House Flip", minStage = 1, -- Economy
    desc = "Doubles your gold (max +40g)",
    icon = "Interface\\Icons\\INV_Misc_Coin_04",
    onTake = function(run) return gain(run, math.min(math.max(run.gold, 0), 40)) end,
  },
}

-- Pack tags open their pack at once, free (Heavy, or a normal Relic Cache). One that finds a pack
-- open stays held and opens its own when that one closes.
local GIFTS = {
  STANDARD = { "STANDARD", "mega" }, CHARM = { "ARCANA", "mega" }, METEOR = { "CELESTIAL", "mega" },
  BUFFOON = { "BUFFOON", "mega" }, ETHEREAL = { "SPECTRAL", "normal" },
}
for id, gift in pairs(GIFTS) do
  local function open(run) return ns.Packs.openGift(run, gift[1], gift[2]) end
  Tags.def[id].onTake, Tags.def[id].onGiftClosed = open, open
end

ns.Tags = Tags
