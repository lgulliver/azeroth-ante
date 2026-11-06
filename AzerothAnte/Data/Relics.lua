local _, ns = ...

-- Balatro's spectral cards. use(run, cards, api) -> nil. `cards` are the selected cards, left to right.
-- Hand effects read the hand through Consumables.targetCards, so they work in play and on an open pack.
-- `check(run) -> ok, reason` is an optional extra precondition.
local Relics = {}

local ICON = "Interface\\Icons\\INV_Misc_Rune_0"
local RARITY_RANK = { common = 1, uncommon = 2, rare = 3 }
local ENHANCEMENTS = {}

for id in pairs(ns.CardTypes.enh) do
  if id ~= "STONE" then ENHANCEMENTS[#ENHANCEMENTS + 1] = id end
end
table.sort(ENHANCEMENTS)

local function unownedTrinkets(run, trinkets)
  local owned, pool = {}, {}
  for _, trinket in ipairs(trinkets) do owned[trinket.id] = true end
  for _, id in ipairs(ns.Trinkets.order) do
    if not owned[id] and ns.Trinkets.inPool(run, id) then pool[#pool + 1] = id end
  end
  return pool
end

local function unedited(trinkets)
  local pool = {}
  for _, trinket in ipairs(trinkets) do
    if not trinket.ed then pool[#pool + 1] = trinket end
  end
  return pool
end

local function ofRarity(ids, rarity)
  local pool = {}
  for _, id in ipairs(ids) do
    if ns.Trinkets.def[id].rarity == rarity then pool[#pool + 1] = id end
  end
  return pool
end

local function rarestOf(ids)
  local best, bestRank = {}, 0
  for _, id in ipairs(ids) do
    local rank = RARITY_RANK[ns.Trinkets.def[id].rarity] or 0
    if rank > bestRank then
      best, bestRank = { id }, rank
    elseif rank == bestRank and rank > 0 then
      best[#best + 1] = id
    end
  end
  return best
end

local function trinketRoom(run)
  if #run.trinkets >= ns.Run.trinketSlots(run) then return false, "No trinket slot" end
  return true
end

-- Rolls an edition like Summoning does, then appends the trinket.
local function addTrinket(run, api, id)
  local trinkets = api.trinkets()
  local trinket = ns.Trinkets.create(run, id, ns.CardTypes.rollEdition(api.rng, true))
  trinkets[#trinkets + 1] = trinket
  api.touch(trinket)
end

local function voidPenalty(run) return run.voidPenalty or 1 end

local function handCheck(n)
  return function(run)
    local hand = ns.Consumables.targetCards(run)
    if not hand or #hand < n then
      return false, "Needs " .. n .. (n == 1 and " card" or " cards") .. " in hand"
    end
    return true
  end
end

local function trinketCheck(filter, reason)
  return function(run)
    if #filter(run.trinkets) == 0 then return false, reason end
    return true
  end
end

local function setSeal(seal)
  return function(_, cards, api)
    cards[1].seal = seal
    api.changed(cards[1])
  end
end

-- Destroys one random card in hand, then adds `count` random enhanced cards of ranks lo..hi.
local function swapForEnhanced(lo, hi, count)
  return function(run, _, api)
    api.destroy(ns.RNG.pick(api.rng, ns.Consumables.targetCards(run)))
    for _ = 1, count do
      api.addCard({
        rank = ns.RNG.int(api.rng, lo, hi),
        suit = ns.RNG.pick(api.rng, ns.Cards.SUITS),
        enh = ns.RNG.pick(api.rng, ENHANCEMENTS),
      })
    end
  end
end

local function eachInHand(run, fn)
  for _, card in ipairs(ns.Consumables.targetCards(run)) do fn(card) end
end

local function createRareCheck(run)
  local ok, reason = trinketRoom(run)
  if not ok then return ok, reason end
  if #ofRarity(unownedTrinkets(run, run.trinkets), "rare") == 0 then
    return false, "No eligible rare trinket"
  end
  return true
end

local function createRarestCheck(run)
  local ok, reason = trinketRoom(run)
  if not ok then return ok, reason end
  if #unownedTrinkets(run, run.trinkets) == 0 then return false, "No eligible trinket" end
  return true
end

local EDITIONLESS_REASON = "No eligible trinket"

local def = {
  COURT = {
    name = "Relic of the Court",
    desc = "Destroy 1 random card in hand; add 3 random enhanced face cards.",
    untargeted = true, check = handCheck(1), use = swapForEnhanced(11, 13, 3),
  },
  ACES = {
    name = "Relic of Aces",
    desc = "Destroy 1 random card in hand; add 2 random enhanced Aces.",
    untargeted = true, check = handCheck(1), use = swapForEnhanced(14, 14, 2),
  },
  NUMBERS = {
    name = "Relic of Numbers",
    desc = "Destroy 1 random card in hand; add 4 random enhanced numbered cards.",
    untargeted = true, check = handCheck(1), use = swapForEnhanced(2, 10, 4),
  },
  GOLD = {
    name = "Relic of Gold",
    desc = "Add a Gold seal to 1 selected card.",
    select = { min = 1, max = 1 }, use = setSeal("GOLD"),
  },
  RADIANCE = {
    name = "Relic of Radiance",
    desc = "Add Foil, Holo or Polychrome to 1 selected card.",
    select = { min = 1, max = 1 },
    checkCards = function(_, cards)
      if cards[1].ed then return false, "Card already has an edition" end
      return true
    end,
    use = function(_, cards, api)
      cards[1].ed = ns.CardTypes.rollAura(api.rng)
      api.changed(cards[1])
    end,
  },
  LICH = {
    name = "Relic of the Lich",
    desc = "Create a rare trinket; set gold to 0g.",
    untargeted = true, check = createRareCheck,
    use = function(run, _, api)
      api.gold(-run.gold)
      local pool = ofRarity(unownedTrinkets(run, api.trinkets()), "rare")
      addTrinket(run, api, ns.RNG.pick(api.rng, pool))
    end,
  },
  UNITY = {
    name = "Relic of Unity",
    desc = "Every card in hand becomes one random suit.",
    untargeted = true, check = handCheck(1),
    use = function(run, _, api)
      local suit = ns.RNG.pick(api.rng, ns.Cards.SUITS)
      eachInHand(run, function(card)
        card.suit = suit
        api.changed(card)
      end)
    end,
  },
  WHISPERS = {
    name = "Relic of Whispers",
    desc = "Every card in hand becomes one random rank; -1 hand size.",
    untargeted = true, check = handCheck(1),
    use = function(run, _, api)
      local rank = ns.RNG.int(api.rng, 2, 14)
      eachInHand(run, function(card)
        card.rank = rank
        api.changed(card)
      end)
      api.handSize(-1)
    end,
  },
  VOID = {
    name = "Relic of the Void",
    desc = "A random trinket becomes Negative; -1 hand size (grows by 1 each use).",
    descFor = function(run)
      return "A random trinket becomes Negative; -" .. voidPenalty(run)
        .. " hand size (the penalty grows by 1 each use)."
    end,
    untargeted = true, check = trinketCheck(unedited, EDITIONLESS_REASON),
    use = function(run, _, api)
      local chosen = ns.RNG.pick(api.rng, unedited(api.trinkets()))
      chosen.ed = "NEGATIVE"
      api.touch(chosen)
      api.handSize(-voidPenalty(run))
      run.voidPenalty = voidPenalty(run) + 1
    end,
  },
  FLAME = {
    name = "Relic of Flame",
    desc = "Destroy up to 5 random cards in hand; gain 20g.",
    untargeted = true, check = handCheck(1),
    use = function(run, _, api)
      local pool = {}
      for i, card in ipairs(ns.Consumables.targetCards(run)) do pool[i] = card end
      ns.RNG.shuffle(api.rng, pool)
      for i = 1, math.min(5, #pool) do api.destroy(pool[i]) end
      api.gold(20)
    end,
  },
  REBIRTH = {
    name = "Relic of Rebirth",
    desc = "Copy a random trinket and destroy the others (Negative is removed from the copy).",
    untargeted = true, check = trinketCheck(function(t) return t end, "No trinkets"),
    use = function(run, _, api)
      local trinkets = api.trinkets()
      local chosen = ns.RNG.pick(api.rng, trinkets)
      local copy = ns.Trinkets.create(run, chosen.id, chosen.ed ~= "NEGATIVE" and chosen.ed or nil)
      for i = #trinkets, 1, -1 do
        if trinkets[i] ~= chosen then table.remove(trinkets, i) end
      end
      trinkets[#trinkets + 1] = copy
      api.touch(copy)
    end,
  },
  RECURRENCE = {
    name = "Relic of Recurrence",
    desc = "Add a Red seal to 1 selected card.",
    select = { min = 1, max = 1 }, use = setSeal("RED"),
  },
  HEXES = {
    name = "Relic of Hexes",
    desc = "A random trinket becomes Polychrome; destroy the others.",
    untargeted = true, check = trinketCheck(unedited, EDITIONLESS_REASON),
    use = function(_, _, api)
      local trinkets = api.trinkets()
      local chosen = ns.RNG.pick(api.rng, unedited(trinkets))
      chosen.ed = "POLY"
      api.touch(chosen)
      for i = #trinkets, 1, -1 do
        if trinkets[i] ~= chosen then table.remove(trinkets, i) end
      end
    end,
  },
  INSIGHT = {
    name = "Relic of Insight",
    desc = "Add a Blue seal to 1 selected card.",
    select = { min = 1, max = 1 }, use = setSeal("BLUE"),
  },
  SPIRITS = {
    name = "Relic of Spirits",
    desc = "Add a Purple seal to 1 selected card.",
    select = { min = 1, max = 1 }, use = setSeal("PURPLE"),
  },
  MIRRORS = {
    name = "Relic of Mirrors",
    desc = "Add 2 copies of 1 selected card to the deck.",
    select = { min = 1, max = 1 },
    use = function(_, cards, api)
      local card = cards[1]
      for _ = 1, 2 do
        api.addCard({ rank = card.rank, suit = card.suit, enh = card.enh, ed = card.ed, seal = card.seal })
      end
    end,
  },
  LEGENDS = {
    name = "Relic of Legends",
    desc = "Create the rarest trinket available (no legendaries in v2).",
    untargeted = true, check = createRarestCheck,
    use = function(run, _, api)
      local pool = rarestOf(unownedTrinkets(run, api.trinkets()))
      addTrinket(run, api, ns.RNG.pick(api.rng, pool))
    end,
  },
  COSMOS = {
    name = "Relic of the Cosmos",
    desc = "Levels up every hand type.",
    untargeted = true,
    use = function(_, _, api)
      for _, id in ipairs(ns.Hands.order) do api.level(id) end -- secret hands too; they stay hidden
    end,
  },
}

Relics.order = {
  "COURT", "ACES", "NUMBERS", "GOLD", "RADIANCE", "LICH", "UNITY", "WHISPERS", "VOID",
  "FLAME", "REBIRTH", "RECURRENCE", "HEXES", "INSIGHT", "SPIRITS", "MIRRORS", "LEGENDS", "COSMOS",
}

local AFFECTS = {
  COURT = "Destroys 1 random card in hand; adds 3 enhanced face cards",
  ACES = "Destroys 1 random card in hand; adds 2 enhanced Aces",
  NUMBERS = "Destroys 1 random card in hand; adds 4 enhanced numbered cards",
  GOLD = "1 selected card gains a Gold seal",
  RADIANCE = "1 selected card gains Foil, Holo or Polychrome",
  LICH = "Creates a rare trinket - sets gold to 0g",
  UNITY = "All cards in hand -> one random suit",
  WHISPERS = "All cards in hand -> one rank; -1 hand size",
  VOID = "1 random trinket -> Negative; -1 hand size (grows each use)",
  FLAME = "Destroys up to 5 random cards in hand; gives 20g",
  REBIRTH = "Copies 1 random trinket, destroys the other trinkets",
  RECURRENCE = "1 selected card gains a Red seal",
  HEXES = "1 random trinket -> Polychrome; destroys the other trinkets",
  INSIGHT = "1 selected card gains a Blue seal",
  SPIRITS = "1 selected card gains a Purple seal",
  MIRRORS = "Adds 2 copies of 1 selected card to the deck",
  LEGENDS = "Creates the rarest trinket available",
  COSMOS = "Levels up every hand type",
}

local AFFECTS_FOR = {
  VOID = function(run)
    return "1 random trinket -> Negative; -" .. voidPenalty(run) .. " hand size"
  end,
}

Relics.def = def
for i, id in ipairs(Relics.order) do
  local d = def[id]
  d.id = id
  d.affects = AFFECTS[id]
  d.affectsFor = AFFECTS_FOR[id]
  d.icon = ICON .. ((i - 1) % 6 + 1)
  d.untargeted = d.untargeted or false
  d.creates = false
end

ns.Relics = Relics
