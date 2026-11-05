local _, ns = ...

-- Card: { rank = 2..14, suit = "S"|"H"|"C"|"D", id = 1..52 }. 11=J, 12=Q, 13=K, 14=A.
local Cards = {}

Cards.SUITS = { "S", "H", "C", "D" }
Cards.SUIT_NAMES = { S = "Spades", H = "Hearts", C = "Clubs", D = "Diamonds" }

local SUIT_ORDER = { S = 1, H = 2, C = 3, D = 4 }
local LABELS = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }

function Cards.newDeck()
  local deck = {}
  for si, suit in ipairs(Cards.SUITS) do
    for rank = 2, 14 do
      deck[#deck + 1] = { rank = rank, suit = suit, id = (si - 1) * 13 + (rank - 1) }
    end
  end
  return deck
end

function Cards.shuffledDeck(r)
  local deck = Cards.newDeck()
  ns.RNG.shuffle(r, deck)
  return deck
end

-- Moves up to n cards from the end of pile into hand. Returns the number drawn.
function Cards.draw(pile, hand, n)
  local drawn = 0
  while drawn < n and #pile > 0 do
    hand[#hand + 1] = table.remove(pile)
    drawn = drawn + 1
  end
  return drawn
end

function Cards.chipValue(card)
  if card.rank == 14 then return 11 end
  if card.rank >= 11 then return 10 end
  return card.rank
end

function Cards.isFace(card)
  return card.rank >= 11 and card.rank <= 13
end

-- mode "rank": rank desc, then suit. mode "suit": suit, then rank desc.
function Cards.sort(list, mode)
  table.sort(list, function(a, b)
    if mode == "suit" then
      if a.suit ~= b.suit then return SUIT_ORDER[a.suit] < SUIT_ORDER[b.suit] end
      return a.rank > b.rank
    end
    if a.rank ~= b.rank then return a.rank > b.rank end
    return SUIT_ORDER[a.suit] < SUIT_ORDER[b.suit]
  end)
end

function Cards.label(card)
  return LABELS[card.rank] or tostring(card.rank)
end

ns.Cards = Cards
