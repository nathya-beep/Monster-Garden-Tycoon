# Monster Garden Tycoon — Propuesta de Diseño Completa

> Documento de diseño de referencia. No es un plan de implementación (para eso ver `docs/superpowers/plans/`) — es el mapa completo de mecánicas, economía y contenido contra el cual planificar features futuras. Se apoya en lo ya construido: `src/` (parcelas, siembra, crecimiento, cosecha, economía, inventario, trading), y el mundo (`docs/worldgen/`).

---

## 1. Resumen del juego

**Monster Garden Tycoon** es un tycoon/collector estilo "Grow a Garden" donde, en vez de vegetales, el jugador cultiva **semillas de monstruos**. Planta, espera, cosecha, y el resultado no es un ítem de venta sino una **mascota coleccionable** con rareza y habilidad propia. El loop combina jardinería idle, coleccionismo por rareza, progresión de poderes de personaje (mega salto, golpe de poder) y economía basada en romper objetos del mundo — todo diseñado para sesiones cortas repetidas y retención a largo plazo vía mascotas raras y zonas desbloqueables.

## 2. Público objetivo

- Edad principal: 8–14 años (línea con la base de Roblox y de "Grow a Garden"/"Pet Simulator").
- Perfil: jugadores de coleccionables/idle games, atraídos por rareza, sonidos satisfactorios y progresión visible.
- Sesión: mobile-first, partidas de 5–20 minutos, con razones para volver cada pocas horas (crecimiento de semillas, cofres, misiones diarias).

## 3. Gameplay loop

```
Ganar coins → Comprar semillas → Plantar → Esperar crecimiento → Cosechar monstruo
   → Equipar como mascota → Mascota ayuda a ganar más coins/romper objetos
   → Romper objetos del mapa → Mejorar jardín y poderes → Desbloquear zonas
   → Comprar semillas mejores → Repetir con recompensas mayores
```

El loop corto (plantar→cosechar) alimenta el loop largo (progresión de zonas y rareza). Las mascotas son el puente: cada cosecha mejora el loop corto siguiente.

## 4. Mecánicas principales

1. **Compra de semillas** — tienda con tabs por rareza; solo semillas ya desbloqueadas por zona son comprables.
2. **Plantación en parcelas** — click/tap en parcela vacía y propia → abre selector de semilla del inventario.
3. **Crecimiento por tiempo** — timer server-side por parcela (ya implementado en `GrowthService`), con barra de progreso visible sobre la parcela.
4. **Cosecha de monstruos** — al completarse el timer, la parcela muestra un ícono de "listo"; cosechar rueda la tabla de probabilidad de esa semilla y entrega monstruo + coins.
5. **Sistema de mascotas** — hasta N mascotas equipadas siguen al jugador, aplican sus habilidades pasivas simultáneamente.
6. **Sistema de rarezas** — 7 tiers (común → secreta), determina probabilidad, valor, VFX y color.
7. **Sistema de monedas (coins)** — única moneda soft; fuente: cosecha, romper objetos, misiones; sumidero: semillas, mejoras, tienda.
8. **Mejoras del jardín** — más parcelas, crecimiento más rápido, suerte de rareza, todo comprable con coins o Robux.
9. **Poderes del jugador** — mega salto y golpe de poder (detallados en sección 7).
10. **Destrucción de objetos** — rocas/cristales/cofres dispersos por el mapa dan coins/semillas/mascotas al romperlos a golpes.
11. **Monetización con Robux** — gamepasses permanentes + productos consumibles (boosts, coins, semillas premium).

## 5. Sistema de semillas

Estructura de datos por semilla (coincide con el patrón ya usado en `ReplicatedStorage/Shared/Config/*.lua`):

```lua
{
  Id = "seed_common_sprout",
  Name = "Semilla Brote Común",
  Rarity = "Common",
  Price = 25,               -- coins
  GrowTimeSeconds = 60,
  HarvestBaseValue = 40,    -- 25 costo + 15 ganancia neta mínima
  MonsterTable = {          -- probabilidad acumulada de qué monstruo sale
    { MonsterId = "slime_basic", Chance = 0.70 },
    { MonsterId = "mushling_basic", Chance = 0.30 },
  },
  SellValueRange = { Min = 10, Max = 60 },   -- si el jugador vende el monstruo en vez de quedárselo
  SpecialPowerChance = 0.05,                 -- probabilidad de que el monstruo tenga un poder bonus
}
```

