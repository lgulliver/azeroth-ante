local ns, T = ...

-- Rules checked against the Balatro wiki (balatrowiki.org, v1.0.1).

local function freshRun(seed)
  local run = ns.Run.new(seed or 7, "ADVENTURER")
  run.phase, run.gold = "shop", 1000
  return run
end

-- Opens a free pack of `packType` and returns its choices.
local function openPack(run, packType, size)
  run.shop = { cards = {}, packs = { { type = packType, size = size or "normal", cost = 0 } }, rerollCost = 5 }
  T.ok(ns.Packs.open(run, 1), "pack opens")
  local choices = run.shop.openPack.choices
  run.shop.openPack = nil
  return choices
end

local function countIds(run, packType, opens)
  local counts, cards = {}, 0
  for _ = 1, opens do
    for _, item in ipairs(openPack(run, packType)) do
      cards = cards + 1
      if item.id then counts[item.id] = (counts[item.id] or 0) + 1 end
    end
  end
  return counts, cards
end

local function withStub(tbl, key, value, fn)
  local old = tbl[key]
  tbl[key] = value
  local ok, err = pcall(fn)
  tbl[key] = old
  if not ok then error(err, 0) end
end

T.test("hidden_relics_never_random", function()
  local run = freshRun()
  for _ = 1, 3000 do
    local item = ns.Consumables.random(run, "relic")
    T.ok(item.id ~= "LEGENDS" and item.id ~= "COSMOS", "rolled hidden relic " .. item.id)
  end
end)

T.test("hidden_relics_rare_pack_swaps", function()
  local run = freshRun()
  -- 0.3% per card: about 24 in 8000 cards.
  local counts, cards = countIds(run, "SPECTRAL", 4000)
  T.eq(cards, 8000)
  for _, id in ipairs({ "LEGENDS", "COSMOS" }) do
    local n = counts[id] or 0
    T.ok(n >= 8 and n <= 50, id .. " in Spectral packs: " .. n)
  end
  counts = countIds(run, "CELESTIAL", 3000)
  T.ok((counts.COSMOS or 0) >= 8 and (counts.COSMOS or 0) <= 50, "Black Hole in Celestial packs: " .. (counts.COSMOS or 0))
  T.eq(counts.LEGENDS, nil, "no Soul in Celestial packs")
  counts = countIds(run, "ARCANA", 3000)
  T.ok((counts.LEGENDS or 0) >= 8 and (counts.LEGENDS or 0) <= 50, "Soul in Arcana packs: " .. (counts.LEGENDS or 0))
  T.eq(counts.COSMOS, nil, "no Black Hole in Arcana packs without Omen Globe")
end)

T.test("boss_hand_and_discard_limits_are_exact", function()
  local run = freshRun()
  run.phase, run.blind = "blind", 3
  withStub(ns.Vouchers, "extraHands", function() return 2 end, function()
    withStub(ns.Vouchers, "extraDiscards", function() return 2 end, function()
      run.bosses[run.stage] = "ONYXIA"
      T.eq(ns.Run.blindHands(run), 1, "Onyxia: exactly one hand")
      run.bosses[run.stage] = "MUTANUS"
      T.eq(ns.Run.blindDiscards(run), 0, "Mutanus: no discards")
      run.bosses[run.stage] = "HOGGER"
      T.eq(ns.Run.blindHands(run), 6, "other bosses keep voucher hands")
    end)
  end)
end)

T.test("boss_minimum_stages_match_balatro", function()
  -- Plant 4; Water, Flint, Needle 2; Goad, Head, Window, Psychic any.
  local want = { HOGGER = 4, MUTANUS = 2, RIVENDARE = 2, ONYXIA = 2,
    VANCLEEF = 1, ARUGAL = 1, VAELASTRASZ = 1, HEROD = 1 }
  for id, stage in pairs(want) do T.eq(ns.Bosses.def[id].minStage, stage, id) end
end)

T.test("bosses_respect_minimum_stage", function()
  for seed = 1, 400 do
    local run = ns.Run.new(seed, "ADVENTURER")
    for stage = 1, 7 do
      local def = ns.Bosses.def[run.bosses[stage]]
      T.ok((def.minStage or 1) <= stage, def.id .. " drawn at stage " .. stage)
    end
  end
end)

T.test("bosses_spread_across_stages", function()
  local run = ns.Run.new(3, "ADVENTURER")
  local seen = {}
  for stage = 1, 7 do
    T.ok(not seen[run.bosses[stage]], "repeat boss " .. run.bosses[stage])
    seen[run.bosses[stage]] = true
  end
end)

