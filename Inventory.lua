-- Inventory.lua: bag and bank counts per character, and the one item-count resolver every module uses.
-- Bags are read on BAG_UPDATE_DELAYED (debounced, never in combat: a fight's loot is read when it ends). The bank
-- can only be read while it's open; its counts are kept for when it's closed. Only items DEB knows (reagents,
-- products, camp items, shopping list) are saved, so SavedVariables stay small. Reads only, never moves an item.
local _, ns = ...
local C, Core = ns.Compat, ns.Core
local I = { bankOpen = false, pending = false, token = 0, scans = 0 }
ns.Inventory = I
local RM = ns.RM
local char

I.DEBOUNCE = 0.5

-- Saved only for items DEB has a use for.
function I.Tracked(id)
  return RM.byReagent[id] ~= nil or RM.byProduct[id] ~= nil or RM.byCamp[id] ~= nil
    or (ns.Seeds ~= nil and ns.Seeds.IsSeedItem(id)) or (ns.Shopping ~= nil and ns.Shopping.Has(id))
end

local function containerCounts(ids)
  local counts = {}
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return counts end
  for _, bag in ipairs(ids) do
    for slot = 1, (C.SafeNumber(C_Container.GetContainerNumSlots(bag)) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local id = info and C.SafeNumber(info.itemID)
      local n = info and C.SafeNumber(info.stackCount)
      if id and n then counts[id] = (counts[id] or 0) + n end
    end
  end
  return counts
end

-- Forever's bank (Blizzard_UIPanels_Game/Camelot/BankFrame.lua): the main bank slots are Enum.BagIndex.Characterbanktab,
-- the bank bags are CharacterBankTab_1 + (slot - 1) for NUM_CHARACTER_BANK_SLOTS slots.
function I.BankIDs()
  local B = Enum and Enum.BagIndex
  if not (B and B.Characterbanktab and B.CharacterBankTab_1) then return {} end
  local ids = { B.Characterbanktab }
  for i = 0, (NUM_CHARACTER_BANK_SLOTS or 0) - 1 do ids[#ids + 1] = B.CharacterBankTab_1 + i end
  return ids
end

local function filtered(counts)
  local out = {}
  for id, n in pairs(counts) do if I.Tracked(id) then out[id] = n end end
  return out
end

function I.Attach(_, c) char = c; char.bags, char.bank = char.bags or {}, char.bank or {} end

function I.ScanBags()
  if not char then return false end
  char.bags, char.bagsAt = filtered(C.GetBagCounts()), C.Now()
  I.scans = I.scans + 1
  if ns.Cache then ns.Cache.Bump() end
  return true
end

function I.ScanBank()
  if not (char and I.bankOpen) then return false end
  char.bank, char.bankAt = filtered(containerCounts(I.BankIDs())), C.Now()
  if ns.Cache then ns.Cache.Bump() end
  return true
end

-- Debounced rescan: a burst of bag events reads the bags once, DEBOUNCE seconds after the last one. In combat
-- it waits for PLAYER_REGEN_ENABLED.
function I.Queue()
  if C.InCombat() then I.pending = true return end
  I.token = I.token + 1
  local token = I.token
  local function run()
    if token ~= I.token then return end
    if C.InCombat() then I.pending = true return end
    Core.SafeCall("bags", I.ScanBags)
    if I.bankOpen then Core.SafeCall("bank", I.ScanBank) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(I.DEBOUNCE, run) else run() end
end

-- The one item-count resolver. { bags, bank, mine = bags + bank (this character), alts = units on your other
-- characters you can mail from (same realm and faction), total, holders = { { name, key, bags, bank, isMe, mailable } } }.
function I.Count(itemID)
  itemID = C.SafeNumber(itemID)
  local out = { bags = 0, bank = 0, mine = 0, alts = 0, total = 0, holders = {} }
  if not itemID then return out end
  local A = ns.Alts
  for _, ch in ipairs(A and A.Characters() or {}) do
    local b, k = ch.rec.bags and ch.rec.bags[itemID] or 0, ch.rec.bank and ch.rec.bank[itemID] or 0
    if b + k > 0 then
      out.holders[#out.holders + 1] = { name = ch.name, key = ch.key, bags = b, bank = k, isMe = ch.isMe, mailable = ch.mailable }
      if ch.isMe then out.bags, out.bank = b, k elseif ch.mailable then out.alts = out.alts + b + k end
    end
  end
  table.sort(out.holders, function(a, b)
    if a.isMe ~= b.isMe then return a.isMe end
    if a.bags + a.bank ~= b.bags + b.bank then return a.bags + a.bank > b.bags + b.bank end
    return a.name < b.name
  end)
  out.mine = out.bags + out.bank
  out.total = out.mine + out.alts
  return out
end

-- Bag slots holding itemID, for a bag highlight (the UI only lights them up; nothing is used for you).
function I.BagSlots(itemID)
  local out = {}
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return out end
  for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
    for slot = 1, (C.SafeNumber(C_Container.GetContainerNumSlots(bag)) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and C.SafeNumber(info.itemID) == itemID then out[#out + 1] = { bag = bag, slot = slot } end
    end
  end
  return out
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
f:SetScript("OnEvent", function(_, event)
  if not char then return end
  if event == "BANKFRAME_OPENED" then I.bankOpen = true; I.Queue()
  elseif event == "BANKFRAME_CLOSED" then I.bankOpen = false -- the bank counts we read stay saved
  elseif event == "PLAYER_REGEN_ENABLED" then if I.pending then I.pending = false; I.Queue() end
  else I.Queue() end
end)
I._frame = f
RM.AddModule(I)
