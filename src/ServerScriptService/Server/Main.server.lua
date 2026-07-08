-- Main.server.lua
-- Punto de entrada del servidor. Inicializa todos los servicios en orden.
-- Orden: DataService primero (los demás servicios dependerán de los datos del jugador).

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

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

print("[Main] Todos los servicios inicializados.")