| Rareza | Precio (coins) | Tiempo crecimiento | Valor cosecha base | Prob. combinada de tabla | Zona mínima |
|---|---|---|---|---|---|
| Común | 25 | 60 s | 40 | 100% monstruos comunes/poco comunes | Jardín inicial |
| Poco común | 100 | 3 min | 160 | 70% poco común / 25% raro / 5% común | Jardín inicial |
| Rara | 400 | 10 min | 650 | 60% raro / 30% épico / 10% poco común | Bosque de monstruos |
| Épica | 1,500 | 30 min | 2,400 | 55% épico / 35% legendario / 10% raro | Cueva de cristales |
| Legendaria | 6,000 | 90 min | 9,500 | 50% legendario / 40% mítico / 10% épico | Isla flotante |
| Mítica | 25,000 | 4 h | 40,000 | 60% mítico / 30% secreto / 10% legendario | Volcán mutante |
| Secreta | Solo por evento/cofre, no comprable con coins | 8 h | 150,000+ | 90% secreto / 10% mítico | Laboratorio secreto |

La regla base "25 coins → 40 coins de valor" se mantiene como **piso de progresión**: cada tier multiplica precio y valor manteniendo un margen neto de ~35-60% para que cosechar siempre se sienta rentable, pero el tiempo de espera creciente evita que sea infinito-idle sin esfuerzo.

## 6. Sistema de monstruos y mascotas

Cada monstruo cosechado es una instancia con: `MonsterId`, `Rarity`, `Level` (sube con duplicados/fusión), `Power` (una de las siguientes), `Nickname`.

**Habilidades posibles (una por monstruo, asignada por su tabla de probabilidad):**

| Habilidad | Efecto | Rareza típica |
|---|---|---|
| Coin Boost | +X% coins ganados (cosecha y objetos rotos) | Común → Legendaria (escala) |
| Growth Boost | -X% tiempo de crecimiento de semillas | Poco común → Mítica |
| Break Power | +X% velocidad/daño al romper objetos | Común → Épica |
| Speed Boost | +X% velocidad de movimiento | Común → Rara |
| Jump Boost | +X% altura de salto normal y mega salto | Poco común → Épica |
| Luck Boost | +X% probabilidad de rareza alta al cosechar | Rara → Secreta |
| Passive Coins | +N coins cada T segundos, pasivo, sin acción del jugador | Épica → Secreta |

**Equipamiento:** el jugador equipa hasta `MaxEquippedPets` mascotas simultáneas (base: 3; ampliable por progresión/gamepass hasta 8). Los efectos son aditivos (o multiplicativos suaves con diminishing returns para Coin/Luck Boost, para evitar estancamiento fuera de control).

## 7. Sistema de poderes del personaje

### Mega salto

- **Activación:** doble tap de barra espaciadora en menos de 300ms (patrón estándar de "double jump" en Roblox, vía `UserInputService` contando timestamps).
- **Cooldown:** 4 segundos base, reducible por gamepass/mejora hasta 1.5s mínimo.
- **Mejora:** upgrade de jardín "Altura de mega salto" (coins) sube el `JumpPower`/`ApplyImpulse` en pasos; tope de 5 niveles + 1 nivel extra vía gamepass.
- **Ventajas:** acceso a plataformas altas, islas flotantes, atajos a zonas secretas y "huevos" ocultos en altura.
- **VFX/SFX:** partícula de anillo bajo los pies al activarse + estela ascendente; sonido "whoosh" agudo distinto del salto normal; pequeño destello de polvo al aterrizar.

### Golpe de poder

