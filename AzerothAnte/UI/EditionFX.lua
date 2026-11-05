local _, ns = ...

ns.UI = ns.UI or {}

-- Edition shimmer for cards and trinket icons. Each attached frame gets a
-- clipped overlay child (created once, reused). One shared OnUpdate driver
-- animates them and runs only while at least one visible animated frame
-- exists: a hidden window or a card-free screen costs nothing per frame.
local EditionFX = {}

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local CYCLE, SWEEP = 2.5, 1.0   -- Foil: a glint every 2.5s, crossing in 1s
local TWO_PI = 2 * math.pi

local driver = CreateFrame("Frame")
local attached = {}   -- active fx records
local clock = 0
local attachCount = 0

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function hue(h)
  return clamp01(math.abs(h * 6 - 3) - 1), clamp01(2 - math.abs(h * 6 - 2)), clamp01(2 - math.abs(h * 6 - 4))
end

-- Per-edition animation steps; t already includes the frame's phase offset.
local STEP = {}

function STEP.FOIL(fx, t)
  local p = t % CYCLE
  if p >= SWEEP then
    if fx.sweeping then
      fx.sheen:Hide()
      fx.sweeping = false
    end
    return
  end
  if not fx.sweeping then
    fx.sheen:Show()
    fx.sweeping = true
  end
  local k = p / SWEEP
  fx.sheen:SetAlpha(0.15 + 0.5 * math.sin(math.pi * k))
  fx.sheen:SetPoint("CENTER", fx.root, "CENTER", (k * k * (3 - 2 * k) * 2 - 1) * fx.w, 0)
end

function STEP.HOLO(fx, t)
  fx.holo:SetAlpha(0.3 + 0.14 * math.sin(t * TWO_PI / 3.2))
  fx.holo:SetPoint("CENTER", fx.root, "CENTER", fx.w * 0.14 * math.sin(t * TWO_PI / 5.5), 0)
end

function STEP.POLY(fx, t)
  fx.holo:SetVertexColor(hue((t / 4) % 1))
  fx.holo:SetPoint("CENTER", fx.root, "CENTER", fx.w * 0.14 * math.sin(t * TWO_PI / 5.5), 0)
end

local function refresh()
  for i = 1, #attached do
    local fx = attached[i]
    if fx.animated and fx.root:IsVisible() then
      driver:SetScript("OnUpdate", EditionFX.onUpdate)
      return
    end
  end
  driver:SetScript("OnUpdate", nil)
end

function EditionFX.onUpdate(_, dt)
  clock = clock + dt
  local any = false
  for i = 1, #attached do
    local fx = attached[i]
    if fx.animated and fx.root:IsVisible() then
      any = true
      STEP[fx.ed](fx, clock + fx.phase)
    end
  end
  if not any then driver:SetScript("OnUpdate", nil) end
end

local function create(frame)
  local root = CreateFrame("Frame", nil, frame)
  root:SetAllPoints(frame)
  root:SetClipsChildren(true) -- a sweep never draws outside its card
  root:SetFrameLevel(frame:GetFrameLevel() + 1)
  local fx = { frame = frame, root = root }

  fx.tint = root:CreateTexture(nil, "BACKGROUND")
  fx.tint:SetAllPoints(root)
  fx.tint:SetTexture(MEDIA .. "Face_Plain") -- rounded, so the tint follows the card corners
  fx.tint:SetVertexColor(0.1, 0.08, 0.35)
  fx.tint:SetAlpha(0.5)
  fx.tint:Hide()

  fx.sheen = root:CreateTexture(nil, "OVERLAY")
  fx.sheen:SetTexture(MEDIA .. "Ed_Sheen")
  fx.sheen:SetBlendMode("ADD")
  fx.sheen:SetVertexColor(0.85, 0.95, 1)
  fx.sheen:Hide()

  fx.holo = root:CreateTexture(nil, "OVERLAY")
  fx.holo:SetTexture(MEDIA .. "Ed_Holo")
  fx.holo:SetBlendMode("ADD")
  fx.holo:Hide()

  frame:HookScript("OnShow", refresh)
  frame:HookScript("OnHide", refresh)
  return fx
end

function EditionFX.Attach(frame, ed)
  if not ed or not STEP[ed] and ed ~= "NEGATIVE" then
    EditionFX.Detach(frame)
    return
  end
  local fx = frame.fx
  if fx and fx.active and fx.ed == ed then
    refresh()
    return
  end
  fx = fx or create(frame)
  frame.fx = fx
  local fresh = not fx.active
  fx.ed, fx.active, fx.sweeping = ed, true, false
  fx.w, fx.h = frame:GetSize()
  fx.animated = ed ~= "NEGATIVE"
  fx.tint:Hide()
  fx.sheen:Hide()
  fx.holo:Hide()
  if fresh then
    fx.phase = (attachCount * 0.37) % CYCLE -- neighbours do not glint in lockstep
    attachCount = attachCount + 1
    attached[#attached + 1] = fx
  end

  if ed == "FOIL" then
    fx.sheen:SetSize(fx.w, fx.h)
  elseif ed == "HOLO" or ed == "POLY" then
    fx.holo:SetSize(fx.w * 1.3, fx.h)
    fx.holo:SetVertexColor(1, 1, 1)
    fx.holo:SetAlpha(ed == "POLY" and 0.42 or 0.3)
    fx.holo:Show()
  else
    fx.tint:Show()
  end
  if fx.animated then STEP[ed](fx, clock + fx.phase) end
  fx.root:Show()
  refresh()
end

function EditionFX.Detach(frame)
  local fx = frame.fx
  if not fx or not fx.active then return end
  fx.active, fx.ed = false, nil
  fx.tint:Hide()
  fx.sheen:Hide()
  fx.holo:Hide()
  fx.root:Hide()
  for i = #attached, 1, -1 do
    if attached[i] == fx then table.remove(attached, i) end
  end
  refresh()
end

-- Face-down cards must not shimmer.
function EditionFX.SetShown(frame, shown)
  local fx = frame.fx
  if fx and fx.active then
    fx.root:SetShown(shown)
    refresh()
  end
end

-- Restarts the driver after a window re-show (OnShow hooks do this in game).
function EditionFX.Wake()
  refresh()
end

function EditionFX.IsRunning()
  return driver:GetScript("OnUpdate") ~= nil
end

ns.UI.EditionFX = EditionFX
