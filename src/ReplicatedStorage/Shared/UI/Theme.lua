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
