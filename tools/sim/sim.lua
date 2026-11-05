-- Usage: luajit tools/sim/sim.lua [runs=200] [deckId=ROGUE] [seed=1]   (run from the repo root)
-- Plays `runs` full runs with a greedy bot and prints the win rate, stage histogram and mean final gold.
local runs = tonumber(arg and arg[1]) or 200
local deckId = (arg and arg[2]) or "ROGUE"
local baseSeed = tonumber(arg and arg[3]) or 1

local ns = {}
local toc = assert(io.open("AzerothAnte/AzerothAnte.toc", "r"), "cannot open toc")
for line in toc:lines() do
  line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line ~= "" and line:sub(1, 1) ~= "#" then
    local path = line:gsub("\\", "/")
    if path:match("^Core/") or path:match("^Data/") then
      assert(loadfile("AzerothAnte/" .. path))("AzerothAnte", ns)
    end
  end
end
toc:close()
assert(ns.Decks.def[deckId], "unknown deck " .. deckId)

-- Optional overrides for tuning: TARGETS="300,800,..." RAG=2
local targets = os.getenv("TARGETS")
if targets then
  local list = {}
  for n in targets:gmatch("%d+") do list[#list + 1] = tonumber(n) end
  ns.Run.BASE_TARGETS = list
end
if os.getenv("RAG") then ns.Bosses.def.RAGNAROS.targetMult = tonumber(os.getenv("RAG")) end

local bot = dofile("tools/sim/bot.lua")(ns)
local wins, goldSum, reached = 0, 0, {}
for i = 1, runs do
  -- Spread seeds out: Park-Miller gives tiny first outputs for small seeds.
  local run = ns.Run.new(baseSeed * 104729 + i * 7919, deckId)
  if bot.playRun(run) then wins = wins + 1 end
  goldSum = goldSum + run.gold
  if run.phase ~= "won" then
    local key = string.format("%d.%d", run.stage, run.blind)
    reached[key] = (reached[key] or 0) + 1
  end
end

print(string.format("deck %s, %d runs, seed %d", deckId, runs, baseSeed))
print(string.format("wins %d/%d (%.1f%%)", wins, runs, wins / runs * 100))
local keys = {}
for k in pairs(reached) do keys[#keys + 1] = k end
table.sort(keys, function(a, b)
  local sa, ba = a:match("(%d+)%.(%d+)")
  local sb, bb = b:match("(%d+)%.(%d+)")
  sa, ba, sb, bb = tonumber(sa), tonumber(ba), tonumber(sb), tonumber(bb)
  if sa ~= sb then return sa < sb end
  return ba < bb
end)
print("lost at stage.blind:")
for _, k in ipairs(keys) do print(string.format("  %s  %d", k, reached[k])) end
print(string.format("mean final gold %.1f", goldSum / runs))
