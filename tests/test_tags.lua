local ns, T = ...

T.test("tags_defs_complete", function()
  T.eq(#ns.Tags.order, 24)
  for _, id in ipairs(ns.Tags.order) do
    local def = ns.Tags.def[id]
    T.ok(def and def.id == id, id .. " def")
    T.ok(type(def.name) == "string" and type(def.desc) == "string" and type(def.icon) == "string", id .. " fields")
    T.ok(def.minStage == 1 or def.minStage == 2, id .. " minStage")
  end
end)

T.test("blind_tags_rolled_per_ante", function()
  local sawLate = false
  for seed = 1, 200 do
    local run = ns.Run.new(seed, "ADVENTURER")
    T.eq(run.tags, {})
    T.eq(run.skips, 0)
    T.ok(run.blindTags[1] and run.blindTags[2] and run.blindTags[3] == nil, "seed " .. seed .. " two tags")
    for i = 1, 2 do
      T.eq(ns.Tags.def[run.blindTags[i]].minStage, 1, "seed " .. seed .. " stage-1 tag")
    end
    run.phase, run.blind = "shop", 3
    ns.Run.nextBlind(run)
    T.eq(run.stage, 2)
    for i = 1, 2 do
      T.ok(ns.Tags.def[run.blindTags[i]], "seed " .. seed .. " stage-2 tag")
      if ns.Tags.def[run.blindTags[i]].minStage == 2 then sawLate = true end
    end
  end
  T.ok(sawLate, "stage 2 rolls minStage 2 tags")
end)

T.test("blind_tags_not_rerolled_within_ante", function()
  local run = ns.Run.new(5, "ADVENTURER")
  local tags = { run.blindTags[1], run.blindTags[2] }
  run.phase = "shop"
  ns.Run.nextBlind(run)
  T.eq(run.blindTags, tags)
end)

T.test("skip_small_then_big", function()
  local run = ns.Run.new(11, "ADVENTURER")
  local gold, small, big = run.gold, run.blindTags[1], run.blindTags[2]
  T.eq(ns.Run.skipBlind(run), small)
  T.eq({ run.blind, run.phase, run.skips }, { 2, "blind", 1 })
  T.eq(ns.Run.skipBlind(run), big)
  T.eq({ run.blind, run.phase, run.skips, run.stage }, { 3, "blind", 2, 1 })
  T.eq(run.gold, gold)
  T.eq(run.tags, { small, big })
  T.eq(run.lastPayout, nil)
end)

T.test("boss_cannot_be_skipped", function()
  local run = ns.Run.new(11, "ADVENTURER")
  run.blind = 3
  local ok, reason = ns.Run.canSkip(run)
  T.ok(not ok and type(reason) == "string", "boss refuses")
  T.eq(ns.Run.skipBlind(run), nil)
  T.eq({ run.blind, run.skips, #run.tags }, { 3, 0, 0 })
  run.blind = 1
  ns.Run.startBlind(run)
  T.ok(not ns.Run.canSkip(run), "no skip while playing")
  T.eq(ns.Run.skipBlind(run), nil)
end)

T.test("skip_fires_on_skip_and_counts", function()
  local run = ns.Run.new(11, "ADVENTURER")
  local fired, events = {}, {}
  local fire, onEvent = ns.TrinketEngine.fire, ns.Profile.onEvent
  ns.TrinketEngine.fire = function(r, hook, ...)
    fired[#fired + 1] = hook
    return fire(r, hook, ...)
  end
  ns.Profile.onEvent = function(name, amount) events[#events + 1] = { name, amount } end
  local ok, err = pcall(ns.Run.skipBlind, run)
  ns.TrinketEngine.fire, ns.Profile.onEvent = fire, onEvent
  T.ok(ok, tostring(err))
  T.eq(fired, { "onSkip" })
  T.eq(events, { { "blindSkipped", 1 } })
end)

T.test("tags_add_and_fire_consume", function()
  ns.Tags.def.TEST_TAKE = { id = "TEST_TAKE", onTake = function() return true end }
  ns.Tags.def.TEST_HOOK = { id = "TEST_HOOK", onShopOpen = function(_, n) return n == 1 end }
  local run = ns.Run.new(3, "ADVENTURER")
  ns.Tags.add(run, "TEST_TAKE")
  T.eq(run.tags, {})
  ns.Tags.add(run, "TEST_HOOK")
  ns.Tags.add(run, "RARE")
  ns.Tags.add(run, "TEST_HOOK")
  ns.Tags.fire(run, "onShopOpen", 2)
  T.eq(run.tags, { "TEST_HOOK", "RARE", "TEST_HOOK" })
  ns.Tags.fire(run, "onShopOpen", 1)
  T.eq(run.tags, { "RARE" })
  ns.Tags.def.TEST_TAKE, ns.Tags.def.TEST_HOOK = nil, nil
end)
