local _, ns = ...

ns.UI = ns.UI or {}

-- One shared OnUpdate driver. The script is set only while tweens exist and
-- cleared when the last one finishes. Ease-out cubic.
local Tween = {}

local driver = CreateFrame("Frame")
local active = {}   -- array of records
local byFrame = {}  -- frame -> record (one tween per frame)

local function safe(fn)
  if not fn then return end
  local ok, err = pcall(fn)
  if not ok then geterrorhandler()(err) end
end

local function ease(t)
  local u = 1 - t
  return 1 - u * u * u
end

local function lerp(a, b, k)
  return a + (b - a) * k
end

local function apply(r, k)
  local f = r.frame
  if r.hasPos then
    r.cx, r.cy = lerp(r.x0, r.x1, k), lerp(r.y0, r.y1, k)
    f:SetPoint(r.point, r.rel, r.relPoint, r.cx, r.cy)
  end
  if r.a1 then
    r.ca = lerp(r.a0, r.a1, k)
    f:SetAlpha(r.ca)
  end
  if r.s1 then
    r.cs = lerp(r.s0, r.s1, k)
    f:SetScale(r.cs)
  end
  if r.w1 then
    r.cw = lerp(r.w0, r.w1, k)
    f:SetWidth(r.cw)
  end
end

local function remove(r)
  byFrame[r.frame] = nil
  for i = #active, 1, -1 do
    if active[i] == r then
      table.remove(active, i)
      break
    end
  end
  if #active == 0 then driver:SetScript("OnUpdate", nil) end
end

local function onUpdate(_, dt)
  local finished
  for i = #active, 1, -1 do
    local r = active[i]
    r.t = r.t + dt
    if r.t >= 0 then
      local k = r.t / r.dur
      if k >= 1 then
        apply(r, 1)
        table.remove(active, i)
        byFrame[r.frame] = nil
        if r.onDone then
          finished = finished or {}
          finished[#finished + 1] = r.onDone
        end
      else
        apply(r, ease(k))
      end
    end
  end
  if #active == 0 then driver:SetScript("OnUpdate", nil) end
  -- Callbacks run last (each isolated), so they may start new tweens safely.
  if finished then
    for i = #finished, 1, -1 do safe(finished[i]) end
  end
end

-- Tweens the first anchor offset (x, y), alpha, scale and/or width of `frame`.
-- `to` = { x =, y =, alpha =, scale =, width = }; any key may be omitted. A new tween on
-- a frame replaces its running one (continuing from the current values; the
-- replaced tween's onDone is not called; its onCancel is). `delay` seconds
-- before it starts. `onCancel` runs if this tween is replaced or cancelled.
function Tween.To(frame, to, duration, onDone, delay, onCancel)
  local old = byFrame[frame]
  local r = { frame = frame, dur = duration or 0, onDone = onDone, onCancel = onCancel, t = -(delay or 0) }
  if old then
    r.point, r.rel, r.relPoint = old.point, old.rel, old.relPoint
    r.cx, r.cy, r.ca, r.cs, r.cw = old.cx, old.cy, old.ca, old.cs, old.cw
    remove(old)
    safe(old.onCancel)
  end

  if to.x or to.y then
    if not r.point then
      local point, rel, relPoint, x, y = frame:GetPoint(1)
      if point then r.point, r.rel, r.relPoint, r.cx, r.cy = point, rel, relPoint, x, y end
    end
    if r.point then
      r.hasPos = true
      r.x0, r.y0 = r.cx or 0, r.cy or 0
      r.x1, r.y1 = to.x or r.x0, to.y or r.y0
    end
  end
  if to.alpha then
    r.a0, r.a1 = r.ca or frame:GetAlpha(), to.alpha
  end
  if to.scale then
    r.s0, r.s1 = r.cs or frame:GetScale(), to.scale
  end
  if to.width then
    r.w0, r.w1 = r.cw or frame:GetWidth(), to.width
  end

  if r.dur <= 0 and r.t >= 0 then
    apply(r, 1)
    safe(onDone)
    return
  end
  if r.dur <= 0 then r.dur = 0.0001 end

  byFrame[frame] = r
  active[#active + 1] = r
  driver:SetScript("OnUpdate", onUpdate)
end

-- Stops a frame's tween where it is; onDone is not called.
function Tween.Cancel(frame)
  local r = byFrame[frame]
  if r then
    remove(r)
    safe(r.onCancel)
  end
end

function Tween.IsActive(frame)
  return byFrame[frame] ~= nil
end

function Tween.Count()
  return #active
end

ns.UI.Tween = Tween
