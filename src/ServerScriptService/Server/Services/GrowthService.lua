-- GrowthService.lua
-- Responsable de plantar, calcular el estado de crecimiento y cosechar.
-- Usa os.time() (no GetServerTimeNow) para que el tiempo de crecimiento
-- sobreviva a un restart del servidor entre sesiones del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crops = require(ReplicatedStorage.Shared.Config.Crops)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
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
	MaxPlotSlots: number,
	Plots: { [number]: PlotStateView }, -- slot index -> estado; slot vacío = ausente
}

local GrowthService = {}

-- Cantidad de slots de plantado del jugador: la base más el bonus del
-- gamepass "ExtraPlotSlots" si lo tiene. Único lugar donde vive esta cuenta.
function GrowthService.GetMaxPlotSlots(player: Player): number
	local bonus = 0
	if MonetizationService.HasGamePass(player, "ExtraPlotSlots") then
		bonus = Monetization.GamePasses.ExtraPlotSlots.BonusSlots or 0
	end
	return Economy.BASE_PLOT_SLOTS + bonus
end

-- Segundos de crecimiento reales para este jugador: la mitad para dueños
-- del gamepass "DoubleGrowthSpeed". Único lugar donde vive esta cuenta para
-- que GetSlotState (cuenta regresiva de la UI) y handleHarvest (validación
-- de "todavía no está lista") nunca puedan desincronizarse entre sí.
local function getEffectiveGrowSeconds(player: Player, crop: Crops.CropDefinition): number
	if MonetizationService.HasGamePass(player, "DoubleGrowthSpeed") then
		return crop.GrowSeconds / 2
	end
	return crop.GrowSeconds
end

-- Snapshot de solo lectura del estado del slot `slotIndex`, para que la UI
-- del cliente sepa si está vacío, creciendo (con cuenta regresiva) o listo.
function GrowthService.GetSlotState(player: Player, slotIndex: number): PlotStateView?
	local data = DataService.Get(player)
	if not data then
		return nil
	end

	local plantedCrop = data.Plots[slotIndex]
	if not plantedCrop then
		return nil
	end

	local crop = Crops[plantedCrop.SeedId]
	if not crop then
		return nil
	end

	local effectiveGrowSeconds = getEffectiveGrowSeconds(player, crop)
	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	local remainingSeconds = math.max(effectiveGrowSeconds - elapsedSeconds, 0)

	return {
		SeedId = plantedCrop.SeedId,
		GrowSeconds = effectiveGrowSeconds,
		RemainingSeconds = remainingSeconds,
		IsReady = remainingSeconds <= 0,
	}
end

local function handlePlantSeed(player: Player, seedId: string, slotIndex: number): ActionResult
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

	if slotIndex < 1 or slotIndex > GrowthService.GetMaxPlotSlots(player) then
		return { Success = false, Reason = "InvalidSlot" }
	end

	if data.Plots[slotIndex] ~= nil then
		return { Success = false, Reason = "PlotOccupied" }
	end

	if not InventoryService.HasItem(player, seedId) then
		return { Success = false, Reason = "SeedNotOwned" }
	end

	InventoryService.RemoveItem(player, seedId, 1)
	data.Plots[slotIndex] = { SeedId = seedId, PlantedAt = os.time() }

	return { Success = true }
end

local function handleHarvest(player: Player, slotIndex: number): ActionResult
	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if slotIndex < 1 or slotIndex > GrowthService.GetMaxPlotSlots(player) then
		return { Success = false, Reason = "InvalidSlot" }
	end

	local plantedCrop = data.Plots[slotIndex]
	if not plantedCrop then
		return { Success = false, Reason = "PlotEmpty" }
	end

	local crop = Crops[plantedCrop.SeedId]
	if not crop then
		-- Config borrada/renombrada después de que alguien ya la plantó.
		data.Plots[slotIndex] = nil
		return { Success = false, Reason = "SeedNotFound" }
	end

	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	if elapsedSeconds < getEffectiveGrowSeconds(player, crop) then
		return { Success = false, Reason = "NotReady" }
	end

	local reward = crop.HarvestReward
	if MonetizationService.HasGamePass(player, "DoubleCoins") then
		reward *= 2
	end

	if MonetizationService.HasGamePass(player, "VipGarden") then
		local bonusPercent = Monetization.GamePasses.VipGarden.CoinBonusPercent or 0
		reward += math.floor(reward * bonusPercent / 100)
	end

	data.Plots[slotIndex] = nil
	EconomyService.AddCoins(player, reward)

	return { Success = true }
end

-- Cosecha automática para dueños del gamepass "AutoCollect": revisa
-- periódicamente cada slot del jugador y cosecha los que estén listos,
-- reusando la misma validación que el harvest manual (nunca asume que un
-- slot sigue listo al momento de ejecutar).
local function startAutoCollectLoop(player: Player)
	task.spawn(function()
		while player.Parent do
			task.wait(AUTO_COLLECT_INTERVAL_SECONDS)
			if not player.Parent then
				break
			end

			if MonetizationService.HasGamePass(player, "AutoCollect") then
				for slotIndex = 1, GrowthService.GetMaxPlotSlots(player) do
					local state = GrowthService.GetSlotState(player, slotIndex)
					if state and state.IsReady then
						pcall(handleHarvest, player, slotIndex)
					end
				end
			end
		end
	end)
end

local function handleGetPlayerState(player: Player): PlayerStateView?
	local data = DataService.Get(player)
	if not data then
		return nil
	end

	local maxSlots = GrowthService.GetMaxPlotSlots(player)
	local plots: { [number]: PlotStateView } = {}
	for slotIndex = 1, maxSlots do
		local state = GrowthService.GetSlotState(player, slotIndex)
		if state then
			plots[slotIndex] = state
		end
	end

	return {
		Coins = data.Coins,
		Inventory = InventoryService.GetSnapshot(player),
		HasPlot = PlotService.GetPlot(player) ~= nil,
		MaxPlotSlots = maxSlots,
		Plots = plots,
	}
end

function GrowthService.Init()
	local plantSeedRemote = Remotes.GetPlantSeedRemote()
	local harvestRemote = Remotes.GetHarvestRemote()
	local getPlayerStateRemote = Remotes.GetPlayerStateRemote()

	plantSeedRemote.OnServerInvoke = function(player: Player, seedId: string, slotIndex: number)
		if typeof(seedId) ~= "string" or typeof(slotIndex) ~= "number" then
			return { Success = false, Reason = "InvalidRequest" }
		end

		local ok, result = pcall(handlePlantSeed, player, seedId, slotIndex)
		if not ok then
			warn(("[GrowthService] Error procesando PlantSeed de %s: %s"):format(player.Name, tostring(result)))
			return { Success = false, Reason = "ServerError" }
		end

		return result
	end

	harvestRemote.OnServerInvoke = function(player: Player, slotIndex: number)
		if typeof(slotIndex) ~= "number" then
			return { Success = false, Reason = "InvalidRequest" }
		end

		local ok, result = pcall(handleHarvest, player, slotIndex)
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
