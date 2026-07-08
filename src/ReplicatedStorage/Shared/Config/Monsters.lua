-- Monsters.lua
-- Registro de definiciones de monstruo. Independiente de Seeds.lua para que
-- objetos rompibles u otras semillas (ciclos futuros) puedan referenciar
-- los mismos monstruos sin duplicar sus datos.

export type MonsterDefinition = {
	Id: string,
	Name: string,
	Rarity: string,
	SellValue: number, -- coins que daría vender este monstruo (venta real: ciclo futuro de PetService)
}

local Monsters: { [string]: MonsterDefinition } = {
	SlimeBasic = {
		Id = "SlimeBasic",
		Name = "Slime Básico",
		Rarity = "Common",
		SellValue = 30,
	},
	MushlingBasic = {
		Id = "MushlingBasic",
		Name = "Hongomonstruo Básico",
		Rarity = "Common",
		SellValue = 35,
	},
	CrystalPup = {
		Id = "CrystalPup",
		Name = "Cristalito",
		Rarity = "Uncommon",
		SellValue = 250,
	},
}

return Monsters
