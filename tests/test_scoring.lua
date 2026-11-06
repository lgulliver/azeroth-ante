local ns, T = ...

local function card(rank, suit)
  return { rank = rank, suit = suit or "S", id = rank }
end

ns.Trinkets = ns.Trinkets or { def = {} }
ns.Bosses = ns.Bosses or { def = {} }

local stubTrinkets, stubBosses = {}, {}

local function stubTrinket(id, def)
  ns.Trinkets.def[id] = def
  stubTrinkets[#stubTrinkets + 1] = id
end

local function stubBoss(id, def)
  ns.Bosses.def[id] = def
  stubBosses[#stubBosses + 1] = id
end

local function cleanup()
  for _, id in ipairs(stubTrinkets) do ns.Trinkets.def[id] = nil end
  for _, id in ipairs(stubBosses) do ns.Bosses.def[id] = nil end
  stubTrinkets, stubBosses = {}, {}
end

local function test(name, fn)
  T.test(name, function()
    local ok, err = pcall(fn)
    cleanup()
    if not ok then error(err, 0) end
  end)
end

local function ctx(cards, extra)
  local c = { cards = cards, handLevels = {}, trinkets = {}, handsPlayedTotal = 1,
    isLastHand = false, discardsLeft = 0, gold = 0 }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function kinds(events)
  local out = {}
  for i, e in ipairs(events) do out[i] = e.kind end
  return out
end

test("pair_of_kings_level1", function()
  local r = ns.Scoring.score(ctx({ card(13, "S"), card(13, "H") }))
  T.eq(r.handId, "PAIR")
  T.eq(r.chips, 30)
  T.eq(r.mult, 2)
  T.eq(r.total, 60)
  T.eq(kinds(r.events), { "base", "card", "card", "total" })
  T.eq(r.events[1].chips, 10)
  T.eq(r.events[2].chips, 10)
  T.eq(r.events[2].index, 1)
end)

test("missing_level_means_level_1_and_levels_apply", function()
  local r = ns.Scoring.score(ctx({ card(13, "S"), card(13, "H") }, { handLevels = { PAIR = 2 } }))
  T.eq(r.events[1].chips, 25)
  T.eq(r.events[1].mult, 3)
  T.eq(r.total, (25 + 20) * 3)
end)

test("debuffed_card_scores_nothing", function()
  stubBoss("STUB_BOSS", { debuff = function(c) return c.suit == "S" end })
  local r = ns.Scoring.score(ctx({ card(13, "S"), card(13, "H") }, { bossId = "STUB_BOSS" }))
  T.eq(r.chips, 20)
  T.eq(r.events[2].kind, "debuff")
  T.eq(r.events[2].index, 1)
  T.eq(r.events[3].kind, "card")
end)

test("debuffed_card_triggers_no_oncard", function()
  stubBoss("STUB_BOSS", { debuff = function(c) return c.suit == "S" end })
  stubTrinket("STUB_A", { onCard = function() return { mult = 1 } end })
  local r = ns.Scoring.score(ctx({ card(13, "S"), card(13, "H") },
    { bossId = "STUB_BOSS", trinkets = { { id = "STUB_A" } } }))
  T.eq(r.mult, 3)
  T.eq(kinds(r.events), { "base", "debuff", "card", "trinket", "total" })
end)

test("halve_base", function()
  stubBoss("STUB_HALVE", { halveBase = true })
  local r = ns.Scoring.score(ctx({ card(13, "S"), card(13, "H") }, { bossId = "STUB_HALVE" }))
  T.eq(r.events[1].chips, 5)
  T.eq(r.events[1].mult, 1)
  T.eq(r.total, (5 + 20) * 1)
end)

test("trinket_order", function()
  stubTrinket("STUB_A", { onHand = function() return { mult = 4 } end })
  stubTrinket("STUB_B", { onHand = function() return { xmult = 2 } end })
  local cards = { card(13, "S"), card(13, "H") }
  local r = ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_A" }, { id = "STUB_B" } } }))
  T.eq(r.mult, 12)
  T.eq(r.total, 30 * 12)
  T.eq(r.events[4].slot, 1)
  T.eq(r.events[5].slot, 2)
  r = ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_B" }, { id = "STUB_A" } } }))
  T.eq(r.mult, 8)
end)

test("oncard_per_scoring_card_only", function()
  stubTrinket("STUB_A", { onCard = function() return { mult = 1 } end })
  local cards = { card(13, "S"), card(13, "H"), card(2, "C"), card(5, "D"), card(9, "S") }
  local r = ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_A" } } }))
  T.eq(r.mult, 4)
  T.eq(r.events[3].kind, "trinket")
  T.eq(r.events[3].index, 1)
  T.eq(r.events[3].mult, 1)
end)

test("context_passed_to_hooks", function()
  local seen
  stubTrinket("STUB_A", { onHand = function(c) seen = c; return nil end })
  local cards = { card(13, "S"), card(13, "H") }
  ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_A" } }, isLastHand = true }))
  T.ok(seen.contains.PAIR)
  T.eq(seen.isLastHand, true)
end)

test("events_carry_running_totals", function()
  stubTrinket("STUB_A", { onCard = function() return { chips = 3, mult = 1, xmult = 1.5 } end })
  stubTrinket("STUB_B", { onHand = function() return { xmult = 2 } end })
  local cards = { card(13, "S"), card(13, "H"), card(2, "C") }
  local r = ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_A" }, { id = "STUB_B" } } }))
  for _, e in ipairs(r.events) do
    T.ok(e.runChips ~= nil and e.runMult ~= nil, "running totals on " .. e.kind)
  end
  local last = r.events[#r.events]
  T.eq(last.kind, "total")
  T.eq(math.floor(last.runChips * last.runMult), r.total)
  T.eq(last.total, r.total)
end)

-- v2: enhancements, editions and seals.
local function ecard(id, rank, suit, extra)
  local c = { id = id, rank = rank, suit = suit }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- Finds a seed whose first rolls satisfy check(rolls).
local function findSeed(n, check)
  for i = 1, 20000 do
    local seed = i * 104729
    local r = ns.RNG.new(seed)
    local rolls = {}
    for i = 1, n do rolls[i] = ns.RNG.next(r) end
    if check(rolls) then return seed end
  end
  error("no seed found")
end

local function eventsOf(r, kind)
  local out = {}
  for _, e in ipairs(r.events) do if e.kind == kind then out[#out + 1] = e end end
  return out
end

test("bonus_mult_stone", function()
  local cards = { ecard(1, 13, "S", { enh = "BONUS" }), ecard(2, 13, "H"), ecard(3, nil, nil, { enh = "STONE" }) }
  local r = ns.Scoring.score(ctx(cards, { rng = ns.RNG.new(1) }))
  T.eq(r.handId, "PAIR")
  T.eq(r.chips, 110)
  T.eq(r.mult, 2)
  T.eq(eventsOf(r, "enh")[1].chips, 30)
  T.eq(eventsOf(r, "enh")[2].chips, 50)
  r = ns.Scoring.score(ctx({ ecard(1, 13, "S", { enh = "MULT" }), ecard(2, 13, "H") }))
  T.eq(r.mult, 6)
end)

test("glass_x2_and_break", function()
  local brk = findSeed(1, function(x) return x[1] < 0.25 end)
  local keep = findSeed(1, function(x) return x[1] >= 0.25 end)
  local cards = { ecard(11, 13, "S", { enh = "GLASS" }), ecard(12, 13, "H") }
  local r = ns.Scoring.score(ctx(cards, { rng = ns.RNG.new(brk) }))
  T.eq(r.mult, 4)
  T.eq(r.total, 30 * 4)
  T.eq(r.destroyed, { 11 })
  T.eq(r.events[#r.events].kind, "destroy")
  T.eq(r.events[#r.events].index, 1)
  T.eq(r.events[#r.events - 1].kind, "total")
  r = ns.Scoring.score(ctx(cards, { rng = ns.RNG.new(keep) }))
  T.eq(r.destroyed, {})
  T.eq(r.events[#r.events].kind, "total")
end)

test("steel_held", function()
  local played = { ecard(1, 13, "S"), ecard(2, 13, "H") }
  local r = ns.Scoring.score(ctx(played, { held = { ecard(3, 5, "C", { enh = "STEEL" }) } }))
  T.eq(r.mult, 3)
  T.eq(r.total, 30 * 3)
  T.eq(eventsOf(r, "held")[1].heldIndex, 1)
  r = ns.Scoring.score(ctx(played, { held = { ecard(3, 5, "C", { enh = "STEEL", seal = "RED" }) } }))
  T.eq(r.mult, 4.5)
  T.eq(#eventsOf(r, "held"), 2)
  T.eq(eventsOf(r, "retrigger")[1].heldIndex, 1)
end)

test("red_seal_retrigger", function()
  local r = ns.Scoring.score(ctx({ ecard(1, 13, "S", { seal = "RED" }), ecard(2, 13, "H") }))
  T.eq(r.chips, 10 + 10 + 10 + 10)
  T.eq(kinds(r.events), { "base", "card", "retrigger", "card", "card", "total" })
  T.eq(r.events[3].index, 1)
end)

test("editions_card", function()
  local cards = { ecard(1, 13, "S", { enh = "MULT", ed = "FOIL" }), ecard(2, 13, "H", { ed = "HOLO" }),
    ecard(3, 2, "C", { ed = "POLY" }) }
  local r = ns.Scoring.score(ctx({ cards[1], cards[2] }))
  T.eq(r.chips, 10 + 10 + 10 + 50)
  T.eq(r.mult, 2 + 4 + 10)
  T.eq(kinds(r.events), { "base", "card", "enh", "edition", "card", "edition", "total" })
  r = ns.Scoring.score(ctx({ ecard(1, 13, "S", { enh = "MULT", ed = "POLY" }), ecard(2, 13, "H") }))
  T.eq(r.mult, (2 + 4) * 1.5)
  T.eq(kinds(r.events), { "base", "card", "enh", "edition", "card", "total" })
  T.eq(r.events[4].xmult, 1.5)
  T.eq(r.events[4].index, 1)
end)

test("trinket_poly_after_effect", function()
  stubTrinket("STUB_A", { onHand = function() return { mult = 4 } end })
  local cards = { card(13, "S"), card(13, "H") }
  local r = ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_A", ed = "POLY" } } }))
  T.eq(r.mult, 9)
  T.eq(kinds(r.events), { "base", "card", "card", "trinket", "edition", "total" })
  T.eq(r.events[5].slot, 1)
  r = ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_A", ed = "FOIL" } } }))
  T.eq(r.chips, 80)
  T.eq(kinds(r.events), { "base", "card", "card", "edition", "trinket", "total" })
  r = ns.Scoring.score(ctx(cards, { trinkets = { { id = "STUB_A", ed = "HOLO" } } }))
  T.eq(r.mult, 16)
end)

test("lucky_gold_visible_to_goblin_bank", function()
  local seed = findSeed(2, function(x) return x[1] < 0.2 and x[2] < 1 / 15 end)
  local cards = { ecard(1, 13, "S", { enh = "LUCKY" }), ecard(2, 13, "H") }
  local goldRef = { gold = 0 }
  local r = ns.Scoring.score(ctx(cards, { rng = ns.RNG.new(seed), goldRef = goldRef,
    trinkets = { { id = "GOBLIN_BANK" } } }))
  T.eq(r.gold, 20)
  T.eq(goldRef.gold, 20)
  T.eq(eventsOf(r, "money")[1].gold, 20)
  T.eq(r.mult, 2 + 20 + 8) -- Spec row 145: +2 Mult per 5g.
  local miss = findSeed(2, function(x) return x[1] >= 0.2 and x[2] >= 1 / 15 end)
  r = ns.Scoring.score(ctx(cards, { rng = ns.RNG.new(miss) }))
  T.eq(r.mult, 2)
  T.eq(r.gold, 0)
end)

test("gold_seal_pays", function()
  local r = ns.Scoring.score(ctx({ ecard(1, 13, "S", { seal = "GOLD" }), ecard(2, 13, "H") }))
  T.eq(r.gold, 3)
  T.eq(eventsOf(r, "seal")[1].gold, 3)
end)

test("debuffed_loses_all", function()
  stubBoss("STUB_BOSS", { debuff = function(c) return c.suit == "S" end })
  local cards = { ecard(1, 13, "S", { enh = "GLASS", seal = "RED", ed = "FOIL" }), ecard(2, 13, "H") }
  local r = ns.Scoring.score(ctx(cards, { bossId = "STUB_BOSS", rng = ns.RNG.new(1) }))
  T.eq(kinds(r.events), { "base", "debuff", "card", "total" })
  T.eq(r.destroyed, {})
end)

test("wild_matches_suit_trinket_and_boss", function()
  local wild = ecard(1, 13, "H", { enh = "WILD" })
  local stone = ecard(3, nil, nil, { enh = "STONE" })
  local r = ns.Scoring.score(ctx({ wild, ecard(2, 13, "D") }, { trinkets = { { id = "WHETSTONE" } } }))
  T.eq(r.mult, 5)
  r = ns.Scoring.score(ctx({ stone, ecard(2, 13, "D"), ecard(4, 13, "C") }, { trinkets = { { id = "WHETSTONE" } } }))
  T.eq(r.mult, 2)
  T.ok(ns.Bosses.def.VANCLEEF.debuff(wild))
  T.ok(not ns.Bosses.def.VANCLEEF.debuff(stone))
  T.ok(ns.Bosses.def.ARUGAL.debuff(wild))
end)

test("rolls_and_card_types", function()
  T.eq(ns.CardTypes.rollEdition({ s = 1 }, true), "NEGATIVE")
  T.eq(ns.CardTypes.rollEdition({ s = 1 }, false), "POLY")
  local seen = {}
  local r = ns.RNG.new(5)
  for _ = 1, 3000 do seen[ns.CardTypes.rollEdition(r, false) or "none"] = true end
  T.ok(seen.FOIL and seen.HOLO and seen.none and not seen.NEGATIVE)
  local aura = {}
  for _ = 1, 200 do aura[ns.CardTypes.rollAura(r)] = true end
  T.ok(aura.FOIL and aura.HOLO and aura.POLY)
  T.eq(ns.CardTypes.enh.GLASS.name, "Glass")
end)
