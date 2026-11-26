local ns, T = ...

T.test("stage_8_draws_a_finisher", function()
  local seen = {}
  for seed = 1, 200 do
    local run = ns.Run.new(seed, "ADVENTURER")
    T.ok(ns.Bosses.isFinal(run.bosses[8]), "seed " .. seed .. " stage 8 is a finisher")
    seen[run.bosses[8]] = true
  end
  for _, id in ipairs(ns.Bosses.FINALS) do T.ok(seen[id], id .. " never drawn") end
end)

T.test("finishers_never_before_stage_8", function()
  for seed = 1, 200 do
    local run = ns.Run.new(seed, "ADVENTURER")
    for stage = 1, 7 do
      T.ok(not ns.Bosses.isFinal(run.bosses[stage]), "seed " .. seed .. " stage " .. stage)
    end
  end
end)

T.test("finisher_reroll_stays_final", function()
  local run = ns.Run.new(3, "ADVENTURER")
  run.stage, run.blind, run.phase, run.gold = 8, 3, "blind", 100
  run.vouchers.DIRECTORS_CUT = true
  local old = run.bosses[8]
  local ok, id = ns.Run.rerollBoss(run)
  T.ok(ok, "reroll succeeds")
  T.ok(ns.Bosses.isFinal(id), "still a finisher")
  T.ok(id ~= old, "a different finisher")
  T.eq(run.bosses[8], id)
end)

T.test("finisher_pays_8", function()
  local run = ns.Run.new(3, "ADVENTURER")
  run.stage, run.blind, run.phase = 8, 3, "play"
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.reward, 8)
end)

T.test("regular_blinds_pay_3_4_5", function()
  for blind, want in ipairs({ 3, 4, 5 }) do
    local run = ns.Run.new(3, "ADVENTURER")
    run.stage, run.blind = 2, blind
    T.eq(ns.Run.blindReward(run), want)
  end
end)

T.test("cthun_target_is_6x", function()
  T.eq(ns.Run.target(8, 3, "CTHUN"), 300000)
end)

T.test("finisher_defs", function()
  T.eq(ns.Bosses.FINALS[1], "RAGNAROS")
  for _, id in ipairs(ns.Bosses.FINALS) do
    local def = ns.Bosses.def[id]
    T.ok(def and def.name and def.desc, id)
    T.ok(not ns.Bosses.isFinal(ns.Bosses.pool[1]))
  end
end)
