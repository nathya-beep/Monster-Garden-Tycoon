# Player-to-Player Trading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar trading de ítems de inventario entre dos jugadores, iniciado por proximidad, con confirmación de doble lock y cancelación automática, según `docs/superpowers/specs/2026-07-08-player-trading-design.md`.

**Architecture:** `TradeService.lua` nuevo (servidor) es la única fuente de verdad del estado de cada trade activo (en memoria). Se comunica con el cliente vía 5 `RemoteEvent`s cliente→servidor (`RequestTrade`, `RespondTradeRequest`, `UpdateTradeOffer`, `ConfirmTrade`, `CancelTrade`) y 1 `RemoteEvent` servidor→cliente (`TradeStateChanged`) que notifica todo (solicitudes, actualizaciones de oferta, cancelación, ejecución) con un payload `{Kind, ...}`. Un archivo cliente nuevo (`TradeUI.client.lua`) maneja toda la UI de trading, separado de `Client.client.lua`.

**Tech Stack:** Luau, Rojo 7.6.1, Roblox Studio (RemoteEvent, HttpService:GenerateGUID).

## Global Constraints

- Solo ítems de inventario en el trade (sin coins) — ver spec, sección "Alcance".
- Validación 100% server-side; nunca confiar en el estado que reporta el cliente (regla del proyecto en `CLAUDE.md`).
- Rango para solicitar trade: 10 studs (`TRADE_RANGE_STUDS`). Rango de cancelación automática: 15 studs (`CANCEL_RANGE_STUDS`). Valores exactos de la spec, sección 2 y 5.
- Chequeo periódico de distancia: cada 2 segundos (`DISTANCE_CHECK_INTERVAL_SECONDS`), igual que `AUTO_COLLECT_INTERVAL_SECONDS` de `GrowthService`.
- Cualquier cambio a una oferta resetea ambos locks a `false` (invariante de la spec, sección 1).
- `default.project.json` no recarga en caliente — no aplica a esta tarea (no toca ese archivo). Los `.lua` bajo `src/` sí sincronizan en caliente.
- Verificar sincronización de cada archivo con `curl -s http://localhost:34872/api/read/<rootInstanceId>` (obtener `rootInstanceId` con `curl -s http://localhost:34872/api/rojo`) antes de pasar a la siguiente tarea — no hay testing automatizado para Luau en este proyecto.

---

### Task 1: RemoteEvents de trading (`Remotes.lua`)

**Files:**
- Modify: `src/ReplicatedStorage/Shared/Remotes.lua`

**Interfaces:**
- Consumes: nada de tareas anteriores.
- Produces: `Remotes.GetRequestTradeEvent()`, `Remotes.GetRespondTradeRequestEvent()`, `Remotes.GetUpdateTradeOfferEvent()`, `Remotes.GetConfirmTradeEvent()`, `Remotes.GetCancelTradeEvent()`, `Remotes.GetTradeStateChangedEvent()`, todas devuelven `RemoteEvent`. Consumidas por `TradeService.lua` (Tarea 2) y `TradeUI.client.lua` (Tarea 3).

- [ ] **Step 1: Agregar el helper `getOrCreateRemoteEvent` junto al existente `getOrCreateRemoteFunction`**

En `src/ReplicatedStorage/Shared/Remotes.lua`, después de la función `getOrCreateRemoteFunction` (antes de `function Remotes.GetBuySeedRemote()`), agregar:

```lua
-- Devuelve el RemoteEvent dado, creándolo si corre en el servidor y
-- esperándolo (WaitForChild) si corre en el cliente. Mismo patrón que
-- getOrCreateRemoteFunction, pero para RemoteEvent (necesario para que el
-- servidor pueda empujar actualizaciones al cliente sin que este las pida).
local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local folder = getOrCreateFolder()
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing :: RemoteEvent
	end

	if RunService:IsServer() then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name) :: RemoteEvent
end
```

- [ ] **Step 2: Agregar los 6 getters de trading al final del archivo, antes de `return Remotes`**