- **Activación:** click/tap sobre un objeto rompible dentro de rango corto (`Tool` equipable tipo "Herramienta de Golpe", o clic directo con `ClickDetector`/`ProximityPrompt` como fallback mobile-friendly).
- **Objetos afectados:** todos los de la sección 8.
- **Golpes necesarios:** definidos por la "vida" de cada objeto (sección 8); cada click resta 1 golpe base (+bonus por Break Power).
- **Recompensas:** al llegar a 0 vida, el objeto explota en VFX + suelta su tabla de recompensas (coins garantizados + probabilidad de semilla/mascota).
- **Ayuda de mascotas:** cada mascota equipada con `Break Power` suma su porcentaje a la reducción de golpes necesarios (server-side, para evitar exploit de client).
- **Mejora:** upgrade de jardín "Fuerza de golpe" (coins) + gamepass "Golpe Poderoso" (Robux) multiplican el daño por golpe.

## 8. Sistema de objetos rompibles

| Objeto | Vida (golpes) | Recompensa coins | Prob. semilla | Prob. mascota rara | Respawn |
|---|---|---|---|---|---|
| Roca pequeña | 3 | 5–15 | 5% (común) | — | 20 s |
| Roca grande | 8 | 20–45 | 10% (común/poco común) | — | 45 s |
| Cristal de monedas | 5 | 40–90 | — | — | 60 s |
| Árbol mutante | 12 | 30–70 | 15% (poco común/rara) | 1% (poco común) | 90 s |
| Caja misteriosa | 6 | 25–60 | 20% (variable) | 2% (rara) | 120 s |
| Huevo fósil | 15 | 60–120 | 5% | 8% (rara/épica) | 5 min |
| Meteorito de monstruo | 25 | 150–300 | 10% (rara+) | 15% (épica/legendaria) | 15 min |
| Cofre antiguo | 20 | 200–500 | 25% (épica+) | 20% (legendaria+) | 30 min |

Todos los objetos se ubican en las zonas (sección 12), con mayor densidad/valor en zonas más avanzadas. La probabilidad de mascota rara aplica un roll adicional sobre la tabla de rarezas general (sección 16), no una tabla propia — así se mantiene una sola fuente de verdad para probabilidades.

## 9. Sistema de economía

- **Moneda única (coins):** todo fuente/sumidero pasa por `EconomyService` (server-authoritative, ya existente).
- **Fuentes:** cosecha de semillas, romper objetos, misiones diarias/semanales, venta de mascotas duplicadas, recompensas diarias, passive income de mascotas.
- **Sumideros:** semillas, mejoras de jardín, expansión de parcelas, herramientas de golpe, algunos cosméticos comprables con coins (los premium van con Robux).
- **Anti-inflación:** cada tier de semilla sube precio ~4x pero valor de cosecha solo ~1.5x el ratio anterior (ver tabla sección 5) — el margen neto crece en valor absoluto pero decrece en % relativo, empujando al jugador a invertir en mejoras de velocidad/rareza en vez de solo repetir la semilla más barata.
- **Doble moneda opcional (futuro, no MVP):** gemas premium compradas con Robux, usadas solo para semillas premium/huevos especiales — mantiene coins como economía 100% ganable gratis.

## 10. Sistema de progresión

Mejoras compradas con coins (progresión F2P) o aceleradas con Robux:

| Mejora | Efecto por nivel | Niveles | Tope free | Tope con gamepass |
|---|---|---|---|---|
| Tamaño del jardín | +1 fila de parcelas | 5 | Nivel 5 | — |
| Número de parcelas | +1 parcela | 10 | Nivel 8 | Nivel 10 |
| Velocidad de crecimiento | -8% tiempo | 6 | Nivel 5 | Nivel 6 + x2 gamepass |
| Suerte de rareza | +3% shift hacia rareza superior | 6 | Nivel 5 | Nivel 6 + gamepass |
| Fuerza de golpe | +15% daño por golpe | 5 | Nivel 5 | — |
| Altura de mega salto | +20% altura | 5 | Nivel 5 | +1 nivel exclusivo |
| Mascotas equipadas | +1 slot | 5 (3→8) | Nivel 4 (hasta 7) | Nivel 5 (hasta 8) |
| Capacidad de inventario | +20 slots | 6 | Nivel 4 | Nivel 6 |
| Multiplicador de coins | +5% global | 8 | Nivel 5 | Nivel 8 + x2 gamepass |

Progresión gatea por **zona**, no solo por coins — cada zona nueva desbloquea el siguiente tier de semillas/objetos/mejoras, evitando que un jugador con mucho coin salte etapas de contenido.

