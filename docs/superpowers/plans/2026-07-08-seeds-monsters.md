# Sistema de Semillas y Monstruos (ciclo 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar el sistema de cosecha de solo-coins por uno que además otorga un monstruo real (guardado en los datos del jugador), con dos semillas jugables (Común/Poco Común) y sus tablas de probabilidad.

**Architecture:** `Seeds.lua` (reemplaza `Crops.lua`) y `Monsters.lua` (nuevo) son configs puras en `ReplicatedStorage/Shared/Config`. `MonsterService` (nuevo, server-only) resuelve el roll de probabilidad y guarda instancias en `DataService.PlayerData.Monsters`. `GrowthService.handleHarvest` pasa a llamar `MonsterService` después de acreditar coins, sin bloquear la cosecha si el roll falla.

**Tech Stack:** Roblox Luau, Rojo (sync `src/` ↔ Studio), sin framework de tests automatizado — la verificación es manual vía Roblox Studio y el MCP `robloxstudio-mcp` (`execute_luau` contra el servidor en vivo).

## Global Constraints

- Server-authoritative: toda economía/inventario/monstruo se resuelve en el servidor, nunca se confía en el cliente (regla de `CLAUDE.md`).
- No hardcodear item IDs, precios, timers o tasas de rareza dentro de la lógica de servicio — todo vive en `Config/*.lua` (regla de `CLAUDE.md`).
- Un roll de monstruo fallido (config corrupta/vacía) nunca debe bloquear ni revertir una cosecha ya exitosa — solo loguea `warn`.
- Alcance de este ciclo: únicamente rarezas Común y Poco Común (`BasicSeed`, `UncommonSeed`). Nada de UI, venta de monstruos, ni rarezas superiores — quedan para ciclos futuros.

---

### Task 1: `Monsters.lua` — registro de definiciones de monstruo

**Files:**
- Create: `src/ReplicatedStorage/Shared/Config/Monsters.lua`

**Interfaces:**
- Produces: `Monsters: { [string]: MonsterDefinition }` donde `MonsterDefinition = { Id: string, Name: string, Rarity: string, SellValue: number }`. Consumido por `MonsterService` (Task 4).

- [ ] **Step 1: Crear el archivo de config**

```lua
-- Monsters.lua
-- Registro de definiciones de monstruo. Independiente de Seeds.lua para que
-- objetos rompibles u otras semillas (ciclos futuros) puedan referenciar
-- los mismos monstruos sin duplicar sus datos.

export type MonsterDefinition = {
	Id: string,
	Name: string,
	Rarity: string,
	SellValue: number, -- coins que daría vender este monstruo (venta real: ciclo futuro de PetService)
}

local Monsters: { [string]: MonsterDefinition } = {
	SlimeBasic = {
		Id = "SlimeBasic",
		Name = "Slime Básico",
		Rarity = "Common",
		SellValue = 30,
	},
	MushlingBasic = {
		Id = "MushlingBasic",
		Name = "Hongomonstruo Básico",
		Rarity = "Common",
		SellValue = 35,
	},
	CrystalPup = {
		Id = "CrystalPup",
		Name = "Cristalito",
		Rarity = "Uncommon",
		SellValue = 250,
	},
}

return Monsters
```

- [ ] **Step 2: Verificar que el archivo quedó bien escrito**

Leé el archivo de vuelta y confirmá que las 3 entradas (`SlimeBasic`, `MushlingBasic`, `CrystalPup`) están presentes con esos `SellValue` exactos — son los números que hacen que la cuenta de valor esperado de la spec (41.5 / 160.75) cierre.

- [ ] **Step 3: Commit**

```bash
git add src/ReplicatedStorage/Shared/Config/Monsters.lua
git commit -m "feat: agregar config de definiciones de monstruo (Monsters.lua)"
```

---

### Task 2: `Seeds.lua` — reemplaza `Crops.lua`

**Files:**
- Create: `src/ReplicatedStorage/Shared/Config/Seeds.lua`
- Delete: `src/ReplicatedStorage/Shared/Config/Crops.lua`

**Interfaces:**
- Consumes: `MonsterId`s definidos en `Monsters.lua` (Task 1) — deben coincidir exactamente (`SlimeBasic`, `MushlingBasic`, `CrystalPup`).
- Produces: `Seeds: { [string]: SeedDefinition }` donde `SeedDefinition = { Id, Name, Rarity, Price, GrowSeconds, HarvestCoins, MonsterTable }`. Consumido por `EconomyService` (Task 6), `GrowthService` (Task 5), `MonsterService` (Task 4).

