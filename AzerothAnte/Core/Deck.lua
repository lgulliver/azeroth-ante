local _, ns = ...

local Deck = {}

function Deck.new()
  local deck = {}
  for si, suit in ipairs(ns.Cards.SUITS) do
    for rank = 2, 14 do
      deck[#deck + 1] = { rank = rank, suit = suit, id = (si - 1) * 13 + (rank - 1) }
    end
  end
  return deck
end

-- Added and destroyed cards pile up in run.cardLog until TrinketEngine.flushCards tells the trinkets.
local function cardLog(run)
  run.cardLog = run.cardLog or { added = {}, destroyed = {} }
  return run.cardLog
end

function Deck.add(run, card)
  card.id = run.nextCardId
  run.nextCardId = run.nextCardId + 1
  run.deck[#run.deck + 1] = card
  local added = cardLog(run).added
  added[#added + 1] = card
  return card
end

function Deck.copy(run, card)
  return Deck.add(run, {
    rank = card.rank, suit = card.suit, enh = card.enh, ed = card.ed, seal = card.seal,
    bonusChips = card.bonusChips,
  })
end

function Deck.find(run, id)
  for _, card in ipairs(run.deck) do
    if card.id == id then return card end
  end
end

function Deck.destroy(run, id)
  local card = Deck.find(run, id)
  if card then
    local destroyed = cardLog(run).destroyed
    destroyed[#destroyed + 1] = {
      id = card.id, rank = card.rank, suit = card.suit, enh = card.enh, ed = card.ed, seal = card.seal,
      bonusChips = card.bonusChips,
    }
  end
  for _, list in ipairs({ run.deck, run.hand, run.pile }) do
    for i = #list, 1, -1 do
      if list[i].id == id then table.remove(list, i) end
    end
  end
end

function Deck.shuffledPile(run)
  local pile = {}
  for i, card in ipairs(run.deck) do pile[i] = card end
  ns.RNG.shuffle(run.rng, pile)
  return pile
end

function Deck.relink(run)
  local byId = {}
  for _, card in ipairs(run.deck) do byId[card.id] = card end
  local lists = { run.hand, run.pile }
  local pack = run.shop and run.shop.openPack
  if pack and pack.hand then lists[#lists + 1] = pack.hand end
  for _, list in ipairs(lists) do
    for i, card in ipairs(list) do list[i] = byId[card.id] end
  end
end

function Deck.handSize(run)
  local size = run.baseHandSize + run.handSizeMod + ns.Vouchers.extraHandSize(run)
  if run.trinkets then size = size + ns.Trinkets.mods(run).handSize end
  for _, card in ipairs(run.deck) do
    if card.ed == "NEGATIVE" then size = size + 1 end
  end
  return math.max(1, size)
end

ns.Deck = Deck