## 11. Tienda y monetización

### Estructura de tienda (tabs)

1. **Semillas** (coins) — filtradas por rareza y zona desbloqueada.
2. **Semillas premium** (Robux) — semillas de rareza alta con probabilidad ligeramente mejor que su par de coins, nunca exclusivas de contenido.
3. **Boosts** — 15 min / 30 min, coins o Robux.
4. **Mejoras permanentes** — coins, ver sección 10.
5. **Huevos especiales** — eventos/Robux, mascotas cosméticamente únicas.
6. **Cosméticos** — skins de mascota, efectos de partícula, trails — 100% Robux, cero impacto en stats.
7. **Herramientas de golpe** — coins (básica) → Robux (skins/efectos, no más daño del permitido por mejoras).
8. **Expansiones de jardín** — coins con tope, Robux para saltarse el grind del tope.

### Regla anti pay-to-win

Ningún ítem con Robux debe superar el **techo de poder** alcanzable gratis en más del 25–30% (ej: si el tope free de Coin Multiplier es +40%, el gamepass no debe pasar de ~+55–60% total, nunca doblar). Los gamepasses aceleran, no reemplazan, la progresión.

## 12. Zonas del mapa

| Zona | Contenido nuevo | Requisito de desbloqueo |
|---|---|---|
| Jardín inicial | Semillas común/poco común, rocas pequeñas/grandes, cristal de monedas | Ninguno (spawn) |
| Bosque de monstruos | Semilla rara, árbol mutante, caja misteriosa | Nivel de jardín 3 + 5,000 coins |
| Cueva de cristales | Semilla épica, cristal de monedas mejorado, huevo fósil | Nivel de jardín 5 + 25,000 coins |
| Isla flotante | Semilla legendaria, meteorito de monstruo, solo accesible con mega salto mejorado | Mega salto nivel 3 + 100,000 coins |
| Volcán mutante | Semilla mítica, objetos de alto riesgo/recompensa | Todas las mejoras nivel 4+ |
| Laboratorio secreto | Semilla secreta (solo por cofres/eventos), fusión y evolución | Completar 1 monstruo mítico + misión especial |
| Mundo de monstruos legendarios | Contenido end-game, rotación de eventos | Todas las zonas anteriores completas |

Cada zona reutiliza el patrón ya construido (`Terrain:FillRegion`/`FillBall` para paisaje, `Farms`/parcelas para siembra) — ver `docs/worldgen/generate-terrain.lua` como referencia de implementación.

## 13. Misiones y recompensas

- **Diarias** (reset 24h): plantar 10 semillas, cosechar 5 monstruos, romper 20 objetos, ganar 500 coins, usar mega salto 10 veces → recompensas: coins, 1 semilla aleatoria, boost corto.
- **Semanales** (reset 7 días): conseguir 1 mascota rara+, desbloquear una zona nueva, romper 100 objetos → recompensas: coins grandes, semilla de rareza garantizada, cosmético.
- **Logros** (una sola vez, permanentes): primera mascota legendaria, primera zona desbloqueada, 100 cosechas totales → recompensas simbólicas + título/badge.

## 14. Interfaz de usuario

Reusa el sistema de `Theme.lua` ya implementado (paleta pastel, `UICorner`, `UIStroke`, tweens de hover/press):

- **HUD superior:** contador de coins (icono + número animado al cambiar).
- **Barra inferior de botones:** Tienda, Inventario, Mascotas, Poderes, Mejoras — iconografía consistente, mismo estilo de botón que ya existe en `Client.client.lua`.
- **Sobre cada parcela:** barra de progreso de crecimiento (billboard GUI) + ícono de rareza cuando está lista.
- **Menú de monetización:** acceso directo desde HUD (ícono Robux), separado de la tienda de coins para no confundir gasto real vs. in-game.
- **Pantalla de recompensa diaria:** modal al primer login del día, con calendario de racha.
- **Pantalla de códigos promocionales:** input simple + botón canjear, validación server-side.
- **Pantalla de misiones:** tabs diarias/semanales/logros con barra de progreso por misión.

## 15. Estilo visual y sonoro

