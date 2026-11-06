local _, ns = ...

local Shop = {}

local function event(name, amount)
  if ns.Profile and ns.Profile.onEvent then ns.Profile.onEvent(name, amount) end
end

function Shop.rollVoucher(run)
  local pool = {}
  for _, id in ipairs(ns.Vouchers.order) do
    local def = ns.Vouchers.def[id]
    if not ns.Vouchers.owns(run, id) and (def.tier == 1
      or (ns.Vouchers.owns(run, def.base) and ns.Profile and ns.Profile.hasAchievement
        and ns.Profile.hasAchievement(def.achievement))) then
      pool[#pool + 1] = id
    end
  end
  if #pool == 0 then return false end
  local id = ns.RNG.pick(run.rng, pool)
  return { id = id, cost = ns.Vouchers.price(run, ns.Vouchers.def[id].cost) }
end

function Shop.rollEdition(run, allowNegative)
  local mult = ns.Vouchers.editionMult(run)
  if mult == 1 then return ns.CardTypes.rollEdition(run.rng, allowNegative) end
  local roll, edge = ns.RNG.next(run.rng), 0
  for _, id in ipairs({ "NEGATIVE", "POLY", "HOLO", "FOIL" }) do
    if id ~= "NEGATIVE" or allowNegative then
      edge = edge + ns.CardTypes.ED_ODDS[id] * (id == "NEGATIVE" and 1 or mult)
      if roll < edge then return id end
    end
  end
end

local function owns(run, id)
  for _, trinket in ipairs(run.trinkets) do
    if trinket.id == id then return true end
  end
  return false
end

-- Shared with Buffoon packs: distinct, unowned trinkets at 70/25/5 rarity.
function Shop.rollTrinket(run, taken)
  local byRarity = { common = {}, uncommon = {}, rare = {} }
  local any = {}
  local dupes = ns.TrinketRules.has(run.trinkets, "SHOWMAN")
  for _, id in ipairs(ns.Trinkets.order) do
    if not taken[id] and (dupes or not owns(run, id)) and ns.Trinkets.inPool(run, id) then
      any[#any + 1] = id
      local list = byRarity[ns.Trinkets.def[id].rarity]
      list[#list + 1] = id
    end
  end
  if #any == 0 then return false end
  local roll = ns.RNG.next(run.rng) * 100
  local rarity = roll < 70 and "common" or (roll < 95 and "uncommon" or "rare")
  local pool = byRarity[rarity]
  if #pool == 0 then pool = any end
  local id = ns.RNG.pick(run.rng, pool)
  taken[id] = true
  local ed = Shop.rollEdition(run, true)
  return { type = "trinket", id = id, ed = ed,
    cost = ns.Trinkets.def[id].cost + (ns.CardTypes.ED_COST[ed] or 0) }
end

-- Voucher-discounted price of an offer; Astronomer makes Tomes and Celestial packs free.
function Shop.priceOf(run, item)
  local free = ns.TrinketRules.has(run.trinkets, "ASTRONOMER")
    and (item.type == "tome" or item.type == "CELESTIAL")
  if free then return 0 end
  return ns.Vouchers.price(run, item.baseCost or item.cost)
end

-- Re-prices every open offer; called after anything that can change prices mid-shop.
function Shop.reprice(run)
  local shop = run.shop
  if not shop then return end
  for _, stock in ipairs({ shop.cards, shop.packs }) do
    for _, item in ipairs(stock) do
      if item then
        item.baseCost = item.baseCost or item.cost
        item.cost = Shop.priceOf(run, item)
      end
    end
  end
end

local function generateCards(run, cards)
  cards = cards or {}
  local taken = {}
  for _, item in ipairs(cards) do
    if item and item.type == "trinket" then taken[item.id] = true end
  end
  local scroll, tome = ns.Vouchers.scrollWeight(run), ns.Vouchers.tomeWeight(run)
  local playing = ns.Vouchers.playingCardsInShop(run) and 4 or 0
  for i = #cards + 1, ns.Vouchers.shopCardSlots(run) do
    local roll = ns.RNG.next(run.rng) * (20 + scroll + tome + playing)
    if roll < 20 then
      cards[i] = Shop.rollTrinket(run, taken)
      if not cards[i] then roll = 20 + ns.RNG.next(run.rng) * (scroll + tome + playing) end
    end
    if not cards[i] then
      if roll >= 20 + scroll + tome then
        local card = ns.Packs.rollCard(run, ns.Vouchers.illusion(run))
        card.type = "card"
        card.cost = 1 + (card.enh and 1 or 0) + (card.seal and 1 or 0)
          + (ns.CardTypes.ED_COST[card.ed] or 0)
        cards[i] = card
      else
        local kind = roll < 20 + scroll and "scroll" or "tome"
        local item = ns.Consumables.random(run, kind)
        cards[i] = { type = kind, id = item.id, cost = ns.Consumables.COST[kind] }
      end
    end
    cards[i].baseCost = cards[i].cost
    cards[i].cost = Shop.priceOf(run, cards[i])
  end
  return cards
end

function Shop.open(run)
  if run.shopVoucher == nil then run.shopVoucher = Shop.rollVoucher(run) end
  run.shop = {
    cards = generateCards(run),
    packs = { ns.Packs.random(run), ns.Packs.random(run) },
    rerollCost = 5, freeRerolls = ns.TrinketRules.count(run.trinkets, "CHAOS"),
  }
  Shop.reprice(run)
end

local function buyItem(run, i)
  local shop = run.shop
  if shop and shop.openPack then return false, "pack" end
  local item = shop and shop.cards[i]
  if not item then return false, "gone" end
  if not ns.Run.canAfford(run, item.cost) then return false, "gold" end
  if item.type == "trinket" then
    local slots = ns.Run.trinketSlots(run) + (item.ed == "NEGATIVE" and 1 or 0)
    if #run.trinkets >= slots then return false, "slots" end
    run.trinkets[#run.trinkets + 1] = ns.Trinkets.create(run, item.id, item.ed, item.cost)
    if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain("trinket", item.id) end
  elseif item.type == "card" then
    ns.Deck.add(run, { rank = item.rank, suit = item.suit, enh = item.enh,
      ed = item.ed, seal = item.seal, paid = item.cost })
  else
    if not ns.Consumables.add(run, { kind = item.type, id = item.id, paid = item.cost }) then
      return false, "slots"
    end
  end
  item.paid = item.cost
  run.gold = run.gold - item.paid
  shop.cards[i] = false
  event("spend", item.paid)
  if item.type == "scroll" then event("scrollBought", 1)
  elseif item.type == "tome" then event("tomeBought", 1)
  elseif item.type == "card" then event("cardBought", 1) end
  return true
end

function Shop.buy(run, i)
  return ns.Run.withMods(run, function() return buyItem(run, i) end)
end

function Shop.buyVoucher(run)
  if run.shop and run.shop.openPack then return false, "pack" end
  local offer = run.shopVoucher
  if not offer or ns.Vouchers.owns(run, offer.id) then return false, "gone" end
  local paid = ns.Vouchers.price(run, ns.Vouchers.def[offer.id].cost)
  if not ns.Run.canAfford(run, paid) then return false, "gold" end
  offer.paid = paid
  run.gold = run.gold - paid
  run.vouchers[offer.id] = true
  ns.Vouchers.onBuy(run, offer.id)
  run.shopVoucher = false
  if run.shop and (offer.id == "OVERSTOCK" or offer.id == "OVERSTOCK_PLUS") then
    generateCards(run, run.shop.cards)
  end
  if run.shop and (offer.id == "CLEARANCE_SALE" or offer.id == "LIQUIDATION") then Shop.reprice(run) end
  if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain("voucher", offer.id) end
  event("spend", paid)
  event("voucherBought", 1)
  if offer.id == "BLANK" then event("blankBought", 1) end
  return true
end

function Shop.sellValue(trinket)
  local cost = trinket.paid
  if cost == nil then
    local def = ns.Trinkets.def[trinket.id]
    -- An id dropped from the game still sells, for the floor.
    cost = def and (def.cost + (ns.CardTypes.ED_COST[trinket.ed] or 0)) or 0
  end
  return math.max(1, math.floor(cost / 2)) + (trinket.sellBonus or 0)
end

-- Kept for the shop UI; Run.sellTrinket does the work (and works in a blind too).
function Shop.sellTrinket(run, slot)
  return ns.Run.sellTrinket(run, slot) or 0
end

function Shop.reroll(run)
  local shop = run.shop
  if shop.openPack then return false, "pack" end
  local free = (shop.freeRerolls or 0) > 0
  local cost = free and 0 or math.max(0, shop.rerollCost - ns.Vouchers.rerollDelta(run))
  if not ns.Run.canAfford(run, cost) then return false, "gold" end
  run.gold = run.gold - cost
  if free then shop.freeRerolls = shop.freeRerolls - 1 else shop.rerollCost = shop.rerollCost + 1 end
  shop.cards = generateCards(run)
  Shop.reprice(run)
  event("reroll", 1)
  event("spend", cost)
  ns.TrinketEngine.fire(run, "onShopReroll")
  return true
end

ns.Shop = Shop
