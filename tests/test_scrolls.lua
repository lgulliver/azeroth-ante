local ns, T = ...

local function newRun()
  local run = ns.Run.new(7, "ADVENTURER")
  run.phase = "shop"
  return run
end

-- Applies a scroll to cards taken from the deck by id.
local function apply(run, id, cards)
  local item = { kind = "scroll", id = id }
  local ok, reason = ns.Consumables.canApply(run, item, cards)
  T.ok(ok, id .. ": " .. tostring(reason))
  return ns.Consumables.apply(run, item, cards)
end

local function cardAt(run, i) return run.deck[i] end

local function enhancement(scrollId, enh, count)
  return function()
    local run = newRun()
    local cards = {}
    for i = 1, count do cards[i] = cardAt(run, i) end
    local outcome = apply(run, scrollId, cards)
    for i = 1, count do
      T.eq(cards[i].enh, enh)
      T.eq(cards[i].rank, i + 1, "rank untouched")
    end
    T.eq(#outcome.changed, count)
  end
end

T.test("fortune_lucky", enhancement("FORTUNE", "LUCKY", 2))
T.test("fury_mult", enhancement("FURY", "MULT", 2))
T.test("blessing_bonus", enhancement("BLESSING", "BONUS", 2))
T.test("wildgrowth_wild", enhancement("WILDGROWTH", "WILD", 1))
T.test("thorium_steel", enhancement("THORIUM", "STEEL", 1))
T.test("crystal_glass", enhancement("CRYSTAL", "GLASS", 1))
T.test("fel_gold", enhancement("FEL", "GOLD", 1))

T.test("enhancement_replaces_and_keeps_seal_edition", function()
  local run = newRun()
  local card = cardAt(run, 1)
  card.enh, card.ed, card.seal = "BONUS", "FOIL", "RED"
  apply(run, "FURY", { card })
  T.eq(card.enh, "MULT")
  T.eq(card.ed, "FOIL")
  T.eq(card.seal, "RED")
end)

T.test("stone_rejected_by_enhancers", function()
  local run = newRun()
  local card = cardAt(run, 1)
  apply(run, "EARTH", { card })
  local ok, reason = ns.Consumables.canApply(run, { kind = "scroll", id = "FORTUNE" }, { card })
  T.ok(not ok)
  T.eq(reason, "Stone cards cannot be changed")
  ok = ns.Consumables.canApply(run, { kind = "scroll", id = "BLADES" }, { card })
  T.ok(not ok)
  T.ok(ns.Consumables.canApply(run, { kind = "scroll", id = "STRENGTH" }, { card }))
  T.ok(ns.Consumables.canApply(run, { kind = "scroll", id = "SACRIFICE" }, { card }))
end)

local function suitScroll(scrollId, suit)
  return function()
    local run = newRun()
    local cards = { cardAt(run, 1), cardAt(run, 2), cardAt(run, 3) }
    cards[1].enh = "WILD"
    apply(run, scrollId, cards)
    for _, card in ipairs(cards) do T.eq(card.suit, suit) end
    T.eq(cards[1].enh, "WILD")
    T.eq(cards[2].rank, 3)
    local ok = ns.Consumables.canApply(run, { kind = "scroll", id = scrollId },
      { cardAt(run, 1), cardAt(run, 2), cardAt(run, 3), cardAt(run, 4) })
    T.ok(not ok, "max 3")
  end
end

T.test("gems_diamonds", suitScroll("GEMS", "D"))
T.test("grove_clubs", suitScroll("GROVE", "C"))
T.test("light_hearts", suitScroll("LIGHT", "H"))
T.test("blades_spades", suitScroll("BLADES", "S"))

T.test("greed_doubles", function()
  local run = newRun()
  run.gold = 12
  local outcome = apply(run, "GREED", {})
  T.eq(run.gold, 24)
  T.eq(outcome.gold, 12)
end)

T.test("greed_caps_20", function()
  local run = newRun()
  run.gold = 30
  apply(run, "GREED", {})
  T.eq(run.gold, 50)
  run.gold = 0
  apply(run, "GREED", {})
  T.eq(run.gold, 0)
end)

T.test("thrift_sums_sell_values", function()
  local run = newRun()
  run.trinkets = { { id = "ARCANE_INTELLECT" }, { id = "BLOODLUST", ed = "POLY" } }
  run.gold = 0
  apply(run, "THRIFT", {})
  T.eq(run.gold, 2 + 6) -- floor(4/2) + floor((8+5)/2)
end)

T.test("thrift_caps_50", function()
  local run = newRun()
  run.maxTrinkets = 5
  run.trinkets = {}
  for i = 1, 5 do run.trinkets[i] = { id = "BLOODLUST", ed = "NEGATIVE" } end
  -- Raise the base cost so the total goes over the cap.
  ns.Trinkets.def.BLOODLUST.cost = 40
  local ok, err = pcall(apply, run, "THRIFT", {})
  ns.Trinkets.def.BLOODLUST.cost = 8
  if not ok then error(err, 0) end
  T.eq(run.gold, 4 + 50)
end)

T.test("chance_one_in_four", function()
  local hits, misses = 0, 0
  for seed = 1, 200 do
    local run = newRun()
    run.rng = ns.RNG.new(seed * 10007919)
    run.trinkets = { { id = "BLOODLUST" }, { id = "FORTITUDE", ed = "FOIL" } }
    apply(run, "CHANCE", {})
    T.eq(run.trinkets[2].ed, "FOIL", "edition untouched")
    if run.trinkets[1].ed then
      hits = hits + 1
      T.ok(run.trinkets[1].ed == "FOIL" or run.trinkets[1].ed == "HOLO" or run.trinkets[1].ed == "POLY")
    else
      misses = misses + 1
    end
  end
  T.ok(hits > 25 and hits < 75, "about 1 in 4, got " .. hits)
  T.ok(misses > 0)
end)

T.test("strength_raises_rank", function()
  local run = newRun()
  local a, b = cardAt(run, 1), cardAt(run, 10)
  local outcome = apply(run, "STRENGTH", { a, b })
  T.eq(a.rank, 3)
  T.eq(b.rank, 12)
  T.eq(#outcome.changed, 2)
end)

T.test("strength_ace_wraps", function()
  local run = newRun()
  local ace = cardAt(run, 13)
  T.eq(ace.rank, 14)
  apply(run, "STRENGTH", { ace })
  T.eq(ace.rank, 2)
end)

T.test("strength_stone_unaffected", function()
  local run = newRun()
  local card = cardAt(run, 1)
  apply(run, "EARTH", { card })
  local outcome = apply(run, "STRENGTH", { card })
  T.eq(card.rank, nil)
  T.eq(card.enh, "STONE")
  T.eq(outcome.changed, {})
end)

T.test("earth_makes_stone", function()
  local run = newRun()
  local card = cardAt(run, 5)
  card.seal = "RED"
  apply(run, "EARTH", { card })
  T.eq(card.enh, "STONE")
  T.eq(card.rank, nil)
  T.eq(card.suit, nil)
  T.eq(card.seal, "RED")
end)

T.test("sacrifice_destroys_two", function()
  local run = newRun()
  run.phase = "play"
  ns.Run.startBlind(run)
  local a, b = run.hand[1], run.hand[2]
  local outcome = apply(run, "SACRIFICE", { a, b })
  T.eq(#run.deck, 50)
  T.eq(ns.Deck.find(run, a.id), nil)
  T.eq(ns.Deck.find(run, b.id), nil)
  T.eq(#run.hand, 6)
  T.eq(outcome.destroyed, { a.id, b.id })
end)

T.test("sacrifice_removes_from_pack_hand", function()
  local run = newRun()
  local cards = { run.deck[1], run.deck[2], run.deck[3] }
  run.shop = { openPack = { hand = { cards[1], cards[2], cards[3] } } }
  apply(run, "SACRIFICE", { cards[2] })
  T.eq(#run.shop.openPack.hand, 2)
  T.eq(#run.deck, 51)
end)

T.test("undeath_left_copies_right", function()
  local run = newRun()
  local left, right = cardAt(run, 1), cardAt(run, 20)
  left.seal = "BLUE"
  right.enh, right.ed, right.seal = "GLASS", "HOLO", "RED"
  local leftId, rightId = left.id, right.id
  local outcome = apply(run, "UNDEATH", { left, right })
  T.eq(left.id, leftId)
  T.eq(right.id, rightId)
  T.eq(left.rank, right.rank)
  T.eq(left.suit, right.suit)
  T.eq(left.enh, "GLASS")
  T.eq(left.ed, "HOLO")
  T.eq(left.seal, "RED")
  T.eq(#run.deck, 52)
  T.eq(outcome.changed, { leftId })
end)

T.test("undeath_clears_plain_right", function()
  local run = newRun()
  local left, right = cardAt(run, 1), cardAt(run, 2)
  left.enh, left.ed, left.seal = "BONUS", "FOIL", "GOLD"
  apply(run, "UNDEATH", { left, right })
  T.eq(left.enh, nil)
  T.eq(left.ed, nil)
  T.eq(left.seal, nil)
  T.eq(left.rank, 3)
end)

T.test("undeath_orders_by_hand_position", function()
  local run = newRun()
  run.phase = "play"
  ns.Run.startBlind(run)
  run.consumables = { { kind = "scroll", id = "UNDEATH" } }
  local first, second = run.hand[1], run.hand[3]
  second.enh = "STEEL"
  ns.Consumables.use(run, 1, { 3, 1 })
  T.eq(first.enh, "STEEL")
  T.eq(first.rank, second.rank)
end)

T.test("stars_creates_tomes", function()
  local run = newRun()
  run.maxConsumables = 5
  local outcome = apply(run, "STARS", {})
  T.eq(#outcome.created, 2)
  for _, item in ipairs(outcome.created) do
    T.eq(item.kind, "tome")
    T.ok(ns.Tomes.def[item.id])
  end
  T.eq(#run.consumables, 2)
end)

T.test("knowledge_creates_scrolls", function()
  local run = newRun()
  run.maxConsumables = 5
  local outcome = apply(run, "KNOWLEDGE", {})
  T.eq(#outcome.created, 2)
  for _, item in ipairs(outcome.created) do
    T.eq(item.kind, "scroll")
    T.ok(ns.Scrolls.def[item.id])
  end
end)

T.test("summoning_adds_trinket", function()
  local run = newRun()
  apply(run, "SUMMONING", {})
  T.eq(#run.trinkets, 1)
  T.ok(ns.Trinkets.def[run.trinkets[1].id])
  T.eq(run.trinkets[1].ed, nil)
  run.trinkets = {}
  for i = 1, 5 do run.trinkets[i] = { id = ns.Trinkets.order[i] } end
  local ok = ns.Consumables.canApply(run, { kind = "scroll", id = "SUMMONING" }, {})
  T.ok(not ok)
  run.trinkets[5].ed = "NEGATIVE"
  apply(run, "SUMMONING", {})
  T.eq(#run.trinkets, 6)
  local seen = {}
  for _, trinket in ipairs(run.trinkets) do
    T.ok(not seen[trinket.id], "no duplicate trinket")
    seen[trinket.id] = true
  end
end)

T.test("echoes_does_not_set_last", function()
  local run = newRun()
  run.lastConsumable = { kind = "scroll", id = "GREED" }
  apply(run, "ECHOES", {})
  T.eq(run.lastConsumable, { kind = "scroll", id = "GREED" })
  apply(run, "GREED", {})
  T.eq(run.lastConsumable, { kind = "scroll", id = "GREED" })
  apply(run, "THRIFT", {})
  T.eq(run.lastConsumable, { kind = "scroll", id = "THRIFT" })
end)
