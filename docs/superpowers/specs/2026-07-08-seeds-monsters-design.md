# Diseño: Sistema de Semillas y Monstruos (ciclo 1 — Común/Poco Común)

## Contexto

`docs/GAME_DESIGN.md` (secciones 5, 6, 16 y 21 ítems 1-2) define un sistema completo de 7 rarezas de semillas/monstruos. Ese diseño es demasiado grande para un solo ciclo de implementación, y las 5 rarezas superiores (rara+) requieren zonas del mapa que todavía no existen (Bosque de monstruos, Cueva de cristales, etc.). Este ciclo cubre únicamente **Común + Poco Común**, las dos rarezas jugables en el Jardín inicial (la única zona construida hoy).

Estado actual antes de este cambio:
- `ReplicatedStorage/Shared/Config/Crops.lua` define una sola semilla (`BasicSeed`: 25 coins, 60s, `HarvestReward = 15`) — nótese que hoy la cosecha da **pérdida neta** (25 costo, 15 recompensa), contradiciendo el piso de 40 coins de valor definido en el diseño general.
- No existe ningún concepto de "monstruo" en los datos del jugador (`DataService.PlayerData` solo tiene `Coins`, `Inventory`, `Plots`).
- `GrowthService.handleHarvest` da coins directas únicamente; `EconomyService.handleBuySeed` ya es genérico por `seedId` (no hace falta tocarlo más que el nombre del require).

## Alcance

Incluye:
- Renombrar `Crops.lua` → `Seeds.lua`, extendido con `Rarity`, `HarvestCoins` y `MonsterTable`.
- Nuevo `Monsters.lua`: registro independiente de definiciones de monstruo (reusable a futuro por objetos rompibles y otras semillas).
- Nuevo `MonsterService.lua`: resuelve el roll de probabilidad al cosechar y guarda la instancia del monstruo obtenido.
- Extender `DataService.PlayerData` con `Monsters: { [instanceId]: MonsterInstance }`.
- Extender `GrowthService.handleHarvest` para otorgar coins + monstruo, y devolver el monstruo obtenido en el `ActionResult`.
- Agregar la semilla `UncommonSeed` (Poco Común) y sus monstruos asociados.

Fuera de alcance (ciclos futuros):
- Semillas Rara/Épica/Legendaria/Mítica/Secreta (bloqueadas por falta de zonas).
- Vender/equipar monstruos como mascotas (`PetService`) — este ciclo solo los guarda con su `SellValue` calculado, sin remote de venta ni UI.
- Cualquier UI nueva (pantalla de mascotas, inventario visual de monstruos) — queda para el ciclo de UI.
- Poderes del jugador, objetos rompibles, misiones — ciclos separados según `docs/GAME_DESIGN.md` sección 21.

## Diseño

### 1. `ReplicatedStorage/Shared/Config/Seeds.lua` (reemplaza `Crops.lua`)

```lua
export type SeedDefinition = {
	Id: string,
	Name: string,
	Rarity: "Common" | "Uncommon",
	Price: number,            -- costo en coins para comprarla en la tienda
	GrowSeconds: number,      -- tiempo de crecimiento una vez plantada
	HarvestCoins: number,     -- coins directas que da al cosechar
	MonsterTable: { { MonsterId: string, Chance: number } }, -- Chance suma 1.0
}
```

| Id | Rarity | Price | GrowSeconds | HarvestCoins | MonsterTable |
|---|---|---|---|---|---|
| `BasicSeed` | Common | 25 | 60 | 10 | 70% `SlimeBasic`, 30% `MushlingBasic` |
| `UncommonSeed` | Uncommon | 100 | 180 | 40 | 55% `MushlingBasic`, 40% `CrystalPup`, 5% `SlimeBasic` |

Valor esperado total (coins directas + valor esperado de venta del monstruo obtenido):
- `BasicSeed`: 10 + (0.70×30 + 0.30×35) = 10 + 31.5 = **41.5** (piso de diseño: 40).
- `UncommonSeed`: 40 + (0.55×35 + 0.40×250 + 0.05×30) = 40 + 120.75 = **160.75** (piso de diseño: 160).

### 2. `ReplicatedStorage/Shared/Config/Monsters.lua` (nuevo)

```lua
export type MonsterDefinition = {
	Id: string,
	Name: string,
	Rarity: string,
	SellValue: number, -- coins que daría vender este monstruo (venta real: ciclo futuro)
}
```