- [ ] **Step 1: Crear `Seeds.lua`**

```lua
-- Seeds.lua
-- Configuración de semillas (precio, tiempo de crecimiento, recompensa de
-- coins directas y tabla de probabilidad de qué monstruo se obtiene al
-- cosechar). Reemplaza al viejo Crops.lua -- mismo patrón, con rareza y
-- tabla de monstruos agregadas.

export type SeedMonsterChance = {
	MonsterId: string,
	Chance: number, -- 0..1; la suma de todas las entradas de una semilla debe dar 1.0
}

export type SeedDefinition = {
	Id: string,
	Name: string,
	Rarity: string, -- "Common" | "Uncommon" (más rarezas se suman en ciclos futuros)
	Price: number, -- costo en coins para comprarla en la tienda
	GrowSeconds: number, -- tiempo de crecimiento una vez plantada
	HarvestCoins: number, -- coins directas que da al cosechar
	MonsterTable: { SeedMonsterChance }, -- qué monstruo se obtiene al cosechar
}

local Seeds: { [string]: SeedDefinition } = {
	BasicSeed = {
		Id = "BasicSeed",
		Name = "Semilla Básica",
		Rarity = "Common",
		Price = 25,
		GrowSeconds = 60,
		HarvestCoins = 10,
		MonsterTable = {
			{ MonsterId = "SlimeBasic", Chance = 0.70 },
			{ MonsterId = "MushlingBasic", Chance = 0.30 },
		},
	},
	UncommonSeed = {
		Id = "UncommonSeed",
		Name = "Semilla Poco Común",
		Rarity = "Uncommon",
		Price = 100,
		GrowSeconds = 180,
		HarvestCoins = 40,
		MonsterTable = {
			{ MonsterId = "MushlingBasic", Chance = 0.55 },
			{ MonsterId = "CrystalPup", Chance = 0.40 },
			{ MonsterId = "SlimeBasic", Chance = 0.05 },
		},
	},
}

return Seeds
```

- [ ] **Step 2: Borrar el archivo viejo**

```bash
rm "src/ReplicatedStorage/Shared/Config/Crops.lua"
```

- [ ] **Step 3: Confirmar que no queda ninguna referencia a `Crops` en el código**

```bash
grep -rn "Config.Crops\|Config\.Crops\|require.*Crops" src/
```

Expected: sin resultados (los requires se actualizan en Tasks 5 y 6, que van después — si corrés esto ahora vas a ver 2 matches en `GrowthService.lua` y `EconomyService.lua`; eso es esperado hasta terminar esas tasks).

- [ ] **Step 4: Commit**

```bash
git add -A src/ReplicatedStorage/Shared/Config/Seeds.lua src/ReplicatedStorage/Shared/Config/Crops.lua
git commit -m "feat: renombrar Crops.lua a Seeds.lua y agregar UncommonSeed"
```

---

### Task 3: `DataService.lua` — agregar `Monsters` a los datos del jugador

**Files:**
- Modify: `src/ServerScriptService/Server/Services/DataService.lua:12-21` (tipos) y `:58-64` (`getDefaultData`)

**Interfaces:**
- Produces: `DataService.PlayerData.Monsters: { [string]: MonsterInstance }` donde `MonsterInstance = { InstanceId, MonsterId, Rarity, SellValue, HarvestedAt }`. Consumido por `MonsterService` (Task 4).
- Nota: el tipo `MonsterInstance` se define localmente acá (no se importa de `MonsterService`) siguiendo el mismo patrón ya usado por `PlantedCrop` en este archivo — evita un require circular (`MonsterService` va a requerir `DataService`).

- [ ] **Step 1: Agregar el tipo `MonsterInstance` y extender `PlayerData`**

Reemplazar (líneas 12-21):

```lua
export type PlantedCrop = {
	SeedId: string,
	PlantedAt: number, -- os.time() en el momento de plantar; sobrevive a restarts del servidor
}

export type PlayerData = {
	Coins: number,
	Inventory: { [string]: number },
	Plots: { [number]: PlantedCrop }, -- slot index (1..N) -> cultivo plantado; slot ausente = vacío
}
```

por:

```lua
export type PlantedCrop = {
	SeedId: string,
	PlantedAt: number, -- os.time() en el momento de plantar; sobrevive a restarts del servidor
}

export type MonsterInstance = {
	InstanceId: string,
	MonsterId: string,
	Rarity: string,
	SellValue: number,
	HarvestedAt: number, -- os.time() en el momento de cosechar
}

export type PlayerData = {
	Coins: number,
	Inventory: { [string]: number },
	Plots: { [number]: PlantedCrop }, -- slot index (1..N) -> cultivo plantado; slot ausente = vacío
	Monsters: { [string]: MonsterInstance }, -- instanceId -> monstruo cosechado
}
```

