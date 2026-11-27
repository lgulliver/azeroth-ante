-- Usage: luajit tests/run.lua [pattern]   (run from the repo root)
local pattern = arg and arg[1]
local ns = {}

-- Load Core/ and Data/ files in TOC order.
local toc = assert(io.open("AzerothAnte/AzerothAnte.toc", "r"), "cannot open toc")
for line in toc:lines() do
  line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line ~= "" and line:sub(1, 1) ~= "#" then
    local path = line:gsub("\\", "/")
    if path:match("^Core/") or path:match("^Data/") then
      local chunk, err = loadfile("AzerothAnte/" .. path)
      if not chunk then
        print("LOAD ERROR " .. err)
        os.exit(1)
      end
      chunk("AzerothAnte", ns)
    end
  end
end
toc:close()

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepEq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. dump(x) end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

local T = {}
local queue = {}
function T.test(name, fn) queue[#queue + 1] = { name = name, fn = fn } end
function T.ok(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end
function T.eq(actual, expected, msg)
  if not deepEq(actual, expected) then
    error((msg and (msg .. ": ") or "") .. "expected " .. dump(expected) .. ", got " .. dump(actual), 2)
  end
end
-- The developer tools (tools/: the balance simulator, the texture generators) are kept out of git; a test
-- that needs them calls T.needSim() and is skipped where they are missing (CI, a fresh clone).
local SKIP = {}
local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end
T.hasSim = exists("tools/sim/bot.lua")
function T.needSim()
  if not T.hasSim then error(SKIP, 0) end
end
-- Starts a blind from whatever phase a test left the run in (Run.startBlind only starts one from
-- the blind screen, Run.canStart); an open pack still refuses it.
function T.startBlind(run)
  run.phase = "blind"
  return ns.Run.startBlind(run)
end

local files = {}
local ls = io.popen("ls tests/test_*.lua")
for f in ls:lines() do
  if not pattern or f:find(pattern, 1, true) then files[#files + 1] = f end
end
ls:close()

local passed, failed, skipped = 0, 0, 0
for _, f in ipairs(files) do
  queue = {}
  local chunk, err = loadfile(f)
  if not chunk then
    print("FAIL " .. f .. ": " .. err)
    failed = failed + 1
  else
    local ok, e = pcall(chunk, ns, T)
    if not ok then
      print("FAIL " .. f .. ": " .. tostring(e))
      failed = failed + 1
    end
    for _, t in ipairs(queue) do
      local ok2, e2 = pcall(t.fn)
      if not ok2 and e2 == SKIP then
        skipped = skipped + 1
        print("SKIP " .. f .. ": " .. t.name .. " (no tools/sim)")
      elseif ok2 then
        passed = passed + 1
        print("PASS " .. f .. ": " .. t.name)
      else
        failed = failed + 1
        print("FAIL " .. f .. ": " .. t.name .. ": " .. tostring(e2))
      end
    end
  end
end
print(passed .. " passed, " .. failed .. " failed" .. (skipped > 0 and (", " .. skipped .. " skipped") or ""))
if failed > 0 then os.exit(1) end
