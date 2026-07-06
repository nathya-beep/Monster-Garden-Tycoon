# Sistema de Criaturas y Rareza — Plan de Implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Al cosechar, el jugador tiene una probabilidad (definida por semilla) de obtener una criatura coleccionable de una de 5 rarezas, visible en una nueva UI de colección.

**Architecture:** Un módulo puro `CreatureRoll.lua` (sin estado, sin remotos) sortea la rareza según los pesos de la semilla cosechada y elige una criatura de esa rareza desde `Creatures.lua`. `GrowthService.handleHarvest` lo invoca y guarda el resultado vía `InventoryService.AddItem` (mismo inventario genérico que las semillas). El remoto `Harvest` existente extiende su respuesta con `Coins` y `CreatureObtained`; el cliente lo usa para mostrar un mensaje y actualizar un panel de colección.

**Tech Stack:** Luau, Rojo (sync a Roblox Studio), sin framework de tests automatizado en este repo — la verificación de código puro se hace vía Studio Command Bar (patrón ya usado por este proyecto para pruebas manuales, ver `AdminService.lua`).

## Global Constraints

- Autoridad de servidor: el cliente nunca decide la criatura obtenida ni las coins — todo el roll ocurre dentro de `handleHarvest` en el servidor.
- Separar config de lógica: rarezas/criaturas/pesos viven en `ReplicatedStorage/Shared/Config/*`, nunca hardcodeados en servicios.
- Módulos pequeños, nombres descriptivos, type annotations donde ayuden (patrón ya usado en todo `src/`).
- No crear archivos grandes — `CreatureRoll.lua` es un módulo nuevo separado, no se agrega a `GrowthService.lua`.
- Alcance de "solo colección": las criaturas obtenidas no dan bonus pasivo ni se pueden vender en este plan (spec `docs/superpowers/specs/2026-07-06-creatures-rarity-design.md`, sección "Fuera de alcance").
- No tocar trading/raids/eventos/monetización avanzada — fuera de alcance (regla existente de `CLAUDE.md`).

---

### Task 1: Contenido de `Rarities.lua`

**Files:**
- Modify: `src/ReplicatedStorage/Shared/Config/Rarities.lua` (reemplaza el archivo vacío completo)

**Interfaces:**
- Consumes: nada.
- Produces: `Rarities: { [string]: { DisplayName: string, Color: Color3 } }` con las claves `Common`, `Uncommon`, `Rare`, `Epic`, `Legendary` — usado por Task 2 (validación de `Rarity`), Task 4 (`CreatureRoll`), y Task 6 (color/nombre en UI).

- [ ] **Step 1: Reemplazar el contenido de `Rarities.lua`**

```lua
-- Rarities.lua
-- Configuración de rarezas de criaturas (nombre de despliegue y color para UI).

export type RarityDefinition = {
	DisplayName: string,
	Color: Color3,
}

local Rarities: { [string]: RarityDefinition } = {
	Common = { DisplayName = "Común", Color = Color3.fromRGB(190, 190, 190) },
	Uncommon = { DisplayName = "Poco común", Color = Color3.fromRGB(90, 200, 90) },
	Rare = { DisplayName = "Raro", Color = Color3.fromRGB(80, 140, 240) },
	Epic = { DisplayName = "Épico", Color = Color3.fromRGB(170, 90, 220) },
	Legendary = { DisplayName = "Legendario", Color = Color3.fromRGB(240, 180, 40) },
}

return Rarities
```

- [ ] **Step 2: Verificar sintaxis vía Rojo**

Run: `rojo build default.project.json -o /tmp/verify.rbxl` (o el comando de build que uses localmente; si no tenés Rojo CLI instalado, abrí Studio con el proyecto sincronizado y confirmá en el Output que no hay errores de script).

Expected: build sin errores de sintaxis Luau.

- [ ] **Step 3: Commit**

```bash
git add src/ReplicatedStorage/Shared/Config/Rarities.lua
git commit -m "feat: define creature rarity tiers (Common..Legendary)"
git push origin main
```

---

### Task 2: Contenido de `Creatures.lua`

**Files:**
- Modify: `src/ReplicatedStorage/Shared/Config/Creatures.lua` (reemplaza el archivo vacío completo)

**Interfaces:**
- Consumes: claves de rareza de Task 1 (`Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`) — usadas como valor del campo `Rarity`.
- Produces: `Creatures: { [string]: { Id: string, Name: string, Rarity: string } }`, keyed por `Id` (mismo patrón que `Crops` en `Crops.lua`) — usado por Task 4 (`CreatureRoll`) y Task 6 (lookup de nombre/rareza en UI).

