-- Permissive WoW API stub for the headless UI smoke run (tests/smoke_ui.lua).
-- Usage: local stub = dofile("tests/wowstub.lua").install(env)
-- It catches Lua runtime errors only; it cannot prove real WoW APIs exist.
--
-- Frame objects implement the behaviour the addon relies on (scripts, show/hide,
-- points, size, alpha, scale, enable, text, events, Click). Any other
-- CamelCase method is a recorded no-op (stub.unknown counts them); lowercase
-- field reads return nil, exactly like real frames.

local M = {}

local STEP = 1 / 60
local noop = function() end

function M.install(env)
  local stub = {
    clock = 1000,
    timers = {},
    frames = {},
    sounds = {},
    unknown = {},
    combat = false,
    lfg = {},       -- LFG mode by category number
    bg = {},        -- battlefield status by index
    maxBG = 0,
  }

  local methods = {}
  local mt = {}
  function mt.__index(t, k)
    local m = methods[k]
    if m then return m end
    if type(k) == "string" and k:find("^[A-Z]") then
      stub.unknown[k] = (stub.unknown[k] or 0) + 1
      return noop
    end
    return nil
  end

  local UIParent

  local function newObject(kind, name, parent)
    local o = setmetatable({
      _kind = kind, _name = name, _parent = parent, _children = {},
      _shown = true, _enabled = true, _scripts = {}, _hooks = {}, _events = {},
      _points = {}, _w = 0, _h = 0, _alpha = 1, _scale = 1,
      _level = parent and ((parent._level or 0) + 1) or 0,
      _mouse = kind == "Button",
    }, mt)
    if parent then parent._children[#parent._children + 1] = o end
    stub.frames[#stub.frames + 1] = o
    return o
  end

  local function runScript(self, name, ...)
    local fn = self._scripts[name]
    if fn then fn(self, ...) end
    local hooks = self._hooks[name]
    if hooks then
      for _, h in ipairs(hooks) do h(self, ...) end
    end
  end

  function methods.SetScript(self, name, fn) self._scripts[name] = fn end
  function methods.GetScript(self, name) return self._scripts[name] end
  function methods.HookScript(self, name, fn)
    self._hooks[name] = self._hooks[name] or {}
    table.insert(self._hooks[name], fn)
  end

  function methods.Show(self)
    if self._shown then return end
    self._shown = true
    runScript(self, "OnShow")
  end
  function methods.Hide(self)
    if not self._shown then return end
    self._shown = false
    runScript(self, "OnHide")
  end
  function methods.SetShown(self, shown)
    if shown then self:Show() else self:Hide() end
  end
  function methods.IsShown(self) return self._shown end
  function methods.IsMouseOver(self) return stub.over[self] == true end
  function methods.IsVisible(self)
    local o = self
    while o do
      if not o._shown then return false end
      o = o._parent
    end
    return true
  end

  function methods.SetPoint(self, point, rel, relPoint, x, y)
    if type(rel) == "number" then -- SetPoint(point, x, y)
      rel, relPoint, x, y = nil, nil, rel, relPoint
    elseif type(relPoint) == "number" then -- SetPoint(point, rel, x, y)
      relPoint, x, y = nil, relPoint, x
    end
    local entry = { point, rel or self._parent, relPoint or point, x or 0, y or 0 }
    for i, p in ipairs(self._points) do
      if p[1] == point then
        self._points[i] = entry
        return
      end
    end
    self._points[#self._points + 1] = entry
  end
  function methods.ClearAllPoints(self) self._points = {} end
  function methods.GetPoint(self, i)
    local p = self._points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function methods.GetNumPoints(self) return #self._points end
  function methods.SetAllPoints(self, rel)
    self._points = { { "TOPLEFT", rel or self._parent, "TOPLEFT", 0, 0 },
                     { "BOTTOMRIGHT", rel or self._parent, "BOTTOMRIGHT", 0, 0 } }
  end

  local function resized(self, w, h)
    if w == self._w and h == self._h then return end
    self._w, self._h = w, h
    if self._scripts.OnSizeChanged then self._scripts.OnSizeChanged(self, w, h) end
  end
  function methods.SetSize(self, w, h) resized(self, w, h) end
  function methods.SetWidth(self, w) resized(self, w, self._h) end
  function methods.SetHeight(self, h) resized(self, self._w, h) end
  function methods.GetWidth(self) return self._w end
  function methods.GetHeight(self) return self._h end
  function methods.GetSize(self) return self._w, self._h end

  function methods.SetClipsChildren(self, on) self._clips = on and true or false end
  function methods.DoesClipChildren(self) return self._clips == true end

  function methods.SetScale(self, s) self._scale = s end
  function methods.GetScale(self) return self._scale end
  function methods.SetAlpha(self, a) self._alpha = a end
  function methods.GetAlpha(self) return self._alpha end

  function methods.Enable(self) self._enabled = true end
  function methods.Disable(self) self._enabled = false end
  function methods.SetEnabled(self, on) self._enabled = on and true or false end
  function methods.IsEnabled(self) return self._enabled end
  function methods.EnableMouse(self, on) self._mouse = on and true or false end
  function methods.IsMouseEnabled(self) return self._mouse end

  function methods.SetTexture(self, t) self._texture = t end
  function methods.GetTexture(self) return self._texture end

  function methods.SetDesaturated(self, on) self._desat = on and 1 or 0 end
  function methods.SetDesaturation(self, v) self._desat = v end
  function methods.IsDesaturated(self) return (self._desat or 0) > 0.5 end
  function methods.GetDesaturation(self) return self._desat or 0 end
  function methods.SetRotation(self, r) self._rot = r end
  function methods.GetRotation(self) return self._rot or 0 end

  function methods.SetText(self, t) self._text = t end
  function methods.GetText(self) return self._text end

  function methods.SetVertexColor(self, r, g, b) self._vertex = { r, g, b } end
  function methods.GetVertexColor(self)
    local c = self._vertex or { 1, 1, 1 }
    return c[1], c[2], c[3]
  end
  function methods.SetFont(self, path, size, flags) self._font = { path, size, flags or "" } end
  function methods.GetFont(self)
    local f = self._font
    if not f then return nil end
    return f[1], f[2], f[3]
  end
  function methods.SetTextColor(self, r, g, b) self._textColor = { r, g, b } end
  function methods.GetTextColor(self)
    local c = self._textColor or { 1, 1, 1 }
    return c[1], c[2], c[3]
  end
  function methods.SetBackdropColor(self, r, g, b, a) self._bdColor = { r, g, b, a } end
  function methods.GetBackdropColor(self)
    local c = self._bdColor or { 0, 0, 0, 1 }
    return c[1], c[2], c[3], c[4]
  end
  -- Strata is inherited from the parent unless set on the frame itself.
  function methods.SetFrameStrata(self, s) self._strata = s end
  function methods.GetFrameStrata(self)
    local o = self
    while o do
      if o._strata then return o._strata end
      o = o._parent
    end
    return "MEDIUM"
  end

  function methods.GetParent(self) return self._parent end
  function methods.SetParent(self, parent)
    if self._parent then
      for i, c in ipairs(self._parent._children) do
        if c == self then table.remove(self._parent._children, i) break end
      end
    end
    self._parent = parent
    if parent then parent._children[#parent._children + 1] = self end
  end
  function methods.GetChildren(self) return unpack(self._children) end
  function methods.GetName(self) return self._name end

  function methods.SetFrameLevel(self, n) self._level = n end
  function methods.GetFrameLevel(self) return self._level end

  function methods.RegisterEvent(self, e)
    if e == "GLOBAL_MOUSE_DOWN" and stub.noGlobalMouse then error("unknown event " .. e) end
    self._events[e] = true
  end
  function methods.UnregisterEvent(self, e) self._events[e] = nil end

  function methods.Click(self, button)
    if self._enabled then runScript(self, "OnClick", button or "LeftButton", false) end
  end

  function methods.CreateTexture(self, name) return newObject("Texture", name, self) end
  function methods.CreateFontString(self, name) return newObject("FontString", name, self) end

  local function createFrame(kind, name, parent)
    local o = newObject(kind or "Frame", name, parent or UIParent)
    if name then rawset(env, name, o) end
    return o
  end

  UIParent = newObject("Frame", "UIParent", nil)
  UIParent._w, UIParent._h = 1920, 1080
  stub.UIParent = UIParent

  -- Tooltip: remembers its owner and last text.
  local tip = createFrame("GameTooltip", "GameTooltip", UIParent)
  tip:Hide()
  tip:SetFrameStrata("TOOLTIP")
  function tip.SetOwner(self, owner) self._owner = owner; self._lines = {} end
  function tip.GetOwner(self) return self._owner end
  function tip.SetText(self, t) self._tipText = t end
  function tip.AddLine(self, t) self._lines = self._lines or {}; self._lines[#self._lines + 1] = t end
  function tip.Hide(self)
    self._owner = nil
    methods.Hide(self)
  end
  stub.tooltip = tip

  ---------------------------------------------------------------------------
  -- Clock, timers, events

  function stub.advance(seconds)
    local steps = math.ceil(seconds / STEP - 1e-9)
    for _ = 1, steps do
      stub.clock = stub.clock + STEP
      local snapshot = {}
      for i, f in ipairs(stub.frames) do snapshot[i] = f end
      for _, f in ipairs(snapshot) do
        local fn = f._scripts.OnUpdate
        if fn and f:IsVisible() then fn(f, STEP) end
      end
      local due = {}
      local rest = {}
      for _, t in ipairs(stub.timers) do
        if t.at <= stub.clock then due[#due + 1] = t else rest[#rest + 1] = t end
      end
      stub.timers = rest
      for _, t in ipairs(due) do t.fn() end
    end
  end

  function stub.fire(event, ...)
    local snapshot = {}
    for i, f in ipairs(stub.frames) do snapshot[i] = f end
    for _, f in ipairs(snapshot) do
      if f._events[event] then
        local fn = f._scripts.OnEvent
        if fn then fn(f, event, ...) end
      end
    end
  end

  -- First visible object whose text equals `text`, or nil.
  function stub.findText(text)
    for _, f in ipairs(stub.frames) do
      if f._text == text and f:IsVisible() then return f end
    end
  end

  ---------------------------------------------------------------------------
  -- Globals

  rawset(env, "CreateFrame", createFrame)
  rawset(env, "UIParent", UIParent)
  rawset(env, "GameTooltip", tip)
  rawset(env, "UISpecialFrames", {})
  rawset(env, "tinsert", table.insert)
  rawset(env, "SOUNDKIT", { READY_CHECK = 8960 })
  rawset(env, "PlaySound", function(id) stub.sounds[#stub.sounds + 1] = id end)
  rawset(env, "time", function() return 1700000000 + math.floor(stub.clock) end)
  rawset(env, "GetTime", function() return stub.clock end)
  rawset(env, "C_Timer", {
    After = function(seconds, fn)
      stub.timers[#stub.timers + 1] = { at = stub.clock + seconds, fn = fn }
    end,
  })
  -- The cursor: stub.over[frame] = true while the mouse is over that frame.
  stub.over = {}
  -- No global MouseIsOver: the live client lacks it (frame:IsMouseOver() exists everywhere).
  rawset(env, "InCombatLockdown", function() return stub.combat end)
  rawset(env, "LE_LFG_CATEGORY_LFD", 1)
  rawset(env, "LE_LFG_CATEGORY_RF", 2)
  rawset(env, "LE_LFG_CATEGORY_SCENARIO", 3)
  rawset(env, "LE_LFG_CATEGORY_LFR", 4)
  rawset(env, "LE_LFG_CATEGORY_FLEXRAID", 5)
  rawset(env, "GetLFGMode", function(category) return stub.lfg[category] end)
  rawset(env, "GetMaxBattlefieldID", function() return stub.maxBG end)
  rawset(env, "GetBattlefieldStatus", function(i) return stub.bg[i] or "none" end)
  -- Raises, so an error the addon routes to the handler still fails the smoke.
  rawset(env, "geterrorhandler", function()
    return function(err) error(err, 0) end
  end)
  rawset(env, "SlashCmdList", {})
  rawset(env, "hooksecurefunc", function(a, b, c)
    local target, name, fn = env, a, b
    if type(a) == "table" then target, name, fn = a, b, c end
    local orig = target[name]
    target[name] = function(...)
      local r = { orig(...) }
      fn(...)
      return unpack(r)
    end
  end)
  for _, font in ipairs({
    "GameFontNormal", "GameFontNormalLarge", "GameFontNormalHuge", "GameFontNormalSmall",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightLarge",
  }) do
    rawset(env, font, font)
  end
  rawset(env, "_G", env)

  return stub
end

return M
