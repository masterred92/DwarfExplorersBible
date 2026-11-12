# Changelog

## 1.1.0
- Recipe data now includes the server hotfixes Blizzard has pushed since launch (client build 1.60.1.70888 plus its hotfixes, via wago.tools). 2,090 recipes (was 1,971) using or making 2,461 items (was 2,331).
- New professions: Herbalism, Skinning and Fishing camp crafts (Incense Candle, Greenhouse, Seed Hybridizer, Camp Chair, Field Guide, Trapper's Workbench, Fish Bowl, Fishing Rack, Fishing Hut), all 26 Poisons, and Comprehension (Study).
- Herb seeds show their camp uses instead of nothing: plant 1 at a Greenhouse, or hybridize 2 at a Seed Hybridizer.
- 83 recipes are back whose crafted item wasn't in the client's item table, including the 32 Artisan's Tier Leatherworking pieces that use Fel Leather, 20 Blacksmithing and 16 Tailoring pieces, Revealing Draught and Critter Cookie. 71 are named from Blizzard's hotfixed item records; the 12 Blizzard still keeps out of the game files are listed under the recipe's name and marked "Not released yet".
- Skill levels fixed for 21 recipes: Tanning Rack 125/125 (was 140/145), Coarse Grinding Stone gives skill-ups to 90 (was 75), and 19 camp crafts now go grey at the level you learn them.
- Five Tailoring bags take one more bolt after the Nov 11 hotfix: Red Mageweave Bag, Green Silk Pack, Black Silk Pack, Green Woolen Bag and Red Woolen Bag.
- Black Lotus is marked as sold by a vendor in Forever. Once you've opened that vendor's window, its price caps what Black Lotus costs in profit maths.
- The potion copies the game says can't be used in profession recipes (Minor and Lesser Healing and Mana, Swiftness, Free Action, Greater Healing) say so in their tooltip.
- The recipe tooltip lists any tool the recipe needs in your bags, for example the Runed Golden Rod for the Arcane Salvager.
- `/deb report` shows which client build the bundled data is from.

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
