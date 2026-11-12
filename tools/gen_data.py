#!/usr/bin/env python3
"""Builds Data.lua from WoW: Forever's own client tables plus the server hotfixes Blizzard pushes on top of them.

Usage: tools/gen_data.py <csv dir> --build 1.60.1.70888 [--hotfixes <dir>] [--vendor data.json] [--out Data.lua]

<csv dir> holds the client DB2 tables for product `wowf` at that build, exported from
https://wago.tools/db2/<Table>/csv?product=wowf&build=<build>:
  SkillLineAbility, SpellEffect, SpellReagents, SpellName, ItemSparse, TradeSkillCategory,
  SpellCastingRequirements, SpellFocusObject, SpellTotems, TotemCategory.
--hotfixes points at a folder of <table>.json files written by tools/fetch_hotfixes.py (wago.tools' public hotfix
list). Since launch every recipe change has come as a server hotfix rather than a new client build, so without them
skill levels and reagent counts go stale. For each record the newest row of this build wins: status 1 replaces or adds
the record, status 2 removes it.
ItemSparse hotfixes are fetched per item: run with --list-hidden first, then
tools/fetch_hotfixes.py <build> ItemSparse <dir>/itemsparse.json <those ids>.
--vendor (nexus-devs/wow-classic-items data.json, MIT) only marks which reagents a vendor sells."""
import argparse, csv, json, os, sys

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("--build", required=True, help="full client build, e.g. 1.60.1.70888")
ap.add_argument("--hotfixes")
ap.add_argument("--vendor")
ap.add_argument("--out", default="Data.lua")
ap.add_argument("--list-hidden", action="store_true",
                help="print the item IDs recipes need that ItemSparse lacks (fetch their ItemSparse hotfixes), then exit")
args = ap.parse_args()
BUILD = args.build
BUILD_NO = BUILD.rsplit(".", 1)[-1]

# Skill lines shown as professions. TradeSkillCategoryID 0 = not in Forever's profession window (gathering ranks,
# unused/test rows), so only real crafting-window recipes come through.
SKILL = {"171": "Alchemy", "164": "Blacksmithing", "185": "Cooking", "333": "Enchanting", "202": "Engineering",
         "129": "First Aid", "165": "Leatherworking", "186": "Mining", "197": "Tailoring",
         "182": "Herbalism", "393": "Skinning", "356": "Fishing", "40": "Poisons", "3012": "Comprehension"}
# Camp actions that use up an item without crafting one: planting and hybridizing herb seeds (spell IDs from
# SpellReagents; Plant Seeds needs SpellFocusObject "Greenhouse" in SpellCastingRequirements).
CAMP_ACTIONS = [1282389, 1282731, 1282732, 1282734, 1282617, 1282618, 1282619, 1282620, 1282621]
# Hybridize Seeds has no SpellCastingRequirements row; the seeds' own client description says
# "combine at a Seed Hybridizer", which is SpellFocusObject 2258.
CAMP_FOCUS_FALLBACK = {"Hybridize Seeds": "2258"}
# Reagents Blizzard has said a Forever vendor sells, so the AH price should never go above the vendor's.
# Stock and price are server data (not in the client), so each entry names its source.
VENDOR_CAP = {13468: "Black Lotus: Clay Stone (Blizzard), Friends Per Second ep. 106, via Wowhead 2026-10-15"}
NO_RECIPE_TEXT = "cannot be used in profession recipes"


def rows(t):
    return list(csv.DictReader(open(os.path.join(args.src, t + ".csv"), encoding="utf-8")))


