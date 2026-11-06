local _, ns = ...

local Bootstrap = {}
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, addon)
  if event == "ADDON_LOADED" and addon == "AzerothAnte" then
    AzerothAnteDB = AzerothAnteDB or {}
    -- Discovery must never abort a buy, pick or use, so errors are swallowed.
    if ns.Profile then
      ns.Profile.onObtain = function(kind, id)
        if AzerothAnteDB then pcall(ns.Profile.discover, AzerothAnteDB, kind, id) end
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
SlashCmdList.AZEROTHANTE = function() ns.UI.Main.Toggle() end

Bootstrap.frame = frame
ns.Bootstrap = Bootstrap
