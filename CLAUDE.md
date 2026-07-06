# Monster Garden Tycoon - Claude Code Instructions

You are the lead Roblox/Luau engineer for Monster Garden Tycoon, a Roblox game inspired by collection simulators, garden tycoons, trading economies, and social defense mechanics.

## Game Vision

Build a Roblox game where players own a magical garden plot, plant creature eggs/seeds, wait for them to grow, collect coins, unlock rare creatures, upgrade their plot, trade with other players, and defend their garden from temporary social raids.

The game should be family-friendly, scalable, modular, and optimized for mobile-first Roblox players.

## Technical Rules

- Use Luau.
- Use modular service-based architecture.
- Keep server authority for all important economy, inventory, trading, purchases, and data saving logic.
- Never trust client requests for currency, item ownership, growth completion, trading, or purchases.
- Use RemoteEvents and RemoteFunctions with validation.
- Use DataStoreService safely with pcall and UpdateAsync when updating persistent data.
- Avoid saving too frequently.
- Add clear comments where business logic matters.
- Separate config data from logic.
- Avoid hardcoding item IDs, prices, timers, or rarity rates inside service logic.
- Every feature must be testable in isolation.

## Monetization Rules

Use gamepasses for permanent benefits:
- VIP Garden
- 2x Coins
- 2x Growth Speed
- Auto Collect
- Extra Plot Slots

Use developer products for repeat purchases:
- Coin packs
- Rare seed packs
- Event egg packs
- Temporary shields
- Instant grow tokens

Do not make the game pay-to-win. Paid products should accelerate progress or improve convenience, not destroy balance.

## MVP Scope

The first playable MVP must include:

1. Player joins and receives a plot.
2. Player receives starting coins.
3. Player can buy a basic seed.
4. Player can plant the seed in a plot slot.
5. Seed grows over time.
6. Player can harvest it.
7. Harvest gives coins.
8. Player data saves and loads.
9. Basic UI shows coins, inventory, shop, and planted items.
10. Admin test commands exist only in Studio.

Do not implement advanced trading, raids, events, or complex monetization before the MVP works.

## Code Quality

- Prefer small modules.
- Prefer descriptive function names.
- Add type annotations where useful.
- Keep configuration tables readable.
- Do not create massive files.
- Before coding a feature, explain the plan briefly.
- After coding a feature, summarize changed files and how to test it.
