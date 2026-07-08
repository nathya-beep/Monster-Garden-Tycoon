# Diseño: Pulido del MVP (parcelas extra, UI, sonido)

## Contexto

El MVP funciona de punta a punta (comprar semilla → plantar → crecer → cosechar → coins), validado en Studio. Esta fase pule tres puntos del MVP actual sin tocar la lógica de negocio del servidor:

1. Solo existe una parcela física (`Workspace.Plots.Plot1`).
2. La UI del cliente (`Client.client.lua`) usa rectángulos planos sin estilo.
3. No hay feedback de sonido en ninguna acción.

No hay assets (imágenes/sonidos) subidos a Roblox todavía — este pulido no depende de ellos.

## Alcance

- Agregar 2 parcelas físicas más (`Plot2`, `Plot3`) vía `default.project.json`, mismo patrón que `Plot1`.
- Introducir `ReplicatedStorage/Shared/UI/Theme.lua`: paleta pastel/jardín + constantes de estilo (radio de esquina, etc.).
- Aplicar el theme en `Client.client.lua`: `UICorner`, `UIStroke` sutil, feedback de hover/click con `TweenService`.
- Introducir `ReplicatedStorage/Shared/Config/Sounds.lua`: IDs placeholder (`AssetId = 0`, patrón ya usado en `Monetization.lua`) para `BuySeed`, `PlantSeed`, `HarvestSuccess`, `ActionError`.
- Agregar un helper `playSound(key)` en `Client.client.lua` que solo reproduce sonido si el ID está configurado (>0).

Fuera de alcance: subir assets reales, modularizar la UI en múltiples archivos, animaciones complejas, trading, monetización real.

## Diseño

### 1. Parcelas adicionales

`default.project.json` gana `Plot2` y `Plot3` dentro de `Workspace.Plots`, con la misma estructura que `Plot1` (`Model` con atributo `Owner = 0`, hijos `Ground` y `SpawnPoint`), separadas 30 studs entre sí en el eje Z (`Plot1` en z=30, `Plot2` en z=60, `Plot3` en z=90) para no superponerse.

No se requieren cambios de código: `PlotService.findFreePlot()` ya itera `Workspace.Plots:GetChildren()` buscando cualquier `Model` con `Owner == 0`, sin importar cuántos haya.

### 2. Tema visual (`Theme.lua`)

Nuevo módulo `ReplicatedStorage/Shared/UI/Theme.lua`, config estática (mismo espíritu que `Config/Economy.lua`):

```lua
Theme.Colors = {
  Background = Color3...,   -- crema suave
  Panel = Color3...,        -- verde pastel
  PanelAccent = Color3...,  -- verde pastel más oscuro (botones)
  Text = Color3...,
  TextMuted = Color3...,
  Success = Color3...,      -- feedback positivo
  Error = Color3...,        -- feedback negativo
}
Theme.CornerRadius = UDim.new(0, 12)
Theme.HoverBrightenFactor = ...
```

`Client.client.lua` actualiza `createLabel`/`createButton`:
- Aplican `UICorner` con `Theme.CornerRadius`.
- Aplican `UIStroke` sutil (borde semitransparente).
- Los botones agregan `MouseEnter`/`MouseLeave` (cambio de color) y `MouseButton1Down`/`Up` (tween de escala leve, ~0.95x) usando `TweenService`.
- Los colores hardcodeados actuales (`Color3.fromRGB(20,20,20)`, `Color3.fromRGB(60,140,60)`, etc.) se reemplazan por referencias a `Theme.Colors`.

El `statusLabel` (mensajes de feedback) usa `Theme.Colors.Success` o `Theme.Colors.Error` según el resultado de la acción, en vez del color amarillo fijo actual.

### 3. Sonido (`Sounds.lua` + helper)

Nuevo módulo `ReplicatedStorage/Shared/Config/Sounds.lua`, mismo patrón que `Monetization.lua`:

```lua
export type SoundDefinition = { AssetId: number }

Sounds.BuySeed = { AssetId = 0 }
Sounds.PlantSeed = { AssetId = 0 }
Sounds.HarvestSuccess = { AssetId = 0 }
Sounds.ActionError = { AssetId = 0 }
```

En `Client.client.lua`, un helper local:

```lua
local function playSound(key: string)
  local def = Sounds[key]
  if not def or def.AssetId <= 0 then
    return -- no configurado todavía, no rompe nada
  end
  local sound = Instance.new("Sound")
  sound.SoundId = "rbxassetid://" .. def.AssetId
  sound.Parent = SoundService
  sound.Ended:Connect(function() sound:Destroy() end)
  sound:Play()
end
```

Se llama en los 4 puntos de feedback existentes: al comprar semilla (éxito → `BuySeed`, fallo → `ActionError`), al plantar (`PlantSeed` / `ActionError`), al cosechar (`HarvestSuccess` / `ActionError`).

## Testing

Repetir manualmente el flujo del paso 1 (comprar → plantar → esperar → cosechar) en Studio vía Rojo, confirmando:
- Las 3 parcelas existen y son asignables (verificable inspeccionando `Workspace.Plots` en el Explorer).
- La UI se ve con el nuevo estilo (esquinas redondeadas, colores pastel, hover/click responden).
- Ninguna acción tira error por los sonidos sin configurar (deben ignorarse en silencio).

No se agregan tests automatizados — el proyecto no tiene infraestructura de testing automatizado para Luau todavía; la validación es manual en Studio, consistente con cómo se validó el MVP original.
