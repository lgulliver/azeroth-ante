local _, ns = ...

-- Every chance roll goes through here so OOPS trinkets can double the odds.
local Prob = {}

function Prob.mult(trinkets)
  local n = 0
  for _, trinket in ipairs(trinkets or {}) do
    local def = ns.Trinkets.def[trinket.id]
    if def and def.rule == "OOPS" then n = n + 1 end
  end
  return 2 ^ n
end

-- Always draws exactly once, whatever the odds.
function Prob.roll(rng, trinkets, num, den)
  return ns.RNG.next(rng) < num * Prob.mult(trinkets) / den
end

function Prob.odds(trinkets, num)
  return num * Prob.mult(trinkets)
end

ns.Prob = Prob
