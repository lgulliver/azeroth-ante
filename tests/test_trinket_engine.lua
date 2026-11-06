local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function pairK() return { H.card(13, "S"), H.card(13, "H") } end
local function kinds(events)
  local out = {}
  for i, e in ipairs(events) do out[i] = e.kind end
  return out
end

local function blueprint() H.stub({ id = "STUB_BP", copies = "right" }) end
local function plus4() H.stub({ id = "STUB_P4", onHand = function() return { mult = 4 } end }) end

H.test("score_is_pure", function()
  H.stub({ id = "STUB_SCALE", before = function(_, self) self.state.n = (self.state.n or 0) + 1 end })
  local run = H.run({ trinkets = { "STUB_SCALE" } })
  local cards = pairK()
  local a, b = H.score(run, cards), H.score(run, cards)
  T.eq(a, b)
  T.eq(run.trinkets[1].state.n, nil)
  T.eq(a.trinketsAfter[1].state.n, 1)
end)

H.test("before_level_affects_base", function()
  H.stub({ id = "STUB_LVL", before = function() return { levelHand = true } end })
  local run = H.run({ trinkets = { "STUB_LVL" } })
  local r = H.score(run, pairK())
  T.eq(r.events[1].kind, "base")
  T.eq(r.events[1].chips, 25)
  T.eq(r.events[1].mult, 3)
  T.eq(r.levelUps, { PAIR = 1 })
  T.eq(run.handLevels.PAIR, 1)
end)

H.test("retrigger_replays_card_step", function()
  H.stub({ id = "STUB_RT", retrigger = function() return 1 end })
  local run = H.run({ trinkets = { "STUB_RT" } })
  local r = H.score(run, { H.card(5, "S"), H.card(5, "H") })
  T.eq(r.chips, 10 + 5 * 4)
  local n = 0
  for _, e in ipairs(r.events) do
    if e.kind == "retrigger" then
      n = n + 1
      T.eq(e.slot, 1)
      T.eq(e.uid, run.trinkets[1].uid)
    end
  end
  T.eq(n, 2)
end)

H.test("held_retrigger_mime", function()
  H.stub({ id = "STUB_MIME", heldRetrigger = function() return 1 end })
  local run = H.run({ trinkets = { "STUB_MIME" } })
  local r = H.score(run, pairK(), { H.card(5, "C", "STEEL") })
  T.eq(r.mult, 2 * 1.5 * 1.5)
  T.eq(kinds(r.events), { "base", "card", "card", "held", "retrigger", "held", "total" })
end)

H.test("copy_right", function()
  blueprint() plus4()
  local run = H.run({ trinkets = { "STUB_BP", "STUB_P4" } })
  T.eq(H.score(run, pairK()).mult, 2 + 8)
  run = H.run({ trinkets = { "STUB_BP" } })
  local r = H.score(run, pairK())
  T.eq(r.mult, 2)
  T.eq(kinds(r.events), { "base", "card", "card", "total" })
end)

H.test("copy_leftmost", function()
  H.stub({ id = "STUB_BS", copies = "leftmost" }) plus4()
  local run = H.run({ trinkets = { "STUB_P4", "STUB_BS" } })
  T.eq(H.score(run, pairK()).mult, 2 + 8)
end)

H.test("copy_chain_and_cycle", function()
  blueprint() plus4()
  H.stub({ id = "STUB_BS", copies = "leftmost" })
  local run = H.run({ trinkets = { "STUB_BP", "STUB_BP", "STUB_P4" } })
  T.eq(H.score(run, pairK()).mult, 2 + 12)
  run = H.run({ trinkets = { "STUB_BS", "STUB_BP" } })
  T.eq(H.score(run, pairK()).mult, 2)
  run = H.run({ trinkets = { "STUB_BP", "STUB_BS" } })
  T.eq(H.score(run, pairK()).mult, 2)
  T.eq(ns.TrinketEngine.source(run.trinkets, 1), nil)
  T.eq(ns.TrinketEngine.source({ run.trinkets[2] }, 1), nil)
end)

H.test("copy_noncopyable", function()
  blueprint()
  H.stub({ id = "STUB_NC", copyable = false, onHand = function() return { mult = 4 } end })
  local run = H.run({ trinkets = { "STUB_BP", "STUB_NC" } })
  T.eq(H.score(run, pairK()).mult, 2 + 4)
  local inst, def = ns.TrinketEngine.source(run.trinkets, 2)
  T.eq(inst, run.trinkets[2])
  T.eq(def.id, "STUB_NC")
end)

