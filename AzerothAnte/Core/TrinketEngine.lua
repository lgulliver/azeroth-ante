local _, ns = ...

-- Resolves Blueprint/Brainstorm copying. Defs are looked up lazily so load order is free.
local TrinketEngine = {}

local function defOf(instance)
  return instance and ns.Trinkets.def[instance.id]
end

-- The instance and def whose hooks a slot runs, or nil when it has none to run.
-- Copiers (def.copies = "right" | "leftmost") follow their target; a visited set stops cycles.
function TrinketEngine.source(trinkets, slot)
  local visited = {}
  local current, viaCopy = slot, false
  while true do
    if visited[current] then return nil end
    visited[current] = true
    local instance = trinkets[current]
    local def = defOf(instance)
    if not def then return nil end
    if viaCopy and def.copyable == false then return nil end
    if not def.copies then return instance, def end
    current = (def.copies == "right") and (current + 1) or 1
    viaCopy = true
  end
end

-- fn(slot, instance, def, isCopy) for every slot whose source resolves, left to right.
function TrinketEngine.each(trinkets, fn)
  for slot = 1, #trinkets do
    local instance, def = TrinketEngine.source(trinkets, slot)
    if instance then fn(slot, instance, def, instance ~= trinkets[slot]) end
  end
end

-- Lifecycle effect handlers, keyed by effect field: fn(run, ctx, value, isCopy, emit) where
-- ctx = { slot, uid }. Later waves add fields here. Destroys run in a second phase (see fire).
local function indexOfUid(run, uid)
  for i, t in ipairs(run.trinkets) do
    if t.uid == uid then return i end
  end
end

local function destroyUid(run, uid, emit)
  local i = indexOfUid(run, uid)
  if not i then return end -- Already gone.
  local id = run.trinkets[i].id
  table.remove(run.trinkets, i)
  emit({ kind = "trinketDestroyed", uid = uid, slot = i, id = id })
end

