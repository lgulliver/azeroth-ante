local ns, T = ...

local function opened(gold)
  local run = ns.Run.new(11, "ADVENTURER")
  run.gold = gold or 0
  ns.Shop.open(run)
  return run
end

T.test("open_two_distinct_unowned", function()
  local run = ns.Run.new(11, "ADVENTURER")
  run.trinkets = { { id = "BLOODLUST" }, { id = "FORTITUDE" } }
  ns.Shop.open(run)
  local shop = run.shop
  T.eq(#shop.offers, 2)
  T.ok(shop.offers[1].id ~= shop.offers[2].id, "offers must be distinct")
  for _, offer in ipairs(shop.offers) do
    T.ok(offer.id ~= "BLOODLUST" and offer.id ~= "FORTITUDE", "offered an owned trinket")
    T.eq(offer.cost, ns.Trinkets.def[offer.id].cost)
  end
  T.ok(ns.Hands.def[shop.tome.handId] ~= nil, "tome hand missing")
  T.eq(shop.tome.cost, 3)
  T.eq(shop.rerollCost, 5)
end)

T.test("open_offers_fewer_when_ineligible", function()
  local run = ns.Run.new(11, "ADVENTURER")
  run.trinkets = {}
  for i = 1, 19 do run.trinkets[i] = { id = ns.Trinkets.order[i] } end
  run.maxTrinkets = 99
  ns.Shop.open(run)
  T.eq(#run.shop.offers, 1)
  T.eq(run.shop.offers[1].id, ns.Trinkets.order[20])
end)

T.test("buy_insufficient_gold", function()
  local run = opened(0)
  local ok, err = ns.Shop.buyTrinket(run, 1)
  T.eq(ok, false)
  T.eq(err, "gold")
  T.eq(run.trinkets, {})
  T.eq(run.shop.offers[1] ~= false, true)
end)

T.test("buy_full_slots", function()
  local run = ns.Run.new(11, "ADVENTURER")
  run.trinkets = {}
  for i = 1, 5 do run.trinkets[i] = { id = ns.Trinkets.order[i] } end
  run.gold = 100
  ns.Shop.open(run)
  local ok, err = ns.Shop.buyTrinket(run, 1)
  T.eq(ok, false)
  T.eq(err, "slots")
  T.eq(run.gold, 100)
  T.eq(#run.trinkets, 5)
end)

T.test("buy_gone_slot", function()
  local run = opened(100)
  T.eq(ns.Shop.buyTrinket(run, 1), true)
  local ok, err = ns.Shop.buyTrinket(run, 1)
  T.eq(ok, false)
  T.eq(err, "gone")
end)

T.test("buy_ok_deducts_and_adds", function()
  local run = opened(20)
  local offer = run.shop.offers[1]
  T.eq(ns.Shop.buyTrinket(run, 1), true)
  T.eq(run.gold, 20 - offer.cost)
  T.eq(run.trinkets, { { id = offer.id } })
  T.eq(run.shop.offers[1], false)
  T.eq(run.shop.offers[2] ~= false, true)
end)

T.test("tome_levels_hand", function()
  local run = opened(20)
  local handId = run.shop.tome.handId
  T.eq(run.handLevels[handId], 1)
  T.eq(ns.Shop.buyTome(run), true)
  T.eq(run.handLevels[handId], 2)
  T.eq(run.shop.tome, false)
  T.eq(run.gold, 17)
  local ok, err = ns.Shop.buyTome(run)
  T.eq(ok, false)
  T.eq(err, "gone")
end)

T.test("tome_insufficient_gold", function()
  local run = opened(2)
  local ok, err = ns.Shop.buyTome(run)
  T.eq(ok, false)
  T.eq(err, "gold")
  T.eq(run.gold, 2)
  T.ok(run.shop.tome ~= false, "tome consumed without payment")
end)

T.test("sell_half_cost", function()
  local run = ns.Run.new(11, "ADVENTURER")
  run.trinkets = { { id = "AVENGING_WRATH" } }
  run.gold = 0
  T.eq(ns.Shop.sell(run, 1), 4)
  T.eq(run.gold, 4)
  T.eq(run.trinkets, {})
end)

T.test("reroll_cost_increments", function()
  local run = opened(20)
  T.eq(run.shop.rerollCost, 5)
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.shop.rerollCost, 6)
  T.eq(run.gold, 15)
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.shop.rerollCost, 7)
  T.eq(run.gold, 9)
end)

T.test("reroll_insufficient_gold", function()
  local run = opened(4)
  local ok, err = ns.Shop.reroll(run)
  T.eq(ok, false)
  T.eq(err, "gold")
  T.eq(run.shop.rerollCost, 5)
end)

T.test("reroll_keeps_tome", function()
  local run = opened(20)
  local tome = run.shop.tome
  ns.Shop.reroll(run)
  T.eq(run.shop.tome, tome)
end)

T.test("tome_name", function()
  T.eq(ns.Shop.tomeName("PAIR"), "Tome of Pair")
  T.eq(ns.Shop.tomeName("FOUR_KIND"), "Tome of Four of a Kind")
end)

T.test("rarity_weights_roughly", function()
  local run = ns.Run.new(12345, "ADVENTURER")
  local counts, total = { common = 0, uncommon = 0, rare = 0 }, 0
  for _ = 1, 2000 do
    ns.Shop.open(run)
    for _, offer in ipairs(run.shop.offers) do
      local rarity = ns.Trinkets.def[offer.id].rarity
      counts[rarity] = counts[rarity] + 1
      total = total + 1
    end
  end
  T.ok(total == 4000, "expected 4000 offers, got " .. total)
  T.ok(counts.common / total > 0.55, "commons too rare: " .. counts.common / total)
  T.ok(counts.rare / total < 0.12, "rares too common: " .. counts.rare / total)
end)
