# MVP Polish (parcelas extra, tema visual, sonido) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pulir el MVP de Monster Garden Tycoon agregando 2 parcelas físicas más, un tema visual pastel/jardín reutilizable, y feedback de sonido con placeholders, sin tocar la lógica de negocio del servidor.

**Architecture:** Roblox/Luau, sincronizado a Studio vía Rojo (`rojo serve` corriendo en `C:\Users\17868\Monster-Garden-Tycoon`, puerto 34872). El árbol de instancias vive en `default.project.json`; el código vive en `src/`. No hay infraestructura de testing automatizado para Luau en este proyecto — la verificación es manual en Studio (Play) más verificación objetiva vía la API HTTP de Rojo (`curl http://localhost:34872/api/read/<rootInstanceId>`) para confirmar que cada archivo sincronizó antes de pasar a la siguiente tarea.

**Tech Stack:** Luau, Rojo 7.6.1, Roblox Studio (TweenService, UICorner, UIStroke, SoundService).

## Global Constraints

- No hay assets (imágenes/sonidos) subidos a Roblox todavía — los sonidos usan `AssetId = 0` como placeholder (mismo patrón que `src/ReplicatedStorage/Shared/Config/Monetization.lua`).
- Luau NO permite anotaciones de tipo en asignaciones a campos de tabla (`Tabla.Campo: Tipo = {...}` es un error de sintaxis) — solo en declaraciones `local`. Ya causó un bug real en `Monetization.lua` (corregido); no repetirlo en `Theme.lua`/`Sounds.lua`.
- `default.project.json` no recarga en caliente — cualquier cambio a ese archivo requiere reiniciar `rojo serve` (matar el proceso y volver a correr `rojo serve` en `C:\Users\17868\Monster-Garden-Tycoon`) y reconectar el plugin de Rojo en Studio (Disconnect → Connect).
- Los archivos de código (`.lua` bajo `src/`) sí sincronizan en caliente sin reiniciar el servidor.
- Estilo de comentarios del proyecto: solo cuando explican el *por qué*, no el qué (ver convención existente en `DataService.lua`, `PlotService.lua`).

---

### Task 1: Parcelas físicas adicionales (Plot2, Plot3)

**Files:**
- Modify: `default.project.json`

**Interfaces:**
- Consumes: nada de tareas anteriores.
- Produces: `Workspace.Plots.Plot2` y `Workspace.Plots.Plot3`, mismo shape que `Plot1` (`Model` con atributo `Owner = 0`, hijos `Ground` y `SpawnPoint` con propiedad `Position`). `PlotService.findFreePlot()` (`src/ServerScriptService/Server/Services/PlotService.lua`) ya itera `Workspace.Plots:GetChildren()` sin cambios de código — las tareas siguientes no dependen de esto, es independiente.

- [ ] **Step 1: Leer el `default.project.json` actual**

Confirmar el bloque `Workspace.Plots.Plot1` existente antes de editar (para no romper el patrón):

```json
"Workspace": {
  "$className": "Workspace",
  "Plots": {
    "$className": "Folder",
    "Plot1": {
      "$className": "Model",
      "$attributes": { "Owner": 0 },
      "Ground": {
        "$className": "Part",
        "$properties": {
          "Anchored": true,
          "CanCollide": true,
          "Material": "Grass",
          "Color": [0.42, 0.71, 0.35],
          "Size": [24, 1, 24],
          "Position": [0, 0.5, 30]
        }
      },
      "SpawnPoint": {
        "$className": "Part",
        "$properties": {
          "Anchored": true,
          "CanCollide": false,
          "Transparency": 1,
          "Size": [4, 1, 4],
          "Position": [0, 1.5, 30]
        }
      }
    }
  }
}
```

- [ ] **Step 2: Agregar `Plot2` y `Plot3` dentro de `Workspace.Plots`, junto a `Plot1`**