local HANDLERS = {
  msg = function(_, ctx, text, _, emit) emit({ kind = "trinketMsg", uid = ctx.uid, slot = ctx.slot, text = text }) end,
  gold = function(run, ctx, n, _, emit)
    run.gold = run.gold + n
    emit({ kind = "money", uid = ctx.uid, slot = ctx.slot, amount = n })
  end,
  destroySelf = function(run, ctx, v, isCopy, emit)
    if v and not isCopy then destroyUid(run, ctx.uid, emit) end
  end,
  destroyTrinket = function(run, _, uid, _, emit) destroyUid(run, uid, emit) end,
  createTrinkets = function(run, ctx, spec, _, emit)
    for _ = 1, spec.n or 1 do
      if #run.trinkets >= ns.Run.trinketSlots(run) then break end
      local id = ns.Trinkets.rollOfRarity(run, spec.rarity)
      if not id then break end
      local instance = ns.Trinkets.create(run, id)
      run.trinkets[#run.trinkets + 1] = instance
      if ns.Profile and ns.Profile.onObtain then ns.Profile.onObtain("trinket", id) end
      emit({ kind = "trinketCreated", uid = instance.uid, slot = #run.trinkets, id = id, by = ctx.uid })
    end
  end,
  sellBonusAll = function(run, _, n)
    for _, t in ipairs(run.trinkets) do t.sellBonus = (t.sellBonus or 0) + n end
    for _, c in ipairs(run.consumables or {}) do c.sellBonus = (c.sellBonus or 0) + n end
  end,
  handsDelta = function(run, _, n) run.handsLeft = run.handsLeft + n end,
  discardsSet = function(run, _, n) run.discardsLeft = n end,
  levelHand = function(run, ctx, handId, _, emit)
    run.handLevels[handId] = (run.handLevels[handId] or 1) + 1
    emit({ kind = "levelUp", uid = ctx.uid, slot = ctx.slot, handId = handId })
  end,
  destroyCard = function(run, ctx, cardId, _, emit)
    ns.Deck.destroy(run, cardId)
    emit({ kind = "cardDestroyed", uid = ctx.uid, slot = ctx.slot, cardId = cardId })
  end,
  -- A card made by a hook joins the deck; in a blind it also goes to the hand, or into the pile
  -- at a random spot (so it can be drawn this round).
  createCard = function(run, ctx, spec, _, emit)
    local src = spec.card
    local card = ns.Deck.add(run, {
      rank = src.rank, suit = src.suit, enh = src.enh, ed = src.ed, seal = src.seal, bonusChips = src.bonusChips,
    })
    local toHand = false
    if run.phase == "play" then
      if spec.toHand then
        run.hand[#run.hand + 1] = card
        toHand = true
      else
        table.insert(run.pile, ns.RNG.int(run.rng, 1, #run.pile + 1), card)
      end
    end
    emit({ kind = "cardCreated", uid = ctx.uid, slot = ctx.slot, cardId = card.id, toHand = toHand })
  end,
  createConsumable = function(run, ctx, spec, _, emit)
    if ns.Consumables.slots(run) - #run.consumables < 1 then return end
    local item = spec.id and { kind = spec.kind, id = spec.id } or ns.Consumables.random(run, spec.kind)
    if item and ns.Consumables.add(run, item) then
      emit({ kind = "consumableCreated", uid = ctx.uid, slot = ctx.slot, item = item })
    end
  end,
  disableBoss = function(run, _, v, _, emit)
    if v and ns.Run.disableBoss(run) then emit({ kind = "bossDisabled" }) end
  end,
  save = function(run, ctx, v)
    if v and not run.savedBy then
      run.savedBy = ctx.uid
      local i = indexOfUid(run, ctx.uid)
      run.savedById = i and run.trinkets[i].id
    end
  end,
}

local GROUP = { destroySelf = "destroy", destroyTrinket = "destroy", createTrinkets = "create",
  createCard = "create", createConsumable = "create" }
local ORDER = { "msg", "gold", "sellBonusAll", "handsDelta", "discardsSet", "disableBoss", "levelHand", "destroyCard",
  "createTrinkets", "createCard", "createConsumable", "save", "destroySelf", "destroyTrinket" }

-- Applies one lifecycle effect for the trinket `uid` in `slot`. With `only` ("now", "destroy" or "create")
-- it applies just that group of fields. Returns the events it produced.
function TrinketEngine.apply(run, slot, uid, effect, isCopy, only)
  local events = {}
  local ctx = { slot = slot, uid = uid }
  local function emit(e) events[#events + 1] = e end
  for _, field in ipairs(ORDER) do
    local value = effect[field]
    local group = GROUP[field] or "now"
    if value ~= nil and value ~= false and (not only or only == group) then
      HANDLERS[field](run, ctx, value, isCopy, emit)
    end
  end
  return events
end

-- Applies every phase of one effect now (selling a trinket has no batch to order against) and
-- appends the events to run.lifecycleEvents. Returns the events.
function TrinketEngine.applyAll(run, slot, uid, effect, isCopy)
  local events = {}
  for _, phase in ipairs({ "now", "destroy", "create" }) do
    for _, e in ipairs(TrinketEngine.apply(run, slot, uid, effect, isCopy, phase)) do events[#events + 1] = e end
  end
  run.lifecycleEvents = run.lifecycleEvents or {}
  for _, e in ipairs(events) do run.lifecycleEvents[#run.lifecycleEvents + 1] = e end
  return events
end

-- True while a fire is running and `uid` is already marked for destruction.
function TrinketEngine.isMarked(run, uid)
  return run.pendingDestroy ~= nil and run.pendingDestroy[uid] == true
end

-- Runs an update hook, hook(run, self, ..., isCopy), on every real instance (copies included),
-- collects the effects, then applies them in slot order: plain fields, destructions, creations.
-- A uid marked for destruction (run.pendingDestroy) skips its own hook; hooks may check isMarked.
-- Returns the events and appends them to run.lifecycleEvents for the UI.
local function fireNow(run, hook, ...)
  local n = select("#", ...)
  local args = { ... }
  local pending = {}
  run.pendingDestroy = {}
  local ok, err = pcall(TrinketEngine.each, run.trinkets, function(slot, instance, def, isCopy)
    local fn = def[hook]
    local uid = run.trinkets[slot].uid
    if not fn or run.pendingDestroy[uid] then return end
    args[n + 1] = isCopy
    local effect = fn(run, instance, unpack(args, 1, n + 1))
    if type(effect) ~= "table" then return end
    if effect.destroyTrinket then run.pendingDestroy[effect.destroyTrinket] = true end
    if effect.destroySelf and not isCopy then run.pendingDestroy[uid] = true end
    pending[#pending + 1] = { slot = slot, uid = uid, effect = effect, isCopy = isCopy }
  end)
  run.pendingDestroy = nil -- Always cleared, even when a hook errored.
  if not ok then error(err, 0) end
  local events = {}
  for _, phase in ipairs({ "now", "destroy", "create" }) do
    for _, p in ipairs(pending) do
      for _, e in ipairs(TrinketEngine.apply(run, p.slot, p.uid, p.effect, p.isCopy, phase)) do events[#events + 1] = e end
    end
  end
  run.lifecycleEvents = run.lifecycleEvents or {}
  for _, e in ipairs(events) do run.lifecycleEvents[#run.lifecycleEvents + 1] = e end
  return events
end

local function logSize(run)
  local log = run.cardLog
  return log and (#log.added + #log.destroyed) or 0
end

-- Tells the trinkets about the cards logged since the last flush (Deck.add / Deck.destroy), once each:
-- onCardsAdded(run, self, cards, isCopy), onCardsDestroyed(run, self, cards, isCopy; copies of the cards).
-- The log is cleared first, so cards a handler makes wait for the next flush.
local flushing = false
function TrinketEngine.flushCards(run)
  local log = run.cardLog
  if flushing or not log or logSize(run) == 0 then return end
  local added, destroyed = log.added, log.destroyed
  run.cardLog = { added = {}, destroyed = {} }
  flushing = true
  local ok, err = pcall(function()
    if #added > 0 then TrinketEngine.fire(run, "onCardsAdded", added) end
    if #destroyed > 0 then TrinketEngine.fire(run, "onCardsDestroyed", destroyed) end
  end)
  flushing = false
  if not ok then error(err, 0) end
end

-- Trinkets created or destroyed by a hook change hands, discards and hand size, so settle them.
-- A fire whose effects added or destroyed cards flushes the card log straight away.
function TrinketEngine.fire(run, hook, ...)
  local args = { ... }
  local n = select("#", ...)
  local before = logSize(run)
  local events = ns.Run.withMods(run, function() return fireNow(run, hook, unpack(args, 1, n)) end)
  if logSize(run) > before then TrinketEngine.flushCards(run) end
  return events
end

ns.TrinketEngine = TrinketEngine
