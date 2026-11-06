local _, ns = ...

-- use(run, cards, api) -> nil. `cards` are the selected cards, left to right.
-- `check(run) -> ok, reason` is an optional extra precondition.
local Scrolls = {}

local ICON = "Interface\\Icons\\INV_Scroll_0"
local TRINKET_WEIGHTS = { { "common", 70 }, { "uncommon", 25 }, { "rare", 5 } }

local function setEnhancement(enh)
  return function(_, cards, api)
    for _, card in ipairs(cards) do
      card.enh = enh
      api.changed(card)
    end
  end
end

local function setSuit(suit)
  return function(_, cards, api)
    for _, card in ipairs(cards) do
      card.suit = suit
      api.changed(card)
    end
  end
end

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

local function trinketRoom(run)
  if #run.trinkets >= ns.Run.trinketSlots(run) then return false, "No trinket slot" end
  if #unownedTrinkets(run, run.trinkets) == 0 then return false, "No eligible trinket" end
  return true
end

local function createConsumables(kind)
  return function(_, _, api)
    for _ = 1, 2 do
      api.add({ kind = kind, id = api.randomId(kind) })
    end
  end
end

local def = {
  ECHOES = {
    name = "Scroll of Echoes", desc = "Create a copy of the last Scroll or Tome used this run (not itself).",
    untargeted = true, creates = true,
    check = function(run)
      if not run.lastConsumable then return false, "Nothing to copy" end
      return true
    end,
    use = function(run, _, api)
      local last = run.lastConsumable
      if last then api.add({ kind = last.kind, id = last.id }) end
    end,
  },
  FORTUNE = {
    name = "Scroll of Fortune", desc = "Up to 2 selected cards become Lucky.",
    select = { min = 1, max = 2 }, use = setEnhancement("LUCKY"),
  },
  STARS = {
    name = "Scroll of the Stars", desc = "Create up to 2 random Tomes.",
    untargeted = true, creates = true, use = createConsumables("tome"),
  },
  FURY = {
    name = "Scroll of Fury", desc = "Up to 2 selected cards become Mult.",
    select = { min = 1, max = 2 }, use = setEnhancement("MULT"),
  },
  KNOWLEDGE = {
    name = "Scroll of Knowledge", desc = "Create up to 2 random Scrolls.",
    untargeted = true, creates = true, use = createConsumables("scroll"),
  },
  BLESSING = {
    name = "Scroll of Blessing", desc = "Up to 2 selected cards become Bonus.",
    select = { min = 1, max = 2 }, use = setEnhancement("BONUS"),
  },
  WILDGROWTH = {
    name = "Scroll of Wildgrowth", desc = "1 selected card becomes Wild.",
    select = { min = 1, max = 1 }, use = setEnhancement("WILD"),
  },
  THORIUM = {
    name = "Scroll of Thorium", desc = "1 selected card becomes Steel.",
    select = { min = 1, max = 1 }, use = setEnhancement("STEEL"),
  },
  CRYSTAL = {
    name = "Scroll of Crystal", desc = "1 selected card becomes Glass.",
    select = { min = 1, max = 1 }, use = setEnhancement("GLASS"),
  },
  GREED = {
    name = "Scroll of Greed", desc = "Double your gold (max +20g).",
    untargeted = true,
    use = function(run, _, api) api.gold(math.max(0, math.min(run.gold, 20))) end,
  },
  CHANCE = {
    name = "Scroll of Chance",
    desc = "1 in 4 chance: a random trinket with no edition gains Foil, Holo or Polychrome.",
    untargeted = true,
    check = function(run)
      if #unedited(run.trinkets) == 0 then return false, "No eligible trinket" end
      return true
    end,
    use = function(_, _, api)
      if ns.RNG.next(api.rng) >= 0.25 then return api.nope() end
      local pool = unedited(api.trinkets())
      if #pool == 0 then return end
      local chosen = ns.RNG.pick(api.rng, pool)
      chosen.ed = ns.CardTypes.rollAura(api.rng)
      api.touch(chosen)
    end,
  },
  STRENGTH = {
    name = "Scroll of Strength", desc = "Raise the rank of up to 2 selected cards by 1 (A wraps to 2).",
    select = { min = 1, max = 2 },
    use = function(_, cards, api)
      for _, card in ipairs(cards) do
        if not ns.Cards.isStone(card) then
          card.rank = card.rank == 14 and 2 or card.rank + 1
          api.changed(card)
        end
      end
    end,
  },
  SACRIFICE = {
    name = "Scroll of Sacrifice", desc = "Destroy up to 2 selected cards.",
    select = { min = 1, max = 2 },
    use = function(_, cards, api)
      for _, card in ipairs(cards) do api.destroy(card) end
    end,
  },
  UNDEATH = {
    name = "Scroll of Undeath", desc = "Select 2 cards: the left becomes a copy of the right.",
    select = { min = 2, max = 2 },
    use = function(_, cards, api)
      local left, right = cards[1], cards[2]
      left.rank, left.suit, left.enh, left.ed, left.seal =
        right.rank, right.suit, right.enh, right.ed, right.seal
      api.changed(left)
    end,
  },
  THRIFT = {
    name = "Scroll of Thrift", desc = "Gain the total sell value of your trinkets (max 50g).",
    untargeted = true,
    use = function(_, _, api)
      local total = 0
      for _, trinket in ipairs(api.trinkets()) do total = total + ns.Shop.sellValue(trinket) end
      api.gold(math.min(total, 50))
    end,
  },
  FEL = {
    name = "Scroll of the Fel", desc = "1 selected card becomes Gold.",
    select = { min = 1, max = 1 }, use = setEnhancement("GOLD"),
  },
  EARTH = {
    name = "Scroll of Earth", desc = "1 selected card becomes Stone.",
    select = { min = 1, max = 1 },
    use = function(_, cards, api)
      local card = cards[1]
      card.enh = "STONE"
      api.changed(card)
    end,
  },
  GEMS = {
    name = "Scroll of Gems", desc = "Up to 3 selected cards become Diamonds.",
    select = { min = 1, max = 3 }, use = setSuit("D"),
  },
  GROVE = {
    name = "Scroll of the Grove", desc = "Up to 3 selected cards become Clubs.",
    select = { min = 1, max = 3 }, use = setSuit("C"),
  },
  LIGHT = {
    name = "Scroll of Light", desc = "Up to 3 selected cards become Hearts.",
    select = { min = 1, max = 3 }, use = setSuit("H"),
  },
  SUMMONING = {
    name = "Scroll of Summoning", desc = "Create a random trinket (needs a free slot).",
    untargeted = true, check = trinketRoom,
    use = function(run, _, api)
      local pool = unownedTrinkets(run, api.trinkets())
      if #pool == 0 or #api.trinkets() >= ns.Run.trinketSlots(run) then return end
      local roll, rarity, acc = ns.RNG.next(api.rng) * 100, "rare", 0
      for _, band in ipairs(TRINKET_WEIGHTS) do
        acc = acc + band[2]
        if roll < acc then rarity = band[1]; break end
      end
      local ofRarity = {}
      for _, id in ipairs(pool) do
        if ns.Trinkets.def[id].rarity == rarity then ofRarity[#ofRarity + 1] = id end
      end
      if #ofRarity == 0 then ofRarity = pool end
      local trinkets = api.trinkets()
      local id = ns.RNG.pick(api.rng, ofRarity)
      local trinket = ns.Trinkets.create(run, id, ns.CardTypes.rollEdition(api.rng, true))
      trinkets[#trinkets + 1] = trinket
      api.touch(trinket)
    end,
  },
  BLADES = {
    name = "Scroll of Blades", desc = "Up to 3 selected cards become Spades.",
    select = { min = 1, max = 3 }, use = setSuit("S"),
  },
}

Scrolls.order = {
  "ECHOES", "FORTUNE", "STARS", "FURY", "KNOWLEDGE", "BLESSING", "WILDGROWTH", "THORIUM",
  "CRYSTAL", "GREED", "CHANCE", "STRENGTH", "SACRIFICE", "UNDEATH", "THRIFT", "FEL",
  "EARTH", "GEMS", "GROVE", "LIGHT", "SUMMONING", "BLADES",
}

local AFFECTS = {
  ECHOES = "Creates a copy of the last Scroll or Tome used",
  FORTUNE = "Up to 2 selected cards -> Lucky",
  STARS = "Creates up to 2 random Tomes (needs free slots)",
  FURY = "Up to 2 selected cards -> Mult",
  KNOWLEDGE = "Creates up to 2 random Scrolls (needs free slots)",
  BLESSING = "Up to 2 selected cards -> Bonus",
  WILDGROWTH = "1 selected card -> Wild",
  THORIUM = "1 selected card -> Steel",
  CRYSTAL = "1 selected card -> Glass",
  GREED = "Gives gold: doubles it (max +20g)",
  CHANCE = "1 random trinket may gain an edition (1 in 4)",
  STRENGTH = "Up to 2 selected cards: rank +1",
  SACRIFICE = "Destroys up to 2 selected cards",
  UNDEATH = "Left selected card becomes a copy of the right",
  THRIFT = "Gives gold (trinket sell value, max 50g)",
  FEL = "1 selected card -> Gold",
  EARTH = "1 selected card -> Stone",
  GEMS = "Up to 3 selected cards -> Diamonds",
  GROVE = "Up to 3 selected cards -> Clubs",
  LIGHT = "Up to 3 selected cards -> Hearts",
  SUMMONING = "Creates a random trinket (needs a free slot)",
  BLADES = "Up to 3 selected cards -> Spades",
}

Scrolls.def = def
for i, id in ipairs(Scrolls.order) do
  local d = def[id]
  d.id = id
  d.affects = AFFECTS[id]
  d.icon = ICON .. ((i - 1) % 8 + 1)
  d.untargeted = d.untargeted or false
  d.creates = d.creates or false
end

ns.Scrolls = Scrolls