- [ ] **Step 2: Agregar `Monsters = {}` al default**

Reemplazar (líneas 58-64):

```lua
local function getDefaultData(): PlayerData
	return {
		Coins = Economy.STARTING_COINS,
		Inventory = { BasicSeed = 0 },
		Plots = {},
	}
end
```

por:

```lua
local function getDefaultData(): PlayerData
	return {
		Coins = Economy.STARTING_COINS,
		Inventory = { BasicSeed = 0 },
		Plots = {},
		Monsters = {},
	}
end
```

- [ ] **Step 3: Confirmar que `fillMissingFields` no necesita cambios**

`fillMissingFields` (líneas 80-89 del archivo original) ya rellena recursivamente cualquier campo del default que falte en un save viejo — como `Monsters` es un campo nuevo en la raíz (`data.Monsters == nil` en saves viejos), la rama `if data[key] == nil then data[key] = defaultValue end` lo cubre sin tocar esa función.

- [ ] **Step 4: Commit**

```bash
git add src/ServerScriptService/Server/Services/DataService.lua
git commit -m "feat: agregar Monsters a PlayerData"
```

---

### Task 4: `MonsterService.lua` — nuevo servicio

**Files:**
- Create: `src/ServerScriptService/Server/Services/MonsterService.lua`

**Interfaces:**
- Consumes: `Seeds` (Task 2), `Monsters` (Task 1), `DataService.Get(player): PlayerData?` (Task 3).
- Produces:
  - `MonsterService.RollMonster(seedId: string): string?`
  - `MonsterService.GrantMonster(player: Player, monsterId: string): MonsterInstance?`
  - `MonsterService.GetSnapshot(player: Player): { [string]: MonsterInstance }`
  - `MonsterService.Init(): ()`
  - Consumido por `GrowthService` (Task 5) y `Main.server.lua` (Task 7).

- [ ] **Step 1: Crear el servicio**

```lua
-- MonsterService.lua
-- Único punto de verdad para resolver qué monstruo se obtiene al cosechar
-- una semilla, y para guardar/leer los monstruos que ya tiene un jugador.
-- No conoce Plots/crecimiento: sólo tablas de probabilidad y el inventario
-- de monstruos (data.Monsters).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Seeds = require(ReplicatedStorage.Shared.Config.Seeds)
local Monsters = require(ReplicatedStorage.Shared.Config.Monsters)
local DataService = require(script.Parent.DataService)

export type MonsterInstance = {
	InstanceId: string,
	MonsterId: string,
	Rarity: string,
	SellValue: number,
	HarvestedAt: number,
}

local MonsterService = {}

-- Tira la MonsterTable de la semilla `seedId` y devuelve el MonsterId
-- elegido. nil si la semilla no existe o su tabla está vacía (nunca tira
-- error: un roll fallido no debe romper la cosecha).
function MonsterService.RollMonster(seedId: string): string?
	local seed = Seeds[seedId]
	if not seed or #seed.MonsterTable == 0 then
		return nil
	end

	local roll = math.random()
	local accumulated = 0
	for _, entry in ipairs(seed.MonsterTable) do
		accumulated += entry.Chance
		if roll <= accumulated then
			return entry.MonsterId
		end
	end

	-- Redondeo de floats: si las Chance no suman exactamente 1.0, cae acá.
	-- Devolvemos la última entrada en vez de nil para no perder el roll.
	return seed.MonsterTable[#seed.MonsterTable].MonsterId
end

-- Crea una instancia de `monsterId` y la guarda en el inventario de
-- monstruos del jugador. nil (+ warn) si el monstruo no existe en la config
-- o si los datos del jugador no cargaron -- nunca tira error.
function MonsterService.GrantMonster(player: Player, monsterId: string): MonsterInstance?
	local definition = Monsters[monsterId]
	if not definition then
		warn(("[MonsterService] MonsterId desconocido: %s"):format(tostring(monsterId)))
		return nil
	end

	local data = DataService.Get(player)
	if not data then
		warn(("[MonsterService] No se pudo otorgar %s a %s: datos no cargados."):format(monsterId, player.Name))
		return nil
	end

	local instance: MonsterInstance = {
		InstanceId = HttpService:GenerateGUID(false),
		MonsterId = definition.Id,
		Rarity = definition.Rarity,
		SellValue = definition.SellValue,
		HarvestedAt = os.time(),
	}

	data.Monsters[instance.InstanceId] = instance
	return instance
end

-- Copia de solo lectura de los monstruos del jugador (instanceId -> datos),
-- o tabla vacía si sus datos todavía no cargaron.
function MonsterService.GetSnapshot(player: Player): { [string]: MonsterInstance }
	local data = DataService.Get(player)
	if not data then
		return {}
	end

	local snapshot = {}
	for instanceId, instance in pairs(data.Monsters) do
		snapshot[instanceId] = instance
	end
	return snapshot
end

function MonsterService.Init()
	-- Sin estado propio que inicializar: todo vive en DataService.
end

return MonsterService
```

