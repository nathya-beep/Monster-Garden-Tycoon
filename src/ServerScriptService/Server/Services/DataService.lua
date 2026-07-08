-- DataService.lua
-- Único punto de verdad para los datos persistentes del jugador.
-- Los demás servicios deben leer/escribir a través de DataService.Get(player)
-- y DataService.Save(player) — nunca acceder al DataStore directamente.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

export type PlantedCrop = {
	SeedId: string,
	PlantedAt: number, -- os.time() en el momento de plantar; sobrevive a restarts del servidor
}

export type PlayerData = {
	Coins: number,
	Inventory: { [string]: number },
	Plots: { [number]: PlantedCrop }, -- slot index (1..N) -> cultivo plantado; slot ausente = vacío
}

local PLAYER_DATA_STORE_NAME = "PlayerData_v1"
local LOAD_RETRY_ATTEMPTS = 3
local SAVE_RETRY_ATTEMPTS = 3
local RETRY_BACKOFF_SECONDS = 2

-- GetDataStore() puede tirar error (no pcall-safe por sí solo) en lugares
-- sin publicar o sin "Enable Studio Access to API Services" activado. Sin
-- este pcall, ese error de configuración tumbaba todo Main.server.lua en
-- cascada (require de DataService fallando) y dejaba el juego entero sin
-- iniciar. Con esto, el juego sigue siendo jugable sin guardado persistente.
local playerDataStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(PLAYER_DATA_STORE_NAME)
	end)

	if ok then
		playerDataStore = result
	else
		warn(("[DataService] No se pudo acceder a DataStoreService (%s). Corriendo sin guardado persistente: publicá el lugar y activá 'Enable Studio Access to API Services' para probar el guardado real.")
			:format(tostring(result)))
	end
end

local DataService = {}

-- Caché en memoria: userId -> PlayerData.
local cache: { [number]: PlayerData } = {}

-- userId -> true si la carga inicial falló (sin poder confirmar si el
-- jugador tenía un save existente). Mientras esté marcado, se BLOQUEA el
-- guardado para no arriesgarse a sobrescribir progreso real con datos
-- por defecto o incompletos.
local loadFailed: { [number]: boolean } = {}

local function getDefaultData(): PlayerData
	return {
		Coins = Economy.STARTING_COINS,
		Inventory = { BasicSeed = 0 },
		Plots = {},
	}
end

-- Migra el esquema viejo (una sola parcela en data.Plot) al nuevo
-- (data.Plots, múltiples slots para soportar el gamepass ExtraPlotSlots).
-- Sin esto, los saves de antes de este cambio perderían su cultivo plantado.
local function migrateLegacyPlot(data: { [string]: any })
	if data.Plot ~= nil and data.Plots == nil then
		data.Plots = { [1] = data.Plot }
	end
	data.Plot = nil
end

-- Combina los datos guardados con la plantilla por defecto: si al jugador
-- le faltan campos nuevos (por una actualización del juego), se rellenan
-- sin pisar lo ya guardado. Recursivo para no perder campos anidados
-- (ej. Inventory) — un merge superficial fue un bug real en el proyecto anterior.
local function fillMissingFields(data: { [string]: any }, defaults: { [string]: any })
	for key, defaultValue in pairs(defaults) do
		if data[key] == nil then
			data[key] = defaultValue
		elseif type(defaultValue) == "table" and type(data[key]) == "table" then
			fillMissingFields(data[key], defaultValue)
		end
	end
	return data
end

-- Intenta cargar del DataStore con reintentos. Devuelve (data, ok):
-- ok = true y data = nil significa "jugador nuevo, sin save" (válido).
-- ok = false significa que no se pudo determinar el estado real.
local function loadFromDataStore(userId: number): (PlayerData?, boolean)
	if not playerDataStore then
		return nil, false
	end

	for attempt = 1, LOAD_RETRY_ATTEMPTS do
		local ok, result = pcall(function()
			return playerDataStore:GetAsync("Player_" .. userId)
		end)

		if ok then
			return result, true
		end

		warn(("[DataService] GetAsync falló (intento %d/%d) para %d: %s")
			:format(attempt, LOAD_RETRY_ATTEMPTS, userId, tostring(result)))

		if attempt < LOAD_RETRY_ATTEMPTS then
			task.wait(RETRY_BACKOFF_SECONDS)
		end
	end

	return nil, false
end

local function saveToDataStore(userId: number, data: PlayerData): boolean
	if not playerDataStore then
		return false
	end

	for attempt = 1, SAVE_RETRY_ATTEMPTS do
		local ok, err = pcall(function()
			playerDataStore:UpdateAsync("Player_" .. userId, function()
				return data
			end)
		end)

		if ok then
			return true
		end

		warn(("[DataService] UpdateAsync falló (intento %d/%d) para %d: %s")
			:format(attempt, SAVE_RETRY_ATTEMPTS, userId, tostring(err)))

		if attempt < SAVE_RETRY_ATTEMPTS then
			task.wait(RETRY_BACKOFF_SECONDS)
		end
	end

	return false
end

-- Carga los datos de un jugador y los deja disponibles en caché.
-- Se llama automáticamente en PlayerAdded; no debería necesitar llamarse
-- manualmente desde otros servicios.
function DataService.Load(player: Player): PlayerData
	local userId = player.UserId
	local savedData, loadedOk = loadFromDataStore(userId)

	if not loadedOk then
		loadFailed[userId] = true
		warn(("[DataService] No se pudo confirmar el save de %s; sesión temporal sin guardado para no arriesgar su progreso real.")
			:format(player.Name))
	else
		loadFailed[userId] = nil
	end

	local data = (savedData :: { [string]: any }?) or {}
	migrateLegacyPlot(data)
	fillMissingFields(data, getDefaultData())

	cache[userId] = data :: PlayerData
	return cache[userId]
end

-- Devuelve los datos en caché del jugador, o nil si todavía no cargaron.
function DataService.Get(player: Player): PlayerData?
	return cache[player.UserId]
end

-- Guarda los datos en caché del jugador. No hace nada (y devuelve false)
-- si la carga inicial falló o si el jugador no tiene datos cargados.
function DataService.Save(player: Player): boolean
	local userId = player.UserId

	if loadFailed[userId] then
		warn(("[DataService] Se omite el guardado de %s: su carga inicial falló.")
			:format(player.Name))
		return false
	end

	local data = cache[userId]
	if not data then
		return false
	end

	return saveToDataStore(userId, data)
end

function DataService.Init()
	Players.PlayerAdded:Connect(function(player)
		DataService.Load(player)

		-- Autoguardado periódico mientras el jugador sigue conectado.
		task.spawn(function()
			while player.Parent do
				task.wait(Economy.AUTOSAVE_INTERVAL_SECONDS)
				if not player.Parent then
					break
				end
				DataService.Save(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataService.Save(player)
		cache[player.UserId] = nil
		loadFailed[player.UserId] = nil
	end)

	-- Jugadores ya conectados al momento de correr Init (Play Solo en Studio).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			DataService.Load(player)
		end)
	end
end

return DataService
