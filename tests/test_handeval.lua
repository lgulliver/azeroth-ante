local ns, T = ...

local function cards(ranks, suits)
  local result = {}
  local suitOrder = { S = 0, H = 1, C = 2, D = 3 }
  suits = suits or { "S", "H", "C", "D", "H" }
  for i, rank in ipairs(ranks) do
    result[i] = { rank = rank, suit = suits[i], id = suitOrder[suits[i]] * 13 + rank - 1 }
  end
  return result
end

local cases = {
  { "high_card", { 2, 13, 5, 9, 7 }, "HIGH_CARD", { 2 } },
  { "pair", { 2, 9, 5, 9, 7 }, "PAIR", { 2, 4 } },
  { "two_pair", { 9, 2, 5, 2, 9 }, "TWO_PAIR", { 1, 2, 4, 5 } },
  { "three_kind", { 9, 2, 9, 5, 9 }, "THREE_KIND", { 1, 3, 5 } },
  { "straight", { 8, 5, 7, 9, 6 }, "STRAIGHT", { 1, 2, 3, 4, 5 } },
  { "flush", { 2, 13, 5, 9, 7 }, "FLUSH", { 1, 2, 3, 4, 5 }, { "H", "H", "H", "H", "H" } },
  { "full_house", { 9, 2, 9, 2, 9 }, "FULL_HOUSE", { 1, 2, 3, 4, 5 } },
  { "four_kind", { 9, 2, 9, 9, 9 }, "FOUR_KIND", { 1, 3, 4, 5 }, { "S", "S", "H", "C", "D" } },
  { "straight_flush", { 12, 10, 14, 11, 13 }, "STRAIGHT_FLUSH", { 1, 2, 3, 4, 5 }, { "S", "S", "S", "S", "S" } },
  { "ace_low_straight", { 14, 2, 3, 4, 5 }, "STRAIGHT", { 1, 2, 3, 4, 5 } },
  { "four_card_flush_not_flush", { 2, 13, 5, 9 }, "HIGH_CARD", { 2 }, { "H", "H", "H", "H" } },
  { "pair_scoring_only_pair", { 13, 13, 2, 5, 9 }, "PAIR", { 1, 2 } },
  { "single_card", { 14 }, "HIGH_CARD", { 1 } },
  { "two_card_pair", { 2, 2 }, "PAIR", { 1, 2 } },
  { "three_card_three_kind", { 2, 2, 2 }, "THREE_KIND", { 1, 2, 3 } },
  { "four_card_straight_not_straight", { 2, 3, 4, 5 }, "HIGH_CARD", { 4 } },
  { "duplicate_rank_not_straight", { 2, 3, 4, 5, 5 }, "PAIR", { 4, 5 } },
  { "ace_does_not_wrap", { 12, 13, 14, 2, 3 }, "HIGH_CARD", { 3 } },
}

for _, case in ipairs(cases) do
  T.test(case[1], function()
    local handId, scoringIdx = ns.HandEval.evaluate(cards(case[2], case[5]))
    T.eq(handId, case[3])
    T.eq(scoringIdx, case[4])
  end)
end

T.test("contains_sets", function()
  local expected = {
    { HIGH_CARD = true },
    { HIGH_CARD = true, PAIR = true },
    { HIGH_CARD = true, PAIR = true, TWO_PAIR = true },
    { HIGH_CARD = true, PAIR = true, THREE_KIND = true },
    { HIGH_CARD = true, STRAIGHT = true },
    { HIGH_CARD = true, FLUSH = true },
    { HIGH_CARD = true, PAIR = true, TWO_PAIR = true, THREE_KIND = true, FULL_HOUSE = true },
    { HIGH_CARD = true, PAIR = true, THREE_KIND = true, FOUR_KIND = true },
    { HIGH_CARD = true, STRAIGHT = true, FLUSH = true, STRAIGHT_FLUSH = true },
  }
  for i, set in ipairs(expected) do
    T.eq(ns.HandEval.contains(cards(cases[i][2], cases[i][5])), set, cases[i][1])
  end
end)

T.test("full_house_contains", function()
  local set = ns.HandEval.contains(cards({ 9, 2, 9, 2, 9 }))
  T.ok(set.PAIR)
  T.ok(set.TWO_PAIR)
  T.ok(set.THREE_KIND)
end)

T.test("hand_definitions", function()
  local order = { "HIGH_CARD", "PAIR", "TWO_PAIR", "THREE_KIND", "STRAIGHT", "FLUSH", "FULL_HOUSE", "FOUR_KIND", "STRAIGHT_FLUSH" }
  local values = {
    { "High Card", 5, 1, 10, 1 }, { "Pair", 10, 2, 15, 1 },
    { "Two Pair", 20, 2, 20, 1 }, { "Three of a Kind", 30, 3, 20, 2 },
    { "Straight", 30, 4, 30, 3 }, { "Flush", 35, 4, 15, 2 },
    { "Full House", 40, 4, 25, 2 }, { "Four of a Kind", 60, 7, 30, 3 },
    { "Straight Flush", 100, 8, 40, 4 },
  }
  T.eq(ns.Hands.order, order)
  for i, id in ipairs(order) do
    local v = values[i]
    T.eq(ns.Hands.def[id], { name = v[1], chips = v[2], mult = v[3], lvlChips = v[4], lvlMult = v[5] })
    local chips, mult = ns.Hands.base(id, 1)
    T.eq(chips, v[2])
    T.eq(mult, v[3])
  end
end)

T.test("base_levels", function()
  local chips, mult = ns.Hands.base("PAIR", 3)
  T.eq(chips, 40)
  T.eq(mult, 4)
end)

T.test("does_not_mutate_cards", function()
  local input = cards({ 9, 2, 9, 2, 9 })
  local original = cards({ 9, 2, 9, 2, 9 })
  ns.HandEval.evaluate(input)
  ns.HandEval.contains(input)
  T.eq(input, original)
end)
