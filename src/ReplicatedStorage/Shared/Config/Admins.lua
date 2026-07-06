-- Admins.lua
-- Whitelist de UserIds autorizados a usar los comandos admin (!coins, !seed,
-- !reset) fuera de Studio. En Studio los comandos siguen disponibles para
-- cualquier jugador, sin importar esta lista.

local Admins = {}

-- Agregá acá los UserId de Roblox de las cuentas admin de producción.
Admins.UserIds = {
	-- 123456789,
}

function Admins.IsAdmin(userId: number): boolean
	for _, adminId in ipairs(Admins.UserIds) do
		if adminId == userId then
			return true
		end
	end
	return false
end

return Admins
