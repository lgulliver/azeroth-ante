local ns, T = ...

local function opened(gold)
  local run = ns.Run.new(11, "ADVENTURER")
  run.phase, run.gold = "shop", gold or 100
  ns.Shop.open(run)
  return run
end

T.test("shop_two_cards_two_packs", function()
  local run = opened()
  T.eq(#run.shop.cards, 2)
  T.eq(#run.shop.packs, 2)
  T.eq(run.shop.rerollCost, 5)
end)

T.test("card_type_weights", function()
  local run, count = opened(), 0
  for _ = 1, 3000 do
    ns.Shop.open(run)
    local seen = {}
    for _, item in ipairs(run.shop.cards) do
      if item.type == "trinket" then
        count = count + 1
        T.ok(not seen[item.id], "duplicate trinket")
        seen[item.id] = true
      else
        T.ok(item.type == "scroll" or item.type == "tome")
        T.eq(item.cost, 3)
        if item.type == "tome" then T.ok(not ns.Hands.def[item.id].secret) end
      end
    end
  end
  T.ok(count / 6000 > 0.6 and count / 6000 < 0.8, "trinket weight: " .. count / 6000)
end)

T.test("edition_cost_added", function()
  local run = opened()
  local original = ns.CardTypes.rollEdition
  ns.CardTypes.rollEdition = function() return "FOIL" end
  ns.Shop.open(run)
  ns.CardTypes.rollEdition = original
  local found = false
  for _, item in ipairs(run.shop.cards) do
    if item.type == "trinket" then
      found = true
      T.eq(item.ed, "FOIL")
      T.eq(item.cost, ns.Trinkets.def[item.id].cost + 2)
    end
  end
  T.ok(found, "fixture needs a trinket")
end)

T.test("unowned_trinkets_only", function()
  local run = opened()
  for _, id in ipairs(ns.Trinkets.order) do run.trinkets[#run.trinkets + 1] = { id = id } end
  for _ = 1, 50 do
    ns.Shop.open(run)
    for _, item in ipairs(run.shop.cards) do T.ok(not item or item.type ~= "trinket") end
  end
end)

T.test("buy_checks_and_preserves_edition", function()
  local run = opened(0)
  run.shop.cards = { { type = "trinket", id = "BLOODLUST", ed = "FOIL", cost = 6 }, false }
  local ok, err = ns.Shop.buy(run, 1)
  T.eq({ ok, err }, { false, "gold" })
  run.gold = 100
  run.maxTrinkets = 0
  ok, err = ns.Shop.buy(run, 1)
  T.eq({ ok, err }, { false, "slots" })
  run.trinkets = { { id = "FORTITUDE", ed = "NEGATIVE" } }
  run.maxTrinkets = 1
  T.eq(ns.Shop.buy(run, 1), true)
  T.eq(run.trinkets[2], { id = "BLOODLUST", ed = "FOIL" })
  T.eq(run.gold, 94)
  T.eq(run.shop.cards[1], false)
  ok, err = ns.Shop.buy(run, 1)
  T.eq({ ok, err }, { false, "gone" })
end)

T.test("buy_consumables_needs_slot_and_does_not_apply", function()
  local run = opened()
  run.shop.cards = { { type = "tome", id = "PAIR", cost = 3 }, { type = "scroll", id = "BLESSING", cost = 3 } }
  run.maxConsumables = 0
  local ok, err = ns.Shop.buy(run, 1)
  T.eq({ ok, err }, { false, "slots" })
  T.eq(run.gold, 100)
  run.maxConsumables = 2
  T.eq(ns.Shop.buy(run, 1), true)
  T.eq(ns.Shop.buy(run, 2), true)
  T.eq(run.consumables, { { kind = "tome", id = "PAIR" }, { kind = "scroll", id = "BLESSING" } })
  T.eq(run.handLevels.PAIR, 1)
  T.eq(run.gold, 94)
end)

T.test("sell_includes_edition", function()
  local run = opened(0)
  run.trinkets = { { id = "AVENGING_WRATH", ed = "POLY" } }
  T.eq(ns.Shop.sellTrinket(run, 1), 6)
  T.eq(run.gold, 6)
  T.eq(run.trinkets, {})
  T.eq(ns.Shop.sellTrinket(run, 1), 0)
end)

T.test("reroll_cards_only", function()
  local run = opened(20)
  local packs = run.shop.packs
  run.shop.cards = { false, false }
  T.eq(ns.Shop.reroll(run), true)
  T.ok(rawequal(run.shop.packs, packs))
  T.ok(run.shop.cards[1] and run.shop.cards[2])
  T.eq(run.gold, 15)
  T.eq(run.shop.rerollCost, 6)
  run.gold = 5
  local ok, err = ns.Shop.reroll(run)
  T.eq({ ok, err }, { false, "gold" })
  T.eq(run.shop.rerollCost, 6)
end)
