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