def overlay(table, base):
    """Applies this build's hotfixes for `table` to base rows (list of dicts keyed like the CSV). Returns
    (rows, set of hotfixed record ids)."""
    if not args.hotfixes:
        return base, set()
    path = os.path.join(args.hotfixes, table.lower() + ".json")
    if not os.path.exists(path):
        sys.exit(f"missing hotfix file {path} (run tools/fetch_hotfixes.py {BUILD_NO} {table} {path})")
    cols = list(base[0].keys()) if base else next(csv.reader(open(os.path.join(args.src, table + ".csv"), encoding="utf-8")))
    best, best_en = {}, {}
    for h in json.load(open(path, encoding="utf-8")):
        if str(h.get("build")) != BUILD_NO or h.get("table_name", "").lower() != table.lower():
            continue
        # The newest push wins; the same record arrives once per region and locale, so enUS breaks ties.
        key = (int(h["push_id"]), h.get("locale") == "enUS", int(h["id"]))
        rid = str(h["record_id"])
        if rid not in best or key > best[rid][0]:
            best[rid] = (key, h)
        if h.get("locale") == "enUS" and (rid not in best_en or key > best_en[rid][0]):
            best_en[rid] = (key, h)
    by_id = {r["ID"]: r for r in base}
    touched = set()
    for rid, (_, h) in best.items():
        if h["status"] == 2:
            by_id.pop(rid, None); touched.add(rid)
        elif h["status"] == 1 and h["data"] is not None:
            flat = []
            for v in h["data"]:
                flat += v if isinstance(v, list) else [v]
            if len(flat) != len(cols):
                sys.exit(f"{table} hotfix {rid}: {len(flat)} fields, CSV has {len(cols)}")
            row = {c: ("" if v is None else str(v)) for c, v in zip(cols, flat)}
            en = best_en.get(rid)
            if h.get("locale") != "enUS" and en and en[1]["status"] == 1 and en[1]["data"] is not None:
                # Text columns from the newest English copy of the record (names show in English, like the CSVs).
                en_flat = []
                for v in en[1]["data"]:
                    en_flat += v if isinstance(v, list) else [v]
                for c, v in zip(cols, en_flat):
                    if c.endswith("_lang"):
                        row[c] = "" if v is None else str(v)
            by_id[rid] = row
            touched.add(rid)
    return list(by_id.values()), touched


sla, sla_hf = overlay("SkillLineAbility", rows("SkillLineAbility"))
effects, _ = overlay("SpellEffect", rows("SpellEffect"))
reagent_rows, sr_hf = overlay("SpellReagents", rows("SpellReagents"))
item_rows, _ = overlay("ItemSparse", rows("ItemSparse")) if args.hotfixes and os.path.exists(
    os.path.join(args.hotfixes, "itemsparse.json")) else (rows("ItemSparse"), set())
casting, _ = overlay("SpellCastingRequirements", rows("SpellCastingRequirements"))
totems, _ = overlay("SpellTotems", rows("SpellTotems"))
spell_name = {r["ID"]: r["Name_lang"] for r in rows("SpellName")}
sod = {r["ID"] for r in rows("TradeSkillCategory") if r["Name_lang"].strip().upper() == "SEASON OF DISCOVERY"}
focus_name = {r["ID"]: r["Name_lang"] for r in rows("SpellFocusObject")}
totem_cat = {r["ID"]: r["Name_lang"] for r in rows("TotemCategory")}

create = {}
for r in sorted(effects, key=lambda r: (int(r["SpellID"]), int(r["EffectIndex"] or 0))):  # effect 24 = CREATE_ITEM
    if r["Effect"] == "24" and r["EffectItemType"] not in ("0", ""):
        create.setdefault(r["SpellID"], (int(r["EffectItemType"]), max(1, int(round(float(r["EffectBasePointsF"] or 1))))))
reag = {}
for r in sorted(reagent_rows, key=lambda r: (r["ID"] in sr_hf, int(r["ID"]))):  # a hotfixed record wins a tie
    reag[r["SpellID"]] = [(int(r[f"Reagent_{i}"]), int(r[f"ReagentCount_{i}"])) for i in range(8)
                          if r[f"Reagent_{i}"] not in ("0", "") and int(r[f"ReagentCount_{i}"] or 0) > 0]
items = {int(r["ID"]): r for r in item_rows}
need_focus = {r["SpellID"]: r["RequiresSpellFocus"] for r in casting if r["RequiresSpellFocus"] not in ("0", "")}
tools = {}
for r in totems:
    names = [items[int(r[f"Totem_{i}"])]["Display_lang"] for i in range(2) if int(r[f"Totem_{i}"] or 0) in items]
    names += [totem_cat[r[f"RequiredTotemCategoryID_{i}"]] for i in range(2) if r[f"RequiredTotemCategoryID_{i}"] in totem_cat]
    names = list(dict.fromkeys(names))
    if names:
        tools[r["SpellID"]] = names

