-- PlotService.lua
-- Responsable de asignar y liberar la parcela física de cada jugador.
-- Las parcelas son Models construidos a mano en Studio dentro de
-- Workspace.Plots (ej. "Plot1", "Plot2", ...). Cada Model usa el atributo
-- "Owner" (number) para marcar de quién es: 0 significa libre.
-- Si el Model tiene una Part/Attachment llamado "SpawnPoint", el jugador
-- es teletransportado ahí al recibir su parcela.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PLOTS_FOLDER_NAME = "Plots"
local SPAWN_POINT_NAME = "SpawnPoint"

local PlotService = {}

-- userId -> Model de la parcela asignada.
local assignedPlots: { [number]: Model } = {}

local function getPlotsFolder(): Instance?
	local folder = Workspace:FindFirstChild(PLOTS_FOLDER_NAME)
	if not folder then
		warn(("[PlotService] No se encontró Workspace.%s. Construí las parcelas en Studio antes de probar esta feature.")
			:format(PLOTS_FOLDER_NAME))
	end
	return folder
end

local function findFreePlot(): Model?
	local folder = getPlotsFolder()
	if not folder then
		return nil
	end

	for _, plot in ipairs(folder:GetChildren()) do
		if plot:IsA("Model") and plot:GetAttribute("Owner") == 0 then
			return plot
		end
	end

	return nil
end

local function teleportToPlot(player: Player, plot: Model)
	local spawnPoint = plot:FindFirstChild(SPAWN_POINT_NAME, true)
	if not spawnPoint then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local spawnCFrame = (spawnPoint :: any).CFrame or CFrame.new((spawnPoint :: any).Position);
	(rootPart :: BasePart).CFrame = spawnCFrame + Vector3.new(0, 3, 0)
end

-- Devuelve la parcela asignada al jugador, o nil si todavía no tiene.
function PlotService.GetPlot(player: Player): Model?
	return assignedPlots[player.UserId]
end

local function assignPlot(player: Player)
	local plot = findFreePlot()
	if not plot then
		warn(("[PlotService] No hay parcelas libres para %s."):format(player.Name))
		return
	end

	plot:SetAttribute("Owner", player.UserId)
	assignedPlots[player.UserId] = plot

	if player.Character then
		teleportToPlot(player, plot)
	end

	player.CharacterAdded:Connect(function()
		if assignedPlots[player.UserId] == plot then
			teleportToPlot(player, plot)
		end
	end)
end

local function releasePlot(player: Player)
	local plot = assignedPlots[player.UserId]
	if not plot then
		return
	end

	plot:SetAttribute("Owner", 0)
	assignedPlots[player.UserId] = nil
end

function PlotService.Init()
	Players.PlayerAdded:Connect(assignPlot)
	Players.PlayerRemoving:Connect(releasePlot)

	-- Jugadores ya conectados al momento de correr Init (Play Solo en Studio).
	for _, player in ipairs(Players:GetPlayers()) do
		assignPlot(player)
	end
end

return PlotService
