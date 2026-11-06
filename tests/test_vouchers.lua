local _, ns = ...

-- The test harness passes the namespace first and assertions second.
local T = ns
ns = _

local voucherPairs = {
  { "OVERSTOCK", "OVERSTOCK_PLUS", "Bulging Saddlebags", "Bottomless Bags" },
  { "CLEARANCE_SALE", "LIQUIDATION", "Goblin Discount", "Auction House Crash" },
  { "HONE", "GLOW_UP", "Enchanter's Whetstone", "Arcane Infusion" },
  { "REROLL_SURPLUS", "REROLL_GLUT", "Lucky Coin", "Gambler's Charm" },
  { "CRYSTAL_BALL", "OMEN_GLOBE", "Scrying Orb", "Seer's Orb" },
  { "TELESCOPE", "OBSERVATORY", "Astrolabe", "Observatory of the Stars" },
  { "GRABBER", "NACHO_TONG", "Extra Ammo Pouch", "Quiver of Plenty" },
  { "WASTEFUL", "RECYCLOMANCY", "Scavenger's Sack", "Junk Golem" },
  { "TAROT_MERCHANT", "TAROT_TYCOON", "Scribe's Stall", "Inscription Guild" },
  { "PLANET_MERCHANT", "PLANET_TYCOON", "Librarian's Cart", "Grand Library" },
  { "SEED_MONEY", "MONEY_TREE", "Savings Pouch", "Goblin Vault" },
  { "BLANK", "ANTIMATTER", "Empty Gem Socket", "Void Socket" },
  { "MAGIC_TRICK", "ILLUSION", "Card Sharp's Sleeve", "Illusionist's Deck" },
  { "HIEROGLYPH", "PETROGLYPH", "Chronomancer's Hourglass", "Bronze Hourglass" },
  { "DIRECTORS_CUT", "RETCON", "Bounty Board", "Infinite Bounty" },
  { "PAINT_BRUSH", "PALETTE", "Bag of Holding", "Greater Bag of Holding" },
}

