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