H.test("copy_state_not_mutated", function()
  blueprint()
  H.stub({ id = "STUB_SCALE",
    before = function(_, self, isCopy)
      if not isCopy then self.state.n = (self.state.n or 0) + 1 end
    end,
    onHand = function(_, self) return { mult = self.state.n } end })
  local run = H.run({ trinkets = { "STUB_BP", "STUB_SCALE" } })
  local r = H.score(run, pairK())
  T.eq(r.trinketsAfter[2].state.n, 1)
  T.eq(r.mult, 2 + 1 + 1)
end)

H.test("baseball_order", function()
  H.stub({ id = "STUB_UNC", rarity = "uncommon", onHand = function() return { mult = 0 } end })
  H.stub({ id = "STUB_BASE", rarity = "rare", otherTrinket = function(_, _, other, isCopy)
    if other.rarity == "uncommon" then return { xmult = 1.5 } end
  end })
  local run = H.run({ trinkets = { "STUB_UNC", "STUB_BASE" } })
  run.trinkets[1].ed = "POLY"
  local r = H.score(run, pairK())
  T.eq(kinds(r.events), { "base", "card", "card", "trinket", "trinket", "edition", "total" })
  T.eq(r.events[4].slot, 1)
  T.eq(r.events[5].slot, 2)
  T.eq(r.events[5].xmult, 1.5)
  T.eq(r.events[6].xmult, 1.5)
  T.eq(r.mult, 2 * 1.5 * 1.5)
end)

H.test("destroy_self_after", function()
  H.stub({ id = "STUB_MELT", after = function(_, _, isCopy) return { destroySelf = true } end })
  blueprint()
  local run = H.run({ trinkets = { "STUB_BP", "STUB_MELT" } })
  local r = H.score(run, pairK())
  T.eq(#r.trinketsAfter, 1)
  T.eq(r.trinketsAfter[1].id, "STUB_BP")
  T.eq(r.destroyedTrinkets, { run.trinkets[2].uid })
  local last = r.events[#r.events]
  T.eq(last.kind, "trinketDestroyed")
  T.eq(last.uid, run.trinkets[2].uid)
  T.eq(kinds(r.events)[4], "total")
  T.eq(#run.trinkets, 2)
end)

H.test("events_carry_uid", function()
  plus4()
  H.stub({ id = "STUB_MSG", onHand = function() return { msg = "hi" } end })
  local run = H.run({ trinkets = { "STUB_P4", "STUB_MSG" } })
  run.trinkets[1].ed = "FOIL"
  local r = H.score(run, pairK())
  local seen = 0
  for _, e in ipairs(r.events) do
    if e.kind == "trinket" or e.kind == "trinketMsg" or (e.kind == "edition" and e.slot) then
      seen = seen + 1
      T.eq(e.uid, run.trinkets[e.slot].uid)
    end
  end
  T.eq(seen, 3)
end)

H.test("round_end_lines", function()
  H.stub({ id = "STUB_HEARTH", onRoundEnd = function() return 4 end })
  H.stub({ id = "STUB_ZERO", onRoundEnd = function() return 0 end })
  blueprint()
  local run = H.run({ trinkets = { "STUB_BP", "STUB_HEARTH", "STUB_ZERO" } })
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.trinketLines, {
    { uid = run.trinkets[1].uid, id = "STUB_BP", gold = 4 },
    { uid = run.trinkets[2].uid, id = "STUB_HEARTH", gold = 4 },
  })
  T.eq(run.lastPayout.trinkets, 8)
end)

H.test("card_sharp_round_counter", function()
  local run = H.run()
  ns.Run.startBlind(run)
  run.target = 1000000
  T.eq(run.roundHandPlays, {})
  local seen
  H.stub({ id = "STUB_SEE", onHand = function(ctx) seen = { ctx.roundHandPlays[ctx.handId], ctx.handPlays[ctx.handId] } end })
  run.trinkets[1] = ns.Trinkets.create(run, "STUB_SEE")
  local r = ns.Run.play(run, { 1 })
  T.eq(seen, { nil, nil })
  T.eq(run.roundHandPlays[r.handId], 1)
  ns.Run.play(run, { 1 })
  T.eq(seen, { 1, 1 })
  T.eq(run.roundHandPlays[r.handId], 2)
  ns.Run.startBlind(run)
  T.eq(run.roundHandPlays, {})
end)

H.test("play_commits_trinkets_and_levels", function()
  H.stub({ id = "STUB_GROW", before = function(_, self) self.state.n = (self.state.n or 0) + 1
    return { levelHand = true } end })
  local run = H.run({ trinkets = { "STUB_GROW" } })
  run.hand = { H.card(13, "S"), H.card(2, "H") }
  run.target = 1000000
  local r = ns.Run.play(run, { 1 })
  T.eq(run.trinkets[1].state.n, 1)
  T.eq(run.handLevels[r.handId], 2)
end)
