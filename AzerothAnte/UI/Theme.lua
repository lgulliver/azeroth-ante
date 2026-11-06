local _, ns = ...

ns.UI = ns.UI or {}

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local FLAT = "Interface\\Buttons\\WHITE8x8"

local Theme = {
  gold = { 1, 0.82, 0 },
  goldBright = { 1, 0.82, 0.29 },           -- #ffd24a: selection, titles, hover
  goldMuted = { 0.541, 0.416, 0.165 },      -- #8a6a2a: frame and button borders
  goldDim = { 0.541, 0.416, 0.165, 0.45 },  -- section rules
  parchment = { 0.91, 0.85, 0.69 },         -- #e8d9b0: values
  label = { 0.604, 0.541, 0.408 },          -- #9a8a68: small dim labels
  bg = { 0.071, 0.051, 0.035, 0.98 },       -- #120d09: the window
  frameLine = { 0.227, 0.165, 0.071 },      -- #3a2a12: 1px line inside the gold border
  insetFill = { 0.114, 0.082, 0.055, 1 },   -- #1d150e: set-in panels
  insetBorder = { 0.227, 0.165, 0.078 },    -- #3a2a14
  raisedFill = { 0.153, 0.11, 0.071, 1 },   -- #271c12: tiles
  titleTop = { 0.165, 0.118, 0.071 },       -- #2a1e12
  titleBottom = { 0.094, 0.067, 0.039 },    -- #18110a
  -- Chips and mult: filled tiles, a vertical gradient each, no outline.
  chips = { 0.2, 0.55, 1 },
  mult = { 1, 0.25, 0.2 },
  tiles = {
    chips = { top = { 0.122, 0.29, 0.525 }, bottom = { 0.086, 0.216, 0.384 }, text = { 0.812, 0.886, 1 } },
    mult = { top = { 0.541, 0.141, 0.125 }, bottom = { 0.392, 0.102, 0.09 }, text = { 1, 0.839, 0.816 } },
  },
  buttons = {
    default = { fill = { 0.153, 0.11, 0.071 }, border = { 0.541, 0.416, 0.165 }, text = { 1, 0.82, 0.29 } },
    primary = { fill = { 0.31, 0.225, 0.085 }, border = { 0.78, 0.6, 0.22 }, text = { 1, 0.88, 0.45 } },
    danger = { fill = { 0.2, 0.09, 0.07 }, border = { 0.66, 0.28, 0.22 }, text = { 0.95, 0.5, 0.42 } },
  },
  rarity = {
    common = { 1, 1, 1 },
    uncommon = { 0.12, 1, 0 },
    rare = { 0, 0.44, 0.87 },
    legendary = { 1, 0.5, 0 },
  },
  fonts = {
    title = "GameFontNormalLarge",
    text = "GameFontHighlight",
    small = "GameFontHighlightSmall",
    big = "GameFontNormalHuge",
  },
  -- Fixed design size; all layout is in these units and scaled to the window.
  -- Card textures are 128x256 with the card in the top 128x179 (5:7).
  cardV = 179 / 256,
  width = 900,
  height = 560,
  sidebarFraction = 0.28,
  margin = 8,
  titleHeight = 32,
  media = { shadow = MEDIA .. "UI_Shadow", gradient = MEDIA .. "UI_Gradient", flat = FLAT },
}

-- Applies an {r, g, b[, a]} colour to a texture or font string.
function Theme.setColor(region, c, isTexture)
  if isTexture then
    region:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  else
    region:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  end
end

---------------------------------------------------------------------------
-- Pixel-perfect edges. The window canvas is scaled (window size / 900x560) on
-- top of UIParent's scale, so one design unit is often less than one physical
-- pixel and the engine's pixel snapping drops or thins a 1-unit line. Every
-- themed edge is therefore sized max(1 physical pixel, its design thickness),
-- registered here, and re-sized whenever the scale changes.

