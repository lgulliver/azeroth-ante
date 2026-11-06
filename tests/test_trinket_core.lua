local ns, T = ...

local function newRun()
  return ns.Run.new(7, "ADVENTURER")
end

-- Registers a stub def for the duration of fn, then removes it again.
local function withStub(def, fn)
  ns.Trinkets.add(def)
  local ok, err = pcall(fn)
  ns.Trinkets.def[def.id] = nil
  ns.Trinkets.order[#ns.Trinkets.order] = nil
  if not ok then error(err, 0) end
end

T.test("create_assigns_uid_state_sellbonus", function()
  local run = newRun()
  local a = ns.Trinkets.create(run, "BLOODLUST", nil, 8)
  local b = ns.Trinkets.create(run, "FORTITUDE")
  T.eq({ a.uid, b.uid }, { 1, 2 })
  T.eq(a.state, {})
  T.eq(a.sellBonus, 0)
  T.eq(a.paid, 8)
  T.eq(run.nextTrinketUid, 3)
  T.eq(#run.trinkets, 0)
end)

T.test("create_calls_init", function()
  withStub({ id = "STUB_INIT", name = "Stub", rarity = "common", cost = 1,
    init = function(self) self.state.x = 7 end }, function()
    local inst = ns.Trinkets.create(newRun(), "STUB_INIT")
    T.eq(inst.state.x, 7)
  end)
end)

T.test("add_rejects_duplicate", function()
  local ok = pcall(ns.Trinkets.add, { id = "BLOODLUST" })
  T.ok(not ok, "duplicate id accepted")
end)

T.test("in_pool_defaults_true_and_respects_def", function()
  local run = newRun()
  T.ok(ns.Trinkets.inPool(run, "BLOODLUST"))
  withStub({ id = "STUB_POOL", name = "Stub", rarity = "common", cost = 1,
    inPool = function() return false end }, function()
    T.ok(not ns.Trinkets.inPool(run, "STUB_POOL"))
  end)
end)

T.test("sell_value_includes_bonus", function()
  T.eq(ns.Shop.sellValue({ id = "BLOODLUST", paid = 6, sellBonus = 3 }), 6)
  T.eq(ns.Shop.sellValue({ id = "WHETSTONE" }), 2)
  T.eq(ns.Shop.sellValue({ id = "WHETSTONE", paid = 0 }), 1)
end)

T.test("prob_roll_draws_once_and_doubles", function()
  local oops = { id = "STUB_OOPS", name = "Stub", rarity = "common", cost = 1, rule = "OOPS" }
  withStub(oops, function()
    local function peek()
      local rng = ns.RNG.new(99)
      return ns.RNG.next(rng)
    end
    local v = peek()
    local rng = ns.RNG.new(99)
    T.eq(ns.Prob.roll(rng, {}, 1, 4), v < 0.25)
    rng = ns.RNG.new(99)
    T.eq(ns.Prob.roll(rng, { { id = "STUB_OOPS" } }, 1, 4), v < 0.5)
    T.eq(ns.Prob.mult({ { id = "STUB_OOPS" }, { id = "STUB_OOPS" } }), 4)
    T.eq(ns.Prob.mult({}), 1)
    T.eq(ns.Prob.odds({ { id = "STUB_OOPS" } }, 3), 6)
    local a, b = ns.RNG.new(5), ns.RNG.new(5)
    T.ok(ns.Prob.roll(a, {}, 4, 4), "4 in 4 must hit")
    ns.RNG.next(b)
    T.eq(ns.RNG.next(a), ns.RNG.next(b))
  end)
end)

T.test("rules_set_collects_rules", function()
  withStub({ id = "STUB_RULE", name = "Stub", rarity = "common", cost = 1, rule = "FOO" }, function()
    local list = { { id = "STUB_RULE" }, { id = "BLOODLUST" } }
    T.eq(ns.TrinketRules.set(list), { FOO = true })
    T.ok(ns.TrinketRules.has(list, "FOO"))
    T.ok(not ns.TrinketRules.has(list, "BAR"))
  end)
end)

T.test("move_trinket_reorders", function()
  local run = newRun()
  run.trinkets = { { id = "a" }, { id = "b" }, { id = "c" } }
  T.eq(ns.Run.moveTrinket(run, 1, 3), true)
  T.eq({ run.trinkets[1].id, run.trinkets[2].id, run.trinkets[3].id }, { "b", "c", "a" })
  T.eq(ns.Run.moveTrinket(run, 0, 2), false)
  T.eq(ns.Run.moveTrinket(run, 1, 4), false)
end)

T.test("run_new_has_uid_counter_and_round_plays", function()
  local run = newRun()
  T.eq(run.nextTrinketUid, 1)
  T.eq(run.roundHandPlays, {})
  ns.Run.startBlind(run)
  ns.Run.play(run, { 1 })
  local total = 0
  for _, n in pairs(run.roundHandPlays) do total = total + n end
  T.eq(total, 1)
  run.phase = "blind"
  ns.Run.startBlind(run)
  T.eq(run.roundHandPlays, {})
end)

T.test("all_creation_sites_use_create", function()
  -- Shop
  local run = newRun()
  run.phase, run.gold = "shop", 100
  ns.Shop.open(run)
  run.shop.cards[1] = { type = "trinket", id = "BLOODLUST", cost = 8 }
  T.eq(ns.Shop.buy(run, 1), true)
  local bought = run.trinkets[1]
  T.ok(bought.uid and bought.state, "shop trinket lacks uid/state")
  T.eq(bought.paid, 8)
  -- Buffoon pack
  run = newRun()
  run.phase, run.gold = "shop", 100
  ns.Shop.open(run)
  run.shop.packs[1] = { type = "BUFFOON", size = "normal", cost = 4 }
  T.eq(ns.Packs.open(run, 1), true)
  T.eq(ns.Packs.pick(run, 1), true)
  local taken = run.trinkets[1]
  T.ok(taken.uid and taken.state, "pack trinket lacks uid/state")
  T.eq(taken.paid, nil)
  -- Relic (Lich creates a rare trinket)
  run = newRun()
  run.phase = "shop"
  local item = { kind = "relic", id = "LICH" }
  local ok, reason = ns.Consumables.canApply(run, item, {})
  T.ok(ok, tostring(reason))
  ns.Consumables.apply(run, item, {})
  local made = run.trinkets[1]
  T.ok(made and made.uid and made.state, "relic trinket lacks uid/state")
  -- Scroll (Summoning)
  run = newRun()
  run.phase = "shop"
  item = { kind = "scroll", id = "SUMMONING" }
  ok, reason = ns.Consumables.canApply(run, item, {})
  T.ok(ok, tostring(reason))
  ns.Consumables.apply(run, item, {})
  made = run.trinkets[1]
  T.ok(made and made.uid and made.state, "scroll trinket lacks uid/state")
end)

T.test("buffoon_trinket_sells_for_half_cost", function()
  local run = newRun()
  run.phase, run.gold = "shop", 100
  ns.Shop.open(run)
  run.shop.packs[1] = { type = "BUFFOON", size = "normal", cost = 4 }
  T.eq(ns.Packs.open(run, 1), true)
  run.shop.openPack.choices[1] = { type = "trinket", id = "WHETSTONE", cost = 5 }
  T.eq(ns.Packs.pick(run, 1), true)
  T.eq(ns.Shop.sellValue(run.trinkets[1]), 2)
end)
