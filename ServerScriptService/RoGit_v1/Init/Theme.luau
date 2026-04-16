local Theme = {}

Theme.Color = {
	Background = Color3.fromHex("#1e1e2e"),
	Surface = Color3.fromHex("#313244"),
	SurfaceHover = Color3.fromHex("#45475a"),
	SurfaceActive = Color3.fromHex("#585b70"),
	Text = Color3.fromHex("#cdd6f4"),
	TextMuted = Color3.fromHex("#a6adc8"),
	TextDim = Color3.fromHex("#7f849c"),
	Accent = Color3.fromHex("#89b4fa"),
	AccentHover = Color3.fromHex("#74c7ec"),
	Green = Color3.fromHex("#a6e3a1"),
	Yellow = Color3.fromHex("#f9e2af"),
	Red = Color3.fromHex("#f38ba8"),
	Orange = Color3.fromHex("#fab387"),
	Border = Color3.fromHex("#45475a"),
	InputBg = Color3.fromHex("#181825"),
	DiffAdd = Color3.fromHex("#1a3a1a"),
	DiffRemove = Color3.fromHex("#3a1a1a"),
	DiffAddText = Color3.fromHex("#a6e3a1"),
	DiffRemoveText = Color3.fromHex("#f38ba8"),
	DiffHunkBg = Color3.fromHex("#242440"),
	DiffHunkText = Color3.fromHex("#b4befe"),

	-- Syntax highlighting
	SynKeyword = Color3.fromHex("#cba6f7"),
	SynBuiltin = Color3.fromHex("#89b4fa"),
	SynString = Color3.fromHex("#a6e3a1"),
	SynComment = Color3.fromHex("#6c7086"),
	SynNumber = Color3.fromHex("#fab387"),
	SynOperator = Color3.fromHex("#89dceb"),
	SynSelf = Color3.fromHex("#f38ba8"),
	SynType = Color3.fromHex("#f9e2af"),
}

Theme.Font = {
	Regular = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Mono = Enum.Font.Code,
}

Theme.Size = {
	TextSmall = 11,
	TextNormal = 13,
	TextLarge = 15,
	TextHeader = 17,
	SpacingXS = 4,
	SpacingS = 6,
	SpacingM = 8,
	SpacingL = 12,
	SpacingXL = 16,
}

Theme.Corner = UDim.new(0, 6)
Theme.CornerSmall = UDim.new(0, 4)

local FILE_COLORS: { [string]: Color3 } = {
	[".server.luau"] = Theme.Color.Green,
	[".client.luau"] = Theme.Color.Yellow,
	[".luau"] = Theme.Color.Accent,
	[".meta.json"] = Theme.Color.SynComment,
	[".json"] = Theme.Color.Orange,
	[".md"] = Theme.Color.TextMuted,
}

function Theme.fileColor(path: string): Color3
	for ext, color in FILE_COLORS do
		if path:sub(-#ext) == ext then
			return color
		end
	end
	return Theme.Color.TextMuted
end

return Theme