```lua
function Remotes.GetRequestTradeEvent(): RemoteEvent
	return getOrCreateRemoteEvent("RequestTrade")
end

function Remotes.GetRespondTradeRequestEvent(): RemoteEvent
	return getOrCreateRemoteEvent("RespondTradeRequest")
end

function Remotes.GetUpdateTradeOfferEvent(): RemoteEvent
	return getOrCreateRemoteEvent("UpdateTradeOffer")
end

function Remotes.GetConfirmTradeEvent(): RemoteEvent
	return getOrCreateRemoteEvent("ConfirmTrade")
end

function Remotes.GetCancelTradeEvent(): RemoteEvent
	return getOrCreateRemoteEvent("CancelTrade")
end

function Remotes.GetTradeStateChangedEvent(): RemoteEvent
	return getOrCreateRemoteEvent("TradeStateChanged")
end
```

- [ ] **Step 3: Confirmar vía la API de Rojo que el archivo sincronizó**

Run: `curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o "GetTradeStateChangedEvent"`
Expected: aparece la línea.

- [ ] **Step 4: Commit**

```bash
git add src/ReplicatedStorage/Shared/Remotes.lua
git commit -m "feat: add trading RemoteEvents"
```

---

### Task 2: `TradeService.lua` + wiring en `Main.server.lua`

**Files:**
- Create: `src/ServerScriptService/Server/Services/TradeService.lua`
- Modify: `src/ServerScriptService/Server/Main.server.lua`

**Interfaces:**
- Consumes: `Remotes.GetRequestTradeEvent()` etc. (Tarea 1); `InventoryService.GetCount(player, itemId): number`, `InventoryService.HasItem(player, itemId, amount): boolean`, `InventoryService.AddItem(player, itemId, amount): boolean`, `InventoryService.RemoveItem(player, itemId, amount): boolean` (ya existen en `src/ServerScriptService/Server/Services/InventoryService.lua`).
- Produces: `TradeService.Init()`. Payload de `TradeStateChangedEvent` con forma `{Kind: string, TradeId: string?, FromUserId: number?, FromName: string?, OtherUserId: number?, OtherName: string?, YourOffer: {[string]: number}?, TheirOffer: {[string]: number}?, YourLocked: boolean?, TheirLocked: boolean?, ByUserId: number?, Reason: string?}` — `Kind` es uno de `"Request" | "Declined" | "Started" | "Updated" | "Cancelled" | "Completed"`. Tarea 3 (`TradeUI.client.lua`) consume este payload por `Kind` y estos nombres de campo exactos.

- [ ] **Step 1: Crear `src/ServerScriptService/Server/Services/TradeService.lua`**

