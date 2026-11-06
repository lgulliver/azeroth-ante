local _, ns = ...

-- Rule trinkets set def.rule; other systems ask whether any owned instance carries it.
local TrinketRules = {}

function TrinketRules.set(trinkets)
  local rules = {}
  for _, trinket in ipairs(trinkets or {}) do
    local def = ns.Trinkets.def[trinket.id]
    if def and def.rule then rules[def.rule] = true end
  end
  return rules
end

function TrinketRules.has(trinkets, rule)
  return TrinketRules.set(trinkets)[rule] == true
end

-- How many owned instances carry `rule` (Chaos grants one free reroll per copy).
function TrinketRules.count(trinkets, rule)
  local n = 0
  for _, trinket in ipairs(trinkets or {}) do
    local def = ns.Trinkets.def[trinket.id]
    if def and def.rule == rule then n = n + 1 end
  end
  return n
end

ns.TrinketRules = TrinketRules
