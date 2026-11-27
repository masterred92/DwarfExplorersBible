-- Planner.lua: "Make now" (what your bags + bank can craft right now, optionally with what your alts hold) and
-- "Best skill-up" (orange > yellow > green, cheapest per expected skill point). Reads counts and prices only.
local _, ns = ...
local PL = {}
ns.Planner = PL
local RM = ns.RM

PL.RANK = { orange = 1, yellow = 2, green = 3, grey = 4 }

-- How many times you can craft r from your bags + bank (plus mailable alts when withAlts).
function PL.MaxCrafts(r, withAlts)
  local I = ns.Inventory
  if not (I and r and #r.reagents > 0) then return 0 end
  local best
  for _, g in ipairs(r.reagents) do
    local h = I.Count(g.id)
    local have = withAlts and h.total or h.mine
    local n = math.floor(have / g.n)
    if not best or n < best then best = n end
  end
  return best or 0
end

-- Chance one craft gives a skill point at your skill: orange 1; yellow/green (grey - skill) / (grey - yellow), the
-- usual Classic estimate; grey 0. nil when your skill isn't known.
function PL.SkillChance(r, skill)
  skill = skill or RM.Skill(r.prof)
  if not (skill and r.skill and r.grey and r.grey > 0) then return nil end
  if skill < r.skill then return 1 end
  if skill >= r.grey then return 0 end
  if r.grey <= r.skill then return 1 end
  return math.max(0, math.min(1, (r.grey - skill) / (r.grey - r.skill)))
end

-- Cost per expected skill point (buy-all cost / chance), or nil when a price is missing or there's no chance.
function PL.CostPerPoint(r, pr)
  pr = pr or RM.Profit(r)
  local chance = PL.SkillChance(r)
  if not chance or chance <= 0 then return nil end
  for _, g in ipairs(r.reagents) do
    if not RM.Resolve(g.id, "buy").price then return nil end
  end
  return math.floor(pr.cost / chance + 0.5)
end

local function sortKey(e)
  local diff = RM.Difficulty(e.r)
  return PL.RANK[diff or "grey"] or 5, PL.CostPerPoint(e.r, e.pr)
end

-- Sorts { r, pr } entries in place: orange, yellow, green, grey; then cheapest per skill point (unknown last).
function PL.SortSkillUp(list)
  local keys = {}
  for _, e in ipairs(list) do local a, b = sortKey(e); keys[e] = { a, b } end
  table.sort(list, function(x, y)
    local kx, ky = keys[x], keys[y]
    if kx[1] ~= ky[1] then return kx[1] < ky[1] end
    if (kx[2] ~= nil) ~= (ky[2] ~= nil) then return kx[2] ~= nil end
    if kx[2] and ky[2] and kx[2] ~= ky[2] then return kx[2] < ky[2] end
    return x.r.product < y.r.product
  end)
  return list
end

-- Best skill-ups for one profession (default: every profession you've opened), known recipes only unless all.
-- { { r, pr, difficulty, chance, costPerPoint, canMake } }, cached until bags/prices change.
function PL.SkillUps(prof, all)
  return ns.Cache.Get("skillups." .. tostring(prof) .. "." .. tostring(all), function()
    local out = {}
    for _, r in ipairs(RM.recipes) do
      if (not prof or r.prof == prof) and RM.MyProfession(r) and (all or RM.Knows(r)) then
        local diff = RM.Difficulty(r)
        if diff and diff ~= "grey" then
          local pr = RM.Profit(r)
          out[#out + 1] = { r = r, pr = pr, difficulty = diff, chance = PL.SkillChance(r), costPerPoint = PL.CostPerPoint(r, pr),
            canMake = PL.MaxCrafts(r) > 0 }
        end
      end
    end
    return PL.SortSkillUp(out)
  end)
end

-- Every known recipe you can craft right now, most crafts first. { { r, pr, crafts } }, cached.
function PL.MakeNow(withAlts)
  return ns.Cache.Get("makenow." .. tostring(withAlts), function()
    local out = {}
    for _, r in ipairs(RM.recipes) do
      if RM.Knows(r) then
        local n = PL.MaxCrafts(r, withAlts)
        if n > 0 then out[#out + 1] = { r = r, pr = RM.Profit(r), crafts = n } end
      end
    end
    table.sort(out, function(a, b) if a.crafts ~= b.crafts then return a.crafts > b.crafts end return a.r.product < b.r.product end)
    return out
  end)
end

-- Reagent line for a recipe row: { { id, n, have, enough, vendor = true when a remembered merchant sells it } }.
function PL.ReagentStatus(r)
  local I, V = ns.Inventory, ns.Vendors
  local out = {}
  for _, g in ipairs(r.reagents) do
    local have = I and I.Count(g.id).mine or 0
    out[#out + 1] = { id = g.id, n = g.n, have = have, enough = have >= g.n, vendor = V ~= nil and V.Tag(g.id) }
  end
  return out
end
