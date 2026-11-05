local ns, T = ...

local function card(rank, suit)
  return { rank = rank, suit = suit or "S", id = rank }
end

local function ctx(extra)
  local c = { cards = {}, handLevels = {}, trinkets = {}, handsPlayedTotal = 1,
    isLastHand = false, discardsLeft = 0, gold = 0, contains = {}, rng = ns.RNG.new(1) }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function trinket(id)
  return ns.Trinkets.def[id]
end

local function handHook(id, c)
  return trinket(id).onHand(c)
end

local function cardHook(id, c, cd)
  return trinket(id).onCard(c, cd)
end

local VALID_RARITY = { common = true, uncommon = true, rare = true }
local ICON_PREFIX = "Interface\\Icons\\"

T.test("twenty_trinkets_complete", function()
  T.eq(#ns.Trinkets.order, 20)
  local seen = {}
  for _, id in ipairs(ns.Trinkets.order) do
    local def = trinket(id)
    T.ok(def, "missing def " .. id)
    T.ok(not seen[id], "duplicate " .. id)
    seen[id] = true
    T.ok(type(def.id) == "string" and def.id == id, id .. ": id mismatch")
    T.ok(type(def.name) == "string" and def.name ~= "", id .. ": no name")
    T.ok(type(def.desc) == "string" and def.desc ~= "", id .. ": no desc")
    T.ok(type(def.icon) == "string" and def.icon:sub(1, #ICON_PREFIX) == ICON_PREFIX, id .. ": bad icon")
    T.ok(VALID_RARITY[def.rarity], id .. ": bad rarity")
    T.ok(type(def.cost) == "number", id .. ": cost not a number")
    T.ok(def.onCard or def.onHand or def.onRoundEnd, id .. ": no hook")
  end
end)

T.test("trinket_bloodlust", function()
  T.eq(handHook("BLOODLUST", ctx({ handsPlayedTotal = 5 })), { xmult = 3 })
  T.eq(handHook("BLOODLUST", ctx({ handsPlayedTotal = 10 })), { xmult = 3 })
  T.eq(handHook("BLOODLUST", ctx({ handsPlayedTotal = 4 })), nil)
end)

T.test("trinket_arcane_intellect", function()
  T.eq(handHook("ARCANE_INTELLECT", ctx()), { mult = 4 })
end)

T.test("trinket_fortitude", function()
  T.eq(handHook("FORTITUDE", ctx()), { chips = 50 })
end)

T.test("trinket_whetstone", function()
  T.eq(cardHook("WHETSTONE", ctx(), card(9, "S")), { mult = 3 })
  T.eq(cardHook("WHETSTONE", ctx(), card(9, "H")), nil)
end)

T.test("trinket_healthstone", function()
  T.eq(cardHook("HEALTHSTONE", ctx(), card(9, "H")), { mult = 3 })
  T.eq(cardHook("HEALTHSTONE", ctx(), card(9, "S")), nil)
end)

T.test("trinket_ogre_cudgel", function()
  T.eq(cardHook("OGRE_CUDGEL", ctx(), card(9, "C")), { mult = 3 })
  T.eq(cardHook("OGRE_CUDGEL", ctx(), card(9, "D")), nil)
end)

T.test("trinket_jewelers_kit", function()
  T.eq(cardHook("JEWELERS_KIT", ctx(), card(9, "D")), { mult = 3 })
  T.eq(cardHook("JEWELERS_KIT", ctx(), card(9, "C")), nil)
end)

T.test("trinket_hearthstone", function()
  T.eq(trinket("HEARTHSTONE").onRoundEnd({}), 3)
end)

T.test("trinket_lucky_charm", function()
  -- Find one seed whose first roll is below 0.25 and one whose roll is at or above it.
  -- Park-Miller gives tiny first outputs for small seeds, so the miss sits at larger seeds.
  local hit, miss
  for seed = 1, 100000 do
    local v = ns.RNG.next(ns.RNG.new(seed))
    if v < 0.25 and not hit then hit = seed end
    if v >= 0.25 and not miss then miss = seed end
    if hit and miss then break end
  end
  T.ok(hit and miss, "could not find seeds")
  T.eq(handHook("LUCKY_CHARM", ctx({ rng = ns.RNG.new(hit) })), { mult = 20 })
  T.eq(handHook("LUCKY_CHARM", ctx({ rng = ns.RNG.new(miss) })), nil)
end)

T.test("trinket_execute", function()
  T.eq(handHook("EXECUTE", ctx({ isLastHand = true })), { xmult = 3 })
  T.eq(handHook("EXECUTE", ctx({ isLastHand = false })), nil)
end)

T.test("trinket_combo_points", function()
  T.eq(handHook("COMBO_POINTS", ctx({ discardsLeft = 3 })), { chips = 60 })
  T.eq(handHook("COMBO_POINTS", ctx({ discardsLeft = 0 })), { chips = 0 })
end)

T.test("trinket_twin_blades", function()
  T.eq(handHook("TWIN_BLADES", ctx({ contains = { PAIR = true } })), { mult = 8 })
  T.eq(handHook("TWIN_BLADES", ctx({ contains = { HIGH_CARD = true } })), nil)
end)

T.test("trinket_cleave", function()
  T.eq(handHook("CLEAVE", ctx({ contains = { THREE_KIND = true } })), { mult = 12 })
  T.eq(handHook("CLEAVE", ctx({ contains = { PAIR = true } })), nil)
end)

T.test("trinket_multi_shot", function()
  T.eq(handHook("MULTI_SHOT", ctx({ contains = { STRAIGHT = true } })), { mult = 12 })
  T.eq(handHook("MULTI_SHOT", ctx({ contains = { FLUSH = true } })), nil)
end)

T.test("trinket_elemental", function()
  T.eq(handHook("ELEMENTAL", ctx({ contains = { FLUSH = true } })), { mult = 10 })
  T.eq(handHook("ELEMENTAL", ctx({ contains = { STRAIGHT = true } })), nil)
end)

T.test("trinket_royal_guard", function()
  T.eq(cardHook("ROYAL_GUARD", ctx(), card(12)), { chips = 30 })
  T.eq(cardHook("ROYAL_GUARD", ctx(), card(10)), nil)
end)

T.test("trinket_battle_shout", function()
  local c = ctx({ trinkets = { { id = "BATTLE_SHOUT" }, { id = "FORTITUDE" }, { id = "EXECUTE" } } })
  T.eq(handHook("BATTLE_SHOUT", c), { mult = 9 })
end)

T.test("trinket_goblin_bank", function()
  T.eq(handHook("GOBLIN_BANK", ctx({ gold = 12 })), { mult = 2 })
  T.eq(handHook("GOBLIN_BANK", ctx({ gold = 4 })), { mult = 0 })
end)

T.test("trinket_avenging_wrath", function()
  T.eq(handHook("AVENGING_WRATH", ctx()), { xmult = 2 })
end)

T.test("trinket_hunters_mark", function()
  T.eq(cardHook("HUNTERS_MARK", ctx(), card(14)), { xmult = 1.5 })
  T.eq(cardHook("HUNTERS_MARK", ctx(), card(13)), nil)
end)

T.test("bosses_complete", function()
  T.eq(#ns.Bosses.pool, 8)
  local expected = { "HOGGER", "VANCLEEF", "ARUGAL", "MUTANUS", "HEROD", "RIVENDARE", "ONYXIA", "VAELASTRASZ" }
  for i, id in ipairs(expected) do T.eq(ns.Bosses.pool[i], id) end
  for _, id in ipairs(ns.Bosses.pool) do
    local def = ns.Bosses.def[id]
    T.ok(def, "missing boss " .. id)
    T.ok(def.name and def.name ~= "", id .. ": no name")
    T.ok(def.desc and def.desc ~= "", id .. ": no desc")
  end
  T.eq(ns.Bosses.FINAL, "RAGNAROS")
  local final = ns.Bosses.def[ns.Bosses.FINAL]
  T.ok(final, "missing final boss")
  T.ok(final.name and final.name ~= "", "final: no name")
  T.ok(final.desc and final.desc ~= "", "final: no desc")
  T.eq(final.targetMult, 4)
end)

T.test("boss_debuffs", function()
  local function debuffs(id, cd)
    return ns.Bosses.def[id].debuff(cd)
  end
  T.eq(debuffs("HOGGER", card(12, "H")), true)
  T.eq(debuffs("HOGGER", card(9, "H")), false)
  T.eq(debuffs("VANCLEEF", card(9, "S")), true)
  T.eq(debuffs("VANCLEEF", card(9, "H")), false)
  T.eq(debuffs("ARUGAL", card(9, "H")), true)
  T.eq(debuffs("ARUGAL", card(9, "D")), false)
  T.eq(debuffs("VAELASTRASZ", card(9, "D")), true)
  T.eq(debuffs("VAELASTRASZ", card(9, "C")), false)
end)

T.test("boss_rules", function()
  local b = ns.Bosses.def
  T.eq(b.MUTANUS.discards, 0)
  T.eq(b.HEROD.mustPlay, 5)
  T.eq(b.RIVENDARE.halveBase, true)
  T.eq(b.ONYXIA.hands, 1)
  T.eq(b.ONYXIA.targetMult, 1)
  T.eq(b.HOGGER.targetMult, 2)
end)

T.test("decks_values", function()
  T.eq(ns.Decks.order, { "ADVENTURER", "WARRIOR", "ROGUE", "GOBLIN" })
  local d = ns.Decks.def
  T.eq(d.ADVENTURER.hands, 4)
  T.eq(d.ADVENTURER.discards, 3)
  T.eq(d.ADVENTURER.gold, 4)
  T.eq(d.WARRIOR.hands, 5)
  T.eq(d.WARRIOR.discards, 3)
  T.eq(d.WARRIOR.gold, 4)
  T.eq(d.ROGUE.hands, 4)
  T.eq(d.ROGUE.discards, 4)
  T.eq(d.ROGUE.gold, 4)
  T.eq(d.GOBLIN.hands, 4)
  T.eq(d.GOBLIN.discards, 3)
  T.eq(d.GOBLIN.gold, 10)
  for _, id in ipairs(ns.Decks.order) do
    T.eq(d[id].id, id)
    T.ok(d[id].name and d[id].desc, id .. ": missing name or desc")
  end
end)
