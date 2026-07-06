-- Crops.lua
-- Configuración de semillas/cultivos (precio, tiempo de crecimiento, recompensa).

export type CropDefinition = {
	Id: string,
	Name: string,
	Price: number, -- costo en coins para comprarla en la tienda
	GrowSeconds: number, -- tiempo de crecimiento una vez plantada
	HarvestReward: number, -- coins que da al cosecharla
}

local Crops: { [string]: CropDefinition } = {
	BasicSeed = {
		Id = "BasicSeed",
		Name = "Semilla Básica",
		Price = 25,
		GrowSeconds = 60,
		HarvestReward = 15,
	},
}

return Crops
