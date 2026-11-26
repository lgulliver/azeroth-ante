local _, ns = ...

-- Held tags (run.tags, a list of ids) and the per-stage skip tags (run.blindTags[1..2]). Defs: Data/Tags.lua.
local Tags = ns.Tags

-- A tag the current stage allows, uniformly among the defs whose minStage it has reached.
function Tags.roll(run)
  local picks = {}
  for _, id in ipairs(Tags.order) do
    if (Tags.def[id].minStage or 1) <= run.stage then picks[#picks + 1] = id end
  end
  return ns.RNG.pick(run.rng, picks)
end

-- Rolls the tags the small and big blind give when skipped (at run start and each new stage).
function Tags.rollBlindTags(run)
  run.blindTags = { Tags.roll(run), Tags.roll(run) }
end

local function addOne(run, id)
  local at = #run.tags + 1
  run.tags[at] = id
  local def = Tags.def[id]
  if def and def.onTake and def.onTake(run) == true and run.tags[at] == id then
    table.remove(run.tags, at)
  end
end

-- Takes a tag: it joins the held tags, then its onTake runs; one returning true is spent at once.
-- Each held Bonus Roll (DOUBLE) is spent to take another copy (Balatro's Double; never of a DOUBLE).
function Tags.add(run, id)
  local copies = 1
  if id ~= "DOUBLE" then
    for i = #run.tags, 1, -1 do
      if run.tags[i] == "DOUBLE" then
        table.remove(run.tags, i)
        copies = copies + 1
      end
    end
  end
  for _ = 1, copies do addOne(run, id) end
end

-- Runs hook(run, ...) on each held tag, oldest first; a hook returning true consumes its tag.
-- Tags added by a hook wait for the next fire.
function Tags.fire(run, hook, ...)
  local i, left = 1, #run.tags
  while left > 0 and i <= #run.tags do
    left = left - 1
    local def = Tags.def[run.tags[i]]
    if def and def[hook] and def[hook](run, ...) == true then
      table.remove(run.tags, i)
    else
      i = i + 1
    end
  end
end
