-- The Guide window (1.3.0 layout, from UI Bot's tabbed spec /workspace/wow-addons/deb-1.3.0-ui-spec.md): a title bar
-- with the search box, four tabs (Materials | Shopping | Seeds | Alts, Nav.lua), and one pane per tab. This file
-- builds the window, the tab bar and the Materials pane: Back + breadcrumb, the picked material with its price and
-- price-source badge, the fixed 38 px "Right Here / Nearest Spot" card, "Show only" filters (Make now) and the
-- Best skill-up sort, one row per recipe, the crafting chain strip, and the mobs it drops from (Drops.lua).
-- The other three panes are in UITabs.lua (M.RegisterPane).
-- LAYOUT.STRIP_MODE "hover" (default, Kenny Nov 20): one click opens a row; the strip follows the row you point at
-- and stays on it after the mouse leaves. "click": the first click puts a row in the strip, a second click opens it.
-- Combat: nothing here is a protected frame, and still no SetPoint / SetSize / SetWidth / SetHeight runs while
-- InCombatLockdown() is true; text, colours and Show/Hide only. Layout that depends on text width waits for
-- PLAYER_REGEN_ENABLED (M.LayoutPending()).
local _, ns = ...
local C, M = ns.Compat, ns.RM

-- Everything UI Bot may want to tweak lives here.
local LAYOUT = {
  width = 660, height = 702,             -- 1.2.0's 632 + 30 (tab bar) + 40 (callout card)
  bg = { 0.05, 0.04, 0.02, 1 },          -- opaque (Kenny's pick); the old window was 0.94 over a tooltip texture
  STRIP_MODE = "hover",                  -- "hover" or "click" (see the top of this file)
  tabTop = 38, tabH = 26, tabW = 152, tabGap = 8, tabRule = 68,   -- 4 x 152 + 3 x 8 = 632 px
  navTop = 72, navRule = 98, headerTop = 102,
  cardTop = 154, cardH = 38,             -- Right Here / Nearest Spot card: fixed height, never resized
  filtersTop = 198, hintTop = 223,       -- the grey hint under the filters sits in its own 14 px slot
  rows = 8, rowH = 40, rowsTop = 238,
  chainH = 34,                           -- one chain step: icon + two 12 pt lines
  searchW = 210, popupW = 300, popupRows = 8,
  chainSteps = 4, chainStepMaxW = 150,
  hoverAlpha = 0.08,                     -- keeps grey (808080) text at 4.5:1 or better on the row stripe
  dropsHeadH = 30, dropsLineH = 20,      -- Drops overlay: header row, then one line per mob
  listTop = 122, listRows = 13,          -- Shopping and Alts wells (UITabs.lua): 13 x 40 px
  seedRows = 10,                         -- Seeds well: 10 x 40 px
}
M.LAYOUT = LAYOUT
local DIFF = { orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 } }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }                -- recipes with no skill data (grey means "no skill-up")
local MIST = { 0.74, 0.83, 0.90 }        -- Mist (BCD3E6), the style table's idle / hint text
local BRIGHT = { 0.45, 1.0, 0.50 }       -- "here" pills and tooltip lines
local SHORT = { 1, 0.35, 0.35 }          -- shortage / alert
local PROFIT = { 0.20, 1, 0.20 }
-- Tab and card fills (spec section 1; contrast checked with UI Bot's contrast.py, all >= 4.5:1).
local TAB = { active = { 0.14, 0.11, 0.05, 1 }, idle = { 0.08, 0.07, 0.05, 1 } }
local CARD = {
  here = { fill = { 0.06, 0.14, 0.08, 1 }, pill = { 0.10, 0.24, 0.12, 1 }, text = BRIGHT },
  away = { fill = { 0.09, 0.08, 0.05, 1 }, pill = { 0.15, 0.12, 0.06, 1 }, text = GOLD },
  none = { fill = { 0.09, 0.08, 0.05, 1 }, pill = { 0.15, 0.12, 0.06, 1 }, text = MIST },
}
local BADGE = { 0.10, 0.09, 0.06, 1 }
M.COLORS = { DIFF = DIFF, GOLD = GOLD, WHITE = WHITE, MIST = MIST, BRIGHT = BRIGHT, SHORT = SHORT, PROFIT = PROFIT, TAB = TAB, CARD = CARD, BADGE = BADGE }
local function hex(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
M.Hex = hex
-- Vertical positions derived from LAYOUT (the headless render in notes/deb-1.3.0-render reads these too).
function M.LayoutY()
  local L = LAYOUT
  local chainTop = L.rowsTop + L.rows * L.rowH + 10     -- the rule above the chain strip
  local dropsTop = chainTop + 18 + L.chainH + 10         -- the rule above "Drops from"
  return { chainTop = chainTop, chainLabel = chainTop + 1, chainSteps = chainTop + 18, dropsTop = dropsTop,
    dropsLine = dropsTop + 4, footRule = L.height - 44, footKey = L.height - 40, footNote = L.height - 24 }
end
-- Mob lines that fit in the Drops overlay under its header (it covers the recipe rows; no scrollbar).
function M.DropsLines()
  local L = LAYOUT
  return math.floor((L.rows * L.rowH + 4 - L.dropsHeadH - 8 - 4) / L.dropsLineH)
end
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
M.READY = READY

local win
local state = { id = nil, mode = "uses", offset = 0, history = {}, list = {}, total = 0, selected = nil }
local function hoverMode() return LAYOUT.STRIP_MODE ~= "click" end
function M.StripLabel()
  if state.mode ~= "uses" then return "Where the selected recipe's reagent comes in:" end
  return hoverMode() and "Crafting chain for the row you point at:" or "Crafting chain for the selected row:"
end

local function isTable(v) return type(v) == "table" end

-- Layout in combat: never. Width-dependent layout is skipped and redone when combat ends.
local layoutPending = false
local function canLayout()
  if C.InCombat() then layoutPending = true; return false end
  return true
end
function M.LayoutPending() return layoutPending end

local function itemIcon(id)
  if not (C_Item and C_Item.GetItemIconByID) then return nil end
  local ok, icon = pcall(C_Item.GetItemIconByID, id)
  return ok and C.SafeNumber(icon) or nil
end
M.ItemIcon = itemIcon

-- Text helpers (also used by the tests) -----------------------------------------------------
local function profSkill(r) return r.prof .. ((r.skill or 0) > 0 and (" " .. r.skill) or "") end

-- Header: name, the counts / camp / bag line, price and where the price is from.
function M.HeaderText(id)
  local uses, made = M.byReagent[id] or {}, M.byProduct[id] or {}
  local parts = {}
  if #uses > 0 or #made > 0 then
    local profs, seen = {}, {}
    for _, r in ipairs(made) do if not seen[r.prof] then seen[r.prof] = true; profs[#profs + 1] = r.prof end end
    local madeBy = #made > 0 and ("Made by |cffffffff%d|r (%s)"):format(#made, table.concat(profs, ", ")) or "Not crafted"
    parts[#parts + 1] = ("Used in |cffffffff%d|r recipe%s  ·  %s"):format(#uses, #uses == 1 and "" or "s", madeBy)
  end
  local have = M.HaveText and ns.Inventory and M.HaveText(ns.Inventory.Count(id))
  if have then parts[#parts + 1] = "|cffffffff" .. have .. "|r" end
  local camp = {}
  for _, c in ipairs(M.CampUses(id) or {}) do camp[#camp + 1] = M.CampText(c) end
  if #camp > 0 then parts[#parts + 1] = "|cffffd100Camp:|r  |cffffffff" .. table.concat(camp, "  ·  ") .. "|r" end
  local off = M.CampOff(id)
  if off then parts[#parts + 1] = "|cffff7373" .. off .. "|r" end
  local p, label = M.Price(id)
  return M.Name(id), table.concat(parts, "  ·  "), p and C.Money(p) or "|cffaaaaaano price yet|r", p and ("each, from " .. label) or ""
end

-- The subtle price-source badge under the price: "Forever baseline (Nov 27)", "PriceLog 2h ago", "Auctionator", or
-- "" when the item has no price.
function M.FreshnessBadge(id)
  local r = M.Resolve(id, "sell")
  if not r.price then return "" end
  if r.source == "baseline" then
    if r.t then return ("Forever baseline (%s %d)"):format(date("%b", r.t), tonumber(date("%d", r.t))) end
    return "Forever baseline"
  end
  if r.ageSeconds then return ("%s %s ago"):format(r.label, M.Ago(r.ageSeconds)) end
  return r.label or ""
end

-- Reagent line with what you hold: "6 Copper Bar (14)" white when you have enough, soft red when short, plus a
-- quiet [Vendor] tag when a remembered merchant sells it.
function M.ReagentLine(r)
  local PL = ns.Planner
  local parts = {}
  if PL and PL.ReagentStatus then
    for _, g in ipairs(PL.ReagentStatus(r)) do
      parts[#parts + 1] = (g.enough and hex(WHITE) or hex(SHORT)) .. ("%d %s (%d)"):format(g.n, M.Name(g.id), g.have) .. "|r"
        .. (g.vendor and (" " .. hex(MIST) .. "[Vendor]|r") or "")
    end
  else
    for _, g in ipairs(r.reagents) do parts[#parts + 1] = g.n .. " " .. M.Name(g.id) end
  end
  return table.concat(parts, ", ")
end

local function moneyText(v, suffix)
  return (v >= 0 and "|cff33ff33+" or "|cffff6060-") .. C.Money(math.abs(v)) .. (suffix or "") .. "|r"
end

-- Profit text for a row: "+12s" when you hold none of the mats; "+12s buy all  ·  +38s w/ bags" when you hold some;
-- "no price" when a price is missing (never 0g).
function M.ProfitText(r)
  local pl = M.ProfitLines(r)
  local buy, bags = pl.buyAll.profit, pl.withBags.profit
  if pl.single or not bags then
    if buy then return moneyText(buy) end
    return "|cffaaaaaano price|r"
  end
  return (buy and moneyText(buy, " buy all") or "|cffaaaaaano price|r") .. "  ·  " .. moneyText(bags, " w/ bags")
end

-- One row: name line (difficulty colour, quantity, "> N more uses"), profit, reagents (with bag counts), profession + learned.
function M.RowText(e)
  local r = e.r
  local qty = r.max == 1 and "" or (r.min == r.max and (" x" .. r.min) or (" x" .. r.min .. "-" .. r.max))
  local nextN = #(M.byReagent[r.product] or {})
  local name = M.Name(r.product) .. "|cffffffff" .. qty .. "|r" .. (nextN > 0 and ("  |cff66ccff> " .. nextN .. " more use" .. (nextN == 1 and "" or "s") .. "|r") or "")
  local money = M.ProfitText(r)
  local skill = M.Skill(r.prof)
  local d = M.Difficulty(r)
  local right = profSkill(r) .. (d == "orange" and skill and (" (you " .. skill .. ")") or "")
  right = right .. (M.Knows(r) and (" " .. READY) or "  |cffff8080not learned|r")
  return name, money, M.ReagentLine(r), right, d
end

-- Right Here / Nearest Spot card ------------------------------------------------------------
-- { kind = "vendorHere" | "farmHere" | "vendor" | "nearest" | "unplaced" | "none", style = "here" | "away" | "none",
--   pill (nil for "none"), detail }. One pill line and one detail line (cut with "..." when long); the card's size
-- never changes. zone / level default to where you stand (Where.PlayerZone, Where.PlayerLevel).
local function vendorWhere(v) return v.subzone and (v.subzone .. ", " .. v.zone) or v.zone end
local function levelBand(e)
  if e.levelMin and e.levelMax then return (" (%d–%d)"):format(e.levelMin, e.levelMax) end
  return ""
end
-- "Mobs: Frostmane Troll Whelp 25%, Rockjaw Trogg 12% · You mined it there 3 times"
local GATHER_VERB = { herb = "picked", mine = "mined", skin = "skinned", fish = "fished" }
local function sourceSummary(e)
  local bits = {}
  local mobs = {}
  for i = 1, math.min(2, #e.mobs) do
    local m = e.mobs[i]
    mobs[#mobs + 1] = ("%s %d%%"):format(m.name or ("mob " .. m.cid), m.pct or 0)
  end
  if #mobs > 0 then bits[#bits + 1] = "Mobs: " .. table.concat(mobs, ", ") .. (#e.mobs > 2 and (" +" .. (#e.mobs - 2)) or "") end
  for _, g in ipairs(e.gather) do
    bits[#bits + 1] = ("You %s it there %d %s"):format(GATHER_VERB[g.kind] or "found", g.n, g.n == 1 and "time" or "times")
  end
  return table.concat(bits, " · ")
end
function M.CalloutCard(id, zone, level)
  local W = ns.Where
  if not (W and id) then return { kind = "none", style = "none", detail = "" } end
  local wf = W.WhereToFarm(id, zone, level)
  local localV, anyV
  for _, v in ipairs(wf.vendors) do
    if not v.limited then
      if v.inZone and not localV then localV = v end
      if not anyV then anyV = v end
    end
  end
  anyV = anyV or wf.vendors[1]
  if localV then
    return { kind = "vendorHere", style = "here", pill = "Vendor here",
      detail = ("%s (%s) — %s%s"):format(localV.npc, vendorWhere(localV), C.Money(localV.price), wf.here and " · Farmable here" or "") }
  end
  if wf.here then
    local s = sourceSummary(wf.here)
    return { kind = "farmHere", style = "here", pill = "Farm right here in " .. wf.here.zone,
      detail = s ~= "" and s or "You've found it in this zone before." }
  end
  local near = wf.nearby[1]
  local vText
  if anyV then
    vText = ("Vendor: %s (%s) — %s%s"):format(anyV.npc, vendorWhere(anyV), C.Money(anyV.price), anyV.limited and " (limited stock)" or "")
  elseif wf.vendorPrice then
    vText = ("Sold by vendors — %s. Open a vendor's window to remember who sells it."):format(C.Money(wf.vendorPrice.price))
  end
  if near then
    local s = sourceSummary(near)
    return { kind = "nearest", style = "away", pill = "Nearest spot: " .. near.zone .. levelBand(near),
      detail = (s ~= "" and s or near.zone) .. (vText and (" · " .. vText) or "") }
  end
  if vText then
    return { kind = "vendor", style = "away", pill = "Vendor", detail = anyV and vText:gsub("^Vendor: ", "") or vText }
  end
  if #wf.unplaced > 0 then
    local names = {}
    for i = 1, math.min(3, #wf.unplaced) do names[#names + 1] = wf.unplaced[i].name or ("mob " .. wf.unplaced[i].cid) end
    return { kind = "unplaced", style = "away", pill = "Drops from mobs",
      detail = table.concat(names, ", ") .. " (zone not seen yet: kill one and DEB remembers where)" }
  end
  local crafted = M.byProduct[id] ~= nil
  return { kind = "none", style = "none",
    detail = crafted and "Crafted item — not farmed in the world. Visit vendors to remember vendor goods."
      or "Not seen in the world yet. Loot, gather or visit vendors and DEB remembers where." }
end

-- The chain strip, built from recipe data only (never from the pages you came through). Each step is { id, sub, current }.
-- Used in: this item (start here) > the row's product > that product's most profitable next step. Before you point at
-- a row: this item's own chain, its most profitable use at each step.
-- Made from: the row's first reagent > this item (made by the row's profession); before a row, its first recipe.
function M.ChainSteps(id, e)
  local steps = {}
  if not id then return steps end
  if state.mode == "uses" then
    steps[1] = { id = id, sub = "start here", current = true }
    local cur, seen, maxN = id, { [id] = true }, LAYOUT.chainSteps
    if e then
      steps[2] = { id = e.r.product, sub = profSkill(e.r) }
      seen[e.r.product], cur, maxN = true, e.r.product, 3
    end
    while #steps < maxN do
      local nxt = M.BestNext(cur)
      if not nxt or seen[nxt.r.product] then break end
      steps[#steps + 1] = { id = nxt.r.product, sub = profSkill(nxt.r) }
      seen[nxt.r.product], cur = true, nxt.r.product
    end
  else
    local r = e and e.r or (M.byProduct[id] or {})[1]
    local g = r and r.reagents[1]
    if g then steps[1] = { id = g.id, sub = "reagent" } end
    steps[#steps + 1] = { id = id, sub = r and profSkill(r) or "", current = true }
  end
  while #steps > LAYOUT.chainSteps do table.remove(steps) end
  return steps
end

-- "Drops from (N kills)" and a short summary for the collapsed line. N counts only the mobs listed (those with
-- a rate, MIN_LOOTS combined kills or more); with none listed yet the title is plain "Drops from".
function M.DropsSummary(id)
  local Dr = ns.Drops
  if not (Dr and id) then return "Drops from", "", {} end
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
    summary = ("Seen from %d mob%s; a rate shows after %d kills of one."):format(s.learning, s.learning == 1 and "" or "s", Dr.MIN_LOOTS)
  else
    summary = "Not seen yet: learns from corpses you loot."
  end
  local shown = 0
  for _, e in ipairs(s.rows) do shown = shown + e.loots end
  return shown > 0 and ("Drops from (%d kills)"):format(shown) or "Drops from", summary, s.rows
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
  -- Keep the row in the strip if it's still listed. Click mode starts on the most profitable row (the list is
  -- best-first); hover mode starts on the page item's own chain.
  local keep
  for _, e in ipairs(state.list) do if state.selected and e.r == state.selected.r then keep = e end end
  state.selected = keep or (not hoverMode() and state.list[1] or nil)
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
local function setFill(tex, c) if tex.SetColorTexture then tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end end

local function refreshRows()
  local n = LAYOUT.rows
  if win.scroll and FauxScrollFrame_Update then
    FauxScrollFrame_Update(win.scroll, #state.list, n, LAYOUT.rowH)
    state.offset = FauxScrollFrame_GetOffset(win.scroll)
  end
  -- The scrollbar only when the list doesn't fit (FauxScrollFrame_Update does this too), and never under the overlay.
  if win.scroll then win.scroll:SetShown(#state.list > n and not win.dropsPanel:IsShown()) end
  state.offset = math.max(0, math.min(state.offset, math.max(0, #state.list - n)))
  for i = 1, n do
    local row, e = win.rows[i], state.list[i + state.offset]
    if e then
      local name, money, reag, right, d = M.RowText(e)
      row.name:SetText(name); setColor(row.name, d and DIFF[d] or WHITE)
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

-- In combat the strip keeps its last layout: only the steps that were laid out show (texts and icons change, sizes
-- and points don't); the full layout runs again when combat ends.
local laidOut = 0
local function refreshChain()
  local steps = M.ChainSteps(state.id, state.selected)
  if not canLayout() then
    for i = 1, LAYOUT.chainSteps do
      local b, s = win.chain[i], steps[i]
      if s and i <= laidOut then
        b.name:SetText(M.Name(s.id)); b.sub:SetText(s.sub)
        if b.icon.SetTexture then b.icon:SetTexture(itemIcon(s.id) or "Interface\\Icons\\INV_Misc_QuestionMark") end
        b.cur:SetShown(s.current == true); b.id = s.id; b:Show()
        win.arrows[i]:SetShown(steps[i + 1] ~= nil and i < laidOut)
      else b.id = nil; b:Hide(); win.arrows[i]:Hide() end
    end
    win.chainLabel:SetText(M.StripLabel())
    return
  end
  local avail = LAYOUT.width - 28
  local ws, total = chainWidths(steps)
  if total > avail and #steps > 3 then table.remove(steps); ws, total = chainWidths(steps) end   -- drop the deepest step first
  if total > avail then
    local scale = (avail - 20 * (#steps - 1)) / (total - 20 * (#steps - 1))
    for i = 1, #ws do ws[i] = math.max(60, math.floor(ws[i] * scale)) end
  end
  local x = 14
  local top = M.LayoutY().chainSteps
  for i = 1, LAYOUT.chainSteps do
    local b, s = win.chain[i], steps[i]
    if s then
      b.name:SetText(M.Name(s.id)); b.sub:SetText(s.sub)
      if b.icon.SetTexture then b.icon:SetTexture(itemIcon(s.id) or "Interface\\Icons\\INV_Misc_QuestionMark") end
      local w = ws[i]
      b.name:SetWidth(w - 28); b.sub:SetWidth(w - 28)
      b:SetWidth(w); b:ClearAllPoints(); b:SetPoint("TOPLEFT", win.panes.materials, "TOPLEFT", x, -top)
      b.cur:SetShown(s.current == true)
      b.id = s.id; b:Show()
      x = x + w
      local arrow = win.arrows[i]
      if steps[i + 1] then arrow:ClearAllPoints(); arrow:SetPoint("TOPLEFT", win.panes.materials, "TOPLEFT", x + 3, -(top + 5)); arrow:Show(); x = x + 20
      else arrow:Hide() end
    else b.id = nil; b:Hide(); win.arrows[i]:Hide() end
  end
  laidOut = #steps
  win.chainLabel:SetText(M.StripLabel())
end

local function refreshDrops()
  local title, summary, rows = M.DropsSummary(state.id)
  win.dropsTitle:SetText(title); win.dropsText:SetText(summary)
  local btnW = (win.exportBtn and 110 + 6 + 110 + 14) or 14
  if canLayout() then win.dropsText:SetWidth(math.max(40, LAYOUT.width - 36 - (win.dropsTitle:GetStringWidth() or 0) - 10 - btnW)) end
  local p = win.dropsPanel
  if p:IsShown() then
    local Dr = ns.Drops
    p.title:SetText(title)
    -- Every mob that fits; if there are more, the last line says how many (no scrollbar in the overlay).
    local fit = #p.lines
    local shown = #rows > fit and fit - 1 or #rows
    for i = 1, fit do
      local e = rows[i]
      if i <= shown then
        p.lines[i]:SetText(("%s:  |cffffffff%d%%|r  |cffaaaaaa(%s)|r"):format(Dr.MobName(e.cid), Dr.Percent({ seen = e.seen, loots = e.loots }), Dr.Label(e.loots)))
        p.lines[i]:Show()
      elseif i == shown + 1 and #rows > fit then
        p.lines[i]:SetText(("|cffaaaaaa+%d more mobs|r"):format(#rows - shown)); p.lines[i]:Show()
      else p.lines[i]:Hide() end
    end
    p.empty:SetShown(#rows == 0)
    p.empty:SetText(summary)
  end
end

-- The card: colours, pill and detail only (its frame is never resized or moved).
local function refreshCard()
  local card = win.card
  local c = state.id and M.CalloutCard(state.id) or { kind = "none", style = "none",
    detail = "Pick a material to see where to farm it or which vendor sells it." }
  local st = CARD[c.style] or CARD.none
  setFill(card.fill, st.fill)
  card.kind = c.kind
  if c.pill then
    card.pill:SetText(c.pill); setColor(card.pill, st.text); setFill(card.pillBg, st.pill)
    card.pill:Show(); card.pillBg:Show()
    card.detail:SetText(c.detail); card.detail:Show(); card.quiet:Hide()
  else
    card.pill:Hide(); card.pillBg:Hide(); card.detail:Hide()
    card.quiet:SetText(c.detail); card.quiet:Show()
  end
end

-- What "+ Shop" in the header adds: a crafted item's missing mats (its first recipe), else one of the item itself.
function M.ShopHeaderAction(id)
  local S = ns.Shopping
  if not (S and id) then return 0, nil end
  local made = M.byProduct[id]
  if made and made[1] then
    local r = (state.mode == "made" and state.selected and state.selected.r) or made[1]
    local n = S.AddRecipe(r, 1)
    return n, n > 0 and ("added %d missing mat%s for %s to Shopping"):format(n, n == 1 and "" or "s", M.Name(r.product))
      or ("you already have the mats for %s"):format(M.Name(r.product))
  end
  local ok = S.AddItem(id, 1, "manual")
  return ok and 1 or 0, ok and ("added %s to Shopping"):format(M.Name(id)) or "shopping list is full (60 items)"
end

-- A row's "+": the recipe's missing mats for one craft.
function M.ShopRow(e)
  local S = ns.Shopping
  if not (S and e) then return 0 end
  local n = S.AddRecipe(e.r, 1)
  if ns.Core then
    ns.Core.Print(n > 0 and ("added %d missing mat%s for %s to Shopping"):format(n, n == 1 and "" or "s", M.Name(e.r.product))
      or ("you already have the mats for %s"):format(M.Name(e.r.product)))
  end
  return n
end

local KEYS = {
  materials = "Colours:  |cffff8040orange|r skill too low   |cffffff00yellow|r / |cff40bf40green|r skill-up   |cff808080grey|r no skill-up",
  shopping = "Tick a line when you have it. Vendors and alts come first, so you spend less at the AH.",
  seeds = "Information only: DEB never plants or uses anything for you.",
  alts = "Each character updates when you log in on it and open its professions and bank.",
}
M.FOOT_KEYS = KEYS

function M.Refresh()
  buildList()
  if not win then return end
  local id = state.id
  if not id then
    win.name:SetText("Type a material, or Alt-click an item."); win.counts:SetText(""); win.price:SetText(""); win.priceFrom:SetText("")
    if win.icon.SetTexture then win.icon:SetTexture(nil) end
  else
    local name, counts, price = M.HeaderText(id)
    win.name:SetText(name); win.counts:SetText(counts)
    win.price:SetText(price .. (M.Price(id) and " |cffaaaaaaeach|r" or ""))
    win.priceFrom:SetText(M.FreshnessBadge(id))
    if win.icon.SetTexture then win.icon:SetTexture(itemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark") end
  end
  local badge = win.priceFrom:GetText() or ""
  win.badgeBg:SetShown(badge ~= "")
  win.shopBtn:SetShown(id ~= nil and ns.Shopping ~= nil)
  if canLayout() then
    local bw = badge ~= "" and ((win.priceFrom:GetStringWidth() or 0) + 12) or 0
    win.counts:SetWidth(LAYOUT.width - 68 - 16 - bw - 12)
  end
  -- Breadcrumb: the item you came from (click to go back) and this one.
  local prev = state.history[#state.history]
  win.crumbPrev:SetShown(prev ~= nil); win.crumbArrow:SetShown(prev ~= nil and id ~= nil)
  if prev then
    win.crumbPrev.text:SetText("|cff66ccff" .. M.Name(prev) .. "|r")
    if canLayout() then win.crumbPrev:SetWidth(math.min(220, (win.crumbPrev.text:GetStringWidth() or 0) + 2)) end
  end
  win.crumbCur:SetText(id and M.Name(id) or "")
  win.back:SetEnabled(#state.history > 0)
  win.modeBtn:SetText(state.mode == "uses" and "Made from" or "Used in")
  win.count:SetText(id and (#state.list .. " of " .. state.total) or "")
  local s = M.Settings()
  win.fKnown:SetChecked(s.filterKnown); win.fMine:SetChecked(s.filterMine); win.fPriced:SetChecked(s.filterPriced)
  win.fMake:SetChecked(s.filterMakeNow)
  win.fAlts:SetChecked(s.makeNowAlts); win.fAlts:SetShown(s.filterMakeNow == true)
  win.skillBtn:SetText(s.bestSkillUp and (READY .. " Best skill-up") or "Best skill-up")
  if s.bestSkillUp then win.skillBtn:LockHighlight() else win.skillBtn:UnlockHighlight() end
  local hint = M.FilterHint()
  win.hint:SetText(hint or ""); win.hint:SetShown(hint ~= nil)
  win.empty:SetText(M.EmptyText() or ""); win.empty:SetShown(M.EmptyText() ~= nil)
  win.foot:SetText(("Prices from %s (/deb sources). Profit is after the %d%% AH cut."):format(
    table.concat(ns.Prices.Installed(), ", "), math.floor((s.ahCut or 0.05) * 100 + 0.5)))
  refreshCard(); refreshRows(); refreshChain(); refreshDrops()
end

-- The friendly line in the recipe well when there is nothing to list (nil when rows show).
function M.EmptyText()
  if not state.id then return "Type a material above or click an item in your bags to see what it crafts." end
  if #state.list == 0 and state.total > 0 then return "No recipes match these filters. Try unchecking Make now or Known." end
  if state.total == 0 then return "Nothing uses this item in a recipe yet." end
  return nil
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
  local lines = M.ProfitLines(e.r)
  GameTooltip:AddDoubleLine("Reagent cost", C.Money(lines.buyAll.cost), 1, 0.82, 0)
  GameTooltip:AddDoubleLine("Sells for (after AH cut)", lines.value and (C.Money(lines.value) .. (pl and (" (" .. pl .. ")") or "")) or "no price", 1, 0.82, 0)
  if lines.buyAll.profit then GameTooltip:AddDoubleLine("Profit (buy all)", C.Money(math.abs(lines.buyAll.profit)) .. (lines.buyAll.profit < 0 and " loss" or ""), 0.2, 1, 0.2) end
  if not lines.single and lines.withBags.profit then
    GameTooltip:AddDoubleLine("Profit (using your bags)", C.Money(math.abs(lines.withBags.profit)) .. (lines.withBags.profit < 0 and " loss" or ""), 0.2, 1, 0.2)
  end
  if lines.ageSeconds then GameTooltip:AddLine("Oldest price used: " .. M.Ago(lines.ageSeconds) .. " old", 0.6, 0.6, 0.6) end
  local PL = ns.Planner
  local crafts = PL and PL.MaxCrafts(e.r) or 0
  if crafts > 0 then GameTooltip:AddLine(("You can make it %d time%s from your bags and bank."):format(crafts, crafts == 1 and "" or "s"), 0.2, 1, 0.2) end
  if pp == nil then GameTooltip:AddLine("Search it at the auction house to price it.", 0.6, 0.6, 0.6, true) end
  local open = state.mode == "uses" and "what can I make from this?" or "open its first reagent."
  if hoverMode() or state.selected == e then GameTooltip:AddLine("Click: " .. open, 0.4, 0.8, 1, true)
  else GameTooltip:AddLine("Click: show its crafting chain. Click again to open it.", 0.4, 0.8, 1, true) end
  GameTooltip:AddLine("+ at the right: add its missing mats to Shopping.", 0.4, 0.8, 1, true)
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

-- The grey hint under the filters while "My professions" has nothing to match yet.
function M.FilterHint()
  local s = M.Settings()
  if s and s.filterMine and not M.HasProfessions() then return "Open a profession window once to use this filter." end
  return nil
end

local function openRow(e)
  if state.mode == "uses" then M.Navigate(e.r.product, true)
  elseif e.r.reagents[1] then M.Navigate(e.r.reagents[1].id, true) end
end

-- Pointing at a row (hover mode): the strip follows it and stays on it after the mouse leaves.
function M.HoverRow(e)
  if not e or not hoverMode() or state.selected == e then return end
  state.selected = e
  if win then refreshRows(); refreshChain() end
end

-- Row click. Hover mode: open it. Click mode: the first click puts it in the strip, a second click opens it.
function M.ClickRow(e)
  if not e then return end
  if hoverMode() then openRow(e)
  elseif state.selected == e then openRow(e)
  else state.selected = e; if win then refreshRows(); refreshChain() end end
end

-- The Drops overlay over the recipe rows. The +/- button, Escape and Back close it.
function M.DropsOverlayShown() return win ~= nil and win.dropsPanel:IsShown() == true end
-- Escape, without ever taking the keyboard (no key handler, so no keybind can be swallowed, in or out of combat):
-- while the overlay is open it, not the window, is the one in UISpecialFrames, so Escape (CloseSpecialWindows)
-- closes just the overlay; once it's closed the window is back in the list. The list is never changed from inside
-- an OnHide: CloseSpecialWindows walks it with pairs() while it hides frames, so the panel's OnHide only updates the
-- button and defers the swap to the next frame.
local WIN_NAME, DROPS_NAME = "KennyDwarfExplorersBibleFrame", "KennyDwarfExplorersBibleDrops"
local function special(name, on)
  if type(UISpecialFrames) ~= "table" then return end
  for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end end
  if on then tinsert(UISpecialFrames, name) end
end
M.Special = special

-- Puts whichever of the overlay / window is showing in UISpecialFrames (from the panel's current state).
local function swapSpecial()
  if not win then return end
  local on = win.dropsPanel:IsShown() == true
  special(DROPS_NAME, on); special(WIN_NAME, not on)
end

local function overlayVisuals(on)
  win.dropsToggle:SetNormalTexture(on and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
  win.dropsToggle:SetPushedTexture(on and "Interface\\Buttons\\UI-MinusButton-Down" or "Interface\\Buttons\\UI-PlusButton-Down")
  if on then refreshDrops() end
  refreshRows()   -- hides the list's scrollbar under the overlay, brings it back after
end

-- The panel's OnHide (Escape, the window closing): button and scrollbar now, the UISpecialFrames swap next frame.
local function overlayHidden()
  overlayVisuals(false)
  if C_Timer and C_Timer.After then C_Timer.After(0, swapSpecial) else swapSpecial() end
end

function M.SetDropsOverlay(on)
  if not win then return end
  on = on and true or false
  win.dropsPanel:SetShown(on)
  overlayVisuals(on); swapSpecial()   -- from a click or Back, never from inside CloseSpecialWindows
end

-- Back: closes the Drops overlay if it's open (and stays on this page), else goes to the previous item.
function M.GoBack()
  if M.DropsOverlayShown() then M.SetDropsOverlay(false); return end
  local prev = table.remove(state.history)
  if prev then M.Navigate(prev, false) end
end

function M.State() return state end

local function rule(parent, y, a)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], a or 0.35)
  t:SetHeight(1); t:SetPoint("TOPLEFT", 10, y); t:SetPoint("TOPRIGHT", -10, y)
  return t
end

local function fontString(parent, template, x, y, point)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint(point or "TOPLEFT", x, y)
  -- A fontstring given a width centres its text unless told otherwise; follow the anchor side instead.
  fs:SetJustifyH(((point or "LEFT"):find("RIGHT") and "RIGHT") or ((point or "LEFT"):find("LEFT") and "LEFT") or "CENTER")
  return fs
end

-- A pill behind a font string: the fill is anchored to the text once, so it follows the text's width without any
-- SetWidth at run time (and so never in combat).
local function pill(parent, fs, padX, padY)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetPoint("TOPLEFT", fs, "TOPLEFT", -(padX or 6), padY or 3)
  t:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", padX or 6, -(padY or 3))
  return t
end

local function tip(frame, lines)
  frame:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local l = type(lines) == "function" and lines() or lines
    for i, s in ipairs(l) do
      if i == 1 then GameTooltip:AddLine(s) else GameTooltip:AddLine(s, 0.85, 0.85, 0.85, true) end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Shared bits for the other panes (UITabs.lua).
M.UIKit = { fontString = fontString, rule = rule, pill = pill, tip = tip, setColor = setColor, setFill = setFill,
  itemIcon = itemIcon, isTable = isTable, canLayout = canLayout, hex = hex }

local function buildSearch()
  local search = CreateFrame("EditBox", "KennyDwarfExplorersBibleSearch", win, "SearchBoxTemplate")
  search:SetSize(LAYOUT.searchW, 22); search:SetPoint("TOPRIGHT", -34, -9); search:SetAutoFocus(false)
  if isTable(search.Instructions) then search.Instructions:SetFontObject("GameFontDisable"); search.Instructions:SetText("Type a material") end   -- template default is 10 pt
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
    b:SetScript("OnClick", function(s) if s.id then search:SetText(""); search:ClearFocus(); pop:Hide(); M.Open(s.id) end end)
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
    if canLayout() then   -- in combat the popup keeps its full height
      pop:SetHeight(10 + 26 * math.max(1, #rows) + 22)
      pop.foot:ClearAllPoints(); pop.foot:SetPoint("TOPLEFT", 10, -(10 + 26 * math.max(1, #rows)))
    end
    pop:Show()
  end
  M.UpdateSearch = update
  search:HookScript("OnTextChanged", function(s) update(s:GetText()) end)
  search:SetScript("OnEnterPressed", function(s)
    local id = M.ParseItem(s:GetText()); s:ClearFocus(); pop:Hide()
    if id then s:SetText(""); M.Open(id) end   -- the search always opens Materials
  end)
  search:HookScript("OnEscapePressed", function() pop:Hide() end)
  search:HookScript("OnEditFocusLost", function() if C_Timer and C_Timer.After then C_Timer.After(0.2, function() pop:Hide() end) end end)
end

-- Tabs ------------------------------------------------------------------------------------------
local TAB_TIPS = {
  materials = "What a material crafts into, what it's worth and where to get it.",
  shopping = "Your shopping list: vendor first, then your alts, then the Auction House.",
  seeds = "Herb seeds, the Greenhouse and the Seed Hybridizer in your bags and bank.",
  alts = "Which of your characters can craft something, and who holds which mats.",
}
local function paintTabs(current)
  for tab, b in pairs(win.tabs) do
    local on = tab == current
    setFill(b.fill, on and TAB.active or TAB.idle)
    b.bar:SetShown(on)
    setColor(b.label, on and GOLD or MIST)
    b.active = on
  end
end

local function buildTabs()
  win.tabs = {}
  local Nav = ns.Nav
  for i, tab in ipairs(Nav.TABS) do
    local b = CreateFrame("Button", nil, win)
    b:SetSize(LAYOUT.tabW, LAYOUT.tabH)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * (LAYOUT.tabW + LAYOUT.tabGap), -LAYOUT.tabTop)
    b.fill = b:CreateTexture(nil, "BACKGROUND"); b.fill:SetAllPoints()
    b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    b.bar:SetHeight(2); b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("TOPRIGHT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, LAYOUT.hoverAlpha)
    b.label = fontString(b, "GameFontNormal", 0, 0, "CENTER")
    b.label:SetText(Nav.TITLES[tab])
    b.tab = tab
    b:SetScript("OnClick", function(s) Nav.ShowTab(s.tab) end)
    tip(b, { Nav.TITLES[tab], TAB_TIPS[tab] })
    win.tabs[tab] = b
  end
  rule(win, -LAYOUT.tabRule)
end

-- Panes: Materials is built here; UITabs.lua registers the others with M.RegisterPane(tab, { build, refresh, wheel }).
M.PANES = M.PANES or {}
function M.RegisterPane(tab, spec) M.PANES[tab] = spec end

local function buildMaterials(mp)
  local W = LAYOUT.width
  -- Back + breadcrumb
  local back = CreateFrame("Button", nil, mp, "UIPanelButtonTemplate")
  back:SetSize(60, 22); back:SetPoint("TOPLEFT", 14, -LAYOUT.navTop); back:SetText("Back")
  back:SetScript("OnClick", M.GoBack)
  win.back = back
  local crumb = CreateFrame("Button", nil, mp)
  crumb:SetSize(160, 18); crumb:SetPoint("LEFT", back, "RIGHT", 10, 0)
  crumb.text = fontString(crumb, "GameFontHighlight", 0, -3)
  crumb:SetScript("OnClick", M.GoBack)
  win.crumbPrev = crumb
  local arrow = mp:CreateTexture(nil, "ARTWORK")
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); arrow:SetSize(12, 12)
  arrow:SetPoint("LEFT", crumb, "RIGHT", 4, 0)
  win.crumbArrow = arrow
  win.crumbCur = fontString(mp, "GameFontHighlight", 0, 0, "LEFT")
  win.crumbCur:ClearAllPoints(); win.crumbCur:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
  rule(mp, -LAYOUT.navRule)

  -- Header: icon, name, counts (with bags/bank); price, its source badge and "+ Shop" on the right.
  local hy = LAYOUT.headerTop
  win.icon = mp:CreateTexture(nil, "ARTWORK"); win.icon:SetSize(44, 44); win.icon:SetPoint("TOPLEFT", 14, -hy)
  win.name = fontString(mp, "GameFontNormalHuge", 68, -hy)
  win.name:SetWordWrap(false); win.name:SetJustifyH("LEFT"); win.name:SetWidth(W - 68 - 16 - 230)
  win.price = fontString(mp, "GameFontHighlightLarge", -16, -hy, "TOPRIGHT")
  win.priceFrom = fontString(mp, "GameFontHighlight", -22, -(hy + 25), "TOPRIGHT")   -- the badge text (Mist)
  setColor(win.priceFrom, MIST)
  win.badgeBg = pill(mp, win.priceFrom, 6, 3); setFill(win.badgeBg, BADGE); win.badgeBg:SetDrawLayer("BORDER")
  local shop = CreateFrame("Button", nil, mp, "UIPanelButtonTemplate")
  shop:SetSize(64, 22); shop:SetPoint("RIGHT", win.price, "LEFT", -10, 0); shop:SetText("+ Shop")
  shop:SetScript("OnClick", function()
    local _, msg = M.ShopHeaderAction(state.id)
    if msg and ns.Core then ns.Core.Print(msg) end
  end)
  tip(shop, function()
    local made = state.id and M.byProduct[state.id]
    return { "+ Shop", made and "Adds the mats you're missing to craft this to your Shopping list."
      or "Adds this item to your Shopping list." }
  end)
  win.shopBtn = shop
  win.counts = fontString(mp, "GameFontHighlight", 68, -(hy + 28))
  win.counts:SetJustifyH("LEFT"); win.counts:SetWordWrap(false); win.counts:SetWidth(W - 68 - 16 - 12)

  -- Right Here / Nearest Spot card: fixed 38 px, 632 px wide; only its colours and text change.
  local card = CreateFrame("Frame", nil, mp)
  card:SetSize(W - 28, LAYOUT.cardH); card:SetPoint("TOPLEFT", 14, -LAYOUT.cardTop)
  card.fill = card:CreateTexture(nil, "BACKGROUND"); card.fill:SetAllPoints()
  card.pill = fontString(card, "GameFontNormal", 12, -5)
  card.pill:SetWordWrap(false)
  card.pillBg = pill(card, card.pill, 6, 2)
  card.detail = fontString(card, "GameFontHighlight", 8, -21)
  card.detail:SetWidth(W - 28 - 16); card.detail:SetJustifyH("LEFT"); card.detail:SetWordWrap(false)
  card.quiet = fontString(card, "GameFontHighlight", 8, -12)
  card.quiet:SetWidth(W - 28 - 16); card.quiet:SetJustifyH("LEFT"); card.quiet:SetWordWrap(false); setColor(card.quiet, MIST)
  card:EnableMouse(true)
  tip(card, function()
    local l = { "Where to get it" }
    if state.id and ns.Where then
      local wf = ns.Where.WhereToFarm(state.id)
      for i, v in ipairs(wf.vendors) do
        if i > 6 then break end
        l[#l + 1] = ("%s%s (%s) — %s%s"):format(v.inZone and "Here: " or "", v.npc, v.subzone and (v.subzone .. ", " .. v.zone) or v.zone,
          C.Money(v.price), v.limited and " (limited stock)" or "")
      end
      for i, e in ipairs(wf.nearby) do
        if i > 3 then break end
        l[#l + 1] = "Nearby: " .. ns.Where.EntryText(e)
      end
    end
    if #l == 1 then l[2] = "Kill, gather or open vendors and DEB remembers where things come from." end
    return l
  end)
  win.card = card

  -- Filters (remembered in SavedVariables), Best skill-up and the mode button.
  local prevAnchor
  local function check(key, text, help)
    local cb = CreateFrame("CheckButton", nil, mp, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    -- The template label sits 1 px high, so chain off it 1 px lower (no drift along the row).
    if prevAnchor then cb:SetPoint("LEFT", prevAnchor, "RIGHT", 14, -1) else cb:SetPoint("TOPLEFT", 12, -LAYOUT.filtersTop) end
    if isTable(cb.Text) then cb.Text:SetFontObject("GameFontHighlight"); cb.Text:SetText(text) end   -- template default is 10 pt
    cb:SetScript("OnClick", function(s) M.SetFilter(key, s:GetChecked()) end)
    tip(cb, { text, help })
    prevAnchor = isTable(cb.Text) and cb.Text or cb
    return cb
  end
  win.fKnown = check("filterKnown", "Known", "Only recipes this character has learned.")
  win.fMine = check("filterMine", "My professions", "Only recipes for professions you have.")
  win.fPriced = check("filterPriced", "Has a price", "Only recipes with a price for every mat and the item made.")
  win.fMake = check("filterMakeNow", "Make now", "Only recipes you can craft right now with what's in your bags and bank.")
  local mode = CreateFrame("Button", nil, mp, "UIPanelButtonTemplate")
  mode:SetSize(96, 22); mode:SetPoint("TOPRIGHT", -14, -LAYOUT.filtersTop)
  mode:SetScript("OnClick", function()
    state.mode = state.mode == "uses" and "made" or "uses"; state.offset = 0; state.selected = nil; M.Refresh()
  end)
  tip(mode, { "Made from / Used in", "Switch between what this item crafts into and what it's made from." })
  win.modeBtn = mode
  local skill = CreateFrame("Button", nil, mp, "UIPanelButtonTemplate")
  skill:SetSize(118, 22); skill:SetPoint("RIGHT", mode, "LEFT", -6, 0)
  skill:SetScript("OnClick", function() local s = M.Settings(); M.SetFilter("bestSkillUp", not s.bestSkillUp) end)
  tip(skill, { "Best skill-up", "Sorts orange, then yellow, then green recipes, cheapest per skill point first. Click again for best profit first." })
  win.skillBtn = skill
  win.hint = fontString(mp, "GameFontHighlight", 14, -LAYOUT.hintTop)
  win.hint:SetTextColor(MIST[1], MIST[2], MIST[3]); win.hint:Hide()
  -- "Make now" can count your alts' mats too (shown only while Make now is ticked).
  local alts = CreateFrame("CheckButton", nil, mp, "UICheckButtonTemplate")
  alts:SetSize(20, 20); alts:SetPoint("TOPLEFT", 330, -(LAYOUT.hintTop - 4))
  if isTable(alts.Text) then alts.Text:SetFontObject("GameFontHighlight"); alts.Text:SetText("Count my alts' mats") end
  alts:SetScript("OnClick", function(s) M.SetFilter("makeNowAlts", s:GetChecked()) end)
  tip(alts, { "Count my alts' mats", "Make now also counts mats on your other characters (same realm and faction) that you could mail." })
  alts:Hide()
  win.fAlts = alts
  win.count = fontString(mp, "GameFontHighlight", -16, -LAYOUT.hintTop, "TOPRIGHT")

  -- Recipe rows
  local top, RH, rowW = LAYOUT.rowsTop, LAYOUT.rowH, W - 24 - 20
  local well = mp:CreateTexture(nil, "BACKGROUND")
  well:SetColorTexture(0, 0, 0, 0.27); well:SetPoint("TOPLEFT", 12, -(top - 2)); well:SetSize(rowW, RH * LAYOUT.rows + 4)
  win.empty = fontString(mp, "GameFontHighlight", 24, -(top + 14))
  win.empty:SetWidth(rowW - 24); win.empty:SetJustifyH("LEFT"); setColor(win.empty, MIST); win.empty:Hide()
  win.rows = {}
  for i = 1, LAYOUT.rows do
    local row = CreateFrame("Button", nil, mp)
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
    row.name:SetWordWrap(false); row.name:SetWidth(rowW - 44 - 230)
    row.money = fontString(row, "GameFontHighlight", -8, -5, "TOPRIGHT")
    row.reag = fontString(row, "GameFontHighlight", 44, -22)
    row.reag:SetTextColor(0.78, 0.78, 0.78); row.reag:SetWordWrap(false); row.reag:SetWidth(rowW - 44 - 236)
    row.right = fontString(row, "GameFontDisable", -30, -22, "TOPRIGHT")
    local add = CreateFrame("Button", nil, row)
    add:SetSize(16, 16); add:SetPoint("TOPRIGHT", -8, -21)
    add:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up"); add:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    add:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    add:SetScript("OnClick", function() M.ShopRow(row.entry) end)
    tip(add, { "Add to Shopping", "Adds the mats you're missing for one craft to your Shopping list." })
    row.add = add
    row:SetScript("OnClick", function(s) M.ClickRow(s.entry); rowTooltip(s) end)
    row:SetScript("OnEnter", function(r) M.HoverRow(r.entry); rowTooltip(r) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.rows[i] = row
  end
  local scroll = CreateFrame("ScrollFrame", "KennyDwarfExplorersBibleScroll", mp, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -(top - 2)); scroll:SetSize(rowW, RH * LAYOUT.rows + 4)
  scroll:SetScript("OnVerticalScroll", function(s, value)
    if FauxScrollFrame_OnVerticalScroll then FauxScrollFrame_OnVerticalScroll(s, value, RH, function() refreshRows() end) end
  end)
  win.scroll = scroll

  -- Chain strip
  local Y = M.LayoutY()
  rule(mp, -Y.chainTop)
  win.chainLabel = fontString(mp, "GameFontNormal", 14, -Y.chainLabel)
  win.chain, win.arrows = {}, {}
  for i = 1, LAYOUT.chainSteps do
    local b = CreateFrame("Button", nil, mp)
    b:SetSize(LAYOUT.chainStepMaxW, LAYOUT.chainH)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * (LAYOUT.chainStepMaxW + 20), -Y.chainSteps)   -- replaced by refreshChain out of combat
    -- The current page's item: a faint gold fill with a 1 px gold outline.
    b.cur = CreateFrame("Frame", nil, b)
    b.cur:SetAllPoints()
    local fill = b.cur:CreateTexture(nil, "BACKGROUND"); fill:SetAllPoints(); fill:SetColorTexture(1, 0.82, 0, 0.14)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
      local t = b.cur:CreateTexture(nil, "BORDER"); t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
      t:SetPoint(edge[1]); t:SetPoint(edge[2])
      if edge[3] == 1 then t:SetWidth(1) else t:SetHeight(1) end
    end
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("TOPLEFT", 3, -3)
    b.name = fontString(b, "GameFontHighlight", 25, -3); b.name:SetWordWrap(false); b.name:SetWidth(LAYOUT.chainStepMaxW - 28)
    b.sub = fontString(b, "GameFontDisable", 25, -19); b.sub:SetWordWrap(false); b.sub:SetWidth(LAYOUT.chainStepMaxW - 28)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function(s) if s.id and s.id ~= state.id then M.Navigate(s.id, true) end end)
    b:Hide()
    win.chain[i] = b
    local a = mp:CreateTexture(nil, "ARTWORK")
    a:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); a:SetSize(12, 12); a:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    a:Hide()
    win.arrows[i] = a
  end

  -- Drops from (learned from looted corpses, plus imported or synced counts); the + opens the full list.
  local dy = Y.dropsLine
  rule(mp, -Y.dropsTop)
  local plus = CreateFrame("Button", nil, mp)
  plus:SetSize(16, 16); plus:SetPoint("TOPLEFT", 14, -(dy + 2))
  plus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
  plus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  win.dropsTitle = fontString(mp, "GameFontNormal", 36, -(dy + 3))
  win.dropsText = fontString(mp, "GameFontDisable", 0, 0, "LEFT")
  win.dropsText:ClearAllPoints(); win.dropsText:SetPoint("LEFT", win.dropsTitle, "RIGHT", 10, 0)
  win.dropsText:SetJustifyH("LEFT"); win.dropsText:SetWordWrap(false)
  local panel = CreateFrame("Frame", "KennyDwarfExplorersBibleDrops", mp, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", 12, -(top - 2)); panel:SetSize(rowW, RH * LAYOUT.rows + 4)
  panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); panel:SetBackdropColor(0.04, 0.03, 0.015, 1)
  panel:SetFrameLevel((mp:GetFrameLevel() or 0) + 10)
  panel:Hide()
  -- Header row: the (-) close and "Drops from (N kills)"; the mobs below it, as many as fit.
  local pclose = CreateFrame("Button", nil, panel)
  pclose:SetSize(16, 16); pclose:SetPoint("TOPLEFT", 8, -7)
  pclose:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up"); pclose:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
  pclose:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  pclose:SetScript("OnClick", function() M.SetDropsOverlay(false) end)
  panel.close = pclose
  panel.title = fontString(panel, "GameFontNormal", 30, -9)
  local hr = panel:CreateTexture(nil, "ARTWORK")
  hr:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35); hr:SetHeight(1)
  hr:SetPoint("TOPLEFT", 6, -LAYOUT.dropsHeadH); hr:SetPoint("TOPRIGHT", -6, -LAYOUT.dropsHeadH)
  panel.lines = {}
  for i = 1, M.DropsLines() do panel.lines[i] = fontString(panel, "GameFontHighlight", 12, -(LAYOUT.dropsHeadH + 8) - (i - 1) * 20) end
  panel.empty = fontString(panel, "GameFontDisable", 12, -(LAYOUT.dropsHeadH + 8))
  win.dropsPanel = panel
  win.dropsToggle = plus
  plus:SetScript("OnClick", function() M.SetDropsOverlay(not panel:IsShown()) end)
  plus:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(panel:IsShown() and "Close the drops list (or press Escape)" or "Show every mob it drops from")
    GameTooltip:Show()
  end)
  plus:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Export / Import: line 1 is the drop string (1.2.1 reads it), line 2 your vendor and gathering sightings (DEBDATA).
  local function shareBtn(caption, right, fn, help)
    local b = CreateFrame("Button", nil, mp, "UIPanelButtonTemplate")
    b:SetSize(110, 20)
    b:SetPoint("TOPRIGHT", right, -(dy + 1))
    b:SetText(caption)
    b:SetScript("OnClick", fn)
    tip(b, help)
    return b
  end
  win.importBtn = shareBtn("Import Drops", -14, function() if ns.DropShare then ns.DropShare.OpenImport() end end, function()
    local n = ns.ShareData and ns.ShareData.Sources() or 0
    return { "Import Drops", "Paste one or both lines someone exported: drop counts, and their vendors and gathering spots.",
      n > 0 and ("Sightings shared with you so far: %d player%s."):format(n, n == 1 and "" or "s") or nil }
  end)
  win.exportBtn = shareBtn("Export Drops", -130, function() if ns.DropShare then ns.DropShare.OpenExport() end end,
    { "Export Drops", "Line 1: your drop counts. Line 2: vendors and gathering spots you've seen. Copy and paste to a friend." })
  panel:SetScript("OnHide", overlayHidden)
  win:HookScript("OnHide", function() if panel:IsShown() then panel:Hide() end end)   -- its OnHide defers the swap
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
  buildTabs()
  win.panes = {}
  for _, tab in ipairs(ns.Nav.TABS) do
    local p = CreateFrame("Frame", nil, win)
    p:SetAllPoints()
    p:Hide()
    win.panes[tab] = p
  end
  buildMaterials(win.panes.materials)
  for tab, spec in pairs(M.PANES) do
    if win.panes[tab] and spec.build then spec.build(win.panes[tab], win) end
  end
  -- Footer: a key line and the price note, shared by every tab (the key changes with the tab).
  local Y = M.LayoutY()
  rule(win, -Y.footRule, 0.2)
  local key = fontString(win, "GameFontHighlight", 14, -Y.footKey)
  key:SetTextColor(0.78, 0.78, 0.78)
  key:SetText(KEYS.materials)
  win.key = key
  win.foot = fontString(win, "GameFontDisable", 14, -Y.footNote)
  -- The mouse wheel scrolls whichever list the current tab shows.
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function(_, delta)
    local tab = ns.Nav.CurrentTab()
    local spec = M.PANES[tab]
    if tab ~= "materials" then if spec and spec.wheel then spec.wheel(delta) end return end
    local bar = win.scroll.ScrollBar
    if isTable(bar) and bar.GetValue and bar.SetValue and bar:GetValue() then bar:SetValue(bar:GetValue() - delta * LAYOUT.rowH * 3)
    else state.offset = math.max(0, math.min(state.offset - delta * 3, math.max(0, #state.list - LAYOUT.rows))); refreshRows() end
  end)
  -- Bags, prices, vendors or the shopping list changed (ns.Cache version): redraw the open tab, at most once a second.
  local since, seen = 0, ns.Cache and ns.Cache.Version() or 0
  win:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since < 1 then return end
    since = 0
    local v = ns.Cache and ns.Cache.Version() or 0
    if v ~= seen then seen = v; M.RefreshCurrent() end
  end)
end

-- Tabs: show one pane, hide the others (Show/Hide only, so it's the same in and out of combat).
function M.RefreshTab(tab)
  if not win then return end
  if tab == "materials" then M.Refresh() return end
  local spec = M.PANES[tab]
  if spec and spec.refresh then spec.refresh(win.panes[tab], win) end
  local s = M.Settings()
  win.foot:SetText(("Prices from %s (/deb sources). Profit is after the %d%% AH cut."):format(
    table.concat(ns.Prices.Installed(), ", "), math.floor(((s and s.ahCut) or 0.05) * 100 + 0.5)))
end

function M.RefreshCurrent()
  if win and win:IsShown() then M.RefreshTab(ns.Nav.CurrentTab()) end
end

function M.SelectTab(tab)
  if not win or not win.panes[tab] then return end
  if tab ~= "materials" and M.DropsOverlayShown() then M.SetDropsOverlay(false) end
  for t, p in pairs(win.panes) do p:SetShown(t == tab) end
  paintTabs(tab)
  win.key:SetText(KEYS[tab] or "")
  M.RefreshTab(tab)
end

function M.ShownPane()
  if not win then return nil end
  for t, p in pairs(win.panes) do if p:IsShown() then return t end end
  return nil
end

function M.Open(id)
  if not win then build() end
  win:Show()
  local Nav = ns.Nav
  if id then
    if Nav.CurrentTab() ~= "materials" then Nav.ShowTab("materials")   -- ShowTab calls Open() again, without an id
    elseif M.ShownPane() ~= "materials" then M.SelectTab("materials") end  -- first open straight onto an item
    M.Navigate(id, true)
  else
    M.SelectTab(Nav.CurrentTab())
  end
end

function M.Toggle()
  if win and win:IsShown() then win:Hide() else M.Open() end
end

function M.Frame() return win end

-- Nav.ShowTab (tab clicks, /deb shop, /deb seeds, /deb alts, /deb materials) switches the pane.
M.tabHandler = ns.Nav.RegisterTabHandler(function(tab) if M.ShownPane() ~= tab then M.SelectTab(tab) end end)

-- Width-dependent layout skipped in combat runs once it ends.
local regen = CreateFrame("Frame")
regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", function()
  if not layoutPending then return end
  layoutPending = false
  if win and win:IsShown() then M.RefreshCurrent() end
end)
