local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function shopRun(opts)
  local run = H.run(opts)
  run.phase = "shop"
  ns.Shop.open(run)
  return run
end

local function blindRun(opts)
  local run = H.run(opts)
  ns.Run.startBlind(run)
  return run
end

local function add(run, id)
  ns.Run.withMods(run, function()
    run.trinkets[#run.trinkets + 1] = ns.Trinkets.create(run, id)
  end)
end

H.test("sell_in_play_allowed", function()
  H.stub({ id = "S_A", cost = 6 })
  local run = H.run({ trinkets = { "S_A" }, gold = 0 })
  T.eq(ns.Run.sellTrinket(run, 1), 3)
  T.eq(run.gold, 3)
  T.eq(#run.trinkets, 0)
  T.eq(ns.Run.sellTrinket(run, 1), nil)
end)

H.test("sell_in_blind_select_refused", function()
  H.stub({ id = "S_A" })
  local run = H.run({ trinkets = { "S_A" }, gold = 0 })
  run.phase = "blind"
  local gained, reason = ns.Run.sellTrinket(run, 1)
  T.eq(gained, nil)
  T.eq(reason, "phase")
  T.eq(#run.trinkets, 1)
  T.eq(run.gold, 0)
end)

H.test("sell_fires_on_sell_others_only", function()
  local seen = {}
  H.stub({ id = "S_SOLD", onSell = function() seen[#seen + 1] = "sold" end })
  H.stub({ id = "S_WATCH", onSell = function(_, _, sold, isCopy)
    seen[#seen + 1] = { sold.kind, sold.item.id, isCopy }
  end })
  local run = shopRun({ trinkets = { "S_SOLD", "S_WATCH" } })
  ns.Run.sellTrinket(run, 1)
  T.eq(seen, { { "trinket", "S_SOLD", false } })
end)

H.test("self_sold_before_removal", function()
  local count
  H.stub({ id = "S_BYE", onSelfSold = function(run) count = #run.trinkets; return { gold = 4 } end })
  local run = H.run({ trinkets = { "S_BYE" }, gold = 0 })
  T.eq(ns.Run.sellTrinket(run, 1), 1)
  T.eq(count, 1)
  T.eq(run.gold, 5)
end)

H.test("mods_hand_size_live", function()
  H.stub({ id = "S_HS", handSize = 1 })
  local run = shopRun({ gold = 50 })
  run.shop.cards = { { type = "trinket", id = "S_HS", cost = 1, baseCost = 1 } }
  T.eq(ns.Shop.buy(run, 1), true)
  ns.Run.nextBlind(run)
  ns.Run.startBlind(run)
  T.eq(#run.hand, 9)
  T.eq(ns.Run.sellTrinket(run, 1) ~= nil, true)
  T.eq(#run.hand, 9) -- A smaller size never discards.
  T.eq(ns.Deck.handSize(run), 8)
  ns.Run.discard(run, { 1, 2 })
  T.eq(#run.hand, 8)
end)

H.test("mods_hand_size_gain_draws_now", function()
  H.stub({ id = "S_HS", handSize = 2 })
  local run = blindRun()
  T.eq(#run.hand, 8)
  add(run, "S_HS")
  T.eq(#run.hand, 10)
end)

H.test("mods_discards_clamp", function()
  H.stub({ id = "S_D", discards = 1 })
  local run = blindRun({ trinkets = { "S_D" } })
  local base = ns.Run.blindDiscards(run)
  T.eq(run.discardsLeft, base)
  run.discardsLeft = 0
  ns.Run.sellTrinket(run, 1)
  T.eq(run.discardsLeft, 0)
  add(run, "S_D")
  T.eq(run.discardsLeft, 1)
end)

H.test("mods_hands_min1", function()
  H.stub({ id = "S_H", hands = 3 })
  local run = blindRun({ trinkets = { "S_H" } })
  T.eq(run.handsLeft, ns.Run.blindHands(run))
  run.handsLeft = 1
  ns.Run.sellTrinket(run, 1)
  T.eq(run.handsLeft, 1)
end)

H.test("credit_card_floor", function()
  H.stub({ id = "S_CC", rule = "CREDIT_CARD", cost = 6 })
  local run = shopRun({ trinkets = { "S_CC" }, gold = 5 })
  T.eq(ns.Run.goldFloor(run), -20)
  run.shop.cards = {
    { type = "card", rank = 5, suit = "S", cost = 30, baseCost = 30 },
    { type = "card", rank = 6, suit = "S", cost = 20, baseCost = 20 },
  }
  T.eq(ns.Shop.buy(run, 1), false)
  T.eq(ns.Shop.buy(run, 2), true)
  T.eq(run.gold, -15)
  -- Interest on debt is zero, and the debt stays.
  run.phase = "play"
  ns.Run.startBlind(run)
  run.gold = -15
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.interest, 0)
  run.gold = -15
  run.phase = "shop"
  T.eq(ns.Run.sellTrinket(run, 1), 3)
  T.eq(run.gold, -12)
  T.eq(ns.Run.goldFloor(run), 0)
end)

H.test("credit_card_floor_applies_to_reroll_pack_and_canAfford", function()
  H.stub({ id = "S_CC", rule = "CREDIT_CARD" })
  local run = shopRun({ trinkets = { "S_CC" }, gold = -18 })
  T.eq(ns.Shop.reroll(run), false)
  run.gold = -15
  T.eq(ns.Shop.reroll(run), true)
  run.gold = 0
  run.shop.packs[1] = { type = "STANDARD", size = "mega", baseCost = 8, cost = 8 }
  T.eq(ns.Packs.open(run, 1), true)
  run.gold = -10
  T.eq(ns.Run.canAfford(run, 10), true)
  T.eq(ns.Run.canAfford(run, 11), false)
end)

H.test("chaos_free_reroll_once_per_shop", function()
  H.stub({ id = "S_CHAOS", rule = "CHAOS" })
  local run = shopRun({ trinkets = { "S_CHAOS" }, gold = 100 })
  T.eq(run.shop.freeRerolls, 1)
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.gold, 100)
  T.eq(run.shop.rerollCost, 5)
  T.eq(run.shop.freeRerolls, 0)
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.gold, 95)
  T.eq(run.shop.rerollCost, 6)
  ns.Shop.open(run)
  T.eq(run.shop.freeRerolls, 1)
end)

H.test("reroll_fires_on_shop_reroll", function()
  local n = 0
  H.stub({ id = "S_R", onShopReroll = function() n = n + 1 end })
  local run = shopRun({ trinkets = { "S_R" }, gold = 100 })
  ns.Shop.reroll(run)
  T.eq(n, 1)
end)

H.test("showman_allows_duplicates", function()
  H.stub({ id = "S_SHOW", rule = "SHOWMAN" })
  local real = ns.Trinkets.inPool
  ns.Trinkets.inPool = function(_, id) return id == "ARCANE_INTELLECT" end
  local ok, err = pcall(function()
    local run = H.run({ trinkets = { "ARCANE_INTELLECT" } })
    T.eq(ns.Shop.rollTrinket(run, {}), false)
    T.eq(ns.Trinkets.rollOfRarity(run, "common"), nil)
    add(run, "S_SHOW")
    local item = ns.Shop.rollTrinket(run, {})
    T.eq(item.id, "ARCANE_INTELLECT")
    T.eq(ns.Trinkets.rollOfRarity(run, "common"), "ARCANE_INTELLECT")
  end)
  ns.Trinkets.inPool = real
  if not ok then error(err, 0) end
end)

H.test("astronomer_free_tomes_and_celestial", function()
  H.stub({ id = "S_ASTRO", rule = "ASTRONOMER", cost = 4 })
  local run = shopRun({ gold = 50 })
  run.shop.cards = {
    { type = "tome", id = "PAIR", cost = 3, baseCost = 3 },
    { type = "scroll", id = "BLESSING", cost = 3, baseCost = 3 },
    { type = "trinket", id = "S_ASTRO", cost = 4, baseCost = 4 },
  }
  run.shop.packs = {
    { type = "CELESTIAL", size = "normal", baseCost = 4, cost = 4 },
    { type = "ARCANA", size = "normal", baseCost = 4, cost = 4 },
  }
  T.eq(ns.Shop.buy(run, 3), true)
  T.eq(run.shop.cards[1].cost, 0)
  T.eq(run.shop.cards[2].cost, 3)
  T.eq(run.shop.packs[1].cost, 0)
  T.eq(run.shop.packs[2].cost, 4)
  ns.Run.sellTrinket(run, 1)
  T.eq(run.shop.cards[1].cost, 3)
  T.eq(run.shop.packs[1].cost, 4)
  add(run, "S_ASTRO")
  ns.Shop.open(run)
  for _, item in ipairs(run.shop.cards) do
    if item.type == "tome" then T.eq(item.cost, 0) end
  end
  for _, pack in ipairs(run.shop.packs) do
    T.eq(pack.cost == 0, pack.type == "CELESTIAL")
  end
  ns.Shop.reroll(run)
  for _, item in ipairs(run.shop.cards) do
    if item.type == "tome" then T.eq(item.cost, 0) end
  end
end)

H.test("interest_bonus_stacks", function()
  H.stub({ id = "S_I1", interestBonus = 1 })
  H.stub({ id = "S_I2", interestBonus = 1 })
  local run = blindRun({ trinkets = { "S_I1", "S_I2" } })
  run.gold = 25
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.interest, 15)
end)

H.test("pack_skip_fires_only_with_picks_left", function()
  local n = 0
  H.stub({ id = "S_SKIP", onPackSkipped = function() n = n + 1 end })
  local run = shopRun({ trinkets = { "S_SKIP" } })
  ns.Packs.skip(run)
  T.eq(n, 0) -- No pack open.
  run.shop.openPack = { picksLeft = 0, choices = {} }
  ns.Packs.skip(run)
  T.eq(n, 0)
  run.shop.openPack = { picksLeft = 1, choices = {} }
  ns.Packs.skip(run)
  T.eq(n, 1)
  T.eq(run.shop.openPack, nil)
end)

H.test("consumable_sell_bonus", function()
  local seen
  H.stub({ id = "S_W", onSell = function(_, _, sold) seen = sold.kind end })
  local run = shopRun({ trinkets = { "S_W" }, gold = 0 })
  run.consumables = { { kind = "tome", id = "PAIR", paid = 3, sellBonus = 2 } }
  T.eq(ns.Consumables.sellValue(run.consumables[1]), 3)
  T.eq(ns.Consumables.sell(run, 1), 3)
  T.eq(run.gold, 3)
  T.eq(seen, "consumable")
end)

H.test("goblin_bank_no_negative_mult_in_debt", function()
  local run = H.run({ trinkets = { "GOBLIN_BANK" }, gold = -15 })
  local result = H.score(run, { H.card(5, "S") })
  local rich = H.run({ trinkets = { "GOBLIN_BANK" }, gold = 0 })
  T.eq(result.total, H.score(rich, { H.card(5, "S") }).total)
end)

H.test("zero_cost_actions_allowed_below_floor", function()
  H.stub({ id = "S_CHAOS", rule = "CHAOS" })
  H.stub({ id = "S_ASTRO", rule = "ASTRONOMER" })
  local run = shopRun({ trinkets = { "S_CHAOS", "S_ASTRO" }, gold = -12 })
  T.eq(ns.Run.canAfford(run, 0), true)
  T.eq(ns.Shop.reroll(run), true)
  run.shop.cards = { { type = "tome", id = "PAIR", cost = 0, baseCost = 3 } }
  T.eq(ns.Shop.buy(run, 1), true)
  T.eq(run.gold, -12)
end)

H.test("chaos_live_buy_and_sell_mid_shop", function()
  H.stub({ id = "S_CHAOS", rule = "CHAOS" })
  local run = shopRun({ gold = 100 })
  T.eq(run.shop.freeRerolls, 0)
  run.shop.cards = { { type = "trinket", id = "S_CHAOS", cost = 1, baseCost = 1 } }
  T.eq(ns.Shop.buy(run, 1), true)
  T.eq(run.shop.freeRerolls, 1)
  local gold = run.gold
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.gold, gold)
  add(run, "S_CHAOS")
  ns.Run.sellTrinket(run, 1)
  ns.Run.sellTrinket(run, 1)
  T.eq(run.shop.freeRerolls, 0)
  local before = run.gold
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.gold < before, true)
end)
