-- Remotes.lua
-- Punto único para crear (servidor) u obtener (cliente) los RemoteEvents/
-- RemoteFunctions del juego. Evita que cada servicio invente su propia
-- convención de nombres/ubicación para comunicarse con el cliente.

local RunService = game:GetService("RunService")

local REMOTES_FOLDER_NAME = "Remotes"

local Remotes = {}

local function getOrCreateFolder(): Folder
	local existing = script.Parent:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing then
		return existing :: Folder
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER_NAME
		folder.Parent = script.Parent
		return folder
	end

	return script.Parent:WaitForChild(REMOTES_FOLDER_NAME) :: Folder
end

-- Devuelve el RemoteFunction dado, creándolo si corre en el servidor y
-- esperándolo (WaitForChild) si corre en el cliente.
local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local folder = getOrCreateFolder()
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing :: RemoteFunction
	end

	if RunService:IsServer() then
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name) :: RemoteFunction
end

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

function Remotes.GetBuySeedRemote(): RemoteFunction
	return getOrCreateRemoteFunction("BuySeed")
end

function Remotes.GetPlantSeedRemote(): RemoteFunction
	return getOrCreateRemoteFunction("PlantSeed")
end

function Remotes.GetHarvestRemote(): RemoteFunction
	return getOrCreateRemoteFunction("Harvest")
end

function Remotes.GetPlayerStateRemote(): RemoteFunction
	return getOrCreateRemoteFunction("GetPlayerState")
end

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

return Remotes
