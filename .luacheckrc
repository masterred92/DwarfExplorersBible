std = "lua51"
max_line_length = false
exclude_files = { "tests/**", "tools/**", ".release/**", ".lua/**", ".luarocks/**" }
-- Our own globals.
globals = { "KennyWhatCanIMake", "KennyWhatCanIMakeDB", "SLASH_KENNYWHATCANIMAKE1", "SLASH_KENNYWHATCANIMAKE2", "SlashCmdList" }
-- WoW API (checked against Blizzard's UI source by tools/verify_api.py) and host-addon globals (tools/host_api.py).
read_globals = { "C_Item", "C_MerchantFrame", "GetMerchantNumItems", "GetMerchantItemID", "GetMerchantItemInfo", "C_AuctionHouse", "C_Timer", "C_Container", "C_AddOns", "C_RestrictedActions", "C_TradeSkillUI",
  "CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip", "TooltipDataProcessor", "Enum", "UISpecialFrames", "tinsert",
  "GetMoneyString", "GetMoney", "GetTime", "GetRealZoneText", "GetBuildInfo", "GetLocale", "GetRealmName", "UnitName",
  "UnitFactionGroup", "UnitAffectingCombat", "issecretvalue", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "time", "date",
  "hooksecurefunc", "HandleModifiedItemClick", "IsAltKeyDown",
  "KennyPriceLog", "LibStub", "Auctionator", "TSM_API", "AucAdvanced" }
