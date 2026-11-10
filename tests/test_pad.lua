local ns, T = ...

-- Loads UI/Pad.lua against a fake Main whose frame records gamepad input state.
local function harness(opts)
  opts = opts or {}
  local h = { calls = {}, frames = {}, combat = false, printed = {}, statuses = {} }
  local function record(name) h.calls[#h.calls + 1] = name end
  local env = setmetatable({ AzerothAnteDB = opts.db }, { __index = _G })
  env.CreateFrame = function(kind)
    T.eq(kind, "Frame")
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, fn) T.eq(script, "OnEvent"); self.handler = fn end
    h.frames[#h.frames + 1] = frame
    return frame
  end
  env.InCombatLockdown = function() return h.combat end
  env.GetMaxBattlefieldID = function() return 2 end
  env.GetBattlefieldStatus = function(i) return h.statuses[i] or "none" end
  env.print = function(msg) h.printed[#h.printed + 1] = msg end

  local main = { frame = { scripts = {}, hooks = {}, padButtons = false, shown = false } }
  local f = main.frame
  function f:IsShown() return self.shown end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:HookScript(name, fn) self.hooks[name] = fn end
  if not opts.noGamePad then
    function f:EnableGamePadButton(on) self.padButtons = on end
  end
  function main.Show() f.shown = true; record("show") end
  function main.Hide()
    f.shown = false
    record("hide")
    if f.hooks.OnHide then f.hooks.OnHide(f) end
  end
  function main.IsShown() return f.shown end
  h.main = main
  h.ns = { UI = { Main = main, Options = nil } }
  local options = assert(loadfile("AzerothAnte/UI/Options.lua"))
  setfenv(options, env)("AzerothAnte", h.ns)
  local chunk = assert(loadfile("AzerothAnte/UI/Pad.lua"))
  setfenv(chunk, env)("AzerothAnte", h.ns)
  h.Pad = h.ns.UI.Pad
  h.env = env
  function h:fire(event, ...)
    for _, frame in ipairs(self.frames) do
      if frame.events[event] then frame.handler(frame, event, ...) end
    end
  end
  function h:press(button) f.scripts.OnGamePadButtonDown(f, button) end
  return h
end

T.test("pad_enter_enables_input_and_b_exits", function()
  local h = harness()
  h.Pad.Enter()
  T.eq(h.Pad.IsActive(), true)
  T.eq(h.main.frame.padButtons, true)
  T.eq(h.calls, { "show" })
  h:press("PAD2")
  T.eq(h.Pad.IsActive(), false)
  T.eq(h.main.frame.padButtons, false)
  T.eq(h.calls, { "show", "hide" })
end)

T.test("pad_menu_exits_and_unhandled_buttons_print", function()
  local h = harness()
  h.Pad.Enter()
  h:press("PAD1")
  T.eq(h.printed, { "Azeroth Ante pad: PAD1" })
  h:press("PADFORWARD")
  T.eq(h.Pad.IsActive(), false)
  T.eq(h.main.IsShown(), false)
end)

T.test("pad_ignores_buttons_when_inactive", function()
  local h = harness()
  h.Pad.Enter()
  h.Pad.Release()
  T.eq(h.main.IsShown(), true)
  T.eq(h.main.frame.padButtons, false)
  h.Pad.OnButton("PAD1")
  T.eq(h.printed, {})
end)

T.test("pad_auto_enter_respects_option", function()
  local h = harness({ db = { options = { padOnAutoOpen = false } } })
  h.Pad.AutoEnter()
  T.eq(h.Pad.IsActive(), false)
  T.eq(h.calls, {})
  local on = harness()
  on.Pad.AutoEnter()
  T.eq(on.Pad.IsActive(), true)
end)

T.test("pad_releases_on_queue_pop_ready_and_role_check", function()
  for _, event in ipairs({ "LFG_PROPOSAL_SHOW", "READY_CHECK", "LFG_ROLE_CHECK_SHOW", "UPDATE_BATTLEFIELD_STATUS" }) do
    local h = harness()
    h.Pad.Enter()
    if event == "UPDATE_BATTLEFIELD_STATUS" then
      h:fire(event)
      T.eq(h.Pad.IsActive(), true, "no confirm yet")
      h.statuses[2] = "confirm"
    end
    h:fire(event)
    T.eq(h.Pad.IsActive(), false, event)
    T.eq(h.main.IsShown(), true, event)
  end
end)

T.test("pad_releases_when_window_hides", function()
  local h = harness()
  h.Pad.Enter()
  h.main.Hide()
  T.eq(h.Pad.IsActive(), false)
  T.eq(h.main.frame.padButtons, false)
end)

T.test("pad_enter_without_gamepad_api_is_harmless", function()
  local h = harness({ noGamePad = true })
  h.Pad.Enter()
  T.eq(h.Pad.IsActive(), false)
  T.eq(h.calls, { "show" })
end)

T.test("pad_enter_in_combat_only_opens", function()
  local h = harness()
  h.combat = true
  h.Pad.Enter()
  T.eq(h.Pad.IsActive(), false)
  T.eq(h.main.frame.padButtons, false)
end)