- [ ] **Step 2: Verificación de distribución del roll (vía MCP, Studio en Play/Edit con el server activo)**

Con `rojo serve` corriendo y el plugin de Rojo conectado en Studio, ejecutá esto con `mcp__robloxstudio-mcp__execute_luau` (`target = "server"`):

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local MonsterService = require(ServerScriptService.Server.Services.MonsterService)

local counts = {}
for _ = 1, 2000 do
	local monsterId = MonsterService.RollMonster("BasicSeed")
	counts[monsterId] = (counts[monsterId] or 0) + 1
end

return counts
```

Expected: una tabla con aproximadamente `{ SlimeBasic = ~1400, MushlingBasic = ~600 }` (70/30 sobre 2000 rolls, con margen de ruido estadístico normal).

- [ ] **Step 3: Commit**

```bash
git add src/ServerScriptService/Server/Services/MonsterService.lua
git commit -m "feat: agregar MonsterService (roll de probabilidad + otorgar monstruo)"
```

---

### Task 5: `GrowthService.lua` — otorgar monstruo al cosechar

**Files:**
- Modify: `src/ServerScriptService/Server/Services/GrowthService.lua` (require en línea 9, tipo `ActionResult` en líneas 21-24, `getEffectiveGrowSeconds` en líneas 57-62, `GetSlotState` en líneas 66-92, `handlePlantSeed` en líneas 94-125, `handleHarvest` en líneas 127-168)

**Interfaces:**
- Consumes: `Seeds` (Task 2), `MonsterService.RollMonster`/`GrantMonster`/`MonsterService.MonsterInstance` (Task 4).
- Produces: `ActionResult.Monster: MonsterService.MonsterInstance?` — presente (no-nil) en el resultado de un harvest exitoso cuando el roll de monstruo funcionó.

- [ ] **Step 1: Cambiar el require de `Crops` a `Seeds` y agregar el require de `MonsterService`**

Reemplazar (línea 9):

```lua
local Crops = require(ReplicatedStorage.Shared.Config.Crops)
```

por:

```lua
local Seeds = require(ReplicatedStorage.Shared.Config.Seeds)
```

Y agregar, después de la línea `local InventoryService = require(script.Parent.InventoryService)` (línea 16):

```lua
local MonsterService = require(script.Parent.MonsterService)
```

- [ ] **Step 2: Extender `ActionResult` con el campo `Monster`**

Reemplazar (líneas 21-24):

```lua
export type ActionResult = {
	Success: boolean,
	Reason: string?,
}
```

por:

```lua
export type ActionResult = {
	Success: boolean,
	Reason: string?,
	Monster: MonsterService.MonsterInstance?, -- presente solo en un harvest exitoso con roll de monstruo
}
```

- [ ] **Step 3: Renombrar `crop` a `seed` en `getEffectiveGrowSeconds`**

Reemplazar (líneas 57-62):

```lua
local function getEffectiveGrowSeconds(player: Player, crop: Crops.CropDefinition): number
	if MonetizationService.HasGamePass(player, "DoubleGrowthSpeed") then
		return crop.GrowSeconds / 2
	end
	return crop.GrowSeconds
end
```

por:

```lua
local function getEffectiveGrowSeconds(player: Player, seed: Seeds.SeedDefinition): number
	if MonetizationService.HasGamePass(player, "DoubleGrowthSpeed") then
		return seed.GrowSeconds / 2
	end
	return seed.GrowSeconds
end
```

- [ ] **Step 4: Renombrar `crop` a `seed` en `GetSlotState`**

Reemplazar (líneas 66-92):

```lua
function GrowthService.GetSlotState(player: Player, slotIndex: number): PlotStateView?
	local data = DataService.Get(player)
	if not data then
		return nil
	end

	local plantedCrop = data.Plots[slotIndex]
	if not plantedCrop then
		return nil
	end

	local crop = Crops[plantedCrop.SeedId]
	if not crop then
		return nil
	end

	local effectiveGrowSeconds = getEffectiveGrowSeconds(player, crop)
	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	local remainingSeconds = math.max(effectiveGrowSeconds - elapsedSeconds, 0)

	return {
		SeedId = plantedCrop.SeedId,
		GrowSeconds = effectiveGrowSeconds,
		RemainingSeconds = remainingSeconds,
		IsReady = remainingSeconds <= 0,
	}
