-- Monetization.lua
-- Configuración de gamepasses y developer products.
-- AssetId = 0 significa "todavía no creado en el Creator Dashboard": el
-- MonetizationService lo trata como no configurado (lo ignora sin romper
-- nada) hasta que se reemplace por el ID real.

export type GamePassDefinition = {
	AssetId: number,
	BonusSlots: number?, -- solo en ExtraPlotSlots: cuántos slots de plantado extra otorga
	CoinBonusPercent: number?, -- solo en VipGarden: % extra de coins en cada cosecha
}

export type DeveloperProductDefinition = {
	AssetId: number,
	CoinAmount: number?, -- presente solo en productos que otorgan coins directamente
}

local Monetization = {}

Monetization.GamePasses = {
	VipGarden = { AssetId = 0, CoinBonusPercent = 10 },
	DoubleCoins = { AssetId = 0 },
	DoubleGrowthSpeed = { AssetId = 0 },
	AutoCollect = { AssetId = 0 },
	ExtraPlotSlots = { AssetId = 0, BonusSlots = 2 },
}

Monetization.DeveloperProducts = {
	CoinPackSmall = { AssetId = 0, CoinAmount = 500 },
	CoinPackMedium = { AssetId = 0, CoinAmount = 1500 },
	CoinPackLarge = { AssetId = 0, CoinAmount = 5000 },
}

return Monetization
