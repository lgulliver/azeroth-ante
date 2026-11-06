local _, ns = ...

local Run = {}

Run.BASE_TARGETS = { 300, 700, 1400, 2800, 5000, 8000, 11500, 16000 }

-- Gold paid for beating the small, big and boss blind.
Run.BLIND_REWARDS = { 3, 4, 5 }

Run.BOSS_REROLL_COST = 10

function Run.target(stage, blind, bossId)
  local mult = 1
  if blind == 2 then mult = 1.5 end
  if blind == 3 then mult = ns.Bosses.def[bossId].targetMult end
  return math.floor(Run.BASE_TARGETS[stage] * mult)
end

function Run.new(seed, deckId)
  local deck = ns.Decks.def[deckId]
  local run = {
    seed = seed, rng = ns.RNG.new(seed), deckId = deckId,
    stage = 1, blind = 1, phase = "blind", gold = deck.gold,
    deck = ns.Deck.new(), nextCardId = 53, baseHandSize = 8, handSizeMod = 0,
    maxTrinkets = 5, trinkets = {}, nextTrinketUid = 1, roundHandPlays = {}, handLevels = {}, voidPenalty = 1,
    consumables = {}, maxConsumables = 2, seenHands = {},
    lastHandId = nil, lastConsumable = nil,
    vouchers = {}, shopVoucher = nil, handPlays = {}, bossRerollsUsed = 0,
    bossesFought = {}, streak = { maxInterest = 0 },
    handsPlayedTotal = 0, handsPlayedRound = 0, bosses = {}, score = 0,
    target = Run.target(1, 1), handsLeft = deck.hands, discardsLeft = deck.discards,
    discardsUsedRound = 0, flags = {}, lifecycleEvents = {},
    usage = { scroll = 0, tome = 0, relic = 0, tomeIds = {} }, cardLog = { added = {}, destroyed = {} },
    bossDisabled = false,
    pile = {}, hand = {}, sortMode = "rank", lastResult = nil, lastPayout = nil,
  }
  for _, id in ipairs(ns.Hands.order) do run.handLevels[id] = 1 end
  local pool = {}
  for i, id in ipairs(ns.Bosses.pool) do pool[i] = id end
  ns.RNG.shuffle(run.rng, pool)
  for i = 1, 7 do run.bosses[i] = pool[i] end
  run.bosses[8] = ns.Bosses.FINAL
  run.startDeckSize = #run.deck
  return run
end

local function event(name, amount, run)
  if ns.Profile and ns.Profile.onEvent then ns.Profile.onEvent(name, amount, run) end
end

local function editionTrinkets(run)
  local count = 0
  for _, trinket in ipairs(run.trinkets) do
    if trinket.ed then count = count + 1 end
  end
  event("editionTrinkets", count, run)
end

function Run.trinketSlots(run)
  local deck = ns.Decks.def[run.deckId]
  local slots = run.maxTrinkets + (deck.extraTrinketSlots or 0) + ns.Vouchers.extraTrinkets(run)
  for _, trinket in ipairs(run.trinkets) do
    if trinket.ed == "NEGATIVE" then slots = slots + 1 end
  end
  return slots
end

function Run.bossId(run)
  if run.blind == 3 then return run.bosses[run.stage] end
end

-- The boss whose rules apply now: nil off a boss blind, and once a trinket has disabled it.
-- Identity and target keep using bossId.
function Run.activeBoss(run)
  local bossId = Run.bossId(run)
  if bossId and not run.bossDisabled then return ns.Bosses.def[bossId] end
end

-- Hands and discards the current blind starts with: the deck's (or the boss's)
-- base plus voucher changes. Shared by startBlind and the blind-screen sidebar.
local function handsFor(run, boss)
  return math.max(1, (boss and boss.hands or ns.Decks.def[run.deckId].hands) + ns.Vouchers.extraHands(run)
    + ns.Trinkets.mods(run).hands)
end

local function discardsFor(run, boss)
  return math.max(0, (boss and boss.discards or ns.Decks.def[run.deckId].discards) + ns.Vouchers.extraDiscards(run)
    + ns.Trinkets.mods(run).discards)
end

function Run.blindHands(run) return handsFor(run, Run.activeBoss(run)) end

function Run.blindDiscards(run) return discardsFor(run, Run.activeBoss(run)) end

