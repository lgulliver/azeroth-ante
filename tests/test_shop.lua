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
    for i = 1, 2 do
      local item = run.shop.cards[i]
      T.ok(item and (item.type == "scroll" or item.type == "tome"), "empty fallback slot")
    end
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
  T.eq(run.trinkets[2], { id = "BLOODLUST", ed = "FOIL", paid = 6 })
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
  T.eq(run.consumables, { { kind = "tome", id = "PAIR", paid = 3 }, { kind = "scroll", id = "BLESSING", paid = 3 } })
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

T.test("sell_value_includes_foil_surcharge", function()
  local run = opened(0)
  local trinket = { id = "BLOODLUST", ed = "FOIL" }
  T.eq(ns.Shop.sellValue(trinket), 5) -- Bloodlust costs 8; Foil adds 2.
  run.trinkets = { trinket }
  T.eq(ns.Shop.sellTrinket(run, 1), 5)
  T.eq(run.gold, 5)
end)

T.test("exhausted_shop_rerolls_both_consumable_types", function()
  local run, seen = opened(1000), {}
  for _, id in ipairs(ns.Trinkets.order) do run.trinkets[#run.trinkets + 1] = { id = id } end
  for _ = 1, 100 do
    T.eq(ns.Shop.reroll(run), true)
    for i = 1, 2 do
      local item = run.shop.cards[i]
      T.ok(item and (item.type == "scroll" or item.type == "tome"), "empty reroll slot")
      seen[item.type] = true
    end
    run.gold = 1000
  end
  T.ok(seen.scroll and seen.tome)
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

T.test("voucher_offer_eligibility", function()
  local run = opened()
  local profile = ns.Profile
  local ok, err = pcall(function()
    ns.Profile = nil
    for _, id in ipairs(ns.Vouchers.order) do run.vouchers[id] = true end
    run.vouchers.OVERSTOCK_PLUS = nil
    T.eq(ns.Shop.rollVoucher(run), false)
    ns.Profile = { hasAchievement = function(id) return id == "OVERSTOCK_PLUS" end }
    run.vouchers.OVERSTOCK = nil
    local offer = ns.Shop.rollVoucher(run)
    T.eq(offer.id, "OVERSTOCK")
    run.vouchers.OVERSTOCK = true
    offer = ns.Shop.rollVoucher(run)
    T.eq({ offer.id, offer.cost }, { "OVERSTOCK_PLUS", 5 })
    run.vouchers.OVERSTOCK_PLUS = true
    T.eq(ns.Shop.rollVoucher(run), false)
  end)
  ns.Profile = profile
  if not ok then error(err) end
end)

T.test("voucher_persists_until_boss", function()
  local run = opened()
  T.ok(run.shopVoucher)
  local offer = run.shopVoucher
  ns.Shop.reroll(run)
  T.ok(rawequal(run.shopVoucher, offer))
  ns.Run.winBlind(run)
  T.ok(rawequal(run.shopVoucher, offer))
  run.blind = 3
  ns.Run.winBlind(run)
  T.ok(run.shopVoucher and not rawequal(run.shopVoucher, offer))
  run.shopVoucher = false
  ns.Shop.open(run)
  T.eq(run.shopVoucher, false)
  run.stage = 8
  ns.Run.winBlind(run)
  T.eq(run.shopVoucher, nil)
end)

T.test("buy_voucher_charges_and_applies", function()
  local run = opened(0)
  run.shopVoucher = { id = "HIEROGLYPH", cost = 10 }
  T.eq({ ns.Shop.buyVoucher(run) }, { false, "gold" })
  run.gold, run.stage = 100, 3
  run.shop.openPack = {}
  T.eq({ ns.Shop.buyVoucher(run) }, { false, "pack" })
  run.shop.openPack = nil
  local offer = run.shopVoucher
  T.eq(ns.Shop.buyVoucher(run), true)
  T.eq(run.gold, 90)
  T.eq(run.stage, 2)
  T.eq(run.vouchers.HIEROGLYPH, true)
  T.eq(offer.paid, 10)
  T.eq(run.shopVoucher, false)
  T.eq({ ns.Shop.buyVoucher(run) }, { false, "gone" })
  run.shopVoucher = { id = "PETROGLYPH", cost = 10 }
  run.stage = 1
  T.eq(ns.Shop.buyVoucher(run), true)
  T.eq(run.stage, 1)
  T.eq(run.gold, 80)
end)

T.test("overstock_slots", function()
  local run = opened()
  run.vouchers.OVERSTOCK = true
  ns.Shop.open(run)
  T.eq(#run.shop.cards, 3)
  run.vouchers.OVERSTOCK_PLUS = true
  ns.Shop.reroll(run)
  T.eq(#run.shop.cards, 4)
end)

T.test("merchant_weights", function()
  local function share(base, upgrade, kind)
    local run, count = opened(), 0
    if base then run.vouchers[base] = true end
    if upgrade then run.vouchers[upgrade] = true end
    for _ = 1, 3000 do
      ns.Shop.open(run)
      for _, item in ipairs(run.shop.cards) do if item.type == kind then count = count + 1 end end
    end
    return count / 6000
  end
  for _, pair in ipairs({ { "TAROT_MERCHANT", "TAROT_TYCOON", "scroll" },
    { "PLANET_MERCHANT", "PLANET_TYCOON", "tome" } }) do
    local baseline = share(nil, nil, pair[3])
    local merchant = share(pair[1], nil, pair[3])
    local tycoon = share(pair[1], pair[2], pair[3])
    T.ok(baseline > 0.11 and baseline < 0.18)
    T.ok(merchant > 0.24 and merchant < 0.33)
    T.ok(tycoon > 0.52 and tycoon < 0.62)
  end
end)

T.test("hone_edition_mult", function()
  local function editions(voucher)
    local run, count = opened(), 0
    if voucher then run.vouchers[voucher] = true end
    for _ = 1, 10000 do
      local item = ns.Shop.rollTrinket(run, {})
      if item.ed and item.ed ~= "NEGATIVE" then count = count + 1 end
    end
    return count
  end
  local base, hone, glow = editions(), editions("HONE"), editions("GLOW_UP")
  T.ok(hone > base * 1.6 and hone < base * 2.5)
  T.ok(glow > base * 3.3 and glow < base * 4.8)
end)

T.test("magic_trick_cards", function()
  local run, plain, enhanced = opened(), 0, 0
  run.vouchers.MAGIC_TRICK = true
  for _ = 1, 300 do
    ns.Shop.open(run)
    for i, item in ipairs(run.shop.cards) do
      if item.type == "card" then
        plain = plain + 1
        T.ok(item.rank and item.suit and not item.enh and not item.ed and not item.seal)
        local count = #run.deck
        run.gold = 100
        T.eq(ns.Shop.buy(run, i), true)
        T.eq(#run.deck, count + 1)
        T.eq(run.deck[#run.deck].paid, item.cost)
      end
    end
  end
  run.vouchers.ILLUSION = true
  for _ = 1, 1000 do
    ns.Shop.open(run)
    for _, item in ipairs(run.shop.cards) do
      if item.type == "card" then
        T.ok(item.ed ~= "NEGATIVE")
        if item.enh or item.ed or item.seal then enhanced = enhanced + 1 end
      end
    end
  end
  T.ok(plain > 30 and enhanced > 50)
end)

T.test("reroll_surplus_cost", function()
  local run = opened(10)
  run.vouchers.REROLL_SURPLUS = true
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.gold, 7)
  run.vouchers.REROLL_GLUT = true
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.gold, 5)
  run.shop.rerollCost, run.gold = 1, 0
  T.eq(ns.Shop.reroll(run), true)
  T.eq(run.gold, 0)
end)

T.test("discount_floor_and_sell", function()
  local run = opened()
  run.vouchers.LIQUIDATION = true
  run.shopVoucher = nil
  T.eq(ns.Vouchers.price(run, 1), 1)
  ns.Shop.open(run)
  for _, item in ipairs(run.shop.cards) do
    local raw = item.type == "trinket" and ns.Trinkets.def[item.id].cost
      + (ns.CardTypes.ED_COST[item.ed] or 0) or ns.Consumables.COST[item.type]
    T.eq(item.cost, ns.Vouchers.price(run, raw))
  end
  T.eq(run.shopVoucher.cost, 5)
  T.eq(ns.Shop.buyVoucher(run), true)
  T.eq(run.gold, 95)
  run.shop.cards[1] = { type = "trinket", id = "BLOODLUST", cost = 5 }
  T.eq(ns.Shop.buy(run, 1), true)
  T.eq(run.trinkets[1].paid, 5)
  T.eq(ns.Shop.sellValue(run.trinkets[1]), 2)
end)

T.test("events_emitted", function()
  local profile, events = ns.Profile, {}
  local ok, err = pcall(function()
    ns.Profile = { onEvent = function(name, amount) events[#events + 1] = { name, amount } end }
    local run = opened()
    run.shopVoucher = { id = "BLANK", cost = 10 }
    T.eq(ns.Shop.buyVoucher(run), true)
    run.shop.cards = { { type = "scroll", id = "BLESSING", cost = 3 },
      { type = "tome", id = "PAIR", cost = 3 },
      { type = "card", rank = 2, suit = ns.Cards.SUITS[1], cost = 1 },
      { type = "trinket", id = "BLOODLUST", cost = 8 } }
    for i = 1, 4 do T.eq(ns.Shop.buy(run, i), true) end
    run.vouchers.REROLL_SURPLUS = true
    T.eq(ns.Shop.reroll(run), true)
    T.eq(events, { { "spend", 10 }, { "voucherBought", 1 }, { "blankBought", 1 },
      { "spend", 3 }, { "scrollBought", 1 }, { "spend", 3 }, { "tomeBought", 1 },
      { "spend", 1 }, { "cardBought", 1 }, { "spend", 8 }, { "reroll", 1 }, { "spend", 3 } })
    ns.Profile = nil
    ns.Shop.open(run)
    T.eq(ns.Shop.reroll(run), true)
  end)
  ns.Profile = profile
  if not ok then error(err) end
end)

T.test("discount_purchase_reprices_current_stock", function()
  local run = opened()
  local prices = {}
  for i, item in ipairs(run.shop.cards) do prices[i] = item.cost end
  local packPrices = {}
  for i, item in ipairs(run.shop.packs) do packPrices[i] = item.cost end
  run.shopVoucher = { id = "CLEARANCE_SALE", cost = 10 }
  T.eq(ns.Shop.buyVoucher(run), true)
  for i, item in ipairs(run.shop.cards) do T.eq(item.cost, ns.Vouchers.price(run, prices[i])) end
  for i, item in ipairs(run.shop.packs) do T.eq(item.cost, ns.Vouchers.price(run, packPrices[i])) end
  T.eq(run.gold, 90)
  run.shopVoucher = { id = "LIQUIDATION", cost = 8 }
  T.eq(ns.Shop.buyVoucher(run), true)
  T.eq(run.gold, 82)
  for i, item in ipairs(run.shop.cards) do T.eq(item.cost, ns.Vouchers.price(run, prices[i])) end
  for i, item in ipairs(run.shop.packs) do T.eq(item.cost, ns.Vouchers.price(run, packPrices[i])) end
end)

T.test("overstock_purchase_expands_current_stock", function()
  local run = opened()
  local first, second = run.shop.cards[1], run.shop.cards[2]
  run.shopVoucher = { id = "OVERSTOCK", cost = 10 }
  T.eq(ns.Shop.buyVoucher(run), true)
  T.eq(#run.shop.cards, 3)
  T.ok(rawequal(run.shop.cards[1], first) and rawequal(run.shop.cards[2], second))
  local third = run.shop.cards[3]
  run.shop.cards[1] = false
  run.shopVoucher = { id = "OVERSTOCK_PLUS", cost = 10 }
  T.eq(ns.Shop.buyVoucher(run), true)
  T.eq(#run.shop.cards, 4)
  T.eq(run.shop.cards[1], false)
  T.ok(rawequal(run.shop.cards[3], third))
  local seen = {}
  for _, item in ipairs(run.shop.cards) do
    if item and item.type == "trinket" then
      T.ok(not seen[item.id])
      seen[item.id] = true
    end
  end
end)
