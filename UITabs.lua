-- UITabs.lua: the Shopping, Seeds and Alts panes of the Guide window (UI Bot's 1.3.0 spec, section 2). UI.lua builds
-- the window and the Materials pane and calls these through M.RegisterPane. Every list is a fixed pool of 40 px slots
-- built once (a section header uses a slot's lower 22 px with a gold rule), so switching tabs, scrolling and every
-- refresh only change text, colours and Show/Hide: no layout ever runs in combat. Text builders are plain functions
-- (M.ShoppingEntries, M.SeedEntries, M.AltEntries) so the tests can read exactly what each slot shows.
local _, ns = ...
local C, M = ns.Compat, ns.RM
local L = M.LAYOUT
local K = M.UIKit
local GOLD, MIST, BRIGHT, SHORT, WHITE = M.COLORS.GOLD, M.COLORS.MIST, M.COLORS.BRIGHT, M.COLORS.SHORT, M.COLORS.WHITE
local hex = M.Hex
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROW_W = L.width - 24 - 20

-- Shared list well -------------------------------------------------------------------------------
-- A slot shows either a header (kind "section" / "group") or an item row (kind "item").
local function buildSlots(pane, name, top, n, onClick, onEnter, withCheck, withRemove)
  local fs = K.fontString
  local well = pane:CreateTexture(nil, "BACKGROUND")
  well:SetColorTexture(0, 0, 0, 0.27); well:SetPoint("TOPLEFT", 12, -(top - 2)); well:SetSize(ROW_W, L.rowH * n + 4)
  local slots = {}
  for i = 1, n do
    local s = CreateFrame("Button", nil, pane)
    s:SetSize(ROW_W, L.rowH); s:SetPoint("TOPLEFT", 12, -top - (i - 1) * L.rowH)
    s.stripe = s:CreateTexture(nil, "BACKGROUND"); s.stripe:SetAllPoints(); s.stripe:SetColorTexture(1, 1, 1, 0.03)
    s.stripe:SetShown(i % 2 == 0)
    s:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local hl = s:GetHighlightTexture()
    if K.isTable(hl) then hl:SetAlpha(L.hoverAlpha) end
    -- header (lower 22 px of the slot)
    s.hdr = fs(s, "GameFontNormal", 8, -22)
    s.hdr:SetWordWrap(false); s.hdr:SetJustifyH("LEFT"); s.hdr:SetWidth(ROW_W - 16 - 200)
    s.hdrRight = fs(s, "GameFontHighlight", -8, -22, "TOPRIGHT")
    s.hdrRule = s:CreateTexture(nil, "ARTWORK")
    s.hdrRule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35); s.hdrRule:SetHeight(1)
    s.hdrRule:SetPoint("BOTTOMLEFT", 4, 1); s.hdrRule:SetPoint("BOTTOMRIGHT", -4, 1)
    -- item row
    local x = 4
    s.check, s.remove = false, false   -- parts this list doesn't have
    if withCheck then
      s.check = CreateFrame("CheckButton", nil, s, "UICheckButtonTemplate")
      s.check:SetSize(24, 24); s.check:SetPoint("TOPLEFT", 4, -8)
      s.check:SetScript("OnClick", function(b) if s.entry and s.entry.onCheck then s.entry.onCheck(b:GetChecked()) end end)
      K.tip(s.check, { "Done", "Tick it when you have it. Clear done removes ticked lines." })
      x = 32
    end
    s.icon = s:CreateTexture(nil, "ARTWORK"); s.icon:SetSize(32, 32); s.icon:SetPoint("TOPLEFT", x, -4)
    if s.icon.SetTexCoord then s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    local tx = x + 40
    local rightPad = withRemove and 30 or 8
    s.name = fs(s, "GameFontNormal", tx, -5)
    s.name:SetWordWrap(false); s.name:SetJustifyH("LEFT"); s.name:SetWidth(ROW_W - tx - 190)
    s.right1 = fs(s, "GameFontHighlight", -rightPad, -5, "TOPRIGHT")
    s.line2 = fs(s, "GameFontHighlight", tx, -22)
    s.line2:SetWordWrap(false); s.line2:SetJustifyH("LEFT"); s.line2:SetWidth(ROW_W - tx - 150)
    s.right2 = fs(s, "GameFontDisable", -rightPad, -22, "TOPRIGHT")
    if withRemove then
      s.remove = CreateFrame("Button", nil, s)
      s.remove:SetSize(16, 16); s.remove:SetPoint("TOPRIGHT", -8, -12)
      s.remove:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up"); s.remove:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
      s.remove:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
      s.remove:SetScript("OnClick", function() if s.entry and s.entry.onRemove then s.entry.onRemove() end end)
      K.tip(s.remove, { "Remove", "Takes this line off your shopping list." })
    end
    s:SetScript("OnClick", function(b) if b.entry and onClick then onClick(b.entry, b) end end)
    s:SetScript("OnEnter", function(b) if b.entry and onEnter then onEnter(b.entry, b) end end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slots[i] = s
  end
  local scroll = CreateFrame("ScrollFrame", name, pane, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -(top - 2)); scroll:SetSize(ROW_W, L.rowH * n + 4)
  local empty = fs(pane, "GameFontHighlight", 24, -(top + 14))
  empty:SetWidth(ROW_W - 24); empty:SetJustifyH("LEFT"); K.setColor(empty, MIST); empty:Hide()
  return { slots = slots, scroll = scroll, empty = empty, offset = 0, n = n, entries = {} }
end

local ITEM_PARTS = { "check", "icon", "name", "right1", "line2", "right2", "remove" }
local HDR_PARTS = { "hdr", "hdrRight", "hdrRule" }

local function fillSlots(list)
  local n, entries = list.n, list.entries
  if list.scroll and FauxScrollFrame_Update then
    FauxScrollFrame_Update(list.scroll, #entries, n, L.rowH)
    list.offset = FauxScrollFrame_GetOffset(list.scroll)
  end
  if list.scroll then list.scroll:SetShown(#entries > n) end
  list.offset = math.max(0, math.min(list.offset, math.max(0, #entries - n)))
  for i = 1, n do
    local s, e = list.slots[i], entries[i + list.offset]
    s.entry = e
    if not e then s:Hide()
    else
      local header = e.kind ~= "item"
      for _, k in ipairs(HDR_PARTS) do if s[k] then s[k]:SetShown(header) end end
      for _, k in ipairs(ITEM_PARTS) do if s[k] then s[k]:SetShown(not header) end end
      s.stripe:SetShown(not header and i % 2 == 0)
      if header then
        s.hdr:SetText(e.text or ""); K.setColor(s.hdr, e.kind == "group" and MIST or GOLD)
        s.hdrRight:SetText(e.right or "")
        s.hdrRule:SetShown(e.kind == "section")
      else
        if s.icon.SetTexture then s.icon:SetTexture(e.itemID and K.itemIcon(e.itemID) or QUESTION) end
        s.name:SetText(e.name or ""); K.setColor(s.name, e.nameColor or WHITE)
        s.right1:SetText(e.right1 or ""); s.line2:SetText(e.line2 or ""); s.right2:SetText(e.right2 or "")
        if s.check then s.check:SetChecked(e.checked == true); s.check:SetShown(e.onCheck ~= nil) end
        if s.remove then s.remove:SetShown(e.onRemove ~= nil) end
      end
      s:Show()
    end
  end
  list.empty:SetShown(list.emptyText ~= nil and #entries == 0)
  list.empty:SetText(list.emptyText or "")
end

local function wheel(list, delta)
  local bar = list.scroll and list.scroll.ScrollBar
  if K.isTable(bar) and bar.GetValue and bar.SetValue and bar:GetValue() then bar:SetValue(bar:GetValue() - delta * L.rowH * 3)
  else list.offset = math.max(0, math.min(list.offset - delta * 3, math.max(0, #list.entries - list.n))); fillSlots(list) end
end

local function hookScroll(list)
  list.scroll:SetScript("OnVerticalScroll", function(s, value)
    if FauxScrollFrame_OnVerticalScroll then FauxScrollFrame_OnVerticalScroll(s, value, L.rowH, function() fillSlots(list) end) end
  end)
end

-- A pair of toggle buttons ("All" / "Ready to plant"): the active one keeps its highlight lit.
local function toggles(pane, defs, y, onPick)
  local out, right = {}, -14
  for i = #defs, 1, -1 do
    local d = defs[i]
    local b = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    b:SetSize(d.w, 22); b:SetPoint("TOPRIGHT", right, -y); b:SetText(d.text)
    b:SetScript("OnClick", function() onPick(d.key) end)
    K.tip(b, { d.text, d.help })
    out[d.key] = b
    right = right - d.w - 6
  end
  return out
end
local function paintToggles(btns, key)
  for k, b in pairs(btns) do if k == key then b:LockHighlight() else b:UnlockHighlight() end end
end

-- Shopping --------------------------------------------------------------------------------------
local function altLine(row)
  local I = ns.Inventory
  for _, h in ipairs(I and I.Count(row.itemID).holders or {}) do
    if h.mailable then return ("On %s: %d bags, %d bank  ·  grab %d"):format(h.name, h.bags, h.bank, row.fromAlt) end
  end
  return "On an alt  ·  grab " .. row.fromAlt
end

local function ageText(sec) return sec and ("price " .. M.Ago(sec) .. " old") or "" end

-- What the Shopping tab shows, top to bottom: { kind = "section"|"group"|"item", text, right, itemID, name, right1,
-- line2, right2, checked, category, row }. Sections in order: Vendor (one group per merchant), Grab from Alt, AH,
-- Have enough, Done; empty sections are left out.
function M.ShoppingEntries(zone)
  local S = ns.Shopping
  local out = {}
  if not S or S.Count() == 0 then return out end
  local secs = S.Sections(zone)
  local function item(row, e)
    e.kind, e.itemID, e.name, e.row, e.category, e.checked = "item", row.itemID, row.name, row, row.category, row.done
    out[#out + 1] = e
  end
  if #secs.vendor.groups > 0 then
    out[#out + 1] = { kind = "section", text = "Vendor", right = "Vendor total: " .. C.Money(secs.vendor.subtotal) }
    for _, g in ipairs(secs.vendor.groups) do
      local label = g.key == "forever" and "Vendor (visit merchant to remember NPC)"
        or ("%s (%s)"):format(g.npc, g.subzone and (g.subzone .. ", " .. g.zone) or g.zone)
      out[#out + 1] = { kind = "group", text = label, right = "subtotal " .. C.Money(g.subtotal) }
      for _, row in ipairs(g.rows) do
        local unit = row.unitPrice and C.Money(row.unitPrice) or "?"
        item(row, { right1 = row.estCost and C.Money(row.estCost) or "|cffaaaaaano price|r",
          line2 = ("Need %d × %s = %s"):format(row.buy, unit, row.estCost and C.Money(row.estCost) or "?")
            .. (row.have > 0 and ("  (have %d)"):format(row.have) or "") })
      end
    end
  end
  if #secs.alt.rows > 0 then
    out[#out + 1] = { kind = "section", text = "Grab from Alt", right = "saves buying them" }
    for _, row in ipairs(secs.alt.rows) do item(row, { right1 = hex(BRIGHT) .. "on your alt|r", line2 = altLine(row) }) end
  end
  if #secs.ah.rows > 0 then
    out[#out + 1] = { kind = "section", text = "AH",
      right = "~" .. C.Money(secs.ah.subtotal) .. (secs.ah.incomplete and " + unpriced" or "") }
    for _, row in ipairs(secs.ah.rows) do
      item(row, { right1 = row.estCost and ("~" .. C.Money(row.estCost)) or "|cffaaaaaano price yet|r",
        line2 = S.NeedText(row), right2 = ageText(row.ageSeconds) })
    end
  end
  if #secs.have.rows > 0 then
    out[#out + 1] = { kind = "section", text = "Have enough", right = "" }
    for _, row in ipairs(secs.have.rows) do item(row, { right1 = hex(BRIGHT) .. "have enough|r", line2 = S.NeedText(row) }) end
  end
  if #secs.done.rows > 0 then
    out[#out + 1] = { kind = "section", text = "Done", right = "" }
    for _, row in ipairs(secs.done.rows) do item(row, { right1 = "done", line2 = S.NeedText(row), nameColor = { 0.6, 0.6, 0.6 } }) end
  end
  return out
end

-- "Missing for: Bolt of Linen Cloth, Copper Mace" (what the lines were added for).
function M.ShoppingFor()
  local S = ns.Shopping
  local db = M.DB()
  if not (S and db and db.shopping) or S.Count() == 0 then return "Shopping list" end
  local seen, names = {}, {}
  for _, id in ipairs(db.shopping.order) do
    local e = db.shopping.items[id]
    for part in tostring(e and e.from or ""):gmatch("[^,]+") do
      part = part:gsub("^%s+", ""):gsub("%s+$", "")
      if part ~= "manual" and part ~= "" and not seen[part] then seen[part] = true; names[#names + 1] = part end
    end
  end
  return #names > 0 and ("Missing for: " .. table.concat(names, ", ")) or "Missing for: your own list"
end

function M.ShoppingTotal()
  local S = ns.Shopping
  if not S or S.Count() == 0 then return "" end
  local secs = S.Sections()
  return "Total ~" .. C.Money(secs.total) .. (secs.incomplete and " + unpriced" or "")
end

M.SHOP_EMPTY = "Your shopping list is empty. Click + on any recipe in Materials to add missing mats."

local shop = {}
local function shopClick(e)
  local S = ns.Shopping
  if not S.AHOpen() then return end
  local ok, why = S.SearchAH(e.itemID)
  if not ok and why == "combat" and ns.Core then ns.Core.Print("the Auction House search waits until combat ends") end
end
local function shopTip(e, s)
  local row = e.row
  GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
  GameTooltip:AddLine(row.name)
  GameTooltip:AddLine(ns.Shopping.NeedText(row), 0.85, 0.85, 0.85, true)
  if row.from and row.from ~= "manual" then GameTooltip:AddLine("For: " .. row.from, 0.7, 0.7, 0.7, true) end
  if row.vendor and row.vendor.npc then GameTooltip:AddLine(ns.Vendors.Text(row.vendor), 1, 0.82, 0) end
  for _, h in ipairs(row.altHolders) do GameTooltip:AddLine(("%s has %d"):format(h.name, h.n), 0.6, 0.8, 0.6) end
  if row.priceLabel then GameTooltip:AddLine("Price from " .. row.priceLabel .. (row.ageSeconds and (", " .. M.Ago(row.ageSeconds) .. " old") or ""), 0.6, 0.6, 0.6) end
  GameTooltip:AddLine(ns.Shopping.AHOpen() and "Click: search it at the Auction House." or "Open the Auction House, then click to search it.", 0.4, 0.8, 1, true)
  GameTooltip:Show()
end

-- The short line under "Missing for": leaves room on the right for "Total ~999g 99s 99c + unpriced".
M.SHOP_STATUS = { open = "Click a row to search it at the AH.", closed = "Open the Auction House to click-search rows." }
M.SHOP_STATUS_W = 352
local function shopRefresh()
  local S = ns.Shopping
  if not shop.list then return end
  shop.forText:SetText(M.ShoppingFor())
  shop.status:SetText(S.Count() > 0 and (S.AHOpen() and M.SHOP_STATUS.open or M.SHOP_STATUS.closed) or "")
  shop.total:SetText(M.ShoppingTotal())
  local entries = M.ShoppingEntries()
  for _, e in ipairs(entries) do
    if e.kind == "item" then
      local id = e.itemID
      e.onCheck = function(on) S.SetDone(id, on); shopRefresh() end
      e.onRemove = function() S.Remove(id); shopRefresh() end
    end
  end
  shop.list.entries = entries
  shop.list.emptyText = M.SHOP_EMPTY
  shop.clearDone:SetEnabled(S.Count() > 0)
  shop.clearAll:SetEnabled(S.Count() > 0)
  fillSlots(shop.list)
end
M.ShoppingRefresh = shopRefresh

M.RegisterPane("shopping", {
  build = function(pane)
    local fs = K.fontString
    shop.pane = pane
    shop.forText = fs(pane, "GameFontNormal", 14, -(L.navTop + 4))
    shop.forText:SetWordWrap(false); shop.forText:SetJustifyH("LEFT"); shop.forText:SetWidth(L.width - 28 - 200 - 12)
    local all = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    all:SetSize(96, 22); all:SetPoint("TOPRIGHT", -14, -L.navTop); all:SetText("Clear all")
    all.armed = false
    -- Clear all asks once: the first click arms it for 4 seconds ("Click again"), the second clears.
    all:SetScript("OnClick", function(b)
      if b.armed then
        b.armed = false; b:SetText("Clear all")
        ns.Shopping.ClearAll(); shopRefresh()
      else
        b.armed = true; b:SetText("Click again")
        if C_Timer and C_Timer.After then C_Timer.After(4, function() if b.armed then b.armed = false; b:SetText("Clear all") end end) end
      end
    end)
    K.tip(all, { "Clear all", "Empties the whole list. Click twice to be sure." })
    local done = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    done:SetSize(96, 22); done:SetPoint("RIGHT", all, "LEFT", -6, 0); done:SetText("Clear done")
    done:SetScript("OnClick", function() ns.Shopping.ClearDone(); shopRefresh() end)
    K.tip(done, { "Clear done", "Removes the lines you ticked." })
    shop.clearAll, shop.clearDone = all, done
    shop.status = fs(pane, "GameFontHighlight", 14, -(L.navTop + 30))
    shop.status:SetWordWrap(false); shop.status:SetJustifyH("LEFT"); shop.status:SetWidth(M.SHOP_STATUS_W); K.setColor(shop.status, MIST)
    shop.total = fs(pane, "GameFontHighlight", -16, -(L.navTop + 30), "TOPRIGHT")
    shop.list = buildSlots(pane, "KennyDwarfExplorersBibleShopScroll", L.listTop, L.listRows, shopClick, shopTip, true, true)
    hookScroll(shop.list)
  end,
  refresh = shopRefresh,
  wheel = function(d) if shop.list then wheel(shop.list, d) end end,
})

-- Seeds -----------------------------------------------------------------------------------------
M.SEED_FILTERS = { "all", "ready" }
local seeds = { filter = "all" }

-- A short status for the row's right side (the full hint is in the tooltip).
function M.SeedShortHint(r)
  if r.canPlant then return "Ready to plant" end
  if r.canHybridize then return "Ready to hybridize" end
  if r.kind ~= "seed" then return r.bags > 0 and "In your bags" or "In your bank" end
  if r.bags == 0 then return "In your bank" end
  if r.hint and r.hint:find("Greenhouse", 1, true) then return "Needs a Greenhouse" end
  return ""
end

-- { kind = "item", itemID, name ("Commonplace Herb Seeds (bags 3, bank 1)"), line2 = role, right1 = value, right2 = hint, row }
function M.SeedEntries(filter)
  local SE = ns.Seeds
  local out = {}
  for _, r in ipairs(SE and SE.Rows(filter) or {}) do
    local value = r.value and ("~" .. C.Money(r.value)) or (r.kind == "seed" and "|cffaaaaaano crop price|r" or "")
    local hint = M.SeedShortHint(r)
    if r.ready and hint ~= "" then hint = hex(BRIGHT) .. hint .. "|r" end
    out[#out + 1] = { kind = "item", itemID = r.itemID, row = r,
      name = ("%s |cffffffff(bags %d, bank %d)|r"):format(r.name, r.bags, r.bank),
      nameColor = GOLD, line2 = r.role ~= "" and r.role or "Seed", right1 = value, right2 = hint }
  end
  return out
end

local function seedTip(e, s)
  local r = e.row
  GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
  GameTooltip:AddLine(r.name)
  if r.role ~= "" then GameTooltip:AddLine(r.role, 0.85, 0.85, 0.85, true) end
  if r.hint then GameTooltip:AddLine(r.hint, r.ready and BRIGHT[1] or 0.7, r.ready and BRIGHT[2] or 0.7, r.ready and BRIGHT[3] or 0.7, true) end
  local slots = ns.Seeds.BagSlots(r.itemID)
  if #slots > 0 then
    local where = {}
    for i, sl in ipairs(slots) do if i <= 4 then where[#where + 1] = ("bag %d slot %d"):format(sl.bag + 1, sl.slot) end end
    GameTooltip:AddLine("In your bags: " .. table.concat(where, ", ") .. (#slots > 4 and "..." or ""), 0.7, 0.7, 0.7, true)
  end
  if r.recipes and r.recipes > 0 then GameTooltip:AddLine(("Used in %d recipe%s. Click to see them."):format(r.recipes, r.recipes == 1 and "" or "s"), 0.4, 0.8, 1, true) end
  GameTooltip:AddLine("DEB never uses or plants anything: use it from your bags yourself.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end
local function seedClick(e) if e.row.recipes and e.row.recipes > 0 then M.Open(e.itemID) end end

local function seedRefresh()
  if not seeds.list then return end
  local SE = ns.Seeds
  local sum = SE.Summary()
  seeds.summary:SetText(sum.empty and "" or sum.text)
  seeds.list.entries = M.SeedEntries(seeds.filter)
  seeds.list.emptyText = (sum.empty or seeds.filter == "all") and SE.EMPTY or "Nothing is ready to plant right now. Click All to see every seed."
  paintToggles(seeds.toggles, seeds.filter)
  fillSlots(seeds.list)
end
function M.SetSeedFilter(f) seeds.filter = f == "ready" and "ready" or "all"; seedRefresh() end
function M.SeedFilter() return seeds.filter end

M.RegisterPane("seeds", {
  build = function(pane)
    local fs = K.fontString
    seeds.summary = fs(pane, "GameFontHighlight", 14, -(L.navTop + 4))
    seeds.summary:SetWordWrap(false); seeds.summary:SetWidth(L.width - 28 - 220)
    seeds.toggles = toggles(pane, {
      { key = "all", text = "All", w = 70, help = "Every seed, Greenhouse and Hybridizer you have." },
      { key = "ready", text = "Ready to plant", w = 124, help = "Only what you can use right now (the Greenhouse or Hybridizer is in your bags)." },
    }, L.navTop, M.SetSeedFilter)
    local note = fs(pane, "GameFontHighlight", 14, -(L.navTop + 30))
    note:SetWordWrap(false); note:SetWidth(L.width - 28); K.setColor(note, MIST)
    note:SetText("What each seed grows into is as reported by Icy Veins. Crop value uses your price source.")
    seeds.list = buildSlots(pane, "KennyDwarfExplorersBibleSeedScroll", L.listTop, L.seedRows, seedClick, seedTip, false, false)
    hookScroll(seeds.list)
  end,
  refresh = seedRefresh,
  wheel = function(d) if seeds.list then wheel(seeds.list, d) end end,
})

-- Alts ------------------------------------------------------------------------------------------
local alts = { mode = "craft", filter = "" }

-- The recipe "Who can craft" looks at: a crafted item typed in the filter box, else the row you picked in Materials,
-- else the Materials item itself when something makes it. Returns recipe or nil.
function M.CraftTarget(filter)
  filter = (filter or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if filter ~= "" then
    for _, id in ipairs(M.Search(filter, 50)) do if M.byProduct[id] then return M.byProduct[id][1] end end
    return nil
  end
  local st = M.State()
  if st.selected then return st.selected.r end
  if st.id and M.byProduct[st.id] then return M.byProduct[st.id][1] end
  if st.id and st.list[1] then return st.list[1].r end
  return nil
end

M.ALTS_EMPTY = "Log in on your other characters once and open their professions or bank so DEB can remember them."

-- { kind = "item", itemID, name, line2, right1, key } for the mode ("craft" | "mats"), plus a context line.
function M.AltEntries(mode, filter)
  local A = ns.Alts
  local out = {}
  if not A then return out, "" end
  if mode == "mats" then
    for _, row in ipairs(A.WhoHasMats(filter)) do
      local parts = {}
      for _, h in ipairs(row.holders) do
        parts[#parts + 1] = ("%s %d%s"):format(h.name, h.bags + h.bank, (h.bags == 0 and h.bank > 0) and " (bank)" or "")
      end
      out[#out + 1] = { kind = "item", itemID = row.itemID, name = ("%s |cffffffff— %d total|r"):format(row.name, row.total),
        nameColor = GOLD, line2 = table.concat(parts, ", "), open = row.itemID }
    end
    return out, A.Status() .. "  ·  Click a row to open it in Materials."
  end
  local r = M.CraftTarget(filter)
  if not r then return out, "Pick a crafted item in Materials, or type one in the box." end
  for _, row in ipairs(A.WhoCanCraft(r)) do
    local need = r.skill and r.skill > 0 and row.skill and row.skill < r.skill
    local line2
    if need then line2 = hex(SHORT) .. ("Skill %d, needs %d"):format(row.skill, r.skill) .. "|r"
    elseif row.knows then line2 = hex(BRIGHT) .. "Can craft it" .. "|r"
    else line2 = ("Skill %s: can learn it"):format(row.skill and tostring(row.skill) or "?") end
    out[#out + 1] = { kind = "item", itemID = r.product, name = A.CraftText(row) .. (row.knows and (" " .. M.READY) or ""),
      nameColor = row.knows and GOLD or WHITE, line2 = line2, right1 = row.isMe and "|cffaaaaaa(you)|r" or "", key = row.key }
  end
  return out, ("Who can craft: %s (%s)"):format(M.Name(r.product), r.prof .. ((r.skill or 0) > 0 and (" " .. r.skill) or ""))
end

local function altsRefresh()
  if not alts.list then return end
  local A = ns.Alts
  local entries, context = M.AltEntries(alts.mode, alts.filter)
  if not A or #A.Characters() <= 1 then entries, context = {}, "" end   -- nothing to compare yet
  alts.context:SetText(context or "")
  K.setColor(alts.context, alts.mode == "craft" and GOLD or MIST)
  alts.list.entries = entries
  if not A or #A.Characters() <= 1 then alts.list.emptyText = M.ALTS_EMPTY
  elseif alts.mode == "craft" then
    local r = M.CraftTarget(alts.filter)
    alts.list.emptyText = r and ("None of your characters has %s yet."):format(r.prof) or "Pick a crafted item in Materials, or type one in the box."
  else alts.list.emptyText = (alts.filter ~= "" and "No mats match that filter." or "No mats seen on your characters yet.") end
  paintToggles(alts.toggles, alts.mode)
  fillSlots(alts.list)
end
function M.SetAltsMode(mode) alts.mode = mode == "mats" and "mats" or "craft"; altsRefresh() end
function M.SetAltsFilter(text) alts.filter = text or ""; altsRefresh() end
function M.AltsMode() return alts.mode end

local function altsClick(e)
  if e.open then ns.Nav.ShowTab("materials"); M.Navigate(e.open, true) end
end
local function altsTip(e, s)
  GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
  GameTooltip:AddLine(e.name)
  if e.line2 then GameTooltip:AddLine(e.line2, 0.85, 0.85, 0.85, true) end
  if e.open then GameTooltip:AddLine("Click: open it in Materials.", 0.4, 0.8, 1, true) end
  GameTooltip:Show()
end

M.RegisterPane("alts", {
  build = function(pane)
    local fs = K.fontString
    local box = CreateFrame("EditBox", "KennyDwarfExplorersBibleAltFilter", pane, "SearchBoxTemplate")
    box:SetSize(L.searchW, 22); box:SetPoint("TOPLEFT", 20, -L.navTop); box:SetAutoFocus(false)
    if K.isTable(box.Instructions) then box.Instructions:SetFontObject("GameFontDisable"); box.Instructions:SetText("Filter alt or item...") end
    box:HookScript("OnTextChanged", function(b) M.SetAltsFilter(b:GetText()) end)
    box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
    alts.box = box
    alts.toggles = toggles(pane, {
      { key = "craft", text = "Who can craft", w = 118, help = "Your characters with the profession for the item picked in Materials (or typed in the box)." },
      { key = "mats", text = "Who has mats", w = 118, help = "Crafting mats on all your characters, most first." },
    }, L.navTop, M.SetAltsMode)
    alts.context = fs(pane, "GameFontNormal", 14, -(L.navTop + 30))
    alts.context:SetWordWrap(false); alts.context:SetJustifyH("LEFT"); alts.context:SetWidth(L.width - 28)
    alts.list = buildSlots(pane, "KennyDwarfExplorersBibleAltScroll", L.listTop, L.listRows, altsClick, altsTip, false, false)
    hookScroll(alts.list)
  end,
  refresh = altsRefresh,
  wheel = function(d) if alts.list then wheel(alts.list, d) end end,
})

function M.PaneLists() return { shopping = shop.list, seeds = seeds.list, alts = alts.list } end
