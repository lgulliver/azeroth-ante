local _, ns = ...

local Vouchers = { order = {}, def = {} }

local function pair(base, name, desc, upgrade, upgradeName, upgradeDesc)
  Vouchers.order[#Vouchers.order + 1] = base
  Vouchers.order[#Vouchers.order + 1] = upgrade
  Vouchers.def[base] = {
    id = base, name = name, wowName = name, desc = desc,
    tier = 1, upgrade = upgrade, cost = 10,
  }
  Vouchers.def[upgrade] = {
    id = upgrade, name = upgradeName, wowName = upgradeName, desc = upgradeDesc,
    tier = 2, base = base, achievement = upgrade, cost = 10,
  }
end

pair("OVERSTOCK", "Bulging Saddlebags", "+1 shop card slot",
  "OVERSTOCK_PLUS", "Bottomless Bags", "+1 more shop card slot")
pair("CLEARANCE_SALE", "Goblin Discount", "Shop items 25% off",
  "LIQUIDATION", "Auction House Crash", "Shop items 50% off")
pair("HONE", "Enchanter's Whetstone", "Foil/Holo/Poly appear 2×",
  "GLOW_UP", "Arcane Infusion", "Foil/Holo/Poly appear 4×")
pair("REROLL_SURPLUS", "Lucky Coin", "Rerolls $2 cheaper",
  "REROLL_GLUT", "Gambler's Charm", "Rerolls another $2 cheaper")
pair("CRYSTAL_BALL", "Scrying Orb", "+1 consumable slot",
  "OMEN_GLOBE", "Seer's Orb", "Relics can appear in Arcana packs")
pair("TELESCOPE", "Astrolabe", "Celestial packs always include the Tome of your most-played hand",
  "OBSERVATORY", "Observatory of the Stars", "Tomes held in consumable slots give ×1.5 mult when their hand is played")
pair("GRABBER", "Extra Ammo Pouch", "+1 hand per round",
  "NACHO_TONG", "Quiver of Plenty", "+1 more hand per round")
pair("WASTEFUL", "Scavenger's Sack", "+1 discard per round",
  "RECYCLOMANCY", "Junk Golem", "+1 more discard per round")
pair("TAROT_MERCHANT", "Scribe's Stall", "Scrolls appear more often in the shop (weight 4 → 9.6)",
  "TAROT_TYCOON", "Inscription Guild", "Scroll shop weight → 32")
pair("PLANET_MERCHANT", "Librarian's Cart", "Tomes appear more often in the shop (weight 4 → 9.6)",
  "PLANET_TYCOON", "Grand Library", "Tome shop weight → 32")
pair("SEED_MONEY", "Savings Pouch", "Interest cap $5 → $10",
  "MONEY_TREE", "Goblin Vault", "Interest cap → $20")
pair("BLANK", "Empty Gem Socket", "Does nothing",
  "ANTIMATTER", "Void Socket", "+1 trinket slot")
pair("MAGIC_TRICK", "Card Sharp's Sleeve", "Playing cards can appear in the shop (card slot type weight 4)",
  "ILLUSION", "Illusionist's Deck", "Shop playing cards may carry an enhancement, edition or seal")
pair("HIEROGLYPH", "Chronomancer's Hourglass", "−1 stage (repeat a stage), −1 hand per round",
  "PETROGLYPH", "Bronze Hourglass", "−1 stage, −1 discard per round")
pair("DIRECTORS_CUT", "Bounty Board", "Reroll the boss once per stage, $10",
  "RETCON", "Infinite Bounty", "Unlimited boss rerolls, $10 each")
pair("PAINT_BRUSH", "Bag of Holding", "+1 hand size",
  "PALETTE", "Greater Bag of Holding", "+1 more hand size")

ns.Vouchers = Vouchers
