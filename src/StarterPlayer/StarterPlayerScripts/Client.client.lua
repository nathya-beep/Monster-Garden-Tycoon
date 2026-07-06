-- Client.client.lua
-- UI básica del jugador: coins, inventario, tienda y estado de las parcelas.
-- Construida por código (no hay assets de UI en StarterGui todavía).
-- Toda la lógica de negocio vive en el servidor; este script solo dispara
-- los remotes y refleja lo que el servidor le devuelve.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Crops = require(ReplicatedStorage.Shared.Config.Crops)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buySeedRemote = Remotes.GetBuySeedRemote()
local plantSeedRemote = Remotes.GetPlantSeedRemote()
local harvestRemote = Remotes.GetHarvestRemote()
local getPlayerStateRemote = Remotes.GetPlayerStateRemote()

local BASIC_SEED_ID = "BasicSeed"
local POLL_INTERVAL_SECONDS = 2
local STATUS_MESSAGE_SECONDS = 2.5

local PLOT_PANEL_WIDTH = 260
local PLOT_PANEL_HEIGHT = 150
local PLOT_PANEL_GAP = 12
local PLOTS_HEADER_POSITION = UDim2.new(0, 20, 0, 205)
local PLOTS_HEADER_SIZE = UDim2.new(0, 260, 0, 20)
local PLOTS_CONTAINER_POSITION = UDim2.new(0, 20, 0, 230)

local REASON_MESSAGES: { [string]: string } = {
	SeedNotFound = "Esa semilla no existe.",
	DataNotLoaded = "Tus datos todavía se están cargando.",
	NotEnoughCoins = "No te alcanzan las coins.",
	NoPlot = "Todavía no tenés una parcela asignada.",
	PlotOccupied = "Ya tenés algo plantado ahí.",
	SeedNotOwned = "No tenés esa semilla en el inventario.",
	PlotEmpty = "No hay nada plantado ahí.",
	NotReady = "Todavía no está lista para cosechar.",
	InvalidSlot = "Slot de parcela inválido.",
	ServerError = "Ocurrió un error en el servidor.",
	InvalidRequest = "Pedido inválido.",
}

-- === Construcción de la UI ===

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GardenUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local function createLabel(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = parent
	return label
end

local function createButton(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent
	return button
end

local coinsLabel = createLabel(screenGui, "CoinsLabel", UDim2.new(0, 20, 0, 20), UDim2.new(0, 220, 0, 50), "Coins: --")

local statusLabel = createLabel(screenGui, "StatusLabel", UDim2.new(0.5, -200, 0, 20), UDim2.new(0, 400, 0, 40), "")
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
statusLabel.Visible = false

local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopPanel"
shopFrame.Position = UDim2.new(0, 20, 0, 90)
shopFrame.Size = UDim2.new(0, 260, 0, 110)
shopFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
shopFrame.BackgroundTransparency = 0.2
shopFrame.Parent = screenGui

createLabel(shopFrame, "Title", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 30), "Tienda")
local inventoryLabel = createLabel(shopFrame, "InventoryLabel", UDim2.new(0, 0, 0, 32), UDim2.new(1, 0, 0, 28), "Semillas: 0")
local buySeedButton = createButton(
	shopFrame,
	"BuySeedButton",
	UDim2.new(0, 10, 0, 64),
	UDim2.new(1, -20, 0, 40),
	("Comprar Semilla (%d coins)"):format(Crops[BASIC_SEED_ID].Price)
)

local plotsHeaderLabel = createLabel(screenGui, "PlotsHeader", PLOTS_HEADER_POSITION, PLOTS_HEADER_SIZE, "Parcelas")
plotsHeaderLabel.BackgroundTransparency = 1
plotsHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left

local plotsContainer = Instance.new("Frame")
plotsContainer.Name = "PlotsContainer"
plotsContainer.Position = PLOTS_CONTAINER_POSITION
plotsContainer.Size = UDim2.new(0, PLOT_PANEL_WIDTH, 0, 0)
plotsContainer.AutomaticSize = Enum.AutomaticSize.Y
plotsContainer.BackgroundTransparency = 1
plotsContainer.Parent = screenGui

-- === Estado / feedback ===

local function showStatus(message: string)
	statusLabel.Text = message
	statusLabel.Visible = true
	task.delay(STATUS_MESSAGE_SECONDS, function()
		if statusLabel.Text == message then
			statusLabel.Visible = false
		end
	end)
end

local function describeReason(reason: string?): string
	return (reason and REASON_MESSAGES[reason]) or "No se pudo completar la acción."
end

-- === Parcelas dinámicas (una por slot: Economy.BASE_PLOT_SLOTS + bonus de ExtraPlotSlots) ===

local fetchState -- forward declaration: los handlers de los slots la necesitan.

type SlotPanel = {
	Frame: Frame,
	StatusLabel: TextLabel,
	PlantButton: TextButton,
	HarvestButton: TextButton,
}

local slotPanels: { [number]: SlotPanel } = {}
local currentSlotCount = 0

local function requestPlantSeed(slotIndex: number)
	local ok, result = pcall(function()
		return plantSeedRemote:InvokeServer(BASIC_SEED_ID, slotIndex)
	end)

	showStatus(ok and result.Success and "¡Semilla plantada!" or describeReason(ok and result.Reason))
	fetchState()
end

local function requestHarvest(slotIndex: number)
	local ok, result = pcall(function()
		return harvestRemote:InvokeServer(slotIndex)
	end)

	showStatus(ok and result.Success and "¡Cosecha exitosa!" or describeReason(ok and result.Reason))
	fetchState()
end

local function createSlotPanel(slotIndex: number): SlotPanel
	local frame = Instance.new("Frame")
	frame.Name = ("PlotPanel%d"):format(slotIndex)
	frame.Position = UDim2.new(0, 0, 0, (slotIndex - 1) * (PLOT_PANEL_HEIGHT + PLOT_PANEL_GAP))
	frame.Size = UDim2.new(0, PLOT_PANEL_WIDTH, 0, PLOT_PANEL_HEIGHT)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	frame.BackgroundTransparency = 0.2
	frame.Parent = plotsContainer

	createLabel(frame, "Title", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 30), ("Parcela %d"):format(slotIndex))
	local slotStatusLabel = createLabel(frame, "PlotStatusLabel", UDim2.new(0, 0, 0, 32), UDim2.new(1, 0, 0, 40), "Cargando...")
	local plantButton = createButton(frame, "PlantButton", UDim2.new(0, 10, 0, 76), UDim2.new(1, -20, 0, 32), "Plantar Semilla")
	local harvestButton = createButton(frame, "HarvestButton", UDim2.new(0, 10, 0, 112), UDim2.new(1, -20, 0, 32), "Cosechar")

	plantButton.MouseButton1Click:Connect(function()
		requestPlantSeed(slotIndex)
	end)

	harvestButton.MouseButton1Click:Connect(function()
		requestHarvest(slotIndex)
	end)

	return {
		Frame = frame,
		StatusLabel = slotStatusLabel,
		PlantButton = plantButton,
		HarvestButton = harvestButton,
	}
