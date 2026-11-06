local ns, T = ...

T.test("deck_starting_rules_reset_each_round", function()
  T.eq(ns.Decks.order, { "ROGUE", "WARRIOR", "GOBLIN", "MONK", "WARLOCK" })
  local cases = {
    { "ROGUE", 4, 4, 4, 5 }, { "WARRIOR", 5, 3, 4, 5 },
    { "GOBLIN", 4, 3, 14, 5 }, { "MONK", 4, 3, 4, 5 },
    { "WARLOCK", 3, 3, 4, 6 }, { "ADVENTURER", 4, 3, 4, 5 },
  }
  for _, c in ipairs(cases) do
    local run = ns.Run.new(7, c[1])
    T.eq({ run.handsLeft, run.discardsLeft, run.gold, ns.Run.trinketSlots(run) }, { c[2], c[3], c[4], c[5] })
    run.handsLeft, run.discardsLeft = 0, 0
    ns.Run.startBlind(run)
    T.eq({ run.handsLeft, run.discardsLeft }, { c[2], c[3] })
  end
end)

T.test("monk_pays_unused_resources_without_interest", function()
  local run = ns.Run.new(7, "MONK")
  run.gold, run.handsLeft, run.discardsLeft = 29, 2, 3
  ns.Run.winBlind(run)
  T.eq(run.lastPayout, { reward = 3, hands = 4, discards = 3, interest = 0, trinkets = 0, trinketLines = {}, held = 0, total = 10 })
  T.eq(run.gold, 39)
  run = ns.Run.new(7, "ROGUE")
  run.gold, run.handsLeft = 29, 2
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.discards, 0)
  T.eq(run.lastPayout.total, 10)
end)