end
```

por:

```lua
function GrowthService.GetSlotState(player: Player, slotIndex: number): PlotStateView?
	local data = DataService.Get(player)
	if not data then
		return nil
	end

	local plantedCrop = data.Plots[slotIndex]
	if not plantedCrop then
		return nil
	end

	local seed = Seeds[plantedCrop.SeedId]
	if not seed then
		return nil
	end

	local effectiveGrowSeconds = getEffectiveGrowSeconds(player, seed)
	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	local remainingSeconds = math.max(effectiveGrowSeconds - elapsedSeconds, 0)

	return {
		SeedId = plantedCrop.SeedId,
		GrowSeconds = effectiveGrowSeconds,
		RemainingSeconds = remainingSeconds,
		IsReady = remainingSeconds <= 0,
	}
end
```

- [ ] **Step 5: Renombrar `crop` a `seed` en `handlePlantSeed`**

Reemplazar (líneas 94-125):

```lua
local function handlePlantSeed(player: Player, seedId: string, slotIndex: number): ActionResult
	local crop = Crops[seedId]
	if not crop then
		return { Success = false, Reason = "SeedNotFound" }
	end

	if not PlotService.GetPlot(player) then
		return { Success = false, Reason = "NoPlot" }
	end

	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if slotIndex < 1 or slotIndex > GrowthService.GetMaxPlotSlots(player) then
		return { Success = false, Reason = "InvalidSlot" }
	end

	if data.Plots[slotIndex] ~= nil then
		return { Success = false, Reason = "PlotOccupied" }
	end

	if not InventoryService.HasItem(player, seedId) then
		return { Success = false, Reason = "SeedNotOwned" }
	end

	InventoryService.RemoveItem(player, seedId, 1)
	data.Plots[slotIndex] = { SeedId = seedId, PlantedAt = os.time() }

	return { Success = true }
end
```

por:

```lua
local function handlePlantSeed(player: Player, seedId: string, slotIndex: number): ActionResult
	local seed = Seeds[seedId]
	if not seed then
		return { Success = false, Reason = "SeedNotFound" }
	end

	if not PlotService.GetPlot(player) then
		return { Success = false, Reason = "NoPlot" }
	end

	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if slotIndex < 1 or slotIndex > GrowthService.GetMaxPlotSlots(player) then
		return { Success = false, Reason = "InvalidSlot" }
	end

	if data.Plots[slotIndex] ~= nil then
		return { Success = false, Reason = "PlotOccupied" }
	end

	if not InventoryService.HasItem(player, seedId) then
		return { Success = false, Reason = "SeedNotOwned" }
	end

	InventoryService.RemoveItem(player, seedId, 1)
	data.Plots[slotIndex] = { SeedId = seedId, PlantedAt = os.time() }

	return { Success = true }
end
```

- [ ] **Step 6: Otorgar monstruo en `handleHarvest`**

Reemplazar (líneas 127-168):

```lua
local function handleHarvest(player: Player, slotIndex: number): ActionResult
	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if slotIndex < 1 or slotIndex > GrowthService.GetMaxPlotSlots(player) then
		return { Success = false, Reason = "InvalidSlot" }
	end

	local plantedCrop = data.Plots[slotIndex]
	if not plantedCrop then
		return { Success = false, Reason = "PlotEmpty" }
	end

	local crop = Crops[plantedCrop.SeedId]
	if not crop then
		-- Config borrada/renombrada después de que alguien ya la plantó.
		data.Plots[slotIndex] = nil
		return { Success = false, Reason = "SeedNotFound" }
	end

	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	if elapsedSeconds < getEffectiveGrowSeconds(player, crop) then
		return { Success = false, Reason = "NotReady" }
	end

	local reward = crop.HarvestReward
	if MonetizationService.HasGamePass(player, "DoubleCoins") then
		reward *= 2
	end

	if MonetizationService.HasGamePass(player, "VipGarden") then
		local bonusPercent = Monetization.GamePasses.VipGarden.CoinBonusPercent or 0
		reward += math.floor(reward * bonusPercent / 100)
	end

	data.Plots[slotIndex] = nil
	EconomyService.AddCoins(player, reward)

	return { Success = true }
