-- Shared by trinket tests: local H = loadfile("tests/trinket_helper.lua")(ns, T)
local ns, T = ...

local H = {}
local nextCardId = 1000

-- A fresh run in the play phase. opts.trinkets = { ids }, opts.gold.
function H.run(opts)
  opts = opts or {}
  local run = ns.Run.new(1, "ROGUE")
  run.phase = "play"
  if opts.gold then run.gold = opts.gold end
  for _, id in ipairs(opts.trinkets or {}) do
    run.trinkets[#run.trinkets + 1] = ns.Trinkets.create(run, id)
  end
  return run
end

function H.card(rank, suit, enh, ed, seal)
  nextCardId = nextCardId + 1
  return { id = nextCardId, rank = rank, suit = suit or "S", enh = enh, ed = ed, seal = seal }
end

-- Scores without touching the run, with a ctx shaped like Run.play's.
function H.score(run, cards, held, overrides)
  return ns.Scoring.score(ns.Run.scoreCtx(run, cards, held, overrides))
end

-- Registers stub defs; H.cleanup() removes them again.
local stubs = {}
function H.stub(def)
  def.name, def.rarity, def.cost = def.name or def.id, def.rarity or "common", def.cost or 1
  ns.Trinkets.add(def)
  stubs[#stubs + 1] = def.id
end

function H.cleanup()
  for _, id in ipairs(stubs) do
    ns.Trinkets.def[id] = nil
    for i, o in ipairs(ns.Trinkets.order) do
      if o == id then table.remove(ns.Trinkets.order, i) break end
    end
  end
  stubs = {}
end

-- T.test wrapper that always cleans the stubs.
function H.test(name, fn)
  T.test(name, function()
    local ok, err = pcall(fn)
    H.cleanup()
    if not ok then error(err, 0) end
  end)
end

return H
