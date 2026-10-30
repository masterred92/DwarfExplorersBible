-- The Guide window: search box, the picked material with its price, and one row per recipe that uses it.
-- Click a row to follow the chain (material -> intermediate -> final); Back walks the chain back.
local _, ns = ...
local C, M = ns.Compat, ns.RM
local ROWS, ROW_H = 12, 34
local win
local state = { id = nil, mode = "uses", offset = 0, history = {}, list = {} }

local function priceText(p, label)
  if not p then return "|cff888888no price|r" end
  return C.Money(p) .. " |cff888888(" .. label .. ")|r"
end

-- Plain text for one row (also used by the tests).
function M.RowText(e)
  local r, pr = e.r, e.pr
  local qty = r.min == r.max and tostring(r.min) or (r.min .. "-" .. r.max)
  local known = M.Knows(r) and "|cff33ff33known|r" or "|cffff5555not known|r"
  local skill = M.Skill(r.prof)
  local DIFF = { orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40bf40", grey = "|cff808080" }
  local d = M.Difficulty(r)
  local skillTxt = (r.skill or 0) > 0 and (" " .. r.skill) or ""
  if d then skillTxt = " " .. DIFF[d] .. (r.skill or 0) .. (d == "orange" and (" (you " .. skill .. ")") or "") .. "|r" end
  local parts = {}
  for _, g in ipairs(r.reagents) do parts[#parts + 1] = g.n .. "x " .. M.Name(g.id) end
  local money
  if pr.profit then
    money = (pr.profit >= 0 and "|cff33ff33+" or "|cffff5555-") .. C.Money(math.abs(pr.profit)) .. "|r"
  else money = "|cff888888cost " .. C.Money(pr.cost) .. (pr.missing and " (some prices missing)" or "") .. "|r" end
  local nextN = #(M.byReagent[r.product] or {})
  local line1 = ("%s x%s  |cffaaaaaa%s%s|r  %s  %s"):format(M.Name(r.product), qty, r.prof, skillTxt, known, money)
  local line2 = "|cffbbbbbb" .. table.concat(parts, ", ") .. (nextN > 0 and ("  |cff66ccff> used in " .. nextN .. "|r") or "") .. "|r"
  return line1, line2
end

local function refresh()
  if not win then return end
  local id = state.id
  if not id then
    win.head:SetText("Type a material, or Alt-click an item.")
    state.list = {}
  else
    local p, label = M.Price(id)
    local uses, made = #(M.byReagent[id] or {}), #(M.byProduct[id] or {})
    win.head:SetText(("%s  %s\nUsed in %d  ·  Made by %d"):format(M.Name(id), priceText(p, label), uses, made))
    if state.mode == "uses" then state.list = M.UsesOf(id)
    else
      state.list = {}
      for _, r in ipairs(M.byProduct[id] or {}) do state.list[#state.list + 1] = { r = r, pr = M.Profit(r) } end
    end
  end
  win.modeBtn:SetText(state.mode == "uses" and "Made from" or "Used in")
  win.back:SetEnabled(#state.history > 0)
  for i = 1, ROWS do
    local row, e = win.rows[i], state.list[i + state.offset]
    if e then
      local a, b = M.RowText(e)
      row.top:SetText(a); row.bottom:SetText(b); row.entry = e; row:Show()
    else row.entry = nil; row:Hide() end
  end
end

local function rowTooltip(row)
  local e = row.entry
  if not e then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(M.Name(e.r.product))
  GameTooltip:AddLine(e.r.prof .. ((e.r.skill or 0) > 0 and (" (yellow " .. e.r.skill .. ", grey " .. (e.r.grey or "?") .. ")") or "") .. (e.r.origin == "scan" and "  (from your profession window)" or ""), 0.7, 0.7, 0.7)
  for _, g in ipairs(e.r.reagents) do
    local p, label = M.ReagentPrice(g.id)
    GameTooltip:AddDoubleLine(g.n .. "x " .. M.Name(g.id), p and (C.Money(p * g.n) .. " (" .. label .. ")") or "no price", 1, 1, 1, 0.9, 0.9, 0.9)
  end
  local pp, pl = M.Price(e.r.product)
  GameTooltip:AddDoubleLine("Reagent cost", C.Money(e.pr.cost), 1, 0.82, 0)
  GameTooltip:AddDoubleLine("Sells for (after AH cut)", e.pr.value and (C.Money(e.pr.value) .. (pl and (" (" .. pl .. ")") or "")) or "no price", 1, 0.82, 0)
  if e.pr.profit then GameTooltip:AddDoubleLine("Profit", C.Money(math.abs(e.pr.profit)) .. (e.pr.profit < 0 and " loss" or ""), 0.2, 1, 0.2) end
  if pp == nil then GameTooltip:AddLine("Search it at the auction house to price it.", 0.6, 0.6, 0.6, true) end
  GameTooltip:AddLine("Click: what can I make from this?", 0.4, 0.8, 1)
  GameTooltip:Show()
end

function M.Navigate(id, push)
  if push and state.id and state.id ~= id then state.history[#state.history + 1] = state.id end
  state.id, state.offset, state.mode = id, 0, "uses"
  if #(M.byReagent[id] or {}) == 0 and #(M.byProduct[id] or {}) > 0 then state.mode = "made" end
  refresh()
end

function M.State() return state end

local function build()
  win = CreateFrame("Frame", "KennyWhatCanIMakeFrame", UIParent, "BackdropTemplate")
  win:SetSize(620, 120 + ROWS * ROW_H)
  win:SetPoint("CENTER")
  win:SetFrameStrata("HIGH")
  win:SetClampedToScreen(true)
  win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  win:SetBackdropColor(0.05, 0.04, 0.02, 0.94)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "KennyWhatCanIMakeFrame")
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12); title:SetText("What Can I Make?")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  local search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
  search:SetSize(220, 22); search:SetPoint("TOPLEFT", 150, -10); search:SetAutoFocus(false)
  search:SetScript("OnEnterPressed", function(s)
    local id = M.ParseItem(s:GetText()); s:ClearFocus()
    if id then M.Navigate(id, true) else win.head:SetText("No recipe uses '" .. s:GetText() .. "'.") end
  end)
  search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  win.search = search
  local back = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  back:SetSize(60, 22); back:SetPoint("LEFT", search, "RIGHT", 8, 0); back:SetText("Back")
  back:SetScript("OnClick", function()
    local prev = table.remove(state.history)
    if prev then M.Navigate(prev, false) end
  end)
  win.back = back
  local mode = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  mode:SetSize(90, 22); mode:SetPoint("LEFT", back, "RIGHT", 6, 0)
  mode:SetScript("OnClick", function() state.mode = state.mode == "uses" and "made" or "uses"; state.offset = 0; refresh() end)
  win.modeBtn = mode
  local head = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  head:SetPoint("TOPLEFT", 14, -42); head:SetPoint("RIGHT", -14, 0); head:SetJustifyH("LEFT")
  win.head = head
  win.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, win)
    row:SetSize(590, ROW_H - 2); row:SetPoint("TOPLEFT", 14, -78 - (i - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.top = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.top:SetPoint("TOPLEFT", 2, -2); row.top:SetPoint("RIGHT", -2, 0); row.top:SetJustifyH("LEFT")
    row.bottom = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bottom:SetPoint("TOPLEFT", 2, -18); row.bottom:SetPoint("RIGHT", -2, 0); row.bottom:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(s) if s.entry then M.Navigate(s.entry.r.product, true) end end)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.rows[i] = row
  end
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function(_, delta)
    state.offset = math.max(0, math.min(state.offset - delta * 3, math.max(0, #state.list - ROWS))); refresh()
  end)
  local foot = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  foot:SetPoint("BOTTOMLEFT", 14, 10)
  foot:SetText("Prices: first source in your order that has one (/wcim sources). Profit is after the 5% AH cut.")
end

function M.Open(id)
  if not win then build() end
  win:Show()
  if id then M.Navigate(id, true) else refresh() end
end

function M.Toggle()
  if win and win:IsShown() then win:Hide() else M.Open() end
end

function M.Frame() return win end
