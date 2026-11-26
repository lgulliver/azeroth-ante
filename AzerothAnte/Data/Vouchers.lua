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
pair("REROLL_SURPLUS", "Darkmoon Prize Ticket", "Rerolls 2g cheaper",
  "REROLL_GLUT", "Darkmoon Faire Token", "Rerolls another 2g cheaper")
pair("CRYSTAL_BALL", "Dalaran Crystal Ball", "+1 consumable slot",
  "OMEN_GLOBE", "Orb of the Kirin Tor", "Relics can appear in Scribe's Satchels")
pair("TELESCOPE", "Titan Orrery", "Archivist's Crates always include the Tome of your most-played hand",
  "OBSERVATORY", "Algalon's Planetarium", "Tomes held in consumable slots give ×1.5 mult when their hand is played")
pair("GRABBER", "Extra Ammo Pouch", "+1 hand per round",
  "NACHO_TONG", "Quiver of Plenty", "+1 more hand per round")
pair("WASTEFUL", "Scavenger's Sack", "+1 discard per round",
  "RECYCLOMANCY", "Mechagon Scrapbot", "+1 more discard per round")
pair("TAROT_MERCHANT", "Scribe's Stall", "Scrolls appear more often in the shop (weight 4 to 9.6)",
  "TAROT_TYCOON", "Inscription Guild", "Scroll shop weight to 32")
pair("PLANET_MERCHANT", "Karazhan Library Cart", "Tomes appear more often in the shop (weight 4 to 9.6)",
  "PLANET_TYCOON", "Guardian's Library", "Tome shop weight to 32")
pair("SEED_MONEY", "Guild Bank Tab", "Interest cap 5g to 10g",
  "MONEY_TREE", "Goblin Vault", "Interest cap to 20g")
pair("BLANK", "Empty Gem Socket", "Does nothing",
  "ANTIMATTER", "Void Socket", "+1 trinket slot")
pair("MAGIC_TRICK", "Darkmoon Card Sleeve", "Playing cards can appear in the shop (card slot type weight 4)",
  "ILLUSION", "Darkmoon Deck", "Shop playing cards may carry an enhancement or edition")
pair("HIEROGLYPH", "Chronomancer's Hourglass", "-1 stage (repeat a stage), -1 hand per round",
  "PETROGLYPH", "Bronze Hourglass", "-1 stage, -1 discard per round")
pair("DIRECTORS_CUT", "Bounty Board", "Reroll the boss once per stage, 10g",
  "RETCON", "Infinite Bounty", "Unlimited boss rerolls, 10g each")
pair("PAINT_BRUSH", "Netherweave Bag", "+1 hand size",
  "PALETTE", "Frostweave Bag", "+1 more hand size")

ns.Vouchers = Vouchers