- **Visual:** paleta pastel ya definida en `Theme.lua`, monstruos redondeados con ojos grandes (nunca colmillos/sangre/agresión), partículas de rareza (brillo dorado = legendario, arcoíris sutil = mítico/secreto).
- **Sonido:**
  - Plantar: "plop" suave de tierra.
  - Cosechar: campanita ascendente +, si es rareza alta, un sting musical corto.
  - Monstruo raro: fanfarria breve + flash de pantalla del color de la rareza.
  - Romper objetos: crunch/crack por golpe, explosión satisfactoria en el golpe final.
  - Monedas: "cha-ching" corto, con pitch que sube levemente en rachas rápidas.
  - Mega salto: whoosh agudo + aterrizaje con thud suave.
  - Música: loop ambiental distinto por zona (ya hay precedente de zonas con biomas propios en el terreno generado).

## 16. Rarezas de mascotas

| Rareza | Color | Prob. base (semilla común) | VFX | Multiplicador de valor |
|---|---|---|---|---|
| Común | Gris/Blanco | 70% | Ninguno | 1x |
| Poco común | Verde | 25% | Brillo tenue | 2x |
| Raro | Azul | 4% (sube con semillas dedicadas) | Partículas azules | 6x |
| Épico | Morado | 0.7% | Aura pulsante | 20x |
| Legendario | Dorado | 0.25% | Destello + sonido único | 60x |
| Mítico | Rojo/Naranja fuego | 0.04% | Fuego/energía visible | 200x |
| Secreto | Arcoíris animado | 0.01% (solo eventos/cofres) | Shader arcoíris + anuncio de servidor | 1000x+ |

Las probabilidades por semilla (sección 5) sobre-representan la rareza "objetivo" de esa semilla — la tabla de arriba es la distribución **global** de referencia con la semilla más barata.

## 17. Ideas para eventos

- **Evento de temporada** (mensual): zona temporal con skin visual único (ej. "Halloween Garden", "Winter Frost Garden"), semilla y mascota exclusivas por tiempo limitado (pero re-obtenibles el año siguiente, nunca perdidas para siempre — evita FOMO tóxico).
- **Monstruos limitados:** aparición rotativa con rate-up temporal en la tabla de probabilidad de una semilla específica.
- **Ranking de jugadores:** leaderboard semanal de coins ganados o mascotas raras conseguidas, con recompensa cosmética al top 100 (no pay-to-win).
- **Doble XP/coins de fin de semana.**

## 18. Ideas de gamepasses

| Gamepass | Beneficio | Permanente/Temporal | Anti-P2W | Precio sugerido (Robux) |
|---|---|---|---|---|
| VIP Garden | +1 parcela extra, chat tag, color de nombre | Permanente | Cosmético + 1 parcela (tope moderado) | 399 |
| 2x Coins | +100% coins ganados | Permanente | Tope combinado con mejoras (sección 11) | 449 |
| 2x Crecimiento | -50% tiempo de crecimiento | Permanente | Acelera, no reemplaza espera mínima | 399 |
| Mascotas extra equipadas | +2 slots (por sobre el tope free) | Permanente | Tope free ya da la mayoría del valor | 299 |
| Mega salto mejorado | +1 nivel extra de altura, -1s cooldown | Permanente | Solo movilidad, no economía | 249 |
| Golpe poderoso | +25% daño de golpe adicional | Permanente | Aditivo sobre mejoras free | 299 |
| Suerte aumentada | +15% shift de rareza adicional | Permanente | Tope moderado vs. mejora free | 549 |
| Auto-cosecha | Cosecha automática al completarse | Permanente | Solo ahorra clicks, no valor | 349 |
| Auto-plantado | Replanta automáticamente la última semilla usada | Permanente | Solo conveniencia | 299 |
| Inventario infinito | Sin límite de slots | Permanente | Conveniencia pura | 249 |

## 19. Ideas de productos de desarrollador (Developer Products)

