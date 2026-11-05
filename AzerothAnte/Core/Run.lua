local _, ns = ...

local Run = {}

Run.BASE_TARGETS = { 300, 600, 1200, 2200, 3600, 5500, 8000, 11000 }

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
    handSize = 8, maxTrinkets = 5, trinkets = {}, handLevels = {},
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

function Run.bossId(run)
  if run.blind == 3 then return run.bosses[run.stage] end
end

function Run.startBlind(run)
  local deck = ns.Decks.def[run.deckId]
  local bossId = Run.bossId(run)
  local boss = bossId and ns.Bosses.def[bossId]
  run.phase = "play"
  run.pile = ns.Cards.shuffledDeck(run.rng)
  run.hand = {}
  ns.Cards.draw(run.pile, run.hand, run.handSize)
  ns.Cards.sort(run.hand, run.sortMode or "rank")
  run.handsLeft = boss and boss.hands or deck.hands
  run.discardsLeft = boss and boss.discards or deck.discards
  run.score = 0
  run.target = Run.target(run.stage, run.blind, bossId)
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

local function removeAndRefill(run, idx)
  local descending = {}
  for i, index in ipairs(idx) do descending[i] = index end
  table.sort(descending, function(a, b) return a > b end)
  for _, index in ipairs(descending) do table.remove(run.hand, index) end
  ns.Cards.draw(run.pile, run.hand, run.handSize - #run.hand)
  ns.Cards.sort(run.hand, run.sortMode or "rank")
end

function Run.play(run, idx)
  local ok, reason = Run.canPlay(run, idx)
  if not ok then return nil, reason end
  local cards = {}
  for i, index in ipairs(idx) do cards[i] = run.hand[index] end
  run.handsPlayedTotal = run.handsPlayedTotal + 1
  local result = ns.Scoring.score({
    cards = cards, handLevels = run.handLevels, trinkets = run.trinkets,
    bossId = Run.bossId(run), rng = run.rng, handsPlayedTotal = run.handsPlayedTotal,
    isLastHand = run.handsLeft == 1, discardsLeft = run.discardsLeft, gold = run.gold,
  })
  run.score = run.score + result.total
  run.handsLeft = run.handsLeft - 1
  removeAndRefill(run, idx)
  run.lastResult = result
  if run.score >= run.target then
    Run.winBlind(run)
  elseif run.handsLeft == 0 then
    run.phase = "lost"
  end
  return result
end

function Run.discard(run, idx)
  local ok, reason = Run.canDiscard(run, idx)
  if not ok then return nil, reason end
  run.discardsLeft = run.discardsLeft - 1
  removeAndRefill(run, idx)
end

function Run.winBlind(run)
  local payout = {
    reward = ({ 3, 4, 5 })[run.blind], hands = run.handsLeft,
    interest = math.min(5, math.floor(run.gold / 5)), trinkets = 0,
  }
  for _, trinket in ipairs(run.trinkets) do
    local def = ns.Trinkets.def[trinket.id]
    if def and def.onRoundEnd then
      payout.trinkets = payout.trinkets + (def.onRoundEnd(run) or 0)
    end
  end
  payout.total = payout.reward + payout.hands + payout.interest + payout.trinkets
  run.lastPayout = payout
  run.gold = run.gold + payout.total
  if run.stage == 8 and run.blind == 3 then
    run.phase = "won"
  else
    run.phase = "shop"
    ns.Shop.open(run)
  end
end

function Run.nextBlind(run)
  if run.phase ~= "shop" then return end
  if run.blind == 3 then
    run.stage, run.blind = run.stage + 1, 1
  else
    run.blind = run.blind + 1
  end
  run.phase = "blind"
end

function Run.sortHand(run, mode)
  run.sortMode = mode
  ns.Cards.sort(run.hand, mode)
end

ns.Run = Run
