-- EconomyService.lua
-- Responsable de monedas y compras (semillas, mejoras).
-- Toda compra se valida acá, en el servidor: nunca se confía en el precio
-- ni en la cantidad de coins que reporte el cliente.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Seeds = require(ReplicatedStorage.Shared.Config.Seeds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

export type BuySeedResult = {
	Success: boolean,
	Reason: string?, -- presente solo si Success == false
	Coins: number?, -- coins restantes tras la operación, si tuvo éxito
}

local EconomyService = {}

-- Suma coins al jugador. Falla en silencio (con warn) si sus datos no
-- están cargados todavía.
function EconomyService.AddCoins(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data then
		warn(("[EconomyService] No se pudo sumar coins a %s: datos no cargados."):format(player.Name))
		return false
	end

	data.Coins += amount
	return true
end

-- Resta coins al jugador. Devuelve false (sin descontar nada) si no le
-- alcanzan o si sus datos no están cargados.
function EconomyService.RemoveCoins(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or data.Coins < amount then
		return false
	end

	data.Coins -= amount
	return true
end

local function handleBuySeed(player: Player, seedId: string): BuySeedResult
	local seed = Seeds[seedId]
	if not seed then
		return { Success = false, Reason = "SeedNotFound" }
	end

	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if data.Coins < seed.Price then
		return { Success = false, Reason = "NotEnoughCoins" }
	end

	data.Coins -= seed.Price
	InventoryService.AddItem(player, seedId, 1)

	return { Success = true, Coins = data.Coins }
end

function EconomyService.Init()
	local buySeedRemote = Remotes.GetBuySeedRemote()

	buySeedRemote.OnServerInvoke = function(player: Player, seedId: string)
		if typeof(seedId) ~= "string" then
			return { Success = false, Reason = "InvalidRequest" }
		end

		local ok, result = pcall(handleBuySeed, player, seedId)
		if not ok then
			warn(("[EconomyService] Error procesando BuySeed de %s: %s"):format(player.Name, tostring(result)))
			return { Success = false, Reason = "ServerError" }
		end

		return result
	end
end

return EconomyService