- [ ] **Step 1: Reemplazar el contenido de `Creatures.lua`**

```lua
-- Creatures.lua
-- Configuración de criaturas coleccionables. Cada una pertenece a una
-- rareza definida en Rarities.lua.

export type CreatureDefinition = {
	Id: string,
	Name: string,
	Rarity: string, -- clave de Rarities.lua
}

local Creatures: { [string]: CreatureDefinition } = {
	Sprout = { Id = "Sprout", Name = "Sprout", Rarity = "Common" },
	Mossling = { Id = "Mossling", Name = "Mossling", Rarity = "Common" },
	Thistlepup = { Id = "Thistlepup", Name = "Thistlepup", Rarity = "Uncommon" },
	Petalfox = { Id = "Petalfox", Name = "Petalfox", Rarity = "Uncommon" },
	Duskbloom = { Id = "Duskbloom", Name = "Duskbloom", Rarity = "Rare" },
	Glimmerhorn = { Id = "Glimmerhorn", Name = "Glimmerhorn", Rarity = "Rare" },
	Emberpetal = { Id = "Emberpetal", Name = "Emberpetal", Rarity = "Epic" },
	Frostvine = { Id = "Frostvine", Name = "Frostvine", Rarity = "Epic" },
	Aurelight = { Id = "Aurelight", Name = "Aurelight", Rarity = "Legendary" },
	Starblossom = { Id = "Starblossom", Name = "Starblossom", Rarity = "Legendary" },
}

return Creatures
```

- [ ] **Step 2: Verificar en Studio (Output sin errores) o `rojo build`**

Expected: sin errores de sintaxis.

- [ ] **Step 3: Commit**

```bash
git add src/ReplicatedStorage/Shared/Config/Creatures.lua
git commit -m "feat: define initial 10-creature roster (2 per rarity tier)"
git push origin main
```

---

### Task 3: `RarityWeights` en `Crops.lua`

**Files:**
- Modify: `src/ReplicatedStorage/Shared/Config/Crops.lua`

**Interfaces:**
- Consumes: nada nuevo (claves de rareza son solo strings, no requiere `require` de `Rarities.lua`).
- Produces: `Crops.BasicSeed.RarityWeights: { [string]: number }` — usado por Task 4 (`CreatureRoll.Roll`).

- [ ] **Step 1: Extender el tipo `CropDefinition` y `BasicSeed`**

Reemplazar todo el archivo `src/ReplicatedStorage/Shared/Config/Crops.lua`:

```lua
-- Crops.lua
-- Configuración de semillas/cultivos (precio, tiempo de crecimiento, recompensa).

export type CropDefinition = {
	Id: string,
	Name: string,
	Price: number, -- costo en coins para comprarla en la tienda
	GrowSeconds: number, -- tiempo de crecimiento una vez plantada
	HarvestReward: number, -- coins que da al cosecharla
	RarityWeights: { [string]: number }?, -- clave de Rarities.lua -> peso relativo de obtener esa rareza al cosechar
}

local Crops: { [string]: CropDefinition } = {
	BasicSeed = {
		Id = "BasicSeed",
		Name = "Semilla Básica",
		Price = 25,
		GrowSeconds = 60,
		HarvestReward = 15,
		RarityWeights = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 },
	},
}

return Crops
```

- [ ] **Step 2: Verificar en Studio (Output sin errores) o `rojo build`**

Expected: sin errores de sintaxis; `EconomyService`/`GrowthService` que ya usan `Crops[seedId].Price`/`.GrowSeconds`/`.HarvestReward` siguen compilando sin cambios (campo nuevo es opcional).

- [ ] **Step 3: Commit**

```bash
git add src/ReplicatedStorage/Shared/Config/Crops.lua
git commit -m "feat: add RarityWeights to BasicSeed for creature drops"
git push origin main
```

---

### Task 4: Módulo `CreatureRoll.lua`

**Files:**
- Create: `src/ReplicatedStorage/Shared/CreatureRoll.lua`

**Interfaces:**
- Consumes: `Crops[seedId].RarityWeights` (Task 3), `Creatures[creatureId].Rarity` (Task 2).
- Produces: `CreatureRoll.Roll(seedId: string): string?` — usado por Task 5 (`GrowthService.handleHarvest`).

- [ ] **Step 1: Crear `CreatureRoll.lua`**