-- Design units equal to exactly one physical pixel for `region`. Every API is
-- guarded: GetPhysicalScreenSize may be missing on Forever, so it falls back to
-- GetScreenHeight() * UIParent's effective scale, then to 1 unit.
function Theme.Pixel(region)
  local height
  if type(GetPhysicalScreenSize) == "function" then
    local _, h = GetPhysicalScreenSize()
    height = h
  end
  if type(height) ~= "number" or height <= 0 then
    height = nil
    if type(GetScreenHeight) == "function" and UIParent and UIParent.GetEffectiveScale then
      local sh, us = GetScreenHeight(), UIParent:GetEffectiveScale()
      if type(sh) == "number" and type(us) == "number" then height = sh * us end
    end
  end
  local scale = region and region.GetEffectiveScale and region:GetEffectiveScale()
  if type(height) ~= "number" or height <= 0 or type(scale) ~= "number" or scale <= 0 then return 1 end
  return 768 / height / scale
end

-- texture -> { axis = "w" | "h", thickness = design units }. Weak keys; nothing per frame.
local edgeRegistry = setmetatable({}, { __mode = "k" })
Theme.edgeRegistry = edgeRegistry

local function applyEdge(t, info)
  local v = math.max(Theme.Pixel(t:GetParent() or t), info.thickness)
  if info.axis == "w" then t:SetWidth(v) else t:SetHeight(v) end
end

-- Makes `t` a themed edge line: `axis` is the dimension it is thin in ("w" for
-- a vertical line, "h" for a horizontal one).
function Theme.Edge(t, axis, thickness)
  if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
  if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
  local info = { axis = axis, thickness = thickness }
  edgeRegistry[t] = info
  applyEdge(t, info)
  return t
end

function Theme.RefreshEdges()
  for t, info in pairs(edgeRegistry) do applyEdge(t, info) end
end

local scaleWatcher = CreateFrame("Frame")
scaleWatcher:SetScript("OnEvent", function() Theme.RefreshEdges() end)
for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
  pcall(scaleWatcher.RegisterEvent, scaleWatcher, e)
end

