local _, ns = ...

local HandEval = {}

local function analyze(cards)
  local counts = {}
  local highest = 1
  for i, card in ipairs(cards) do
    counts[card.rank] = (counts[card.rank] or 0) + 1
    if card.rank > cards[highest].rank then highest = i end
  end

  local pairsCount, triple, four, unique = 0, false, false, 0
  local minRank, maxRank = 14, 2
  for rank, count in pairs(counts) do
    unique = unique + 1
    if rank < minRank then minRank = rank end
    if rank > maxRank then maxRank = rank end
    if count >= 2 then pairsCount = pairsCount + 1 end
    if count >= 3 then triple = true end
    if count == 4 then four = true end
  end

  local straight, flush = false, false
  if #cards == 5 then
    local wheel = counts[14] == 1 and counts[2] == 1 and counts[3] == 1
      and counts[4] == 1 and counts[5] == 1
    straight = unique == 5 and (maxRank - minRank == 4 or wheel)
    flush = true
    for i = 2, #cards do
      if cards[i].suit ~= cards[1].suit then flush = false end
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
  if straight and flush then contains.STRAIGHT_FLUSH = true end
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

  if handId == "HIGH_CARD" then return handId, { highest } end

  local matchedCount = { PAIR = 2, TWO_PAIR = 2, THREE_KIND = 3, FOUR_KIND = 4 }
  local scoringIdx = {}
  for i, card in ipairs(cards) do
    if not matchedCount[handId] or counts[card.rank] == matchedCount[handId] then
      scoringIdx[#scoringIdx + 1] = i
    end
  end
  return handId, scoringIdx
end

ns.HandEval = HandEval
