local _, ns = ...

local HandEval = {}

-- Find the longest qualifying run, scoring every card of its ranks. Ace can start low.
local function findStraight(cards, live, need, shortcut)
  local byRank = {}
  for _, i in ipairs(live) do
    local rank = cards[i].rank
    if not byRank[rank] then byRank[rank] = i end
  end
  byRank[1] = byRank[14]

  local path, used, best, bestLength = {}, {}, nil, need - 1
  local function search(rank)
    local i = byRank[rank]
    if not i or used[i] then return end
    path[#path + 1], used[i] = i, true
    if #path > bestLength then
      best, bestLength = {}, #path
      for _, index in ipairs(path) do best[index] = true end
    end
    if rank < 14 then search(rank + 1) end
    if shortcut and rank < 13 then search(rank + 2) end
    used[i], path[#path] = nil, nil
  end
  for rank = 1, 14 do search(rank) end
  if best then
    local ranks = {}
    for i in pairs(best) do ranks[cards[i].rank] = true end
    for _, i in ipairs(live) do
      if ranks[cards[i].rank] then best[i] = true end
    end
  end
  return best
end

-- Stone cards never form part of a hand, so only the other cards are analysed.
local function analyze(cards, rules)
  local live = {}
  for i, card in ipairs(cards) do
    if not ns.Cards.isStone(card) then live[#live + 1] = i end
  end

  local counts = {}
  local highest
  for _, i in ipairs(live) do
    local rank = cards[i].rank
    counts[rank] = (counts[rank] or 0) + 1
    if not highest or rank > cards[highest].rank then highest = i end
  end

  local pairsCount, triple, four, five = 0, false, false, false
  for _, count in pairs(counts) do
    if count >= 2 then pairsCount = pairsCount + 1 end
    if count >= 3 then triple = true end
    if count >= 4 then four = true end
    if count >= 5 then five = true end
  end

  local need = rules and rules.FOUR_FINGERS and 4 or 5
  local straight, flush, straightFlush
  if (rules and rules.FOUR_FINGERS and #live >= need) or #live == 5 then
    straight = findStraight(cards, live, need, rules and rules.SHORTCUT)
    local flushLength = 0
    for _, suit in ipairs(ns.Cards.SUITS) do
      local suited = {}
      for _, i in ipairs(live) do
        if ns.Cards.hasSuit(cards[i], suit, rules) then suited[#suited + 1] = i end
      end
      if #suited >= need then
        if #suited > flushLength then
          flush, flushLength = {}, #suited
          for _, i in ipairs(suited) do flush[i] = true end
        end
      end
    end
    if straight and flush then
      straightFlush = {}
      for i in pairs(straight) do straightFlush[i] = true end
      for i in pairs(flush) do straightFlush[i] = true end
    end
  end

  local contains = { HIGH_CARD = true }
  if pairsCount >= 1 then contains.PAIR = true end
  if pairsCount >= 2 then contains.TWO_PAIR = true end
  if triple then contains.THREE_KIND = true end
  if straight then contains.STRAIGHT = true end
  if flush then contains.FLUSH = true end
  if triple and pairsCount >= 2 then contains.FULL_HOUSE = true end
  if four then contains.FOUR_KIND = true end
  if five then contains.FIVE_KIND = true end
  if straightFlush then contains.STRAIGHT_FLUSH = true end
  if flush and triple and pairsCount >= 2 then contains.FLUSH_HOUSE = true end
  if flush and five then contains.FLUSH_FIVE = true end
  return contains, counts, highest, { STRAIGHT = straight, FLUSH = flush, STRAIGHT_FLUSH = straightFlush }
end

function HandEval.contains(cards, rules)
  local contains = analyze(cards, rules)
  return contains
end

function HandEval.evaluate(cards, rules)
  local contains, counts, highest, groups = analyze(cards, rules)
  local handId
  for i = #ns.Hands.order, 1, -1 do
    local id = ns.Hands.order[i]
    if contains[id] then
      handId = id
      break
    end
  end

  -- Stone cards always score. Other cards score only when they make up the hand.
  local matchedCount = { PAIR = 2, TWO_PAIR = 2, THREE_KIND = 3, FOUR_KIND = 4 }
  local scoringIdx = {}
  for i, card in ipairs(cards) do
    local scores
    if (rules and rules.SPLASH) or ns.Cards.isStone(card) then
      scores = true
    elseif handId == "HIGH_CARD" then
      scores = i == highest
    elseif groups[handId] then
      scores = groups[handId][i]
    elseif matchedCount[handId] then
      scores = counts[card.rank] == matchedCount[handId]
    else
      scores = true
    end
    if scores then scoringIdx[#scoringIdx + 1] = i end
  end
  return handId, scoringIdx
end

ns.HandEval = HandEval
