-- Sounds.lua
-- IDs de sonido para feedback de acciones del jugador. AssetId = 0 significa
-- "todavía no configurado" (mismo patrón que Config/Monetization.lua): el
-- cliente lo ignora sin romper nada hasta que se reemplace por un ID real
-- subido al Creator Dashboard.

local Sounds = {}

Sounds.BuySeed = { AssetId = 0 }
Sounds.PlantSeed = { AssetId = 0 }
Sounds.HarvestSuccess = { AssetId = 0 }
Sounds.ActionError = { AssetId = 0 }

return Sounds