```lua
-- TradeService.lua
-- Único punto de verdad del estado de los trades activos entre jugadores.
-- Todo cambio de oferta resetea ambos locks: evita que un jugador confirme
-- y el otro cambie la oferta después sin que la confirmación se re-valide.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local InventoryService = require(script.Parent.InventoryService)

export type TradeState = {
	TradeId: string,
	PlayerA: Player,
	PlayerB: Player,
	OfferA: { [string]: number },
	OfferB: { [string]: number },
	LockedA: boolean,
	LockedB: boolean,
	CreatedAt: number,
}

local TRADE_RANGE_STUDS = 10
local CANCEL_RANGE_STUDS = 15
local DISTANCE_CHECK_INTERVAL_SECONDS = 2

local TradeService = {}

-- tradeId -> TradeState
local activeTrades: { [string]: TradeState } = {}
-- userId -> tradeId (para lookup rápido y bloquear trades duplicados)
local playerTradeId: { [number]: string } = {}
-- targetUserId -> requesterUserId (solo la solicitud entrante más reciente)
local pendingRequestFrom: { [number]: number } = {}

local function getDistance(playerA: Player, playerB: Player): number?
	local rootA = playerA.Character and playerA.Character:FindFirstChild("HumanoidRootPart")
	local rootB = playerB.Character and playerB.Character:FindFirstChild("HumanoidRootPart")
	if not rootA or not rootB then
		return nil
	end
	return ((rootA :: BasePart).Position - (rootB :: BasePart).Position).Magnitude
end

local function fireTradeStateChanged(player: Player, payload: { [string]: any })
	Remotes.GetTradeStateChangedEvent():FireClient(player, payload)
end

-- Arma el payload "Updated" desde la perspectiva de `forPlayer`, para que el
-- cliente nunca necesite saber si es "A" o "B" — siempre ve Your*/Their*.
local function buildUpdatedPayload(trade: TradeState, forPlayer: Player): { [string]: any }
	local isA = trade.PlayerA == forPlayer
	return {
		Kind = "Updated",
		TradeId = trade.TradeId,
		YourOffer = isA and trade.OfferA or trade.OfferB,
		TheirOffer = isA and trade.OfferB or trade.OfferA,
		YourLocked = isA and trade.LockedA or trade.LockedB,
		TheirLocked = isA and trade.LockedB or trade.LockedA,
	}
end

local function broadcastUpdate(trade: TradeState)
	fireTradeStateChanged(trade.PlayerA, buildUpdatedPayload(trade, trade.PlayerA))
	fireTradeStateChanged(trade.PlayerB, buildUpdatedPayload(trade, trade.PlayerB))
end

local function cleanupTrade(trade: TradeState, kind: string, reason: string?)
	activeTrades[trade.TradeId] = nil
	playerTradeId[trade.PlayerA.UserId] = nil
	playerTradeId[trade.PlayerB.UserId] = nil

	fireTradeStateChanged(trade.PlayerA, { Kind = kind, TradeId = trade.TradeId, Reason = reason })
	fireTradeStateChanged(trade.PlayerB, { Kind = kind, TradeId = trade.TradeId, Reason = reason })
end

local function cancelTrade(trade: TradeState, reason: string)
	cleanupTrade(trade, "Cancelled", reason)
end

local function handleRequestTrade(player: Player, targetUserId: number)
	if typeof(targetUserId) ~= "number" then
		return
	end
	if playerTradeId[player.UserId] then
		return
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	if playerTradeId[target.UserId] then
		return
	end

	local distance = getDistance(player, target)
	if not distance or distance > TRADE_RANGE_STUDS then
		return
	end

	pendingRequestFrom[target.UserId] = player.UserId
	fireTradeStateChanged(target, { Kind = "Request", FromUserId = player.UserId, FromName = player.Name })
end

local function handleRespondTradeRequest(player: Player, fromUserId: number, accepted: boolean)
	if typeof(fromUserId) ~= "number" or typeof(accepted) ~= "boolean" then
		return
	end
	if pendingRequestFrom[player.UserId] ~= fromUserId then
		return
	end
	pendingRequestFrom[player.UserId] = nil

	local requester = Players:GetPlayerByUserId(fromUserId)
	if not requester then
		return
	end

	if not accepted then
		fireTradeStateChanged(requester, { Kind = "Declined", ByUserId = player.UserId })
		return
	end

	if playerTradeId[player.UserId] or playerTradeId[requester.UserId] then
		return
	end

	local distance = getDistance(player, requester)
	if not distance or distance > TRADE_RANGE_STUDS then
		fireTradeStateChanged(requester, { Kind = "Declined", ByUserId = player.UserId })
		return
	end

	local tradeId = HttpService:GenerateGUID(false)
	local trade: TradeState = {
		TradeId = tradeId,
		PlayerA = requester,
		PlayerB = player,
		OfferA = {},
		OfferB = {},
		LockedA = false,
		LockedB = false,
		CreatedAt = os.time(),
	}
	activeTrades[tradeId] = trade
	playerTradeId[requester.UserId] = tradeId
	playerTradeId[player.UserId] = tradeId

	fireTradeStateChanged(requester, { Kind = "Started", TradeId = tradeId, OtherUserId = player.UserId, OtherName = player.Name })
	fireTradeStateChanged(player, { Kind = "Started", TradeId = tradeId, OtherUserId = requester.UserId, OtherName = requester.Name })
	broadcastUpdate(trade)
end

local function getTradeForPlayer(player: Player, tradeId: string): TradeState?
	local trade = activeTrades[tradeId]
	if not trade then
		return nil
	end
	if trade.PlayerA ~= player and trade.PlayerB ~= player then
		return nil
	end
	return trade
end

local function handleUpdateTradeOffer(player: Player, tradeId: string, itemId: string, delta: number)
	if typeof(tradeId) ~= "string" or typeof(itemId) ~= "string" or typeof(delta) ~= "number" then
		return
	end

	local trade = getTradeForPlayer(player, tradeId)
	if not trade then
		return
	end

	local isA = trade.PlayerA == player
	local offer = isA and trade.OfferA or trade.OfferB
	local newQty = (offer[itemId] or 0) + delta

	if newQty < 0 then
		return
	end
	if newQty > 0 and newQty > InventoryService.GetCount(player, itemId) then
		return
	end

	if newQty == 0 then
		offer[itemId] = nil
	else
		offer[itemId] = newQty
	end

	trade.LockedA = false
	trade.LockedB = false
	broadcastUpdate(trade)
end

-- Revalida todo antes de mover cualquier ítem: nunca ejecuta parcialmente.
local function executeTrade(trade: TradeState): boolean
	for itemId, qty in pairs(trade.OfferA) do
		if not InventoryService.HasItem(trade.PlayerA, itemId, qty) then
			return false
		end
	end
	for itemId, qty in pairs(trade.OfferB) do
		if not InventoryService.HasItem(trade.PlayerB, itemId, qty) then
			return false
		end
	end

	for itemId, qty in pairs(trade.OfferA) do
		InventoryService.RemoveItem(trade.PlayerA, itemId, qty)
		InventoryService.AddItem(trade.PlayerB, itemId, qty)
	end
	for itemId, qty in pairs(trade.OfferB) do
		InventoryService.RemoveItem(trade.PlayerB, itemId, qty)
		InventoryService.AddItem(trade.PlayerA, itemId, qty)
	end

	return true
end

local function handleConfirmTrade(player: Player, tradeId: string)
	if typeof(tradeId) ~= "string" then
		return
	end

	local trade = getTradeForPlayer(player, tradeId)
	if not trade then
		return
	end

	if trade.PlayerA == player then
		trade.LockedA = true
	else
		trade.LockedB = true
	end

	if trade.LockedA and trade.LockedB then
		local success = executeTrade(trade)
		cleanupTrade(trade, success and "Completed" or "Cancelled", success and nil or "InventoryChanged")
	else
		broadcastUpdate(trade)
	end
end

local function handleCancelTrade(player: Player, tradeId: string)
	if typeof(tradeId) ~= "string" then
		return
	end

	local trade = getTradeForPlayer(player, tradeId)
	if not trade then
		return
	end

	cancelTrade(trade, "PlayerCancelled")
end

function TradeService.Init()
	local requestTradeEvent = Remotes.GetRequestTradeEvent()
	local respondTradeRequestEvent = Remotes.GetRespondTradeRequestEvent()
	local updateTradeOfferEvent = Remotes.GetUpdateTradeOfferEvent()
	local confirmTradeEvent = Remotes.GetConfirmTradeEvent()
	local cancelTradeEvent = Remotes.GetCancelTradeEvent()

	requestTradeEvent.OnServerEvent:Connect(function(player, targetUserId)
		local ok, err = pcall(handleRequestTrade, player, targetUserId)
		if not ok then
			warn(("[TradeService] Error en RequestTrade de %s: %s"):format(player.Name, tostring(err)))
		end
	end)

	respondTradeRequestEvent.OnServerEvent:Connect(function(player, fromUserId, accepted)
		local ok, err = pcall(handleRespondTradeRequest, player, fromUserId, accepted)
		if not ok then
			warn(("[TradeService] Error en RespondTradeRequest de %s: %s"):format(player.Name, tostring(err)))
		end
	end)

	updateTradeOfferEvent.OnServerEvent:Connect(function(player, tradeId, itemId, delta)
		local ok, err = pcall(handleUpdateTradeOffer, player, tradeId, itemId, delta)
		if not ok then
			warn(("[TradeService] Error en UpdateTradeOffer de %s: %s"):format(player.Name, tostring(err)))
		end
	end)

	confirmTradeEvent.OnServerEvent:Connect(function(player, tradeId)
		local ok, err = pcall(handleConfirmTrade, player, tradeId)
		if not ok then
			warn(("[TradeService] Error en ConfirmTrade de %s: %s"):format(player.Name, tostring(err)))
		end
	end)

	cancelTradeEvent.OnServerEvent:Connect(function(player, tradeId)
		local ok, err = pcall(handleCancelTrade, player, tradeId)
		if not ok then
			warn(("[TradeService] Error en CancelTrade de %s: %s"):format(player.Name, tostring(err)))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingRequestFrom[player.UserId] = nil

		local tradeId = playerTradeId[player.UserId]
		if tradeId then
			local trade = activeTrades[tradeId]
			if trade then
				cancelTrade(trade, "PlayerLeft")
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(DISTANCE_CHECK_INTERVAL_SECONDS)
			for _, trade in pairs(activeTrades) do
				local distance = getDistance(trade.PlayerA, trade.PlayerB)
				if not distance or distance > CANCEL_RANGE_STUDS then
					cancelTrade(trade, "TooFar")
				end
			end
		end
	end)
end

return TradeService
```

