-- Monetization.lua
-- Configuración de gamepasses y developer products.
-- AssetId = 0 significa "todavía no creado en el Creator Dashboard": el
-- MonetizationService lo trata como no configurado (lo ignora sin romper
-- nada) hasta que se reemplace por el ID real.

export type GamePassDefinition = {
	AssetId: number,
}

export type DeveloperProductDefinition = {
	AssetId: number,
	CoinAmount: number?, -- presente solo en productos que otorgan coins directamente
}

local Monetization = {}

Monetization.GamePasses: { [string]: GamePassDefinition } = {
	VipGarden = { AssetId = 0 },
	DoubleCoins = { AssetId = 0 },
	DoubleGrowthSpeed = { AssetId = 0 },
	AutoCollect = { AssetId = 0 },
	ExtraPlotSlots = { AssetId = 0 },
}

Monetization.DeveloperProducts: { [string]: DeveloperProductDefinition } = {
	CoinPackSmall = { AssetId = 0, CoinAmount = 500 },
	CoinPackMedium = { AssetId = 0, CoinAmount = 1500 },
	CoinPackLarge = { AssetId = 0, CoinAmount = 5000 },
}

return Monetization
