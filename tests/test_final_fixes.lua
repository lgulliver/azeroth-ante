local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

-- Boss debuffs honour Smeared Suits / Pareidolia like Balatro.
H.test("suit boss debuff follows Murky Ink's smeared partner suit", function()
  local boss = ns.Bosses.def.VANCLEEF
  local club = H.card(9, "C")
  T.eq(boss.debuff(club), false)
  T.eq(boss.debuff(club, ns.TrinketRules.set({ { id = "MURKY_INK" } })), true)
  local run = H.run({ trinkets = { "MURKY_INK" } })
  local base = H.score(run, { H.card(9, "C") }, {}, { bossId = "HOGGER" })
  local debuffed = H.score(run, { club }, {}, { bossId = "VANCLEEF" })
  local sawDebuff = false
  for _, e in ipairs(debuffed.events) do if e.kind == "debuff" then sawDebuff = true end end
  T.ok(sawDebuff, "scoring forwards ctx.rules to the boss debuff")
  T.ok(debuffed.total < base.total, "the smeared club scores nothing")
end)

H.test("face boss debuff follows Mind Vision", function()
  local boss = ns.Bosses.def.HOGGER
  local two = H.card(2, "H")
  T.eq(boss.debuff(two), false)
  T.eq(boss.debuff(two, ns.TrinketRules.set({ { id = "MIND_VISION" } })), true)
end)

H.test("round-end debuff check honours rules", function()
  local run = H.run({ trinkets = { "MIND_VISION" } })
  run.blind, run.bosses[run.stage] = 3, "HOGGER"
  run.hand = { H.card(2, "H", "GOLD") }
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.held, 0, "a Mind Vision face-debuffed Gold card pays nothing")
end)

-- Scroll of Chance goes through Prob.
H.test("Scroll of Chance honours Loaded Dice with one draw", function()
  local function attempt(trinkets)
    local run = H.run({ trinkets = trinkets })
    run.consumables = { { kind = "scroll", id = "CHANCE" } }
    local real, draws = ns.RNG.next, 0
    ns.RNG.next = function() draws = draws + 1 return 0.3 end
    local ok, err = pcall(ns.Consumables.use, run, 1)
    ns.RNG.next = real
    if not ok then error(err, 0) end
    return run, draws
  end
  local run, draws = attempt({ "FLIGHT_PATH", "LOADED_DICE" })
  T.ok(run.trinkets[1].ed ~= nil or run.trinkets[2].ed ~= nil, "0.3 < 0.5 succeeds with Loaded Dice")
  local run2 = attempt({ "FLIGHT_PATH", "ARCANE_INTELLECT" })
  T.ok(run2.trinkets[1].ed == nil and run2.trinkets[2].ed == nil, "0.3 >= 0.25 fails without")
end)

-- Trinkets.duplicate keeps state without a fresh init.
H.test("duplicate keeps scaled state and sell bonus", function()
  local run = H.run({ trinkets = { "FLIGHT_PATH" } })
  local src = run.trinkets[1]
  src.state.mult = 7
  src.sellBonus, src.paid = 3, 6
  local uid = run.nextTrinketUid
  local copy = ns.Trinkets.duplicate(run, src, "FOIL")
  T.eq(copy.state.mult, 7)
  T.ok(copy.state ~= src.state, "state is deep copied")
  T.eq(copy.sellBonus, 3)
  T.eq(copy.paid, nil)
  T.eq(copy.ed, "FOIL")
  T.eq(copy.uid, uid)
  T.eq(run.nextTrinketUid, uid + 1)
  T.eq(copy.id, "FLIGHT_PATH")
end)

H.test("duplicate does not re-roll Zandalari Idol or draw RNG", function()
  local run = H.run({ trinkets = { "ZANDALARI_IDOL" } })
  local src = run.trinkets[1]
  local snapshot = {}
  for k, v in pairs(run.rng) do snapshot[k] = v end
  local copy = ns.Trinkets.duplicate(run, src)
  T.eq(copy.state.rank, src.state.rank)
  T.eq(copy.state.suit, src.state.suit)
  for k, v in pairs(snapshot) do T.eq(run.rng[k], v, "rng." .. k) end
end)

H.test("Relic of Rebirth keeps the copy's state", function()
  local run = H.run({ trinkets = { "FLIGHT_PATH" } })
  run.trinkets[1].state.mult = 9
  run.consumables = { { kind = "relic", id = "REBIRTH" } }
  ns.Consumables.use(run, 1)
  T.eq(#run.trinkets, 2)
  T.eq(run.trinkets[2].state.mult, 9, "the copy keeps its scaled state")
end)

-- Effective odds in descriptions.
H.test("describe shows effective odds", function()
  local plain = H.run({ trinkets = { "BLOODSTONE" } })
  local dice = H.run({ trinkets = { "BLOODSTONE", "LOADED_DICE" } })
  local def = ns.Trinkets.def.BLOODSTONE
  T.eq(ns.Trinkets.describe(def, plain), "Played Hearts 1 in 2 for ×1.5 Mult")
  T.eq(ns.Trinkets.describe(def, dice), "Played Hearts 2 in 2 for ×1.5 Mult")
  T.eq(ns.Trinkets.describe(def, nil), "Played Hearts 1 in 2 for ×1.5 Mult")
  T.eq(ns.Trinkets.describe({ desc = "+4 Mult" }, dice), "+4 Mult")
  for _, id in ipairs({ "TRADE_PRINCE", "TWISTING_NETHER" }) do
    local d = ns.Trinkets.describe(ns.Trinkets.def[id], dice)
    T.ok(not d:find("{", 1, true), id .. " has no raw token")
    T.ok(d:find("2 in ", 1, true), id .. " shows doubled odds")
  end
end)

-- Unknown trinket ids are tolerated.
H.test("unknown trinket id does not crash scoring or selling", function()
  local run = H.run({ trinkets = { "GUILD_CHARTER" } })
  run.trinkets[2] = { id = "GONE_FROM_GAME", sellBonus = 1, state = {}, uid = 99, paid = 6 }
  local r = H.score(run, { H.card(2) })
  T.ok(r.total > 0)
  T.eq(ns.Shop.sellValue(run.trinkets[2]), 4)
  T.eq(ns.Shop.sellValue({ id = "GONE_FROM_GAME" }), 1)
end)