- [ ] **Step 2: Cablear `TradeService` en `Main.server.lua`**

En `src/ServerScriptService/Server/Main.server.lua`, reemplazar:

```lua
local DataService = require(Services.DataService)
local PlotService = require(Services.PlotService)
local GrowthService = require(Services.GrowthService)
local EconomyService = require(Services.EconomyService)
local InventoryService = require(Services.InventoryService)
local MonetizationService = require(Services.MonetizationService)
local AdminService = require(Services.AdminService)

print("[Main] Monster Garden Tycoon iniciando...")

DataService.Init()
PlotService.Init()
GrowthService.Init()
EconomyService.Init()
InventoryService.Init()
MonetizationService.Init()
AdminService.Init()
```

por:

```lua
local DataService = require(Services.DataService)
local PlotService = require(Services.PlotService)
local GrowthService = require(Services.GrowthService)
local EconomyService = require(Services.EconomyService)
local InventoryService = require(Services.InventoryService)
local TradeService = require(Services.TradeService)
local MonetizationService = require(Services.MonetizationService)
local AdminService = require(Services.AdminService)

print("[Main] Monster Garden Tycoon iniciando...")

DataService.Init()
PlotService.Init()
GrowthService.Init()
EconomyService.Init()
InventoryService.Init()
TradeService.Init()
MonetizationService.Init()
AdminService.Init()
```

