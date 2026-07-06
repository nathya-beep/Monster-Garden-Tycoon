-- GrowthService.lua
-- Responsable de plantar, calcular el estado de crecimiento y cosechar.
-- Usa os.time() (no GetServerTimeNow) para que el tiempo de crecimiento
-- sobreviva a un restart del servidor entre sesiones del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crops = require(ReplicatedStorage.Shared.Config.Crops)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local InventoryService = require(script.Parent.InventoryService)
local MonetizationService = require(script.Parent.MonetizationService)

local AUTO_COLLECT_INTERVAL_SECONDS = 5

export type ActionResult = {
	Success: boolean,
	Reason: string?,
}

export type PlotStateView = {
	SeedId: string,
	GrowSeconds: number,
	RemainingSeconds: number,
	IsReady: boolean,
}

export type PlayerStateView = {
	Coins: number,
	Inventory: { [string]: number },
	HasPlot: boolean,
	Plot: PlotStateView?,
}

local GrowthService = {}

-- Snapshot de solo lectura del estado de la parcela, para que la UI del
-- cliente sepa si está vacía, creciendo (con cuenta regresiva) o lista.
function GrowthService.GetPlotState(player: Player): PlotStateView?
	local data = DataService.Get(player)
	if not data or not data.Plot then
		return nil
	end

	local plantedCrop = data.Plot
	local crop = Crops[plantedCrop.SeedId]
	if not crop then
		return nil
	end

	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	local remainingSeconds = math.max(crop.GrowSeconds - elapsedSeconds, 0)

	return {
		SeedId = plantedCrop.SeedId,
		GrowSeconds = crop.GrowSeconds,
		RemainingSeconds = remainingSeconds,
		IsReady = remainingSeconds <= 0,
	}
end

local function handlePlantSeed(player: Player, seedId: string): ActionResult
	local crop = Crops[seedId]
	if not crop then
		return { Success = false, Reason = "SeedNotFound" }
	end

	if not PlotService.GetPlot(player) then
		return { Success = false, Reason = "NoPlot" }
	end

	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if data.Plot ~= nil then
		return { Success = false, Reason = "PlotOccupied" }
	end

	if not InventoryService.HasItem(player, seedId) then
		return { Success = false, Reason = "SeedNotOwned" }
	end

	InventoryService.RemoveItem(player, seedId, 1)
	data.Plot = { SeedId = seedId, PlantedAt = os.time() }

	return { Success = true }
end

local function handleHarvest(player: Player): ActionResult
	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	local plantedCrop = data.Plot
	if not plantedCrop then
		return { Success = false, Reason = "PlotEmpty" }
	end

	local crop = Crops[plantedCrop.SeedId]
	if not crop then
		-- Config borrada/renombrada después de que alguien ya la plantó.
		data.Plot = nil
		return { Success = false, Reason = "SeedNotFound" }
	end

	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	if elapsedSeconds < crop.GrowSeconds then
		return { Success = false, Reason = "NotReady" }
	end

	local reward = crop.HarvestReward
	if MonetizationService.HasGamePass(player, "DoubleCoins") then
		reward *= 2
	end

	data.Plot = nil
	EconomyService.AddCoins(player, reward)

	return { Success = true }
end

-- Cosecha automática para dueños del gamepass "AutoCollect": revisa
-- periódicamente si la parcela del jugador está lista y la cosecha sola,
-- reusando la misma validación que el harvest manual (nunca asume que la
-- parcela sigue lista al momento de ejecutar).
local function startAutoCollectLoop(player: Player)
	task.spawn(function()
		while player.Parent do
			task.wait(AUTO_COLLECT_INTERVAL_SECONDS)
			if not player.Parent then
				break
			end

			if MonetizationService.HasGamePass(player, "AutoCollect") then
				pcall(handleHarvest, player)
			end
		end
	end)
end

local function handleGetPlayerState(player: Player): PlayerStateView?
	local data = DataService.Get(player)
	if not data then
		return nil
	end

	return {
		Coins = data.Coins,
		Inventory = InventoryService.GetSnapshot(player),
		HasPlot = PlotService.GetPlot(player) ~= nil,
		Plot = GrowthService.GetPlotState(player),
	}
end

function GrowthService.Init()
	local plantSeedRemote = Remotes.GetPlantSeedRemote()
	local harvestRemote = Remotes.GetHarvestRemote()
	local getPlayerStateRemote = Remotes.GetPlayerStateRemote()

	plantSeedRemote.OnServerInvoke = function(player: Player, seedId: string)
		if typeof(seedId) ~= "string" then
			return { Success = false, Reason = "InvalidRequest" }
		end

		local ok, result = pcall(handlePlantSeed, player, seedId)
		if not ok then
			warn(("[GrowthService] Error procesando PlantSeed de %s: %s"):format(player.Name, tostring(result)))
			return { Success = false, Reason = "ServerError" }
		end

		return result
	end

	harvestRemote.OnServerInvoke = function(player: Player)
		local ok, result = pcall(handleHarvest, player)
		if not ok then
			warn(("[GrowthService] Error procesando Harvest de %s: %s"):format(player.Name, tostring(result)))
			return { Success = false, Reason = "ServerError" }
		end

		return result
	end

	getPlayerStateRemote.OnServerInvoke = function(player: Player)
		local ok, result = pcall(handleGetPlayerState, player)
		if not ok then
			warn(("[GrowthService] Error procesando GetPlayerState de %s: %s"):format(player.Name, tostring(result)))
			return nil
		end

		return result
	end

	Players.PlayerAdded:Connect(startAutoCollectLoop)

	for _, player in ipairs(Players:GetPlayers()) do
		startAutoCollectLoop(player)
	end
end

return GrowthService