```lua
-- CreatureRoll.lua
-- Lógica pura para sortear qué criatura (si alguna) se obtiene al cosechar
-- una semilla. Sin estado, sin efectos secundarios: fácil de testear
-- llamando Roll muchas veces y verificando la distribución resultante.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crops = require(ReplicatedStorage.Shared.Config.Crops)
local Creatures = require(ReplicatedStorage.Shared.Config.Creatures)

local CreatureRoll = {}

-- Elige una clave de `weights` (ej. "Common"/"Rare") de forma ponderada.
-- Los pesos son relativos, no necesitan sumar 100.
local function weightedPick(weights: { [string]: number }): string?
	local total = 0
	for _, weight in pairs(weights) do
		total += weight
	end

	if total <= 0 then
		return nil
	end

	local roll = math.random() * total
	local cumulative = 0
	for key, weight in pairs(weights) do
		cumulative += weight
		if roll <= cumulative then
			return key
		end
	end

	return nil
end

-- Sortea una criatura para la semilla `seedId`. Retorna nil si la semilla
-- no define RarityWeights, o si la rareza sorteada no tiene ninguna
-- criatura definida en Creatures.lua (nunca debe romper la cosecha).
function CreatureRoll.Roll(seedId: string): string?
	local crop = Crops[seedId]
	if not crop or not crop.RarityWeights then
		return nil
	end

	local rarity = weightedPick(crop.RarityWeights)
	if not rarity then
		return nil
	end

	local pool = {}
	for creatureId, creature in pairs(Creatures) do
		if creature.Rarity == rarity then
			table.insert(pool, creatureId)
		end
	end

	if #pool == 0 then
		return nil
	end

	return pool[math.random(#pool)]
end

return CreatureRoll
```

- [ ] **Step 2: Verificar la distribución vía Studio Command Bar**

Este repo no tiene framework de tests Luau (confirmado: no hay `TestEZ` ni carpeta `tests/`). El equivalente de "correr el test" en este proyecto es pegar código en el Command Bar de Studio con el proyecto sincronizado por Rojo (mismo patrón manual que ya usa `AdminService.lua` para pruebas). Pegar y ejecutar:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CreatureRoll = require(ReplicatedStorage.Shared.CreatureRoll)
local Creatures = require(ReplicatedStorage.Shared.Config.Creatures)

local counts = {}
local ITERATIONS = 10000
for _ = 1, ITERATIONS do
	local creatureId = CreatureRoll.Roll("BasicSeed")
	if creatureId then
		local rarity = Creatures[creatureId].Rarity
		counts[rarity] = (counts[rarity] or 0) + 1
	end
end

for rarity, count in pairs(counts) do
	print(rarity, count, string.format("%.1f%%", count / ITERATIONS * 100))
end
```

Expected: salida con 5 líneas (Common, Uncommon, Rare, Epic, Legendary) cuyos porcentajes se aproximan a 60% / 25% / 10% / 4% / 1% respectivamente (tolerancia ±3 puntos porcentuales dado el tamaño de muestra). Si alguna rareza no aparece o los porcentajes están muy lejos de los pesos configurados, revisar `weightedPick` antes de continuar.

- [ ] **Step 3: Commit**

```bash
git add src/ReplicatedStorage/Shared/CreatureRoll.lua
git commit -m "feat: add CreatureRoll pure module for weighted creature drops"
git push origin main
```

---

### Task 5: Integrar `CreatureRoll` en `GrowthService.handleHarvest`

**Files:**
- Modify: `src/ServerScriptService/Server/Services/GrowthService.lua:9-24` (requires + tipo `ActionResult`), `:127-168` (`handleHarvest`)

**Interfaces:**
- Consumes: `CreatureRoll.Roll(seedId): string?` (Task 4), `InventoryService.AddItem(player, itemId, amount): boolean` (ya existente).
- Produces: remoto `Harvest` ahora responde `{ Success: true, Coins: number, CreatureObtained: string? }` en éxito — usado por Task 6 (`Client.client.lua`).

- [ ] **Step 1: Agregar el require de `CreatureRoll` y extender el tipo `ActionResult`**

En `src/ServerScriptService/Server/Services/GrowthService.lua`, la línea 12 actual es:

```lua
local Remotes = require(ReplicatedStorage.Shared.Remotes)
```

Agregar inmediatamente después (nueva línea 13):

```lua
local CreatureRoll = require(ReplicatedStorage.Shared.CreatureRoll)
```

El bloque de tipo `ActionResult` (líneas 21-24 actuales):

```lua
export type ActionResult = {
	Success: boolean,
	Reason: string?,
}
```

reemplazarlo por:

```lua
export type ActionResult = {
	Success: boolean,
	Reason: string?,
	Coins: number?,
	CreatureObtained: string?,
}
```

- [ ] **Step 2: Extender `handleHarvest` para rolear y guardar la criatura**

El `handleHarvest` actual (líneas 127-168) termina así:

```lua
	data.Plots[slotIndex] = nil
	EconomyService.AddCoins(player, reward)

	return { Success = true }
