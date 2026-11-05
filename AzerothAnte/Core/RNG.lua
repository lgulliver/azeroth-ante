local _, ns = ...

-- Park-Miller minimal standard generator. State is a plain number, exact in doubles.
local RNG = {}

local MOD = 2147483647

function RNG.new(seed)
  return { s = (seed % (MOD - 1)) + 1 }
end

function RNG.next(r)
  r.s = (16807 * r.s) % MOD
  return (r.s - 1) / (MOD - 1)
end

-- Inclusive integer in [lo, hi].
function RNG.int(r, lo, hi)
  return lo + math.floor(RNG.next(r) * (hi - lo + 1))
end

-- In-place Fisher-Yates.
function RNG.shuffle(r, list)
  for i = #list, 2, -1 do
    local j = RNG.int(r, 1, i)
    list[i], list[j] = list[j], list[i]
  end
end

function RNG.pick(r, list)
  return list[RNG.int(r, 1, #list)]
end

ns.RNG = RNG
