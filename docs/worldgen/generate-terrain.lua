-- generate-terrain.lua
-- Generador de ambientación (terreno, lagunas, camino, vegetación) para
-- Monster Garden Tycoon. Se corrió vía MCP execute_luau (robloxstudio-mcp),
-- en modo Edición, contra Place1.rbxl. No es parte del árbol Rojo (src/) —
-- el resultado queda en el .rbxl; documentado acá para reproducibilidad.
-- Ver docs/superpowers/specs/2026-07-08-world-environment-design.md.
--
-- v2: mundo agrandado a ~500x500 studs (v1 era ~140x140). Terrain:Clear()
-- + borrado de la carpeta Decoration vieja al inicio para poder re-correr
-- este script sin duplicar geometría.

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

Terrain:Clear()
local oldDecor = Workspace:FindFirstChild("Decoration")
if oldDecor then
	oldDecor:Destroy()
end

local PLOT_Z = { 30, 60, 90 }
local POND_POSITION = Vector3.new(-90, 0, 60)
local POND_RADIUS = 22

-- 1. Base plana (~500x500 studs) cubriendo las 3 parcelas con mucho margen alrededor.
Terrain:FillRegion(Region3.new(Vector3.new(-260, -8, -180), Vector3.new(260, 4, 340)):ExpandToGrid(4), 4, Enum.Material.Grass)

-- 2. Colinas en un anillo amplio en el perímetro (16 colinas, radio 30-55).
local hillPositions = {
	Vector3.new(-200, 0, -60),
	Vector3.new(-140, 0, -140),
	Vector3.new(0, 0, -170),
	Vector3.new(140, 0, -140),
	Vector3.new(200, 0, -60),
	Vector3.new(230, 0, 60),
	Vector3.new(200, 0, 180),
	Vector3.new(140, 0, 280),
	Vector3.new(0, 0, 310),
	Vector3.new(-140, 0, 280),
	Vector3.new(-200, 0, 180),
	Vector3.new(-230, 0, 60),
	Vector3.new(-100, 0, -20),
	Vector3.new(100, 0, -20),
	Vector3.new(-100, 0, 140),
	Vector3.new(100, 0, 140),
}
for _, position in ipairs(hillPositions) do
	local radius = 30 + math.random() * 25
	Terrain:FillBall(position - Vector3.new(0, radius * 0.55, 0), radius, Enum.Material.Grass)
end

-- 3. Lagunas
Terrain:FillBall(POND_POSITION, POND_RADIUS, Enum.Material.Water)
Terrain:FillBall(Vector3.new(150, -1, 220), 14, Enum.Material.Water)

-- 4. Camino de tierra entre las 3 parcelas (todas en x=0)
Terrain:FillRegion(Region3.new(Vector3.new(-2, -1, 25), Vector3.new(2, 2, 95)):ExpandToGrid(4), 4, Enum.Material.Ground)

-- 5. Vegetación dispersa en toda el área, evitando parcelas, lagunas y camino
local function isNearExcludedZone(x: number, z: number): boolean
	for _, plotZ in ipairs(PLOT_Z) do
		if (Vector3.new(x, 0, z) - Vector3.new(0, 0, plotZ)).Magnitude < 15 then
			return true
		end
	end
	if (Vector3.new(x, 0, z) - Vector3.new(POND_POSITION.X, 0, POND_POSITION.Z)).Magnitude < POND_RADIUS + 6 then
		return true
	end
	if (Vector3.new(x, 0, z) - Vector3.new(150, 0, 220)).Magnitude < 20 then
		return true
	end
	if math.abs(x) < 6 and z > 20 and z < 100 then
		return true
	end
	return false
end

local decorFolder = Instance.new("Folder")
decorFolder.Name = "Decoration"
decorFolder.Parent = Workspace

local function createTree(position: Vector3)
	local tree = Instance.new("Model")
	tree.Name = "Tree"

	local trunk = Instance.new("Part")
	trunk.Size = Vector3.new(2, 8, 2)
	trunk.Position = position + Vector3.new(0, 4, 0)
	trunk.Anchored = true
	trunk.Color = Color3.fromRGB(92, 64, 42)
	trunk.Material = Enum.Material.Wood
	trunk.Parent = tree

	local leaves = Instance.new("Part")
	leaves.Shape = Enum.PartType.Ball
	leaves.Size = Vector3.new(10, 10, 10)
	leaves.Position = position + Vector3.new(0, 11, 0)
	leaves.Anchored = true
	leaves.Color = Color3.fromRGB(58, 128, 42)
	leaves.Material = Enum.Material.Grass
	leaves.Parent = tree

	tree.PrimaryPart = trunk
	tree.Parent = decorFolder
end

local function createRock(position: Vector3)
	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Shape = Enum.PartType.Ball
	local size = 2 + math.random() * 3
	rock.Size = Vector3.new(size, size * 0.7, size)
	rock.Position = position + Vector3.new(0, size * 0.35, 0)
	rock.Anchored = true
	rock.Color = Color3.fromRGB(120, 120, 120)
	rock.Material = Enum.Material.Slate
	rock.Parent = decorFolder
end

local function scatter(count: number, place: (Vector3) -> ())
	local placed = 0
	local attempts = 0
	while placed < count and attempts < 600 do
		attempts += 1
		local x = (math.random() - 0.5) * 500
		local z = math.random() * 480 - 160
		if not isNearExcludedZone(x, z) then
			place(Vector3.new(x, 0, z))
			placed += 1
		end
	end
	return placed
end

local treeCount = scatter(60, createTree)
local rockCount = scatter(50, createRock)

print(("[WorldGen] Mundo agrandado: %d árboles, %d rocas, terreno 500x500 studs."):format(treeCount, rockCount))
