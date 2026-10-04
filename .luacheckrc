std = "lua51"
self = false
max_line_length = 140
exclude_files = { "tests/" }
globals = {
  "BattlewrightDB", "BattlewrightProbeDB", "SlashCmdList",
  "SLASH_BATTLEWRIGHT1", "SLASH_BATTLEWRIGHT2", "SLASH_BATTLEWRIGHTPROBE1",
}
read_globals = {
  "C_AddOns", "C_Spell", "C_UnitAuras", "C_Timer", "Enum", "GetAddOnMetadata",
  "CreateFrame", "UIParent", "geterrorhandler", "issecretvalue",
  "UnitClass", "UnitPower", "UnitPowerMax", "GetComboPoints", "UnitHealth", "UnitHealthMax",
  "UnitCanAttack", "UnitExists", "UnitAffectingCombat", "IsStealthed", "GetTime", "GetPowerRegen",
  "date", "tinsert", "UISpecialFrames", "ChatFontNormal", "UnitGUID",
}