| Producto | Beneficio | Tipo | Precio sugerido (Robux) |
|---|---|---|---|
| Pack de coins pequeño | +1,000 coins | Consumible | 79 |
| Pack de coins mediano | +6,000 coins | Consumible | 399 |
| Pack de coins grande | +15,000 coins | Consumible | 799 |
| Semilla rara individual | 1 semilla rara garantizada | Consumible | 149 |
| Semilla épica individual | 1 semilla épica garantizada | Consumible | 349 |
| Boost 15 min (coins o crecimiento) | +100% temporal | Consumible | 49 |
| Boost 30 min (coins o crecimiento) | +100% temporal | Consumible | 79 |
| Token de instant-grow | Completa 1 parcela al instante | Consumible | 39 |
| Huevo misterioso premium | Mascota aleatoria de rareza rara+ garantizada | Consumible | 299 |
| Escudo temporal (anti-competencia social si se agrega esa mecánica a futuro) | Protección 30 min | Consumible | 99 |

## 20. Balance inicial recomendado

- **Coins iniciales al primer join:** 100 (suficiente para 4 semillas comunes, refuerza el loop desde el minuto uno).
- **Primera parcela:** gratis (ya implementado).
- **Semilla común:** 25 coins → 60s de espera → 40 coins de valor de cosecha promedio (ratio de retorno ~1.6x, tiempo corto para enganchar).
- **Curva de precio entre tiers:** ~x4 por tier de semilla, valor de cosecha ~x2.5–3 por tier — el margen % baja con cada tier, empujando a invertir en mejoras.
- **Mega salto cooldown inicial:** 4s (ni frustrante ni trivial de spamear).
- **Golpe de poder:** objeto más débil (roca pequeña) muere en 3 golpes con la herramienta básica — feedback rápido desde el primer minuto.
- **Primera zona nueva (Bosque de monstruos):** alcanzable en ~20–30 minutos de juego activo, para dar el primer gran hito de sesión.

## 21. Lista de tareas para empezar a construir en Roblox Studio

Ordenada por dependencia, asumiendo la base ya existente (`PlotService`, `GrowthService`, `EconomyService`, `InventoryService`, `TradeService`, `Theme.lua`, mundo generado):

1. **Config de datos** — crear `ReplicatedStorage/Shared/Config/Seeds.lua` y `Monsters.lua` con las tablas de la sección 5 y 16 (mismo patrón que `Monetization.lua`/`Sounds.lua`).
2. **MonsterService** — nuevo servicio server-side: resuelve la tabla de probabilidad al cosechar, crea la instancia de monstruo, la guarda en el inventario del jugador vía `DataService`.
3. **PetService** — gestiona equipar/desequipar mascotas (máx. `MaxEquippedPets`), aplica sus buffs a un `PlayerStats` module compartido que lean `GrowthService`/`EconomyService`/movimiento.
4. **Extender `PlotService`/`GrowthService`** — que el tiempo de crecimiento lea el `GrowTimeSeconds` de la semilla y aplique el `GrowthBoost` de mascotas equipadas.
5. **PowerService** — mega salto (detección de doble-tap en un `LocalScript`, validación de cooldown server-side) y golpe de poder (`ClickDetector`/`Tool`, validación de daño server-side).
6. **BreakableService** — spawner de objetos rompibles por zona con vida/recompensa/respawn (tabla de la sección 8), usando el patrón ya usado en `docs/worldgen` para posicionar por zona.
7. **UpgradeService** — compra y aplica las mejoras de la sección 10, persistidas en `DataService`.
8. **Extender `MonetizationService`** — completar los `AssetId`s placeholder con los gamepasses/productos reales una vez el juego esté publicado (bloqueado hasta publicar, como ya se definió).
9. **UI nueva** — pantallas de Mascotas, Poderes, Mejoras, Misiones, Recompensa diaria, Códigos promocionales — reusando `Theme.lua` y el patrón de `Client.client.lua`.
10. **MissionService** — misiones diarias/semanales con reset por `os.time()`, persistidas en `DataService`.
11. **Zonas nuevas** — replicar el patrón de `docs/worldgen/generate-terrain.lua` por zona (Bosque, Cueva, Isla, Volcán, Laboratorio), cada una con su propio script documentado.
12. **Balance pass** — una vez todo integrado, ajustar los números exactos de la sección 20 jugando internamente antes de publicar.

Cada uno de estos ítems es candidato a su propio ciclo brainstorming → spec → plan → implementación (como ya se hizo con MVP-polish y trading), en vez de construirse todo junto.
