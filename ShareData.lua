-- ShareData.lua: shares what you've seen with other Dwarf Explorer's Bible users in your party, raid or guild:
-- merchants you opened (who, zone, subzone, crafting goods with price and limited stock), gathering sightings
-- (item, herb/mine/skin/fish, zone, count) and the zones you killed counted mobs in. A separate addon prefix
-- (DEBDATA), so 1.2.1 clients never see it and their DEBDROPS sync is unchanged. It uses DropShare's send queue
-- and rules: out of combat and chat lockdown only, PARTY/RAID/GUILD/INSTANCE_CHAT only, chunks of 240 bytes or
-- less, throttled, and a source id stays bound to the player who first sent it (cross-realm names normalized).
-- Received data is checked, stripped of escape codes and control characters, capped, and kept apart in
-- KennyDwarfExplorersBibleDB.sightShares (newest MAX_SOURCES sources). Your own records are never changed.
local _, ns = ...
local C, Core, Dr, DS = ns.Compat, ns.Core, ns.Drops, ns.DropShare
local SD = {}
ns.ShareData = SD

SD.PREFIX = "DEBDATA"
SD.MAX_SOURCES = 30
SD.MAX_VENDORS = 30
SD.MAX_GOODS = 40
SD.MAX_GATHER = 300
SD.MAX_MOBS = 300
SD.MAX_MOB_ZONES = 4
SD.MAX_TEXT = 60
SD.MAX_PRICE = 2000000000
SD.MAX_COUNT = 1000000
SD.MAX_ID = 99999999
SD.GATHER_KINDS = { herb = true, mine = true, skin = true, fish = true }

local db
local pending, lastSentHash, lastAnnounceAt = false, nil, 0
local lastQueryAt, lastDataByChannel = {}, {}

function SD.Attach(d)
  db = d
  db.sightShares = type(db.sightShares) == "table" and db.sightShares or {}
end

-- Text ------------------------------------------------------------------------------------
local function esc(s)
  s = tostring(s or "")
  return (s:gsub("%%", "%%25"):gsub(":", "%%3A"):gsub(",", "%%2C"):gsub("/", "%%2F"):gsub(";", "%%3B"))
end
local function unesc(s)
  s = tostring(s or "")
  return (s:gsub("%%3[Aa]", ":"):gsub("%%2[Cc]", ","):gsub("%%2[Ff]", "/"):gsub("%%3[Bb]", ";"):gsub("%%25", "%%"))
end

