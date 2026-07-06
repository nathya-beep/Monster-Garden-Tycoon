-- InventoryService.lua
-- Único punto de verdad para leer/modificar el inventario de ítems del
-- jugador (semillas y, a futuro, cualquier otro ítem no plantado).
-- Los demás servicios nunca deben tocar data.Inventory directamente.
-- No conoce Crops/Creatures/precios: sólo maneja cantidades por itemId.

local DataService = require(script.Parent.DataService)

local InventoryService = {}

-- Cantidad de itemId que tiene el jugador (0 si no tiene o si sus datos
-- todavía no cargaron).
function InventoryService.GetCount(player: Player, itemId: string): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end

	return data.Inventory[itemId] or 0
end

function InventoryService.HasItem(player: Player, itemId: string, amount: number?): boolean
	return InventoryService.GetCount(player, itemId) >= (amount or 1)
end

-- Devuelve una copia del inventario completo (itemId -> cantidad), o una
-- tabla vacía si los datos todavía no cargaron. Es una copia para que quien
-- la reciba (ej. la UI) no pueda mutar el estado real por accidente.
function InventoryService.GetSnapshot(player: Player): { [string]: number }
	local data = DataService.Get(player)
	if not data then
		return {}
	end

	local snapshot = {}
	for itemId, count in pairs(data.Inventory) do
		snapshot[itemId] = count
	end
	return snapshot
end

-- Suma `amount` unidades de itemId. Falla (sin sumar nada) si los datos no
-- cargaron o si amount no es un número positivo.
function InventoryService.AddItem(player: Player, itemId: string, amount: number): boolean
	if type(amount) ~= "number" or amount <= 0 then
		return false
	end

	local data = DataService.Get(player)
	if not data then
		warn(("[InventoryService] No se pudo agregar %s a %s: datos no cargados."):format(itemId, player.Name))
		return false
	end

	data.Inventory[itemId] = (data.Inventory[itemId] or 0) + amount
	return true
end

-- Resta `amount` unidades de itemId. Falla (sin restar nada) si no le
-- alcanzan, si los datos no cargaron, o si amount no es un número positivo.
function InventoryService.RemoveItem(player: Player, itemId: string, amount: number): boolean
	if type(amount) ~= "number" or amount <= 0 then
		return false
	end

	local data = DataService.Get(player)
	if not data or (data.Inventory[itemId] or 0) < amount then
		return false
	end

	data.Inventory[itemId] -= amount
	return true
end

function InventoryService.Init()
	-- Sin estado propio que inicializar: todo vive en DataService.
end

return InventoryService
