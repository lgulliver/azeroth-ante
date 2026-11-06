local _, ns = ...

-- Resolves Blueprint/Brainstorm copying. Defs are looked up lazily so load order is free.
local TrinketEngine = {}

local function defOf(instance)
  return instance and ns.Trinkets.def[instance.id]
end

-- The instance and def whose hooks a slot runs, or nil when it has none to run.
-- Copiers (def.copies = "right" | "leftmost") follow their target; a visited set stops cycles.
function TrinketEngine.source(trinkets, slot)
  local visited = {}
  local current, viaCopy = slot, false
  while true do
    if visited[current] then return nil end
    visited[current] = true
    local instance = trinkets[current]
    local def = defOf(instance)
    if not def then return nil end
    if viaCopy and def.copyable == false then return nil end
    if not def.copies then return instance, def end
    current = (def.copies == "right") and (current + 1) or 1
    viaCopy = true
  end
end

-- fn(slot, instance, def, isCopy) for every slot whose source resolves, left to right.
function TrinketEngine.each(trinkets, fn)
  for slot = 1, #trinkets do
    local instance, def = TrinketEngine.source(trinkets, slot)
    if instance then fn(slot, instance, def, instance ~= trinkets[slot]) end
  end
end

ns.TrinketEngine = TrinketEngine
