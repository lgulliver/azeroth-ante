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
  local order = { "HIGH_CARD", "PAIR", "TWO_PAIR", "THREE_KIND", "STRAIGHT", "FLUSH", "FULL_HOUSE", "FOUR_KIND", "STRAIGHT_FLUSH", "FIVE_KIND", "FLUSH_HOUSE", "FLUSH_FIVE" }
  local values = {
    { "High Card", 5, 1, 10, 1 }, { "Pair", 10, 2, 15, 1 },
    { "Two Pair", 20, 2, 20, 1 }, { "Three of a Kind", 30, 3, 20, 2 },
    { "Straight", 30, 4, 30, 3 }, { "Flush", 35, 4, 15, 2 },
    { "Full House", 40, 4, 25, 2 }, { "Four of a Kind", 60, 7, 30, 3 },
    { "Straight Flush", 100, 8, 40, 4 },
  }
  T.eq(ns.Hands.order, order)
  for i, v in ipairs(values) do
    local id = order[i]
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

local function stone()
  return { enh = "STONE", id = 0 }
end

local H5 = { "H", "H", "H", "H", "H" }
local S5 = { "S", "S", "S", "S", "S" }

T.test("five_kind", function()
  T.eq((ns.HandEval.evaluate(cards({ 9, 9, 9, 9, 9 }))), "FIVE_KIND")
end)

T.test("flush_house", function()
  T.eq((ns.HandEval.evaluate(cards({ 13, 13, 13, 4, 4 }, H5))), "FLUSH_HOUSE")
end)

T.test("flush_five", function()
  T.eq((ns.HandEval.evaluate(cards({ 7, 7, 7, 7, 7 }, S5))), "FLUSH_FIVE")
end)

T.test("wild_completes_flush", function()
  local hand = cards({ 2, 5, 9, 13, 7 }, { "H", "H", "H", "H", "S" })
  hand[5].enh = "WILD"
  local handId, scoringIdx = ns.HandEval.evaluate(hand)
  T.eq(handId, "FLUSH")
  T.eq(scoringIdx, { 1, 2, 3, 4, 5 })
end)

T.test("stone_always_scores", function()
  local hand = cards({ 13, 13 }, { "S", "H" })
  hand[3] = stone()
  local handId, scoringIdx = ns.HandEval.evaluate(hand)
  T.eq(handId, "PAIR")
  T.ok(scoringIdx[3] == 3, "stone index in scoringIdx")
  T.eq(scoringIdx, { 1, 2, 3 })
end)

T.test("stone_breaks_straight", function()
  local hand = cards({ 2, 3, 4, 5 }, { "S", "H", "C", "D" })
  hand[5] = stone()
  local handId, scoringIdx = ns.HandEval.evaluate(hand)
  T.eq(handId, "HIGH_CARD")
  T.eq(scoringIdx, { 4, 5 })
end)

