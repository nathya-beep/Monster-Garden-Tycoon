-- Seeds.lua
-- Configuración de semillas (precio, tiempo de crecimiento, recompensa de
-- coins directas y tabla de probabilidad de qué monstruo se obtiene al
-- cosechar). Reemplaza al viejo Crops.lua -- mismo patrón, con rareza y
-- tabla de monstruos agregadas.

export type SeedMonsterChance = {
	MonsterId: string,
	Chance: number, -- 0..1; la suma de todas las entradas de una semilla debe dar 1.0
}

export type SeedDefinition = {
	Id: string,
	Name: string,
	Rarity: string, -- "Common" | "Uncommon" (más rarezas se suman en ciclos futuros)
	Price: number, -- costo en coins para comprarla en la tienda
	GrowSeconds: number, -- tiempo de crecimiento una vez plantada
	HarvestCoins: number, -- coins directas que da al cosechar
	MonsterTable: { SeedMonsterChance }, -- qué monstruo se obtiene al cosechar
}

local Seeds: { [string]: SeedDefinition } = {
	BasicSeed = {
		Id = "BasicSeed",
		Name = "Semilla Básica",
		Rarity = "Common",
		Price = 25,
		GrowSeconds = 60,
		HarvestCoins = 10,
		MonsterTable = {
			{ MonsterId = "SlimeBasic", Chance = 0.70 },
			{ MonsterId = "MushlingBasic", Chance = 0.30 },
		},
	},
	UncommonSeed = {
		Id = "UncommonSeed",
		Name = "Semilla Poco Común",
		Rarity = "Uncommon",
		Price = 100,
		GrowSeconds = 180,
		HarvestCoins = 40,
		MonsterTable = {
			{ MonsterId = "MushlingBasic", Chance = 0.55 },
			{ MonsterId = "CrystalPup", Chance = 0.40 },
			{ MonsterId = "SlimeBasic", Chance = 0.05 },
		},
	},
}

return Seeds
