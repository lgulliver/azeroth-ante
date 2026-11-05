local _, ns = ...

local Shop = {}

local OFFER_COUNT = 2
local TOME_COST = 3
local REROLL_COST = 5

local function owns(run, id)
  for _, trinket in ipairs(run.trinkets) do
    if trinket.id == id then return true end
  end
  return false
end

-- Draws one trinket by rarity weight (70/25/5), not owned and not in `taken`.
-- Falls back to any eligible trinket when the rolled rarity has none.
local function draw(run, taken)
  local byRarity = { common = {}, uncommon = {}, rare = {} }
  local any = {}
  for _, id in ipairs(ns.Trinkets.order) do
    if not taken[id] and not owns(run, id) then
      any[#any + 1] = id
      local list = byRarity[ns.Trinkets.def[id].rarity]
      list[#list + 1] = id
    end
  end
  if #any == 0 then return nil end
  local roll = ns.RNG.next(run.rng) * 100
  local rarity = roll < 70 and "common" or (roll < 95 and "uncommon" or "rare")
  local pool = byRarity[rarity]
  if #pool == 0 then pool = any end
  return ns.RNG.pick(run.rng, pool)
end

local function makeOffer(id)
  return { id = id, cost = ns.Trinkets.def[id].cost }
end

-- Up to OFFER_COUNT distinct, unowned offers.
local function generateOffers(run)
  local taken, offers = {}, {}
  while #offers < OFFER_COUNT do
    local id = draw(run, taken)
    if not id then break end
    taken[id] = true
    offers[#offers + 1] = makeOffer(id)
  end
  return offers
end

function Shop.open(run)
  run.shop = {
    offers = generateOffers(run),
    tome = { handId = ns.RNG.pick(run.rng, ns.Hands.order), cost = TOME_COST },
    rerollCost = REROLL_COST,
  }
end

function Shop.buyTrinket(run, i)
  local offer = run.shop.offers[i]
  if not offer then return false, "gone" end
  if run.gold < offer.cost then return false, "gold" end
  if #run.trinkets >= run.maxTrinkets then return false, "slots" end
  run.gold = run.gold - offer.cost
  run.trinkets[#run.trinkets + 1] = { id = offer.id }
  run.shop.offers[i] = false
  return true
end

function Shop.buyTome(run)
  local tome = run.shop.tome
  if not tome then return false, "gone" end
  if run.gold < tome.cost then return false, "gold" end
  run.gold = run.gold - tome.cost
  run.handLevels[tome.handId] = run.handLevels[tome.handId] + 1
  run.shop.tome = false
  return true
end

function Shop.sell(run, slot)
  local trinket = run.trinkets[slot]
  if not trinket then return 0 end
  local gained = math.floor(ns.Trinkets.def[trinket.id].cost / 2)
  run.gold = run.gold + gained
  table.remove(run.trinkets, slot)
  return gained
end

-- Regenerates the whole trinket offer list, refilling bought slots. Only owned
-- trinkets are excluded, so current offers may reappear.
function Shop.reroll(run)
  local shop = run.shop
  if run.gold < shop.rerollCost then return false, "gold" end
  run.gold = run.gold - shop.rerollCost
  shop.rerollCost = shop.rerollCost + 1
  shop.offers = generateOffers(run)
  return true
end

function Shop.tomeName(handId)
  return "Tome of " .. ns.Hands.def[handId].name
end

ns.Shop = Shop