end
```

Reemplazar esas últimas 4 líneas por:

```lua
	data.Plots[slotIndex] = nil
	EconomyService.AddCoins(player, reward)

	local creatureObtained = CreatureRoll.Roll(plantedCrop.SeedId)
	if creatureObtained then
		InventoryService.AddItem(player, creatureObtained, 1)
	end

	return { Success = true, Coins = reward, CreatureObtained = creatureObtained }
end
```

(El resto de la función — validaciones de `DataNotLoaded`, `InvalidSlot`, `PlotEmpty`, `SeedNotFound`, `NotReady`, y el cálculo de `reward` con `DoubleCoins`/`VipGarden` — no cambia.)

- [ ] **Step 3: Verificar en Studio**

Con el proyecto sincronizado por Rojo y Play Solo activo: comprar `BasicSeed` (`!seed 1` en el chat si hace falta más coins vía `!coins 100`), plantarla, esperar a que esté lista, y cosechar. En el Output del servidor no debe haber warnings de `[GrowthService] Error procesando Harvest`. Agregar temporalmente un `print("[Harvest]", player.Name, creatureObtained)` justo antes del `return` final de `handleHarvest`, cosechar varias veces (reponiendo con `!coins`/`!seed`), y confirmar en el Output que a veces `creatureObtained` no es `nil`. Quitar el `print` temporal después de confirmar.

Expected: la cosecha sigue dando coins como antes, y ocasionalmente el `print` muestra un `creatureId` no-nil.

- [ ] **Step 4: Commit**

```bash
git add src/ServerScriptService/Server/Services/GrowthService.lua
git commit -m "feat: roll and grant a creature on harvest via CreatureRoll"
git push origin main
```

---

### Task 6: UI — mensaje de cosecha y panel de colección

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/Client.client.lua:11` (requires), `:124-132` (`showStatus`), `:161-168` (`requestHarvest`), `:220-253` (`refreshUI`)

**Interfaces:**
- Consumes: `Rarities` (Task 1), `Creatures` (Task 2), campos `Coins`/`CreatureObtained` de la respuesta de `Harvest` (Task 5), `state.Inventory` (ya expuesto por `GetPlayerState`, sin cambios de Task 5 — las criaturas quedan ahí automáticamente vía `InventoryService`).
- Produces: nada consumido por otro archivo (es la capa de presentación final).

- [ ] **Step 1: Agregar requires de `Rarities` y `Creatures`**

La línea 11 actual es:

```lua
local Crops = require(ReplicatedStorage.Shared.Config.Crops)
```

Agregar inmediatamente después (nueva línea 12):

```lua
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Creatures = require(ReplicatedStorage.Shared.Config.Creatures)
```

- [ ] **Step 2: Extender `showStatus` para aceptar un color opcional**

El `showStatus` actual (líneas 124-132):

```lua
local function showStatus(message: string)
	statusLabel.Text = message
	statusLabel.Visible = true
	task.delay(STATUS_MESSAGE_SECONDS, function()
		if statusLabel.Text == message then
			statusLabel.Visible = false
		end
	end)
end
```

reemplazarlo por:

```lua
local DEFAULT_STATUS_COLOR = Color3.fromRGB(255, 230, 120)

local function showStatus(message: string, color: Color3?)
	statusLabel.Text = message
	statusLabel.TextColor3 = color or DEFAULT_STATUS_COLOR
	statusLabel.Visible = true
	task.delay(STATUS_MESSAGE_SECONDS, function()
		if statusLabel.Text == message then
			statusLabel.Visible = false
		end
	end)
end
```

Todos los demás llamados existentes a `showStatus(msg)` (sin segundo argumento) siguen funcionando igual, usando `DEFAULT_STATUS_COLOR`.

- [ ] **Step 3: Mostrar la criatura obtenida en `requestHarvest`**

El `requestHarvest` actual (líneas 161-168):

```lua
local function requestHarvest(slotIndex: number)
	local ok, result = pcall(function()
		return harvestRemote:InvokeServer(slotIndex)
	end)

	showStatus(ok and result.Success and "¡Cosecha exitosa!" or describeReason(ok and result.Reason))
	fetchState()
end
```

reemplazarlo por:

