local _, ns = ...

local Save = {}

Save.VERSION = 7

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[deepCopy(k)] = deepCopy(v) end
  return out
end

function Save.store(db, run)
  db.run = deepCopy(run)
  -- Kel'Thuzad's forced card is a reference into the hand: stored by id, relinked on load.
  db.run.forcedCard = nil
  db.run.forcedCardId = run.forcedCard and run.forcedCard.id or nil
  db.version = Save.VERSION
end

function Save.load(db)
  if not db or type(db.version) ~= "number" or db.version < 2
    or db.version > Save.VERSION then return nil end
  local run = db.run
  if type(run) ~= "table" or type(run.phase) ~= "string" then return nil end
  if type(run.deck) ~= "table" or type(run.hand) ~= "table"
    or type(run.pile) ~= "table" then return nil end
  run = deepCopy(run)
  if db.version == 2 then
    run.vouchers = run.vouchers or {}
    run.handPlays = run.handPlays or {}
    run.bossRerollsUsed = run.bossRerollsUsed or 0
    run.bossesFought = run.bossesFought or {}
    run.streak = run.streak or { maxInterest = 0 }
    if run.phase == "shop" and run.shopVoucher == nil then run.shopVoucher = ns.Shop.rollVoucher(run) end
  end
  if db.version < 4 then
    run.nextTrinketUid = 1
    run.roundHandPlays = run.roundHandPlays or {}
    for _, trinket in ipairs(run.trinkets or {}) do
      trinket.uid = run.nextTrinketUid
      run.nextTrinketUid = run.nextTrinketUid + 1
      trinket.sellBonus = trinket.sellBonus or 0
      trinket.state = trinket.state or {}
      local def = ns.Trinkets.def[trinket.id]
      if def and def.init then def.init(trinket, run) end
    end
  end
  if db.version < 5 then
    run.discardsUsedRound = run.discardsUsedRound or 0
    run.flags = run.flags or {}
    run.lifecycleEvents = run.lifecycleEvents or {}
    if run.shop then run.shop.freeRerolls = run.shop.freeRerolls or 0 end
  end
  if run.handsPlayedRound == nil then
    local n = 0
    for _, plays in pairs(run.roundHandPlays or {}) do n = n + plays end
    run.handsPlayedRound = n
  end
  if db.version < 6 then
    run.usage = run.usage or { scroll = 0, tome = 0, relic = 0, tomeIds = {} }
    run.cardLog = run.cardLog or { added = {}, destroyed = {} }
    run.bossDisabled = run.bossDisabled or false
    run.startDeckSize = run.startDeckSize or 52
  end
  if db.version < 7 then
    run.tags = run.tags or {}
    -- Older saves have no skip tags: roll this stage's pair, or Skip would give nothing.
    if not (run.blindTags and run.blindTags[1]) then ns.Tags.rollBlindTags(run) end
    run.skips = run.skips or 0
    run.skippedBlinds = run.skippedBlinds or {}
    run.playedThisAnte = run.playedThisAnte or {}
    run.discardsUnusedTotal = run.discardsUnusedTotal or 0
    -- Gluth locks the blind's first hand: a mid-blind save from before it was stored has played one.
    if run.roundFirstHand == nil then run.roundFirstHand = next(run.roundHandPlays or {}) end
  end
  run.pendingDestroy = nil
  run.cardLog = { added = {}, destroyed = {} } -- Like events: a reload never replays pending notifications.
  run.lifecycleEvents = {} -- Events are for the live UI only; never replayed after a reload.
  ns.Deck.relink(run)
  -- Older saves held a detached copy of the forced card; either way it relinks by id.
  local forcedId = run.forcedCardId or (type(run.forcedCard) == "table" and run.forcedCard.id)
  run.forcedCard = forcedId and ns.Deck.find(run, forcedId) or nil
  run.forcedCardId = nil
  return run
end

function Save.clear(db)
  db.run = nil
  db.version = nil
end

ns.Save = Save
