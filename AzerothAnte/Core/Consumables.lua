local _, ns = ...

-- Consumable instance: { kind = "tome"|"scroll"|"relic", id }. Slots hold instances.
local Consumables = {}

Consumables.COST = { tome = 3, scroll = 3, relic = 4 }
Consumables.REASON_NO_HAND = "Select cards in a hand"

local USABLE_PHASES = { play = true, shop = true, blind = true }

function Consumables.def(item)
  if item.kind == "tome" then return ns.Tomes.def[item.id] end
  if item.kind == "scroll" then return ns.Scrolls.def[item.id] end
  if item.kind == "relic" and ns.Relics then return ns.Relics.def[item.id] end
end

function Consumables.slots(run)
  return run.maxConsumables + ns.Vouchers.extraConsumables(run)
end

function Consumables.add(run, item)
  if #run.consumables >= Consumables.slots(run) then return false end
  run.consumables[#run.consumables + 1] = item
  if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain(item.kind, item.id) end
  return true
end

-- Hidden secret-hand Tomes are never rolled. Returns nil if the kind has no pool.
function Consumables.random(run, kind)
  local pool
  if kind == "tome" then
    pool = ns.Hands.visible(run)
  elseif kind == "scroll" then
    pool = ns.Scrolls.order
  elseif kind == "relic" and ns.Relics then
    pool = ns.Relics.order
  end
  if not pool or #pool == 0 then return nil end
  return { kind = kind, id = ns.RNG.pick(run.rng, pool) }
end

function Consumables.targetCards(run)
  if run.phase == "play" then return run.hand end
  local pack = run.shop and run.shop.openPack
  if pack and pack.hand then return pack.hand end
end

local function inSlot(run, item)
  for _, held in ipairs(run.consumables) do
    if held == item then return true end
  end
  return false
end

local function selectReason(select)
  if select.min == select.max then
    return "Select " .. select.min .. (select.min == 1 and " card" or " cards")
  end
  return "Select " .. select.min .. " to " .. select.max .. " cards"
end

function Consumables.canApply(run, item, cards)
  local def = Consumables.def(item)
  if not def then return false, "Unknown consumable" end
  if def.select then
    cards = cards or {}
    if #cards < def.select.min or #cards > def.select.max then
      return false, selectReason(def.select)
    end
    if def.checkCards then
      local ok, reason = def.checkCards(run, cards)
      if not ok then return false, reason end
    end
  elseif not USABLE_PHASES[run.phase] then
    return false, "Cannot use that now"
  end
  if def.check then
    local ok, reason = def.check(run)
    if not ok then return false, reason end
  end
  if def.creates then
    local free = Consumables.slots(run) - #run.consumables + (inSlot(run, item) and 1 or 0)
    if free < 1 then return false, "No room" end
  end
  return true
end

-- Description and "affects" lines for an item. A def may supply descFor(run) /
-- affectsFor(run) when the text depends on the run (Void's penalty); Tomes
-- always show the level they will reach.
function Consumables.describe(run, item)
  local def = Consumables.def(item)
  if not def then return "" end
  if item.kind == "tome" then
    local name = ns.Hands.def[def.handId].name
    local level = (run and run.handLevels[def.handId]) or 1
    return "Levels up " .. name .. " to level " .. (level + 1) .. "."
  end
  if def.descFor then return def.descFor(run) end
  return def.desc or ""
end

function Consumables.affects(run, item)
  local def = Consumables.def(item)
  if not def then return "" end
  if item.kind == "tome" then
    local hand = ns.Hands.def[def.handId]
    local level = (run and run.handLevels[def.handId]) or 1
    return hand.name .. ": Lv " .. level .. " -> " .. (level + 1)
  end
  if def.affectsFor then return def.affectsFor(run) end
  return def.affects or ""
end

local function removeFrom(list, card)
  for i = #list, 1, -1 do
    if list[i] == card then table.remove(list, i) end
  end
end

local function buildApi(run, outcome, touched)
  local api = { rng = run.rng }
  local function note(list, id)
    for _, existing in ipairs(list) do
      if existing == id then return end
    end
    list[#list + 1] = id
  end
  function api.add(item)
    if not Consumables.add(run, item) then return false end
    outcome.created[#outcome.created + 1] = item
    return true
  end
  function api.randomId(kind)
    local item = Consumables.random(run, kind)
    return item and item.id
  end
  function api.addCard(card)
    ns.Deck.add(run, card)
    if run.phase == "play" then
      run.hand[#run.hand + 1] = card
    elseif run.shop and run.shop.openPack and run.shop.openPack.hand then
      local hand = run.shop.openPack.hand
      hand[#hand + 1] = card
    end
    outcome.added[#outcome.added + 1] = card.id
    return card
  end
  function api.destroy(card)
    ns.Deck.destroy(run, card.id)
    local pack = run.shop and run.shop.openPack
    if pack and pack.hand then removeFrom(pack.hand, card) end
    note(outcome.destroyed, card.id)
  end
  function api.changed(card) note(outcome.changed, card.id) end
  function api.gold(delta)
    run.gold = run.gold + delta
    outcome.gold = outcome.gold + delta
  end
  function api.trinkets() return run.trinkets end
  -- Marks a trinket (table) as changed or added; apply turns these into slot indices.
  function api.touch(trinket) note(touched, trinket) end
  function api.level(handId)
    run.handLevels[handId] = run.handLevels[handId] + 1
    outcome.levelled[handId] = run.handLevels[handId]
  end
  -- delta is negative for a smaller hand; the outcome sums it.
  function api.handSize(delta)
    run.handSizeMod = run.handSizeMod + delta
    outcome.handSize = (outcome.handSize or 0) + delta
  end
  function api.nope() outcome.nope = true end
  return api
end

-- Applies an item's effect with no slot involved. Callers check canApply first.
function Consumables.apply(run, item, cards)
  local def = Consumables.def(item)
  local outcome = {
    changed = {}, destroyed = {}, created = {}, added = {}, gold = 0,
    levelled = {}, trinkets = {},
  }
  local touched, owned = {}, {}
  for _, trinket in ipairs(run.trinkets) do owned[trinket] = true end
  local api = buildApi(run, outcome, touched)
  if item.kind == "tome" then
    api.level(def.handId)
  else
    def.use(run, cards or {}, api)
  end
  if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain(item.kind, item.id) end
  for i, trinket in ipairs(run.trinkets) do
    if not owned[trinket] and ns.Profile and ns.Profile.onObtain then
      ns.Profile.onObtain("trinket", trinket.id)
    end
    for _, mark in ipairs(touched) do
      if mark == trinket then outcome.trinkets[#outcome.trinkets + 1] = i end
    end
  end
  if item.kind ~= "relic" and not (item.kind == "scroll" and item.id == "ECHOES") then
    run.lastConsumable = { kind = item.kind, id = item.id }
  end
  ns.Run.checkHand(run) -- a thinned hand refills, or the blind is lost when nothing is left
  return outcome
end

-- Resolves selected hand indices into cards, left to right. Returns nil, reason on bad input.
local function selectedCards(run, def, idx)
  if not def.select then return {} end
  local source = Consumables.targetCards(run)
  if not source then return nil, Consumables.REASON_NO_HAND end
  local sorted, seen, cards = {}, {}, {}
  for i, index in ipairs(idx or {}) do sorted[i] = index end
  table.sort(sorted)
  for _, index in ipairs(sorted) do
    if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #source or seen[index] then
      return nil, "Invalid card selection"
    end
    seen[index] = true
    cards[#cards + 1] = source[index]
  end
  return cards
end

function Consumables.canUse(run, slot, idx)
  local item = run.consumables[slot]
  if not item then return false, "Nothing there" end
  local cards, reason = selectedCards(run, Consumables.def(item) or {}, idx)
  if not cards then return false, reason end
  return Consumables.canApply(run, item, cards)
end

function Consumables.use(run, slot, idx)
  local ok, reason = Consumables.canUse(run, slot, idx)
  if not ok then return nil, reason end
  local item = run.consumables[slot]
  local cards = selectedCards(run, Consumables.def(item), idx)
  table.remove(run.consumables, slot)
  return Consumables.apply(run, item, cards)
end

function Consumables.sellValue(item)
  return math.floor((item.paid or Consumables.COST[item.kind]) / 2) + (item.sellBonus or 0)
end

function Consumables.sell(run, slot)
  local item = run.consumables[slot]
  if not item then return 0 end
  local gained = Consumables.sellValue(item)
  run.gold = run.gold + gained
  table.remove(run.consumables, slot)
  return gained
end

ns.Consumables = Consumables