end
```

por:

```lua
local function handleHarvest(player: Player, slotIndex: number): ActionResult
	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if slotIndex < 1 or slotIndex > GrowthService.GetMaxPlotSlots(player) then
		return { Success = false, Reason = "InvalidSlot" }
	end

	local plantedCrop = data.Plots[slotIndex]
	if not plantedCrop then
		return { Success = false, Reason = "PlotEmpty" }
	end

	local seed = Seeds[plantedCrop.SeedId]
	if not seed then
		-- Config borrada/renombrada después de que alguien ya la plantó.
		data.Plots[slotIndex] = nil
		return { Success = false, Reason = "SeedNotFound" }
	end

	local elapsedSeconds = os.time() - plantedCrop.PlantedAt
	if elapsedSeconds < getEffectiveGrowSeconds(player, seed) then
		return { Success = false, Reason = "NotReady" }
	end

	local reward = seed.HarvestCoins
	if MonetizationService.HasGamePass(player, "DoubleCoins") then
		reward *= 2
	end

	if MonetizationService.HasGamePass(player, "VipGarden") then
		local bonusPercent = Monetization.GamePasses.VipGarden.CoinBonusPercent or 0
		reward += math.floor(reward * bonusPercent / 100)
	end

	data.Plots[slotIndex] = nil
	EconomyService.AddCoins(player, reward)

	local monster: MonsterService.MonsterInstance? = nil
	local monsterId = MonsterService.RollMonster(seed.Id)
	if monsterId then
		monster = MonsterService.GrantMonster(player, monsterId)
	else
		warn(("[GrowthService] %s no otorgó monstruo a %s al cosechar: MonsterTable vacía/corrupta."):format(seed.Id, player.Name))
	end

	return { Success = true, Monster = monster }
end
```

- [ ] **Step 7: Verificación de cosecha completa (vía MCP `execute_luau`, `target = "server"`)**

Con un jugador conectado (Play Solo en Studio) y `rojo serve` corriendo:

```lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

local DataService = require(Services.DataService)
local GrowthService = require(Services.GrowthService)
local InventoryService = require(Services.InventoryService)

local player = Players:GetPlayers()[1]
if not player then
	return "No hay ningún jugador conectado -- entrá a Play Solo primero."
end

local data = DataService.Get(player)
local coinsBefore = data.Coins

local targetSlot = 1
data.Plots[targetSlot] = nil -- asegurar vacío
data.Plots[targetSlot] = { SeedId = "BasicSeed", PlantedAt = os.time() - 999 } -- ya listo

local monstersBefore = 0
for _ in pairs(data.Monsters) do
	monstersBefore += 1
end

-- Cosechar invocando el remote real (mismo camino que usa el cliente)
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)
local harvestRemote = Remotes.GetHarvestRemote()
local result = harvestRemote.OnServerInvoke(player, targetSlot)

local monstersAfter = 0
for _ in pairs(data.Monsters) do
	monstersAfter += 1
end

return {
	CoinsBefore = coinsBefore,
	CoinsAfter = data.Coins,
	MonstersBefore = monstersBefore,
	MonstersAfter = monstersAfter,
	HarvestResult = result,
}
```

Expected: `CoinsAfter - CoinsBefore == 10` (o más si el jugador tiene gamepasses activos en Studio), `MonstersAfter == MonstersBefore + 1`, y `HarvestResult.Monster` no-nil con un `MonsterId` de `SlimeBasic` o `MushlingBasic`.

- [ ] **Step 8: Commit**

```bash
git add src/ServerScriptService/Server/Services/GrowthService.lua
git commit -m "feat: GrowthService otorga un monstruo real al cosechar"
```

---

### Task 6: `EconomyService.lua` — actualizar require

**Files:**
- Modify: `src/ServerScriptService/Server/Services/EconomyService.lua:8` y `:46-65`

**Interfaces:**
- Consumes: `Seeds` (Task 2). Sin cambios de firma pública — `EconomyService.AddCoins`/`RemoveCoins`/`Init` quedan iguales.

- [ ] **Step 1: Cambiar el require**

Reemplazar (línea 8):

```lua
local Crops = require(ReplicatedStorage.Shared.Config.Crops)
```

por:

```lua
local Seeds = require(ReplicatedStorage.Shared.Config.Seeds)
```

- [ ] **Step 2: Renombrar `crop` a `seed` en `handleBuySeed`**

Reemplazar (líneas 46-65):

```lua
local function handleBuySeed(player: Player, seedId: string): BuySeedResult
	local crop = Crops[seedId]
	if not crop then
		return { Success = false, Reason = "SeedNotFound" }
	end

	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if data.Coins < crop.Price then
		return { Success = false, Reason = "NotEnoughCoins" }
	end

	data.Coins -= crop.Price
	InventoryService.AddItem(player, seedId, 1)

	return { Success = true, Coins = data.Coins }
