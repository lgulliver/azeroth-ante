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
