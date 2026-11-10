local _, ns = ...

-- Controller mode: while active, the main frame takes the gamepad's buttons so
-- they drive the addon instead of the character. Leaving it (B, the window
-- hiding, or a Blizzard prompt that needs the pad) hands the pad back.
local Pad = {}

local active = false
local wired = false

-- button name (PAD1, PADDUP, PADRTRIGGER...) -> fn(); later tasks fill this in.
Pad.handlers = {}

local function wire(frame)
  if wired then return end
  wired = true
  frame:HookScript("OnHide", function() Pad.Release() end)
  frame:SetScript("OnGamePadButtonDown", function(_, button) Pad.OnButton(button) end)
end

function Pad.IsActive() return active end

-- Opens the window; takes the pad only where the client supports it and out of combat.
function Pad.Enter()
  local Main = ns.UI.Main
  Main.Show()
  local frame = Main.frame
  if active or InCombatLockdown() or not frame or not frame.EnableGamePadButton
    or not Main.IsShown() then return end
  wire(frame)
  frame:EnableGamePadButton(true)
  active = true
end

function Pad.Release()
  if not active then return end
  active = false
  local frame = ns.UI.Main.frame
  if frame and frame.EnableGamePadButton then frame:EnableGamePadButton(false) end
end

function Pad.Exit()
  Pad.Release()
  ns.UI.Main.Hide()
end

function Pad.AutoEnter()
  if ns.UI.Options.Get("padOnAutoOpen") then Pad.Enter() end
end

function Pad.OnButton(button)
  if not active then return end
  local handler = Pad.handlers[button]
  if handler then
    handler()
  else
    print("Azeroth Ante pad: " .. tostring(button)) -- capture check; removed once every button is mapped
  end
end

Pad.handlers.PAD2 = Pad.Exit
-- A captured frame swallows Menu too, so it hands the pad back rather than doing nothing.
Pad.handlers.PADFORWARD = Pad.Exit

-- Blizzard's accept and role dialogs need the pad, and the addon cannot answer them.
local releaseEvents = { LFG_PROPOSAL_SHOW = true, READY_CHECK = true, LFG_ROLE_CHECK_SHOW = true }

local function battlefieldConfirm()
  local ok, count = pcall(GetMaxBattlefieldID)
  if not ok or not count then return false end
  for i = 1, count do
    local statusOK, status = pcall(GetBattlefieldStatus, i)
    if statusOK and status == "confirm" then return true end
  end
  return false
end

local frame = CreateFrame("Frame")
for event in pairs(releaseEvents) do frame:RegisterEvent(event) end
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:SetScript("OnEvent", function(_, event)
  if releaseEvents[event] or battlefieldConfirm() then Pad.Release() end
end)

Pad.frame = frame
ns.UI.Pad = Pad