end
```

por:

```lua
local function handleBuySeed(player: Player, seedId: string): BuySeedResult
	local seed = Seeds[seedId]
	if not seed then
		return { Success = false, Reason = "SeedNotFound" }
	end

	local data = DataService.Get(player)
	if not data then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if data.Coins < seed.Price then
		return { Success = false, Reason = "NotEnoughCoins" }
	end

	data.Coins -= seed.Price
	InventoryService.AddItem(player, seedId, 1)

	return { Success = true, Coins = data.Coins }
end
```

- [ ] **Step 3: Confirmar que ya no queda ninguna referencia a `Crops` en `src/`**

```bash
grep -rn "Config.Crops\|require.*Crops" src/
```

Expected: sin resultados.

- [ ] **Step 4: Commit**

```bash
git add src/ServerScriptService/Server/Services/EconomyService.lua
git commit -m "feat: EconomyService usa Seeds.lua en vez de Crops.lua"
```

---

### Task 7: `Main.server.lua` — inicializar `MonsterService`

**Files:**
- Modify: `src/ServerScriptService/Server/Main.server.lua`

**Interfaces:**
- Consumes: `MonsterService.Init()` (Task 4).

- [ ] **Step 1: Agregar el require y la llamada a `Init()`**

Reemplazar el archivo completo:

```lua
-- Main.server.lua
-- Punto de entrada del servidor. Inicializa todos los servicios en orden.
-- Orden: DataService primero (los demás servicios dependerán de los datos del jugador).

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

local DataService = require(Services.DataService)
local PlotService = require(Services.PlotService)
local MonsterService = require(Services.MonsterService)
local GrowthService = require(Services.GrowthService)
local EconomyService = require(Services.EconomyService)
local InventoryService = require(Services.InventoryService)
local TradeService = require(Services.TradeService)
local MonetizationService = require(Services.MonetizationService)
local AdminService = require(Services.AdminService)

print("[Main] Monster Garden Tycoon iniciando...")

DataService.Init()
PlotService.Init()
MonsterService.Init()
GrowthService.Init()
EconomyService.Init()
InventoryService.Init()
TradeService.Init()
MonetizationService.Init()
AdminService.Init()

print("[Main] Todos los servicios inicializados.")
```

- [ ] **Step 2: Commit**

```bash
git add src/ServerScriptService/Server/Main.server.lua
git commit -m "feat: inicializar MonsterService en Main.server.lua"
```

---

### Task 8: `AdminService.lua` — comando `!seed` acepta `UncommonSeed`

**Files:**
- Modify: `src/ServerScriptService/Server/Services/AdminService.lua:1-9` (comentario de cabecera), `:41-54` (`handleSeedCommand`) y `:56-66` (`handleResetCommand`)

**Interfaces:**
- Sin cambios de firma pública — solo cambia el parseo del comando de chat `!seed` y qué limpia `!reset`.

- [ ] **Step 1: Actualizar el comentario de cabecera**

Reemplazar (líneas 1-9):

```lua
-- AdminService.lua
-- Comandos de prueba por chat. En Studio (Play Solo / Team Test) cualquier
-- jugador puede usarlos. Fuera de Studio, solo los UserIds de la whitelist
-- en Config/Admins.lua pueden ejecutarlos.
--
-- Comandos:
--   !coins <cantidad>  -> suma coins
--   !seed <cantidad>   -> suma BasicSeed al inventario
--   !reset             -> vuelve Coins/Inventory/Plots a los valores por defecto
```

por:

```lua
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
```

- [ ] **Step 2: Reescribir `handleSeedCommand`**

Reemplazar (líneas 41-54):

```lua
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
```

por:

```lua
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
```

- [ ] **Step 3: Actualizar `handleResetCommand` para limpiar también `Monsters`**

Reemplazar (líneas 56-66):

```lua
local function handleResetCommand(player: Player)
	local data = DataService.Get(player)
	if not data then
		warn(("[AdminService] Datos de %s todavía no cargaron."):format(player.Name))
		return
	end

	data.Coins = Economy.STARTING_COINS
	data.Inventory = { BasicSeed = 0 }
	data.Plots = {}