| Id | Name | Rarity | SellValue |
|---|---|---|---|
| `SlimeBasic` | Slime Básico | Common | 30 |
| `MushlingBasic` | Hongomonstruo Básico | Common | 35 |
| `CrystalPup` | Cristalito | Uncommon | 250 |

### 3. `ServerScriptService/Server/Services/MonsterService.lua` (nuevo)

Mismo patrón que `InventoryService`: no tiene estado propio, todo vive en `DataService`.

```lua
export type MonsterInstance = {
	InstanceId: string, -- HttpService:GenerateGUID(false), mismo patrón que TradeService
	MonsterId: string,
	Rarity: string,
	SellValue: number,
	HarvestedAt: number, -- os.time()
}

function MonsterService.RollMonster(seedId: string): string?
-- Busca Seeds[seedId].MonsterTable, tira un random 0-1 contra las Chance
-- acumuladas, devuelve el MonsterId elegido. nil si la semilla no existe
-- o su MonsterTable está vacía/mal configurada (nunca tira error).

function MonsterService.GrantMonster(player: Player, monsterId: string): MonsterInstance?
-- Busca Monsters[monsterId]; si no existe, warn + devuelve nil (no bloquea
-- al caller). Si existe, crea la instancia, la guarda en
-- data.Monsters[instance.InstanceId], la devuelve.

function MonsterService.GetSnapshot(player: Player): { [string]: MonsterInstance }
-- Copia de solo lectura (mismo patrón que InventoryService.GetSnapshot),
-- para que UI/PetService futuros no puedan mutar el estado real.

function MonsterService.Init()
-- Sin estado propio que inicializar: todo vive en DataService.
```

### 4. `DataService.lua`

- `PlayerData` gana el campo `Monsters: { [string]: MonsterInstance }`.
- `getDefaultData()` gana `Monsters = {}`.
- `fillMissingFields` ya rellena recursivamente los campos nuevos en saves viejos — sin necesidad de una función de migración dedicada (a diferencia de `migrateLegacyPlot`, que resuelve un cambio de *forma*, no solo un campo nuevo).

### 5. `GrowthService.lua`

- Cambia el require `Crops` → `Seeds` en todo el archivo.
- `handleHarvest`: el `reward` pasa a leer `seed.HarvestCoins` (antes `crop.HarvestReward`), con los mismos bonus `DoubleCoins`/`VipGarden` de hoy aplicados igual.
- Después de acreditar coins y limpiar el slot, llama `MonsterService.RollMonster(seed.Id)` → si devuelve un `MonsterId`, llama `MonsterService.GrantMonster(player, monsterId)`.
- `ActionResult` (solo para el caso de harvest) gana un campo opcional `Monster: MonsterInstance?`, para que el cliente pueda mostrar "conseguiste un X" a futuro (sin implementar esa UI en este ciclo — el campo queda disponible).
- Si `RollMonster` o `GrantMonster` devuelven `nil` (config vacía/corrupta, o datos no cargados en el instante exacto de cosechar), la cosecha **igual se considera exitosa** con las coins ya acreditadas — solo se loguea un `warn`. Nunca se bloquea al jugador por un problema de datos de monstruos.

### 6. `EconomyService.lua`

- Único cambio: el require `Crops` → `Seeds`. `handleBuySeed` ya es genérico por `seedId`, así que `UncommonSeed` queda comprable automáticamente en el backend en cuanto existe en `Seeds.lua` (la UI de tienda para elegirla es trabajo de un ciclo de UI futuro).

## Testing

Verificación manual en Studio (no hay entorno de tests automatizados en este proyecto):
1. Plantar `BasicSeed`, esperar a que esté lista, cosechar → confirmar coins recibidas = 10 (+ bonus de gamepass si aplica) y que aparece una entrada nueva en `data.Monsters` (vía `execute_luau` inspeccionando `DataService.Get(player).Monsters`, o un print de debug temporal).
2. Repetir con `UncommonSeed`, obtenida vía comando admin (`AdminService`) ya que la tienda actual no tiene UI para elegir semilla distinta de `BasicSeed`.
3. Confirmar que un save existente (jugador con datos previos sin campo `Monsters`) carga sin error y termina con `Monsters = {}` tras `fillMissingFields`.
4. Confirmar que `RollMonster` con una `MonsterTable` corrupta (ej. `Chance` que no suma 1.0) no rompe la cosecha — solo loguea warn y las coins igual se acreditan.
