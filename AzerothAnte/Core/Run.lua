local _, ns = ...

local Run = {}

Run.BASE_TARGETS = { 300, 600, 1200, 2200, 3600, 5500, 8000, 11000 }

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
    handsPlayedTotal = 0, bosses = {}, score = 0,
    target = Run.target(1, 1), handsLeft = deck.hands, discardsLeft = deck.discards,
    pile = {}, hand = {}, sortMode = "rank", lastResult = nil, lastPayout = nil,
  }
  for _, id in ipairs(ns.Hands.order) do run.handLevels[id] = 1 end
  local pool = {}
  for i, id in ipairs(ns.Bosses.pool) do pool[i] = id end
  ns.RNG.shuffle(run.rng, pool)
  for i = 1, 7 do run.bosses[i] = pool[i] end
  run.bosses[8] = ns.Bosses.FINAL
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

-- Hands and discards the current blind starts with: the deck's (or the boss's)
-- base plus voucher changes. Shared by startBlind and the blind-screen sidebar.
function Run.blindHands(run)
  local bossId = Run.bossId(run)
  local boss = bossId and ns.Bosses.def[bossId]
  return math.max(1, (boss and boss.hands or ns.Decks.def[run.deckId].hands) + ns.Vouchers.extraHands(run))
end

function Run.blindDiscards(run)
  local bossId = Run.bossId(run)
  local boss = bossId and ns.Bosses.def[bossId]
  return math.max(0, (boss and boss.discards or ns.Decks.def[run.deckId].discards) + ns.Vouchers.extraDiscards(run))
end

function Run.startBlind(run)
  local bossId = Run.bossId(run)
  run.phase = "play"
  run.pile = ns.Deck.shuffledPile(run)
  run.hand = {}
  ns.Cards.draw(run.pile, run.hand, ns.Deck.handSize(run))
  ns.Cards.sort(run.hand, run.sortMode or "rank")
  run.handsLeft = Run.blindHands(run)
  run.discardsLeft = Run.blindDiscards(run)
  run.score = 0
  run.roundHandPlays = {}
  run.target = Run.target(run.stage, run.blind, bossId)
  if bossId then
    run.bossesFought[bossId] = true
    event("bossFought", bossId, run)
  end
  event("handSize", ns.Deck.handSize(run), run)
  editionTrinkets(run)
  Run.checkHand(run)
end

-- Ends the run as lost, once.
local function lose(run)
  if run.phase == "lost" then return end
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
  local bossId = Run.bossId(run)
  local boss = bossId and ns.Bosses.def[bossId]
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

local function removeSelected(run, idx)
  local descending = {}
  for i, index in ipairs(idx) do descending[i] = index end
  table.sort(descending, function(a, b) return a > b end)
  for _, index in ipairs(descending) do table.remove(run.hand, index) end
end

local function refill(run)
  ns.Cards.draw(run.pile, run.hand, ns.Deck.handSize(run) - #run.hand)
  ns.Cards.sort(run.hand, run.sortMode or "rank")
end

-- Never leaves the player with nothing to do. An empty hand refills from the
-- pile; if there is still nothing to play the blind is lost (unless already won).
function Run.checkHand(run)
  if run.phase ~= "play" then return end
  if #run.hand == 0 then refill(run) end
  if #run.hand == 0 and run.score < run.target then lose(run) end
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
  run.handsPlayedTotal = run.handsPlayedTotal + 1
  local result = ns.Scoring.score({
    cards = cards, held = held, goldRef = goldRef, handLevels = run.handLevels, trinkets = run.trinkets,
    bossId = Run.bossId(run), rng = run.rng, handsPlayedTotal = run.handsPlayedTotal,
    isLastHand = run.handsLeft == 1, discardsLeft = run.discardsLeft, gold = run.gold,
    consumables = ns.Vouchers.observatory(run) and run.consumables or nil,
  })
  run.handPlays[result.handId] = (run.handPlays[result.handId] or 0) + 1
  run.roundHandPlays[result.handId] = (run.roundHandPlays[result.handId] or 0) + 1
  event("cardsPlayed", #cards, run)
  run.gold = goldRef.gold
  run.seenHands[result.handId] = true
  run.lastHandId = result.handId
  run.score = run.score + result.total
  run.handsLeft = run.handsLeft - 1
  removeSelected(run, idx)
  for _, id in ipairs(result.destroyed) do ns.Deck.destroy(run, id) end
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
  if ns.Consumables then
    local boss = ns.Bosses.def[Run.bossId(run) or ""]
    for _, index in ipairs(idx) do
      local card = run.hand[index]
      local debuffed = boss and boss.debuff and boss.debuff(card)
      if card.seal == "PURPLE" and not debuffed and #run.consumables < ns.Consumables.slots(run) then
        local item = ns.Consumables.random(run, "scroll")
        ns.Consumables.add(run, item)
        outcome.created[#outcome.created + 1] = item
      end
    end
  end
  removeSelected(run, idx)
  refill(run)
  Run.checkHand(run)
  return outcome
end

function Run.winBlind(run)
  if run.blind == 3 then run.shopVoucher = nil end
  local deck = ns.Decks.def[run.deckId]
  local payout = {
    reward = Run.BLIND_REWARDS[run.blind], hands = run.handsLeft * (deck.goldPerHand or 1),
    discards = run.discardsLeft * (deck.goldPerDiscard or 0),
    interest = 0, trinkets = 0, held = 0,
  }
  local cap = ns.Vouchers.interestCap(run)
  if not deck.noInterest then payout.interest = math.min(cap, math.floor(run.gold / 5)) end
  local streak = (payout.interest == cap and payout.interest > 0) and run.streak.maxInterest + 1 or 0
  if streak ~= run.streak.maxInterest then
    run.streak.maxInterest = streak
    event("maxInterestStreak", streak, run)
  end
  for _, trinket in ipairs(run.trinkets) do
    local def = ns.Trinkets.def[trinket.id]
    if def and def.onRoundEnd then
      payout.trinkets = payout.trinkets + (def.onRoundEnd(run) or 0)
    end
  end
  local boss = ns.Bosses.def[Run.bossId(run)]
  for _, card in ipairs(run.hand) do
    if not (boss and boss.debuff and boss.debuff(card)) then
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
  if run.gold < Run.BOSS_REROLL_COST then return false, "Not enough gold." end
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
