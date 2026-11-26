local ns, T = ...

T.test("tags_defs_complete", function()
  T.eq(#ns.Tags.order, 24)
  for _, id in ipairs(ns.Tags.order) do
    local def = ns.Tags.def[id]
    T.ok(def and def.id == id, id .. " def")
    T.ok(type(def.name) == "string" and type(def.desc) == "string" and type(def.icon) == "string", id .. " fields")
    T.ok(def.minStage == 1 or def.minStage == 2, id .. " minStage")
  end
end)

T.test("blind_tags_rolled_per_ante", function()
  local sawLate = false
  for seed = 1, 200 do
    local run = ns.Run.new(seed, "ADVENTURER")
    T.eq(run.tags, {})
    T.eq(run.skips, 0)
    T.ok(run.blindTags[1] and run.blindTags[2] and run.blindTags[3] == nil, "seed " .. seed .. " two tags")
    for i = 1, 2 do
      T.eq(ns.Tags.def[run.blindTags[i]].minStage, 1, "seed " .. seed .. " stage-1 tag")
    end
    run.phase, run.blind = "shop", 3
    ns.Run.nextBlind(run)
    T.eq(run.stage, 2)
    for i = 1, 2 do
      T.ok(ns.Tags.def[run.blindTags[i]], "seed " .. seed .. " stage-2 tag")
      if ns.Tags.def[run.blindTags[i]].minStage == 2 then sawLate = true end
    end
  end
  T.ok(sawLate, "stage 2 rolls minStage 2 tags")
end)

T.test("blind_tags_not_rerolled_within_ante", function()
  local run = ns.Run.new(5, "ADVENTURER")
  local tags = { run.blindTags[1], run.blindTags[2] }
  run.phase = "shop"
  ns.Run.nextBlind(run)
  T.eq(run.blindTags, tags)
end)

T.test("skip_small_then_big", function()
  local run = ns.Run.new(11, "ADVENTURER")
  local gold, small, big = run.gold, run.blindTags[1], run.blindTags[2]
  T.eq(ns.Run.skipBlind(run), small)
  T.eq({ run.blind, run.phase, run.skips }, { 2, "blind", 1 })
  T.eq(ns.Run.skipBlind(run), big)
  T.eq({ run.blind, run.phase, run.skips, run.stage }, { 3, "blind", 2, 1 })
  T.eq(run.gold, gold)
  T.eq(run.tags, { small, big })
  T.eq(run.lastPayout, nil)
end)

T.test("boss_cannot_be_skipped", function()
  local run = ns.Run.new(11, "ADVENTURER")
  run.blind = 3
  local ok, reason = ns.Run.canSkip(run)
  T.ok(not ok and type(reason) == "string", "boss refuses")
  T.eq(ns.Run.skipBlind(run), nil)
  T.eq({ run.blind, run.skips, #run.tags }, { 3, 0, 0 })
  run.blind = 1
  ns.Run.startBlind(run)
  T.ok(not ns.Run.canSkip(run), "no skip while playing")
  T.eq(ns.Run.skipBlind(run), nil)
end)

T.test("skip_fires_on_skip_and_counts", function()
  local run = ns.Run.new(11, "ADVENTURER")
  local fired, events = {}, {}
  local fire, onEvent = ns.TrinketEngine.fire, ns.Profile.onEvent
  ns.TrinketEngine.fire = function(r, hook, ...)
    fired[#fired + 1] = hook
    return fire(r, hook, ...)
  end
  ns.Profile.onEvent = function(name, amount) events[#events + 1] = { name, amount } end
  local ok, err = pcall(ns.Run.skipBlind, run)
  ns.TrinketEngine.fire, ns.Profile.onEvent = fire, onEvent
  T.ok(ok, tostring(err))
  T.eq(fired, { "onSkip" })
  T.eq(events, { { "blindSkipped", 1 } })
end)

-- Registers test-only tag defs for the duration of fn, removed even if an assert fails.
local function withDefs(defs, fn)
  for id, def in pairs(defs) do ns.Tags.def[id] = def end
  local ok, err = pcall(fn)
  for id in pairs(defs) do ns.Tags.def[id] = nil end
  if not ok then error(err, 0) end
end

T.test("tags_add_and_fire_consume", function()
  withDefs({
    TEST_TAKE = { id = "TEST_TAKE", onTake = function() return true end },
    TEST_HOOK = { id = "TEST_HOOK", onShopOpen = function(_, n) return n == 1 end },
  }, function()
    local run = ns.Run.new(3, "ADVENTURER")
    ns.Tags.add(run, "TEST_TAKE")
    T.eq(run.tags, {})
    ns.Tags.add(run, "TEST_HOOK")
    ns.Tags.add(run, "RARE")
    ns.Tags.add(run, "TEST_HOOK")
    ns.Tags.fire(run, "onShopOpen", 2)
    T.eq(run.tags, { "TEST_HOOK", "RARE", "TEST_HOOK" })
    ns.Tags.fire(run, "onShopOpen", 1)
    T.eq(run.tags, { "RARE" })
  end)
end)

T.test("skip_counts_before_the_tag", function()
  local seen
  withDefs({ TEST_SPEED = { id = "TEST_SPEED", onTake = function(run) seen = run.skips end } }, function()
    local run = ns.Run.new(3, "ADVENTURER")
    run.blindTags[1] = "TEST_SPEED"
    ns.Run.skipBlind(run)
    T.eq(seen, 1, "onTake sees this skip counted")
  end)
end)

T.test("skipped_blinds_tracked_per_ante", function()
  local run = ns.Run.new(3, "ADVENTURER")
  T.eq(run.skippedBlinds, {})
  ns.Run.skipBlind(run)
  T.eq(run.skippedBlinds, { [1] = true })
  ns.Run.startBlind(run)
  ns.Run.winBlind(run)
  ns.Run.nextBlind(run)
  T.eq({ run.blind, run.skippedBlinds }, { 3, { [1] = true } })
  run.phase = "shop"
  ns.Run.nextBlind(run)
  T.eq({ run.stage, run.skippedBlinds }, { 2, {} })
end)

-- Takes a tag on a fresh run (seed 9) after setup(run); returns the run.
local function take(id, setup)
  local run = ns.Run.new(9, "ADVENTURER")
  if setup then setup(run) end
  ns.Tags.add(run, id)
  return run
end

T.test("economy_tag_doubles_gold_capped", function()
  T.eq(take("ECONOMY", function(r) r.gold = 15 end).gold, 30)
  T.eq(take("ECONOMY", function(r) r.gold = 60 end).gold, 100)
  T.eq(take("ECONOMY", function(r) r.gold = -5 end).gold, -5)
  T.eq(take("ECONOMY").tags, {})
end)

T.test("speed_tag_pays_per_skip", function()
  local run = ns.Run.new(9, "ADVENTURER")
  run.skips, run.gold, run.blindTags[1] = 2, 4, "SPEED"
  ns.Run.skipBlind(run)
  T.eq(run.gold, 4 + 15) -- this skip counts: 3 skips
  T.eq(run.tags, {})
end)

T.test("handy_tag_pays_per_hand_played", function()
  local run = take("HANDY", function(r) r.gold, r.handsPlayedTotal = 4, 7 end)
  T.eq(run.gold, 11)
  T.eq(run.tags, {})
end)

T.test("garbage_tag_pays_per_unused_discard", function()
  local run = ns.Run.new(9, "ADVENTURER")
  T.eq(run.discardsUnusedTotal, 0)
  ns.Run.startBlind(run)
  run.discardsLeft = 2
  ns.Run.winBlind(run)
  T.eq(run.discardsUnusedTotal, 2)
  run = take("GARBAGE", function(r) r.gold, r.discardsUnusedTotal = 4, 6 end)
  T.eq(run.gold, 10)
  T.eq(run.tags, {})
end)

T.test("orbital_tag_levels_a_visible_hand_three_times", function()
  for seed = 1, 20 do
    local run = ns.Run.new(seed, "ADVENTURER")
    ns.Tags.add(run, "ORBITAL")
    local levelled = {}
    for id, level in pairs(run.handLevels) do
      if level ~= 1 then levelled[#levelled + 1] = { id, level } end
    end
    T.eq(#levelled, 1, "seed " .. seed .. " one hand")
    T.eq(levelled[1][2], 4, "seed " .. seed .. " three levels")
    T.ok(not ns.Hands.def[levelled[1][1]].secret, "seed " .. seed .. " a visible hand")
    T.eq(run.tags, {})
  end
end)

T.test("topup_tag_creates_common_trinkets", function()
  local run = take("TOPUP")
  T.eq(#run.trinkets, 2)
  for _, trinket in ipairs(run.trinkets) do
    T.eq(ns.Trinkets.def[trinket.id].rarity, "common", trinket.id)
  end
  T.ok(run.trinkets[1].id ~= run.trinkets[2].id, "distinct")
  T.eq(run.tags, {})
  run = take("TOPUP", function(r)
    for i = 1, 4 do r.trinkets[i] = ns.Trinkets.create(r, "ARCANE_INTELLECT") end
    r.trinkets[1].id = "BLOODLUST"
  end)
  T.ok(#run.trinkets == 5 or (#run.trinkets == 6 and run.trinkets[5].ed == "NEGATIVE"), "fills one free slot")
  run = take("TOPUP", function(r)
    for i = 1, 5 do r.trinkets[i] = ns.Trinkets.create(r, "BLOODLUST") end
  end)
  T.eq(#run.trinkets, 5, "no free slot, no trinket")
  T.eq(run.tags, {})
end)

T.test("boss_tag_rerolls_boss_free", function()
  local run = ns.Run.new(9, "ADVENTURER")
  local before, gold = run.bosses[1], run.gold
  ns.Tags.add(run, "BOSS")
  T.ok(run.bosses[1] ~= before, "new boss")
  T.ok(ns.Bosses.def[run.bosses[1]], "a real boss")
  T.eq({ run.gold, run.bossRerollsUsed, run.tags }, { gold, 0, {} })
end)

T.test("pack_tags_open_free_gift_packs", function()
  local want = { STANDARD = { "STANDARD", "mega" }, CHARM = { "ARCANA", "mega" }, METEOR = { "CELESTIAL", "mega" },
    BUFFOON = { "BUFFOON", "mega" }, ETHEREAL = { "SPECTRAL", "normal" } }
  for id, kind in pairs(want) do
    local run = take(id, function(r) r.gold = 3 end)
    local pack = run.giftPack
    T.ok(pack, id .. " opened")
    T.eq({ pack.type, pack.size, pack.paid, run.gold, run.tags }, { kind[1], kind[2], 0, 3, {} }, id)
    T.ok(#pack.choices > 0, id .. " has choices")
    T.eq(pack.hand ~= nil, kind[1] == "ARCANA" or kind[1] == "SPECTRAL", id .. " hand to aim at")
  end
end)

T.test("gift_pack_opens_free_on_blind_screen", function()
  local run = ns.Run.new(9, "ADVENTURER")
  run.blindTags[1], run.gold = "BUFFOON", 6
  ns.Run.skipBlind(run)
  local pack = run.giftPack
  T.ok(pack, "gift pack open")
  T.ok(ns.Packs.current(run) == pack, "current is the gift")
  T.eq({ run.phase, run.gold, run.blind }, { "blind", 6, 2 })
  T.ok(not ns.Run.canSkip(run), "no skipping with a pack open")
  T.ok(not ns.Run.canStart(run), "no starting with a pack open")
  local id = pack.choices[1].id
  T.ok(ns.Packs.pick(run, 1), "pick")
  T.eq(run.trinkets[1].id, id)
  T.ok(run.giftPack == pack, "a pick left")
  ns.Packs.skip(run)
  T.eq({ run.giftPack, ns.Packs.current(run), run.phase, run.gold }, { nil, nil, "blind", 6 })
  T.ok(ns.Run.canSkip(run), "skip is back")
end)

T.test("gift_pack_skip_fires_on_pack_skipped", function()
  local run = take("CHARM")
  local fired = {}
  local fire = ns.TrinketEngine.fire
  ns.TrinketEngine.fire = function(r, hook, ...)
    fired[#fired + 1] = hook
    return fire(r, hook, ...)
  end
  local ok, err = pcall(ns.Packs.skip, run)
  ns.TrinketEngine.fire = fire
  T.ok(ok, tostring(err))
  T.eq(fired, { "onPackSkipped" })
end)

T.test("pack_tag_waits_for_the_open_gift", function()
  local run = take("CHARM")
  ns.Tags.add(run, "BUFFOON")
  T.eq({ run.giftPack.type, run.tags }, { "ARCANA", { "BUFFOON" } })
  ns.Packs.skip(run)
  T.eq({ run.giftPack.type, run.giftPack.paid, run.tags }, { "BUFFOON", 0, {} })
end)

T.test("start_blind_refused_while_gift_open", function()
  local run = take("CHARM")
  local deckSize = #run.pile
  ns.Run.startBlind(run)
  T.eq({ run.phase, #run.hand, #run.pile }, { "blind", 0, deckSize })
end)

-- Opens the shop on a fresh run (seed) holding `tags`, after setup(run); returns the run.
local function shopWith(seed, tags, setup)
  local run = ns.Run.new(seed, "ADVENTURER")
  run.tags, run.gold, run.phase = tags, 100, "shop"
  if setup then setup(run) end
  ns.Shop.open(run)
  return run
end

T.test("uncommon_tag_free_uncommon", function()
  for _, rarity in ipairs({ "uncommon", "rare" }) do
    for seed = 1, 10 do
      local run = shopWith(seed, { rarity:upper() })
      local item = run.shop.cards[1]
      T.eq({ item.type, ns.Trinkets.def[item.id].rarity, item.cost, run.tags }, { "trinket", rarity, 0, {} },
        rarity .. " seed " .. seed)
      ns.Shop.reprice(run)
      T.eq(item.cost, 0, "reprice keeps it free")
      T.ok(ns.Shop.buy(run, 1))
      T.eq(run.gold, 100, "free")
      T.eq(ns.Shop.sellValue(run.trinkets[1]), 1, "sells for 1g, priced after the tag")
    end
  end
  local roll = ns.Shop.rollTrinket
  ns.Shop.rollTrinket = function(r, taken, rarity)
    if rarity then return false end
    return roll(r, taken)
  end
  local ok, run = pcall(shopWith, 3, { "RARE" })
  ns.Shop.rollTrinket = roll
  T.ok(ok, tostring(run))
  T.eq(run.tags, { "RARE" }, "empty pool: the tag waits")
end)

T.test("poly_tag_waits_for_base_trinket", function()
  local inPool = ns.Trinkets.inPool
  ns.Trinkets.inPool = function() return false end
  local ok, run = pcall(shopWith, 3, { "POLY" })
  ns.Trinkets.inPool = inPool
  T.ok(ok, tostring(run))
  T.eq(run.tags, { "POLY" }, "no trinket in the shop: waits")
  run.shop.cards = {
    { type = "trinket", id = "BLOODLUST", cost = 6, baseCost = 6 },
    { type = "trinket", id = "ARCANE_INTELLECT", ed = "FOIL", cost = 6, baseCost = 6 },
    { type = "scroll", id = "FORTUNE", cost = 3, baseCost = 3 },
    { type = "trinket", id = "FORTITUDE", cost = 5, baseCost = 5 },
  }
  run.tags = { "POLY", "NEGATIVE", "HOLO" }
  ns.Tags.fire(run, "onShopOpen")
  local cards = run.shop.cards
  T.eq({ cards[1].ed, cards[1].cost, cards[4].ed, cards[4].cost }, { "POLY", 0, "NEGATIVE", 0 })
  T.eq({ cards[2].ed, cards[2].cost, cards[3].cost }, { "FOIL", 6, 3 }, "others untouched")
  T.eq(run.tags, { "HOLO" }, "no base trinket left for the third")
  ns.Shop.reprice(run)
  T.eq({ cards[1].cost, cards[4].cost }, { 0, 0 }, "reprice keeps them free")
end)

T.test("coupon_frees_initial_shop_only", function()
  local run = shopWith(4, { "COUPON" })
  local voucher = run.shopVoucher
  T.eq(run.tags, {})
  for i, item in ipairs(run.shop.cards) do T.eq(item.cost, 0, "card " .. i) end
  for i, item in ipairs(run.shop.packs) do T.eq(item.cost, 0, "pack " .. i) end
  T.ok(voucher and voucher.cost > 0, "the voucher still costs")
  ns.Shop.reprice(run)
  for i, item in ipairs(run.shop.cards) do T.eq(item.cost, 0, "repriced card " .. i) end
  T.ok(ns.Shop.reroll(run))
  for i, item in ipairs(run.shop.cards) do
    T.eq(item.cost, ns.Shop.priceOf(run, item), "rerolled card " .. i .. " pays")
    T.ok(item.cost > 0, "rerolled card " .. i .. " costs")
  end
  for i, item in ipairs(run.shop.packs) do T.eq(item.cost, 0, "pack " .. i .. " still free") end
end)

T.test("d6_rerolls_start_free", function()
  local run = shopWith(4, { "D6" })
  T.eq({ run.shop.rerollCost, run.tags }, { 0, {} })
  T.ok(ns.Shop.reroll(run))
  T.eq({ run.gold, run.shop.rerollCost }, { 100, 1 })
  T.ok(ns.Shop.reroll(run))
  T.eq({ run.gold, run.shop.rerollCost }, { 99, 2 })
  run = shopWith(4, {})
  T.eq(run.shop.rerollCost, 5, "only with the tag")
  run = shopWith(4, { "D6" }, function(r) r.vouchers.REROLL_SURPLUS = true end)
  for i = 0, 2 do
    T.ok(ns.Shop.reroll(run))
    T.eq(run.gold, 100 - i * (i + 1) / 2, "D6 with Reroll Surplus: reroll " .. (i + 1) .. " costs " .. i)
  end
  run = shopWith(4, {}, function(r) r.vouchers.REROLL_SURPLUS = true end)
  T.ok(ns.Shop.reroll(run))
  T.eq(run.gold, 97, "Reroll Surplus alone still discounts")
end)

T.test("voucher_tag_adds_offer", function()
  for seed = 1, 10 do
    local run = shopWith(seed, { "VOUCHER" })
    local main, extra = run.shopVoucher, run.shop.extraVoucher
    T.ok(main and extra and main.id ~= extra.id, "seed " .. seed .. " two offers")
    T.eq(run.tags, {})
    T.ok(ns.Shop.buyVoucher(run, "extra"))
    T.ok(ns.Vouchers.owns(run, extra.id), "bought the extra")
    T.eq(run.shop.extraVoucher, false)
    T.ok(run.shopVoucher == main, "the main offer stays")
    T.eq({ ns.Shop.buyVoucher(run, "extra") }, { false, "gone" })
    T.ok(ns.Shop.buyVoucher(run))
    T.eq(run.shopVoucher, false)
  end
  local run = shopWith(3, { "VOUCHER" }, function(r)
    for id, def in pairs(ns.Vouchers.def) do
      if def.tier == 1 then r.vouchers[id] = true end
    end
  end)
  T.eq({ run.shopVoucher, run.shop.extraVoucher, run.tags }, { false, nil, {} }, "empty pool: still spent")
end)

T.test("juggle_one_blind_only", function()
  local run = ns.Run.new(9, "ADVENTURER")
  run.tags = { "JUGGLE" }
  ns.Run.startBlind(run)
  T.eq({ #run.hand, ns.Deck.handSize(run), run.tags }, { 11, 11, {} })
  ns.Run.winBlind(run)
  T.eq({ run.blindHandSizeBonus, ns.Deck.handSize(run) }, { nil, 8 })
  run = ns.Run.new(9, "ADVENTURER")
  run.tags = { "JUGGLE" }
  ns.Run.startBlind(run)
  run.target, run.handsLeft = 1e9, 1
  ns.Run.play(run, { 1 })
  T.eq({ run.phase, run.blindHandSizeBonus }, { "lost", nil })
end)

T.test("investment_pays_after_boss", function()
  local run = ns.Run.new(9, "ADVENTURER")
  run.tags = { "INVESTMENT" }
  ns.Run.startBlind(run)
  ns.Run.winBlind(run)
  T.eq({ run.lastPayout.investment, run.tags }, { nil, { "INVESTMENT" } }, "not a boss")
  run.phase, run.blind = "blind", 3
  ns.Run.startBlind(run)
  local gold = run.gold
  ns.Run.winBlind(run)
  local pay = run.lastPayout
  T.eq({ pay.investment, run.tags }, { 25, {} })
  T.eq(pay.total, pay.reward + pay.hands + pay.discards + pay.interest + pay.trinkets + pay.held + 25)
  T.eq(run.gold, gold + pay.total)
end)

T.test("double_copies_next_tag", function()
  local run = ns.Run.new(9, "ADVENTURER")
  ns.Tags.add(run, "DOUBLE")
  ns.Tags.add(run, "D6")
  T.eq(run.tags, { "D6", "D6" })
  run = ns.Run.new(9, "ADVENTURER")
  run.tags = { "DOUBLE", "COUPON", "DOUBLE" }
  ns.Tags.add(run, "D6")
  T.eq(run.tags, { "COUPON", "D6", "D6", "D6" }, "Doubles stack")
  run = ns.Run.new(9, "ADVENTURER")
  run.tags, run.skips, run.gold = { "DOUBLE" }, 2, 0
  ns.Tags.add(run, "SPEED")
  T.eq({ run.gold, run.tags }, { 20, {} }, "an immediate tag pays twice")
end)

T.test("double_never_copies_double", function()
  local run = ns.Run.new(9, "ADVENTURER")
  ns.Tags.add(run, "DOUBLE")
  ns.Tags.add(run, "DOUBLE")
  T.eq(run.tags, { "DOUBLE", "DOUBLE" })
end)

T.test("rarity_tag_keeps_edition_tag_trinket", function()
  local run = ns.Run.new(3, "ADVENTURER")
  run.shop = { cards = {
    { type = "trinket", id = "BLOODLUST", cost = 6, baseCost = 6 },
    { type = "scroll", id = "FORTUNE", cost = 3, baseCost = 3 },
  }, packs = {}, rerollCost = 5 }
  run.tags = { "POLY", "UNCOMMON" }
  ns.Tags.fire(run, "onShopOpen")
  local cards = run.shop.cards
  T.eq({ cards[1].id, cards[1].ed, cards[1].cost }, { "BLOODLUST", "POLY", 0 }, "the Poly trinket stays")
  T.eq({ cards[2].type, ns.Trinkets.def[cards[2].id].rarity, cards[2].cost }, { "trinket", "uncommon", 0 })
  T.eq(run.tags, {})
end)