```lua
local function requestHarvest(slotIndex: number)
	local ok, result = pcall(function()
		return harvestRemote:InvokeServer(slotIndex)
	end)

	if ok and result.Success then
		local message = ("¡Cosecha exitosa! +%d coins"):format(result.Coins or 0)
		local color: Color3? = nil

		if result.CreatureObtained then
			local creature = Creatures[result.CreatureObtained]
			local rarity = Rarities[creature.Rarity]
			message ..= (" · ¡Obtuviste: %s (%s)!"):format(creature.Name, rarity.DisplayName)
			color = rarity.Color
		end

		showStatus(message, color)
	else
		showStatus(describeReason(ok and result.Reason))
	end

	fetchState()
end
```

- [ ] **Step 4: Agregar el panel de colección**

Después del bloque de creación de `plotsContainer` (líneas 114-120 actuales, termina en `plotsContainer.Parent = screenGui`), agregar:

```lua
local COLLECTION_HEADER_POSITION = UDim2.new(0, 300, 0, 205)
local COLLECTION_HEADER_SIZE = UDim2.new(0, 260, 0, 20)
local COLLECTION_CONTAINER_POSITION = UDim2.new(0, 300, 0, 230)
local COLLECTION_ENTRY_HEIGHT = 26

local collectionHeaderLabel = createLabel(screenGui, "CollectionHeader", COLLECTION_HEADER_POSITION, COLLECTION_HEADER_SIZE, "Colección")
collectionHeaderLabel.BackgroundTransparency = 1
collectionHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left

local collectionContainer = Instance.new("Frame")
collectionContainer.Name = "CollectionContainer"
collectionContainer.Position = COLLECTION_CONTAINER_POSITION
collectionContainer.Size = UDim2.new(0, 260, 0, 0)
collectionContainer.AutomaticSize = Enum.AutomaticSize.Y
collectionContainer.BackgroundTransparency = 1
collectionContainer.Parent = screenGui
```

(Posicionado a la derecha del panel de parcelas existente, mismo alto que `PLOTS_HEADER_POSITION`, para no superponerse.)

Luego, antes de la definición de `refreshUI` (línea 220 actual), agregar la función que reconstruye la lista:

```lua
-- Reconstruye la lista de criaturas coleccionadas a partir del inventario.
-- Se recrea completa en cada refresh (como máximo 10 entradas hoy; sin
-- costo perceptible al pollear cada POLL_INTERVAL_SECONDS).
local function refreshCollection(inventory: { [string]: number })
	for _, child in ipairs(collectionContainer:GetChildren()) do
		child:Destroy()
	end

	local row = 0
	for creatureId, creature in pairs(Creatures) do
		local count = inventory[creatureId] or 0
		if count > 0 then
			local rarity = Rarities[creature.Rarity]
			local entry = createLabel(
				collectionContainer,
				creatureId,
				UDim2.new(0, 0, 0, row * COLLECTION_ENTRY_HEIGHT),
				UDim2.new(1, 0, 0, COLLECTION_ENTRY_HEIGHT - 2),
				("%s (%s) x%d"):format(creature.Name, rarity.DisplayName, count)
			)
			entry.TextColor3 = rarity.Color
			entry.TextXAlignment = Enum.TextXAlignment.Left
			row += 1
		end
	end
end
```

Finalmente, en `refreshUI` (líneas 220-253 actuales), la línea:

```lua
	inventoryLabel.Text = ("Semillas: %d"):format(state.Inventory[BASIC_SEED_ID] or 0)
```

Agregar inmediatamente después:

```lua
	refreshCollection(state.Inventory)
```

- [ ] **Step 5: Verificar en Studio**

Con el proyecto sincronizado y Play Solo activo: comprar/plantar/cosechar `BasicSeed` repetidamente (usando `!coins 500` y `!seed 20` para tener margen). Confirmar:
1. El mensaje de estado muestra `"¡Cosecha exitosa! +N coins"` siempre.
2. Cuando toca criatura, el mensaje agrega `"· ¡Obtuviste: <Nombre> (<Rareza>)!"` y cambia de color según la rareza.
3. El panel "Colección" (a la derecha del panel de parcelas) muestra cada criatura obtenida con su nombre, rareza y cantidad, y se actualiza dentro de los `POLL_INTERVAL_SECONDS` (2s) siguientes a la cosecha.

Expected: los 3 puntos se cumplen sin warnings nuevos en el Output.

- [ ] **Step 6: Commit**

```bash
git add src/StarterPlayer/StarterPlayerScripts/Client.client.lua
git commit -m "feat: show creature reward on harvest and add collection panel"
git push origin main
```
