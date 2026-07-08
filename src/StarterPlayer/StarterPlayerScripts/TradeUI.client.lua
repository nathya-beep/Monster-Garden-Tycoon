-- TradeUI.client.lua
-- UI de trading entre jugadores: detección de proximidad, solicitud/
-- aceptación, panel de oferta con doble confirmación. Separado de
-- Client.client.lua para no mezclar la UI de trading con coins/tienda/parcelas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local requestTradeEvent = Remotes.GetRequestTradeEvent()
local respondTradeRequestEvent = Remotes.GetRespondTradeRequestEvent()
local updateTradeOfferEvent = Remotes.GetUpdateTradeOfferEvent()
local confirmTradeEvent = Remotes.GetConfirmTradeEvent()
local cancelTradeEvent = Remotes.GetCancelTradeEvent()
local tradeStateChangedEvent = Remotes.GetTradeStateChangedEvent()
local getPlayerStateRemote = Remotes.GetPlayerStateRemote()

-- Mismo valor que TRADE_RANGE_STUDS en TradeService.lua: el servidor
-- revalida la distancia real, esto es solo para mostrar/ocultar el botón.
local TRADE_RANGE_STUDS = 10
local INVENTORY_POLL_SECONDS = 2

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TradeUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local function createLabel(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundColor3 = Theme.Colors.Panel
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Theme.Colors.Text
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = label

	return label
end

local function createButton(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Theme.Colors.PanelAccent
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = button

	return button
end

-- === Botón "Solicitar Trade" por proximidad ===

local requestButton = createButton(screenGui, "RequestTradeButton", UDim2.new(0.5, -110, 1, -80), UDim2.new(0, 220, 0, 40), "")
requestButton.Visible = false

local nearbyTargetUserId: number? = nil
local requestPending = false

local function findNearbyPlayer(): Player?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local closest: Player? = nil
	local closestDistance = TRADE_RANGE_STUDS

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local distance = ((rootPart :: BasePart).Position - (otherRoot :: BasePart).Position).Magnitude
				if distance <= closestDistance then
					closest = other
					closestDistance = distance
				end
			end
		end
	end

	return closest
end

requestButton.MouseButton1Click:Connect(function()
	if nearbyTargetUserId and not requestPending then
		requestPending = true
		requestTradeEvent:FireServer(nearbyTargetUserId)
		requestButton.Text = "Solicitud enviada..."
	end
end)

RunService.Heartbeat:Connect(function()
	if requestPending then
		return
	end

	local nearby = findNearbyPlayer()
	if nearby then
		nearbyTargetUserId = nearby.UserId
		requestButton.Visible = true
		requestButton.Text = ("Solicitar Trade a %s"):format(nearby.Name)
	else
		nearbyTargetUserId = nil
		requestButton.Visible = false
	end
end)

-- === Solicitud entrante ===

local incomingRequestFrame = Instance.new("Frame")
incomingRequestFrame.Name = "IncomingTradeRequest"
incomingRequestFrame.AnchorPoint = Vector2.new(0.5, 0)
incomingRequestFrame.Position = UDim2.new(0.5, 0, 0, 20)
incomingRequestFrame.Size = UDim2.new(0, 300, 0, 90)
incomingRequestFrame.BackgroundColor3 = Theme.Colors.Panel
incomingRequestFrame.Visible = false
incomingRequestFrame.Parent = screenGui

local incomingCorner = Instance.new("UICorner")
incomingCorner.CornerRadius = Theme.CornerRadius
incomingCorner.Parent = incomingRequestFrame

local incomingLabel = createLabel(incomingRequestFrame, "Label", UDim2.new(0, 10, 0, 5), UDim2.new(1, -20, 0, 30), "")
incomingLabel.BackgroundTransparency = 1

local acceptButton = createButton(incomingRequestFrame, "Accept", UDim2.new(0, 10, 0, 45), UDim2.new(0.5, -15, 0, 35), "Aceptar")
local declineButton = createButton(incomingRequestFrame, "Decline", UDim2.new(0.5, 5, 0, 45), UDim2.new(0.5, -15, 0, 35), "Rechazar")

local pendingIncomingFromUserId: number? = nil

acceptButton.MouseButton1Click:Connect(function()
	if pendingIncomingFromUserId then
		respondTradeRequestEvent:FireServer(pendingIncomingFromUserId, true)
		incomingRequestFrame.Visible = false
		pendingIncomingFromUserId = nil
	end
end)

declineButton.MouseButton1Click:Connect(function()
	if pendingIncomingFromUserId then
		respondTradeRequestEvent:FireServer(pendingIncomingFromUserId, false)
		incomingRequestFrame.Visible = false
		pendingIncomingFromUserId = nil
	end
end)

-- === Panel de trade activo ===

local tradePanel = Instance.new("Frame")
tradePanel.Name = "TradePanel"
tradePanel.AnchorPoint = Vector2.new(0.5, 0.5)
tradePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
tradePanel.Size = UDim2.new(0, 520, 0, 380)
tradePanel.BackgroundColor3 = Theme.Colors.Background
tradePanel.Visible = false
tradePanel.Parent = screenGui

local tradePanelCorner = Instance.new("UICorner")
tradePanelCorner.CornerRadius = Theme.CornerRadius
tradePanelCorner.Parent = tradePanel

local titleLabel = createLabel(tradePanel, "Title", UDim2.new(0, 10, 0, 10), UDim2.new(1, -20, 0, 30), "Trade")
titleLabel.BackgroundTransparency = 1

local yourOfferLabel = createLabel(tradePanel, "YourOfferLabel", UDim2.new(0, 10, 0, 50), UDim2.new(0.45, 0, 0, 24), "Tu oferta")
local theirOfferLabel = createLabel(tradePanel, "TheirOfferLabel", UDim2.new(0.55, 0, 0, 50), UDim2.new(0.45, 0, 0, 24), "Su oferta")

local yourOfferText = createLabel(tradePanel, "YourOfferText", UDim2.new(0, 10, 0, 78), UDim2.new(0.45, 0, 0, 80), "(vacío)")
yourOfferText.TextXAlignment = Enum.TextXAlignment.Left
yourOfferText.TextYAlignment = Enum.TextYAlignment.Top

local theirOfferText = createLabel(tradePanel, "TheirOfferText", UDim2.new(0.55, 0, 0, 78), UDim2.new(0.45, 0, 0, 80), "(vacío)")
theirOfferText.TextXAlignment = Enum.TextXAlignment.Left
theirOfferText.TextYAlignment = Enum.TextYAlignment.Top

local clearOfferButton = createButton(tradePanel, "ClearOfferButton", UDim2.new(0, 10, 0, 162), UDim2.new(0.45, 0, 0, 24), "Quitar mi oferta")

local lockStatusLabel = createLabel(tradePanel, "LockStatus", UDim2.new(0, 10, 0, 192), UDim2.new(1, -20, 0, 24), "")
lockStatusLabel.BackgroundTransparency = 1

local inventoryHeader = createLabel(tradePanel, "InventoryHeader", UDim2.new(0, 10, 0, 222), UDim2.new(1, -20, 0, 20), "Tu inventario (click para agregar 1)")
inventoryHeader.BackgroundTransparency = 1
inventoryHeader.TextXAlignment = Enum.TextXAlignment.Left

local inventoryList = Instance.new("ScrollingFrame")
inventoryList.Name = "InventoryList"
inventoryList.Position = UDim2.new(0, 10, 0, 246)
inventoryList.Size = UDim2.new(1, -20, 0, 80)
inventoryList.BackgroundTransparency = 1
inventoryList.CanvasSize = UDim2.new(0, 0, 0, 0)
inventoryList.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryList.ScrollBarThickness = 6
inventoryList.Parent = tradePanel

local inventoryLayout = Instance.new("UIListLayout")
inventoryLayout.Padding = UDim.new(0, 4)
inventoryLayout.Parent = inventoryList

local confirmButton = createButton(tradePanel, "ConfirmButton", UDim2.new(0, 10, 1, -50), UDim2.new(0.45, 0, 0, 40), "Listo")
local cancelButton = createButton(tradePanel, "CancelButton", UDim2.new(0.55, 0, 1, -50), UDim2.new(0.45, 0, 0, 40), "Cancelar")

local currentTradeId: string? = nil
local latestInventory: { [string]: number } = {}
local lastYourOffer: { [string]: number } = {}
local inventoryButtons: { [string]: TextButton } = {}

local function formatOffer(offer: { [string]: number }): string
	local parts = {}
	for itemId, qty in pairs(offer) do
		table.insert(parts, ("%s x%d"):format(itemId, qty))
	end
	if #parts == 0 then
		return "(vacío)"
	end
	return table.concat(parts, "\n")
end

local function rebuildInventoryButtons()
	for _, button in pairs(inventoryButtons) do
		button:Destroy()
	end
	table.clear(inventoryButtons)

	for itemId, qty in pairs(latestInventory) do
		if qty > 0 then
			local button = createButton(
				inventoryList,
				itemId,
				UDim2.new(0, 0, 0, 0),
				UDim2.new(1, 0, 0, 28),
				("%s (%d disponibles)"):format(itemId, qty)
			)
			button.MouseButton1Click:Connect(function()
				if currentTradeId then
					updateTradeOfferEvent:FireServer(currentTradeId, itemId, 1)
				end
			end)
			inventoryButtons[itemId] = button
		end
	end
end

confirmButton.MouseButton1Click:Connect(function()
	if currentTradeId then
		confirmTradeEvent:FireServer(currentTradeId)
	end
end)

cancelButton.MouseButton1Click:Connect(function()
	if currentTradeId then
		cancelTradeEvent:FireServer(currentTradeId)
	end
end)

clearOfferButton.MouseButton1Click:Connect(function()
	if not currentTradeId then
		return
	end
	for itemId, qty in pairs(lastYourOffer) do
		updateTradeOfferEvent:FireServer(currentTradeId, itemId, -qty)
	end
end)

local function closeTradePanel()
	tradePanel.Visible = false
	currentTradeId = nil
	lastYourOffer = {}
end

local function refreshInventorySnapshot()
	local ok, state = pcall(function()
		return getPlayerStateRemote:InvokeServer()
	end)

	if ok and state then
		latestInventory = state.Inventory
		if tradePanel.Visible then
			rebuildInventoryButtons()
		end
	end
end

task.spawn(function()
	while true do
		refreshInventorySnapshot()
		task.wait(INVENTORY_POLL_SECONDS)
	end
end)

tradeStateChangedEvent.OnClientEvent:Connect(function(payload)
	if payload.Kind == "Request" then
		pendingIncomingFromUserId = payload.FromUserId
		incomingLabel.Text = ("%s te invitó a tradear"):format(payload.FromName)
		incomingRequestFrame.Visible = true
	elseif payload.Kind == "Declined" then
		requestPending = false
		requestButton.Text = "Solicitud rechazada"
		task.delay(2, function()
			if requestButton.Text == "Solicitud rechazada" then
				requestButton.Text = ""
			end
		end)
	elseif payload.Kind == "Started" then
		requestPending = false
		currentTradeId = payload.TradeId
		titleLabel.Text = ("Trade con %s"):format(payload.OtherName)
		tradePanel.Visible = true
		rebuildInventoryButtons()
	elseif payload.Kind == "Updated" then
		if payload.TradeId == currentTradeId then
			lastYourOffer = payload.YourOffer
			yourOfferText.Text = formatOffer(payload.YourOffer)
			theirOfferText.Text = formatOffer(payload.TheirOffer)
			lockStatusLabel.Text = ("Vos: %s | El otro: %s"):format(
				payload.YourLocked and "Listo" or "Editando",
				payload.TheirLocked and "Listo" or "Editando"
			)
		end
	elseif payload.Kind == "Cancelled" or payload.Kind == "Completed" then
		if payload.TradeId == currentTradeId then
			closeTradePanel()
		end
	end
end)

print("[TradeUI] Sistema de trading inicializado.")