Insertar estos dos bloques como hermanos de `"Plot1": { ... }` (separados por coma), con el mismo shape pero `z = 60` para `Plot2` y `z = 90` para `Plot3` (30 studs de separación, mismo `x = 0`):

```json
    "Plot2": {
      "$className": "Model",
      "$attributes": { "Owner": 0 },
      "Ground": {
        "$className": "Part",
        "$properties": {
          "Anchored": true,
          "CanCollide": true,
          "Material": "Grass",
          "Color": [0.42, 0.71, 0.35],
          "Size": [24, 1, 24],
          "Position": [0, 0.5, 60]
        }
      },
      "SpawnPoint": {
        "$className": "Part",
        "$properties": {
          "Anchored": true,
          "CanCollide": false,
          "Transparency": 1,
          "Size": [4, 1, 4],
          "Position": [0, 1.5, 60]
        }
      }
    },
    "Plot3": {
      "$className": "Model",
      "$attributes": { "Owner": 0 },
      "Ground": {
        "$className": "Part",
        "$properties": {
          "Anchored": true,
          "CanCollide": true,
          "Material": "Grass",
          "Color": [0.42, 0.71, 0.35],
          "Size": [24, 1, 24],
          "Position": [0, 0.5, 90]
        }
      },
      "SpawnPoint": {
        "$className": "Part",
        "$properties": {
          "Anchored": true,
          "CanCollide": false,
          "Transparency": 1,
          "Size": [4, 1, 4],
          "Position": [0, 1.5, 90]
        }
      }
    }
```

- [ ] **Step 3: Validar el JSON**

Run: `python -c "import json; json.load(open('C:/Users/17868/Monster-Garden-Tycoon/default.project.json'))" && echo VALID`
Expected: `VALID` (jq no está instalado en este entorno, usar python como fallback)

- [ ] **Step 4: Reiniciar `rojo serve` (requerido porque cambió `default.project.json`)**

Matar el proceso `rojo serve` anterior y volver a levantarlo en `C:\Users\17868\Monster-Garden-Tycoon`.

- [ ] **Step 5: Confirmar vía la API de Rojo que Plot2 y Plot3 sincronizaron**

Run: `curl -s http://localhost:34872/api/rojo` para obtener el `rootInstanceId` nuevo, luego:
`curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o '"Name":"Plot2"\|"Name":"Plot3"'`
Expected: ambas líneas aparecen.

- [ ] **Step 6: Commit**

```bash
git add default.project.json
git commit -m "feat: add Plot2 and Plot3 physical plots"
```

---

### Task 2: Módulo de tema visual (`Theme.lua`)

**Files:**
- Create: `src/ReplicatedStorage/Shared/UI/Theme.lua`

**Interfaces:**
- Consumes: nada.
- Produces: tabla `Theme` con campos `Theme.Colors` (`Background`, `Panel`, `PanelAccent`, `PanelAccentHover`, `Text`, `Success`, `Error`, todos `Color3`), `Theme.CornerRadius` (`UDim`), `Theme.StrokeColor` (`Color3`), `Theme.StrokeTransparency` (`number`), `Theme.HoverTweenSeconds` (`number`), `Theme.PressScale` (`number`). Tareas 4 y 5 (`Client.client.lua`) consumen todos estos campos por nombre exacto.

- [ ] **Step 1: Crear `src/ReplicatedStorage/Shared/UI/Theme.lua`**

```lua
-- Theme.lua
-- Paleta visual pastel/jardín y constantes de estilo compartidas por la UI
-- del cliente. Config estática, mismo espíritu que Config/Economy.lua.

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(250, 245, 230), -- crema suave
	Panel = Color3.fromRGB(214, 234, 202), -- verde pastel
	PanelAccent = Color3.fromRGB(122, 178, 105), -- verde pastel más oscuro (botones)
	PanelAccentHover = Color3.fromRGB(140, 196, 122),
	Text = Color3.fromRGB(58, 74, 51),
	Success = Color3.fromRGB(76, 153, 76),
	Error = Color3.fromRGB(196, 92, 92),
}

Theme.CornerRadius = UDim.new(0, 12)
Theme.StrokeColor = Color3.fromRGB(58, 74, 51)
Theme.StrokeTransparency = 0.7
Theme.HoverTweenSeconds = 0.12
Theme.PressScale = 0.95

return Theme
```

