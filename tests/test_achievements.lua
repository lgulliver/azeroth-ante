local ns, T = ...

local counters = {
  { "OVERSTOCK_PLUS", "spend", 2500 }, { "LIQUIDATION", "voucherBought", 10 },
  { "REROLL_GLUT", "reroll", 100 }, { "OMEN_GLOBE", "scrollFromPackUsed", 25 },
  { "OBSERVATORY", "tomeFromPackUsed", 25 }, { "NACHO_TONG", "cardsPlayed", 2500 },
  { "RECYCLOMANCY", "cardsDiscarded", 2500 }, { "TAROT_TYCOON", "scrollBought", 50 },
  { "PLANET_TYCOON", "tomeBought", 50 }, { "ANTIMATTER", "blankBought", 10 },
  { "ILLUSION", "cardBought", 20 },
}

T.test("achievement_data_matches_all_tier_two_vouchers", function()
  T.ok(ns.Achievements, "Achievements data missing")
  T.eq(#ns.Achievements.order, 16)
  local seen = {}
  for _, id in ipairs(ns.Achievements.order) do
    T.ok(not seen[id], "duplicate achievement")
    seen[id] = true
    local def = ns.Achievements.def[id]
    T.eq(def.id, id)
    T.eq(def.unlocks, id)
    T.eq(ns.Vouchers.def[id].tier, 2)
    T.ok(type(def.name) == "string" and #def.name > 0)
    T.ok(type(def.desc) == "string" and #def.desc > 0)
  end
  for _, id in ipairs(ns.Vouchers.order) do
    if ns.Vouchers.def[id].tier == 2 then T.ok(seen[id], "missing achievement " .. id) end
  end
end)

T.test("counters_accumulate", function()
  local db = {}
  ns.Profile.event(db, "spend", 12)
  ns.Profile.event(db, "spend", 8)
  ns.Profile.event(db, "cardsPlayed", 5)
  T.eq(ns.Profile.get(db).counters.spend, 20)
  T.eq(ns.Profile.get(db).counters.cardsPlayed, 5)
  T.eq({ ns.Profile.achievementProgress(db, "OVERSTOCK_PLUS") }, { 20, 2500 })
  T.eq(ns.Profile.hasAchievement(db, "OVERSTOCK_PLUS"), false)
end)

for _, c in ipairs(counters) do
  local id, event, target = c[1], c[2], c[3]
  T.test("achievement_boundary_" .. id, function()
    local db = {}
    T.eq(ns.Profile.event(db, event, target - 1), {})
    T.eq(ns.Profile.hasAchievement(db, id), false)
    T.eq({ ns.Profile.achievementProgress(db, id) }, { target - 1, target })
    T.eq(ns.Profile.event(db, event, 1), { id })
    T.eq(ns.Profile.hasAchievement(db, id), true)
    T.eq({ ns.Profile.achievementProgress(db, id) }, { target, target })
    T.eq(ns.Profile.event(db, event, 1), {})
  end)
end

T.test("achievement_boundary_GLOW_UP", function()
  local db = {}
  T.eq(ns.Profile.event(db, "editionTrinkets", 4, {}), {})
  T.eq(ns.Profile.event(db, "editionTrinkets", 4, {}), {})
  T.eq({ ns.Profile.achievementProgress(db, "GLOW_UP") }, { 4, 5 })
  T.eq(ns.Profile.event(db, "editionTrinkets", 5, {}), { "GLOW_UP" })
  ns.Profile.event(db, "editionTrinkets", 0, {})
  T.eq(ns.Profile.hasAchievement(db, "GLOW_UP"), true)
end)

T.test("achievement_boundary_MONEY_TREE", function()
  local db, run = {}, {}
  T.eq(ns.Profile.event(db, "maxInterestStreak", 9, run), {})
  T.eq(ns.Profile.event(db, "maxInterestStreak", 0, run), {})
  T.eq(ns.Profile.event(db, "maxInterestStreak", 9, {}), {})
  T.eq({ ns.Profile.achievementProgress(db, "MONEY_TREE") }, { 9, 10 })
  T.eq(ns.Profile.event(db, "maxInterestStreak", 10, run), { "MONEY_TREE" })
end)

T.test("achievement_boundary_PETROGLYPH", function()
  local db = {}
  T.eq({ ns.Profile.achievementProgress(db, "PETROGLYPH") }, { 0, 1 })
  T.eq(ns.Profile.event(db, "runEnded", 1), {})
  T.eq(ns.Profile.event(db, "runEnded", 1, {}), {})
  T.eq(ns.Profile.event(db, "runEnded", 1, { vouchers = {} }), {})
  local run = { vouchers = { HIEROGLYPH = true } }
  T.eq(ns.Profile.event(db, "runEnded", 0, run), {})
  T.eq(ns.Profile.event(db, "spend", 1, run), {})
  T.eq(ns.Profile.event(db, "runEnded", 1, run), { "PETROGLYPH" })
  T.eq({ ns.Profile.achievementProgress(db, "PETROGLYPH") }, { 1, 1 })
end)

T.test("achievement_boundary_RETCON", function()
  local db = {}
  T.eq(ns.Profile.event(db, "bossFought", "UNKNOWN", {}), {})
  for _, id in ipairs({ "HOGGER", "VANCLEEF", "ARUGAL", "MUTANUS", "HEROD", "RIVENDARE", "ONYXIA", "VAELASTRASZ" }) do
    T.eq(ns.Profile.event(db, "bossFought", id, {}), {})
    T.eq(ns.Profile.event(db, "bossFought", id, {}), {})
  end
  T.eq({ ns.Profile.achievementProgress(db, "RETCON") }, { 8, 9 })
  T.eq(ns.Profile.get(db).bossesSeen.HOGGER, true)
  T.eq(ns.Profile.event(db, "bossFought", "RAGNAROS", {}), { "RETCON" })
  T.eq({ ns.Profile.achievementProgress(db, "RETCON") }, { 9, 9 })
end)

T.test("achievement_boundary_PALETTE", function()
  local db = {}
  T.eq(ns.Profile.event(db, "handSize", 6, {}), {})
  T.eq(ns.Profile.event(db, "cardsPlayed", 5, {}), {})
  T.eq(ns.Profile.event(db, "handSize", 5, {}), { "PALETTE" })
  T.eq(ns.Profile.event(db, "handSize", 4, {}), {})
  T.eq(ns.Profile.hasAchievement(db, "PALETTE"), true)
  T.eq(ns.Profile.event({}, "handSize", 4, {}), { "PALETTE" })
end)

T.test("achievement_toast_queue", function()
  local db = {}
  T.eq(ns.Profile.newAchievements(db), {})
  ns.Profile.event(db, "voucherBought", 10)
  ns.Profile.event(db, "spend", 2500)
  T.eq(ns.Profile.newAchievements(db), { "OVERSTOCK_PLUS", "LIQUIDATION" })
  ns.Profile.markAchievementSeen(db, "OVERSTOCK_PLUS")
  T.eq(ns.Profile.newAchievements(db), { "LIQUIDATION" })
  T.eq(ns.Profile.event(db, "spend", 1), {})
  T.eq(ns.Profile.newAchievements(db), { "LIQUIDATION" })
  ns.Profile.markAchievementSeen(db, "LIQUIDATION")
  T.eq(ns.Profile.newAchievements(db), {})
  T.eq(ns.Profile.hasAchievement(db, "OVERSTOCK_PLUS"), true)
end)

T.test("achievement_migration_preserves_progress", function()
  local db = { profile = { counters = { spend = 2499 }, achievements = { LIQUIDATION = true },
    bossesSeen = { HOGGER = true }, seenAchievements = { LIQUIDATION = true }, unlockedDecks = { WARRIOR = true } } }
  T.eq(ns.Profile.event(db, "spend", 1), { "OVERSTOCK_PLUS" })
  T.eq(ns.Profile.get(db).bossesSeen, { HOGGER = true })
  T.eq(ns.Profile.newAchievements(db), { "OVERSTOCK_PLUS" })
  T.eq(ns.Profile.isUnlocked(db, "WARRIOR"), true)
  T.eq({ ns.Profile.achievementProgress(db, "UNKNOWN") }, { 0, 0 })
end)

T.test("shop_without_bound_profile_keeps_upgrades_locked", function()
  local run = ns.Run.new(11, "ROGUE")
  for _, id in ipairs(ns.Vouchers.order) do
    if ns.Vouchers.def[id].tier == 1 then run.vouchers[id] = true end
  end
  T.eq(ns.Shop.rollVoucher(run), false)
end)

T.test("has_achievement_one_argument_uses_profile_db", function()
  local db = {}
  ns.Profile.db = nil
  T.eq(ns.Profile.hasAchievement("PALETTE"), false)
  ns.Profile.db = db
  T.eq(ns.Profile.hasAchievement("PALETTE"), false)
  ns.Profile.get(db).achievements.PALETTE = true
  T.eq(ns.Profile.hasAchievement("PALETTE"), true)
  T.eq(ns.Profile.hasAchievement(db, "PALETTE"), true)
  ns.Profile.db = nil
  T.eq(ns.Profile.hasAchievement("PALETTE"), false)
end)
