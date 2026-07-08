-- MonsterService.lua
-- Único punto de verdad para resolver qué monstruo se obtiene al cosechar
-- una semilla, y para guardar/leer los monstruos que ya tiene un jugador.
-- No conoce Plots/crecimiento: sólo tablas de probabilidad y el inventario
-- de monstruos (data.Monsters).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Seeds = require(ReplicatedStorage.Shared.Config.Seeds)
local Monsters = require(ReplicatedStorage.Shared.Config.Monsters)
local DataService = require(script.Parent.DataService)

export type MonsterInstance = {
	InstanceId: string,
	MonsterId: string,
	Rarity: string,
	SellValue: number,
	HarvestedAt: number,
}

local MonsterService = {}

-- Tira la MonsterTable de la semilla `seedId` y devuelve el MonsterId
-- elegido. nil si la semilla no existe o su tabla está vacía (nunca tira
-- error: un roll fallido no debe romper la cosecha).
function MonsterService.RollMonster(seedId: string): string?
	local seed = Seeds[seedId]
	if not seed or #seed.MonsterTable == 0 then
		return nil
	end

	local roll = math.random()
	local accumulated = 0
	for _, entry in ipairs(seed.MonsterTable) do
		accumulated += entry.Chance
		if roll <= accumulated then
			return entry.MonsterId
		end
	end

	-- Redondeo de floats: si las Chance no suman exactamente 1.0, cae acá.
	-- Devolvemos la última entrada en vez de nil para no perder el roll.
	return seed.MonsterTable[#seed.MonsterTable].MonsterId
end

-- Crea una instancia de `monsterId` y la guarda en el inventario de
-- monstruos del jugador. nil (+ warn) si el monstruo no existe en la config
-- o si los datos del jugador no cargaron -- nunca tira error.
function MonsterService.GrantMonster(player: Player, monsterId: string): MonsterInstance?
	local definition = Monsters[monsterId]
	if not definition then
		warn(("[MonsterService] MonsterId desconocido: %s"):format(tostring(monsterId)))
		return nil
	end

	local data = DataService.Get(player)
	if not data then
		warn(("[MonsterService] No se pudo otorgar %s a %s: datos no cargados."):format(monsterId, player.Name))
		return nil
	end

	local instance: MonsterInstance = {
		InstanceId = HttpService:GenerateGUID(false),
		MonsterId = definition.Id,
		Rarity = definition.Rarity,
		SellValue = definition.SellValue,
		HarvestedAt = os.time(),
	}

	data.Monsters[instance.InstanceId] = instance
	return instance
end

-- Copia de solo lectura de los monstruos del jugador (instanceId -> datos),
-- o tabla vacía si sus datos todavía no cargaron.
function MonsterService.GetSnapshot(player: Player): { [string]: MonsterInstance }
	local data = DataService.Get(player)
	if not data then
		return {}
	end

	local snapshot = {}
	for instanceId, instance in pairs(data.Monsters) do
		snapshot[instanceId] = instance
	end
	return snapshot
end

function MonsterService.Init()
	-- Sin estado propio que inicializar: todo vive en DataService.
end

return MonsterService
