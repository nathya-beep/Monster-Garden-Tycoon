-- AdminService.lua
-- Comandos de prueba por chat. En Studio (Play Solo / Team Test) cualquier
-- jugador puede usarlos. Fuera de Studio, solo los UserIds de la whitelist
-- en Config/Admins.lua pueden ejecutarlos.
--
-- Comandos:
--   !coins <cantidad>               -> suma coins
--   !seed <cantidad>                -> suma BasicSeed al inventario
--   !seed <seedId> <cantidad>       -> suma la semilla indicada (BasicSeed | UncommonSeed)
--   !reset                          -> vuelve Coins/Inventory/Plots/Monsters a los valores por defecto

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ReplicatedStorage.Shared.Config.Admins)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)

local AdminService = {}

local function parseAmount(argument: string?): number?
	local amount = argument and tonumber(argument)
	if not amount or amount <= 0 then
		return nil
	end
	return amount
end

local function handleCoinsCommand(player: Player, argument: string?)
	local amount = parseAmount(argument)
	if not amount then
		warn(("[AdminService] Uso: !coins <cantidad positiva> (%s)"):format(player.Name))
		return
	end

	EconomyService.AddCoins(player, amount)
end

local VALID_SEED_IDS = { BasicSeed = true, UncommonSeed = true }

local function handleSeedCommand(player: Player, argument: string?)
	if not DataService.Get(player) then
		warn(("[AdminService] Datos de %s todavía no cargaron."):format(player.Name))
		return
	end

	local seedId, amountText = (argument or ""):match("^(%a+)%s+(%d+)$")
	if not seedId then
		-- Uso corto "!seed <cantidad>": siempre BasicSeed.
		seedId = "BasicSeed"
		amountText = argument
	end

	local amount = parseAmount(amountText)
	if not amount or not VALID_SEED_IDS[seedId] then
		warn(("[AdminService] Uso: !seed [BasicSeed|UncommonSeed] <cantidad positiva> (%s)"):format(player.Name))
		return
	end

	InventoryService.AddItem(player, seedId, amount)
end

local function handleResetCommand(player: Player)
	local data = DataService.Get(player)
	if not data then
		warn(("[AdminService] Datos de %s todavía no cargaron."):format(player.Name))
		return
	end

	data.Coins = Economy.STARTING_COINS
	data.Inventory = { BasicSeed = 0 }
	data.Plots = {}
	data.Monsters = {}
end

local function isAuthorized(player: Player): boolean
	return RunService:IsStudio() or Admins.IsAdmin(player.UserId)
end

local function onPlayerChatted(player: Player, message: string)
	local command, argument = message:match("^!(%a+)%s*(.*)$")
	if not command then
		return
	end

	if not isAuthorized(player) then
		return
	end

	if command == "coins" then
		handleCoinsCommand(player, argument)
	elseif command == "seed" then
		handleSeedCommand(player, argument)
	elseif command == "reset" then
		handleResetCommand(player)
	end
end

function AdminService.Init()
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			onPlayerChatted(player, message)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.Chatted:Connect(function(message)
			onPlayerChatted(player, message)
		end)
	end

	print("[AdminService] Comandos admin activos (Studio: todos | producción: whitelist en Config/Admins.lua).")
end

return AdminService
