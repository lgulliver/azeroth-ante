local ns, T = ...

local function offered(kind, size, gold)
  local run = ns.Run.new(42, "ADVENTURER")
  run.phase, run.gold = "shop", gold or 100
  ns.Shop.open(run)
  run.shop.packs[1] = { type = kind or "ARCANA", size = size or "mega", cost = 8 }
  return run
end

T.test("open_pack_charges_and_sizes", function()
  local run = offered()
  T.eq(ns.Packs.open(run, 1), true)
  T.eq(run.gold, 92)
  T.eq(run.shop.packs[1], false)
  local pack = run.shop.openPack
  T.eq({ pack.type, pack.size, #pack.choices, pack.picksLeft, #pack.hand }, { "ARCANA", "mega", 5, 2, 8 })
  for _, card in ipairs(pack.hand) do T.ok(rawequal(card, ns.Deck.find(run, card.id))) end
end)

T.test("all_pack_sizes_and_kinds", function()
  for _, kind in ipairs({ "ARCANA", "CELESTIAL", "SPECTRAL", "BUFFOON", "STANDARD" }) do
    for _, size in ipairs({ "normal", "jumbo", "mega" }) do
      local run = offered(kind, size)
      T.eq(ns.Packs.open(run, 1), true)
      local pack = run.shop.openPack
      local small = kind == "SPECTRAL" or kind == "BUFFOON"
      T.eq(#pack.choices, size == "normal" and (small and 2 or 3) or (small and 4 or 5))
      T.eq(pack.picksLeft, size == "mega" and 2 or 1)
      T.eq(pack.hand ~= nil, kind == "ARCANA" or kind == "SPECTRAL")
    end
  end
end)

T.test("open_errors_do_not_charge", function()
  local run = offered(nil, nil, 7)
  local ok, err = ns.Packs.open(run, 1)
  T.eq({ ok, err }, { false, "gold" })
  T.eq(run.gold, 7)
  ok, err = ns.Packs.open(run, 3)
  T.eq({ ok, err }, { false, "gone" })
end)

T.test("consumable_pack_choices_distinct_over_seeds", function()
  for seed = 1, 300 do
    for _, kind in ipairs({ "ARCANA", "CELESTIAL", "SPECTRAL" }) do
      local run = offered(kind)
      run.rng = ns.RNG.new(seed)
      T.eq(ns.Packs.open(run, 1), true)
      local seen = {}
      for _, item in ipairs(run.shop.openPack.choices) do
        T.ok(not seen[item.id], kind .. " duplicate at seed " .. seed)
        seen[item.id] = true
      end
    end
  end
end)

T.test("consumable_pack_duplicates_only_after_pool_exhausted", function()
  local order = ns.Scrolls.order
  ns.Scrolls.order = { "BLESSING", "FURY" }
  local ok, err = pcall(function()
    local run = offered("ARCANA")
    T.eq(ns.Packs.open(run, 1), true)
    local choices = run.shop.openPack.choices
    T.eq(#choices, 5)
    T.ok(choices[1].id ~= choices[2].id)
    for _, item in ipairs(choices) do
      T.ok(item.id == "BLESSING" or item.id == "FURY")
    end
  end)
  ns.Scrolls.order = order
  if not ok then error(err) end
end)

T.test("buffoon_exhausted_pool_has_no_false_choices", function()
  for remaining = 0, 1 do
    local run = offered("BUFFOON")
    for i, id in ipairs(ns.Trinkets.order) do
      if i > remaining then run.trinkets[#run.trinkets + 1] = { id = id } end
    end
    run.maxTrinkets = #run.trinkets + 1
    T.eq(ns.Packs.open(run, 1), true)
    local pack = run.shop.openPack
    T.eq(#pack.choices, remaining)
    T.eq(pack.picksLeft, remaining)
    for _, item in pairs(pack.choices) do T.ok(type(item) == "table") end
    if remaining == 1 then
      T.eq(pack.choices[1].id, ns.Trinkets.order[1])
      T.eq(ns.Packs.pick(run, 1), true)
      T.eq(run.shop.openPack, nil)
    else
      ns.Packs.skip(run)
      T.eq(run.shop.openPack, nil)
    end
  end
end)

T.test("pick_scroll_uses_on_pack_hand", function()
  local run = offered()
  ns.Packs.open(run, 1)
  local pack = run.shop.openPack
  pack.choices[1] = { kind = "scroll", id = "BLESSING" }
  run.maxConsumables = 0
  local ok, err = ns.Packs.pick(run, 1, { 1, 1 })
  T.eq(ok, false)
  T.ok(err)
  T.eq(pack.picksLeft, 2)
  local outcome
  ok, err, outcome = ns.Packs.pick(run, 1, { 2 })
  T.eq(ok, true)
  T.eq(pack.hand[2].enh, "BONUS")
  T.eq(outcome.changed, { pack.hand[2].id })
  T.eq(pack.choices[1], false)
  T.eq(pack.picksLeft, 1)
  T.eq(#run.consumables, 0)
  T.eq(ns.Packs.pick(run, 1), false)
  pack.choices[2] = { kind = "scroll", id = "BLESSING" }
  T.eq(ns.Packs.pick(run, 2, { 1 }), true)
  T.eq(run.shop.openPack, nil)
end)

T.test("pick_tome_applies_without_slot", function()
  local run = offered("CELESTIAL", "normal")
  ns.Packs.open(run, 1)
  run.maxConsumables = 0
  local item = run.shop.openPack.choices[1]
  T.eq(item.kind, "tome")
  T.eq(ns.Packs.pick(run, 1), true)
  T.eq(run.handLevels[item.id], 2)
  T.eq(#run.consumables, 0)
  T.eq(run.shop.openPack, nil)
end)

T.test("celestial_hides_secret_tomes", function()
  local run = offered("CELESTIAL")
  for _ = 1, 100 do
    run.shop.packs[1] = { type = "CELESTIAL", size = "mega", cost = 0 }
    ns.Packs.open(run, 1)
    for _, item in ipairs(run.shop.openPack.choices) do T.ok(not ns.Hands.def[item.id].secret) end
    ns.Packs.skip(run)
  end
end)

T.test("pick_relic_uses_pack_hand", function()
  local run = offered("SPECTRAL")
  ns.Packs.open(run, 1)
  run.shop.openPack.choices[1] = { kind = "relic", id = "RADIANCE" }
  local ok = ns.Packs.pick(run, 1, { 1 })
  T.eq(ok, true)
  T.ok(run.shop.openPack.hand[1].ed)
end)

T.test("buffoon_distinct_unowned_and_slots", function()
  local run = offered("BUFFOON")
  run.trinkets = { { id = "BLOODLUST", ed = "NEGATIVE" } }
  ns.Packs.open(run, 1)
  local pack, seen = run.shop.openPack, {}
  for _, item in ipairs(pack.choices) do
    T.ok(item.id ~= "BLOODLUST" and not seen[item.id])
    seen[item.id] = true
  end
  pack.choices[1] = { type = "trinket", id = "FORTITUDE", ed = "FOIL", cost = 6 }
  run.maxTrinkets = 0
  local ok, err = ns.Packs.pick(run, 1)
  T.eq({ ok, err }, { false, "slots" })
  T.eq(pack.picksLeft, 2)
  run.maxTrinkets = 1
  T.eq(ns.Packs.pick(run, 1), true)
  T.eq(run.trinkets[2], { id = "FORTITUDE", ed = "FOIL" })
end)

T.test("pick_standard_adds_to_deck", function()
  local run = offered("STANDARD", "normal")
  ns.Packs.open(run, 1)
  local card = run.shop.openPack.choices[1]
  T.eq(#run.deck, 52)
  T.eq(card.id, nil)
  T.ok(card.rank >= 2 and card.rank <= 14 and card.suit)
  T.eq(ns.Packs.pick(run, 1), true)
  T.eq(#run.deck, 53)
  T.ok(rawequal(run.deck[53], card))
  T.eq(card.id, 53)
end)

T.test("standard_rolls_types_without_negative_and_keeps_stone_rank", function()
  local run, enh, seals, editions, stones = offered("STANDARD"), 0, 0, 0, 0
  for _ = 1, 1000 do
    run.shop.packs[1] = { type = "STANDARD", size = "mega", cost = 0 }
    ns.Packs.open(run, 1)
    for _, card in ipairs(run.shop.openPack.choices) do
      T.ok(card.rank >= 2 and card.rank <= 14 and card.suit)
      T.eq(card.id, nil)
      T.ok(card.ed ~= "NEGATIVE")
      if card.enh then enh = enh + 1 end
      if card.enh == "STONE" then stones = stones + 1 end
      if card.seal then seals = seals + 1 end
      if card.ed then editions = editions + 1 end
    end
    ns.Packs.skip(run)
  end
  T.ok(enh > 1800 and enh < 2200, "enhancement frequency")
  T.ok(seals > 850 and seals < 1150, "seal frequency")
  T.ok(editions > 120 and editions < 250, "edition frequency")
  T.ok(stones > 0)
  T.eq(#run.deck, 52)
end)

T.test("skip_closes", function()
  local run = offered()
  ns.Packs.open(run, 1)
  ns.Packs.skip(run)
  T.eq(run.shop.openPack, nil)
  T.eq(run.gold, 92)
end)

T.test("open_pack_survives_save", function()
  local run, db = offered(), {}
  ns.Packs.open(run, 1)
  ns.Save.store(db, run)
  local loaded = ns.Save.load(db)
  T.eq(loaded.shop.openPack, run.shop.openPack)
  T.eq(loaded.rng, run.rng)
  for _, card in ipairs(loaded.shop.openPack.hand) do
    T.ok(rawequal(card, ns.Deck.find(loaded, card.id)), "pack hand must relink to deck")
  end
  loaded.shop.openPack.choices[1] = { kind = "scroll", id = "BLESSING" }
  T.eq(ns.Packs.pick(loaded, 1, { 1 }), true)
  local card = loaded.shop.openPack.hand[1]
  T.eq(ns.Deck.find(loaded, card.id).enh, "BONUS")
end)

T.test("shop_locked_while_pack_open", function()
  local run = offered()
  ns.Packs.open(run, 1)
  for _, action in ipairs({ function() return ns.Shop.buy(run, 1) end,
    function() return ns.Shop.reroll(run) end, function() return ns.Run.nextBlind(run) end,
    function() return ns.Packs.open(run, 2) end }) do
    local ok, err = action()
    T.eq({ ok, err }, { false, "pack" })
    T.eq(run.gold, 92)
    T.eq(run.phase, "shop")
  end
end)

T.test("pack_discount", function()
  local run = offered()
  run.vouchers.LIQUIDATION = true
  ns.Shop.open(run)
  for _, offer in ipairs(run.shop.packs) do
    T.eq(offer.cost, ns.Vouchers.price(run, ns.Packs.SIZES[offer.size].cost))
  end
  local offer = run.shop.packs[1]
  local gold = run.gold
  T.eq(ns.Packs.open(run, 1), true)
  T.eq(run.gold, gold - offer.cost)
  T.eq(run.shop.openPack.paid, offer.cost)
end)

T.test("omen_globe_relics", function()
  local run, relics, total = offered(), 0, 0
  run.vouchers.OMEN_GLOBE = true
  for _ = 1, 1000 do
    run.gold = 100
    run.shop.packs[1] = { type = "ARCANA", size = "mega", cost = 8 }
    T.eq(ns.Packs.open(run, 1), true)
    local seen = {}
    for _, item in ipairs(run.shop.openPack.choices) do
      local key = item.kind .. ":" .. item.id
      T.ok(not seen[key])
      seen[key] = true
      if item.kind == "relic" then
        T.ok(ns.Relics.def[item.id])
        relics = relics + 1
      else T.eq(item.kind, "scroll") end
      total = total + 1
    end
    ns.Packs.skip(run)
  end
  T.ok(relics / total > 0.17 and relics / total < 0.23)
end)

T.test("telescope_most_played", function()
  local run = offered("CELESTIAL")
  run.vouchers.TELESCOPE = true
  for _, plays in ipairs({ { PAIR = 10, FLUSH = 4 }, { PAIR = 5, FLUSH = 5 },
    { FLUSH_FIVE = 20, PAIR = 5 } }) do
    run.handPlays = plays
    run.seenHands.FLUSH_FIVE = plays.FLUSH_FIVE and true or nil
    run.shop.packs[1] = { type = "CELESTIAL", size = "mega", cost = 8 }
    T.eq(ns.Packs.open(run, 1), true)
    local expected = plays.FLUSH_FIVE and "FLUSH_FIVE" or (plays.FLUSH == 5 and "FLUSH" or "PAIR")
    T.eq(run.shop.openPack.choices[1], { kind = "tome", id = expected })
    local seen = {}
    for _, item in ipairs(run.shop.openPack.choices) do
      T.ok(not seen[item.id])
      seen[item.id] = true
    end
    ns.Packs.skip(run)
  end
  run.handPlays, run.seenHands = {}, {}
  local seen = {}
  for _ = 1, 100 do
    run.gold = 100
    run.shop.packs[1] = { type = "CELESTIAL", size = "normal", cost = 4 }
    ns.Packs.open(run, 1)
    local id = run.shop.openPack.choices[1].id
    T.ok(not ns.Hands.def[id].secret)
    seen[id] = true
    ns.Packs.skip(run)
  end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  T.ok(count > 1)
end)

T.test("pack_events_emitted", function()
  local profile, events = ns.Profile, {}
  local ok, err = pcall(function()
    ns.Profile = { onEvent = function(name, amount) events[#events + 1] = { name, amount } end }
    local run = offered("ARCANA", "normal")
    ns.Packs.open(run, 1)
    run.shop.openPack.choices[1] = { kind = "scroll", id = "BLESSING" }
    T.eq(ns.Packs.pick(run, 1), false)
    T.eq(ns.Packs.pick(run, 1, { 1 }), true)
    run.shop.packs[1] = { type = "CELESTIAL", size = "normal", cost = 4 }
    ns.Packs.open(run, 1)
    T.eq(ns.Packs.pick(run, 1), true)
    T.eq(events, { { "spend", 8 }, { "scrollFromPackUsed", 1 },
      { "spend", 4 }, { "tomeFromPackUsed", 1 } })
    ns.Profile = nil
    run.shop.packs[1] = { type = "CELESTIAL", size = "normal", cost = 4 }
    T.eq(ns.Packs.open(run, 1), true)
    T.eq(ns.Packs.pick(run, 1), true)
  end)
  ns.Profile = profile
  if not ok then error(err) end
end)
