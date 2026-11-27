-- Alts.lua: what each of your characters knows and holds, account-wide (KennyDwarfExplorersBibleDB.alts).
-- Each character fills its own record when you log in on it and open its professions and bank.
-- "Who can craft" and "Who has mats" read those records; nothing is sent anywhere.
local _, ns = ...
local A = {}
ns.Alts = A
local RM = ns.RM
local db, myKey

function A.Attach(d, _, key) db, myKey = d, key end

local function realmOf(rec, key) return rec.realm or (key and key:match("^(.-)%-[^%-]+%-[^%-]+$")) or "?" end
local function factionOf(rec, key) return rec.faction or (key and key:match("%-([^%-]+)%-[^%-]+$")) or "?" end
local function nameOf(rec, key) return rec.name or (key and key:match("([^%-]+)$")) or "?" end

-- Your characters on this realm (you first): { key, name, faction, isMe, mailable (same faction), rec, skills }.
function A.Characters()
  if not db then return {} end
  local function build()
    local me = db.alts[myKey]
    local realm, faction = me and realmOf(me, myKey), me and factionOf(me, myKey)
    local out = {}
    for key, rec in pairs(db.alts) do
      if type(rec) == "table" and realmOf(rec, key) == realm then
        local isMe = key == myKey
        out[#out + 1] = { key = key, name = nameOf(rec, key), faction = factionOf(rec, key), isMe = isMe,
          mailable = (not isMe) and factionOf(rec, key) == faction, rec = rec, skills = rec.skills or {} }
      end
    end
    table.sort(out, function(a, b) if a.isMe ~= b.isMe then return a.isMe end return a.name < b.name end)
    return out
  end
  return ns.Cache and ns.Cache.Get("alts.chars", build) or build()
end

-- Who can craft: one row per character with the recipe's profession or the recipe itself.
-- target = a recipe table or an itemID (its first recipe). Rows { name, key, prof, skill, knows, isMe }, those who
-- know it first, then highest skill.
function A.WhoCanCraft(target)
  local r = type(target) == "table" and target or (RM.byProduct[target] or {})[1]
  if not r then return {} end
  local out = {}
  for _, ch in ipairs(A.Characters()) do
    local skill = ch.skills[r.prof]
    local knows = ch.rec.learned ~= nil and ch.rec.learned[r.product] == true
    if skill or knows then
      out[#out + 1] = { name = ch.name, key = ch.key, prof = r.prof, skill = skill, knows = knows, isMe = ch.isMe,
        recipeSkill = r.skill }
    end
  end
  table.sort(out, function(a, b)
    if a.knows ~= b.knows then return a.knows end
    if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) > (b.skill or 0) end
    return a.name < b.name
  end)
  return out
end

-- "Blacksmithing 185 · Knows recipe" / "Blacksmithing 140 · doesn't know it yet".
function A.CraftText(row)
  return ("%s · %s%s · %s"):format(row.name, row.prof, row.skill and (" " .. row.skill) or "",
    row.knows and "Knows recipe" or "doesn't know it yet")
end

-- Who has mats: { { itemID, name, total, holders = { { name, bags, bank, isMe } } } }, most first.
-- filter (optional) keeps rows whose item name or a holder's name contains it (case-insensitive).
function A.WhoHasMats(filter)
  local rows = ns.Cache and ns.Cache.Get("alts.mats", A.BuildMats) or A.BuildMats()
  filter = (filter or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if filter == "" then return rows end
  local out = {}
  for _, row in ipairs(rows) do
    local hit = row.name:lower():find(filter, 1, true) ~= nil
    for _, h in ipairs(row.holders) do if h.name:lower():find(filter, 1, true) then hit = true end end
    if hit then out[#out + 1] = row end
  end
  return out
end

function A.BuildMats()
  local byItem, rows = {}, {}
  for _, ch in ipairs(A.Characters()) do
    for _, part in ipairs({ "bags", "bank" }) do
      for id, n in pairs(ch.rec[part] or {}) do
        if RM.byReagent[id] then
          local row = byItem[id]
          if not row then row = { itemID = id, name = RM.Name(id), total = 0, holders = {}, by = {} }; byItem[id] = row; rows[#rows + 1] = row end
          local h = row.by[ch.key]
          if not h then h = { name = ch.name, bags = 0, bank = 0, isMe = ch.isMe }; row.by[ch.key] = h; row.holders[#row.holders + 1] = h end
          h[part] = h[part] + n
          row.total = row.total + n
        end
      end
    end
  end
  for _, row in ipairs(rows) do
    row.by = nil
    table.sort(row.holders, function(a, b) if a.bags + a.bank ~= b.bags + b.bank then return a.bags + a.bank > b.bags + b.bank end return a.name < b.name end)
  end
  table.sort(rows, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.itemID < b.itemID end)
  return rows
end

-- "Copper Bar — 42 total: Main 14, Bankalt 28 (bank)"
function A.MatsText(row)
  local parts = {}
  for _, h in ipairs(row.holders) do
    parts[#parts + 1] = ("%s %d%s"):format(h.name, h.bags + h.bank, (h.bags == 0 and h.bank > 0) and " (bank)" or "")
  end
  return ("%s — %d total: %s"):format(row.name, row.total, table.concat(parts, ", "))
end

-- Forget another character's record (it fills again next time you log in on it).
function A.Forget(key)
  if not db or key == myKey or not db.alts[key] then return false end
  db.alts[key] = nil
  if ns.Cache then ns.Cache.Bump() end
  return true
end

function A.HasAlts() return #A.Characters() > 1 end
function A.Status()
  local n = #A.Characters()
  if n <= 1 then return "Log in on your other characters once and open their professions/bank so DEB can remember them." end
  return ("%d characters on this realm"):format(n)
end
RM.AddModule(A)
