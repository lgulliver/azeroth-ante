local _, ns = ...

local HandEval = {}

-- Stone cards never form part of a hand, so only the other cards are analysed.
local function analyze(cards)
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

  local pairsCount, triple, four, five, unique = 0, false, false, false, 0
  local minRank, maxRank = 14, 2
  for rank, count in pairs(counts) do
    unique = unique + 1
    if rank < minRank then minRank = rank end
    if rank > maxRank then maxRank = rank end
    if count >= 2 then pairsCount = pairsCount + 1 end
    if count >= 3 then triple = true end
    if count >= 4 then four = true end
    if count >= 5 then five = true end
  end

  local straight, flush = false, false
  if #live == 5 then
    local wheel = counts[14] == 1 and counts[2] == 1 and counts[3] == 1
      and counts[4] == 1 and counts[5] == 1
    straight = unique == 5 and (maxRank - minRank == 4 or wheel)
    -- A Wild card counts toward every suit, so one suit must fit all five.
    for _, suit in ipairs(ns.Cards.SUITS) do
      local all = true
      for _, i in ipairs(live) do
        if not ns.Cards.hasSuit(cards[i], suit) then
          all = false
          break
        end
      end
      if all then
        flush = true
        break
      end
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
  if straight and flush then contains.STRAIGHT_FLUSH = true end
  if flush and triple and pairsCount >= 2 then contains.FLUSH_HOUSE = true end
  if flush and five then contains.FLUSH_FIVE = true end
  return contains, counts, highest
end

function HandEval.contains(cards)
  local contains = analyze(cards)
  return contains
end

function HandEval.evaluate(cards)
  local contains, counts, highest = analyze(cards)
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
    if ns.Cards.isStone(card) then
      scores = true
    elseif handId == "HIGH_CARD" then
      scores = i == highest
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
