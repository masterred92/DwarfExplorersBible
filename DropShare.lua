-- DropShare.lua: copy-paste export/import and party/guild sync of personal drop counts.
-- Only your own kills are sent (never dropDone, and never numbers you already imported).
-- Each source has an id: importing or receiving the same id again replaces that source's
-- snapshot, so pasting one string twice does not double the numbers. Different sources add up.
local _, ns = ...
local C, Core, Dr = ns.Compat, ns.Core, ns.Drops
local S = {}
ns.DropShare = S

S.PREFIX = "DEBDROPS"
S.MAX_CHUNK = 240
S.SEND_GAP = 0.25
S.ANNOUNCE_GAP = 15
S.DATA_GAP = 15
S.QUERY_GAP = 30
S.ASSEMBLE_TTL = 30
S.RESULT_SUCCESS, S.RESULT_THROTTLE, S.RESULT_CHANNEL_THROTTLE, S.RESULT_LOCKDOWN = 0, 3, 8, 11

local MAX_KILLS, MAX_ID, MAX_MOBS, MAX_ITEMS, MAX_NAME = 1000000, 99999999, 2000, 40, 80

local queue, pumping, pending = {}, false, false
local lastSentHash, lastAnnounceAt = nil, 0
local lastQueryAt, assembling = {}, {}
local lastDataByChannel = {}

local function lockdown()
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() == true
end

function S.CanSend()
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "no api" end
  if InCombatLockdown and InCombatLockdown() then return false, "combat" end
  if C.InCombat() then return false, "combat" end
  if lockdown() then return false, "lockdown" end
  return true
end