T.test("secret_hidden_until_seen", function()
  T.eq(#ns.Hands.visible({ seenHands = {} }), 9)
  T.eq(#ns.Hands.visible({ seenHands = { FIVE_KIND = true } }), 10)
end)

T.test("secret_definitions", function()
  T.eq(ns.Hands.def.FIVE_KIND, { name = "Five of a Kind", chips = 120, mult = 12, lvlChips = 35, lvlMult = 3, secret = true })
  T.eq(ns.Hands.def.FLUSH_HOUSE, { name = "Flush House", chips = 140, mult = 14, lvlChips = 40, lvlMult = 4, secret = true })
  T.eq(ns.Hands.def.FLUSH_FIVE, { name = "Flush Five", chips = 160, mult = 16, lvlChips = 50, lvlMult = 3, secret = true })
end)

T.test("secret_contains", function()
  local five = ns.HandEval.contains(cards({ 9, 9, 9, 9, 9 }))
  T.ok(five.FIVE_KIND and five.FOUR_KIND and five.THREE_KIND and five.PAIR)
  local flushFive = ns.HandEval.contains(cards({ 7, 7, 7, 7, 7 }, S5))
  T.ok(flushFive.FLUSH_FIVE and flushFive.FIVE_KIND and flushFive.FLUSH)
  local flushHouse = ns.HandEval.contains(cards({ 13, 13, 13, 4, 4 }, H5))
  T.ok(flushHouse.FLUSH_HOUSE and flushHouse.FULL_HOUSE and flushHouse.FLUSH)
  T.ok(flushHouse.TWO_PAIR and flushHouse.THREE_KIND and flushHouse.PAIR)
end)

local ruleCases = {
  { "four_fingers_flush_four_cards", { 2, 5, 9, 13, 3 }, { FOUR_FINGERS = true }, "FLUSH", { 1, 2, 3, 4 }, { "H", "H", "H", "H", "S" } },
  { "four_fingers_straight_four_cards_only_played", { 5, 6, 7, 8 }, { FOUR_FINGERS = true }, "STRAIGHT", { 1, 2, 3, 4 } },
  { "four_fingers_straight_flush", { 5, 6, 7, 8, 2 }, { FOUR_FINGERS = true }, "STRAIGHT_FLUSH", { 1, 2, 3, 4 }, { "H", "H", "H", "H", "S" } },
  { "shortcut_gap_straight", { 2, 4, 6, 8, 10 }, { SHORTCUT = true }, "STRAIGHT", { 1, 2, 3, 4, 5 } },
  { "shortcut_gap_too_big", { 2, 4, 6, 8, 11 }, { SHORTCUT = true }, "HIGH_CARD", { 5 } },
  { "shortcut_ace_low", { 14, 2, 3, 5, 6 }, { SHORTCUT = true }, "STRAIGHT", { 1, 2, 3, 4, 5 } },
  { "shortcut_ace_high", { 7, 9, 11, 13, 14 }, { SHORTCUT = true }, "STRAIGHT", { 1, 2, 3, 4, 5 } },
  { "shortcut_no_wrap", { 12, 13, 14, 2, 3 }, { SHORTCUT = true }, "HIGH_CARD", { 3 } },
  { "shortcut_needs_five", { 2, 4, 6, 8 }, { SHORTCUT = true }, "HIGH_CARD", { 4 } },
  { "four_fingers_and_shortcut", { 3, 5, 7, 9, 13 }, { FOUR_FINGERS = true, SHORTCUT = true }, "STRAIGHT", { 1, 2, 3, 4 } },
  { "smeared_flush", { 2, 5, 9, 13, 3 }, { SMEARED = true }, "FLUSH", { 1, 2, 3, 4, 5 }, { "H", "D", "H", "D", "H" } },
  { "smeared_flush_without_rule", { 2, 5, 9, 13, 3 }, nil, "HIGH_CARD", { 4 }, { "H", "D", "H", "D", "H" } },
  { "splash_all_score", { 7, 7, 2, 5, 9 }, { SPLASH = true }, "PAIR", { 1, 2, 3, 4, 5 } },
  { "four_fingers_five_straight_score", { 8, 5, 7, 9, 6 }, { FOUR_FINGERS = true }, "STRAIGHT", { 1, 2, 3, 4, 5 } },
  { "four_fingers_five_flush_score", { 2, 5, 9, 13, 3 }, { FOUR_FINGERS = true }, "FLUSH", { 1, 2, 3, 4, 5 }, H5 },
  { "four_fingers_five_straight_flush_score", { 5, 6, 7, 8, 9 }, { FOUR_FINGERS = true }, "STRAIGHT_FLUSH", { 1, 2, 3, 4, 5 }, H5 },
  { "four_fingers_pair_unchanged", { 7, 7, 2, 5, 9 }, { FOUR_FINGERS = true }, "PAIR", { 1, 2 } },
  { "four_fingers_distinct_ranks", { 2, 3, 4, 4, 9 }, { FOUR_FINGERS = true }, "PAIR", { 3, 4 } },
  { "four_fingers_duplicate_scores_once", { 2, 3, 4, 5, 5 }, { FOUR_FINGERS = true }, "STRAIGHT", { 1, 2, 3, 4 } },
  { "four_fingers_needs_same_subset", { 2, 3, 4, 9, 5 }, { FOUR_FINGERS = true }, "FLUSH", { 1, 2, 3, 4 }, { "H", "H", "H", "H", "S" } },
  { "four_fingers_shortcut_longest_run", { 2, 4, 5, 6, 8 }, { FOUR_FINGERS = true, SHORTCUT = true }, "STRAIGHT", { 1, 2, 3, 4, 5 } },
  { "four_fingers_smeared_straight_flush", { 5, 6, 7, 8, 2 }, { FOUR_FINGERS = true, SMEARED = true }, "STRAIGHT_FLUSH", { 1, 2, 3, 4 }, { "H", "D", "H", "D", "S" } },
}

for _, case in ipairs(ruleCases) do
  T.test(case[1], function()
    local input = cards(case[2], case[6])
    local handId, scoringIdx = ns.HandEval.evaluate(input, case[3])
    T.eq(handId, case[4])
    T.eq(scoringIdx, case[5])
    T.eq(ns.HandEval.contains(input, case[3])[case[4]], true)
  end)
end

T.test("nil_rules_unchanged", function()
  for _, case in ipairs(cases) do
    local input = cards(case[2], case[5])
    for _, rules in ipairs({ {}, { FOUR_FINGERS = false, SHORTCUT = false, SMEARED = false, SPLASH = false } }) do
      local handId, scoringIdx = ns.HandEval.evaluate(input, rules)
      T.eq(handId, case[3], case[1])
      T.eq(scoringIdx, case[4], case[1])
      T.eq(ns.HandEval.contains(input, rules), ns.HandEval.contains(input), case[1])
    end
  end
  local six = cards({ 2, 3, 4, 5, 6 }, H5)
  six[6] = { rank = 7, suit = "H" }
  T.eq((ns.HandEval.evaluate(six)), "HIGH_CARD")
end)

T.test("rule_hands_stone_never_qualifies_always_scores", function()
  local rules = { FOUR_FINGERS = true, SHORTCUT = true, SMEARED = true }
  local hand = cards({ 2, 4, 6 }, { "H", "D", "H" })
  hand[4] = { rank = 8, suit = "D", enh = "STONE" }
  local handId, scoringIdx = ns.HandEval.evaluate(hand, rules)
  T.eq(handId, "HIGH_CARD")
  T.eq(scoringIdx, { 3, 4 })
  hand[5] = { rank = 8, suit = "D" }
  handId, scoringIdx = ns.HandEval.evaluate(hand, rules)
  T.eq(handId, "STRAIGHT_FLUSH")
  T.eq(scoringIdx, { 1, 2, 3, 4, 5 })
end)

T.test("rule_hands_wild_and_splash", function()
  local hand = cards({ 2, 5, 9, 13, 3 }, { "H", "D", "H", "S", "C" })
  hand[4].enh = "WILD"
  local rules = { FOUR_FINGERS = true, SMEARED = true }
  local handId, scoringIdx = ns.HandEval.evaluate(hand, rules)
  T.eq(handId, "FLUSH")
  T.eq(scoringIdx, { 1, 2, 3, 4 })
  rules.SPLASH = true
  handId, scoringIdx = ns.HandEval.evaluate(hand, rules)
  T.eq(handId, "FLUSH")
  T.eq(scoringIdx, { 1, 2, 3, 4, 5 })
end)
