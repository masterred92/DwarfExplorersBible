-- The Guide window (1.2.0 layout, from UI Bot's approved mockup): search with live results, Back + breadcrumb,
-- the picked material with its price, "Show only" filters, one row per recipe, the crafting chain for the selected
-- row, and the mobs it drops from (learned from your own kills, Drops.lua).
-- Click a row to put it in the chain strip; click it again (or a step in the strip) to open that item.
local _, ns = ...
local C, M = ns.Compat, ns.RM

-- Everything UI Bot may want to tweak lives here.
local LAYOUT = {
  width = 660, height = 632,
  bg = { 0.05, 0.04, 0.02, 1 },          -- opaque (Kenny's pick); the old window was 0.94 over a tooltip texture
  rows = 8, rowH = 40, rowsTop = 162,
  searchW = 210, popupW = 300, popupRows = 8,
  chainSteps = 4, chainStepMaxW = 150,
  hoverAlpha = 0.08,                     -- keeps grey (808080) text at 4.5:1 or better on the row stripe
}
M.LAYOUT = LAYOUT
local DIFF = { orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 } }
local GOLD = { 1, 0.82, 0 }
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

local win
local state = { id = nil, mode = "uses", offset = 0, history = {}, list = {}, total = 0, selected = nil }

local function isTable(v) return type(v) == "table" end

local function itemIcon(id)
  if not (C_Item and C_Item.GetItemIconByID) then return nil end
  local ok, icon = pcall(C_Item.GetItemIconByID, id)
  return ok and C.SafeNumber(icon) or nil
end

-- Text helpers (also used by the tests) -----------------------------------------------------
local function profSkill(r) return r.prof .. ((r.skill or 0) > 0 and (" " .. r.skill) or "") end

-- Header: name, the counts / camp line, price and where the price is from.
function M.HeaderText(id)
  local uses, made = M.byReagent[id] or {}, M.byProduct[id] or {}
  local parts = {}
  if #uses > 0 or #made > 0 then
    local profs, seen = {}, {}
    for _, r in ipairs(made) do if not seen[r.prof] then seen[r.prof] = true; profs[#profs + 1] = r.prof end end
    parts[#parts + 1] = ("Used in |cffffffff%d|r recipe%s  ·  Made by |cffffffff%d|r%s"):format(#uses, #uses == 1 and "" or "s",
      #made, #profs > 0 and (" (" .. table.concat(profs, ", ") .. ")") or "")
  end
  local camp = {}
  for _, c in ipairs(M.CampUses(id) or {}) do camp[#camp + 1] = M.CampText(c) end
  if #camp > 0 then parts[#parts + 1] = "|cffffd100Camp:|r  |cffffffff" .. table.concat(camp, "  ·  ") .. "|r" end
  local off = M.CampOff(id)
  if off then parts[#parts + 1] = "|cffff7373" .. off .. "|r" end
  local p, label = M.Price(id)
  return M.Name(id), table.concat(parts, "  ·  "), p and C.Money(p) or "|cffaaaaaano price yet|r", p and ("each, from " .. label) or ""
end

-- One row: name line (difficulty colour, quantity, "> N more uses"), profit, reagents, profession + learned.
function M.RowText(e)
  local r, pr = e.r, e.pr
  local qty = r.max == 1 and "" or (r.min == r.max and (" x" .. r.min) or (" x" .. r.min .. "-" .. r.max))
  local nextN = #(M.byReagent[r.product] or {})
  local name = M.Name(r.product) .. "|cffffffff" .. qty .. "|r" .. (nextN > 0 and ("  |cff66ccff> " .. nextN .. " more use" .. (nextN == 1 and "" or "s") .. "|r") or "")
  local money
  if pr.profit then money = (pr.profit >= 0 and "|cff33ff33+" or "|cffff6060-") .. C.Money(math.abs(pr.profit)) .. "|r"
  else money = "|cffaaaaaano price|r" end
  local parts = {}
  for _, g in ipairs(r.reagents) do parts[#parts + 1] = g.n .. " " .. M.Name(g.id) end
  local skill = M.Skill(r.prof)
  local d = M.Difficulty(r)
  local right = profSkill(r) .. (d == "orange" and skill and (" (you " .. skill .. ")") or "")
  right = right .. (M.Knows(r) and (" " .. READY) or "  |cffff8080not learned|r")
  return name, money, table.concat(parts, ", "), right, d
end

-- The chain strip: where you came from, this item, the selected row, and that row's most profitable next step.
-- Each step is { id, sub, current }.
function M.ChainSteps(id, e)
  local steps = {}
  if not id then return steps end
  local prev = state.history[#state.history]
  if prev then steps[#steps + 1] = { id = prev, sub = "start here" } end
  local how = prev and nil or "start here"
  if prev then
    for _, r in ipairs(M.byProduct[id] or {}) do
      for _, g in ipairs(r.reagents) do if g.id == prev and not how then how = profSkill(r) end end
    end
    if not how and M.byProduct[id] and M.byProduct[id][1] then how = profSkill(M.byProduct[id][1]) end
  end
  steps[#steps + 1] = { id = id, sub = how or "", current = true }
  if e and state.mode == "uses" then
    steps[#steps + 1] = { id = e.r.product, sub = profSkill(e.r) }
    local nxt = M.BestNext(e.r.product)
    if nxt then steps[#steps + 1] = { id = nxt.r.product, sub = profSkill(nxt.r) } end
  elseif e then
    -- "Made from" mode: the row is a recipe that makes this item; show its first reagent before it.
    local g = e.r.reagents[1]
    if g then table.insert(steps, #steps, { id = g.id, sub = "reagent" }) end
  end
  while #steps > LAYOUT.chainSteps do table.remove(steps, 1) end
  return steps
end

-- "Drops from (your N kills)" and a short summary for the collapsed line.
function M.DropsSummary(id)
  local Dr = ns.Drops
  if not (Dr and id) then return "Drops from (your 0 kills)", "", {} end
  local s = Dr.SourcesOf(id)
  local summary
  if #s.rows > 0 then
    local bits = {}
    for i = 1, math.min(2, #s.rows) do
      local e = s.rows[i]
      bits[#bits + 1] = ("%s %d%% (%s)"):format(Dr.MobName(e.cid), Dr.Percent({ seen = e.seen, loots = e.loots }), Dr.Label(e.loots))
    end
    summary = table.concat(bits, ",  ") .. (#s.rows > 2 and ("  +" .. (#s.rows - 2) .. " more") or "")
  elseif s.learning > 0 then
    summary = ("Seen from %d mob%s; a rate shows after %d of your kills of one."):format(s.learning, s.learning == 1 and "" or "s", Dr.MIN_LOOTS)
  else
    summary = "Not seen yet: learns from corpses you loot."
  end
  return ("Drops from (your %d kills)"):format(s.kills), summary, s.rows
end

-- Search popup rows: { id, name, right } for items with a word starting with text.
function M.SearchPopup(text)
  local hits = M.Search(text, 200)
  local out = {}
  for i = 1, math.min(#hits, LAYOUT.popupRows) do
    local id = hits[i]
    local n = #(M.byReagent[id] or {})
    out[i] = { id = id, name = M.Name(id), right = n > 0 and ("used in " .. n) or (M.byCamp[id] and "camp use" or "crafted item") }
  end
  return out, #hits
end

-- List + filters --------------------------------------------------------------------------
local function buildList()
  local id, all = state.id, {}
  if id then
    if state.mode == "uses" then all = M.UsesOf(id)
    else for _, r in ipairs(M.byProduct[id] or {}) do all[#all + 1] = { r = r, pr = M.Profit(r) } end end
  end
  state.total = #all
  state.list = M.FilterList(all, M.Settings())
  -- Keep the selected row if it's still listed, else the most profitable one (the list is best-first).
  local keep
  for _, e in ipairs(state.list) do if state.selected and e.r == state.selected.r then keep = e end end
  state.selected = keep or state.list[1]
end

function M.SetFilter(key, on)
  local s = M.Settings()
  if not s then return end
  s[key] = on and true or false
  state.offset = 0
  if win then M.Refresh() else buildList() end
end

-- Widgets ---------------------------------------------------------------------------------
local function setColor(fs, c) if fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end end

local function refreshRows()
  local n = LAYOUT.rows
  if win.scroll and FauxScrollFrame_Update then
    FauxScrollFrame_Update(win.scroll, #state.list, n, LAYOUT.rowH)
    state.offset = FauxScrollFrame_GetOffset(win.scroll)
  end
  state.offset = math.max(0, math.min(state.offset, math.max(0, #state.list - n)))
  for i = 1, n do
    local row, e = win.rows[i], state.list[i + state.offset]
    if e then
      local name, money, reag, right, d = M.RowText(e)
      row.name:SetText(name); setColor(row.name, d and DIFF[d] or GOLD)
      row.money:SetText(money); row.reag:SetText(reag); row.right:SetText(right)
      if row.icon.SetTexture then row.icon:SetTexture(itemIcon(e.r.product) or "Interface\\Icons\\INV_Misc_QuestionMark") end
      row.selected:SetShown(state.selected == e)
      row.entry = e; row:Show()
    else row.entry = nil; row:Hide() end
  end
end

-- Natural width of each step (icon + the longer of its two lines), capped; then fitted to the window: the step you
-- came from goes first, then every step shrinks evenly (names are cut with "...").
local function chainWidths(steps)
  local ws, total = {}, 0
  for i, s in ipairs(steps) do
    local b = win.chain[i]
    b.name:SetText(M.Name(s.id)); b.sub:SetText(s.sub)
    ws[i] = math.min(LAYOUT.chainStepMaxW, math.max(b.name:GetStringWidth() or 0, b.sub:GetStringWidth() or 0)) + 30
    total = total + ws[i] + (i > 1 and 20 or 0)
  end
  return ws, total
end

local function refreshChain()
  local steps = M.ChainSteps(state.id, state.selected)
  local avail = LAYOUT.width - 28
  local ws, total = chainWidths(steps)
  if total > avail and #steps > 3 and not steps[1].current then table.remove(steps, 1); ws, total = chainWidths(steps) end
  if total > avail then
    local scale = (avail - 20 * (#steps - 1)) / (total - 20 * (#steps - 1))
    for i = 1, #ws do ws[i] = math.max(60, math.floor(ws[i] * scale)) end
  end
  local x = 14
  for i = 1, LAYOUT.chainSteps do
    local b, s = win.chain[i], steps[i]
    if s then
      b.name:SetText(M.Name(s.id)); b.sub:SetText(s.sub)
      if b.icon.SetTexture then b.icon:SetTexture(itemIcon(s.id) or "Interface\\Icons\\INV_Misc_QuestionMark") end
      local w = ws[i]
      b.name:SetWidth(w - 28); b.sub:SetWidth(w - 28)
      b:SetWidth(w); b:ClearAllPoints(); b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -(LAYOUT.rowsTop + LAYOUT.rows * LAYOUT.rowH + 30))
      b.cur:SetShown(s.current == true)
      b.id = s.id; b:Show()
      x = x + w
      local arrow = win.arrows[i]
      if steps[i + 1] then arrow:ClearAllPoints(); arrow:SetPoint("TOPLEFT", win, "TOPLEFT", x + 3, -(LAYOUT.rowsTop + LAYOUT.rows * LAYOUT.rowH + 35)); arrow:Show(); x = x + 20
      else arrow:Hide() end
    else b.id = nil; b:Hide(); win.arrows[i]:Hide() end
  end
  win.chainLabel:SetText(state.mode == "uses" and "Crafting chain for the selected row:" or "Where the selected recipe's reagent comes in:")
end

local function refreshDrops()
  local title, summary, rows = M.DropsSummary(state.id)
  win.dropsTitle:SetText(title); win.dropsText:SetText(summary)
  win.dropsText:SetWidth(LAYOUT.width - 36 - (win.dropsTitle:GetStringWidth() or 0) - 10 - 14)
  local p = win.dropsPanel
  if p:IsShown() then
    local Dr = ns.Drops
    for i = 1, #p.lines do
      local e = rows[i]
      if e then
        p.lines[i]:SetText(("%s:  |cffffffff%d%%|r  |cffaaaaaa(%s)|r"):format(Dr.MobName(e.cid), Dr.Percent({ seen = e.seen, loots = e.loots }), Dr.Label(e.loots)))
        p.lines[i]:Show()
      else p.lines[i]:Hide() end
    end
    p.empty:SetShown(#rows == 0)
    p.empty:SetText(summary)
  end
end

function M.Refresh()
  buildList()
  if not win then return end
  local id = state.id
  if not id then
    win.name:SetText("Type a material, or Alt-click an item."); win.counts:SetText(""); win.price:SetText(""); win.priceFrom:SetText("")
    if win.icon.SetTexture then win.icon:SetTexture(nil) end
  else
    local name, counts, price, from = M.HeaderText(id)
    win.name:SetText(name); win.counts:SetText(counts); win.price:SetText(price); win.priceFrom:SetText(from)
    win.counts:SetWidth(LAYOUT.width - 68 - 16 - (win.priceFrom:GetStringWidth() or 0) - 12)
    if win.icon.SetTexture then win.icon:SetTexture(itemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark") end
  end
  -- Breadcrumb: the item you came from (click to go back) and this one.
  local prev = state.history[#state.history]
  win.crumbPrev:SetShown(prev ~= nil); win.crumbArrow:SetShown(prev ~= nil and id ~= nil)
  if prev then
    win.crumbPrev.text:SetText("|cff66ccff" .. M.Name(prev) .. "|r")
    win.crumbPrev:SetWidth(math.min(220, (win.crumbPrev.text:GetStringWidth() or 0) + 2))
  end
  win.crumbCur:SetText(id and M.Name(id) or "")
  win.back:SetEnabled(#state.history > 0)
  win.modeBtn:SetText(state.mode == "uses" and "Made from" or "Used in")
  win.count:SetText(id and (#state.list .. " of " .. state.total) or "")
  local s = M.Settings()
  win.fKnown:SetChecked(s.filterKnown); win.fMine:SetChecked(s.filterMine); win.fPriced:SetChecked(s.filterPriced)
  win.foot:SetText(("Prices from %s (/deb sources). Profit is after the %d%% AH cut."):format(
    table.concat(ns.Prices.Installed(), ", "), math.floor((s.ahCut or 0.05) * 100 + 0.5)))
  refreshRows(); refreshChain(); refreshDrops()
end

local function rowTooltip(row)
  local e = row.entry
  if not e then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(M.Name(e.r.product))
  GameTooltip:AddLine(e.r.prof .. ((e.r.skill or 0) > 0 and (" (yellow " .. e.r.skill .. ", grey " .. (e.r.grey or "?") .. ")") or "") .. (e.r.origin == "scan" and "  (from your profession window)" or ""), 0.7, 0.7, 0.7)
  if M.IsHidden(e.r.product) then GameTooltip:AddLine("Not released yet: Blizzard keeps this item out of the game files until then.", 1, 0.6, 0.2, true) end
  local tools = M.Tools(e.r)
  if tools then GameTooltip:AddLine("Needs: " .. table.concat(tools, ", "), 0.7, 0.7, 0.7, true) end
  for _, g in ipairs(e.r.reagents) do
    local p, label = M.ReagentPrice(g.id)
    GameTooltip:AddDoubleLine(g.n .. "x " .. M.Name(g.id), p and (C.Money(p * g.n) .. " (" .. label .. ")") or "no price", 1, 1, 1, 0.9, 0.9, 0.9)
  end
  local pp, pl = M.Price(e.r.product)
  GameTooltip:AddDoubleLine("Reagent cost", C.Money(e.pr.cost), 1, 0.82, 0)
  GameTooltip:AddDoubleLine("Sells for (after AH cut)", e.pr.value and (C.Money(e.pr.value) .. (pl and (" (" .. pl .. ")") or "")) or "no price", 1, 0.82, 0)
  if e.pr.profit then GameTooltip:AddDoubleLine("Profit", C.Money(math.abs(e.pr.profit)) .. (e.pr.profit < 0 and " loss" or ""), 0.2, 1, 0.2) end
  if pp == nil then GameTooltip:AddLine("Search it at the auction house to price it.", 0.6, 0.6, 0.6, true) end
  GameTooltip:AddLine(state.selected == e and "Click: what can I make from this?" or "Click: show its crafting chain. Click again to open it.", 0.4, 0.8, 1, true)
  GameTooltip:Show()
end

function M.Navigate(id, push)
  if push and state.id and state.id ~= id then state.history[#state.history + 1] = state.id end
  state.id, state.offset, state.mode, state.selected = id, 0, "uses", nil
  if #(M.byReagent[id] or {}) == 0 and #(M.byProduct[id] or {}) > 0 then state.mode = "made" end
  if win and win.scroll and FauxScrollFrame_SetOffset then
    FauxScrollFrame_SetOffset(win.scroll, 0)
    local bar = win.scroll.ScrollBar
    if isTable(bar) and bar.SetValue then bar:SetValue(0) end
  end
  M.Refresh()
end

-- Row click: the first click puts the row in the chain strip, a click on the selected row opens its item.
function M.ClickRow(e)
  if not e then return end
  if state.selected == e and state.mode == "uses" then M.Navigate(e.r.product, true)
  else state.selected = e; if win then refreshRows(); refreshChain() end end
end

function M.GoBack()
  local prev = table.remove(state.history)
  if prev then M.Navigate(prev, false) end
end

function M.State() return state end

local function rule(y, a)
  local t = win:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], a or 0.35)
  t:SetHeight(1); t:SetPoint("TOPLEFT", 10, y); t:SetPoint("TOPRIGHT", -10, y)
  return t
end

local function fontString(parent, template, x, y, point)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint(point or "TOPLEFT", x, y)
  return fs
end

local function buildSearch()
  local search = CreateFrame("EditBox", "KennyDwarfExplorersBibleSearch", win, "SearchBoxTemplate")
  search:SetSize(LAYOUT.searchW, 22); search:SetPoint("TOPRIGHT", -34, -9); search:SetAutoFocus(false)
  if isTable(search.Instructions) then search.Instructions:SetText("Type a material") end
  win.search = search
  local pop = CreateFrame("Frame", nil, win, "BackdropTemplate")
  pop:SetSize(LAYOUT.popupW, 10 + 26 * LAYOUT.popupRows + 22)
  pop:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -66, -3)
  pop:SetFrameStrata("DIALOG")
  pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  pop:SetBackdropColor(0.03, 0.02, 0.01, 1)
  pop:Hide()
  pop.rows = {}
  for i = 1, LAYOUT.popupRows do
    local b = CreateFrame("Button", nil, pop)
    b:SetSize(LAYOUT.popupW - 10, 26); b:SetPoint("TOPLEFT", 5, -6 - (i - 1) * 26)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 5, 0)
    b.name = fontString(b, "GameFontHighlight", 29, -7)
    b.right = fontString(b, "GameFontDisable", -5, -7, "TOPRIGHT")
    b:SetScript("OnClick", function(s) if s.id then search:SetText(""); search:ClearFocus(); pop:Hide(); M.Navigate(s.id, true) end end)
    pop.rows[i] = b
  end
  pop.foot = fontString(pop, "GameFontDisable", 10, -(10 + 26 * LAYOUT.popupRows))
  win.popup = pop
  local function update(text)
    local rows, total = M.SearchPopup(text)
    if (text or "") == "" then pop:Hide(); return end
    for i, b in ipairs(pop.rows) do
      local r = rows[i]
      if r then
        b.id = r.id; b.name:SetText(r.name); b.right:SetText(r.right); setColor(b.name, i == 1 and GOLD or { 1, 1, 1 })
        if b.icon.SetTexture then b.icon:SetTexture(itemIcon(r.id) or "Interface\\Icons\\INV_Misc_QuestionMark") end
        b:Show()
      else b.id = nil; b:Hide() end
    end
    pop.foot:SetText(total == 0 and "No material has a word starting with that." or
      (total .. " match" .. (total == 1 and "" or "es") .. ". Enter opens the top one."))
    pop:SetHeight(10 + 26 * math.max(1, #rows) + 22)
    pop.foot:ClearAllPoints(); pop.foot:SetPoint("TOPLEFT", 10, -(10 + 26 * math.max(1, #rows)))
    pop:Show()
  end
  M.UpdateSearch = update
  search:HookScript("OnTextChanged", function(s) update(s:GetText()) end)
  search:SetScript("OnEnterPressed", function(s)
    local id = M.ParseItem(s:GetText()); s:ClearFocus(); pop:Hide()
    if id then s:SetText(""); M.Navigate(id, true) end
  end)
  search:HookScript("OnEscapePressed", function() pop:Hide() end)
  search:HookScript("OnEditFocusLost", function() if C_Timer and C_Timer.After then C_Timer.After(0.2, function() pop:Hide() end) end end)
end

local function build()
  local W, H = LAYOUT.width, LAYOUT.height
  win = CreateFrame("Frame", "KennyDwarfExplorersBibleFrame", UIParent, "BackdropTemplate")
  win:SetSize(W, H)
  win:SetPoint("CENTER")
  win:SetFrameStrata("HIGH")
  win:SetClampedToScreen(true)
  win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  win:SetBackdropColor(LAYOUT.bg[1], LAYOUT.bg[2], LAYOUT.bg[3], LAYOUT.bg[4])
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "KennyDwarfExplorersBibleFrame")
  fontString(win, "GameFontNormalLarge", 14, -12):SetText("Dwarf Explorer's Bible")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  buildSearch()

  -- Back + breadcrumb
  local back = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  back:SetSize(60, 22); back:SetPoint("TOPLEFT", 14, -38); back:SetText("Back")
  back:SetScript("OnClick", M.GoBack)
  win.back = back
  local crumb = CreateFrame("Button", nil, win)
  crumb:SetSize(160, 18); crumb:SetPoint("LEFT", back, "RIGHT", 10, 0)
  crumb.text = fontString(crumb, "GameFontHighlight", 0, -3)
  crumb:SetScript("OnClick", M.GoBack)
  win.crumbPrev = crumb
  local arrow = win:CreateTexture(nil, "ARTWORK")
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); arrow:SetSize(12, 12)
  arrow:SetPoint("LEFT", crumb, "RIGHT", 4, 0)
  win.crumbArrow = arrow
  win.crumbCur = fontString(win, "GameFontHighlight", 0, 0, "LEFT")
  win.crumbCur:ClearAllPoints(); win.crumbCur:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
  rule(-66)

  -- Header
  win.icon = win:CreateTexture(nil, "ARTWORK"); win.icon:SetSize(44, 44); win.icon:SetPoint("TOPLEFT", 14, -74)
  win.name = fontString(win, "GameFontNormalHuge", 68, -74)
  win.price = fontString(win, "GameFontHighlightLarge", -16, -74, "TOPRIGHT")
  win.priceFrom = fontString(win, "GameFontDisable", -16, -96, "TOPRIGHT")
  win.counts = fontString(win, "GameFontHighlight", 68, -102)
  win.counts:SetJustifyH("LEFT"); win.counts:SetWordWrap(false)
  rule(-124)

  -- Filters (remembered in SavedVariables) and the mode button
  local label = fontString(win, "GameFontNormal", 14, -138)
  label:SetText("Show only:")
  local prevAnchor, x = label, 8
  local function check(key, text)
    local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    cb:SetSize(24, 24); cb:SetPoint("LEFT", prevAnchor, "RIGHT", x, 0)
    if isTable(cb.Text) then cb.Text:SetText(text) end
    cb:SetScript("OnClick", function(s) M.SetFilter(key, s:GetChecked()) end)
    prevAnchor, x = isTable(cb.Text) and cb.Text or cb, 14
    return cb
  end
  win.fKnown = check("filterKnown", "Known")
  win.fMine = check("filterMine", "My professions")
  win.fPriced = check("filterPriced", "Has a price")
  local mode = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  mode:SetSize(96, 22); mode:SetPoint("TOPRIGHT", -14, -132)
  mode:SetScript("OnClick", function()
    state.mode = state.mode == "uses" and "made" or "uses"; state.offset = 0; state.selected = nil; M.Refresh()
  end)
  win.modeBtn = mode
  win.count = fontString(win, "GameFontHighlight", 0, 0, "RIGHT")
  win.count:ClearAllPoints(); win.count:SetPoint("RIGHT", mode, "LEFT", -8, 0)

  -- Recipe rows
  local top, RH, rowW = LAYOUT.rowsTop, LAYOUT.rowH, W - 24 - 20
  local well = win:CreateTexture(nil, "BACKGROUND")
  well:SetColorTexture(0, 0, 0, 0.27); well:SetPoint("TOPLEFT", 12, -(top - 2)); well:SetSize(rowW, RH * LAYOUT.rows + 4)
  win.rows = {}
  for i = 1, LAYOUT.rows do
    local row = CreateFrame("Button", nil, win)
    row:SetSize(rowW, RH); row:SetPoint("TOPLEFT", 12, -top - (i - 1) * RH)
    if i % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND"); stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.03)
    end
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local hl = row:GetHighlightTexture()
    if isTable(hl) then hl:SetAlpha(LAYOUT.hoverAlpha) end
    row.selected = row:CreateTexture(nil, "ARTWORK")
    row.selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1); row.selected:SetSize(3, RH - 2); row.selected:SetPoint("LEFT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(32, 32); row.icon:SetPoint("TOPLEFT", 4, -4)
    if row.icon.SetTexCoord then row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    row.name = fontString(row, "GameFontNormal", 44, -5)
    row.name:SetWordWrap(false); row.name:SetWidth(rowW - 44 - 120)
    row.money = fontString(row, "GameFontHighlight", -8, -5, "TOPRIGHT")
    row.reag = fontString(row, "GameFontHighlight", 44, -22)
    row.reag:SetTextColor(0.78, 0.78, 0.78); row.reag:SetWordWrap(false); row.reag:SetWidth(rowW - 44 - 220)
    row.right = fontString(row, "GameFontDisable", -8, -22, "TOPRIGHT")
    row:SetScript("OnClick", function(s) M.ClickRow(s.entry); rowTooltip(s) end)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.rows[i] = row
  end
  local scroll = CreateFrame("ScrollFrame", "KennyDwarfExplorersBibleScroll", win, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -(top - 2)); scroll:SetSize(rowW, RH * LAYOUT.rows + 4)
  scroll:SetScript("OnVerticalScroll", function(s, value)
    if FauxScrollFrame_OnVerticalScroll then FauxScrollFrame_OnVerticalScroll(s, value, RH, function() refreshRows() end) end
  end)
  win.scroll = scroll
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function(_, delta)
    local bar = scroll.ScrollBar
    if isTable(bar) and bar.GetValue and bar.SetValue and bar:GetValue() then bar:SetValue(bar:GetValue() - delta * RH * 3)
    else state.offset = math.max(0, math.min(state.offset - delta * 3, math.max(0, #state.list - LAYOUT.rows))); refreshRows() end
  end)

  -- Chain strip
  local cy = top + RH * LAYOUT.rows + 12
  rule(-(cy - 4))
  win.chainLabel = fontString(win, "GameFontNormal", 14, -(cy + 1))
  win.chain, win.arrows = {}, {}
  for i = 1, LAYOUT.chainSteps do
    local b = CreateFrame("Button", nil, win)
    b:SetSize(LAYOUT.chainStepMaxW, 36)
    b.cur = b:CreateTexture(nil, "BACKGROUND"); b.cur:SetAllPoints(); b.cur:SetColorTexture(1, 0.82, 0, 0.14)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("TOPLEFT", 3, -3)
    b.name = fontString(b, "GameFontHighlight", 25, -3); b.name:SetWordWrap(false)
    b.sub = fontString(b, "GameFontDisable", 25, -19); b.sub:SetWordWrap(false)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function(s) if s.id and s.id ~= state.id then M.Navigate(s.id, true) end end)
    win.chain[i] = b
    local a = win:CreateTexture(nil, "ARTWORK")
    a:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); a:SetSize(12, 12); a:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    win.arrows[i] = a
  end

  -- Drops from (learned from your kills); the + opens the full list over the recipe rows.
  local dy = cy + 46
  rule(-(dy - 4))
  local plus = CreateFrame("Button", nil, win)
  plus:SetSize(16, 16); plus:SetPoint("TOPLEFT", 14, -(dy + 2))
  plus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
  plus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  win.dropsTitle = fontString(win, "GameFontNormal", 36, -(dy + 3))
  win.dropsText = fontString(win, "GameFontDisable", 0, 0, "LEFT")
  win.dropsText:ClearAllPoints(); win.dropsText:SetPoint("LEFT", win.dropsTitle, "RIGHT", 10, 0)
  win.dropsText:SetJustifyH("LEFT"); win.dropsText:SetWordWrap(false)
  local panel = CreateFrame("Frame", nil, win, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", 12, -(top - 2)); panel:SetSize(rowW, RH * LAYOUT.rows + 4)
  panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); panel:SetBackdropColor(0.04, 0.03, 0.015, 1)
  panel:SetFrameLevel((win:GetFrameLevel() or 0) + 10)
  panel:Hide()
  panel.lines = {}
  for i = 1, 16 do panel.lines[i] = fontString(panel, "GameFontHighlight", 12, -8 - (i - 1) * 20) end
  panel.empty = fontString(panel, "GameFontDisable", 12, -8)
  win.dropsPanel = panel
  plus:SetScript("OnClick", function()
    panel:SetShown(not panel:IsShown())
    plus:SetNormalTexture(panel:IsShown() and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    refreshDrops()
  end)
  win.dropsToggle = plus

  -- Footer
  rule(-(H - 46), 0.2)
  local key = fontString(win, "GameFontHighlight", 14, -(H - 40))
  key:SetTextColor(0.78, 0.78, 0.78)
  key:SetText("Colours:  |cffff8040orange|r skill too low   |cffffff00yellow|r / |cff40bf40green|r skill-up   |cff808080grey|r no skill-up")
  win.foot = fontString(win, "GameFontDisable", 14, -(H - 24))
end

function M.Open(id)
  if not win then build() end
  win:Show()
  if id then M.Navigate(id, true) else M.Refresh() end
end

function M.Toggle()
  if win and win:IsShown() then win:Hide() else M.Open() end
end

function M.Frame() return win end
