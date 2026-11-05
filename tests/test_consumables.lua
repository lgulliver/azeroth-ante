local ns, T = ...

local function newRun(phase)
  local run = ns.Run.new(7, "ADVENTURER")
  if phase == "play" then ns.Run.startBlind(run) else run.phase = phase or "shop" end
  return run
end

local function scroll(id) return { kind = "scroll", id = id } end
local function tome(id) return { kind = "tome", id = id } end

T.test("add_respects_slots", function()
  local run = newRun()
  T.ok(ns.Consumables.add(run, scroll("FORTUNE")))
  T.ok(ns.Consumables.add(run, scroll("FURY")))
  T.ok(not ns.Consumables.add(run, scroll("BLADES")))
  T.eq(#run.consumables, 2)
end)

T.test("catalog_sizes", function()
  T.eq(#ns.Tomes.order, 12)
  T.eq(ns.Tomes.def.PAIR.name, "Tome of Pair")
  T.eq(#ns.Scrolls.order, 22)
  for _, id in ipairs(ns.Scrolls.order) do
    local d = ns.Scrolls.def[id]
    T.eq(d.id, id)
    T.ok(type(d.name) == "string" and type(d.desc) == "string" and type(d.icon) == "string", id)
    T.ok(type(d.use) == "function", id)
    T.eq(type(d.untargeted), "boolean")
    T.ok((d.select ~= nil) ~= d.untargeted, id .. ": targeted xor untargeted")
  end
end)

T.test("creator_respects_slots", function()
  local run = newRun()
  run.consumables = { scroll("KNOWLEDGE"), scroll("FORTUNE") }
  local ok = ns.Consumables.canUse(run, 1)
  T.ok(ok, "own slot frees")
  local outcome = ns.Consumables.use(run, 1)
  T.eq(#outcome.created, 1)
  T.eq(#run.consumables, 2)
  T.eq(outcome.created[1].kind, "scroll")

  run = newRun()
  run.consumables = { scroll("STARS"), scroll("FORTUNE") }
  outcome = ns.Consumables.use(run, 1)
  T.eq(#outcome.created, 1, "one slot free")
  T.eq(outcome.created[1].kind, "tome")

  run = newRun()
  run.maxConsumables = 3
  run.consumables = { scroll("STARS"), scroll("FORTUNE"), scroll("FURY") }
  T.eq(#ns.Consumables.use(run, 1).created, 1)
  run.consumables = { scroll("STARS") }
  T.eq(#ns.Consumables.use(run, 1).created, 2)
end)

T.test("creator_disabled_from_pack_without_room", function()
  local run = newRun()
  run.consumables = { scroll("FORTUNE"), scroll("FURY") }
  local ok, reason = ns.Consumables.canApply(run, scroll("KNOWLEDGE"), {})
  T.ok(not ok)
  T.eq(reason, "No room")
end)

T.test("targeted_needs_hand", function()
  local run = newRun("shop")
  run.consumables = { scroll("FORTUNE") }
  local ok, reason = ns.Consumables.canUse(run, 1, { 1 })
  T.ok(not ok)
  T.eq(reason, "Select cards in a hand")
  T.eq(ns.Consumables.targetCards(run), nil)
  local hand = { { id = 1, rank = 5, suit = "S" } }
  run.shop = { openPack = { hand = hand } }
  T.eq(ns.Consumables.targetCards(run), hand)
  T.ok(ns.Consumables.canUse(run, 1, { 1 }))
  run = newRun("play")
  T.eq(ns.Consumables.targetCards(run), run.hand)
end)

T.test("selection_count_checked", function()
  local run = newRun("play")
  run.consumables = { scroll("FORTUNE"), scroll("UNDEATH") }
  local ok, reason = ns.Consumables.canUse(run, 1, {})
  T.ok(not ok)
  T.eq(reason, "Select 1 to 2 cards")
  ok = ns.Consumables.canUse(run, 1, { 1, 2, 3 })
  T.ok(not ok)
  ok, reason = ns.Consumables.canUse(run, 2, { 1 })
  T.ok(not ok)
  T.eq(reason, "Select 2 cards")
  ok = ns.Consumables.canUse(run, 2, { 1, 1 })
  T.ok(not ok)
  ok = ns.Consumables.canUse(run, 2, { 1, 99 })
  T.ok(not ok)
  T.ok(ns.Consumables.canUse(run, 1, { 2, 1 }))
end)

T.test("untargeted_phases", function()
  for _, phase in ipairs({ "play", "shop", "blind" }) do
    local run = newRun(phase)
    run.consumables = { scroll("GREED") }
    T.ok(ns.Consumables.canUse(run, 1), phase)
  end
  local run = newRun("lost")
  run.consumables = { scroll("GREED") }
  T.ok(not ns.Consumables.canUse(run, 1))
end)

T.test("trinket_reasons", function()
  local run = newRun()
  run.trinkets = {}
  local ok, reason = ns.Consumables.canApply(run, scroll("CHANCE"), {})
  T.ok(not ok)
  T.eq(reason, "No eligible trinket")
  run.trinkets = { { id = "BLOODLUST", ed = "FOIL" } }
  ok, reason = ns.Consumables.canApply(run, scroll("CHANCE"), {})
  T.eq(reason, "No eligible trinket")
  run.trinkets = {}
  for i = 1, 5 do run.trinkets[i] = { id = ns.Trinkets.order[i] } end
  ok, reason = ns.Consumables.canApply(run, scroll("SUMMONING"), {})
  T.ok(not ok)
  T.eq(reason, "No trinket slot")
  run.trinkets[1].ed = "NEGATIVE"
  T.ok(ns.Consumables.canApply(run, scroll("SUMMONING"), {}))
  ok, reason = ns.Consumables.canApply(newRun(), scroll("ECHOES"), {})
  T.ok(not ok)
  T.eq(reason, "Nothing to copy")
end)

T.test("tome_levels", function()
  local run = newRun()
  run.consumables = { tome("PAIR") }
  local outcome = ns.Consumables.use(run, 1)
  T.eq(run.handLevels.PAIR, 2)
  T.eq(#run.consumables, 0)
  T.eq(run.lastConsumable, tome("PAIR"))
  T.eq(outcome.gold, 0)
end)

T.test("use_removes_item_and_sets_last", function()
  local run = newRun("play")
  run.consumables = { scroll("FORTUNE") }
  local id = run.hand[1].id
  local outcome = ns.Consumables.use(run, 1, { 1 })
  T.eq(#run.consumables, 0)
  T.eq(run.lastConsumable, scroll("FORTUNE"))
  T.eq(outcome.changed, { id })
  T.eq(run.hand[1].enh, "LUCKY")
  T.eq(ns.Deck.find(run, id).enh, "LUCKY")
end)

T.test("sell_half", function()
  local run = newRun()
  run.consumables = { scroll("FORTUNE"), { kind = "relic", id = "X" } }
  T.eq(ns.Consumables.sell(run, 1), 1)
  T.eq(run.gold, 5)
  T.eq(#run.consumables, 1)
  T.eq(ns.Consumables.COST, { tome = 3, scroll = 3, relic = 4 })
  T.eq(ns.Consumables.sell(run, 5), 0)
end)

T.test("echoes_repeats_last", function()
  local run = newRun()
  run.lastConsumable = tome("FLUSH")
  run.consumables = { scroll("ECHOES") }
  local outcome = ns.Consumables.use(run, 1)
  T.eq(run.consumables, { tome("FLUSH") })
  T.eq(outcome.created, { tome("FLUSH") })
  T.eq(run.lastConsumable, tome("FLUSH"), "Echoes does not become the last")
  run.consumables = { scroll("ECHOES") }
  run.lastConsumable = scroll("GREED")
  ns.Consumables.use(run, 1)
  T.eq(run.consumables, { scroll("GREED") })
end)

T.test("random_excludes_hidden_tomes", function()
  local run = newRun()
  local seen = {}
  for _ = 1, 400 do
    local item = ns.Consumables.random(run, "tome")
    T.eq(item.kind, "tome")
    seen[item.id] = true
  end
  T.ok(not seen.FIVE_KIND and not seen.FLUSH_HOUSE and not seen.FLUSH_FIVE)
  T.ok(seen.PAIR and seen.STRAIGHT_FLUSH)
  run.seenHands.FIVE_KIND = true
  local found = false
  for _ = 1, 600 do
    if ns.Consumables.random(run, "tome").id == "FIVE_KIND" then found = true end
  end
  T.ok(found, "seen secret hands roll")
  T.eq(ns.Consumables.random(run, "scroll").kind, "scroll")
end)

T.test("add_card_goes_to_hand_or_pack", function()
  local run = newRun("play")
  local count = #run.hand
  local deckCount = #run.deck
  run.consumables = { scroll("FORTUNE") }
  local api
  local def = ns.Scrolls.def.FORTUNE
  local old = def.use
  def.use = function(_, _, a) api = a end
  ns.Consumables.use(run, 1, { 1 })
  def.use = old
  local card = api.addCard({ rank = 3, suit = "D" })
  T.eq(#run.hand, count + 1)
  T.eq(#run.deck, deckCount + 1)
  T.eq(run.hand[#run.hand], card)
  run.phase = "shop"
  run.shop = { openPack = { hand = {} } }
  local card2 = api.addCard({ rank = 4, suit = "D" })
  T.eq(run.shop.openPack.hand, { card2 })
  T.eq(#run.hand, count + 1)
end)

T.test("every_scroll_and_relic_has_an_affects_line", function()
  for _, set in ipairs({ { ns.Scrolls, "scroll" }, { ns.Relics, "relic" } }) do
    for _, id in ipairs(set[1].order) do
      local a = set[1].def[id].affects
      T.ok(type(a) == "string" and #a > 0 and #a <= 70, set[2] .. " " .. id .. " needs a short affects line")
    end
  end
end)