T.test("catalog_32", function()
  T.ok(ns.Vouchers, "voucher module missing")
  T.eq(#ns.Vouchers.order, 32)
  local seen = {}
  for i, pair in ipairs(voucherPairs) do
    for tier = 1, 2 do
      local id = pair[tier]
      T.eq(ns.Vouchers.order[(i - 1) * 2 + tier], id)
      T.ok(not seen[id], "duplicate voucher")
      seen[id] = true
      local def = ns.Vouchers.def[id]
      T.eq(def.id, id)
      T.eq(def.name, pair[tier + 2])
      T.eq(def.wowName, pair[tier + 2])
      T.eq(def.tier, tier)
      T.eq(def.cost, 10)
      T.ok(type(def.desc) == "string" and #def.desc > 0)
      T.eq(def.base, tier == 2 and pair[1] or nil)
      T.eq(def.upgrade, tier == 1 and pair[2] or nil)
      T.eq(def.achievement, tier == 2 and id or nil)
    end
  end
end)

local function owned(ids)
  local run = { vouchers = {} }
  for _, id in ipairs(ids) do run.vouchers[id] = true end
  return run
end

T.test("owns", function()
  T.eq(ns.Vouchers.owns(owned({}), "BLANK"), false)
  T.eq(ns.Vouchers.owns(owned({ "BLANK" }), "BLANK"), true)
  T.eq(ns.Vouchers.owns({ vouchers = { BLANK = false } }, "BLANK"), false)
end)

local queries = {
  { "shopCardSlots", 2, "OVERSTOCK", 3, "OVERSTOCK_PLUS", 4 },
  { "discount", 0, "CLEARANCE_SALE", 0.25, "LIQUIDATION", 0.5 },
  { "rerollDelta", 0, "REROLL_SURPLUS", 2, "REROLL_GLUT", 4 },
  { "editionMult", 1, "HONE", 2, "GLOW_UP", 4 },
  { "scrollWeight", 4, "TAROT_MERCHANT", 9.6, "TAROT_TYCOON", 32 },
  { "tomeWeight", 4, "PLANET_MERCHANT", 9.6, "PLANET_TYCOON", 32 },
  { "interestCap", 5, "SEED_MONEY", 10, "MONEY_TREE", 20 },
  { "extraHands", 0, "GRABBER", 1, "NACHO_TONG", 2 },
  { "extraDiscards", 0, "WASTEFUL", 1, "RECYCLOMANCY", 2 },
  { "extraHandSize", 0, "PAINT_BRUSH", 1, "PALETTE", 2 },
  { "extraConsumables", 0, "CRYSTAL_BALL", 1, "OMEN_GLOBE", 1 },
  { "extraTrinkets", 0, "BLANK", 0, "ANTIMATTER", 1 },
  { "bossRerolls", 0, "DIRECTORS_CUT", 1, "RETCON", math.huge },
}
for _, row in ipairs(queries) do
  local case = row
  T.test(case[1], function()
    local query = ns.Vouchers[case[1]]
    T.eq(query(owned({})), case[2])
    T.eq(query(owned({ case[3] })), case[4])
    T.eq(query(owned({ case[3], case[5] })), case[6])
  end)
end

local flags = {
  { "playingCardsInShop", "MAGIC_TRICK" }, { "illusion", "ILLUSION" },
  { "omenGlobe", "OMEN_GLOBE" }, { "telescope", "TELESCOPE" },
  { "observatory", "OBSERVATORY" },
}
for _, row in ipairs(flags) do
  local case = row
  T.test(case[1], function()
    T.eq(ns.Vouchers[case[1]](owned({})), false)
    T.eq(ns.Vouchers[case[1]](owned({ "BLANK" })), false)
    T.eq(ns.Vouchers[case[1]](owned({ case[2] })), true)
  end)
end

T.test("price_rounding", function()
  T.eq(ns.Vouchers.price(owned({}), 10), 10)
  local sale = owned({ "CLEARANCE_SALE" })
  T.eq(ns.Vouchers.price(sale, 10), 8)
  T.eq(ns.Vouchers.price(sale, 6), 5)
  local liquidation = owned({ "CLEARANCE_SALE", "LIQUIDATION" })
  T.eq(ns.Vouchers.price(liquidation, 3), 2)
  T.eq(ns.Vouchers.price(liquidation, 1), 1)
  T.eq(ns.Vouchers.price(liquidation, 0), 1)
end)

T.test("hourglass_penalties", function()
  local run = owned({ "HIEROGLYPH" })
  T.eq(ns.Vouchers.extraHands(run), -1)
  T.eq(ns.Vouchers.extraDiscards(run), 0)
  run.vouchers.PETROGLYPH = true
  T.eq(ns.Vouchers.extraHands(run), -1)
  T.eq(ns.Vouchers.extraDiscards(run), -1)
  run.vouchers.GRABBER, run.vouchers.NACHO_TONG = true, true
  run.vouchers.WASTEFUL, run.vouchers.RECYCLOMANCY = true, true
  T.eq(ns.Vouchers.extraHands(run), 1)
  T.eq(ns.Vouchers.extraDiscards(run), 1)
end)

T.test("onBuy", function()
  for _, pair in ipairs(voucherPairs) do
    for tier = 1, 2 do
      local id = pair[tier]
      local run = owned({ id })
      run.stage, run.blind, run.gold = 3, 2, 20
      ns.Vouchers.onBuy(run, id)
      T.eq(run.stage, (id == "HIEROGLYPH" or id == "PETROGLYPH") and 2 or 3)
      T.eq(run.blind, 2)
      T.eq(run.gold, 20)
      T.eq(run.vouchers, owned({ id }).vouchers)
    end
  end
  for _, id in ipairs({ "HIEROGLYPH", "PETROGLYPH" }) do
    local run = { stage = 1 }
    ns.Vouchers.onBuy(run, id)
    T.eq(run.stage, 1)
  end
end)

local function defaults(run)
  T.eq(run.vouchers, {})
  T.eq(run.shopVoucher, nil)
  T.eq(run.handPlays, {})
  T.eq(run.bossRerollsUsed, 0)
  T.eq(run.bossesFought, {})
  T.eq(run.streak, { maxInterest = 0 })
end

T.test("new_run_fields", function()
  local run = ns.Run.new(7, "ROGUE")
  defaults(run)
  run.vouchers.BLANK = true
  run.streak.maxInterest = 9
  defaults(ns.Run.new(8, "ROGUE"))
end)

T.test("v2_save_migrates", function()
  T.eq(ns.Save.VERSION, 3)
  local run = ns.Run.new(7, "ROGUE")
  ns.Run.startBlind(run)
  local control = ns.Run.new(7, "ROGUE")
  ns.Run.startBlind(control)
  run.vouchers, run.shopVoucher, run.handPlays = nil, nil, nil
  run.bossRerollsUsed, run.bossesFought, run.streak = nil, nil, nil
  local db = {}
  ns.Save.store(db, run)
  db.version = 2
  local loaded = ns.Save.load(db)
  T.ok(loaded ~= nil)
  defaults(loaded)
  T.eq(loaded.stage, run.stage)
  T.eq(loaded.rng, run.rng)
  T.ok(rawequal(loaded.hand[1], ns.Deck.find(loaded, loaded.hand[1].id)))
  T.ok(db.run.vouchers == nil, "migration mutated saved data")
  T.eq(ns.Run.play(loaded, { 1 }), ns.Run.play(control, { 1 }))
end)

T.test("v2_save_in_shop_gets_a_voucher", function()
  local run = ns.Run.new(7, "ROGUE")
  ns.Run.startBlind(run)
  ns.Run.winBlind(run)
  T.eq(run.phase, "shop")
  run.shopVoucher = nil
  local db = {}
  ns.Save.store(db, run)
  db.version = 2
  local loaded = ns.Save.load(db)
  T.ok(type(loaded.shopVoucher) == "table" and ns.Vouchers.def[loaded.shopVoucher.id] ~= nil, "a voucher was rolled")
  -- Outside the shop it stays unset, and an existing offer is kept.
  local play = ns.Run.new(7, "ROGUE")
  ns.Run.startBlind(play)
  ns.Save.store(db, play)
  db.version = 2
  T.eq(ns.Save.load(db).shopVoucher, nil)
  run.shopVoucher = false
  ns.Save.store(db, run)
  db.version = 2
  T.eq(ns.Save.load(db).shopVoucher, false)
end)

T.test("v3_save_preserves_voucher_state", function()
  local run = ns.Run.new(7, "ROGUE")
  run.vouchers.BLANK = true
  run.shopVoucher = { id = "GRABBER", cost = 10 }
  run.handPlays.PAIR = 3
  run.bossRerollsUsed = 1
  run.bossesFought[run.bosses[1]] = true
  run.streak.maxInterest = 4
  local db = {}
  ns.Save.store(db, run)
  T.eq(db.version, 3)
  local loaded = ns.Save.load(db)
  T.eq(loaded, run)
  loaded.vouchers.BLANK = nil
  T.eq(db.run.vouchers.BLANK, true)
  run.shopVoucher = false
  ns.Save.store(db, run)
  T.eq(ns.Save.load(db).shopVoucher, false)
end)
