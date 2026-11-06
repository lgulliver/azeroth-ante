local ns, T = ...

local function newRun()
  return {
    deck = ns.Deck.new(), nextCardId = 53, hand = {}, pile = {},
    rng = ns.RNG.new(1), baseHandSize = 8, handSizeMod = 0,
  }
end

T.test("deck_new_ids", function()
  local deck = ns.Deck.new()
  T.eq(#deck, 52)
  local ids, cards = {}, {}
  for i, c in ipairs(deck) do
    T.eq(c.id, i)
    T.ok(not ids[c.id], "duplicate id")
    ids[c.id] = true
    T.ok(c.rank >= 2 and c.rank <= 14)
    local key = c.suit .. c.rank
    T.ok(not cards[key], "duplicate rank and suit")
    cards[key] = true
  end
  for _, suit in ipairs({ "S", "H", "C", "D" }) do
    for rank = 2, 14 do T.ok(cards[suit .. rank]) end
  end
end)

T.test("deck_add_copy_destroy", function()
  local run = newRun()
  local card = { rank = 12, suit = "H", enh = "WILD", ed = "FOIL", seal = "RED" }
  local added = ns.Deck.add(run, card)
  T.ok(rawequal(added, card))
  T.ok(rawequal(run.deck[53], card))
  T.eq(card.id, 53)
  T.eq(#run.deck, 53)
  T.eq(run.nextCardId, 54)
  local copy = ns.Deck.copy(run, card)
  T.eq(copy, { id = 54, rank = 12, suit = "H", enh = "WILD", ed = "FOIL", seal = "RED" })
  T.ok(not rawequal(copy, card))
  T.ok(rawequal(ns.Deck.find(run, 54), copy))
  T.eq(run.nextCardId, 55)
  run.hand = { card, copy }
  run.pile = { copy, run.deck[1] }
  ns.Deck.destroy(run, 54)
  T.eq(#run.deck, 53)
  T.eq(ns.Deck.find(run, 54), nil)
  T.eq(#run.hand, 1)
  T.eq(#run.pile, 1)
  T.ok(rawequal(run.hand[1], card))
  T.ok(rawequal(run.pile[1], run.deck[1]))
  T.eq(run.nextCardId, 55)
  local stone = ns.Deck.add(run, { enh = "STONE", ed = "NEGATIVE", seal = "BLUE" })
  T.eq(ns.Deck.copy(run, stone), { id = 56, enh = "STONE", ed = "NEGATIVE", seal = "BLUE" })
end)

T.test("deck_relink", function()
  local run = newRun()
  run.deck[1].enh = "WILD"
  run.hand = { { id = 1, rank = 2, suit = "S", enh = "WILD" } }
  run.pile = { { id = 52, rank = 14, suit = "D" } }
  T.ok(not rawequal(run.hand[1], run.deck[1]))
  ns.Deck.relink(run)
  T.ok(rawequal(run.hand[1], ns.Deck.find(run, run.hand[1].id)))
  T.ok(rawequal(run.pile[1], run.deck[52]))
  run.hand[1].seal = "GOLD"
  T.eq(run.deck[1].seal, "GOLD")
end)

T.test("deck_shuffled_pile", function()
  local run, sameSeed = newRun(), newRun()
  local pile = ns.Deck.shuffledPile(run)
  local other = ns.Deck.shuffledPile(sameSeed)
  T.eq(#pile, 52)
  T.ok(not rawequal(pile, run.deck))
  local seen, moved = {}, false
  for i, c in ipairs(pile) do
    T.ok(rawequal(c, ns.Deck.find(run, c.id)))
    T.ok(not seen[c.id], "duplicate in pile")
    seen[c.id] = true
    T.eq(c.id, other[i].id)
    T.eq(run.deck[i].id, i, "deck order unchanged")
    if c.id ~= i then moved = true end
  end
  T.ok(moved, "pile shuffled")
  T.ok(run.rng.s ~= ns.RNG.new(1).s, "run RNG advanced")
end)

T.test("hand_size_negative", function()
  local run = newRun()
  T.eq(ns.Deck.handSize(run), 8)
  run.handSizeMod = -1
  run.deck[1].ed, run.deck[2].ed = "NEGATIVE", "NEGATIVE"
  run.deck[3].ed = "FOIL"
  T.eq(ns.Deck.handSize(run), 9)
  ns.Deck.destroy(run, 1)
  T.eq(ns.Deck.handSize(run), 8)
end)

T.test("deck_copy_keeps_ranked_stone", function()
  local run = newRun()
  local stone = ns.Deck.add(run, { rank = 14, suit = "H", enh = "STONE" })
  local copy = ns.Deck.copy(run, stone)
  T.eq(copy.enh, "STONE")
  T.eq(copy.rank, 14)
  T.eq(copy.suit, "H")
end)
