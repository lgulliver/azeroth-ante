std = "lua51"
max_line_length = false
-- WoW callbacks and hook stubs have fixed signatures, so unused arguments are expected.
unused_args = false

-- Globals the addon assigns to.
globals = {
	"AzerothAnteDB",
	"SLASH_AZEROTHANTE1",
	"SlashCmdList",
}

-- WoW API the addon reads.
read_globals = {
	"C_Timer",
	"CreateFrame",
	"GameFontNormalLarge",
	"GameTooltip",
	"GetBattlefieldStatus",
	"GetCursorPosition",
	"GetLFGMode",
	"GetMaxBattlefieldID",
	"GetPhysicalScreenSize",
	"GetScreenHeight",
	"GetTime",
	"InCombatLockdown",
	"IsMouseButtonDown",
	"LE_LFG_CATEGORY_FLEXRAID",
	"LE_LFG_CATEGORY_LFD",
	"LE_LFG_CATEGORY_LFR",
	"LE_LFG_CATEGORY_RF",
	"LE_LFG_CATEGORY_SCENARIO",
	"PlaySound",
	"SOUNDKIT",
	"UIParent",
	"UISpecialFrames",
	"geterrorhandler",
	"time",
	"tinsert",
}