T.test("boss_reroll_respects_minimum_stage", function()
  local run = freshRun(5)
  run.phase, run.stage, run.blind = "blind", 1, 1
  for _ = 1, 200 do
    run.bossRerollsUsed, run.gold = 0, 100
    withStub(ns.Vouchers, "bossRerolls", function() return 1 end, function()
      local ok, id = ns.Run.rerollBoss(run)
      T.ok(ok, "reroll allowed: " .. tostring(id))
      T.ok((ns.Bosses.def[id].minStage or 1) <= 1, id .. " rerolled in at stage 1")
    end)
  end
end)

T.test("shop_playing_card_costs_base_plus_edition", function()
  local run = freshRun()
  local seen = 0
  withStub(ns.Vouchers, "playingCardsInShop", function() return true end, function()
    withStub(ns.Vouchers, "illusion", function() return true end, function()
      for _ = 1, 400 do
        ns.Shop.open(run)
        for _, item in ipairs(run.shop.cards) do
          if item.type == "card" then
            seen = seen + 1
            T.eq(item.baseCost, 1 + (ns.CardTypes.ED_COST[item.ed] or 0), "card price")
            T.eq(item.seal, nil, "shop cards have no seal")
          end
        end
      end
    end)
  end)
  T.ok(seen > 20, "saw shop playing cards")
end)

local function editionRates(mod, rate, allowNegative, n)
  local r, counts = ns.RNG.new(99), {}
  for _ = 1, n do
    local ed = ns.CardTypes.pollEdition(r, mod, rate, allowNegative)
    if ed then counts[ed] = (counts[ed] or 0) + 1 end
  end
  for k, v in pairs(counts) do counts[k] = v / n end
  return counts
end

local function near(actual, expected, msg)
  T.ok(math.abs((actual or 0) - expected) < 0.002, msg .. ": " .. tostring(actual) .. " vs " .. expected)
end

T.test("edition_odds_match_balatro", function()
  local std = editionRates(2, 1, false, 200000) -- Standard pack cards
  near(std.POLY, 0.012, "pack poly")
  near(std.HOLO, 0.028, "pack holo")
  near(std.FOIL, 0.04, "pack foil")
  T.eq(std.NEGATIVE, nil, "no negative playing cards")
  local joker = editionRates(1, 1, true, 200000)
  near(joker.NEGATIVE, 0.003, "joker negative")
  near(joker.POLY, 0.003, "joker poly")
  near(joker.HOLO, 0.014, "joker holo")
  near(joker.FOIL, 0.02, "joker foil")
  local hone = editionRates(1, 2, true, 200000)
  near(hone.POLY, 0.009, "Hone poly")
  near(hone.HOLO, 0.028, "Hone holo")
end)

T.test("first_shop_has_buffoon_pack", function()
  for seed = 1, 30 do
    local run = ns.Run.new(seed, "ADVENTURER")
    run.gold = 100
    ns.Shop.open(run)
    local pack = run.shop.packs[1]
    T.eq({ pack.type, pack.size }, { "BUFFOON", "normal" }, "first shop pack")
  end
end)

T.test("discount_rounds_half_down", function()
  local run = freshRun()
  withStub(ns.Vouchers, "discount", function() return 0.25 end, function()
    T.eq(ns.Vouchers.price(run, 6), 4)
    T.eq(ns.Vouchers.price(run, 10), 7)
    T.eq(ns.Vouchers.price(run, 5), 4)
    T.eq(ns.Vouchers.price(run, 1), 1)
  end)
  withStub(ns.Vouchers, "discount", function() return 0.5 end, function()
    T.eq(ns.Vouchers.price(run, 3), 1)
    T.eq(ns.Vouchers.price(run, 2), 1)
  end)
end)

T.test("shop_consumables_are_not_duplicated", function()
  local run = freshRun()
  local n = #ns.Scrolls.order
  local keep = { [ns.Scrolls.order[n - 1]] = true, [ns.Scrolls.order[n]] = true }
  run.consumables = {}
  for i = 1, n - 2 do run.consumables[i] = { kind = "scroll", id = ns.Scrolls.order[i] } end
  for _ = 1, 300 do
    ns.Shop.open(run)
    local shown = {}
    for _, item in ipairs(run.shop.cards) do
      if item.type == "scroll" then
        T.ok(keep[item.id], "held scroll offered: " .. item.id)
      end
      if item.type == "scroll" or item.type == "tome" then
        T.ok(not shown[item.id], "same consumable in two slots")
        shown[item.id] = true
      end
    end
  end
end)

T.test("mirror_image_retriggers_end_of_round_gold", function()
  local run = ns.Run.new(4, "ADVENTURER")
  run.phase, run.stage, run.blind, run.gold = "play", 1, 1, 0
  run.hand = { { id = 900, rank = 5, suit = "S", enh = "GOLD" } }
  run.trinkets = { ns.Trinkets.create(run, "MIRROR_IMAGE") }
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.held, 6, "Gold card held with Mirror Image pays twice")
end)