-- Strips colour, link and texture codes, every other "|", control characters and outer spaces; cuts to MAX_TEXT.
function SD.Clean(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|+", "")
  s = s:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #s > SD.MAX_TEXT then s = s:sub(1, SD.MAX_TEXT) end
  return s
end

local function int(s, lo, hi)
  if type(s) ~= "string" or not s:match("^%d+$") or #s > 12 then return nil end
  local n = tonumber(s)
  if not n or n < lo or n > hi then return nil end
  return n
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function fields(part)
  local out, i = {}, 0
  for f in (part .. ","):gmatch("([^,]*),") do i = i + 1; out[i] = f end
  return out
end

-- Snapshot --------------------------------------------------------------------------------
-- { vendors = { { npc, zone, subzone, t, items = { [id] = { p, limited } } } }, gather = { { id, k, zone, n } },
--   mobs = { [cid] = { [zone] = kills } } }
function SD.PersonalSnapshot()
  local snap = { vendors = {}, gather = {}, mobs = {} }
  local V = ns.Vendors
  local list = V and V.List() or {}
  for i = 1, math.min(#list, SD.MAX_VENDORS) do
    local v = V.Own()[list[i].key]
    local items, n = {}, 0
    for _, id in ipairs(sortedKeys(v.items)) do
      if n >= SD.MAX_GOODS then break end
      items[id] = { p = v.items[id].p, limited = v.items[id].limited }; n = n + 1
    end
    snap.vendors[#snap.vendors + 1] = { npc = v.npc, zone = v.zone, subzone = v.subzone, t = v.t, items = items }
  end
  for _, zone in ipairs(sortedKeys(db and db.gather or {})) do
    for _, id in ipairs(sortedKeys(db.gather[zone])) do
      if #snap.gather >= SD.MAX_GATHER then break end
      local e = db.gather[zone][id]
      snap.gather[#snap.gather + 1] = { id = id, k = e.k, zone = zone, n = e.n or 1 }
    end
  end
  local nm = 0
  for _, cid in ipairs(sortedKeys(db and db.mobZones or {})) do
    if nm >= SD.MAX_MOBS then break end
    snap.mobs[cid] = {}
    for z, k in pairs(db.mobZones[cid]) do snap.mobs[cid][z] = k end
    nm = nm + 1
  end
  return snap
end

function SD.IsEmpty(snap)
  return #snap.vendors == 0 and #snap.gather == 0 and next(snap.mobs) == nil
end

-- Wire format: DEB2:<sourceId>:<hash>:<records>, records split by "/":
--   V,<npc>,<zone>,<subzone>,<id>:<copper>:<1 limited|0>,...
--   G,<id>,<herb|mine|skin|fish>,<zone>,<count>
--   M,<creatureID>,<zone>:<kills>,...
function SD.RecordsOf(snap)
  local parts = {}
  for _, v in ipairs(snap.vendors or {}) do
    local bits = { "V", esc(v.npc), esc(v.zone), esc(v.subzone or "") }
    for _, id in ipairs(sortedKeys(v.items)) do
      local it = v.items[id]
      bits[#bits + 1] = ("%d:%d:%d"):format(id, it.p, it.limited and 1 or 0)
    end
    parts[#parts + 1] = table.concat(bits, ",")
  end
  for _, g in ipairs(snap.gather or {}) do
    parts[#parts + 1] = ("G,%d,%s,%s,%d"):format(g.id, g.k, esc(g.zone), g.n)
  end
  for _, cid in ipairs(sortedKeys(snap.mobs or {})) do
    local bits = { "M", tostring(cid) }
    for _, z in ipairs(sortedKeys(snap.mobs[cid])) do bits[#bits + 1] = esc(z) .. ":" .. tostring(snap.mobs[cid][z]) end
    parts[#parts + 1] = table.concat(bits, ",")
  end
  return table.concat(parts, "/")
end

function SD.Encode(sourceId, snap)
  local rec = SD.RecordsOf(snap or { vendors = {}, gather = {}, mobs = {} })
  sourceId = tostring(sourceId or "")
  return "DEB2:" .. sourceId .. ":" .. DS.Hash(sourceId .. ":" .. rec) .. ":" .. rec
end

function SD.EncodePersonal()
  local sid = Dr and Dr.SourceId and Dr.SourceId()
  if not sid then return nil end
  return SD.Encode(sid, SD.PersonalSnapshot())
end

-- Strict header and checksum; bad records are skipped; every cap applies.
function SD.Decode(text)
  if type(text) ~= "string" then return nil, nil, nil, "empty" end
  text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]+", "")
  if text == "" then return nil, nil, nil, "empty" end
  local sid, hash, rec = text:match("^DEB2:([%w]+):(%x+):(.*)$")
  if not sid or #sid < 6 or #sid > 32 or #hash ~= 8 then return nil, nil, nil, "malformed" end
  hash = hash:lower()
  if DS.Hash(sid .. ":" .. rec) ~= hash then return nil, nil, nil, "bad checksum" end
  local snap = { vendors = {}, gather = {}, mobs = {} }
  local seenV, nMobs, parts = {}, 0, 0
  for part in rec:gmatch("[^/]+") do
    parts = parts + 1
    if parts > SD.MAX_VENDORS + SD.MAX_GATHER + SD.MAX_MOBS then break end
    local f = fields(part)
    if f[1] == "V" and #snap.vendors < SD.MAX_VENDORS then
      local npc, zone, sub = SD.Clean(unesc(f[2])), SD.Clean(unesc(f[3])), SD.Clean(unesc(f[4]))
      local key = npc .. "|" .. zone .. "|" .. sub
      if npc ~= "" and zone ~= "" and not seenV[key] then
        seenV[key] = true
        local items, n = {}, 0
        for i = 5, #f do
          local a, b, c = f[i]:match("^(%d+):(%d+):([01])$")
          local id, p = int(a, 1, SD.MAX_ID), int(b, 0, SD.MAX_PRICE)
          if id and p and n < SD.MAX_GOODS and not items[id] then items[id] = { p = p, limited = c == "1" or nil }; n = n + 1 end
        end
        if n > 0 then snap.vendors[#snap.vendors + 1] = { npc = npc, zone = zone, subzone = sub ~= "" and sub or nil, items = items } end
      end
    elseif f[1] == "G" and #snap.gather < SD.MAX_GATHER then
      local id, k, zone, n = int(f[2], 1, SD.MAX_ID), f[3], SD.Clean(unesc(f[4])), int(f[5], 1, SD.MAX_COUNT)
      if id and SD.GATHER_KINDS[k] and zone ~= "" and n then snap.gather[#snap.gather + 1] = { id = id, k = k, zone = zone, n = n } end
    elseif f[1] == "M" and nMobs < SD.MAX_MOBS then
      local cid = int(f[2], 1, SD.MAX_ID)
      if cid and not snap.mobs[cid] then
        local zones, n = {}, 0
        for i = 3, #f do
          local zs, ks = f[i]:match("^(.*):(%d+)$")
          local z, k = SD.Clean(unesc(zs)), int(ks, 1, SD.MAX_COUNT)
          if z ~= "" and k and n < SD.MAX_MOB_ZONES and not zones[z] then zones[z] = k; n = n + 1 end
        end
        if n > 0 then snap.mobs[cid] = zones; nMobs = nMobs + 1 end
      end
    end
  end
  return snap, sid, hash, nil
end

local function pruneSources()
  local n, oldest, at = 0, nil, nil
  for sid, sh in pairs(db.sightShares) do
    n = n + 1
    if not oldest or (sh.at or 0) < at then oldest, at = sid, sh.at or 0 end
  end
  if n >= SD.MAX_SOURCES and oldest then db.sightShares[oldest] = nil; return pruneSources() end
end

-- Replace this source's sightings. Returns ok, kind ("added"/"replaced"/"same"/"own"/"sender"/"empty").
function SD.Apply(sid, snap, hash, sender)
  if not db then return false, "not loaded" end
  if type(sid) ~= "string" or sid == "" or type(snap) ~= "table" then return false, "empty" end
  if Dr and sid == Dr.SourceId() then return false, "own" end
  local existing = db.sightShares[sid]
  if existing and hash and existing.hash == hash then return true, "same" end
  local norm = sender and Dr.NormalizeSender(sender)
  if norm and existing and existing.sender and not Dr.SameSender(existing.sender, norm) then return false, "sender" end
  if not existing then pruneSources() end
  local now = C.Now()
  for _, v in ipairs(snap.vendors) do v.t = now end
  db.sightShares[sid] = { hash = hash, sender = (existing and existing.sender) or norm, at = now,
    vendors = snap.vendors, gather = snap.gather, mobs = snap.mobs }
  if ns.Cache then ns.Cache.Bump() end
  return true, existing and "replaced" or "added"
end

function SD.Import(text, silent, sender)
  local snap, sid, hash, err = SD.Decode(text)
  if not snap then
    if not silent then Core.Print(err == "empty" and "paste a sightings string first." or "couldn't read that sightings string.") end
    return false, err or "malformed"
  end
  local ok, kind = SD.Apply(sid, snap, hash, sender)
  if not silent then
    if kind == "own" then Core.Print("those are your own sightings; nothing changed.")
    elseif kind == "sender" then Core.Print("that sightings id is already tied to another player.")
    elseif kind == "same" then Core.Print("already had those sightings.")
    elseif ok then Core.Print(("added sightings from another player (%d vendor%s, %d gathering spot%s)."):format(#snap.vendors,
      #snap.vendors == 1 and "" or "s", #snap.gather, #snap.gather == 1 and "" or "s"))
    else Core.Print("couldn't import that sightings string.") end
  end
  if ok and kind ~= "same" and ns.RM and ns.RM.Refresh then ns.RM.Refresh() end
  return ok, kind
end

function SD.Sources()
  local n = 0
  for _ in pairs(db and db.sightShares or {}) do n = n + 1 end
  return n
end

-- Export / import ----------------------------------------------------------------------------
-- /deb export shows the DEB1 drop line (unchanged, readable by 1.2.1) and, on the next line, the DEB2 sightings line.
-- /deb import takes either line or both pasted together.
function SD.ExportText()
  local lines = { DS.EncodePersonal() or "" }
  local snap = SD.PersonalSnapshot()
  if not SD.IsEmpty(snap) then lines[#lines + 1] = SD.Encode(Dr.SourceId(), snap) end
  return table.concat(lines, "\n"), snap
end

-- Splits pasted text into its DEB1 / DEB2 lines (each line kept whole; a pasted line break inside one is undone).
function SD.SplitImport(text)
  if type(text) ~= "string" then return nil, nil end
  -- ":" is always escaped inside names, so "DEB1:" / "DEB2:" only ever start a string.
  local flat = text:gsub("[\r\n]+", "")
  local d1 = flat:match("(DEB1:.-)DEB2:") or flat:match("(DEB1:.*)$")
  local d2 = flat:match("(DEB2:.-)DEB1:") or flat:match("(DEB2:.*)$")
  local function trim(x) return x and (x:gsub("^%s+", ""):gsub("%s+$", "")) or nil end
  return trim(d1), trim(d2)
end

function SD.ImportText(text, silent)
  local d1, d2 = SD.SplitImport(text)
  local results = {}
  if not d1 and not d2 then
    results.drops = { DS.Import(text, silent) } -- same messages as 1.2.1 for empty or unreadable text
    return results.drops[1], results
  end
  local any = false
  if d1 then results.drops = { DS.Import(d1, silent) }; any = any or results.drops[1] end
  if d2 then results.sightings = { SD.Import(d2, silent) }; any = any or results.sightings[1] end
  return any, results
end

-- Comms ---------------------------------------------------------------------------------------
function SD.Pending() return pending end
function SD.SetPending(v) pending = v and true or false end
local flushQueued = false
-- A new merchant or gathering sighting: send it a little later (one flush per PUSH_GAP, never in combat).
function SD.OnPersonalChange()
  pending = true
  if flushQueued or not (C_Timer and C_Timer.After) then return end
  flushQueued = true
  C_Timer.After(DS.PUSH_GAP, function() flushQueued = false; if pending then Core.SafeCall("sightings sync", SD.Flush) end end)
end
function SD.ResetComms() pending, lastSentHash, lastAnnounceAt, lastQueryAt, lastDataByChannel = false, nil, 0, {}, {} end

local function hashOf(payload) return payload and payload:match("^DEB2:[%w]+:(%x+):") end

function SD.Flush()
  if not DS.CanSend() then pending = true; return false end
  local chans = DS.Channels()
  if #chans == 0 then pending = false; return false end
  local snap = SD.PersonalSnapshot()
  if SD.IsEmpty(snap) then pending = false; return false end
  local sid = Dr.SourceId()
  local payload = SD.Encode(sid, snap)
  local hash, now = hashOf(payload), C.Clock()
  local changed = hash ~= lastSentHash
  if changed or now - lastAnnounceAt >= DS.ANNOUNCE_GAP then
    for _, ch in ipairs(chans) do DS.Enqueue(ch, "A:" .. sid .. ":" .. hash, SD.PREFIX) end
    lastAnnounceAt = now
  end
  if changed then
    local recent = false
    for _, ch in ipairs(chans) do
      local prev = lastDataByChannel[ch]
      if prev and now - prev.at < DS.PUSH_GAP then recent = true end
    end
    if DS.DataInFlight(nil, SD.PREFIX) or recent then
      pending = true
    else
      DS.QueueData(chans, payload, hash, SD.PREFIX)
      for _, ch in ipairs(chans) do lastDataByChannel[ch] = { hash = hash, at = now } end
      lastSentHash, pending = hash, false
    end
  else
    pending = false
  end
  DS.Pump()
  return true
end

local function maybeQuery(channel, sid, hash)
  if sid == Dr.SourceId() then return end
  local have = db and db.sightShares[sid]
  if have and have.hash == hash then return end
  local key, now = sid .. ":" .. hash, C.Clock()
  for k, at in pairs(lastQueryAt) do if now - at >= DS.QUERY_GAP then lastQueryAt[k] = nil end end
  if lastQueryAt[key] then return end
  lastQueryAt[key] = now
  if DS.CanSend() then DS.Enqueue(channel, "Q:" .. sid .. ":" .. hash, SD.PREFIX); DS.Pump() else pending = true end
end

local function maybeAnswer(channel, sid, hash)
  if sid ~= Dr.SourceId() then return end
  local payload = SD.EncodePersonal()
  if hashOf(payload) ~= hash then return end
  local prev, now = lastDataByChannel[channel], C.Clock()
  if prev and prev.hash == hash and now - prev.at < DS.DATA_GAP then return end
  if not DS.CanSend() then pending = true; return end
  DS.QueueData({ channel }, payload, hash, SD.PREFIX)
  lastDataByChannel[channel] = { hash = hash, at = now }
  DS.Pump()
end

function SD.QueryMapSize() local n = 0; for _ in pairs(lastQueryAt) do n = n + 1 end; return n end

function SD.OnAddonMessage(prefix, text, channel, sender)
  prefix, text, channel, sender = C.Safe(prefix), C.Safe(text), C.Safe(channel), C.Safe(sender)
  if prefix ~= SD.PREFIX or type(text) ~= "string" or text == "" or #text > DS.MAX_CHUNK then return end
  if type(sender) ~= "string" or sender == "" then return end
  if type(channel) ~= "string" or not DS.ALLOWED_CHANNELS[channel:upper()] then return end
  if DS.IsSelf(sender) then return end
  local kind, a = text:match("^([ADQ]):(.*)$")
  if not kind then return end
  if kind == "A" or kind == "Q" then
    local sid, hash = a:match("^([%w]+):(%x+)$")
    if not sid or #sid > 32 or #hash ~= 8 then return end
    if kind == "A" then maybeQuery(channel, sid, hash) else maybeAnswer(channel, sid, hash) end
  else
    local hash, i, n, data = a:match("^(%x+):(%d+):(%d+):(.*)$")
    if hash then
      DS.Assemble(sender, hash, i, n, data, function(payload) SD.Import(payload, true, sender) end, SD.PREFIX)
    end
  end
end

local function registerPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(SD.PREFIX) end
end
registerPrefix()

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    Core.SafeCall("sightings message", SD.OnAddonMessage, ...)
  elseif event == "PLAYER_LOGIN" then
    registerPrefix()
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(4, function() Core.SafeCall("sightings sync", SD.Flush) end) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending then Core.SafeCall("sightings sync", SD.Flush) end
  else
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(3, function() Core.SafeCall("sightings sync", SD.Flush) end) end
  end
end)
SD._frame = f
ns.RM.AddModule(SD)
