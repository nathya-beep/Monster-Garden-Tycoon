-- MonetizationService.lua
-- Responsable de gamepasses y developer products.
-- - Gamepasses: cachea la propiedad (UserOwnsGamePassAsync) en memoria por
--   jugador; otros servicios consultan el efecto vía MonetizationService.HasGamePass.
-- - Developer products: se otorgan desde MarketplaceService.ProcessReceipt,
--   el único lugar seguro para acreditar una compra con dinero real.
-- Mientras un AssetId siga en 0 (no configurado en Shared.Config.Monetization),
-- ese pass/producto se ignora sin romper nada: permite programar los efectos
-- antes de tener los IDs reales de Studio/Creator Dashboard.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local EconomyService = require(script.Parent.EconomyService)

local OWNERSHIP_CHECK_ATTEMPTS = 3
local OWNERSHIP_RETRY_BACKOFF_SECONDS = 2

local MonetizationService = {}

-- userId -> { [gamePassKey]: boolean }
local ownershipCache: { [number]: { [string]: boolean } } = {}

local function isConfigured(assetId: number?): boolean
	return typeof(assetId) == "number" and assetId > 0
end

local function checkOwnership(userId: number, assetId: number): boolean
	for attempt = 1, OWNERSHIP_CHECK_ATTEMPTS do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, assetId)
		end)

		if ok then
			return owns
		end

		warn(("[MonetizationService] UserOwnsGamePassAsync falló (intento %d/%d) para %d/%d: %s")
			:format(attempt, OWNERSHIP_CHECK_ATTEMPTS, userId, assetId, tostring(owns)))

		if attempt < OWNERSHIP_CHECK_ATTEMPTS then
			task.wait(OWNERSHIP_RETRY_BACKOFF_SECONDS)
		end
	end

	return false
end

local function cacheOwnershipForPlayer(player: Player)
	local cache = {}
	for passKey, pass in pairs(Monetization.GamePasses) do
		cache[passKey] = isConfigured(pass.AssetId) and checkOwnership(player.UserId, pass.AssetId) or false
	end
	ownershipCache[player.UserId] = cache
end

-- ¿El jugador tiene el gamepass `passKey` (una clave de Monetization.GamePasses,
-- ej. "DoubleCoins")? Devuelve false si no lo tiene, si el pass no está
-- configurado todavía, o si su propiedad no se cacheó todavía (se resuelve
-- solo unos segundos después de que el jugador entra).
function MonetizationService.HasGamePass(player: Player, passKey: string): boolean
	local cache = ownershipCache[player.UserId]
	return cache ~= nil and cache[passKey] == true
end

local function findDeveloperProduct(productAssetId: number)
	for productKey, product in pairs(Monetization.DeveloperProducts) do
		if isConfigured(product.AssetId) and product.AssetId == productAssetId then
			return productKey, product
		end
	end
	return nil
end

local function handleProcessReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- El jugador ya no está: Roblox vuelve a llamar ProcessReceipt más
		-- tarde (incluso en otra sesión), así que es seguro no procesarlo ahora.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productKey, product = findDeveloperProduct(receiptInfo.ProductId)
	if not product then
		warn(("[MonetizationService] Recibo para ProductId desconocido: %d"):format(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if product.CoinAmount then
		EconomyService.AddCoins(player, product.CoinAmount)
	else
		warn(("[MonetizationService] %s no tiene efecto de compra implementado todavía."):format(productKey))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local ok, result = pcall(handleProcessReceipt, receiptInfo)
		if not ok then
			warn(("[MonetizationService] Error procesando recibo %s: %s")
				:format(tostring(receiptInfo.PurchaseId), tostring(result)))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return result
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end

		local cache = ownershipCache[player.UserId]
		if not cache then
			return
		end

		for passKey, pass in pairs(Monetization.GamePasses) do
			if pass.AssetId == gamePassId then
				cache[passKey] = true
				break
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(cacheOwnershipForPlayer, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		ownershipCache[player.UserId] = nil
	end)

	-- Jugadores ya conectados al momento de correr Init (Play Solo en Studio).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(cacheOwnershipForPlayer, player)
	end
end

return MonetizationService