T.test("warlock_slot_stacks_with_negative_and_allows_sixth_purchase", function()
  local run = ns.Run.new(7, "WARLOCK")
  for i = 1, 5 do run.trinkets[i] = { id = "BLOODLUST" } end
  run.shop = { cards = { { type = "trinket", id = "HEARTHSTONE", cost = 1 } } }
  T.eq(ns.Shop.buy(run, 1), true)
  T.eq(#run.trinkets, 6)
  run.trinkets[1].ed = "NEGATIVE"
  T.eq(ns.Run.trinketSlots(run), 7)
end)

T.test("profile_creation_migration_preserves_progress_and_save", function()
  T.ok(ns.Profile, "Profile module missing")
  local db = { run = { seed = 7 }, version = 2 }
  local p = ns.Profile.get(db)
  T.eq(p, { version = 1, discovered = {}, stats = {}, seenUnlocks = {},
    counters = {}, achievements = {}, bossesSeen = {}, unlockedDecks = {}, seenAchievements = {} })
  T.ok(p == ns.Profile.get(db))
  db.profile = { version = 0, discovered = { ["scroll:FURY"] = true }, stats = { ROGUE = { wins = 2 } } }
  p = ns.Profile.get(db)
  T.eq(p.version, 1)
  T.eq(p.discovered["scroll:FURY"], true)
  T.eq(p.seenUnlocks, {})
  T.eq(p.stats.ROGUE, { wins = 2, bestStage = 0, runs = 0 })
  T.eq(db.run, { seed = 7 })
  T.eq(db.version, 2)
  ns.Save.clear(db)
  T.eq(ns.Profile.discoveredCount(db), 1)
end)

T.test("discovery_idempotence_counts_and_kind_namespaces", function()
  T.ok(ns.Profile, "Profile module missing")
  local db = {}
  T.eq(ns.Profile.totalDiscoverable(), 164) -- Wave 1 adds 60 discoverable S trinkets.
  T.eq(ns.Profile.discoveredCount(db), 0)
  for _, item in ipairs({ { "trinket", "BLOODLUST" }, { "scroll", "FURY" }, { "tome", "PAIR" }, { "relic", "LICH" }, { "voucher", "BLANK" } }) do
    T.eq(ns.Profile.discover(db, item[1], item[2]), true)
    T.eq(ns.Profile.discover(db, item[1], item[2]), false)
  end
  T.eq(ns.Profile.discoveredCount(db), 5)
end)

T.test("unlock_thresholds_and_seen_notifications", function()
  T.ok(ns.Profile, "Profile module missing")
  local db = {}
  local p = ns.Profile.get(db)
  T.eq({ ns.Profile.isUnlocked(db, "ROGUE") }, { true, 0, 0 })
  T.eq(ns.Profile.newlyUnlocked(db), { "ROGUE" })
  ns.Profile.markSeen(db, "ROGUE")
  local items = {}
  for _, data in ipairs({ ns.Trinkets, ns.Tomes, ns.Scrolls, ns.Relics }) do
    for _, id in ipairs(data.order) do items[#items + 1] = tostring(#items + 1) .. ":" .. id end
  end
  for i = 1, 35 do
    p.discovered[items[i]] = true
    for _, c in ipairs({ { "WARRIOR", 7 }, { "GOBLIN", 17 }, { "MONK", 26 }, { "WARLOCK", 35 } }) do
      T.eq({ ns.Profile.isUnlocked(db, c[1]) }, { i >= c[2], i, c[2] })
    end
  end
  T.eq(ns.Profile.newlyUnlocked(db), { "WARRIOR", "GOBLIN", "MONK", "WARLOCK" })
  ns.Profile.markSeen(db, "WARRIOR")
  T.eq(ns.Profile.newlyUnlocked(db), { "GOBLIN", "MONK", "WARLOCK" })
end)

T.test("record_runs_tracks_decks_wins_and_furthest_stage", function()
  T.ok(ns.Profile, "Profile module missing")
  local db, run = {}, ns.Run.new(7, "ROGUE")
  run.phase, run.stage = "lost", 6
  ns.Profile.recordRun(db, run)
  run.phase, run.stage = "won", 8
  ns.Profile.recordRun(db, run)
  run.phase, run.stage = "lost", 2
  ns.Profile.recordRun(db, run)
  run.deckId = "ADVENTURER"
  ns.Profile.recordRun(db, run)
  T.eq(ns.Profile.get(db).stats, {
    ROGUE = { runs = 3, wins = 1, bestStage = 8 },
    ADVENTURER = { runs = 1, wins = 0, bestStage = 2 },
  })
end)

local function withCallback(fn)
  T.ok(ns.Profile, "Profile module missing")
  local old, events = ns.Profile.onObtain, {}
  ns.Profile.onObtain = function(kind, id) events[#events + 1] = { kind, id } end
  local ok, err = pcall(fn, events)
  ns.Profile.onObtain = old
  if not ok then error(err, 0) end
end

T.test("shop_obtains_trinkets_and_all_consumable_kinds_once", function()
  withCallback(function(events)
    local run = ns.Run.new(7, "ROGUE")
    run.gold, run.maxConsumables = 100, 3
    run.shop = { cards = {
      { type = "trinket", id = "BLOODLUST", cost = 1 },
      { type = "scroll", id = "FURY", cost = 1 },
      { type = "tome", id = "PAIR", cost = 1 },
      { type = "relic", id = "LICH", cost = 1 },
    } }
    for i = 1, 4 do T.eq(ns.Shop.buy(run, i), true) end
    T.eq(ns.Shop.buy(run, 1), false)
    T.eq(events, { { "trinket", "BLOODLUST" }, { "scroll", "FURY" }, { "tome", "PAIR" }, { "relic", "LICH" } })
  end)
end)

T.test("pack_picks_discover_including_immediately_used_tomes", function()
  withCallback(function(events)
    local run = ns.Run.new(7, "ROGUE")
    for _, c in ipairs({ { "BUFFOON", "trinket", "BLOODLUST" }, { "CELESTIAL", "tome", "PAIR" },
      { "ARCANA", "scroll", "GREED" }, { "SPECTRAL", "relic", "COSMOS" } }) do
      run.shop = { openPack = { type = c[1], choices = { { kind = c[2], id = c[3] } }, picksLeft = 1 } }
      T.eq(ns.Packs.pick(run, 1), true)
    end
    T.eq(events, { { "trinket", "BLOODLUST" }, { "tome", "PAIR" }, { "scroll", "GREED" }, { "relic", "COSMOS" } })
    T.eq(run.handLevels.PAIR, 3)
  end)
end)

T.test("created_consumables_and_seals_discover_only_added_items", function()
  withCallback(function(events)
    for _, c in ipairs({ { "KNOWLEDGE", "scroll" }, { "STARS", "tome" } }) do
      local run = ns.Run.new(7, "ROGUE")
      local start = #events
      local result = ns.Consumables.apply(run, { kind = "scroll", id = c[1] })
      T.eq(#events - start, 3)
      for _, item in ipairs(result.created) do
        local found = false
        for i = start + 1, #events do
          if events[i][1] == c[2] and events[i][2] == item.id then found = true end
        end
        T.ok(found, "created item missing discovery")
      end
    end
    local run = ns.Run.new(7, "ROGUE")
    ns.Run.startBlind(run)
    run.hand[1].seal = "PURPLE"
    local start = #events
    local out = ns.Run.discard(run, { 1 })
    T.eq(events[start + 1], { "scroll", out.created[1].id })
    run.hand[1].seal, run.lastHandId = "BLUE", "PAIR"
    ns.Run.winBlind(run)
    T.eq(events[start + 2], { "tome", "PAIR" })
    T.eq(ns.Consumables.add(run, { kind = "scroll", id = "FURY" }), false)
    T.eq(#events, start + 2)
  end)
end)

T.test("consumable_trinket_creation_and_rebirth_copies_discover", function()
  withCallback(function(events)
    for _, c in ipairs({ { "scroll", "SUMMONING" }, { "relic", "LICH" }, { "relic", "LEGENDS" }, { "relic", "REBIRTH" } }) do
      local run = ns.Run.new(7, "ROGUE")
      if c[2] == "REBIRTH" then run.trinkets = { { id = "BLOODLUST" } } end
      local start = #events
      ns.Consumables.apply(run, { kind = c[1], id = c[2] })
      T.eq(#events - start, 2)
      local created = run.trinkets[#run.trinkets]
      local got = { events[start + 1], events[start + 2] }
      T.ok((got[1][1] == "trinket" and got[1][2] == created.id) or
        (got[2][1] == "trinket" and got[2][2] == created.id))
    end
  end)
end)

T.test("editing_existing_trinkets_does_not_obtain_them_again", function()
  withCallback(function(events)
    local run = ns.Run.new(7, "ROGUE")
    run.trinkets = { { id = "BLOODLUST" } }
    ns.Consumables.apply(run, { kind = "relic", id = "VOID" })
    T.eq(events, { { "relic", "VOID" } })
  end)
end)

T.test("sim_defaults_to_every_selectable_deck", function()
  local process = assert(io.popen("luajit tools/sim/sim.lua 1"))
  local output = process:read("*a")
  process:close()
  for _, id in ipairs({ "ROGUE", "WARRIOR", "GOBLIN", "MONK", "WARLOCK" }) do
    T.ok(output:find("deck " .. id .. ", 1 runs, seed 1", 1, true), "sim missing " .. id)
  end
  T.ok(not output:find("deck ADVENTURER", 1, true))
end)

T.test("grandfathered_unlocks", function()
  for _, c in ipairs({ { "WARRIOR", 5 }, { "GOBLIN", 12 }, { "MONK", 18 }, { "WARLOCK", 24 } }) do
    local db = { profile = { discovered = {}, seenUnlocks = { [c[1]] = true } } }
    for i = 1, c[2] do db.profile.discovered[tostring(i)] = true end
    local p = ns.Profile.get(db)
    T.eq(p.unlockedDecks[c[1]], true)
    p.discovered = {}
    T.eq(ns.Profile.isUnlocked(db, c[1]), true)
    T.eq(p.seenUnlocks[c[1]], true)
  end
  local db = { profile = { discovered = {} } }
  for i = 1, 6 do db.profile.discovered[tostring(i)] = true end
  ns.Profile.get(db)
  T.eq(ns.Profile.isUnlocked(db, "WARRIOR"), true)
  T.eq(ns.Profile.isUnlocked(db, "GOBLIN"), false)
end)

T.test("new_thresholds_persist_without_reapplying_old_thresholds", function()
  for _, c in ipairs({ { "WARRIOR", 7 }, { "GOBLIN", 17 }, { "MONK", 26 }, { "WARLOCK", 35 } }) do
    local db = {}
    local p = ns.Profile.get(db)
    for i = 1, c[2] - 1 do p.discovered[tostring(i)] = true end
    T.eq(ns.Profile.isUnlocked(db, c[1]), false)
    p.discovered[tostring(c[2])] = true
    T.eq(ns.Profile.isUnlocked(db, c[1]), true)
    T.eq(p.unlockedDecks[c[1]], true)
    p.discovered = {}
    T.eq(ns.Profile.isUnlocked(db, c[1]), true)
  end
end)

T.test("total_discoverable_164", function()
  local db = {}
  for _, c in ipairs({ { "trinket", ns.Trinkets }, { "scroll", ns.Scrolls },
    { "tome", ns.Tomes }, { "relic", ns.Relics }, { "voucher", ns.Vouchers } }) do
    for _, id in ipairs(c[2].order) do T.eq(ns.Profile.discover(db, c[1], id), true) end
  end
  T.eq(ns.Profile.discoveredCount(db), 164)
  T.eq(ns.Profile.totalDiscoverable(), 164) -- Wave 1 adds 60 discoverable S trinkets.
  T.eq(ns.Profile.discover(db, "voucher", "UNKNOWN"), false)
end)