end
```

por:

```lua
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
```

- [ ] **Step 4: Verificación manual en Studio**

En el chat de Play Solo: `!seed UncommonSeed 1` → confirmar (vía `execute_luau`, `target = "server"`, `InventoryService.GetCount(player, "UncommonSeed")`) que da `1`. Probar también `!seed 3` (uso corto) → confirmar que suma `BasicSeed`.

- [ ] **Step 5: Commit**

```bash
git add src/ServerScriptService/Server/Services/AdminService.lua
git commit -m "feat: comando admin !seed acepta UncommonSeed y !reset limpia Monsters"
```

---

### Task 9: Verificación end-to-end en Studio

**Files:** ninguno (solo verificación manual — no hay tests automatizados en este proyecto)

- [ ] **Step 1: Levantar Rojo y confirmar sync**

```bash
cd "C:\Users\17868\Monster-Garden-Tycoon" && rojo serve
```

En Studio: Rojo plugin → Connect. Confirmar en el Output que no hay errores de sintaxis al sincronizar los archivos nuevos/modificados.

- [ ] **Step 2: Play Solo y probar el loop completo manualmente**

1. `!seed UncommonSeed 1` en el chat.
2. Comprar y plantar una `BasicSeed` (flujo normal de UI) y también plantar la `UncommonSeed` recién obtenida.
3. Usar `!coins 999999` si hace falta esperar sin gamepass de crecimiento (o simplemente esperar los 60s/180s reales).
4. Cosechar ambas. Confirmar en el Output/UI que las coins suben (10 y 40 respectivamente) y que no aparece ningún error rojo.

- [ ] **Step 3: Inspeccionar `data.Monsters` final vía MCP**

```lua
local Players = game:GetService("Players")
local DataService = require(game:GetService("ServerScriptService").Server.Services.DataService)

local player = Players:GetPlayers()[1]
local data = DataService.Get(player)

local monsters = {}
for _, instance in pairs(data.Monsters) do
	table.insert(monsters, instance)
end

return monsters
```

Expected: una lista con 2 entradas (una por cada cosecha), cada una con `MonsterId` válido (`SlimeBasic`, `MushlingBasic` o `CrystalPup`), `SellValue` coincidiendo con `Monsters.lua`, y `HarvestedAt` reciente.

- [ ] **Step 4: Confirmar que un save previo sin `Monsters` migra bien**

Como el lugar no está publicado (sin DataStore real disponible — ver `DataService.lua` líneas 33-45, "Enable Studio Access to API Services" desactivado), la migración de saves viejos solo se puede probar end-to-end después de publicar. Queda documentado como pendiente de verificación post-publicación — la garantía en este ciclo es de lectura de código: `getDefaultData()` (Task 3) incluye `Monsters = {}`, y `fillMissingFields` (sin cambios) ya rellena recursivamente cualquier campo raíz ausente. No bloquea este ciclo.

- [ ] **Step 5: Guardar el lugar**

En Studio: `File > Save` (por si se generó algo adicional en el mundo durante las pruebas manuales).

- [ ] **Step 6: Push final**

```bash
git push
```

---

## Self-Review

**Cobertura de la spec:**
- Sección 1 (`Seeds.lua`) → Task 2. ✓
- Sección 2 (`Monsters.lua`) → Task 1. ✓
- Sección 3 (`MonsterService.lua`) → Task 4. ✓
- Sección 4 (`DataService.lua`) → Task 3. ✓
- Sección 5 (`GrowthService.lua`) → Task 5. ✓
- Sección 6 (`EconomyService.lua`) → Task 6. ✓
- Testing puntos 1-2 (cosecha con `BasicSeed`/`UncommonSeed` vía admin) → Tasks 8 y 9. ✓
- Testing punto 3 (save viejo migra) → Task 9 Step 4 (documentado como no verificable sin publicar; no bloquea).
- Testing punto 4 (`MonsterTable` corrupta no rompe cosecha) → cubierto por el diseño de `RollMonster`/`GrantMonster` (Task 4), que siempre devuelven `nil` en vez de tirar error; no requiere un test dedicado porque no hay forma de "corromper" la config sin editar el archivo a mano.

**Sin placeholders:** cada step tiene código completo, comandos exactos o instrucciones concretas de verificación manual — ninguno dice "TBD" ni "similar a Task N" sin repetir el código.

**Consistencia de tipos:** `MonsterService.MonsterInstance` (Task 4) y el `MonsterInstance` local de `DataService.lua` (Task 3) tienen exactamente los mismos 5 campos (`InstanceId`, `MonsterId`, `Rarity`, `SellValue`, `HarvestedAt`) — intencionalmente duplicados para evitar un require circular, documentado en Task 3 Step 1. `ActionResult.Monster` (Task 5) referencia `MonsterService.MonsterInstance`, no el tipo local de `DataService` — consistente porque `GrowthService` ya requiere `MonsterService` directamente.