- [ ] **Step 2: Confirmar vía la API de Rojo que el archivo sincronizó**

Run: `curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o "Paleta visual pastel"`
Expected: aparece la línea (confirma que el `Source` del `ModuleScript` llegó al árbol de Rojo).

- [ ] **Step 3: Commit**

```bash
git add src/ReplicatedStorage/Shared/UI/Theme.lua
git commit -m "feat: add pastel garden UI theme module"
```

---

### Task 3: Módulo de sonidos (`Sounds.lua`)

**Files:**
- Create: `src/ReplicatedStorage/Shared/Config/Sounds.lua`

**Interfaces:**
- Consumes: nada.
- Produces: tabla `Sounds` con `Sounds.BuySeed`, `Sounds.PlantSeed`, `Sounds.HarvestSuccess`, `Sounds.ActionError`, cada uno `{ AssetId: number }` con `AssetId = 0` (no configurado). Tarea 5 (`Client.client.lua`) consume estas 4 claves por nombre exacto vía `playSound(key)`.

- [ ] **Step 1: Crear `src/ReplicatedStorage/Shared/Config/Sounds.lua`**

```lua
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
```

- [ ] **Step 2: Confirmar vía la API de Rojo que el archivo sincronizó**

Run: `curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o "Sounds.BuySeed"`
Expected: aparece la línea.

- [ ] **Step 3: Commit**

```bash
git add src/ReplicatedStorage/Shared/Config/Sounds.lua
git commit -m "feat: add sound config placeholders"
```

---

### Task 4: Aplicar el tema a `createLabel`/`createButton` en `Client.client.lua`

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/Client.client.lua`

**Interfaces:**
- Consumes: `Theme.Colors`, `Theme.CornerRadius`, `Theme.StrokeColor`, `Theme.StrokeTransparency`, `Theme.HoverTweenSeconds`, `Theme.PressScale` de la Tarea 2.
- Produces: `createLabel` y `createButton` con la misma firma que antes (sin cambios de tipo), ahora con `UICorner`/`UIStroke` y, en botones, hover/press animado. Tarea 5 no depende de esto (son cambios independientes al mismo archivo), pero se hacen en el mismo orden para minimizar conflictos de edición.

- [ ] **Step 1: Agregar los `require` de `Theme` y los servicios nuevos**

En `src/StarterPlayer/StarterPlayerScripts/Client.client.lua`, reemplazar:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Crops = require(ReplicatedStorage.Shared.Config.Crops)
```

por:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Crops = require(ReplicatedStorage.Shared.Config.Crops)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
```

- [ ] **Step 2: Actualizar `createLabel` para usar el tema**

Reemplazar:

```lua
local function createLabel(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = parent
	return label
end
```

por:

```lua
local function createLabel(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundColor3 = Theme.Colors.Panel
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Theme.Colors.Text
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.StrokeColor
	stroke.Transparency = Theme.StrokeTransparency
	stroke.Parent = label

	return label
end
```

- [ ] **Step 3: Actualizar `createButton` para usar el tema y agregar hover/press**

Reemplazar:

```lua
local function createButton(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent
	return button
end
```

por:

```lua
local function createButton(parent: Instance, name: string, position: UDim2, size: UDim2, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Theme.Colors.PanelAccent
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.AutoButtonColor = false
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.StrokeColor
	stroke.Transparency = Theme.StrokeTransparency
	stroke.Parent = button

	local baseSize = size
	local hoverTweenInfo = TweenInfo.new(Theme.HoverTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, hoverTweenInfo, { BackgroundColor3 = Theme.Colors.PanelAccentHover }):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, hoverTweenInfo, { BackgroundColor3 = Theme.Colors.PanelAccent }):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, hoverTweenInfo, {
			Size = UDim2.new(
				baseSize.X.Scale,
				baseSize.X.Offset * Theme.PressScale,
				baseSize.Y.Scale,
				baseSize.Y.Offset * Theme.PressScale
			),
		}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, hoverTweenInfo, { Size = baseSize }):Play()
	end)

	return button
end
```

- [ ] **Step 4: Quitar el color fijo del `statusLabel` (ahora lo controla la Tarea 5)**

Reemplazar:

```lua
local statusLabel = createLabel(screenGui, "StatusLabel", UDim2.new(0.5, -200, 0, 20), UDim2.new(0, 400, 0, 40), "")
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
statusLabel.Visible = false
```

por:

```lua
local statusLabel = createLabel(screenGui, "StatusLabel", UDim2.new(0.5, -200, 0, 20), UDim2.new(0, 400, 0, 40), "")
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Visible = false
```

- [ ] **Step 5: Confirmar vía la API de Rojo que el archivo sincronizó**

Run: `curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o "PanelAccentHover"`
Expected: aparece la línea.

- [ ] **Step 6: Commit**

```bash
git add src/StarterPlayer/StarterPlayerScripts/Client.client.lua
git commit -m "feat: apply pastel garden theme to UI labels and buttons"
```

---

### Task 5: Feedback de sonido en las 4 acciones (`Client.client.lua`)

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/Client.client.lua`

**Interfaces:**
- Consumes: `Sounds.BuySeed`, `Sounds.PlantSeed`, `Sounds.HarvestSuccess`, `Sounds.ActionError` de la Tarea 3; `SoundService` (ya importado en la Tarea 4, Step 1).
- Produces: función local `playSound(key: string)`; `showStatus` gana un segundo parámetro `kind: string?` (`"Success"` o `"Error"`, controla el color del texto vía `Theme.Colors.Success`/`Theme.Colors.Error`).

- [ ] **Step 1: Actualizar `showStatus` para colorear según éxito/error, y agregar `playSound`**

Reemplazar:

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

por:

```lua
local function showStatus(message: string, kind: string?)
	statusLabel.Text = message
	statusLabel.TextColor3 = (kind == "Error") and Theme.Colors.Error or Theme.Colors.Success
	statusLabel.Visible = true
	task.delay(STATUS_MESSAGE_SECONDS, function()
		if statusLabel.Text == message then
			statusLabel.Visible = false
		end
	end)
end

local function playSound(key: string)
	local definition = Sounds[key]
	if not definition or definition.AssetId <= 0 then
		return -- no configurado todavía, no rompe nada
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. definition.AssetId
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end
```

- [ ] **Step 2: Cablear sonido en `requestPlantSeed`**

Reemplazar:

```lua
local function requestPlantSeed(slotIndex: number)
	local ok, result = pcall(function()
		return plantSeedRemote:InvokeServer(BASIC_SEED_ID, slotIndex)
	end)

	showStatus(ok and result.Success and "¡Semilla plantada!" or describeReason(ok and result.Reason))
	fetchState()
end
```

por:

```lua
local function requestPlantSeed(slotIndex: number)
	local ok, result = pcall(function()
		return plantSeedRemote:InvokeServer(BASIC_SEED_ID, slotIndex)
	end)

	if ok and result.Success then
		showStatus("¡Semilla plantada!", "Success")
		playSound("PlantSeed")
	else
		showStatus(describeReason(ok and result.Reason), "Error")
		playSound("ActionError")
	end

	fetchState()
end
```

- [ ] **Step 3: Cablear sonido en `requestHarvest`**

Reemplazar:

```lua
local function requestHarvest(slotIndex: number)
	local ok, result = pcall(function()
		return harvestRemote:InvokeServer(slotIndex)
	end)

	showStatus(ok and result.Success and "¡Cosecha exitosa!" or describeReason(ok and result.Reason))
	fetchState()
end
```

por:

```lua
local function requestHarvest(slotIndex: number)
	local ok, result = pcall(function()
		return harvestRemote:InvokeServer(slotIndex)
	end)

	if ok and result.Success then
		showStatus("¡Cosecha exitosa!", "Success")
		playSound("HarvestSuccess")
	else
		showStatus(describeReason(ok and result.Reason), "Error")
		playSound("ActionError")
	end

	fetchState()
end
```

- [ ] **Step 4: Cablear sonido en el handler de `buySeedButton`**

Reemplazar:

```lua
buySeedButton.MouseButton1Click:Connect(function()
	local ok, result = pcall(function()
		return buySeedRemote:InvokeServer(BASIC_SEED_ID)
	end)

	showStatus(ok and result.Success and "¡Semilla comprada!" or describeReason(ok and result.Reason))
	fetchState()
end)
```

por:

```lua
buySeedButton.MouseButton1Click:Connect(function()
	local ok, result = pcall(function()
		return buySeedRemote:InvokeServer(BASIC_SEED_ID)
	end)

	if ok and result.Success then
		showStatus("¡Semilla comprada!", "Success")
		playSound("BuySeed")
	else
		showStatus(describeReason(ok and result.Reason), "Error")
		playSound("ActionError")
	end

	fetchState()
end)
```

- [ ] **Step 5: Confirmar vía la API de Rojo que el archivo sincronizó**

Run: `curl -s http://localhost:34872/api/read/<rootInstanceId> | grep -o "playSound"`
Expected: aparecen varias líneas (definición + 3 llamadas).

- [ ] **Step 6: Commit**

```bash
git add src/StarterPlayer/StarterPlayerScripts/Client.client.lua
git commit -m "feat: wire sound feedback into buy/plant/harvest actions"
```

---

### Task 6: Verificación manual end-to-end en Studio

**Files:** ninguno (solo verificación).

**Interfaces:**
- Consumes: todo lo de las Tareas 1-5.
- Produces: confirmación de que el pulido no rompió el flujo del MVP.

- [ ] **Step 1: Reconectar el plugin de Rojo en Studio**

En el panel del plugin: Disconnect → Connect (el servidor se reinició en la Tarea 1, Step 4).

- [ ] **Step 2: Dale Play y confirmar en el Output**

Esperado en el Output (sin errores en rojo):
```
[Main] Monster Garden Tycoon iniciando...
[Main] Todos los servicios inicializados.
[Client] Monster Garden Tycoon - UI inicializada.
```

- [ ] **Step 3: Confirmar visualmente el tema**

Los paneles de Coins/Tienda/Parcelas deben verse con esquinas redondeadas, fondo verde pastel/crema, y los botones deben cambiar de tono al pasar el mouse y achicarse levemente al hacer click.

- [ ] **Step 4: Confirmar las 3 parcelas**

Inspeccionar `Workspace.Plots` en el Explorer: deben existir `Plot1`, `Plot2`, `Plot3`.

- [ ] **Step 5: Repetir el flujo comprar → plantar → esperar → cosechar**

Confirmar que el mensaje de estado aparece en verde (`Theme.Colors.Success`) en éxito y en rojo (`Theme.Colors.Error`) en fallo, y que ninguna acción tira error en el Output por los sonidos sin configurar (deben ignorarse en silencio, `AssetId = 0`).

- [ ] **Step 6: Commit final (si hubo ajustes manuales)**

Solo si Step 1-5 requirió tocar algún archivo por un bug encontrado durante la verificación:

```bash
git add -A
git commit -m "fix: address issues found during MVP polish verification"
```