- [ ] **Step 3: Confirmar vía la API de Rojo que ambos archivos sincronizaron**

Run: `curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o "TradeService.Init\|handleConfirmTrade"`
Expected: ambas líneas aparecen.

- [ ] **Step 4: Commit**

```bash
git add src/ServerScriptService/Server/Services/TradeService.lua src/ServerScriptService/Server/Main.server.lua
git commit -m "feat: add TradeService with proximity trading and double-lock confirmation"
```

---

### Task 3: UI de trading (`TradeUI.client.lua`)

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/TradeUI.client.lua`

**Interfaces:**
- Consumes: los 6 Remotes de la Tarea 1; el payload `TradeStateChanged` documentado en la Tarea 2; `Remotes.GetPlayerStateRemote()` (ya existe, usado también por `Client.client.lua`) para obtener `state.Inventory: {[string]: number}`; `ReplicatedStorage.Shared.UI.Theme` (ya existe, del pulido del MVP) para `Theme.Colors`, `Theme.CornerRadius`.
- Produces: nada que otras tareas consuman — es un LocalScript hoja, Roblox lo ejecuta automáticamente por estar en `StarterPlayerScripts`.

- [ ] **Step 1: Crear `src/StarterPlayer/StarterPlayerScripts/TradeUI.client.lua`**

```lua
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
```

- [ ] **Step 2: Confirmar vía la API de Rojo que el archivo sincronizó**

Run: `curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o "TradeUI"`
Expected: aparece al menos una línea.

- [ ] **Step 3: Commit**

```bash
git add src/StarterPlayer/StarterPlayerScripts/TradeUI.client.lua
git commit -m "feat: add player trading UI (proximity request, offer panel, double lock)"
```

---

### Task 4: Verificación manual con 2 jugadores en Studio

**Files:** ninguno (solo verificación).

**Interfaces:**
- Consumes: todo lo de las Tareas 1-3.
- Produces: confirmación de que el trading funciona de punta a punta sin romper el resto del juego.

- [ ] **Step 1: Reconectar Rojo y dar Play con 2 clientes**

En Studio: reconectar el plugin de Rojo (Disconnect → Connect). Usar el dropdown de Play junto al botón Play para elegir "Play - 2 Players" (o similar, según versión de Studio) para tener dos personajes controlables en la misma sesión.

- [ ] **Step 2: Confirmar en el Output que ambos clientes arrancan sin errores**

Esperado (sin líneas en rojo): `[Main] ... iniciando...`, `[Main] Todos los servicios inicializados.`, y un `[Client]`/`[TradeUI]` por cada cliente.

- [ ] **Step 3: Comprar semillas con ambos jugadores**

Cada jugador compra al menos 2-3 `BasicSeed` desde el panel de Tienda existente, para tener algo que ofrecer en el trade.

- [ ] **Step 4: Acercar a los dos jugadores y solicitar trade**

Caminar a uno hacia el otro hasta quedar a menos de 10 studs. Debe aparecer el botón "Solicitar Trade a `<Nombre>`" en la parte inferior de la pantalla del jugador que se acerca. Click en el botón.

- [ ] **Step 5: Aceptar la solicitud**

En el otro cliente, debe aparecer el panel de solicitud entrante arriba de la pantalla. Click en "Aceptar". Ambos clientes deben mostrar el panel de trade con el título "Trade con `<Nombre>`".

- [ ] **Step 6: Agregar y quitar ítems de la oferta**

En un cliente, click en el ítem del inventario (ej. "BasicSeed (3 disponibles)") un par de veces — el texto "Tu oferta" debe actualizarse en ambos clientes (el propio como "Tu oferta", el otro como "Su oferta"). Click en "Quitar mi oferta" y confirmar que vuelve a "(vacío)" en ambos lados.

- [ ] **Step 7: Confirmar con doble lock**

Agregar ítems de nuevo en ambos clientes. Click en "Listo" en un cliente — el texto de estado debe decir "Vos: Listo | El otro: Editando" (o equivalente) en ese cliente. Click en "Listo" en el otro cliente — el panel debe cerrarse en ambos (trade ejecutado). Verificar que los inventarios se intercambiaron correctamente (recomprar semillas o revisar el conteo mostrado la próxima vez que se abra un trade).

- [ ] **Step 8: Confirmar que cambiar la oferta resetea el lock del otro**

Repetir un trade: un jugador da "Listo", el otro agrega un ítem más a su oferta. El estado de "Listo" del primero debe resetearse a "Editando" (visible en el texto de estado de ambos clientes).

- [ ] **Step 9: Confirmar cancelación por distancia**

Con un trade activo y sin confirmar, alejar a los dos jugadores más de 15 studs. Dentro de los 2 segundos siguientes, el panel debe cerrarse solo en ambos clientes (cancelación automática). Confirmar que ningún ítem se transfirió (los inventarios quedan igual que antes del intercambio).

- [ ] **Step 10: Commit final (si hubo ajustes por bugs encontrados)**

Solo si algún paso anterior reveló un bug real que requirió tocar código:

```bash
git add -A
git commit -m "fix: address issues found during trading verification"
```