profs = list(dict.fromkeys(SKILL.values()))  # new professions go last so existing row indices stay put
out_rows, used, seen, hidden, tool_rows, missing_items = [], set(), set(), {}, {}, set()
stats = {"hidden_kept": 0, "sod_hidden_skipped": 0, "hidden_reagent_skipped": 0}
for r in sorted(sla, key=lambda r: (int(r["Spell"]), int(r["ID"]))):
    sp = r["Spell"]
    if r["SkillLine"] not in SKILL or r["TradeSkillCategoryID"] in ("0", "") or sp not in create or not reag.get(sp):
        continue
    pid, n = create[sp]
    if (pid, sp) in seen:
        continue
    if r["TradeSkillCategoryID"] not in sod:
        missing_items.update(i for i in [pid] + [i for i, _ in reag[sp]] if i not in items)
    if pid not in items:
        # Blizzard hides not-yet-released items from the client's ItemSparse; the recipe itself is in Forever's
        # profession window, so keep it under its spell name. Leftover Season of Discovery rows are skipped.
        if r["TradeSkillCategoryID"] in sod:
            stats["sod_hidden_skipped"] += 1; continue
        if not all(i in items for i, _ in reag[sp]):
            stats["hidden_reagent_skipped"] += 1; continue
        hidden[pid] = spell_name.get(sp) or f"item {pid}"
        stats["hidden_kept"] += 1
    seen.add((pid, sp))
    y, g = int(r["TrivialSkillLineRankLow"] or 0), int(r["TrivialSkillLineRankHigh"] or 0)
    rg = ",".join(f"{i}:{c}" for i, c in reag[sp])
    out_rows.append((pid, int(sp), f'"{pid};{n};{n};{profs.index(SKILL[r["SkillLine"]]) + 1};{y};{g};{sp};{rg}"'))
    used.add(pid); used.update(i for i, _ in reag[sp])
    if sp in tools:
        tool_rows[int(sp)] = tools[sp]
out_rows.sort()

if args.list_hidden:
    print(" ".join(str(i) for i in sorted(missing_items)))
    sys.exit(0)

camp = []
for sp in CAMP_ACTIONS:
    s = str(sp)
    rg = reag.get(s)
    if not rg or not all(i in items for i, _ in rg):
        continue  # e.g. the fifth seed tier: its item record is still hidden
    act = spell_name.get(s, "")
    fid = need_focus.get(s) or CAMP_FOCUS_FALLBACK.get(act)
    place = focus_name.get(fid, "") if fid else ""
    camp.append(f'"{sp};{",".join(f"{i}:{c}" for i, c in rg)};{act};{place}"')
    used.update(i for i, _ in rg)

no_recipe = sorted(k for k, it in items.items() if NO_RECIPE_TEXT in (it.get("Description_lang") or "").lower())

vendor_sold = set()
if args.vendor:
    vendor_sold = {i["itemId"] for i in json.load(open(args.vendor)) if i.get("vendorPrice")}


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def name_of(k):
    return items[k]["Display_lang"] if k in items else hidden.get(k)


out = [f"-- GENERATED by tools/gen_data.py from WoW: Forever {BUILD} client tables plus that build's server hotfixes"
       " (wago.tools, product wowf). Do not edit by hand.",
       "-- Row: product;minQty;maxQty;profession;yellowAt;greyAt;spellID;reagent:count,...",
       "-- buy = vendor price per unit (Forever ItemSparse BuyPrice / VendorStackCount) for reagents sold by vendors.",
       "-- hidden = products whose item record Blizzard keeps out of the client until release (named by recipe).",
       "-- camp = spellID;reagent:count;action;place for camp actions that use an item up without crafting one.",
       "-- tools = items or tool types a recipe needs in your bags (SpellTotems). noRecipe = copies the client says",
       "-- can't be used in profession recipes. vendorCap = reagents Blizzard says a vendor sells (source given).",
       "local _, ns = ...", "ns.Data = {", f"  build = {q(BUILD)},",
       "  professions = { " + ", ".join(q(p) for p in profs) + " },", "  recipes = {"]
out += ["    " + r + "," for _, _, r in out_rows]
out += ["  },", "  names = {"]
named = used | set(no_recipe)
out += [f"    [{k}] = {q(name_of(k))}," for k in sorted(named) if name_of(k)]
out += ["  },", "  hidden = {"]
out += [f"    [{k}] = true," for k in sorted(hidden)]
out += ["  },", "  camp = {"]
out += ["    " + c + "," for c in camp]
out += ["  },", "  tools = {"]
out += [f"    [{k}] = {{ {', '.join(q(t) for t in v)} }}," for k, v in sorted(tool_rows.items())]
out += ["  },", "  noRecipe = {"]
out += [f"    [{k}] = true," for k in no_recipe]
out += ["  },", "  vendorCap = {"]
out += [f"    [{k}] = {q(v)}," for k, v in sorted(VENDOR_CAP.items())]
out += ["  },", "  buy = {"]
for k in sorted(used):
    it = items.get(k)
    if k in vendor_sold and it and int(it["BuyPrice"] or 0) > 0:
        out.append(f"    [{k}] = {max(1, round(int(it['BuyPrice']) / max(1, int(it['VendorStackCount'] or 1))))},")
out += ["  },", "}"]
open(args.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(len(out_rows), "recipes,", len(named), "items,", len(camp), "camp actions,", len(tool_rows), "with tools,",
      len(no_recipe), "no-recipe copies;", "hotfixed SLA", len(sla_hf), "SpellReagents", len(sr_hf), stats)
