-- AdminService.lua
-- Comandos de prueba por chat, SOLO disponibles en Studio (Play Solo /
-- Team Test). Nunca se conectan en un servidor real, así que no hace
-- falta validar permisos de "quién puede usarlos": no existen en producción.
--
-- Comandos:
--   !coins <cantidad>  -> suma coins
--   !seed <cantidad>   -> suma BasicSeed al inventario
--   !reset             -> vuelve Coins/Inventory/Plot a los valores por defecto

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function handleSeedCommand(player: Player, argument: string?)
	local amount = parseAmount(argument)
	if not amount then
		warn(("[AdminService] Uso: !seed <cantidad positiva> (%s)"):format(player.Name))
		return
	end

	if not DataService.Get(player) then
		warn(("[AdminService] Datos de %s todavía no cargaron."):format(player.Name))
		return
	end

	InventoryService.AddItem(player, "BasicSeed", amount)
end

local function handleResetCommand(player: Player)
	local data = DataService.Get(player)
	if not data then
		warn(("[AdminService] Datos de %s todavía no cargaron."):format(player.Name))
		return
	end

	data.Coins = Economy.STARTING_COINS
	data.Inventory = { BasicSeed = 0 }
	data.Plot = nil
end

local function onPlayerChatted(player: Player, message: string)
	local command, argument = message:match("^!(%a+)%s*(.*)$")
	if not command then
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
	if not RunService:IsStudio() then
		return
	end

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

	print("[AdminService] Comandos admin de Studio activos (!coins, !seed, !reset).")
end

return AdminService
