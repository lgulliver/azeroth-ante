local ns, T = ...

local function bossRun()
  local run = ns.Run.new(7, "ADVENTURER")
  run.blind, run.bosses[1] = 3, "VANCLEEF"
  ns.Run.startBlind(run)
  run.hand = { ns.Deck.find(run, 1) } -- Spade, debuffed by VanCleef.
  return run
end

T.test("debuffed_held_gold_pays_nothing", function()
  for _, seal in ipairs({ "RED", "BLUE" }) do
    local run = bossRun()
    run.hand[1].enh, run.hand[1].seal = "GOLD", seal
    local gold = run.gold
    ns.Run.winBlind(run)
    T.eq(run.lastPayout.held, 0)
    T.eq(run.gold, gold + run.lastPayout.total)
    T.eq(run.lastPayout.total, run.lastPayout.reward + run.lastPayout.hands
      + run.lastPayout.interest + run.lastPayout.trinkets)
  end
end)

T.test("debuffed_held_blue_creates_nothing", function()
  local old = ns.Consumables
  ns.Consumables = {
    add = function(run, item)
      run.consumables[#run.consumables + 1] = item
    end,
  }
  local ok, err = pcall(function()
    local run = bossRun()
    run.hand[1].seal = "BLUE"
    run.lastHandId = "PAIR"
    ns.Run.winBlind(run)
    T.eq(run.consumables, {})
  end)
  ns.Consumables = old
  if not ok then error(err, 0) end
end)

for _, field in ipairs({ "deck", "hand", "pile" }) do
  T.test("load_rejects_non_table_" .. field, function()
    for _, value in ipairs({ false, 1, "corrupt" }) do
      local run = ns.Run.new(7, "ADVENTURER")
      run[field] = value
      local ok, loaded = pcall(ns.Save.load, { version = 2, run = run })
      T.ok(ok, "invalid " .. field .. " crashed Save.load: " .. tostring(loaded))
      T.eq(loaded, nil, "invalid " .. field)
    end
    local run = ns.Run.new(7, "ADVENTURER")
    run[field] = nil
    T.eq(ns.Save.load({ version = 2, run = run }), nil, "missing " .. field)
  end)
end

T.test("winning_glass_break_leaves_persistent_deck", function()
  local run = ns.Run.new(7, "ADVENTURER")
  ns.Run.startBlind(run)
  run.target = 1
  local card = run.hand[1]
  card.enh = "GLASS"
  run.rng = ns.RNG.new(0) -- First roll breaks Glass.
  local result = ns.Run.play(run, { 1 })
  T.eq(result.destroyed, { card.id })
  T.eq(run.phase, "shop")
  T.ok(run.score >= run.target)
  T.eq(#run.deck, 51)
  T.eq(ns.Deck.find(run, card.id), nil)
  for _, list in ipairs({ run.hand, run.pile }) do
    for _, remaining in ipairs(list) do T.ok(remaining.id ~= card.id) end
  end
end)