function S.Channels()
  local out = {}
  if IsInRaid and IsInRaid() then out[#out + 1] = "RAID"
  elseif IsInGroup and IsInGroup() then out[#out + 1] = "PARTY" end
  if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
  return out
end

-- Format --------------------------------------------------------------------------------
local function escapeName(s)
  s = tostring(s or "")
  return (s:gsub("%%", "%%25"):gsub(":", "%%3A"):gsub(",", "%%2C"):gsub("/", "%%2F"))
end

local function unescapeName(s)
  s = tostring(s or "")
  return (s:gsub("%%3[Aa]", ":"):gsub("%%2[Cc]", ","):gsub("%%2[Ff]", "/"):gsub("%%25", "%%"))
end

function S.Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return ("%08x"):format(h)
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

function S.RecordsOf(snap)
  local parts = {}
  for _, cid in ipairs(sortedKeys(snap and snap.kills or {})) do
    local kills = snap.kills[cid]
    local name = (snap.names and snap.names[cid]) or ""
    local bits = { tostring(cid), tostring(kills), escapeName(name) }
    local rec = snap.drops and snap.drops[cid]
    if rec then
      for _, id in ipairs(sortedKeys(rec)) do
        local e = rec[id]
        bits[#bits + 1] = ("%d:%d:%d"):format(id, e.seen, e.loots)
      end
    end
    parts[#parts + 1] = table.concat(bits, ",")
  end
  return table.concat(parts, "/")
end

function S.Encode(sourceId, snap)
  local rec = S.RecordsOf(snap or { kills = {}, drops = {}, names = {} })
  sourceId = tostring(sourceId or "")
  return "DEB1:" .. sourceId .. ":" .. S.Hash(sourceId .. ":" .. rec) .. ":" .. rec
end

function S.EncodePersonal()
  if not Dr or not Dr.SourceId then return nil end
  return S.Encode(Dr.SourceId(), Dr.PersonalSnapshot())
end

local function parseInt(s, minv, maxv)
  if type(s) ~= "string" or not s:match("^%d+$") then return nil end
  local n = tonumber(s)
  if not n or n < minv or n > maxv then return nil end
  return n
end

-- Strict: a bad checksum or header rejects the whole string; a bad mob or item is skipped.
function S.Decode(text)
  if type(text) ~= "string" then return nil, nil, nil, "empty" end
  text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]+", "")
  if text == "" then return nil, nil, nil, "empty" end
  local sid, hash, rec = text:match("^DEB1:([%w]+):(%x+):(.*)$")
  if not sid or #sid < 6 or #sid > 32 or not hash or #hash ~= 8 then return nil, nil, nil, "malformed" end
  hash = hash:lower()
  if S.Hash(sid .. ":" .. rec) ~= hash then return nil, nil, nil, "bad checksum" end
  local snap = { kills = {}, drops = {}, names = {} }
  if rec == "" then return snap, sid, hash, nil end
  local nMobs = 0
  for part in rec:gmatch("[^/]+") do
    nMobs = nMobs + 1
    if nMobs > MAX_MOBS then break end
    local fields, i = {}, 0
    for f in (part .. ","):gmatch("([^,]*),") do
      i = i + 1; fields[i] = f
    end
    local cid = parseInt(fields[1], 1, MAX_ID)
    local kills = parseInt(fields[2], 1, MAX_KILLS)
    if cid and kills then
      snap.kills[cid] = kills
      local name = unescapeName(fields[3] or "")
      if #name > MAX_NAME then name = name:sub(1, MAX_NAME) end
      if name ~= "" then snap.names[cid] = name end
      snap.drops[cid] = snap.drops[cid] or {}
      local nItems = 0
      for fi = 4, #fields do
        local idS, seenS, lootsS = (fields[fi] or ""):match("^(%d+):(%d+):(%d+)$")
        local id, seen, loots = parseInt(idS or "", 1, MAX_ID), parseInt(seenS or "", 0, MAX_KILLS), parseInt(lootsS or "", 1, MAX_KILLS)
        nItems = nItems + 1
        if nItems <= MAX_ITEMS and id and seen and loots and seen > 0 and seen <= loots and loots <= kills then
          snap.drops[cid][id] = { seen = seen, loots = loots }
        end
      end
    end
  end
  return snap, sid, hash, nil
end

function S.Import(text, silent)
  local snap, sid, hash, err = S.Decode(text)
  if not snap then
    if not silent then Core.Print(err == "empty" and "paste a drop string first." or "couldn't read that drop string.") end
    return false, err or "malformed"
  end
  local ok, kind = Dr.ApplyShare(sid, snap, hash)
  if not silent then
    local n = 0; for _ in pairs(snap.kills) do n = n + 1 end
    if kind == "own" then Core.Print("that's your own export; nothing changed.")
    elseif kind == "same" then Core.Print("already had that drop string.")
    elseif ok and kind == "replaced" then Core.Print(("updated drop counts from another player (%d mob%s)."):format(n, n == 1 and "" or "s"))
    elseif ok then Core.Print(("added drop counts from another player (%d mob%s)."):format(n, n == 1 and "" or "s"))
    else Core.Print("couldn't import that drop string.") end
  end
  if ok and kind ~= "same" and kind ~= "own" and ns.RM and ns.RM.Refresh then ns.RM.Refresh() end
  return ok, kind
end

function S.OpenExport()
  local text = S.EncodePersonal() or ""
  local n = 0
  if Dr and Dr.PersonalSnapshot then for _ in pairs(Dr.PersonalSnapshot().kills) do n = n + 1 end end
  local opts = {}
  if CopyToClipboard then
    opts.actionLabel = "Copy"
    opts.action = function(s)
      CopyToClipboard(s)
      Core.Print("copied the drop string.")
    end
  end
  return Core.ShowText("DropExport",
    n > 0 and ("Drop data (%d mob%s): Ctrl+C to copy"):format(n, n == 1 and "" or "s")
      or "Drop data: you haven't looted any mobs yet. Ctrl+C to copy.",
    text, opts)
end

function S.OpenImport()
  return Core.ShowText("DropImport", "Paste a drop string, then click Import", "", {
    actionLabel = "Import",
    noHighlight = true,
    action = function(s, w)
      local ok = S.Import(s, false)
      if ok and w then w:Hide() end
    end,
  })
end

-- Chunking / comms ----------------------------------------------------------------------
function S.BuildChunks(payload)
  payload = payload or ""
  local hash = payload:match("^DEB1:[%w]+:(%x+):") or S.Hash(payload)
  -- Reserve "D:<hash>:<iii>:<nnn>:" so a 3-digit index always fits in MAX_CHUNK.
  local overhead = #("D:" .. hash .. ":000:000:")
  local size = S.MAX_CHUNK - overhead
  if size < 16 then size = 16 end
  local n = math.max(1, math.ceil(math.max(#payload, 1) / size))
  local chunks = {}
  for i = 1, n do
    local data = payload:sub((i - 1) * size + 1, i * size)
    chunks[i] = ("D:%s:%d:%d:%s"):format(hash, i, n, data)
  end
  return chunks, hash
end

local function startPump()
  if pumping then return end
  pumping = true
  local function step()
    pumping = false
    if #queue == 0 then return end
    local ok, why = S.CanSend()
    if not ok then
      pending = true
      if why == "lockdown" or why == "combat" then return end
    end
    local item = table.remove(queue, 1)
    -- All four arguments are plain strings this file built (SecretArguments = "NotAllowed").
    local result = C_ChatInfo.SendAddonMessage(S.PREFIX, item.msg, item.chatType)
    if result == S.RESULT_THROTTLE or result == S.RESULT_CHANNEL_THROTTLE or result == S.RESULT_LOCKDOWN then
      table.insert(queue, 1, item)
      pending = true
      if result ~= S.RESULT_LOCKDOWN and C_Timer and C_Timer.After then
        pumping = true
        C_Timer.After(1, step)
      end
      return
    end
    if #queue > 0 and C_Timer and C_Timer.After then
      pumping = true
      C_Timer.After(S.SEND_GAP, step)
    end
  end
  step()
end

function S.Enqueue(chatType, msg)
  if type(chatType) ~= "string" or type(msg) ~= "string" or #msg > S.MAX_CHUNK then return end
  queue[#queue + 1] = { chatType = chatType, msg = msg }
end

function S.QueueSize() return #queue end
function S.ClearQueue() queue = {} end

function S.QueueData(chans, payload, hash)
  local chunks = S.BuildChunks(payload)
  for _, ch in ipairs(chans) do
    lastDataByChannel[ch] = { hash = hash, at = C.Clock() }
    for i = 1, #chunks do S.Enqueue(ch, chunks[i]) end
  end
end

function S.OnPersonalChange()
  pending = true
end

function S.Flush()
  local ok = S.CanSend()
  if not ok then pending = true; return false end
  local chans = S.Channels()
  if #chans == 0 then pending = false; return false end
  if not Dr or not Dr.PersonalSnapshot then return false end
  local snap = Dr.PersonalSnapshot()
  if not next(snap.kills) then pending = false; return false end
  local sid, payload = Dr.SourceId(), S.Encode(Dr.SourceId(), snap)
  local hash = payload:match("^DEB1:[%w]+:(%x+):")
  local now, hashChanged = C.Clock(), hash ~= lastSentHash
  if hashChanged or (now - lastAnnounceAt) >= S.ANNOUNCE_GAP then
    for _, ch in ipairs(chans) do S.Enqueue(ch, "A:" .. sid .. ":" .. hash) end
    lastAnnounceAt = now
  end
  if hashChanged then
    S.QueueData(chans, payload, hash)
    lastSentHash = hash
  end
  pending = false
  startPump()
  return true
end

local function expireAssemblies()
  local now = C.Clock()
  for k, rec in pairs(assembling) do
    if now - (rec.at or 0) > S.ASSEMBLE_TTL then assembling[k] = nil end
  end
end

local function handleData(sender, hash, i, n, data)
  i, n = tonumber(i), tonumber(n)
  if not (sender and hash and i and n and data) then return end
  if n < 1 or n > 400 or i < 1 or i > n or #data > S.MAX_CHUNK then return end
  expireAssemblies()
  local key = sender .. ":" .. hash
  local rec = assembling[key]
  if not rec or rec.n ~= n then
    rec = { hash = hash, n = n, parts = {}, at = C.Clock(), count = 0 }
    assembling[key] = rec
  end
  if not rec.parts[i] then rec.parts[i] = data; rec.count = rec.count + 1 end
  if rec.count ~= rec.n then return end
  local bits = {}
  for j = 1, rec.n do
    if not rec.parts[j] then assembling[key] = nil; return end
    bits[j] = rec.parts[j]
  end
  assembling[key] = nil
  S.Import(table.concat(bits), true)
end

local function maybeQuery(channel, sid, hash)
  if not sid or not hash or (Dr and Dr.SourceId and sid == Dr.SourceId()) then return end
  local shares = KennyDwarfExplorersBibleDB and KennyDwarfExplorersBibleDB.dropShares
  local have = shares and shares[sid]
  if have and have.hash == hash then return end
  local key, now = sid .. ":" .. hash, C.Clock()
  if lastQueryAt[key] and now - lastQueryAt[key] < S.QUERY_GAP then return end
  lastQueryAt[key] = now
  if S.CanSend() then S.Enqueue(channel, "Q:" .. sid .. ":" .. hash); startPump() else pending = true end
end

local function maybeAnswer(channel, wantSid, wantHash)
  if not Dr or wantSid ~= Dr.SourceId() then return end
  local payload = S.EncodePersonal()
  local hash = payload and payload:match("^DEB1:[%w]+:(%x+):")
  if not payload or hash ~= wantHash then return end
  local prev, now = lastDataByChannel[channel], C.Clock()
  if prev and prev.hash == wantHash and now - (prev.at or 0) < S.DATA_GAP then return end
  if not S.CanSend() then pending = true; return end
  S.QueueData({ channel }, payload, hash)
  startPump()
end

function S.OnAddonMessage(prefix, text, channel, sender)
  prefix, text, channel, sender = C.Safe(prefix), C.Safe(text), C.Safe(channel), C.Safe(sender)
  if prefix ~= S.PREFIX or type(text) ~= "string" or text == "" then return end
  if type(sender) ~= "string" or sender == "" then return end
  local me = UnitName and C.Safe(UnitName("player"))
  if me and sender == me then return end
  local kind, a = text:match("^([ADQ]):(.*)$")
  if not kind then return end
  if kind == "A" then
    local sid, hash = a:match("^([%w]+):(%x+)$")
    if sid and hash then maybeQuery(channel, sid, hash) end
  elseif kind == "Q" then
    local sid, hash = a:match("^([%w]+):(%x+)$")
    if sid and hash then maybeAnswer(channel, sid, hash) end
  elseif kind == "D" then
    -- D:hash:i:n:data  (data may contain colons)
    local hash, i, n, data = a:match("^(%x+):(%d+):(%d+):(.*)$")
    if hash then handleData(sender, hash, i, n, data) end
  end
end

function S.Pending() return pending end
function S.SetPending(v) pending = v and true or false end
function S.ResetComms()
  queue, pumping, pending = {}, false, false
  lastSentHash, lastAnnounceAt = nil, 0
  lastQueryAt, assembling, lastDataByChannel = {}, {}, {}
end

local function registerPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(S.PREFIX)
  end
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
    local prefix, text, channel, sender = ...
    Core.SafeCall("addon message", S.OnAddonMessage, prefix, text, channel, sender)
  elseif event == "PLAYER_LOGIN" then
    registerPrefix()
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(2, function() Core.SafeCall("drop sync", S.Flush) end)
    else Core.SafeCall("drop sync", S.Flush) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending or #queue > 0 then Core.SafeCall("drop sync", S.Flush); startPump() end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
    pending = true
    Core.SafeCall("drop sync", S.Flush)
  end
end)
S._frame = f
