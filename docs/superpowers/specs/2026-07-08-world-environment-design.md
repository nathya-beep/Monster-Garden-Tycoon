# Diseño: Ambientación del mundo (terreno esculpido + zonas)

## Contexto

El `CLAUDE.md` describe la visión ("jardín mágico") pero no dice nada sobre ambientación/paisaje del mundo — hueco confirmado al revisar el archivo. Antes de publicar el lugar a Roblox (paso previo necesario para conectar monetización real), el usuario quiere mejorar la ambientación: hoy es un baseplate plano sin paisaje.

## Alcance

- Terreno esculpido (colinas suaves) alrededor del área de las 3 parcelas existentes.
- Una laguna/pileta de agua en zona libre.
- Camino de tierra conectando los `SpawnPoint` de `Plot1` → `Plot2` → `Plot3`.
- Vegetación dispersa (árboles y rocas simples, mismo estilo Part que ya se usó en la sesión) fuera de las parcelas y la laguna.

Fuera de alcance: assets importados del Marketplace, iluminación/skybox personalizado, más de 3 parcelas, terreno fuera del área jugable actual.

## Cómo se construye (decisión técnica clave)

A diferencia de todo el código anterior (sincronizado vía Rojo desde `src/`), el terreno de Roblox (`Workspace.Terrain`) es data binaria que Rojo no puede versionar como archivos `.lua`, y los props decorativos son más prácticos de generar por script que de tipear a mano en `default.project.json`. Por eso esto se ejecuta como un script Luau **una sola vez**, corrido directamente contra la instancia de Studio abierta vía el MCP `robloxstudio-mcp` (`execute_luau`), en modo Edición (no Play).

El resultado queda en el archivo `.rbxl` de Studio — persiste solo si el usuario hace `File > Save` después. El script generador se guarda en `docs/worldgen/generate-terrain.lua` como documentación/reproducibilidad, pero no es parte del árbol `src/` que Rojo sincroniza ni de la lógica de gameplay.

## Diseño

### 1. Terreno base y colinas

`Terrain:FillRegion` con una región plana (Material.Grass) cubriendo `x: [-70, 70]`, `z: [-10, 130]` (cubre las 3 parcelas, que van de `z=15` a `z=105` aprox. considerando su `Ground` de 24 studs). Sobre esa base, 6-8 llamadas a `Terrain:FillBall` con centros en el perímetro (fuera del rango de las parcelas, `|x| > 35` o `z < 5` o `z > 115`) y radios entre 15-25 studs, embebidas para que solo sobresalga la parte superior — generan lomas suaves sin tapar las parcelas.

### 2. Laguna

Una `Terrain:FillBall` con Material.Water, radio ~10, centrada en una posición fija alejada de las 3 parcelas y de las colinas (ej. `x = -50, z = 60`).

### 3. Camino

Franjas rectangulares fusionadas con `Terrain:FillRegion` (Material.Ground o Mud), de ~4 studs de ancho, conectando en línea recta los `SpawnPoint` de `Plot1` (z=30), `Plot2` (z=60) y `Plot3` (z=90), todos en `x=0` — el camino es una franja recta sobre el eje X=0 entre `z=25` y `z=95`.

### 4. Vegetación

Loop en el script generador: 12 árboles (mismo Model trunk+leaves de la prueba inicial de la sesión) y 12 rocas (Part esférica gris, `Material.Slate`), posiciones aleatorias dentro del área del terreno pero excluyendo: un radio de 15 studs alrededor de cada `SpawnPoint`, la zona de la laguna, y la franja del camino (`|x| < 6`).

## Testing

Verificación visual manual: después de correr el script, pedirle al usuario que mire el Viewport de Studio (o darle Play) y confirme que las colinas, la laguna, el camino, y los árboles/rocas aparecen sin superponerse con las parcelas. No aplica testing automatizado (contenido visual, no lógica).