-- Switches the boss's rules off for the rest of the blind. A boss that overrode hands or discards
-- hands back the difference to the normal count; the target stays. Returns false if there was nothing to disable.
function Run.disableBoss(run)
  local boss = Run.activeBoss(run)
  if not boss or run.phase ~= "play" then return false end
  local hands, discards = handsFor(run, boss), discardsFor(run, boss)
  run.bossDisabled = true
  if run.phase == "play" then
    if boss.hands then run.handsLeft = run.handsLeft + math.max(0, handsFor(run) - hands) end
    if boss.discards then run.discardsLeft = run.discardsLeft + math.max(0, discardsFor(run) - discards) end
  end
  return true
end

-- Hands, discards and hand size derived from trinkets; applyMods settles a change in the live round.
function Run.goldFloor(run)
  return ns.TrinketRules.has(run.trinkets, "CREDIT_CARD") and -20 or 0
end

function Run.canAfford(run, cost)
  return cost <= 0 or run.gold - cost >= Run.goldFloor(run)
end

function Run.startBlind(run)
  local bossId = Run.bossId(run)
  run.phase = "play"
  run.bossDisabled = false
  run.pile = ns.Deck.shuffledPile(run)
  run.hand = {}
  run.handsLeft = Run.blindHands(run)
  run.discardsLeft = Run.blindDiscards(run)
  run.score = 0
  run.roundHandPlays = {}
  run.handsPlayedRound = 0
  run.discardsUsedRound = 0
  run.savedBy, run.savedById = nil, nil
  run.target = Run.target(run.stage, run.blind, bossId)
  if bossId then
    run.bossesFought[bossId] = true
    event("bossFought", bossId, run)
  end
  -- Blind-select hooks fire before the draw (Balatro's set_blind): a trinket they destroy never adds cards.
  ns.TrinketEngine.fire(run, "onBlindSelect")
  ns.Cards.draw(run.pile, run.hand, ns.Deck.handSize(run) - #run.hand)
  ns.Cards.sort(run.hand, run.sortMode or "rank")
  event("handSize", ns.Deck.handSize(run), run)
  editionTrinkets(run)
  ns.TrinketEngine.fire(run, "onFirstDraw")
  Run.checkHand(run)
  ns.TrinketEngine.flushCards(run)
end

-- Ends the run as lost, once, unless an onLose trinket (Mr. Bones) saves the blind.
local function lose(run)
  if run.phase == "lost" then return end
  ns.TrinketEngine.fire(run, "onLose")
  if run.savedBy then return Run.winBlind(run, { saved = true }) end
  run.phase = "lost"
  event("runEnded", 0, run)
end

local function validSelection(run, idx)
  if run.phase ~= "play" then return false, "Not playing a blind." end
  if type(idx) ~= "table" or #idx < 1 or #idx > 5 then
    return false, "Select 1 to 5 cards."
  end
  local seen = {}
  for _, i in ipairs(idx) do
    if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > #run.hand then
      return false, "Invalid card index."
    end
    if seen[i] then return false, "Select each card only once." end
    seen[i] = true
  end
  return true
end

function Run.moveTrinket(run, from, to)
  local n = #run.trinkets
  if from < 1 or from > n or to < 1 or to > n then return false end
  table.insert(run.trinkets, to, table.remove(run.trinkets, from))
  return true
end

function Run.canPlay(run, idx)
  local ok, reason = validSelection(run, idx)
  if not ok then return false, reason end
  local boss = Run.activeBoss(run)
  if boss and boss.mustPlay and #idx ~= boss.mustPlay then
    return false, "Must play exactly " .. boss.mustPlay .. " cards."
  end
  return true
end

function Run.canDiscard(run, idx)
  local ok, reason = validSelection(run, idx)
  if not ok then return false, reason end
  if run.discardsLeft <= 0 then return false, "No discards left." end
  return true
end

-- By identity, so cards created into the hand can never shift what was selected.
local function removePlayed(run, played)
  local gone = {}
  for _, card in ipairs(played) do gone[card] = true end
  for i = #run.hand, 1, -1 do
    if gone[run.hand[i]] then table.remove(run.hand, i) end
  end
end

-- Applies scoring's side effects in order; consumables only while a slot is free.
local function applySideEffects(run, effects)
  for _, fx in ipairs(effects) do
    if fx.kind == "createCard" then
      local card = ns.Deck.add(run, fx.card)
      if fx.toHand then run.hand[#run.hand + 1] = card end
    elseif fx.kind == "createConsumable" then
      if #run.consumables < ns.Consumables.slots(run) then
        local item = fx.id and { kind = fx.consumableKind, id = fx.id }
          or ns.Consumables.random(run, fx.consumableKind)
        if item then ns.Consumables.add(run, item) end
      end
    elseif fx.kind == "destroyCard" then
      ns.Deck.destroy(run, fx.id)
    end
  end
end

local function refill(run)
  ns.Cards.draw(run.pile, run.hand, ns.Deck.handSize(run) - #run.hand)
  ns.Cards.sort(run.hand, run.sortMode or "rank")
end

-- Call after any trinket acquire, sell or destroy with `before = Trinkets.mods(run)` taken first.
-- In a live blind the change moves hands and discards left; a bigger hand draws up to the new size,
-- a smaller one never discards. A blind already won is being tallied, so it is left alone.
function Run.applyMods(run, before)
  local after = ns.Trinkets.mods(run)
  if run.phase == "play" and run.score < run.target then
    if after.hands ~= before.hands then
      run.handsLeft = math.max(1, run.handsLeft + after.hands - before.hands)
    end
    if after.discards ~= before.discards then
      run.discardsLeft = math.max(0, run.discardsLeft + after.discards - before.discards)
    end
    if after.handSize > before.handSize then refill(run) end
  end
  -- Astronomer arriving or leaving changes what the open offers cost.
  if run.phase == "shop" and run.shop then ns.Shop.reprice(run) end
end

-- Runs fn and settles trinket changes it made. Nested calls settle once, at the outermost.
local modsDepth = 0
function Run.withMods(run, fn)
  if modsDepth > 0 then return fn() end
  local before = ns.Trinkets.mods(run)
  modsDepth = 1
  local out = { pcall(fn) }
  modsDepth = 0
  if not out[1] then error(out[2], 0) end
  Run.applyMods(run, before)
  return unpack(out, 2, table.maxn(out))
end

-- Sells the trinket in `slot` in a shop or a blind. Returns the gold gained, or nil and a reason.
function Run.sellTrinket(run, slot)
  if run.phase ~= "shop" and run.phase ~= "play" then return nil, "phase" end
  if not run.trinkets[slot] then return nil, "gone" end
  return Run.withMods(run, function()
    local trinket = run.trinkets[slot]
    local def = ns.Trinkets.def[trinket.id]
    -- Before removal, original only (a copier never runs its target's farewell).
    local effect = def and def.onSelfSold and def.onSelfSold(run, trinket)
    if type(effect) == "table" then ns.TrinketEngine.applyAll(run, slot, trinket.uid, effect, false) end
    for i, t in ipairs(run.trinkets) do
      if t == trinket then table.remove(run.trinkets, i) break end
    end
    local gained = ns.Shop.sellValue(trinket)
    run.gold = run.gold + gained
    ns.TrinketEngine.fire(run, "onSell", { kind = "trinket", item = trinket })
    ns.TrinketEngine.flushCards(run)
    return gained
  end)
end

-- Never leaves the player with nothing to do. An empty hand refills from the
-- pile; if there is still nothing to play the blind is lost (unless already won).
function Run.checkHand(run)
  if run.phase ~= "play" then return end
  if #run.hand == 0 then refill(run) end
  if #run.hand == 0 and run.score < run.target then lose(run) end
end

-- The scoring ctx for playing `cards` (with `held` kept) now; overrides replace fields (the bot
-- passes its own goldRef and rng copy). Shared by Run.play, the sim bot and the test helper.
function Run.scoreCtx(run, cards, held, overrides)
  local boss = Run.activeBoss(run)
  local ctx = {
    cards = cards, held = held or {}, goldRef = { gold = run.gold }, handLevels = run.handLevels,
    trinkets = run.trinkets, bossId = boss and boss.id, rng = run.rng,
    handsPlayedTotal = run.handsPlayedTotal + 1, isLastHand = run.handsLeft == 1,
    discardsLeft = run.discardsLeft, gold = run.gold,
    consumables = ns.Vouchers.observatory(run) and run.consumables or nil,
    handsLeft = run.handsLeft, handPlays = run.handPlays, roundHandPlays = run.roundHandPlays,
    pileCount = #run.pile, trinketSlots = Run.trinketSlots(run),
    deckCards = run.deck, startDeckSize = run.startDeckSize or 52,
    firstHandOfRound = (run.handsPlayedRound or 0) == 0,
    consumableRoom = ns.Consumables.slots(run) - #run.consumables, usage = run.usage,
  }
  for k, v in pairs(overrides or {}) do ctx[k] = v end
  return ctx
end

function Run.play(run, idx)
  local ok, reason = Run.canPlay(run, idx)
  if not ok then return nil, reason end
  local cards, held, selected = {}, {}, {}
  for i, index in ipairs(idx) do
    cards[i] = run.hand[index]
    selected[index] = true
  end
  for i, card in ipairs(run.hand) do
    if not selected[i] then held[#held + 1] = card end
  end
  local goldRef = { gold = run.gold }
  local ctx = Run.scoreCtx(run, cards, held, { goldRef = goldRef })
  run.handsPlayedTotal = run.handsPlayedTotal + 1
  run.handsPlayedRound = run.handsPlayedRound + 1
  local result = ns.Scoring.score(ctx)
  removePlayed(run, cards)
  -- Scoring worked on scratch copies of the instances and cards; this is the commit. A trinket
  -- destroyed while scoring changes hands, discards and hand size, so the swap settles them.
  Run.withMods(run, function()
    run.trinkets = result.trinketsAfter
    for id, fields in pairs(result.cardsAfter) do
      local card = ns.Deck.find(run, id)
      if card then
        card.enh, card.bonusChips, card.seal, card.ed = fields.enh, fields.bonusChips, fields.seal, fields.ed
      end
    end
    applySideEffects(run, result.sideEffects)
    for handId, n in pairs(result.levelUps) do run.handLevels[handId] = (run.handLevels[handId] or 1) + n end
  end)
  run.handPlays[result.handId] = (run.handPlays[result.handId] or 0) + 1
  run.roundHandPlays[result.handId] = (run.roundHandPlays[result.handId] or 0) + 1
  event("cardsPlayed", #cards, run)
  run.gold = goldRef.gold
  run.seenHands[result.handId] = true
  run.lastHandId = result.handId
  run.score = run.score + result.total
  run.handsLeft = run.handsLeft - 1
  for _, id in ipairs(result.destroyed) do ns.Deck.destroy(run, id) end
  ns.TrinketEngine.flushCards(run)
  if run.score < run.target then refill(run) end
  run.lastResult = result
  if run.score >= run.target then
    Run.winBlind(run)
  elseif run.handsLeft == 0 then
    lose(run)
  else
    Run.checkHand(run)
  end
  return result
end

-- Returns { created = { items } }: Scrolls the discarded Purple seals made.
function Run.discard(run, idx)
  local ok, reason = Run.canDiscard(run, idx)
  if not ok then return nil, reason end
  run.discardsLeft = run.discardsLeft - 1
  event("cardsDiscarded", #idx, run)
  local outcome = { created = {} }
  local cards = {}
  for i, index in ipairs(idx) do cards[i] = run.hand[index] end
  -- Before the count moves, so a first-discard trinket sees 0; hooks may destroy cards in hand.
  ns.TrinketEngine.fire(run, "onDiscard", cards)
  run.discardsUsedRound = run.discardsUsedRound + 1
  if ns.Consumables then
    local boss = Run.activeBoss(run)
    local rules = ns.TrinketRules.set(run.trinkets)
    for _, card in ipairs(cards) do
      local debuffed = boss and boss.debuff and boss.debuff(card, rules)
      if card.seal == "PURPLE" and not debuffed and #run.consumables < ns.Consumables.slots(run) then
        local item = ns.Consumables.random(run, "scroll")
        ns.Consumables.add(run, item)
        outcome.created[#outcome.created + 1] = item
      end
    end
  end
  local gone = {}
  for _, card in ipairs(cards) do gone[card] = true end
  for i = #run.hand, 1, -1 do
    if gone[run.hand[i]] then table.remove(run.hand, i) end
  end
  refill(run)
  ns.TrinketEngine.flushCards(run)
  Run.checkHand(run)
  return outcome
end

-- opts.saved: a loss prevented by an onLose trinket; the blind reward is replaced by the save.
function Run.winBlind(run, opts)
  if run.blind == 3 then run.shopVoucher = nil end
  ns.TrinketEngine.fire(run, "roundUpdate")
  if run.blind == 3 then ns.TrinketEngine.fire(run, "onBossDefeated") end
  local deck = ns.Decks.def[run.deckId]
  local payout = {
    reward = Run.BLIND_REWARDS[run.blind], hands = run.handsLeft * (deck.goldPerHand or 1),
    discards = run.discardsLeft * (deck.goldPerDiscard or 0),
    interest = 0, trinkets = 0, held = 0,
  }
  if opts and opts.saved then payout.reward, payout.saved, payout.savedId = 0, run.savedBy, run.savedById end
  local cap = ns.Vouchers.interestCap(run)
  local units = deck.noInterest and 0 or math.min(cap, math.floor(math.max(0, run.gold) / 5))
  payout.interest = units * (1 + ns.Trinkets.interestBonus(run))
  local streak = (units == cap and units > 0) and run.streak.maxInterest + 1 or 0
  if streak ~= run.streak.maxInterest then
    run.streak.maxInterest = streak
    event("maxInterestStreak", streak, run)
  end
  payout.trinketLines = {}
  ns.TrinketEngine.each(run.trinkets, function(slot, instance, def, isCopy)
    local gold = def.onRoundEnd and def.onRoundEnd(run, instance, isCopy)
    if gold and gold > 0 then
      local own = run.trinkets[slot]
      payout.trinketLines[#payout.trinketLines + 1] = { uid = own.uid, id = own.id, gold = gold }
      payout.trinkets = payout.trinkets + gold
    end
  end)
  local boss = Run.activeBoss(run)
  local rules = ns.TrinketRules.set(run.trinkets)
  for _, card in ipairs(run.hand) do
    if not (boss and boss.debuff and boss.debuff(card, rules)) then
      if card.enh == "GOLD" then
        payout.held = payout.held + ((card.seal == "RED") and 6 or 3)
      end
      if card.seal == "BLUE" and run.lastHandId and ns.Consumables
        and #run.consumables < ns.Consumables.slots(run) then
        ns.Consumables.add(run, { kind = "tome", id = run.lastHandId })
        payout.created = (payout.created or 0) + 1
      end
    end
  end
  payout.total = payout.reward + payout.hands + payout.discards + payout.interest + payout.trinkets + payout.held
  run.lastPayout = payout
  run.gold = run.gold + payout.total
  if run.stage == 8 and run.blind == 3 then
    run.phase = "won"
    event("runEnded", 1, run)
  else
    run.phase = "shop"
    ns.Shop.open(run)
  end
end

function Run.nextBlind(run)
  if run.shop and run.shop.openPack then return false, "pack" end
  if run.phase ~= "shop" then return end
  if run.blind == 3 then
    run.stage, run.blind = run.stage + 1, 1
    run.bossRerollsUsed = 0
  else
    run.blind = run.blind + 1
  end
  run.phase = "blind"
end

function Run.canRerollBoss(run)
  if run.stage >= 8 then return false, "The final boss cannot be rerolled." end
  if run.phase ~= "blind" then return false, "Only on the blind screen" end
  if run.bossRerollsUsed >= ns.Vouchers.bossRerolls(run) then return false, "No boss rerolls left." end
  if not Run.canAfford(run, Run.BOSS_REROLL_COST) then return false, "Not enough gold." end
  return true
end

-- Picks a boss other than `current` from the pool, preferring ones not yet
-- fought (the final boss is never in the pool).
local function pickBoss(run, current)
  local fresh, any = {}, {}
  for _, id in ipairs(ns.Bosses.pool) do
    if id ~= current then
      any[#any + 1] = id
      if not run.bossesFought[id] then fresh[#fresh + 1] = id end
    end
  end
  return ns.RNG.pick(run.rng, #fresh > 0 and fresh or any)
end

-- A stage replayed after Hieroglyph or Petroglyph gets a new boss if its old
-- one was already fought (Balatro does the same when you go back an ante).
function Run.refreshReplayedBoss(run, stage)
  local current = run.bosses and run.bosses[stage]
  if stage >= 8 or not current or not run.bossesFought[current] then return end
  run.bosses[stage] = pickBoss(run, current)
end

function Run.rerollBoss(run)
  local ok, reason = Run.canRerollBoss(run)
  if not ok then return false, reason end
  local bossId = pickBoss(run, run.bosses[run.stage])
  run.gold = run.gold - Run.BOSS_REROLL_COST
  run.bossRerollsUsed = run.bossRerollsUsed + 1
  run.bosses[run.stage] = bossId
  event("spend", Run.BOSS_REROLL_COST, run)
  return true, bossId
end

function Run.sortHand(run, mode)
  run.sortMode = mode
  ns.Cards.sort(run.hand, mode)
end

ns.Run = Run
