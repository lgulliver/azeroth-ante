local _, ns = ...

local Shop = {}

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
  for _, id in ipairs(ns.Trinkets.order) do
    if not taken[id] and not owns(run, id) then
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
  local ed = ns.CardTypes.rollEdition(run.rng, true)
  return { type = "trinket", id = id, ed = ed,
    cost = ns.Trinkets.def[id].cost + (ns.CardTypes.ED_COST[ed] or 0) }
end

local function generateCards(run)
  local cards, taken = {}, {}
  for i = 1, 2 do
    local roll = ns.RNG.next(run.rng) * 28
    if roll < 20 then
      cards[i] = Shop.rollTrinket(run, taken)
    else
      local kind = roll < 24 and "scroll" or "tome"
      local item = ns.Consumables.random(run, kind)
      cards[i] = { type = kind, id = item.id, cost = ns.Consumables.COST[kind] }
    end
  end
  return cards
end

function Shop.open(run)
  run.shop = {
    cards = generateCards(run),
    packs = { ns.Packs.random(run), ns.Packs.random(run) },
    rerollCost = 5,
  }
end

function Shop.buy(run, i)
  local shop = run.shop
  if shop and shop.openPack then return false, "pack" end
  local item = shop and shop.cards[i]
  if not item then return false, "gone" end
  if run.gold < item.cost then return false, "gold" end
  if item.type == "trinket" then
    local slots = ns.Run.trinketSlots(run) + (item.ed == "NEGATIVE" and 1 or 0)
    if #run.trinkets >= slots then return false, "slots" end
    run.trinkets[#run.trinkets + 1] = { id = item.id, ed = item.ed }
  else
    if not ns.Consumables.add(run, { kind = item.type, id = item.id }) then
      return false, "slots"
    end
  end
  run.gold = run.gold - item.cost
  shop.cards[i] = false
  return true
end

function Shop.sellTrinket(run, slot)
  local trinket = run.trinkets[slot]
  if not trinket then return 0 end
  local cost = ns.Trinkets.def[trinket.id].cost + (ns.CardTypes.ED_COST[trinket.ed] or 0)
  local gained = math.floor(cost / 2)
  run.gold = run.gold + gained
  table.remove(run.trinkets, slot)
  return gained
end

function Shop.reroll(run)
  local shop = run.shop
  if shop.openPack then return false, "pack" end
  if run.gold < shop.rerollCost then return false, "gold" end
  run.gold = run.gold - shop.rerollCost
  shop.rerollCost = shop.rerollCost + 1
  shop.cards = generateCards(run)
  return true
end

ns.Shop = Shop
