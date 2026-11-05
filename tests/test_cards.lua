local ns, T = ...

local function card(rank, suit)
  return { rank = rank, suit = suit, id = 1 }
end

T.test("new_deck_52_unique", function()
  local deck = ns.Cards.newDeck()
  T.eq(#deck, 52)
  local ids, perSuit = {}, {}
  for _, c in ipairs(deck) do
    T.ok(not ids[c.id], "duplicate id " .. c.id)
    ids[c.id] = true
    perSuit[c.suit] = (perSuit[c.suit] or 0) + 1
  end
  for _, s in ipairs({ "S", "H", "C", "D" }) do
    T.eq(perSuit[s], 13, "suit " .. s)
  end
end)

T.test("chip_values", function()
  T.eq(ns.Cards.chipValue(card(2, "S")), 2)
  T.eq(ns.Cards.chipValue(card(10, "S")), 10)
  T.eq(ns.Cards.chipValue(card(12, "S")), 10)
  T.eq(ns.Cards.chipValue(card(14, "S")), 11)
end)

T.test("is_face", function()
  T.ok(ns.Cards.isFace(card(11, "S")), "J")
  T.ok(ns.Cards.isFace(card(12, "S")), "Q")
  T.ok(ns.Cards.isFace(card(13, "S")), "K")
  T.ok(not ns.Cards.isFace(card(10, "S")), "10")
  T.ok(not ns.Cards.isFace(card(14, "S")), "A")
end)

T.test("sort_rank", function()
  local list = { card(14, "S"), card(2, "H"), card(13, "C") }
  ns.Cards.sort(list, "rank")
  T.eq(list[1].rank, 14)
  T.eq(list[2].rank, 13)
  T.eq(list[3].rank, 2)
end)

T.test("draw_past_empty", function()
  local pile = { card(2, "S"), card(3, "S"), card(4, "S") }
  local hand = {}
  local n = ns.Cards.draw(pile, hand, 8)
  T.eq(n, 3)
  T.eq(#hand, 3)
  T.eq(#pile, 0)
end)

T.test("cards_stone_and_wild", function()
  local stone = { id = 53, enh = "STONE" }
  local wild = { id = 54, rank = 12, suit = "D", enh = "WILD" }
  T.ok(ns.Cards.isStone(stone))
  T.ok(not ns.Cards.isStone(wild))
  for _, suit in ipairs({ "S", "H", "C", "D" }) do
    T.eq(ns.Cards.hasSuit(stone, suit), false)
    T.eq(ns.Cards.hasSuit(wild, suit), true)
  end
  T.eq(ns.Cards.hasSuit(card(2, "S"), "S"), true)
  T.eq(ns.Cards.hasSuit(card(2, "S"), "H"), false)
  T.eq(ns.Cards.chipValue(stone), 0)
  T.eq(ns.Cards.isFace(stone), false)
  T.eq(ns.Cards.label(stone), "")
  T.eq(ns.Cards.chipValue(wild), 10)
  T.eq(ns.Cards.isFace(wild), true)
  T.eq(ns.Cards.label(wild), "Q")
  local two, ace = card(2, "S"), card(14, "H")
  local otherStone = { id = 55, enh = "STONE" }
  local list = { stone, two, ace, otherStone }
  ns.Cards.sort(list, "rank")
  T.ok(rawequal(list[1], ace))
  T.ok(rawequal(list[2], two))
  T.ok(ns.Cards.isStone(list[3]) and ns.Cards.isStone(list[4]))
  ns.Cards.sort(list, "suit")
  T.ok(rawequal(list[1], two))
  T.ok(rawequal(list[2], ace))
  T.ok(ns.Cards.isStone(list[3]) and ns.Cards.isStone(list[4]))
end)
