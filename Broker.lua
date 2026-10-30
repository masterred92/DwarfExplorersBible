-- LibDataBroker launcher (Titan Panel, ChocolateBar, Bazooka...).
local _, ns = ...
local M, P = ns.RM, ns.Prices
local obj

function M.InstallBroker()
  if obj then return obj end
  local ldb = type(LibStub) == "table" and LibStub("LibDataBroker-1.1", true)
  if not ldb then return nil end
  obj = ldb:NewDataObject("RecipeMaster", {
    type = "launcher", text = "Recipe Master", label = "Recipe Master",
    icon = "Interface\\AddOns\\RecipeMaster\\media\\icon",
    OnClick = function() M.Toggle() end,
    OnTooltipShow = function(tt)
      tt:AddLine("Recipe Master")
      tt:AddLine(#M.recipes .. " recipes. Click to open, or Alt-click any material.", 1, 1, 1, true)
      local inst = P.Installed()
      tt:AddLine("Price sources: " .. table.concat(inst, ", "), 0.7, 0.7, 0.7, true)
    end,
  })
  return obj
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() M.InstallBroker() end)
