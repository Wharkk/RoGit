local PropertyMap = {}

local BASE_PART = { "Anchored", "CanCollide", "CanTouch", "CanQuery", "CastShadow", "Color", "Material", "MaterialVariant", "Reflectance", "Transparency", "Size", "CFrame", "CollisionGroup", "Massless", "TopSurface", "BottomSurface" }
local BASE_GUI = { "Size", "Position", "AnchorPoint", "Rotation", "BackgroundColor3", "BackgroundTransparency", "BorderColor3", "BorderSizePixel", "Visible", "ZIndex", "LayoutOrder", "AutomaticSize", "ClipsDescendants" }
local TEXT_PROPS = { "Text", "TextColor3", "TextSize", "TextTransparency", "TextWrapped", "TextXAlignment", "TextYAlignment", "Font", "RichText" }
local IMAGE_PROPS = { "Image", "ImageColor3", "ImageTransparency", "ImageRectOffset", "ImageRectSize", "ScaleType", "SliceCenter", "SliceScale" }

local function merge(...: { string }): { string }
	local r: { string } = {}
	for _, list in { ... } do
		for _, p in list do table.insert(r, p) end
	end
	return r
end

local REGISTRY: { [string]: { string } } = {
	Part = merge(BASE_PART, { "Shape" }),
	MeshPart = merge(BASE_PART, { "MeshId", "TextureID" }),
	UnionOperation = merge(BASE_PART, { "UsePartColor", "SmoothingAngle" }),
	WedgePart = merge(BASE_PART),
	CornerWedgePart = merge(BASE_PART),
	SpawnLocation = merge(BASE_PART, { "TeamColor", "Neutral", "Duration" }),
	Seat = merge(BASE_PART, { "Disabled" }),
	VehicleSeat = merge(BASE_PART, { "Disabled", "MaxSpeed", "Torque", "TurnSpeed" }),

	Model = { "PrimaryPart" },
	Folder = {},
	Camera = { "CFrame", "FieldOfView", "FieldOfViewMode", "CameraType" },
	Attachment = { "CFrame", "Visible" },

	PointLight = { "Brightness", "Color", "Enabled", "Range", "Shadows" },
	SpotLight = { "Brightness", "Color", "Enabled", "Range", "Shadows", "Angle", "Face" },
	SurfaceLight = { "Brightness", "Color", "Enabled", "Range", "Shadows", "Angle", "Face" },
	Decal = { "Color3", "Face", "Texture", "Transparency", "ZIndex" },
	Texture = { "Color3", "Face", "Texture", "Transparency", "ZIndex", "OffsetStudsU", "OffsetStudsV", "StudsPerTileU", "StudsPerTileV" },
	Sound = { "SoundId", "Volume", "PlaybackSpeed", "Looped", "Playing", "RollOffMaxDistance", "RollOffMinDistance" },

	Frame = merge(BASE_GUI),
	ScrollingFrame = merge(BASE_GUI, { "CanvasSize", "ScrollBarThickness", "ScrollingDirection", "AutomaticCanvasSize" }),
	TextLabel = merge(BASE_GUI, TEXT_PROPS),
	TextButton = merge(BASE_GUI, TEXT_PROPS, { "AutoButtonColor" }),
	TextBox = merge(BASE_GUI, TEXT_PROPS, { "PlaceholderText", "PlaceholderColor3", "ClearTextOnFocus", "MultiLine" }),
	ImageLabel = merge(BASE_GUI, IMAGE_PROPS),
	ImageButton = merge(BASE_GUI, IMAGE_PROPS, { "AutoButtonColor" }),
	ViewportFrame = merge(BASE_GUI, { "CurrentCamera", "ImageColor3", "ImageTransparency", "Ambient", "LightColor", "LightDirection" }),

	ScreenGui = { "Enabled", "ResetOnSpawn", "DisplayOrder", "IgnoreGuiInset", "ZIndexBehavior" },
	BillboardGui = { "Enabled", "Active", "Adornee", "Size", "StudsOffset", "AlwaysOnTop", "MaxDistance" },
	SurfaceGui = { "Enabled", "Active", "Adornee", "Face", "CanvasSize", "PixelsPerStud", "AlwaysOnTop" },

	UIListLayout = { "SortOrder", "FillDirection", "HorizontalAlignment", "VerticalAlignment", "Padding", "Wraps" },
	UIGridLayout = { "SortOrder", "CellSize", "CellPadding", "FillDirection", "FillDirectionMaxCells" },
	UIPadding = { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" },
	UICorner = { "CornerRadius" },
	UIStroke = { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode" },
	UIScale = { "Scale" },
	UIAspectRatioConstraint = { "AspectRatio", "AspectType", "DominantAxis" },
	UISizeConstraint = { "MaxSize", "MinSize" },

	WeldConstraint = { "Enabled", "Part0", "Part1" },
	Motor6D = { "C0", "C1", "Part0", "Part1", "Enabled" },
	HingeConstraint = { "Enabled", "Attachment0", "Attachment1", "ActuatorType" },
	SpringConstraint = { "Enabled", "Attachment0", "Attachment1", "Stiffness", "Damping", "FreeLength" },
	RopeConstraint = { "Enabled", "Attachment0", "Attachment1", "Length", "Visible", "Color" },
	AlignPosition = { "Enabled", "Attachment0", "Attachment1", "Mode", "RigidityEnabled", "MaxForce" },
	AlignOrientation = { "Enabled", "Attachment0", "Attachment1", "Mode", "RigidityEnabled", "MaxTorque" },

	Beam = { "Attachment0", "Attachment1", "Color", "Enabled", "Segments", "Texture", "Width0", "Width1" },
	Trail = { "Attachment0", "Attachment1", "Color", "Enabled", "Lifetime", "Texture", "WidthScale" },
	ParticleEmitter = { "Color", "Enabled", "Size", "Texture", "Transparency", "Acceleration", "Lifetime", "Rate", "Rotation", "Speed", "SpreadAngle" },

	Humanoid = { "MaxHealth", "Health", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "HipHeight", "AutoRotate", "DisplayName" },

	StringValue = { "Value" },
	IntValue = { "Value" },
	NumberValue = { "Value" },
	BoolValue = { "Value" },
	Color3Value = { "Value" },
	Vector3Value = { "Value" },
	CFrameValue = { "Value" },

	BindableEvent = {},
	RemoteEvent = {},
	RemoteFunction = {},
	Configuration = {},

	PackageLink = { "PackageIdSerialize", "AutoUpdate", "VersionIdSerialize" },
}

local OBJECT_REFS: { [string]: boolean } = {
	PrimaryPart = true, Part0 = true, Part1 = true,
	Attachment0 = true, Attachment1 = true,
	Adornee = true, CurrentCamera = true,
}

function PropertyMap.getProperties(className: string): { string }?
	return REGISTRY[className]
end

function PropertyMap.isRegistered(className: string): boolean
	return REGISTRY[className] ~= nil
end

function PropertyMap.isObjectReference(propName: string): boolean
	return OBJECT_REFS[propName] == true
end

return PropertyMap