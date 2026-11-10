# Changelog

## 1.0.5
- Rebuilt the recipe list from the current WoW: Forever client tables (build 1.60.1.70862, via wago.tools). The 1,971 recipes, reagents, skill levels and vendor prices are unchanged from 1.0.4.
- README: the release workflow already publishes tagged versions to CurseForge, Wago Addons and GitHub Releases.

## 1.0.4
- No duplicate AH price in tooltips: when MatTooltip is installed, its price line is the only one on trade goods.

## 1.0.3
- `/deb prefer <unknown id>` now lists the valid source ids instead of searching for an item called 'prefer ...'.
- Slash commands typed before the addon finished loading are ignored instead of erroring.

## 1.0.2
- Now published on CurseForge and Wago Addons; download links added to the README.
- Releases are published automatically from tagged versions.

## 1.0.1
- Recipes now come from WoW: Forever's own client data (1,971 recipes) instead of vanilla data; many Forever recipes use different reagents.
- Skill shown as where the recipe turns yellow/grey, coloured for your skill like the profession window.
- Vendor-sold reagents (thread, flux, vials...) are costed at the vendor price, learned from merchant windows you open.
- Profit is only shown when every price is known (no more optimistic "partial" profits).
- Auctioneer prices: pass the item ID, so Auctioneer no longer prints "Link is not item".
- Profession scans are debounced; tooltip lines can't be added twice.

## 1.0.0 (first release)
- Pick a material by Alt-click, `/deb <name, link or ID>` or the search box, and see every recipe that uses it: profession, skill level, other reagents, and whether you know it.
- Latest auction price for the material, reagents and results, reagent cost and estimated profit after the AH cut, each labelled with its source.
- Price sources: PriceLog, Auctionator, TradeSkillMaster, Auctioneer, and its own cache of your AH searches. Order set with `/deb prefer` or `/deb order`.
- Crafting chains: click a result to follow it, Back to return, "Made from" for the recipes that create an item.
- Bundled recipe list plus recipes recorded from your own profession windows.
- Tooltip line "used in N recipes" and an LDB launcher. Game version: WoW: Forever 1.60.1 (Interface 16001).
