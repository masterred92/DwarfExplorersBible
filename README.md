<p align="center"><img src="media/logo.png" alt="Dwarf Explorer's Bible logo" width="200"></p>

# Dwarf Explorer's Bible (WoW: Forever) v1.0.5

[![Tests](https://github.com/masterred92/DwarfExplorersBible/actions/workflows/tests.yml/badge.svg)](https://github.com/masterred92/DwarfExplorersBible/actions/workflows/tests.yml) [![WoW: Forever](https://img.shields.io/badge/WoW%3A%20Forever-Interface%2016001-c8a165)](https://github.com/masterred92/DwarfExplorersBible/blob/main/DwarfExplorersBible.toc) [![Release](https://img.shields.io/github/v/release/masterred92/DwarfExplorersBible?label=release)](https://github.com/masterred92/DwarfExplorersBible/releases) [![License: MIT](https://img.shields.io/github/license/masterred92/DwarfExplorersBible)](https://github.com/masterred92/DwarfExplorersBible/blob/main/LICENSE)

**What can I make with this?** Pick any material and Dwarf Explorer's Bible shows every recipe that uses it, what each one is worth at the auction house right now, and where the result goes next.

- **Pick a material:** Alt-click any item (bags, chat links, loot, the AH), type `/deb linen cloth`, paste a link, or use the search box.
- **Every recipe that uses it:** profession, skill level (orange when it's above yours), the other reagents, and whether you know the recipe.
- **Prices and profit:** the latest auction price for the material, every reagent and every crafted result, the reagent cost, and the estimated profit after the 5% AH cut. Each price says which addon it came from.
- **Follow the chain:** click a result to see what *that* makes: Linen Cloth > Bolt of Linen Cloth > Linen Bag. Back walks the chain back. "Made from" flips to the recipes that create the item.
- **Tooltip line:** "Used in N recipes (Dwarf Explorer's Bible)", with its price and source.
- **LDB launcher** for Titan Panel, ChocolateBar and other broker displays.

<p align="center"><img src="media/screenshots/banner.png" alt="Dwarf Explorer's Bible banner" width="560"></p>
<p align="center"><img src="media/screenshots/mockup-guide.png" alt="Dwarf Explorer's Bible preview" width="560"></p>

## Price sources
Dwarf Explorer's Bible reads prices from whichever price addon you already use. The first source in your order that has a price wins:

| Source | API used | Forever (16001) build |
| --- | --- | --- |
| [PriceLog](https://github.com/masterred92/PriceLog) (mine) | `KennyPriceLog.GetLatest(itemID)` | Yes |
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | `Auctionator.API.v1.GetAuctionPriceByItemID` | Yes (341, Oct 13 2026) |
| [TradeSkillMaster](https://tradeskillmaster.com) | `TSM_API.GetCustomPriceValue("DBMarket")`, then `DBMinBuyout` | Not yet; works when it ships one |
| [Auctioneer (Forever)](https://www.curseforge.com/wow/addons/auctioneer-forever) | `AucAdvanced.API.GetMarketValue` | Yes (4.0.0) |
| Dwarf Explorer's Bible scan | prices it sees in AH searches **you** do | Always on |

No price addon? It still works: every AH search you make (browse or commodity) is cached. It never searches on its own.
Change the order with `/deb prefer auctionator` or `/deb order tsm,auctionator,scan`; `/deb sources` shows the order and what's installed.

## Where the recipes come from
The recipe list (1,971 recipes across Alchemy, Blacksmithing, Cooking, Enchanting items, Engineering, First Aid, Leatherworking, Mining and Tailoring) comes from **WoW: Forever's own client tables** (build 1.60.1.70862, via [wago.tools](https://wago.tools)), so it has Forever's reagents, not vanilla's: for example Minor Healing Potion in Forever uses an Empty Vial, Mild Spices and Peaceblooms. `tools/gen_data.py` regenerates it after a patch. Skill levels are where a recipe turns yellow and grey, coloured against your own skill. Each time you open a profession window the addon also records what you know and adds any recipe the bundled list doesn't have.

**Reagent cost** uses the vendor price for reagents a vendor sells (thread, flux, vials, spices, dyes), as Auctionator's crafting view does: learned from merchant windows you open, else Forever's listed price. Everything else uses the auction price. Profit is shown only when every reagent and the result have a price, so a missing price can't make a recipe look better than it is.

## How it's different
Reverse lookups exist ([Recipe Master by BrenoLudgero](https://www.curseforge.com/wow/addons/recipe-master), ATT, Auctionator's crafting info, TSM's crafting tab, CraftSim on retail, Crafting Dictionary on retail), but they either track which recipes you're missing, price recipes you already know, or start from the recipe rather than the material. This one starts from the material, prices every option from your own AH addon, and lets you walk the chain material > intermediate > final, like the Guide in Terraria.

## Commands
`/deb` (or `/craftguide`) open · `/deb <name, link or itemID>` · `sources` · `prefer <id>` · `order a,b,c` · `tooltip` · `altclick` · `report` · `help`. Source ids: `pricelog`, `auctionator`, `tsm`, `auctioneer`, `scan`.

## Download
- **Wago Addons:** [Dwarf Explorer's Bible on Wago](https://addons.wago.io/addons/dwarfexplorersbible)
- **CurseForge:** [Dwarf Explorer's Bible on CurseForge](https://www.curseforge.com/wow/addons/dwarf-explorers-bible)
- **GitHub:** [Releases](https://github.com/masterred92/DwarfExplorersBible/releases) · [Issues](https://github.com/masterred92/DwarfExplorersBible/issues)
- **More by Kenny:** [PriceLog](https://github.com/masterred92/PriceLog) · [MatTooltip](https://github.com/masterred92/MatTooltip) · [NeutralFlip](https://github.com/masterred92/NeutralFlip) · [GoldPerSpot](https://github.com/masterred92/GoldPerSpot) · [all WoW: Forever addons](https://github.com/masterred92/wow-forever-addons)

## Install
Put the `DwarfExplorersBible` folder in `World of Warcraft\_forever_\Interface\AddOns\` and restart the game or `/reload`.

## In-game test checklist (launch day)
1. Listed in AddOns with its icon.
2. Hover Linen Cloth: "Used in N recipes (Dwarf Explorer's Bible)". Alt-click it: the guide opens on Linen Cloth.
3. `/deb copper bar` opens Copper Bar; click a result and Back returns.
4. Open each profession window: your known recipes turn green and your skill shows; a Forever-only recipe appears with "from your profession window".
5. With Auctionator installed and a scan done, prices say "(Auctionator)". Turn it off: an AH search you do shows "(Dwarf Explorer's Bible scan)".
6. `/deb prefer scan` and `/deb sources` show the new order; it survives `/reload`.
7. Titan Panel or another broker display shows the launcher.

## Credits
- Idea from Kenny's mate, who asked for "the Guide from Terraria, but for WoW, with auction prices".
- Inspired by the Guide NPC in Terraria (Re-Logic) and the tModLoader Recipe Browser mod's way of showing "what can I make from this". No code from either.
- Recipe data: WoW: Forever 1.60.1.70862 client tables via [wago.tools](https://wago.tools); vendor-sold flags from [nexus-devs/wow-classic-items](https://github.com/nexus-devs/wow-classic-items) (MIT).

## Licence
MIT. Written from scratch; no code copied from other addons. Free, no paid features. It doesn't automate anything: it only shows information, and only caches AH prices from searches you make yourself.

## Development
`tests/run.sh [path-to-wow-ui-source-forever]` runs `luac -p`, luacheck, the mock-client tests (every price source is mocked) and (with a path) an API check against Blizzard's Forever UI source. GitHub Actions runs the tests on every push. `tools/gen_data.py <csv-dir> [wow-classic-items data.json]` regenerates `Data.lua` from the current Forever client tables. Pushing a `v*` tag packages a full release with [BigWigsMods/packager](https://github.com/BigWigsMods/packager) and publishes it to CurseForge, Wago Addons and GitHub Releases (project IDs are in the TOC).
