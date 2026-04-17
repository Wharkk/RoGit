local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

local AppModule = require(script.App)

local toolbar = plugin:CreateToolbar("RoGit")
local mainButton = toolbar:CreateButton("RoGit", "Open RoGit", "rbxassetid://88313731361406")
local outputButton = toolbar:CreateButton("Output", "Toggle RoGit Output", "rbxassetid://133886310616998")
local initButton = toolbar:CreateButton("Git Init", "Setup project with gitignore and README", "rbxassetid://95621848685313")

mainButton.ClickableWhenViewportHidden = true
outputButton.ClickableWhenViewportHidden = true
initButton.ClickableWhenViewportHidden = true

local mainWidgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, false,
	320, 600,
	280, 400
)

local outputWidgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Bottom,
	false, false,
	400, 150,
	300, 100
)

local diffWidgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, false,
	700, 500,
	500, 350
)

local mainWidget = plugin:CreateDockWidgetPluginGuiAsync("RoGitMain", mainWidgetInfo)
mainWidget.Title = "RoGit"

local outputWidget = plugin:CreateDockWidgetPluginGuiAsync("RoGitOutput", outputWidgetInfo)
outputWidget.Title = "RoGit Output"

local diffWidget = plugin:CreateDockWidgetPluginGuiAsync("RoGitDiff", diffWidgetInfo)
diffWidget.Title = "RoGit Diff"

local app: AppModule.App? = nil

local function ensureApp()
	if not app then
		app = AppModule.new(mainWidget, outputWidget, diffWidget, plugin)
	end
end

mainButton.Click:Connect(function()
	mainWidget.Enabled = not mainWidget.Enabled
	mainButton:SetActive(mainWidget.Enabled)
	if mainWidget.Enabled then ensureApp() end
end)

outputButton.Click:Connect(function()
	outputWidget.Enabled = not outputWidget.Enabled
	outputButton:SetActive(outputWidget.Enabled)
	if outputWidget.Enabled then ensureApp() end
end)

initButton.Click:Connect(function()
	ensureApp()
	
	-- Open output so user sees what was created
	if not outputWidget.Enabled then
		outputWidget.Enabled = true
		outputButton:SetActive(true)
	end
	app:gitInit()
end)

mainWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	mainButton:SetActive(mainWidget.Enabled)
	if mainWidget.Enabled then ensureApp() end
end)

outputWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	outputButton:SetActive(outputWidget.Enabled)
end)

plugin.Unloading:Connect(function()
	if app then
		app:destroy()
		app = nil
	end
end)