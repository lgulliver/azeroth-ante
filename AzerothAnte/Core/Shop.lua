local _, ns = ...

local Shop = {}

local function event(name, amount)
  if ns.Profile and ns.Profile.onEvent then ns.Profile.onEvent(name, amount) end
end

-- A voucher offer (false when none is left); `exclude` is an id already offered (Vendor Restock).
function Shop.rollVoucher(run, exclude)
  local pool = {}
  for _, id in ipairs(ns.Vouchers.order) do
    local def = ns.Vouchers.def[id]
    if id ~= exclude and not ns.Vouchers.owns(run, id) and (def.tier == 1
      or (ns.Vouchers.owns(run, def.base) and ns.Profile and ns.Profile.hasAchievement
        and ns.Profile.hasAchievement(def.achievement))) then
      pool[#pool + 1] = id
    end
  end
  if #pool == 0 then return false end
  local id = ns.RNG.pick(run.rng, pool)
  return { id = id, cost = ns.Vouchers.price(run, ns.Vouchers.def[id].cost) }
end

-- An edition at the run's rate (Hone, Glow Up); `mod` 2 for Standard pack cards.
function Shop.rollEdition(run, allowNegative, mod)
  return ns.CardTypes.pollEdition(run.rng, mod or 1, ns.Vouchers.editionMult(run), allowNegative)
end

local function owns(run, id)
  for _, trinket in ipairs(run.trinkets) do
    if trinket.id == id then return true end
  end
  return false
end

-- Shared with Buffoon packs: distinct, unowned trinkets at 70/25/5 rarity, or only of `rarity`
-- (Recruit-a-Friend's commons; false when none is left).
function Shop.rollTrinket(run, taken, rarity)
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
  local pool
  if rarity then
    pool = byRarity[rarity]
    if #pool == 0 then return false end
  else
    if #any == 0 then return false end
    local roll = ns.RNG.next(run.rng) * 100
    pool = byRarity[roll < 70 and "common" or (roll < 95 and "uncommon" or "rare")]
    if #pool == 0 then pool = any end
  end
  local id = ns.RNG.pick(run.rng, pool)
  taken[id] = true
  local ed = Shop.rollEdition(run, true)
  local offer = { type = "trinket", id = id, ed = ed,
    cost = ns.Trinkets.def[id].cost + (ns.CardTypes.ED_COST[ed] or 0) }
  ns.Stakes.rollStickers(run, offer) -- Black Stake and up (Recruit-a-Friend ignores them)
  return offer
end

-- Voucher-discounted price of an offer; Astronomer makes Tomes and Celestial packs free.
function Shop.priceOf(run, item)
  local free = ns.TrinketRules.has(run.trinkets, "ASTRONOMER")
    and (item.type == "tome" or item.type == "CELESTIAL")
  if free then return 0 end
  if item.rental then return ns.Stakes.RENTAL_COST end -- Gold Stake: a Rental costs 1g, as Balatro
  return ns.Vouchers.price(run, item.baseCost or item.cost)
end

-- Re-prices every open offer; called after anything that can change prices mid-shop. A tag-freed
-- offer (tagFree) stays free, and so sells for 1g, as Balatro's set_cost prices the sale after the coupon.
function Shop.reprice(run)
  local shop = run.shop
  if not shop then return end
  -- Chaos bought or sold mid-shop adds or removes a free reroll.
  local chaos = ns.TrinketRules.count(run.trinkets, "CHAOS")
  shop.freeRerolls = math.max(0, (shop.freeRerolls or 0) + chaos - (shop.chaosSeen or chaos))
  shop.chaosSeen = chaos
  for _, stock in ipairs({ shop.cards, shop.packs }) do
    for _, item in ipairs(stock) do
      if item then
        item.baseCost = item.baseCost or item.cost
        item.cost = item.tagFree and 0 or Shop.priceOf(run, item)
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
  -- As in Balatro, a consumable you hold (unless Showman) or that another slot shows isn't offered.
  local blocked = {}
  for _, item in ipairs(cards) do
    if item and (item.type == "scroll" or item.type == "tome") then blocked[item.id] = true end
  end
  if not ns.TrinketRules.has(run.trinkets, "SHOWMAN") then
    for _, item in ipairs(run.consumables) do blocked[item.id] = true end
  end
  local scroll, tome = ns.Vouchers.scrollWeight(run), ns.Vouchers.tomeWeight(run)
  local playing = ns.Vouchers.playingCardsInShop(run) and 4 or 0
  -- Death Knight deck: Relics too, after playing cards (Balatro's Ghost deck, spectral weight 2).
  local relic = ns.Decks.def[run.deckId].relicWeight or 0
  for i = #cards + 1, ns.Vouchers.shopCardSlots(run) do
    local roll = ns.RNG.next(run.rng) * (20 + scroll + tome + playing + relic)
    if roll < 20 then
      cards[i] = Shop.rollTrinket(run, taken)
      if not cards[i] then roll = 20 + ns.RNG.next(run.rng) * (scroll + tome + playing + relic) end
    end
    if not cards[i] and roll >= 20 + scroll + tome + playing then
      local item = ns.Consumables.random(run, "relic", blocked)
      blocked[item.id] = true
      cards[i] = { type = "relic", id = item.id, cost = ns.Consumables.COST.relic }
    end
    if not cards[i] then
      if roll >= 20 + scroll + tome then
        local card = ns.Packs.rollShopCard(run, ns.Vouchers.illusion(run))
        card.type = "card"
        card.cost = 1 + (ns.CardTypes.ED_COST[card.ed] or 0) -- enhancements are free, as in Balatro
        cards[i] = card
      else
        local kind = roll < 20 + scroll and "scroll" or "tome"
        local item = ns.Consumables.random(run, kind, blocked)
        blocked[item.id] = true
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
    packs = { run.firstShopDone and ns.Packs.random(run) or ns.Packs.make(run, "BUFFOON", "normal"),
      ns.Packs.random(run) },
    rerollCost = 5, freeRerolls = ns.TrinketRules.count(run.trinkets, "CHAOS"),
  }
  run.shop.chaosSeen = run.shop.freeRerolls
  run.firstShopDone = true -- Balatro's first shop of a run always has a Buffoon pack
  Shop.reprice(run)
  ns.Tags.fire(run, "onShopOpen") -- after pricing, so a tag's change is final
end

local function buyItem(run, i)
  local shop = run.shop
  if ns.Packs.current(run) then return false, "pack" end
  local item = shop and shop.cards[i]
  if not item then return false, "gone" end
  if not ns.Run.canAfford(run, item.cost) then return false, "gold" end
  if item.type == "trinket" then
    local slots = ns.Run.trinketSlots(run) + (item.ed == "NEGATIVE" and 1 or 0)
    if #run.trinkets >= slots then return false, "slots" end
    run.trinkets[#run.trinkets + 1] = ns.Stakes.stick(ns.Trinkets.create(run, item.id, item.ed, item.cost), item)
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
  return ns.Run.withMods(run, function()
    local ok, reason = buyItem(run, i)
    ns.TrinketEngine.flushCards(run)
    return ok, reason
  end)
end

-- Buys the shop's voucher, or with which = "extra" the second offer a Vendor Restock tag added.
function Shop.buyVoucher(run, which)
  if ns.Packs.current(run) then return false, "pack" end
  local extra = which == "extra"
  local offer
  if extra then offer = run.shop and run.shop.extraVoucher else offer = run.shopVoucher end
  if not offer or ns.Vouchers.owns(run, offer.id) then return false, "gone" end
  local paid = ns.Vouchers.price(run, ns.Vouchers.def[offer.id].cost)
  if not ns.Run.canAfford(run, paid) then return false, "gold" end
  offer.paid = paid
  run.gold = run.gold - paid
  run.vouchers[offer.id] = true
  ns.Vouchers.onBuy(run, offer.id)
  if extra then run.shop.extraVoucher = false else run.shopVoucher = false end
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

-- The next paid reroll's price: Reroll Surplus/Glut take their discount off it, except in a shop
-- whose rerolls Heirloom Dice started at 0g (shop.d6; Balatro's D6 replaces the discounted base).
function Shop.rerollPrice(run)
  local shop = run.shop
  return math.max(0, shop.rerollCost - (shop.d6 and 0 or ns.Vouchers.rerollDelta(run)))
end

function Shop.reroll(run)
  local shop = run.shop
  if ns.Packs.current(run) then return false, "pack" end
  local free = (shop.freeRerolls or 0) > 0
  local cost = free and 0 or Shop.rerollPrice(run)
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
