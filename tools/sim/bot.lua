-- Greedy bot for the balance sim. Plays whole runs through ns.Run; no WoW, no UI.
-- Usage: local bot = dofile("tools/sim/bot.lua")(ns); bot.playRun(run)
return function(ns)
  local Run, Scoring, Shop, Packs, Consumables = ns.Run, ns.Scoring, ns.Shop, ns.Packs, ns.Consumables
  local Vouchers = ns.Vouchers
  local bot = {}

  -- Every purchase below checks price <= gold itself: the bot never goes into debt, even with Credit Card.
  -- Trinkets are scored: rarity (1/2/3) plus 3 for any scoring hook; the bot never reorders them.
  local RARITY_WEIGHT = { common = 1, uncommon = 2, rare = 3 }
  local SCORING_HOOKS = { "onHand", "onCard", "before", "retrigger", "onHeld", "heldRetrigger",
    "otherTrinket", "copies" }
  local function isScoring(def)
    for _, hook in ipairs(SCORING_HOOKS) do
      if def[hook] then return true end
    end
    return false
  end
  local function trinketWeight(offer)
    local def = ns.Trinkets.def[offer.id]
    if not def then return 0 end
    return (RARITY_WEIGHT[def.rarity] or 0) + (isScoring(def) and 3 or 0)
  end
  -- Rule, interest and round-end payout trinkets only; skipped while a scoring one is affordable.
  local function isEconomyOnly(offer)
    local def = ns.Trinkets.def[offer.id]
    return def ~= nil and not isScoring(def) and (def.rule or def.interestBonus or def.onRoundEnd) ~= nil
  end

  -- Scrolls worth using on the highest-rank cards, best first.
  local SCROLL_PRIORITY = {
    "FURY", "BLESSING", "FORTUNE", "THORIUM", "CRYSTAL", "FEL", "STRENGTH",
    "STARS", "SUMMONING", "KNOWLEDGE", "GREED", "THRIFT", "CHANCE",
  }
  -- Only buy a Scroll when gold stays at or above this (Scroll cost 3 + a 5 gold cushion).
  local SCROLL_BUY_RESERVE = 8
  local SCROLL_RANK = {}
  for i, id in ipairs(SCROLL_PRIORITY) do SCROLL_RANK[id] = i end

  -- Vouchers worth buying when affordable (either tier); anything else is skipped.
  local VOUCHER_PRIORITY = {
    "GRABBER", "NACHO_TONG", "WASTEFUL", "RECYCLOMANCY", "PAINT_BRUSH", "PALETTE",
    "SEED_MONEY", "MONEY_TREE", "OVERSTOCK", "OVERSTOCK_PLUS",
  }
  local VOUCHER_RANK = {}
  for i, id in ipairs(VOUCHER_PRIORITY) do VOUCHER_RANK[id] = i end

  local function combos(n, maxK)
    local out = {}
    local function rec(start, cur)
      if #cur > 0 then
        local copy = {}
        for i, v in ipairs(cur) do copy[i] = v end
        out[#out + 1] = copy
      end
      if #cur == maxK then return end
      for i = start, n do
        cur[#cur + 1] = i
        rec(i + 1, cur)
        cur[#cur] = nil
      end
    end
    rec(1, {})
    return out
  end
  local comboCache = {}
  local function combosFor(n)
    comboCache[n] = comboCache[n] or combos(n, 5)
    return comboCache[n]
  end

  -- Best-scoring playable selection. Fresh ctx and a copied RNG: run state never moves.
  local function bestPlay(run)
    local best, bestIdx = -1, nil
    for _, idx in ipairs(combosFor(#run.hand)) do
      if Run.canPlay(run, idx) then
        local chosen, picked, held = {}, {}, {}
        for i, index in ipairs(idx) do
          chosen[i] = run.hand[index]
          picked[index] = true
        end
        for i, card in ipairs(run.hand) do
          if not picked[i] then held[#held + 1] = card end
        end
        local result = Scoring.score(Run.scoreCtx(run, chosen, held, { rng = { s = run.rng.s } }))
        if result.total > best then best, bestIdx = result.total, idx end
      end
    end
    return best, bestIdx
  end

  local function discardPlan(run, keep)
    local kept = {}
    for _, index in ipairs(keep) do kept[index] = true end
    local out = {}
    for i, card in ipairs(run.hand) do
      if not kept[i] then out[#out + 1] = i end
    end
    table.sort(out, function(a, b) return ns.Cards.chipValue(run.hand[a]) < ns.Cards.chipValue(run.hand[b]) end)
    while #out > 5 do out[#out] = nil end
    return out
  end

  local function highRankIdx(cards, count)
    local order = {}
    for i, card in ipairs(cards) do
      if not ns.Cards.isStone(card) then order[#order + 1] = i end
    end
    table.sort(order, function(a, b)
      if cards[a].rank ~= cards[b].rank then return cards[a].rank > cards[b].rank end
      return a < b
    end)
    local out = {}
    for i = 1, math.min(count, #order) do out[i] = order[i] end
    return out
  end

  local function mostPlayed(run, played)
    local best, n = nil, 0
    for id, count in pairs(played or run.bot.played) do
      if count > n or (count == n and best and id < best) then best, n = id, count end
    end
    return best
  end

  -- Which cards (indexes into `cards`) to use consumable `slot` on, or nil to leave it.
  -- Held Tomes and untargeted Relics/Scrolls need no cards; targeted Scrolls go on the best cards.
  local function usePlan(run, slot, cards)
    local item = run.consumables[slot]
    local def = item and Consumables.def(item)
    local want = item and (item.kind == "tome" or item.kind == "relic"
      or (item.kind == "scroll" and SCROLL_RANK[item.id]))
    if not (def and want) then return nil end
    local idx = {}
    if def.select then
      if cards then idx = highRankIdx(cards, def.select.max) end
      if not cards or #idx < def.select.min then return nil end
    end
    if Consumables.canUse(run, slot, idx) then return idx end
    return nil
  end

  local function useConsumables(run, cards)
    local slot = 1
    while slot <= #run.consumables do
      local idx = usePlan(run, slot, cards)
      local used = idx ~= nil and Consumables.use(run, slot, idx) ~= nil
      if not used then slot = slot + 1 end
    end
  end

  local function playBlind(run)
    Run.startBlind(run)
    useConsumables(run, run.hand)
    while run.phase == "play" do
      local best, idx = bestPlay(run)
      local need = (run.target - run.score) / run.handsLeft
      if best < need and best < run.target - run.score and run.discardsLeft > 0 then
        local plan = discardPlan(run, idx)
        if #plan > 0 then
          Run.discard(run, plan)
          idx = nil
        end
      end
      if idx then
        local result = Run.play(run, idx)
        run.bot.played[result.handId] = (run.bot.played[result.handId] or 0) + 1
      end
    end
  end

  -- The pack choice to take and the pack-hand indexes to aim it at, or nil to skip.
  local function choosePick(run, pack, played)
    local choice, idx, rankBest = nil, nil, 1e9
    for c, item in ipairs(pack.choices) do
      if item then
        local def = Consumables.def(item)
        local pick, sel = nil, {}
        if item.kind == "tome" then
          pick = (item.id == mostPlayed(run, played)) and 0 or 50
        elseif item.kind == "scroll" and SCROLL_RANK[item.id] and def then
          if def.select then sel = highRankIdx(pack.hand or {}, def.select.max) end
          local cards = {}
          for _, i in ipairs(sel) do cards[#cards + 1] = pack.hand[i] end
          if Consumables.canApply(run, item, cards) then pick = 10 + SCROLL_RANK[item.id] end
        end
        if pick and pick < rankBest then choice, idx, rankBest = c, sel, pick end
      end
    end
    return choice, idx
  end

  local function pickFromPack(run)
    while run.shop.openPack do
      local choice, idx = choosePick(run, run.shop.openPack)
      if not choice then break end
      if not Packs.pick(run, choice, idx) then break end
    end
    Packs.skip(run)
  end

  local function shop(run)
    useConsumables(run, nil)
    -- Trinkets, highest score first.
    local progress = true
    while progress do
      progress = false
      local bestI, bestWeight = nil, 0
      local function affordable(offer)
        return offer and offer.type == "trinket" and offer.cost <= run.gold
          and #run.trinkets < Run.trinketSlots(run)
      end
      local scoringAvailable = false
      for _, offer in ipairs(run.shop.cards) do
        if affordable(offer) and not isEconomyOnly(offer) and isScoring(ns.Trinkets.def[offer.id]) then
          scoringAvailable = true
        end
      end
      for i, offer in ipairs(run.shop.cards) do
        if affordable(offer) and not (scoringAvailable and isEconomyOnly(offer)) then
          local weight = trinketWeight(offer)
          if weight > bestWeight then bestI, bestWeight = i, weight end
        end
      end
      if bestI and Shop.buy(run, bestI) then progress = true end
    end
    -- The stage's voucher, when it is one the bot likes and it is affordable.
    local offer = run.shopVoucher
    if offer and VOUCHER_RANK[offer.id] and run.gold >= Vouchers.price(run, Vouchers.def[offer.id].cost) then
      Shop.buyVoucher(run)
    end
    -- Tomes for the most-played hand.
    local favourite = mostPlayed(run)
    for i, offer in ipairs(run.shop.cards) do
      if offer and offer.type == "tome" and offer.id == favourite and offer.cost <= run.gold then Shop.buy(run, i) end
    end
    -- Packs: Arcana or Celestial when flush enough.
    for i, offer in ipairs(run.shop.packs) do
      if offer and (offer.type == "ARCANA" or offer.type == "CELESTIAL")
        and run.gold >= 8 and offer.cost <= run.gold then
        if Packs.open(run, i) then pickFromPack(run) end
      end
    end
    -- Scrolls on offer.
    for i, offer in ipairs(run.shop.cards) do
      if offer and offer.type == "scroll" and SCROLL_RANK[offer.id] and run.gold >= SCROLL_BUY_RESERVE
        and offer.cost <= run.gold then
        Shop.buy(run, i)
      end
    end
    useConsumables(run, nil)
  end

  -- Decision pieces, exposed so a UI harness can drive the same choices through clicks.
  bot.bestPlay, bot.discardPlan, bot.usePlan = bestPlay, discardPlan, usePlan
  bot.choosePick, bot.mostPlayed = choosePick, mostPlayed
  bot.trinketWeight, bot.SCROLL_RANK, bot.VOUCHER_RANK = trinketWeight, SCROLL_RANK, VOUCHER_RANK

  function bot.playRun(run)
    run.bot = { played = {} }
    while run.phase ~= "won" and run.phase ~= "lost" do
      playBlind(run)
      if run.phase == "shop" then
        shop(run)
        Run.nextBlind(run)
      end
    end
    run.bot = nil
    return run.phase == "won"
  end

  return bot
end
