# Changelog

## 1.0.1
- Recipes now come from WoW: Forever's own client data (1,971 recipes) instead of vanilla data; many Forever recipes use different reagents.
- Skill shown as where the recipe turns yellow/grey, coloured for your skill like the profession window.
- Vendor-sold reagents (thread, flux, vials...) are costed at the vendor price, learned from merchant windows you open.
- Profit is only shown when every price is known (no more optimistic "partial" profits).
- Auctioneer prices: pass the item ID, so Auctioneer no longer prints "Link is not item".
- Profession scans are debounced; tooltip lines can't be added twice.

## 1.0.0 (first release)
- Pick a material by Alt-click, `/wcim <name, link or ID>` or the search box, and see every recipe that uses it: profession, skill level, other reagents, and whether you know it.
- Latest auction price for the material, reagents and results, reagent cost and estimated profit after the AH cut, each labelled with its source.
- Price sources: PriceLog, Auctionator, TradeSkillMaster, Auctioneer, and its own cache of your AH searches. Order set with `/wcim prefer` or `/wcim order`.
- Crafting chains: click a result to follow it, Back to return, "Made from" for the recipes that create an item.
- Bundled recipe list plus recipes recorded from your own profession windows.
- Tooltip line "used in N recipes" and an LDB launcher. Game version: WoW: Forever 1.60.1 (Interface 16001).