end

-- Reconstruye los paneles de parcela si la cantidad de slots cambió (ej. el
-- jugador compró ExtraPlotSlots a mitad de sesión). No hace nada si ya
-- coincide, para no destruir/recrear la UI en cada poll.
local function ensureSlotPanels(maxSlots: number)
	if maxSlots == currentSlotCount then
		return
	end

	for _, panel in ipairs(slotPanels) do
		panel.Frame:Destroy()
	end
	table.clear(slotPanels)

	for slotIndex = 1, maxSlots do
		slotPanels[slotIndex] = createSlotPanel(slotIndex)
	end

	currentSlotCount = maxSlots
end

local function refreshUI(state)
	if not state then
		return
	end

	coinsLabel.Text = ("Coins: %d"):format(state.Coins)
	inventoryLabel.Text = ("Semillas: %d"):format(state.Inventory[BASIC_SEED_ID] or 0)

	if not state.HasPlot then
		plotsHeaderLabel.Text = "Sin parcela asignada."
		ensureSlotPanels(0)
		return
	end

	plotsHeaderLabel.Text = ("Parcelas (%d)"):format(state.MaxPlotSlots)
	ensureSlotPanels(state.MaxPlotSlots)

	for slotIndex, panel in ipairs(slotPanels) do
		local plot = state.Plots[slotIndex]
		if not plot then
			panel.StatusLabel.Text = "Parcela vacía."
			panel.PlantButton.Visible = true
			panel.HarvestButton.Visible = false
		elseif plot.IsReady then
			panel.StatusLabel.Text = "¡Lista para cosechar!"
			panel.PlantButton.Visible = false
			panel.HarvestButton.Visible = true
		else
			panel.StatusLabel.Text = ("Creciendo... %ds restantes"):format(plot.RemainingSeconds)
			panel.PlantButton.Visible = false
			panel.HarvestButton.Visible = false
		end
	end
end

fetchState = function()
	local ok, state = pcall(function()
		return getPlayerStateRemote:InvokeServer()
	end)

	if ok then
		refreshUI(state)
	else
		warn("[Client] No se pudo obtener el estado del jugador: " .. tostring(state))
	end
end

-- === Conexiones de botones ===

buySeedButton.MouseButton1Click:Connect(function()
	local ok, result = pcall(function()
		return buySeedRemote:InvokeServer(BASIC_SEED_ID)
	end)

	showStatus(ok and result.Success and "¡Semilla comprada!" or describeReason(ok and result.Reason))
	fetchState()
end)

-- === Polling periódico ===

fetchState()

task.spawn(function()
	while screenGui.Parent do
		task.wait(POLL_INTERVAL_SECONDS)
		fetchState()
	end
end)

print("[Client] Monster Garden Tycoon - UI inicializada.")
