# Sistema de Criaturas y Rareza — Diseño

**Fecha**: 2026-07-06
**Estado**: Aprobado, pendiente de plan de implementación

## Contexto

El MVP de Monster Garden Tycoon está completo funcionalmente (parcela, monedas, comprar/plantar/cosechar
`BasicSeed`, guardado/carga, UI básica, comandos admin). `Creatures.lua` y `Rarities.lua` existen como
archivos vacíos (`local X = {}; return X`) — son la base de la visión del juego ("desbloquear criaturas
raras") y aún no tienen ningún contenido ni lógica.

Este documento define cómo se integran las criaturas y su sistema de rareza al loop de cosecha existente.

## Decisiones de diseño (por qué)

1. **Cosecha da criatura + monedas** (no huevos separados, no solo eventos): la cosecha ya es el punto
   central del loop; añadirle una probabilidad de criatura no requiere nuevos remotos ni nueva UI de compra.
2. **5 niveles de rareza**: Common / Uncommon / Rare / Epic / Legendary.
3. **Probabilidad por semilla**: cada `CropDefinition` en `Crops.lua` define su propia tabla de pesos de
   rareza (`RarityWeights`), no una tabla global. Esto deja el sistema listo para cuando existan más semillas
   premium con mejores probabilidades, sin tocar la lógica de roll.
4. **Solo colección por ahora**: las criaturas obtenidas no tienen efecto de gameplay (sin bonus pasivo, sin
   venta). Se sienta la base de datos/persistencia sin acoplar mecánicas que no se han pedido (YAGNI).
5. **Reusar `InventoryService`**: las criaturas son ítems más del inventario genérico existente
   (`AddItem`/`RemoveItem`/`GetSnapshot`), distinguidas por su `Id` (ej. `"Sprout"`). Cero código nuevo de
   persistencia, cero migración de esquema en `DataService`.
6. **Feedback visible en UI**: mensaje temporal al cosechar + panel simple de colección, para que el sistema
   sea observable por el jugador desde el día uno.

## Arquitectura

### Enfoque elegido: módulo stateless `CreatureRoll.lua`

Se descartaron dos alternativas:
- **`CreatureService` con `Init()`**: ceremonia innecesaria — no hay estado ni remotos propios que
  gestionar todavía.
- **Lógica inline en `GrowthService`**: `GrowthService` ya es el módulo más grande/central del proyecto;
  añadir el roll ahí mezclaría responsabilidades (crecimiento vs. colección) y lo haría crecer más.

`CreatureRoll.lua` es un módulo puro (sin `Init()`, sin estado, sin remotos) ubicado junto a los demás
configs/lógica compartida. Expone una única función:

```lua
function CreatureRoll.Roll(seedId: string): string? -- retorna creatureId o nil
```

Sin efectos secundarios — fácil de testear en aislamiento corriendo muchas iteraciones y verificando que la
distribución observada se aproxima a los pesos configurados.

### Datos de configuración

**`Rarities.lua`** (reemplaza el archivo vacío actual):
```lua
{
  Common    = { DisplayName = "Común",      Color = Color3.fromRGB(...) },
  Uncommon  = { DisplayName = "Poco común",  Color = Color3.fromRGB(...) },
  Rare      = { DisplayName = "Raro",        Color = Color3.fromRGB(...) },
  Epic      = { DisplayName = "Épico",       Color = Color3.fromRGB(...) },
  Legendary = { DisplayName = "Legendario",  Color = Color3.fromRGB(...) },
}
```

**`Creatures.lua`** (reemplaza el archivo vacío actual) — 10 criaturas iniciales, 2 por rareza, tipadas:
```lua
export type CreatureDefinition = {
    Id: string,
    Name: string,
    Rarity: string, -- clave de Rarities.lua
}
```
Lista inicial (2 por rareza, 10 total):

| Id | Name | Rarity |
|---|---|---|
| `Sprout` | Sprout | Common |
| `Mossling` | Mossling | Common |
| `Thistlepup` | Thistlepup | Uncommon |
| `Petalfox` | Petalfox | Uncommon |
| `Duskbloom` | Duskbloom | Rare |
| `Glimmerhorn` | Glimmerhorn | Rare |
| `Emberpetal` | Emberpetal | Epic |
| `Frostvine` | Frostvine | Epic |
| `Aurelight` | Aurelight | Legendary |
| `Starblossom` | Starblossom | Legendary |

**`Crops.lua`** — `BasicSeed` gana el campo `RarityWeights` (pesos relativos, no necesitan sumar 100):
```lua
RarityWeights = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 }
```

### Lógica de roll

1. Buscar `Crops[seedId]`; si no existe o no tiene `RarityWeights`, retornar `nil` (backward-compatible con
   semillas futuras que no otorguen criaturas).
2. Elegir una rareza mediante selección ponderada (`weightedPick`) sobre `RarityWeights`.
3. Filtrar `Creatures.lua` a las criaturas de esa rareza. Si el pool está vacío, retornar `nil` (no debe
   romper la cosecha).
4. Elegir uniformemente una criatura del pool filtrado.

### Integración en `GrowthService.handleHarvest`

Después de calcular las monedas de cosecha (con los bonuses de `DoubleCoins`/`VipGarden` ya existentes):
1. Llamar `CreatureRoll.Roll(seedId)`.
2. Si retorna un `creatureId`, llamar `InventoryService.AddItem(player, creatureId, 1)`.
3. Extender la respuesta del remoto `Harvest`: `{ Success = true, Coins = n, CreatureObtained: string? }`.

No se toca el esquema de `DataService` — `Inventory` ya soporta ítems arbitrarios por Id sin migración.

### UI (`Client.client.lua`)

- Si `Harvest` devuelve `CreatureObtained`, el panel de mensajes temporales existente muestra:
  `"¡Cosechaste! +15 monedas · ¡Obtuviste: Sprout (Común)!"`, coloreado según `Rarities[rarity].Color`.
- Nuevo panel de "Colección": lista los creature IDs presentes en el snapshot de inventario (ya expuesto por
  `GetPlayerState`), mostrando nombre + rareza vía lookup en `Creatures.lua`/`Rarities.lua`. Texto plano, sin
  iconos/arte — consistente con el resto de la UI actual (código, no assets diseñados).

## Manejo de errores / edge cases

- Semilla sin `RarityWeights` → `Roll` retorna `nil`, cosecha funciona normal sin criatura.
- Rareza sorteada sin ninguna criatura definida en `Creatures.lua` → `Roll` retorna `nil`, mismo
  comportamiento.
- Todo el roll ocurre server-side dentro de `handleHarvest`, que ya está protegido por las validaciones
  existentes (SeedNotFound, NoPlot, InvalidSlot, PlotOccupied, SeedNotOwned, PlotEmpty, NotReady) — el
  cliente no puede influir en el resultado del roll.

## Testing

- Test aislado de `CreatureRoll.Roll`: miles de iteraciones, verificar que la distribución de rarezas
  observada se aproxima a los pesos configurados (tolerancia razonable).
- Test manual en Studio: cosechar repetidamente, confirmar que el inventario acumula criaturas correctamente
  y que la UI muestra el mensaje temporal y el panel de colección.

## Fuera de alcance (explícitamente, YAGNI)

- Bonus pasivo de monedas por criaturas coleccionadas.
- Venta de criaturas duplicadas.
- Pools de criaturas específicos por semilla (todas las semillas comparten el roster de `Creatures.lua`,
  solo cambian los pesos de rareza).
- Trading, raids, eventos — fuera de alcance del proyecto hasta completar el MVP pulido (regla existente de
  `CLAUDE.md`).
