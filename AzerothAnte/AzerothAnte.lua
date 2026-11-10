local _, ns = ...

local Bootstrap = {}
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, addon)
  if event == "ADDON_LOADED" and addon == "AzerothAnte" then
    AzerothAnteDB = AzerothAnteDB or {}
    if ns.UI.Options then ns.UI.Options.Register(AzerothAnteDB) end
    -- Discovery must never abort a buy, pick or use, so errors are swallowed.
    if ns.Profile then
      ns.Profile.onObtain = function(kind, id)
        if AzerothAnteDB then pcall(ns.Profile.discover, AzerothAnteDB, kind, id) end
      end
    end
    -- Core's one-argument hasAchievement(id) reads this database; the hook feeds
    -- lifetime counters and toasts each achievement in unlock order.
    if ns.Profile then
      ns.Profile.db = AzerothAnteDB
      ns.Profile.onEvent = function(n, a, run)
        if not AzerothAnteDB then return end
        local ok, new = pcall(ns.Profile.event, AzerothAnteDB, n, a, run)
        if ok and new and ns.UI.Toast then
          for _, id in ipairs(new) do pcall(ns.UI.Toast.Achievement, id) end
        end
      end
    end
    ns.UI.Main.Create()
    ns.UI.Main.SetRun(ns.Save.load(AzerothAnteDB))
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGOUT" and ns.UI.OnRunChanged then
    ns.UI.OnRunChanged()
  end
end)

SLASH_AZEROTHANTE1 = "/ante"
-- "/ante pad" opens the window with the gamepad in control; Bindings.xml calls it too.
SlashCmdList.AZEROTHANTE = function(msg)
  if type(msg) == "string" and msg:lower():match("^%s*pad%s*$") and ns.UI.Pad then
    ns.UI.Pad.Enter()
  else
    ns.UI.Main.Toggle()
  end
end
BINDING_HEADER_AZEROTHANTE = "Azeroth Ante"
BINDING_NAME_AZEROTHANTE_PAD = "Open / take controller"

Bootstrap.frame = frame
ns.Bootstrap = Bootstrap
