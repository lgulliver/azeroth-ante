local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function uids(run)
  local out = {}
  for i, t in ipairs(run.trinkets) do out[i] = t.uid end
  return out
end

local function kinds(events)
  local out = {}
  for i, e in ipairs(events) do out[i] = e.kind end
  return out
end

H.test("fire_destroy_self_no_skip", function()
  local ran = {}
  H.stub({ id = "S_A", onBlindSelect = function() ran[#ran + 1] = 1; return { destroySelf = true } end })
  H.stub({ id = "S_B", onBlindSelect = function() ran[#ran + 1] = 2 end })
  H.stub({ id = "S_C", onBlindSelect = function() ran[#ran + 1] = 3 end })
  local run = H.run({ trinkets = { "S_A", "S_B", "S_C" } })
  ns.TrinketEngine.fire(run, "onBlindSelect")
  T.eq(ran, { 1, 2, 3 })
  T.eq(uids(run), { 2, 3 })
end)

H.test("fire_destroy_right", function()
  local ran = 0
  H.stub({ id = "S_KILL", onBlindSelect = function(run) return { destroyTrinket = run.trinkets[2].uid } end })
  H.stub({ id = "S_VICTIM", onBlindSelect = function() ran = ran + 1 end })
  local run = H.run({ trinkets = { "S_KILL", "S_VICTIM" } })
  local victim = run.trinkets[2].uid
  local events = ns.TrinketEngine.fire(run, "onBlindSelect")
  T.eq(ran, 0) -- Marked before its turn, so its hook is skipped.
  T.eq(#run.trinkets, 1)
  T.eq(events[1].kind, "trinketDestroyed")
  T.eq(events[1].uid, victim)
  T.eq(run.lifecycleEvents, events)
end)

H.test("fire_copy_no_destroy_self", function()
  local ran = 0
  H.stub({ id = "S_BP", copies = "right" })
  H.stub({ id = "S_DIE", onBlindSelect = function() ran = ran + 1; return { destroySelf = true } end })
  local run = H.run({ trinkets = { "S_BP", "S_DIE" } })
  local events = ns.TrinketEngine.fire(run, "onBlindSelect")
  T.eq(ran, 2)
  T.eq(#events, 1)
  T.eq(run.trinkets[1].id, "S_BP")
  T.eq(#run.trinkets, 1)
end)

H.test("create_trinkets_room", function()
  H.stub({ id = "S_MAKER", onBlindSelect = function() return { createTrinkets = { rarity = "common", n = 2 } } end })
  local run = H.run({ trinkets = { "S_MAKER" } })
  run.maxTrinkets = 2
  local events = ns.TrinketEngine.fire(run, "onBlindSelect")
  T.eq(#run.trinkets, 2)
  T.eq(kinds(events), { "trinketCreated" })
  T.eq(events[1].uid, run.trinkets[2].uid)
  T.eq(ns.Trinkets.def[run.trinkets[2].id].rarity, "common")
end)

H.test("round_passes_order", function()
  local updates = 0
  H.stub({ id = "S_PAY", init = function(self) self.state.pay = 0 end,
    roundUpdate = function(_, self, isCopy)
      if not isCopy then updates = updates + 1; self.state.pay = 9 end
    end,
    onRoundEnd = function(_, self) return self.state.pay end })
  H.stub({ id = "S_BP", copies = "right" })
  local run = H.run({ trinkets = { "S_BP", "S_PAY" } })
  ns.Run.startBlind(run)
  ns.Run.winBlind(run)
  T.eq(updates, 1)
  T.eq(run.lastPayout.trinkets, 18)
end)

H.test("boss_defeated_only_on_boss", function()
  local n = 0
  H.stub({ id = "S_BOSS", onBossDefeated = function() n = n + 1 end })
  local run = H.run({ trinkets = { "S_BOSS" } })
  ns.Run.winBlind(run)
  T.eq(n, 0)
  run.blind = 3
  ns.Run.winBlind(run)
  T.eq(n, 1)
end)

H.test("discard_hook_once_per_action", function()
  local seen, used = {}, {}
  H.stub({ id = "S_DISC", onDiscard = function(run, _, cards)
    seen[#seen + 1] = #cards
    used[#used + 1] = run.discardsUsedRound
  end })
  local run = H.run({ trinkets = { "S_DISC" } })
  ns.Run.startBlind(run)
  local c1, c2 = run.hand[1], run.hand[2]
  ns.Run.discard(run, { 1, 2 })
  T.eq(seen, { 2 })
  T.eq(used, { 0 })
  T.eq(run.discardsUsedRound, 1)
  T.ok(c1 ~= run.hand[1] and c2 ~= run.hand[2])
  ns.Run.startBlind(run)
  T.eq(run.discardsUsedRound, 0)
end)

-- An empty hand and pile below target is the loss path (Run.checkHand -> lose).
local function stuck(run, score)
  ns.Run.startBlind(run)
  run.target, run.score, run.hand, run.pile = 300, score, {}, {}
  ns.Run.checkHand(run)
end

local function bones()
  H.stub({ id = "S_BONES", onLose = function(run)
    if run.score * 4 >= run.target then return { save = true, destroySelf = true } end
  end })
end

H.test("on_lose_save_boundary", function()
  bones()
  local lost = H.run({ trinkets = { "S_BONES" } })
  stuck(lost, 74)
  T.eq(lost.phase, "lost")
  T.eq(#lost.trinkets, 1)
  local run = H.run({ trinkets = { "S_BONES" } })
  local uid = run.trinkets[1].uid
  stuck(run, 75)
  T.eq(run.phase, "shop")
  T.eq(run.lastPayout.reward, 0)
  T.eq(run.lastPayout.saved, uid)
  T.eq(run.savedBy, uid)
  T.eq(#run.trinkets, 0)
  -- A later loss without the trinket is real, and startBlind clears the save.
  ns.Run.nextBlind(run)
  stuck(run, 200)
  T.eq(run.savedBy, nil)
  T.eq(run.phase, "lost")
end)

H.test("on_lose_via_play", function()
  bones()
  local run = H.run({ trinkets = { "S_BONES" } })
  ns.Run.startBlind(run)
  run.target, run.handsLeft, run.score = 300, 1, 70
  run.hand = { H.card(14, "S") }
  run.deck[#run.deck + 1] = run.hand[1]
  ns.Run.play(run, { 1 })
  T.eq(run.phase, "shop")
end)

H.test("titan_idol_roll_in_round_update", function()
  local run = H.run({ trinkets = { "TITAN_RELIC", "ZANDALARI_IDOL" } })
  run.deck = { H.card(3, "H") }
  run.rng = ns.RNG.new(1)
  ns.TrinketEngine.fire(run, "roundUpdate")
  T.eq(run.trinkets[1].state.suit, "S")
  T.eq({ run.trinkets[2].state.rank, run.trinkets[2].state.suit }, { 3, "H" })
end)

H.test("create_records_profile_obtain", function()
  H.stub({ id = "S_MAKER", onBlindSelect = function() return { createTrinkets = { rarity = "common", n = 1 } } end })
  local run = H.run({ trinkets = { "S_MAKER" } })
  local old, got = ns.Profile, {}
  ns.Profile = { onObtain = function(kind, id) got[#got + 1] = { kind, id } end }
  local ok, err = pcall(ns.TrinketEngine.fire, run, "onBlindSelect")
  ns.Profile = old
  if not ok then error(err, 0) end
  T.eq(got, { { "trinket", run.trinkets[2].id } })
end)

H.test("create_after_destroy_in_full_row", function()
  H.stub({ id = "S_K", onBlindSelect = function(run) return { destroyTrinket = run.trinkets[2].uid } end })
  H.stub({ id = "S_V" })
  H.stub({ id = "S_M", onBlindSelect = function() return { createTrinkets = { rarity = "common", n = 1 } } end })
  local run = H.run({ trinkets = { "S_K", "S_V", "S_M" } })
  run.maxTrinkets = 3
  local events = ns.TrinketEngine.fire(run, "onBlindSelect")
  T.eq(#run.trinkets, 3)
  T.eq(kinds(events), { "trinketDestroyed", "trinketCreated" })
  T.eq(events[2].slot, 3)
end)

H.test("pending_destroy_skips_hook", function()
  local ran = {}
  H.stub({ id = "S_D", onBlindSelect = function(run) return { destroyTrinket = run.trinkets[2].uid } end })
  H.stub({ id = "S_X", onBlindSelect = function(run)
    ran[#ran + 1] = "X"; return { destroyTrinket = run.trinkets[3].uid }
  end })
  H.stub({ id = "S_Y", onBlindSelect = function() ran[#ran + 1] = "Y" end })
  local run = H.run({ trinkets = { "S_D", "S_X", "S_Y" } })
  local y = run.trinkets[3].uid
  ns.TrinketEngine.fire(run, "onBlindSelect")
  T.eq(ran, { "Y" })
  T.eq(uids(run), { run.trinkets[1].uid, y })
  T.eq(run.pendingDestroy, nil)
  T.eq(ns.TrinketEngine.isMarked(run, y), false)
end)