-- The look of an empty trinket or consumable slot: a dark inset with a thin,
-- soft gold outline at low alpha. One helper so both rows match. The returned
-- frame fills `parent`; Show/Hide it as the slot empties and fills.
Theme.emptySlotEdgeAlpha = 0.28
function Theme.EmptySlot(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(parent)
  f.isEmptySlot = true
  local inset = f:CreateTexture(nil, "BACKGROUND")
  inset:SetAllPoints(f)
  inset:SetColorTexture(0.04, 0.03, 0.02, 0.6)
  local g, a = Theme.goldMuted, Theme.emptySlotEdgeAlpha
  local function edge(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetPoint(p1, f, p1, 0, 0)
    t:SetPoint(p2, f, p2, 0, 0)
    t:SetColorTexture(g[1], g[2], g[3], a)
    Theme.Edge(t, w and "w" or "h", w or h)
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 1)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
  return f
end


---------------------------------------------------------------------------
-- Window chrome: dark leather and gold. Everything is built from flat colour
-- textures plus the generated UI_Gradient / UI_Shadow media, tinted with
-- SetVertexColor. Texture:SetGradient is deliberately not used (its signature
-- differs between client generations). Each helper is idempotent.

local function flat(frame, layer, sub, c, a)
  local t = frame:CreateTexture(nil, layer, nil, sub or 0)
  t:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
  return t
end

-- Four 1px (or w px) edge textures hugging `frame`, `grow` px outside it.
local function edges(frame, layer, sub, c, a, w, grow)
  w, grow = w or 1, grow or 0
  local list = {}
  local function edge(p1, p2, width, height)
    local t = flat(frame, layer, sub, c, a)
    t:SetPoint(p1, frame, p1, p1:find("LEFT") and -grow or grow, p1:find("TOP") and grow or -grow)
    t:SetPoint(p2, frame, p2, p2:find("LEFT") and -grow or grow, p2:find("TOP") and grow or -grow)
    Theme.Edge(t, width and "w" or "h", width or height)
    list[#list + 1] = t
  end
  edge("TOPLEFT", "TOPRIGHT", nil, w)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, w)
  edge("TOPLEFT", "BOTTOMLEFT", w, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", w, nil)
  return list
end

-- A soft shadow (UI_Shadow tinted) `grow` px outside the frame.
local function shadow(frame, color, alpha, grow, drop)
  local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  t:SetTexture(Theme.media.shadow)
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", -grow, grow - (drop or 0))
  t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", grow, -grow - (drop or 0))
  t:SetVertexColor(color[1], color[2], color[3], alpha)
  return t
end

-- A vertical ramp (UI_Gradient: opaque at its top edge) tinted `c` at `a`.
-- flip makes it opaque at the bottom edge instead.
local function ramp(frame, layer, sub, c, a, flip)
  local t = frame:CreateTexture(nil, layer, nil, sub or 0)
  t:SetTexture(Theme.media.gradient)
  if flip then t:SetTexCoord(0, 1, 1, 0) else t:SetTexCoord(0, 1, 0, 1) end
  t:SetVertexColor(c[1], c[2], c[3], a)
  return t
end

-- The main window: 2px muted gold border, 1px dark line just inside it, a soft
-- drop shadow. The border sits on its own click-through child above the
-- content so nothing inside covers it.
function Theme.Frame(frame)
  if frame.themeFrame then return frame.chrome end
  frame.themeFrame = true
  local fill = flat(frame, "BACKGROUND", 0, Theme.bg)
  fill:SetAllPoints(frame)
  frame.fill = fill
  frame.shadow = shadow(frame, { 0, 0, 0 }, 0.7, 16, 4)
  local chrome = CreateFrame("Frame", nil, frame)
  chrome:SetAllPoints(frame)
  chrome:SetFrameLevel(frame:GetFrameLevel() + 2000)
  chrome:EnableMouse(false)
  local inner = CreateFrame("Frame", nil, chrome)
  inner:SetPoint("TOPLEFT", chrome, "TOPLEFT", 2, -2)
  inner:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -2, 2)
  chrome.border = edges(chrome, "OVERLAY", 1, Theme.goldMuted, 1, 2, 0)
  chrome.line = edges(inner, "OVERLAY", 0, Theme.frameLine, 1, 1, 0)
  frame.chrome = chrome
  return chrome
end

-- The title bar: a gradient (lighter at the top) with a thin gold rule under it.
-- `bar` is any frame; `span` (optional) is the frame whose full width it covers.
function Theme.TitleBar(bar, span)
  if bar.themeTitleBar then return end
  bar.themeTitleBar = true
  span = span or bar
  local base = flat(bar, "BACKGROUND", 1, Theme.titleBottom)
  base:SetPoint("TOPLEFT", span, "TOPLEFT", 0, 0)
  base:SetPoint("TOPRIGHT", span, "TOPRIGHT", 0, 0)
  base:SetHeight(Theme.titleHeight)
  local top = ramp(bar, "BACKGROUND", 2, Theme.titleTop, 1)
  top:SetPoint("TOPLEFT", span, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", span, "TOPRIGHT", 0, 0)
  top:SetHeight(Theme.titleHeight)
  local rule = flat(bar, "BORDER", 0, Theme.goldMuted)
  rule:SetPoint("TOPLEFT", span, "TOPLEFT", 0, -Theme.titleHeight)
  rule:SetPoint("TOPRIGHT", span, "TOPRIGHT", 0, -Theme.titleHeight)
  Theme.Edge(rule, "h", 1)
  bar.rule = rule
end

-- A set-in panel: darker fill, a soft inner shadow along the top, and a 1px very
-- dark border. No bright outline. frame.insetFillColor records the fill.
function Theme.Inset(frame)
  if frame.themeInset then return frame end
  frame.themeInset = true
  local c = Theme.insetFill
  frame.insetFillColor = { c[1], c[2], c[3], c[4] or 1 }
  local fill = flat(frame, "BACKGROUND", -7, c)
  fill:SetAllPoints(frame)
  frame.insetFill = fill
  frame.themeEdges = edges(frame, "BORDER", 0, Theme.insetBorder, 1, 1, 0)
  local inner = ramp(frame, "BORDER", -1, { 0, 0, 0 }, 0.55)
  inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  inner:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  inner:SetHeight(8)
  frame.insetShade = inner
  return frame
end

-- A raised tile: lighter fill, a faint top highlight and a soft drop shadow.
function Theme.Raised(frame)
  if frame.themeRaised then return frame end
  frame.themeRaised = true
  frame.raisedShadow = shadow(frame, { 0, 0, 0 }, 0.55, 6, 2)
  local fill = flat(frame, "BACKGROUND", -7, Theme.raisedFill)
  fill:SetAllPoints(frame)
  frame.raisedFill = fill
  local hi = flat(frame, "BORDER", 0, { 1, 1, 1 }, 0.07)
  hi:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  hi:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  Theme.Edge(hi, "h", 1)
  frame.raisedHighlight = hi
  return frame
end

-- The selected or current item: a thin gold outline and a soft gold glow.
function Theme.Selected(frame, on)
  if not frame.selectedGlow then
    frame.selectedGlow = shadow(frame, Theme.goldBright, 0.4, 8, 0)
    frame.selectedEdges = edges(frame, "OVERLAY", 2, Theme.goldBright, 1, 1, 0)
  end
  frame.themeSelected = on and true or false
  frame.selectedGlow:SetShown(on and true or false)
  for _, t in ipairs(frame.selectedEdges) do t:SetShown(on and true or false) end
  return frame
end

-- A small label: dim parchment. (Fonts cannot be letter-spaced in the client.)
function Theme.Label(fs)
  fs.themeLabel = true
  fs:SetTextColor(Theme.label[1], Theme.label[2], Theme.label[3], 1)
  return fs
end

-- A value: parchment, or gold.
function Theme.Value(fs, gold)
  fs.themeValue = gold and "gold" or "parchment"
  local c = gold and Theme.goldBright or Theme.parchment
  fs:SetTextColor(c[1], c[2], c[3], 1)
  return fs
end

-- A thin dim gold rule across `parent` at y (from its top), inset by `pad`.
function Theme.Rule(parent, y, pad)
  pad = pad or Theme.margin
  local t = flat(parent, "BORDER", 1, Theme.goldDim)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
  t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, y)
  Theme.Edge(t, "h", 1)
  t.isRule = true
  return t
end

-- A chips or mult tile: vertical gradient fill, small bottom inner shadow, and
-- NO outline (frame.themeEdges stays nil). kind is "chips" or "mult".
function Theme.Tile(frame, kind)
  if frame.themeTile then return frame end
  local spec = Theme.tiles[kind]
  frame.themeTile = kind
  local base = flat(frame, "BACKGROUND", 0, spec.bottom)
  base:SetAllPoints(frame)
  local top = ramp(frame, "BACKGROUND", 1, spec.top, 1)
  top:SetAllPoints(frame)
  local lip = flat(frame, "BORDER", 0, { 0, 0, 0 }, 0.27)
  lip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  lip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  Theme.Edge(lip, "h", 2)
  frame.tileText = spec.text
  return frame
end

-- Widens `btn` so its label (plus `pad` on each side) fits. It only widens: the
-- width the layout gave the button is the floor, and it returns to that floor
-- when a shorter label is set. Anchors are untouched, so the button grows away
-- from its anchored side.
function Theme.FitButton(btn, pad)
  local label = btn.label
  if not label or not label.GetStringWidth then return btn end
  local w = btn:GetWidth()
  if btn.fitWidth and w == btn.fitWidth then w = btn.fitBase end
  local target = math.max(w, math.ceil(label:GetStringWidth() + 2 * (pad or 8)))
  if target ~= btn:GetWidth() then btn:SetWidth(target) end
  btn.fitBase, btn.fitWidth = w, target
  return btn
end

-- Themed button states. The look is textures only, so it never needs the stock template.
local function buttonRefresh(b)
  local v = Theme.buttons[b.themeButton]
  local enabled = b:IsEnabled()
  if not enabled then
    b.pressed = false
  elseif b.wasDisabled then
    b.hover = b:IsMouseOver() -- the cursor may have moved while it was disabled
  end
  b.wasDisabled = not enabled
  local border, text, fill = v.border, v.text, v.fill
  local k = 1
  if not enabled then
    k = 0.45
    text = { v.text[1] * 0.55, v.text[2] * 0.55, v.text[3] * 0.55 }
  elseif b.pressed then
    k = 0.7
  elseif b.hover then
    border = { math.min(1, border[1] * 1.3 + 0.1), math.min(1, border[2] * 1.3 + 0.1), math.min(1, border[3] * 1.3 + 0.1) }
    text = { math.min(1, text[1] + 0.12), math.min(1, text[2] + 0.12), math.min(1, text[3] + 0.12) }
    k = 1.15
  end
  b.themeState = (not enabled and "disabled") or (b.pressed and "pressed") or (b.hover and "hover") or "normal"
  for _, t in ipairs(b.themeEdges) do
    t:SetColorTexture(border[1], border[2], border[3], enabled and 1 or 0.5)
  end
  b.fillTex:SetColorTexture(fill[1] * k, fill[2] * k, fill[3] * k, 1)
  b.highlight:SetShown(enabled and not b.pressed)
  b.label:SetTextColor(text[1], text[2], text[3], 1)
  b.label:ClearAllPoints()
  b.label:SetPoint("CENTER", b, "CENTER", 0, b.pressed and -1 or 0)
end

-- Gives a plain Button (no template) the themed look. variant: nil (default raised
-- fill, gold text), "primary" (warmer gold-tinted fill for the main action) or
-- "danger" (subdued red: text 6.3:1 on its fill, border 3.1:1 on the inset panel). Hover brightens, pressed insets, disabled dims.
function Theme.Button(btn, variant)
  variant = variant or "default"
  if btn.themeButton then
    btn.themeButton = variant
    buttonRefresh(btn)
    return btn
  end
  btn.themeButton = variant
  btn.fillTex = flat(btn, "BACKGROUND", 0, Theme.raisedFill)
  btn.fillTex:SetAllPoints(btn)
  btn.highlight = flat(btn, "BORDER", 0, { 1, 1, 1 }, 0.08)
  btn.highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
  btn.highlight:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
  Theme.Edge(btn.highlight, "h", 1)
  btn.themeEdges = edges(btn, "BORDER", 1, Theme.goldMuted, 1, 1, 0)
  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  btn:SetFontString(btn.label)
  btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
  local setText = btn.SetText
  btn.SetText = function(self, text)
    setText(self, text)
    Theme.FitButton(self)
  end
  btn:HookScript("OnEnter", function(self) self.hover = true; buttonRefresh(self) end)
  btn:HookScript("OnLeave", function(self) self.hover, self.pressed = false, false; buttonRefresh(self) end)
  btn:HookScript("OnMouseDown", function(self) self.pressed = true; buttonRefresh(self) end)
  btn:HookScript("OnMouseUp", function(self) self.pressed = false; buttonRefresh(self) end)
  btn:HookScript("OnHide", function(self) self.hover, self.pressed = false, false end)
  btn:HookScript("OnEnable", buttonRefresh)
  btn:HookScript("OnDisable", buttonRefresh)
  buttonRefresh(btn)
  return btn
end

-- Creates a themed button in one call.
function Theme.NewButton(parent, label, w, h, variant)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h or 26)
  Theme.Button(b, variant)
  if label then b:SetText(label) end
  return b
end

ns.UI.Theme = Theme
