local ns, T = ...

T.test("same_seed_same_sequence", function()
  local a, b = ns.RNG.new(42), ns.RNG.new(42)
  for _ = 1, 10 do
    T.eq(ns.RNG.next(a), ns.RNG.next(b))
  end
end)

T.test("int_in_range", function()
  local r = ns.RNG.new(7)
  local seen = {}
  for _ = 1, 1000 do
    local v = ns.RNG.int(r, 1, 6)
    T.ok(v >= 1 and v <= 6 and v == math.floor(v), "out of range: " .. tostring(v))
    seen[v] = true
  end
  for v = 1, 6 do
    T.ok(seen[v], "never saw " .. v)
  end
end)

T.test("shuffle_is_permutation", function()
  local r = ns.RNG.new(123)
  local list = {}
  for i = 1, 52 do list[i] = i end
  ns.RNG.shuffle(r, list)
  T.eq(#list, 52)
  local sorted = {}
  for i = 1, 52 do sorted[i] = list[i] end
  table.sort(sorted)
  local identity = true
  for i = 1, 52 do
    T.eq(sorted[i], i)
    if list[i] ~= i then identity = false end
  end
  T.ok(not identity, "shuffle left the identity order")
end)

T.test("state_is_plain", function()
  local r = ns.RNG.new(99)
  T.eq(type(r.s), "number")
  T.ok(getmetatable(r) == nil, "rng has a metatable")
end)
