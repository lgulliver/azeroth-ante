local _, ns = ...

local Packs = {}

Packs.SIZES = {
  normal = { cost = 4, show = 3, pick = 1 },
  jumbo = { cost = 6, show = 5, pick = 1 },
  mega = { cost = 8, show = 5, pick = 2 },
}
Packs.WEIGHTS = {
  ARCANA = { normal = 4, jumbo = 2, mega = 0.5 },
  CELESTIAL = { normal = 4, jumbo = 2, mega = 0.5 },
  STANDARD = { normal = 4, jumbo = 2, mega = 0.5 },
  BUFFOON = { normal = 1.2, jumbo = 0.6, mega = 0.15 },
  SPECTRAL = { normal = 0.6, jumbo = 0.3, mega = 0.07 },
}

local TYPES = { "ARCANA", "CELESTIAL", "STANDARD", "BUFFOON", "SPECTRAL" }
local SIZES = { "normal", "jumbo", "mega" }
local KINDS = { ARCANA = "scroll", CELESTIAL = "tome", SPECTRAL = "relic" }
local ENHANCEMENTS, SEALS = {}, {}
for id in pairs(ns.CardTypes.enh) do ENHANCEMENTS[#ENHANCEMENTS + 1] = id end
for id in pairs(ns.CardTypes.seal) do SEALS[#SEALS + 1] = id end
table.sort(ENHANCEMENTS)
table.sort(SEALS)

function Packs.random(run)
  local total = 0
  for _, kind in ipairs(TYPES) do
    for _, size in ipairs(SIZES) do total = total + Packs.WEIGHTS[kind][size] end
  end
  local roll, edge = ns.RNG.next(run.rng) * total, 0
  for _, kind in ipairs(TYPES) do
    for _, size in ipairs(SIZES) do
      edge = edge + Packs.WEIGHTS[kind][size]
      if roll < edge then return { type = kind, size = size, cost = Packs.SIZES[size].cost } end
    end
  end
end

local function standardCard(run)
  local card = { rank = ns.RNG.int(run.rng, 2, 14), suit = ns.RNG.pick(run.rng, ns.Cards.SUITS) }
  if ns.RNG.next(run.rng) < 0.4 then card.enh = ns.RNG.pick(run.rng, ENHANCEMENTS) end
  if ns.RNG.next(run.rng) < 0.2 then card.seal = ns.RNG.pick(run.rng, SEALS) end
  card.ed = ns.CardTypes.rollEdition(run.rng, false)
  return card
end

-- How many choices a pack shows (Spectral and Buffoon packs show one fewer).
function Packs.showCount(packType, size)
  local show = Packs.SIZES[size].show
  if packType == "SPECTRAL" or packType == "BUFFOON" then show = show - 1 end
  return show
end

function Packs.open(run, i)
  local shop = run.shop
  if shop and shop.openPack then return false, "pack" end
  local offer = shop and shop.packs[i]
  if not offer then return false, "gone" end
  if run.gold < offer.cost then return false, "gold" end
  local size = Packs.SIZES[offer.size]
  local show = Packs.showCount(offer.type, offer.size)
  local pack = { type = offer.type, size = offer.size, choices = {}, picksLeft = size.pick }
  local taken = {}
  local kind = KINDS[offer.type]
  local pool = {}
  if kind then
    local ids = kind == "tome" and ns.Hands.visible(run)
      or (kind == "scroll" and ns.Scrolls.order or ns.Relics.order)
    for c, id in ipairs(ids) do pool[c] = id end
  end
  for c = 1, show do
    local item
    if kind then
      if #pool > 0 then
        local index = ns.RNG.int(run.rng, 1, #pool)
        item = { kind = kind, id = table.remove(pool, index) }
      else
        item = ns.Consumables.random(run, kind)
      end
    elseif offer.type == "BUFFOON" then
      item = ns.Shop.rollTrinket(run, taken)
    else
      item = standardCard(run)
    end
    if item then pack.choices[#pack.choices + 1] = item end
  end
  pack.picksLeft = math.min(pack.picksLeft, #pack.choices)
  if offer.type == "ARCANA" or offer.type == "SPECTRAL" then
    pack.hand = {}
    ns.Cards.draw(ns.Deck.shuffledPile(run), pack.hand, ns.Deck.handSize(run))
  end
  run.gold = run.gold - offer.cost
  shop.packs[i] = false
  shop.openPack = pack
  return true
end

local function selectedCards(pack, item, idx)
  local def = ns.Consumables.def(item)
  if not def or not def.select then return {} end
  local sorted, seen, cards = {}, {}, {}
  for i, index in ipairs(idx or {}) do
    if type(index) ~= "number" or index % 1 ~= 0 or not pack.hand
      or index < 1 or index > #pack.hand or seen[index] then
      return nil, "Invalid card selection"
    end
    seen[index] = true
    sorted[i] = index
  end
  table.sort(sorted)
  for _, index in ipairs(sorted) do cards[#cards + 1] = pack.hand[index] end
  return cards
end

function Packs.pick(run, c, idx)
  local pack = run.shop and run.shop.openPack
  local item = pack and pack.choices[c]
  if not item then return false, "gone" end
  local outcome
  if pack.type == "BUFFOON" then
    local slots = ns.Run.trinketSlots(run) + (item.ed == "NEGATIVE" and 1 or 0)
    if #run.trinkets >= slots then return false, "slots" end
    run.trinkets[#run.trinkets + 1] = { id = item.id, ed = item.ed }
    if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain("trinket", item.id) end
  elseif pack.type == "STANDARD" then
    ns.Deck.add(run, item)
  else
    local cards, reason = selectedCards(pack, item, idx)
    if not cards then return false, reason end
    local ok, err = ns.Consumables.canApply(run, item, cards)
    if not ok then return false, err end
    outcome = ns.Consumables.apply(run, item, cards)
  end
  pack.choices[c] = false
  pack.picksLeft = pack.picksLeft - 1
  if pack.picksLeft == 0 then run.shop.openPack = nil end
  return true, nil, outcome
end

function Packs.skip(run)
  if run.shop then run.shop.openPack = nil end
end

ns.Packs = Packs
