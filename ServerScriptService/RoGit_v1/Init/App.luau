local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Types = require(script.Parent.Types)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local GitHubClientModule = require(script.Parent.GitHubClient)
local InstanceSerializerModule = require(script.Parent.InstanceSerializer)
local DiffEngine = require(script.Parent.DiffEngine)

type GitHubConfig = Types.GitHubConfig
type CommitInfo = Types.CommitInfo
type BranchInfo = Types.BranchInfo
type TreeEntry = Types.TreeEntry

local SETTING_OWNER = "RoGit_Owner"
local SETTING_REPO = "RoGit_Repo"
local SETTING_BRANCH = "RoGit_Branch"
local SETTING_TOKEN = "RoGit_Token"
local SETTING_REMEMBER = "RoGit_Remember"
local SETTING_AUTOBACKUP = "RoGit_AutoBackup"
local SETTING_EXCLUDED = "RoGit_ExcludedServices"

export type ChangedFile = {
	path: string,
	status: string,
	localContent: string?,
}

local App = {}
App.__index = App

export type App = typeof(setmetatable({} :: {
	widget: DockWidgetPluginGui,
	outputWidget: DockWidgetPluginGui,
	diffWidget: DockWidgetPluginGui,
	pluginRef: Plugin,
	client: GitHubClientModule.GitHubClient?,
	serializer: InstanceSerializerModule.InstanceSerializer,
	connected: boolean,
	currentBranch: string,
	branches: { string },
	busy: boolean,
	activeView: string,
	remoteFiles: { [string]: string },
	remoteTreeEntries: { TreeEntry },
	remoteReady: boolean,
	changedFiles: { ChangedFile },
	refs: { [string]: any },
	connections: { RBXScriptConnection },
	stagingDirty: boolean,
	refreshQueued: boolean,
	outputLines: { string },
	tokenValue: string,
	tokenMasked: boolean,
	autoBackupEnabled: boolean,
	autoBackupThread: thread?,
	destroyed: boolean,
	applyingRemote: boolean,
}, App))

function App.new(widget: DockWidgetPluginGui, outputWidget: DockWidgetPluginGui, diffWidget: DockWidgetPluginGui, pluginRef: Plugin): App
	local self = setmetatable({}, App)
	self.widget = widget
	self.outputWidget = outputWidget
	self.diffWidget = diffWidget
	self.pluginRef = pluginRef
	self.client = nil
	self.serializer = InstanceSerializerModule.new()
	self.connected = false
	self.currentBranch = "main"
	self.branches = {}
	self.busy = false
	self.activeView = "connection"
	self.remoteFiles = {}
	self.remoteTreeEntries = {}
	self.remoteReady = false
	self.changedFiles = {}
	self.refs = {}
	self.refs.headerConnectedItems = {}
	self.connections = {}
	self.stagingDirty = false
	self.refreshQueued = false
	self.outputLines = {}
	self.tokenValue = ""
	self.tokenMasked = true
	self.autoBackupEnabled = false
	self.autoBackupThread = nil
	self.destroyed = false
	self.applyingRemote = false
	self:_buildUI()
	self:_buildOutputUI()
	self:_buildDiffWidget()
	self:_restoreSettings()
	
	-- Show wizard on first launch (no saved repo), otherwise connection panel
	local savedOwner = self.pluginRef:GetSetting(SETTING_OWNER)
	if not savedOwner or savedOwner == "" then
		self:_showView("wizard")
	else
		self:_showView("connection")
	end
	self:_setupAutoRefresh()
	return self
end

--==============================--
--     AUTO-REFRESH STAGING     --
--==============================--

function App._setupAutoRefresh(self: App)
	local services = { "ServerScriptService", "ReplicatedStorage", "StarterGui", "StarterPlayer", "ServerStorage", "StarterPack", "Workspace", "Lighting", "SoundService" }
	for _, svcName in services do
		local service = game:FindService(svcName)
		if not service then continue end
		table.insert(self.connections, service.DescendantAdded:Connect(function() self:_markStagingDirty() end))
		table.insert(self.connections, service.DescendantRemoving:Connect(function() self:_markStagingDirty() end))
	end
end

function App._markStagingDirty(self: App)
	if not self.connected or not self.remoteReady then return end
	if self.destroyed or self.applyingRemote then return end
	self.stagingDirty = true
	if self.refreshQueued then return end
	self.refreshQueued = true
	task.delay(1.5, function()
		self.refreshQueued = false
		if self.destroyed then return end
		if self.stagingDirty and not self.busy and self.connected and self.remoteReady and not self.applyingRemote then
			self.stagingDirty = false
			self:_refreshStaging()
		end
	end)
end

--==============================--
--          BUILD UI            --
--==============================--

function App._buildUI(self: App)
	local root = Instance.new("Frame")
	root.Name = "RoGitRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.Color.Background
	root.BorderSizePixel = 0
	root.Parent = self.widget
	self.refs.root = root

	self:_buildHeader(root)
	self:_buildWizardPanel(root)
	self:_buildConnectionPanel(root)
	self:_buildMainPanel(root)
	self:_buildClonePanel(root)
end

function App._buildHeader(self: App, parent: Frame)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = Theme.Color.Surface
	header.BorderSizePixel = 0
	header.Parent = parent

	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.SortOrder = Enum.SortOrder.LayoutOrder
	hl.VerticalAlignment = Enum.VerticalAlignment.Center
	hl.Padding = UDim.new(0, Theme.Size.SpacingXS)
	hl.Parent = header

	local hp = Instance.new("UIPadding")
	hp.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	hp.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	hp.Parent = header

	local logo = Instance.new("TextLabel")
	logo.Size = UDim2.fromOffset(42, 36)
	logo.BackgroundTransparency = 1
	logo.Text = "RoGit"
	logo.TextColor3 = Theme.Color.Accent
	logo.Font = Theme.Font.Bold
	logo.TextSize = Theme.Size.TextLarge
	logo.TextXAlignment = Enum.TextXAlignment.Left
	logo.LayoutOrder = 0
	logo.Parent = header

	-- Branch dropdown (connected only)
	local branchDropdown = Components.createDropdown(header, {
		items = { "main" }, selected = "main", placeholder = "branch...",
		layoutOrder = 1, maxVisibleItems = 8,
		showCreateOption = true, createPlaceholder = "+ New branch...",
		onCreateNew = function(name: string) self:_createBranch(name) end,
	})
	branchDropdown.frame.Size = UDim2.fromOffset(140, 28)
	local branchConstraint = Instance.new("UISizeConstraint")
	branchConstraint.MinSize = Vector2.new(80, 28)
	branchConstraint.MaxSize = Vector2.new(160, 28)
	branchConstraint.Parent = branchDropdown.frame
	branchDropdown.onChanged(function(branch: string) self:_switchBranch(branch) end)
	self.refs.branchDropdown = branchDropdown
	table.insert(self.refs.headerConnectedItems, branchDropdown.frame)

	-- Spacer
	local spacer = Instance.new("Frame")
	spacer.Size = UDim2.new(1, -380, 0, 36)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 2
	spacer.Parent = header

	-- Connected-only buttons
	local refBtn = Components.createIconButton(header, {
		icon = "rbxassetid://102776660012261", tooltip = "Refresh", size = UDim2.fromOffset(28, 24), layoutOrder = 3,
		onClick = function() self:refresh() end,
	})
	table.insert(self.refs.headerConnectedItems, refBtn)

	local pullBtn = Components.createIconButton(header, {
		icon = "rbxassetid://70867730193156", tooltip = "Pull", size = UDim2.fromOffset(30, 24), layoutOrder = 4,
		color = Theme.Color.Green, onClick = function() self:pull() end,
	})
	table.insert(self.refs.headerConnectedItems, pullBtn)

	local pushBtn = Components.createIconButton(header, {
		icon = "rbxassetid://91947770716702", tooltip = "Push all", size = UDim2.fromOffset(34, 24), layoutOrder = 5,
		onClick = function() self:_quickPush() end,
	})
	table.insert(self.refs.headerConnectedItems, pushBtn)

	local diffBtn = Components.createIconButton(header, {
		icon = "rbxassetid://110896426937794", tooltip = "View diff", size = UDim2.fromOffset(28, 24), layoutOrder = 6,
		color = Theme.Color.Yellow, onClick = function() self:_showDiff() end,
	})
	table.insert(self.refs.headerConnectedItems, diffBtn)

	local searchBtn = Components.createIconButton(header, {
		icon = "rbxassetid://85482361348123", tooltip = "Search files", size = UDim2.fromOffset(22, 24), layoutOrder = 7,
		onClick = function() self:_showSearch() end,
	})
	table.insert(self.refs.headerConnectedItems, searchBtn)

	local homeBtn = Components.createIconButton(header, {
		icon = "rbxassetid://139751969553505", tooltip = "Home", size = UDim2.fromOffset(22, 24), layoutOrder = 8,
		onClick = function() self:_showView("connection") end,
	})
	table.insert(self.refs.headerConnectedItems, homeBtn)
end

function App._buildWizardPanel(self: App, parent: Frame)
	local panel = Instance.new("Frame")
	panel.Name = "WizardPanel"
	panel.Size = UDim2.new(1, 0, 1, -36)
	panel.Position = UDim2.fromOffset(0, 36)
	panel.BackgroundColor3 = Theme.Color.Background
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent
	self.refs.wizardPanel = panel

	local scroll = Components.createScrollFrame(panel)
	local wl = Instance.new("UIListLayout")
	wl.SortOrder = Enum.SortOrder.LayoutOrder
	wl.Padding = UDim.new(0, Theme.Size.SpacingM)
	wl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	wl.Parent = scroll

	local wp = Instance.new("UIPadding")
	wp.PaddingTop = UDim.new(0, Theme.Size.SpacingXL)
	wp.PaddingLeft = UDim.new(0, Theme.Size.SpacingXL)
	wp.PaddingRight = UDim.new(0, Theme.Size.SpacingXL)
	wp.PaddingBottom = UDim.new(0, Theme.Size.SpacingXL)
	wp.Parent = scroll

	-- Step content frames (all inside the scroll, toggled by step number)
	local steps: { Frame } = {}
	local currentStep = 1

	local function createStep(order: number): Frame
		local stepFrame = Instance.new("Frame")
		stepFrame.Name = `Step{order}`
		stepFrame.Size = UDim2.new(1, 0, 0, 0)
		stepFrame.AutomaticSize = Enum.AutomaticSize.Y
		stepFrame.BackgroundTransparency = 1
		stepFrame.LayoutOrder = 1
		stepFrame.Visible = order == 1
		stepFrame.Parent = scroll

		local sl = Instance.new("UIListLayout")
		sl.SortOrder = Enum.SortOrder.LayoutOrder
		sl.Padding = UDim.new(0, Theme.Size.SpacingM)
		sl.Parent = stepFrame

		table.insert(steps, stepFrame)
		return stepFrame
	end

	-- Step indicator
	local stepLabel = Instance.new("TextLabel")
	stepLabel.Size = UDim2.new(1, 0, 0, 16)
	stepLabel.BackgroundTransparency = 1
	stepLabel.Text = "Step 1 of 4"
	stepLabel.TextColor3 = Theme.Color.TextDim
	stepLabel.Font = Theme.Font.Regular
	stepLabel.TextSize = 10
	stepLabel.TextXAlignment = Enum.TextXAlignment.Center
	stepLabel.LayoutOrder = 0
	stepLabel.Parent = scroll

	--== STEP 1: Welcome ==--
	local s1 = createStep(1)
	Components.createLabel(s1, "Welcome to RoGit", { color = Theme.Color.Accent, font = Theme.Font.Bold, textSize = Theme.Size.TextHeader, layoutOrder = 0, alignment = Enum.TextXAlignment.Center })
	Components.createLabel(s1, "Git version control for Roblox Studio, powered by the GitHub API. This guide will help you get set up in under 2 minutes.", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 1, alignment = Enum.TextXAlignment.Center })

	self:_spacer(s1, 2)

	Components.createLabel(s1, "What you'll need:", { color = Theme.Color.Text, font = Theme.Font.Bold, textSize = Theme.Size.TextNormal, layoutOrder = 3 })
	Components.createLabel(s1, "1.  A GitHub account (free at github.com)", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 4 })
	Components.createLabel(s1, "2.  A repository to store your project", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 5 })
	Components.createLabel(s1, "3.  A Personal Access Token (PAT) for authentication", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 6 })

	self:_spacer(s1, 7)

	Components.createLabel(s1, "RoGit serializes your Studio instances into files and syncs them with GitHub. Scripts become .luau files, instances become .json files. Your full project structure is preserved.", { color = Theme.Color.TextDim, textSize = 10, layoutOrder = 8 })

	--== STEP 2: Create Repository ==--
	local s2 = createStep(2)
	Components.createLabel(s2, "Create a Repository", { color = Theme.Color.Accent, font = Theme.Font.Bold, textSize = Theme.Size.TextLarge, layoutOrder = 0, alignment = Enum.TextXAlignment.Center })

	self:_spacer(s2, 1)

	Components.createLabel(s2, "If you already have a repository, press the 'next' button to proceed to the next step.", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 2, alignment = Enum.TextXAlignment.Center })

	self:_spacer(s2, 3)

	Components.createLabel(s2, "To create a new repository:", { color = Theme.Color.Text, font = Theme.Font.Bold, textSize = Theme.Size.TextNormal, layoutOrder = 4 })
	Components.createLabel(s2, '1.  Go to github.com/new', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 5 })
	Components.createLabel(s2, '2.  Enter a repository name (e.g. "my-roblox-game")', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 6 })
	Components.createLabel(s2, "3.  Choose Private or Public", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 7 })
	Components.createLabel(s2, '4.  Check "Add a README file"', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 8 })
	Components.createLabel(s2, '5.  Click "Create repository"', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 9 })

	self:_spacer(s2, 10)

	Components.createLabel(s2, "Note your username and repo name. You'll need them in step 4.", { color = Theme.Color.Yellow, textSize = Theme.Size.TextSmall, layoutOrder = 11 })

	--== STEP 3: Generate PAT ==--
	local s3 = createStep(3)
	Components.createLabel(s3, "Generate a Token", { color = Theme.Color.Accent, font = Theme.Font.Bold, textSize = Theme.Size.TextLarge, layoutOrder = 0, alignment = Enum.TextXAlignment.Center })

	self:_spacer(s3, 1)

	Components.createLabel(s3, "A Personal Access Token (PAT) lets RoGit access your repository on your behalf.", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 2, alignment = Enum.TextXAlignment.Center })

	self:_spacer(s3, 3)

	Components.createLabel(s3, "To generate a token:", { color = Theme.Color.Text, font = Theme.Font.Bold, textSize = Theme.Size.TextNormal, layoutOrder = 4 })
	Components.createLabel(s3, '1.  Go to github.com/settings/tokens', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 5 })
	Components.createLabel(s3, '2.  Click "Generate new token" then "Classic"', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 6 })
	Components.createLabel(s3, '3.  Give it a name (e.g. "RoGit Studio")', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 7 })
	Components.createLabel(s3, '4.  Set expiration (90 days or no expiration)', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 8 })
	Components.createLabel(s3, '5.  Check the "repo" scope (full control of private repositories)', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 9 })
	Components.createLabel(s3, '6.  Click "Generate token" and copy it immediately', { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 10 })

	self:_spacer(s3, 11)

	Components.createLabel(s3, "The token starts with ghp_ and is only shown once. Copy it now!", { color = Theme.Color.Red, textSize = Theme.Size.TextSmall, layoutOrder = 12 })

	--== STEP 4: Connect ==--
	local s4 = createStep(4)
	Components.createLabel(s4, "Connect to GitHub", { color = Theme.Color.Accent, font = Theme.Font.Bold, textSize = Theme.Size.TextLarge, layoutOrder = 0, alignment = Enum.TextXAlignment.Center })

	self:_spacer(s4, 1)

	Components.createLabel(s4, "Enter your details below and connect:", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 2, alignment = Enum.TextXAlignment.Center })

	self:_spacer(s4, 3)

	Components.createLabel(s4, "Repository Owner (your GitHub username)", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 4 })
	self.refs.wizOwnerInput = Components.createInput(s4, { placeholder = "your-username", layoutOrder = 5 })

	Components.createLabel(s4, "Repository Name", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 6 })
	self.refs.wizRepoInput = Components.createInput(s4, { placeholder = "my-roblox-game", layoutOrder = 7 })

	Components.createLabel(s4, "Branch", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 8 })
	self.refs.wizBranchInput = Components.createInput(s4, { placeholder = "main", layoutOrder = 9 })

	Components.createLabel(s4, "Personal Access Token", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 10 })
	self.refs.wizTokenInput = Components.createInput(s4, { placeholder = "ghp_xxxxxxxxxxxxxxxxxxxx", layoutOrder = 11 })

	self:_spacer(s4, 12)
	
	local wizRemember = Components.createCheckbox(s4, { label = "Remember token", checked = true, layoutOrder = 13, labelColor = Theme.Color.TextMuted })

	self:_spacer(s4, 14)

	self.refs.wizStatus = Components.createLabel(s4, "", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 15, alignment = Enum.TextXAlignment.Center })

	Components.createButton(s4, {
		text = "Connect & Start", layoutOrder = 16,
		color = Theme.Color.Green, textColor = Theme.Color.Background,
		onClick = function()
			local owner = (self.refs.wizOwnerInput :: TextBox).Text:gsub("%s", "")
			local repo = (self.refs.wizRepoInput :: TextBox).Text:gsub("%s", "")
			local branch = (self.refs.wizBranchInput :: TextBox).Text:gsub("%s", "")
			local token = (self.refs.wizTokenInput :: TextBox).Text:gsub("%s", "")

			if branch == "" then branch = "main" end

			if owner == "" or repo == "" or token == "" then
				(self.refs.wizStatus :: TextLabel).Text = "Owner, repo, and token are required"
				(self.refs.wizStatus :: TextLabel).TextColor3 = Theme.Color.Red
				return
			end

			-- Fill connection panel fields so _connect reads them
			(self.refs.ownerInput :: TextBox).Text = owner;
			(self.refs.repoInput :: TextBox).Text = repo;
			(self.refs.tokenInput :: TextBox).Text = token;
			(self.refs.branchInput :: TextBox).Text = branch

			-- Set remember state before connecting
			local remember = (wizRemember :: Components.CheckboxHandle).getValue()
			;(self.refs.rememberCheckbox :: Components.CheckboxHandle).setValue(remember)

			self:_showView("connection")
			self:_connect()
		end,
	})

	--== Navigation ==--
	local navRow = Instance.new("Frame")
	navRow.Size = UDim2.new(1, 0, 0, 32)
	navRow.BackgroundTransparency = 1
	navRow.LayoutOrder = 2
	navRow.Parent = scroll

	local navLayout = Instance.new("UIListLayout")
	navLayout.FillDirection = Enum.FillDirection.Horizontal
	navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	navLayout.Padding = UDim.new(0, Theme.Size.SpacingM)
	navLayout.Parent = navRow

	local function showStep(step: number)
		currentStep = math.clamp(step, 1, #steps)
		for i, frame in steps do
			frame.Visible = i == currentStep
		end
		stepLabel.Text = `Step {currentStep} of {#steps}`
	end

	local backBtn = Components.createButton(navRow, {
		text = "Back", size = UDim2.fromOffset(80, 28), layoutOrder = 0,
		color = Theme.Color.Surface, textColor = Theme.Color.TextMuted,
		onClick = function()
			if currentStep == 1 then
				self:_showView("connection")
			else
				showStep(currentStep - 1)
			end
		end,
	})

	local nextBtn = Components.createButton(navRow, {
		text = "Next", size = UDim2.fromOffset(80, 28), layoutOrder = 1,
		color = Theme.Color.Accent, textColor = Theme.Color.Background,
		onClick = function() showStep(currentStep + 1) end,
	})

	Components.createButton(navRow, {
		text = "Skip", size = UDim2.fromOffset(60, 28), layoutOrder = 2,
		color = Theme.Color.Surface, textColor = Theme.Color.TextDim,
		onClick = function() self:_showView("connection") end,
	})
end

function App._buildConnectionPanel(self: App, parent: Frame)
	local panel = Instance.new("Frame")
	panel.Name = "ConnectionPanel"
	panel.Size = UDim2.new(1, 0, 1, -36)
	panel.Position = UDim2.fromOffset(0, 36)
	panel.BackgroundColor3 = Theme.Color.Background
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent
	self.refs.connectionPanel = panel

	local scroll = Components.createScrollFrame(panel)
	local sl = Instance.new("UIListLayout")
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Padding = UDim.new(0, Theme.Size.SpacingM)
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.Parent = scroll

	local sp = Instance.new("UIPadding")
	sp.PaddingTop = UDim.new(0, Theme.Size.SpacingXL * 2)
	sp.PaddingLeft = UDim.new(0, Theme.Size.SpacingXL)
	sp.PaddingRight = UDim.new(0, Theme.Size.SpacingXL)
	sp.PaddingBottom = UDim.new(0, Theme.Size.SpacingXL)
	sp.Parent = scroll

	Components.createLabel(scroll, "RoGit", { color = Theme.Color.Accent, font = Theme.Font.Bold, textSize = Theme.Size.TextHeader, layoutOrder = 0, alignment = Enum.TextXAlignment.Center })
	Components.createLabel(scroll, "Git for Roblox Studio via GitHub API", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 1, alignment = Enum.TextXAlignment.Center })

	self:_spacer(scroll, 2)

	Components.createLabel(scroll, "Repository Owner", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 3 })
	self.refs.ownerInput = Components.createInput(scroll, { placeholder = "your-username", layoutOrder = 4 })

	Components.createLabel(scroll, "Repository Name", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 5 })
	self.refs.repoInput = Components.createInput(scroll, { placeholder = "my-roblox-game", layoutOrder = 6 })

	Components.createLabel(scroll, "Branch", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 7 })
	self.refs.branchInput = Components.createInput(scroll, { placeholder = "main", layoutOrder = 8 })

	Components.createLabel(scroll, "Exclude Services (comma-separated)", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 9 })
	self.refs.excludedInput = Components.createInput(scroll, { placeholder = "e.g. Lighting, SoundService", layoutOrder = 10 })
	Components.createLabel(scroll, "Leave empty to sync all services. Excluding large/unused services reduces API usage.", { color = Theme.Color.TextDim, textSize = 10, layoutOrder = 11 })

	Components.createLabel(scroll, "Personal Access Token", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 12 })
	self.refs.tokenInput = Components.createInput(scroll, { placeholder = "ghp_xxxxxxxxxxxxxxxxxxxx", layoutOrder = 13 })

	-- Token masking: single TextBox, shows asterisks when masked
	local tokenBox = self.refs.tokenInput :: TextBox
	local updatingToken = false

	local function setTokenDisplay()
		updatingToken = true
		if self.tokenMasked then
			tokenBox.Text = if #self.tokenValue > 0 then string.rep("*", #self.tokenValue) else ""
		else
			tokenBox.Text = self.tokenValue
		end
		updatingToken = false
	end

	tokenBox:GetPropertyChangedSignal("Text"):Connect(function()
		if updatingToken then return end
		local newText = tokenBox.Text

		if not self.tokenMasked then
			-- Unmasked: text IS the token
			self.tokenValue = newText
			return
		end

		-- Masked mode: figure out what the user did
		if newText == "" then
			-- Selected all + deleted
			self.tokenValue = ""
		elseif not newText:find("%*") then
			-- No asterisks = fresh paste replacing everything
			self.tokenValue = newText
		elseif #newText > #self.tokenValue then
			-- Characters added: extract the non-asterisk chars and append
			local added = newText:gsub("%*", "")
			self.tokenValue = self.tokenValue .. added
		elseif #newText < #self.tokenValue then
			-- Characters removed: trim tokenValue to match new length
			self.tokenValue = self.tokenValue:sub(1, #newText)
		end

		setTokenDisplay()
	end)

	Components.createLabel(scroll, "Token needs 'repo' scope - github.com/settings/tokens", { color = Theme.Color.TextDim, textSize = 10, layoutOrder = 14 })

	self.refs.showTokenCheckbox = Components.createCheckbox(scroll, {
		label = "Show token", checked = false, layoutOrder = 15,
	})
	;(self.refs.showTokenCheckbox :: Components.CheckboxHandle).onChanged(function(show: boolean)
		self.tokenMasked = not show
		setTokenDisplay()
	end)

	self.refs.rememberCheckbox = Components.createCheckbox(scroll, {
		label = "Remember token", checked = false, layoutOrder = 16,
	})

	self:_spacer(scroll, 17)

	self.refs.connectBtn = Components.createButton(scroll, { text = "Connect", layoutOrder = 18, onClick = function() self:_connect() end })

	self.refs.cloneBtn = Components.createButton(scroll, {
		text = "Clone Repository", layoutOrder = 19,
		color = Theme.Color.Green, textColor = Theme.Color.Background,
		onClick = function() self:_showView("clone") end,
	})

	self.refs.gitInitBtn = Components.createButton(scroll, {
		text = "Git Init (Setup Project)", layoutOrder = 20,
		color = Theme.Color.Surface, textColor = Theme.Color.Text,
		onClick = function() self:gitInit() end,
	})

	self.refs.wizardBtn = Components.createButton(scroll, {
		text = "First Time? Setup Guide", layoutOrder = 21,
		color = Theme.Color.Surface, textColor = Theme.Color.Accent,
		onClick = function() self:_showView("wizard") end,
	})

	-- "Back to main" button only visible when connected
	self.refs.connBackBtn = Components.createButton(scroll, {
		text = "Back", layoutOrder = 23,
		color = Theme.Color.Surface, textColor = Theme.Color.TextMuted,
		onClick = function() self:_showView("main") end,
	})
	self.refs.connBackBtn.Visible = false

	self.refs.disconnectBtn = Components.createButton(scroll, {
		text = "Disconnect", layoutOrder = 22,
		color = Theme.Color.Red, textColor = Theme.Color.Text,
		onClick = function() self:_disconnect() end,
	})
	self.refs.disconnectBtn.Visible = false

	self.refs.connectionStatus = Components.createLabel(scroll, "", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 21, alignment = Enum.TextXAlignment.Center })
end

function App._buildMainPanel(self: App, parent: Frame)
	local main = Instance.new("Frame")
	main.Name = "MainPanel"
	main.Size = UDim2.new(1, 0, 1, -36)
	main.Position = UDim2.fromOffset(0, 36)
	main.BackgroundTransparency = 1
	main.Visible = false
	main.Parent = parent
	self.refs.mainPanel = main

	local scroll = Components.createScrollFrame(main)
	self.refs.mainScroll = scroll

	local ml = Instance.new("UIListLayout")
	ml.SortOrder = Enum.SortOrder.LayoutOrder
	ml.Padding = UDim.new(0, Theme.Size.SpacingS)
	ml.Parent = scroll

	local mp = Instance.new("UIPadding")
	mp.PaddingTop = UDim.new(0, Theme.Size.SpacingM)
	mp.PaddingBottom = UDim.new(0, Theme.Size.SpacingM)
	mp.Parent = scroll

	self:_buildCommitSection(scroll)
	self:_buildStagingSection(scroll)
	self:_buildMergeSection(scroll)
	self:_buildPRSection(scroll)
	self:_buildActionsSection(scroll)
	self:_buildReleasesSection(scroll)
	self:_buildActivitySection(scroll)
	self:_buildLogSection(scroll)
end

function App._buildCommitSection(self: App, parent: ScrollingFrame)
	local frame = Instance.new("Frame")
	frame.Name = "CommitSection"
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = 0
	frame.Parent = parent

	local fl = Instance.new("UIListLayout")
	fl.SortOrder = Enum.SortOrder.LayoutOrder
	fl.Padding = UDim.new(0, Theme.Size.SpacingS)
	fl.Parent = frame

	local fp = Instance.new("UIPadding")
	fp.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	fp.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	fp.Parent = frame

	self.refs.commitInput = Components.createInput(frame, {
		placeholder = "Commit message...", size = UDim2.new(1, 0, 0, 70),
		layoutOrder = 0, multiLine = true,
	})

	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, 0, 0, 32)
	btnRow.BackgroundTransparency = 1
	btnRow.LayoutOrder = 1
	btnRow.Parent = frame

	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Padding = UDim.new(0, Theme.Size.SpacingS)
	rl.Parent = btnRow

	Components.createButton(btnRow, {
		text = "Commit & Push", size = UDim2.new(0.55, -3, 0, 32), layoutOrder = 0,
		onClick = function() self:commitAndPush() end,
	})
	Components.createButton(btnRow, {
		text = "Pull", size = UDim2.new(0.45, -3, 0, 32), layoutOrder = 1,
		color = Theme.Color.Green, textColor = Theme.Color.Background,
		onClick = function() self:pull() end,
	})

	local _, updateProgress = Components.createProgressBar(frame, { layoutOrder = 2 })
	self.refs.updateProgress = updateProgress

	Components.createDivider(frame, 3)

	-- Auto-backup toggle
	self.refs.autoBackupCheckbox = Components.createCheckbox(frame, {
		label = "Auto-backup every 5 min", checked = false, layoutOrder = 4,
	})
	Components.createLabel(frame, "Automatically pushes all changes every 5 minutes with a generated commit message. Useful for continuous saving.", { color = Theme.Color.TextDim, textSize = 10, layoutOrder = 5 })
	;(self.refs.autoBackupCheckbox :: Components.CheckboxHandle).onChanged(function(enabled: boolean)
		self:_toggleAutoBackup(enabled)
	end)
end

function App._buildStagingSection(self: App, parent: ScrollingFrame)
	local section = Components.createSection(parent, {
		title = "Changed Files", count = 0, layoutOrder = 1,
		collapsible = true, actionText = "rbxassetid://102776660012261",
		onAction = function() self:_refreshStaging() end,
	})
	self.refs.stagingSection = section

	self.refs.stagingStatus = Components.createLabel(section.content, "Connect to see changes", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 0 })

	self.refs.stagingCheckboxes = Components.createCheckboxList(section.content, { items = {}, allChecked = false, layoutOrder = 1 })

	-- File history button row
	local histRow = Instance.new("Frame")
	histRow.Size = UDim2.new(1, 0, 0, 24)
	histRow.BackgroundTransparency = 1
	histRow.LayoutOrder = 2
	histRow.Parent = section.content

	local histPad = Instance.new("UIPadding")
	histPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	histPad.Parent = histRow

	Components.createIconButton(histRow, {
		icon = "?", tooltip = "File history (selected instance)", size = UDim2.fromOffset(70, 20),
		onClick = function()
			local selection = game:GetService("Selection"):Get()
			if #selection == 0 then
				self:_log("No instance selected in Explorer", Theme.Color.Yellow)
				return
			end

			local filePath = self.serializer:getInstanceFilePath(selection[1])
			if not filePath then
				self:_log(`No history found for "{selection[1].Name}"`, Theme.Color.Yellow)
				return
			end

			self:_showFileHistory(filePath)
		end,
	})
end

function App._buildLogSection(self: App, parent: ScrollingFrame)
	local section = Components.createSection(parent, {
		title = "Commit History", count = 0, layoutOrder = 2,
		collapsible = true, defaultCollapsed = true,
	})
	self.refs.logSection = section
end

function App._buildMergeSection(self: App, parent: ScrollingFrame)
	local section = Components.createSection(parent, {
		title = "Merge Branch", count = 0, layoutOrder = 3,
		collapsible = true, defaultCollapsed = true,
	})
	self.refs.mergeSection = section

	local fp = Instance.new("UIPadding")
	fp.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	fp.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	fp.Parent = section.content

	Components.createLabel(section.content, "Merge into current branch:", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 0 })

	local mergeDropdown = Components.createDropdown(section.content, {
		items = {}, placeholder = "Select branch...", layoutOrder = 1,
		maxVisibleItems = 6,
	})
	self.refs.mergeDropdown = mergeDropdown

	self.refs.mergeStatus = Components.createLabel(section.content, "", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 2 })

	Components.createButton(section.content, {
		text = "Merge", layoutOrder = 3, size = UDim2.new(1, 0, 0, 28),
		color = Theme.Color.Accent, textColor = Theme.Color.Background,
		onClick = function() self:_mergeBranch() end,
	})
end

--==============================--
--    PULL REQUESTS SECTION     --
--==============================--

function App._buildPRSection(self: App, parent: ScrollingFrame)
	local section = Components.createSection(parent, {
		title = "Pull Requests", count = 0, layoutOrder = 4,
		collapsible = true, defaultCollapsed = true,
		actionText = "rbxassetid://102776660012261",
		onAction = function() self:_refreshPRs() end,
	})
	self.refs.prSection = section

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	pad.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	pad.Parent = section.content

	-- Create PR controls
	Components.createLabel(section.content, "New Pull Request", { color = Theme.Color.Text, font = Theme.Font.Bold, textSize = Theme.Size.TextSmall, layoutOrder = 0 })

	Components.createLabel(section.content, "Title", { color = Theme.Color.TextMuted, textSize = 10, layoutOrder = 1 })
	self.refs.prTitleInput = Components.createInput(section.content, { placeholder = "PR title...", layoutOrder = 2 })

	Components.createLabel(section.content, "Description (optional)", { color = Theme.Color.TextMuted, textSize = 10, layoutOrder = 3 })
	self.refs.prBodyInput = Components.createInput(section.content, { placeholder = "Description...", layoutOrder = 4, multiLine = true, size = UDim2.new(1, 0, 0, 50) })

	Components.createLabel(section.content, "Base branch (merge into)", { color = Theme.Color.TextMuted, textSize = 10, layoutOrder = 5 })
	self.refs.prBaseDropdown = Components.createDropdown(section.content, {
		items = {}, placeholder = "main", layoutOrder = 6, maxVisibleItems = 6,
	})

	self.refs.prStatus = Components.createLabel(section.content, "", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 7 })

	Components.createButton(section.content, {
		text = "Create Pull Request", layoutOrder = 8, size = UDim2.new(1, 0, 0, 28),
		color = Theme.Color.Accent, textColor = Theme.Color.Background,
		onClick = function() self:_createPR() end,
	})

	Components.createDivider(section.content, 9)

	Components.createLabel(section.content, "Open PRs", { color = Theme.Color.Text, font = Theme.Font.Bold, textSize = Theme.Size.TextSmall, layoutOrder = 10 })

	self.refs.prListFrame = Instance.new("Frame")
	self.refs.prListFrame.Size = UDim2.new(1, 0, 0, 0)
	self.refs.prListFrame.AutomaticSize = Enum.AutomaticSize.Y
	self.refs.prListFrame.BackgroundTransparency = 1
	self.refs.prListFrame.LayoutOrder = 11
	self.refs.prListFrame.Parent = section.content

	local prListLayout = Instance.new("UIListLayout")
	prListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	prListLayout.Padding = UDim.new(0, 2)
	prListLayout.Parent = self.refs.prListFrame
end

--==============================--
--    ACTIONS STATUS SECTION    --
--==============================--

function App._buildActionsSection(self: App, parent: ScrollingFrame)
	local section = Components.createSection(parent, {
		title = "CI / Actions", count = 0, layoutOrder = 5,
		collapsible = true, defaultCollapsed = true,
		actionText = "rbxassetid://102776660012261",
		onAction = function() self:_refreshActions() end,
	})
	self.refs.actionsSection = section

	self.refs.actionsListFrame = Instance.new("Frame")
	self.refs.actionsListFrame.Size = UDim2.new(1, 0, 0, 0)
	self.refs.actionsListFrame.AutomaticSize = Enum.AutomaticSize.Y
	self.refs.actionsListFrame.BackgroundTransparency = 1
	self.refs.actionsListFrame.LayoutOrder = 0
	self.refs.actionsListFrame.Parent = section.content

	local actListLayout = Instance.new("UIListLayout")
	actListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actListLayout.Padding = UDim.new(0, 2)
	actListLayout.Parent = self.refs.actionsListFrame

	Components.createLabel(section.content, "Shows recent GitHub Actions workflow runs", { color = Theme.Color.TextDim, textSize = 10, layoutOrder = 1 })
end

--==============================--
--     RELEASES SECTION         --
--==============================--

function App._buildReleasesSection(self: App, parent: ScrollingFrame)
	local section = Components.createSection(parent, {
		title = "Tags / Releases", count = 0, layoutOrder = 6,
		collapsible = true, defaultCollapsed = true,
	})
	self.refs.releasesSection = section

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	pad.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	pad.Parent = section.content

	Components.createLabel(section.content, "Create Release", { color = Theme.Color.Text, font = Theme.Font.Bold, textSize = Theme.Size.TextSmall, layoutOrder = 0 })

	Components.createLabel(section.content, "Tag (e.g. v1.0.0)", { color = Theme.Color.TextMuted, textSize = 10, layoutOrder = 1 })
	self.refs.releaseTagInput = Components.createInput(section.content, { placeholder = "v1.0.0", layoutOrder = 2 })

	Components.createLabel(section.content, "Name (optional)", { color = Theme.Color.TextMuted, textSize = 10, layoutOrder = 3 })
	self.refs.releaseNameInput = Components.createInput(section.content, { placeholder = "Release name...", layoutOrder = 4 })

	Components.createLabel(section.content, "Notes (optional)", { color = Theme.Color.TextMuted, textSize = 10, layoutOrder = 5 })
	self.refs.releaseBodyInput = Components.createInput(section.content, { placeholder = "What changed...", layoutOrder = 6, multiLine = true, size = UDim2.new(1, 0, 0, 50) })

	self.refs.releaseStatus = Components.createLabel(section.content, "", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 7 })

	Components.createButton(section.content, {
		text = "Create Release", layoutOrder = 8, size = UDim2.new(1, 0, 0, 28),
		color = Theme.Color.Green, textColor = Theme.Color.Background,
		onClick = function() self:_createRelease() end,
	})

	Components.createDivider(section.content, 9)

	self.refs.releasesListFrame = Instance.new("Frame")
	self.refs.releasesListFrame.Size = UDim2.new(1, 0, 0, 0)
	self.refs.releasesListFrame.AutomaticSize = Enum.AutomaticSize.Y
	self.refs.releasesListFrame.BackgroundTransparency = 1
	self.refs.releasesListFrame.LayoutOrder = 10
	self.refs.releasesListFrame.Parent = section.content

	local relListLayout = Instance.new("UIListLayout")
	relListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	relListLayout.Padding = UDim.new(0, 2)
	relListLayout.Parent = self.refs.releasesListFrame
end

--==============================--
--    TEAM ACTIVITY SECTION     --
--==============================--

function App._buildActivitySection(self: App, parent: ScrollingFrame)
	local section = Components.createSection(parent, {
		title = "Team Activity", count = 0, layoutOrder = 6,
		collapsible = true, defaultCollapsed = true,
		actionText = "rbxassetid://102776660012261",
		onAction = function() self:_refreshActivity() end,
	})
	self.refs.activitySection = section

	self.refs.activityListFrame = Instance.new("Frame")
	self.refs.activityListFrame.Size = UDim2.new(1, 0, 0, 0)
	self.refs.activityListFrame.AutomaticSize = Enum.AutomaticSize.Y
	self.refs.activityListFrame.BackgroundTransparency = 1
	self.refs.activityListFrame.LayoutOrder = 0
	self.refs.activityListFrame.Parent = section.content

	local actLayout = Instance.new("UIListLayout")
	actLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actLayout.Padding = UDim.new(0, 2)
	actLayout.Parent = self.refs.activityListFrame
end

function App._buildDiffWidget(self: App)
	local root = Instance.new("Frame")
	root.Name = "DiffRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.Color.Background
	root.BorderSizePixel = 0
	root.Parent = self.diffWidget

	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 32)
	topBar.BackgroundColor3 = Theme.Color.Surface
	topBar.BorderSizePixel = 0
	topBar.Parent = root

	local tbPad = Instance.new("UIPadding")
	tbPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	tbPad.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	tbPad.Parent = topBar

	Components.createLabel(topBar, "Changes vs Remote", { color = Theme.Color.Text, font = Theme.Font.Bold, textSize = Theme.Size.TextNormal }).Position = UDim2.fromOffset(0, 6)

	self.refs.diffStatus = Instance.new("TextLabel")
	self.refs.diffStatus.Size = UDim2.fromOffset(160, 32)
	self.refs.diffStatus.Position = UDim2.new(1, -210, 0, 0)
	self.refs.diffStatus.BackgroundTransparency = 1
	self.refs.diffStatus.TextColor3 = Theme.Color.TextDim
	self.refs.diffStatus.Font = Theme.Font.Regular
	self.refs.diffStatus.TextSize = 10
	self.refs.diffStatus.TextXAlignment = Enum.TextXAlignment.Right
	self.refs.diffStatus.Parent = topBar

	Components.createIconButton(topBar, {
		icon = "Back", tooltip = "Back to main", size = UDim2.fromOffset(34, 22),
		onClick = function()
			self.diffWidget.Enabled = false
			self:_showView("main")
		end,
	}).Position = UDim2.new(1, -36, 0, 5)

	local diffViewer = Components.createDiffViewer(root, { size = UDim2.new(1, 0, 1, -32), layoutOrder = 1 })
	diffViewer.frame.Position = UDim2.fromOffset(0, 32)
	self.refs.diffViewer = diffViewer
	self.refs.diffRoot = root
end

function App._buildClonePanel(self: App, parent: Frame)
	local panel = Instance.new("Frame")
	panel.Name = "ClonePanel"
	panel.Size = UDim2.new(1, 0, 1, -36)
	panel.Position = UDim2.fromOffset(0, 36)
	panel.BackgroundColor3 = Theme.Color.Background
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent
	self.refs.clonePanel = panel

	local scroll = Components.createScrollFrame(panel)
	local sl = Instance.new("UIListLayout")
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Padding = UDim.new(0, Theme.Size.SpacingM)
	sl.Parent = scroll

	local sp = Instance.new("UIPadding")
	sp.PaddingTop = UDim.new(0, Theme.Size.SpacingXL * 2)
	sp.PaddingLeft = UDim.new(0, Theme.Size.SpacingXL)
	sp.PaddingRight = UDim.new(0, Theme.Size.SpacingXL)
	sp.Parent = scroll

	Components.createLabel(scroll, "Clone Repository", { color = Theme.Color.Accent, font = Theme.Font.Bold, textSize = Theme.Size.TextHeader, layoutOrder = 0, alignment = Enum.TextXAlignment.Center })
	Components.createLabel(scroll, "Pull a GitHub repo into Studio", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 1, alignment = Enum.TextXAlignment.Center })

	self:_spacer(scroll, 2)

	Components.createLabel(scroll, "Repository (owner/repo or https URL)", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 3 })
	self.refs.cloneRepoInput = Components.createInput(scroll, { placeholder = "owner/repo or https://github.com/...", layoutOrder = 4 })

	Components.createLabel(scroll, "Branch (default: main)", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 5 })
	self.refs.cloneBranchInput = Components.createInput(scroll, { placeholder = "main", layoutOrder = 6 })

	Components.createLabel(scroll, "Personal Access Token", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 7 })
	self.refs.cloneTokenInput = Components.createInput(scroll, { placeholder = "ghp_...", layoutOrder = 8 })

	self:_spacer(scroll, 9)

	Components.createButton(scroll, {
		text = "Clone", layoutOrder = 10,
		color = Theme.Color.Green, textColor = Theme.Color.Background,
		onClick = function() self:_performClone() end,
	})

	Components.createButton(scroll, {
		text = "Back", layoutOrder = 11,
		color = Theme.Color.Surface, textColor = Theme.Color.Text,
		onClick = function() self:_showView("connection") end,
	})

	self.refs.cloneStatus = Components.createLabel(scroll, "", { color = Theme.Color.TextMuted, textSize = Theme.Size.TextSmall, layoutOrder = 12, alignment = Enum.TextXAlignment.Center })
end

--==============================--
--     OUTPUT PANEL (DOCK)      --
--==============================--

function App._buildOutputUI(self: App)
	local root = Instance.new("Frame")
	root.Name = "OutputRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.Color.InputBg
	root.BorderSizePixel = 0
	root.Parent = self.outputWidget
	self.refs.outputRoot = root

	local outScroll = Instance.new("ScrollingFrame")
	outScroll.Size = UDim2.new(1, 0, 1, 0)
	outScroll.BackgroundTransparency = 1
	outScroll.BorderSizePixel = 0
	outScroll.ScrollBarThickness = 4
	outScroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
	outScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	outScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	outScroll.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 0)
	layout.Parent = outScroll

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	padding.PaddingTop = UDim.new(0, Theme.Size.SpacingS)
	padding.PaddingRight = UDim.new(0, Theme.Size.SpacingS)
	padding.Parent = outScroll

	-- Auto-scroll to bottom when canvas grows (new log lines).
	-- Respects manual scroll-up: if user scrolled up, auto-tail pauses.
	local pinnedToBottom = true
	outScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local maxY = math.max(0, outScroll.AbsoluteCanvasSize.Y - outScroll.AbsoluteWindowSize.Y)
		pinnedToBottom = outScroll.CanvasPosition.Y >= maxY - 5
	end)
	outScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if not pinnedToBottom then return end
		local maxY = math.max(0, outScroll.AbsoluteCanvasSize.Y - outScroll.AbsoluteWindowSize.Y)
		outScroll.CanvasPosition = Vector2.new(0, maxY)
	end)

	self.refs.outputScroll = outScroll
	self.outputLines = {}
	self.refs.outputLineCount = 0
end
--==============================--
--         UTILITIES            --
--==============================--

function App._spacer(_self: App, parent: GuiObject, order: number)
	local s = Instance.new("Frame")
	s.Size = UDim2.new(1, 0, 0, Theme.Size.SpacingM)
	s.BackgroundTransparency = 1
	s.LayoutOrder = order
	s.Parent = parent
end

function App._showView(self: App, view: string)
	self.activeView = view
	self.refs.wizardPanel.Visible = view == "wizard"
	self.refs.connectionPanel.Visible = view == "connection"
	self.refs.mainPanel.Visible = view == "main"
	self.refs.clonePanel.Visible = view == "clone"

	-- Header buttons: only visible on main view when connected
	local showHeader = self.connected and (view == "main")
	for _, item in self.refs.headerConnectedItems do
		item.Visible = showHeader
	end

	-- Connection panel button visibility
	if view == "connection" then
		local isConn = self.connected
		self.refs.connectBtn.Visible = not isConn
		self.refs.cloneBtn.Visible = not isConn
		self.refs.gitInitBtn.Visible = not isConn
		self.refs.wizardBtn.Visible = not isConn
		self.refs.disconnectBtn.Visible = isConn
		self.refs.connBackBtn.Visible = isConn
		-- Clear status when showing connected settings
		if isConn then self:_setStatus("") end
	end
end

function App._log(self: App, message: string, color: Color3?)
	local outScroll = self.refs.outputScroll :: ScrollingFrame
	local line = `[{os.date("%H:%M:%S")}] {message}`

	if not self.outputLines then self.outputLines = {} end
	table.insert(self.outputLines, line)

	self.refs.outputLineCount = (self.refs.outputLineCount or 0) + 1

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 0)
	local lbl = Instance.new("TextBox")
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.BackgroundTransparency = 1
	lbl.Text = line
	lbl.TextColor3 = color or Theme.Color.TextMuted
	lbl.Font = Theme.Font.Mono
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextWrapped = true
	lbl.TextEditable = false
	lbl.ClearTextOnFocus = false
	lbl.LayoutOrder = self.refs.outputLineCount
	lbl.Parent = outScroll
end

function App._clearOutput(self: App)
	self.outputLines = {}
	self.refs.outputLineCount = 0
	local outScroll = self.refs.outputScroll :: ScrollingFrame
	for _, child in outScroll:GetChildren() do
		if child:IsA("TextLabel") then child:Destroy() end
	end
end

function App._setStatus(self: App, text: string, color: Color3?)
	local lbl = self.refs.connectionStatus :: TextLabel
	lbl.Text = text
	lbl.TextColor3 = color or Theme.Color.TextMuted
end

function App._clearContainer(_self: App, container: Frame)
	for _, child in container:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
	end
end

function App._saveSettings(self: App)
	if not self.client then return end
	local c = self.client.config
	self.pluginRef:SetSetting(SETTING_OWNER, c.owner)
	self.pluginRef:SetSetting(SETTING_REPO, c.repo)
	self.pluginRef:SetSetting(SETTING_BRANCH, c.branch)

	local remember = (self.refs.rememberCheckbox :: Components.CheckboxHandle).getValue()
	self.pluginRef:SetSetting(SETTING_REMEMBER, remember)
	if remember then
		self.pluginRef:SetSetting(SETTING_TOKEN, c.token)
	else
		self.pluginRef:SetSetting(SETTING_TOKEN, "")
	end
end

function App._restoreSettings(self: App)
	local owner = self.pluginRef:GetSetting(SETTING_OWNER)
	local repo = self.pluginRef:GetSetting(SETTING_REPO)
	local branch = self.pluginRef:GetSetting(SETTING_BRANCH)
	local token = self.pluginRef:GetSetting(SETTING_TOKEN)
	local remember = self.pluginRef:GetSetting(SETTING_REMEMBER)

	if owner and owner ~= "" then (self.refs.ownerInput :: TextBox).Text = owner end
	if repo and repo ~= "" then (self.refs.repoInput :: TextBox).Text = repo end
	if branch and branch ~= "" then (self.refs.branchInput :: TextBox).Text = branch end

	if remember then
		(self.refs.rememberCheckbox :: Components.CheckboxHandle).setValue(true)
		if token and token ~= "" then
			(self.refs.tokenInput :: TextBox).Text = token
		end
	end

	-- Restore excluded services
	local excluded = self.pluginRef:GetSetting(SETTING_EXCLUDED)
	if excluded and excluded ~= "" then
		(self.refs.excludedInput :: TextBox).Text = excluded
	end

	-- Restore auto-backup state
	local autoBackup = self.pluginRef:GetSetting(SETTING_AUTOBACKUP)
	if autoBackup then
		-- Don't start the loop yet -- it starts after connect
	end
end

--==============================--
--          GIT INIT            --
--==============================--

function App.gitInit(self: App)
	local created: { string } = {}

	-- Create README in ServerStorage
	local ss = game:GetService("ServerStorage")
	if not ss:FindFirstChild("README") then
		local readme = Instance.new("ModuleScript")
		readme.Name = "README"
		readme.Source = 'local README = {\n[[\n# My Roblox Project\n\nManaged with RoGit.\n]]\n}\n\nreturn README'
		readme.Parent = ss
		table.insert(created, "ServerStorage/README")
	end

	-- Create .gitignore in common services
	local ignoreServices = { "ServerScriptService", "ReplicatedStorage", "StarterGui", "StarterPlayer", "ServerStorage", "Workspace" }
	for _, svcName in ignoreServices do
		local svc = game:FindService(svcName)
		if not svc then continue end
		if svc:FindFirstChild("_gitignore") or svc:FindFirstChild(".gitignore") then continue end

		local ignore = Instance.new("ModuleScript")
		ignore.Name = "_gitignore"
		ignore.Source = '-- Add instance names to ignore during git operations\n-- Example: return { "TestFolder", "DebugScript" }\n\nreturn {\n\n}'
		ignore.Parent = svc
		table.insert(created, `{svcName}/_gitignore`)
	end

	if #created > 0 then
		self:_log(`Git init: created {#created} files`, Theme.Color.Green)
		for _, path in created do
			self:_log(`  + {path}`, Theme.Color.Green)
		end
		self:_setStatus(`Created {#created} files`, Theme.Color.Green)
		ChangeHistoryService:SetWaypoint("RoGit: Git Init")
	else
		self:_setStatus("Already initialized (files exist)", Theme.Color.Yellow)
		self:_log("Git init: project already has gitignore/readme", Theme.Color.Yellow)
	end
end

--==============================--
--      CONNECT / DISCONNECT    --
--==============================--

function App._connect(self: App)
	local owner = (self.refs.ownerInput :: TextBox).Text:gsub("%s", "")
	local repo = (self.refs.repoInput :: TextBox).Text:gsub("%s", "")
	local branch = (self.refs.branchInput :: TextBox).Text:gsub("%s", "")
	local token = self.tokenValue:gsub("%s", "")

	if owner == "" or repo == "" or token == "" then
		self:_setStatus("Owner, repo, and token are required", Theme.Color.Red)
		return
	end
	if branch == "" then branch = "main" end

	-- Parse excluded services and rebuild serializer
	local excludedRaw = (self.refs.excludedInput :: TextBox).Text
	local excludedSet: { [string]: boolean } = {}
	for svc in excludedRaw:gmatch("[^,]+") do
		local trimmed = svc:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then excludedSet[trimmed] = true end
	end
	local DEFAULT_SERVICES = { "ServerScriptService", "ReplicatedStorage", "StarterGui", "StarterPlayer", "ServerStorage", "StarterPack", "Lighting", "SoundService", "ReplicatedFirst", "Workspace" }
	local filteredServices: { string } = {}
	for _, svc in DEFAULT_SERVICES do
		if not excludedSet[svc] then table.insert(filteredServices, svc) end
	end
	self.serializer = InstanceSerializerModule.new(filteredServices)
	self.pluginRef:SetSetting(SETTING_EXCLUDED, excludedRaw)

	self:_setStatus("Connecting...", Theme.Color.Yellow)

	task.spawn(function()
		local config: GitHubConfig = { owner = owner, repo = repo, token = token, branch = branch }
		local client = GitHubClientModule.new(config)

		local testR = client:testConnection()
		if not testR.ok then
			self:_setStatus(`Failed: {testR.error}`, Theme.Color.Red)
			return
		end

		local refR = client:getRef(branch)
		if not refR.ok then
			self:_setStatus(`Branch '{branch}' not found: {refR.error}`, Theme.Color.Red)
			return
		end

		self.client = client
		self.connected = true
		self.currentBranch = branch
		self:_saveSettings()
		self:_setStatus("") -- Clear "Connecting..."
		self:_log(`Connected to {owner}/{repo} on {branch}`, Theme.Color.Green)
		self:_showView("main")
		self:_refreshBranches()
		self:_fetchRemoteState()

		-- Start auto-backup if was previously enabled
		local autoBackupChecked = (self.refs.autoBackupCheckbox :: Components.CheckboxHandle).getValue()
		if autoBackupChecked and not self.autoBackupEnabled then
			self:_toggleAutoBackup(true)
		end
	end)
end

function App._disconnect(self: App)
	-- Stop auto-backup if running
	if self.autoBackupEnabled then
		self.autoBackupEnabled = false
		if self.autoBackupThread then
			task.cancel(self.autoBackupThread)
			self.autoBackupThread = nil
		end
	end
	-- Only wipe token if "Remember" is unchecked.
	-- If checked, keep in memory + UI so reconnect is seamless.
	local remember = (self.refs.rememberCheckbox :: Components.CheckboxHandle).getValue()
	if not remember then
		self.tokenValue = ""
		;(self.refs.tokenInput :: TextBox).Text = ""
		self.pluginRef:SetSetting(SETTING_TOKEN, "")
	end

	self.client = nil
	self.connected = false
	self.remoteFiles = {}
	self.remoteTreeEntries = {}
	self.remoteReady = false
	self.changedFiles = {}
	self.currentBranch = "main"
	self.branches = {}

	local dropdown = self.refs.branchDropdown :: Components.DropdownHandle
	dropdown.setItems({ "main" })
	dropdown.setSelected("main")

	local checkboxList = self.refs.stagingCheckboxes :: Components.CheckboxListHandle
	checkboxList.setItems({})

	local stagingStatus = self.refs.stagingStatus :: TextLabel
	stagingStatus.Text = "Connect to see changes"
	stagingStatus.Visible = true

	local section = self.refs.stagingSection :: Components.SectionHandle
	section.updateCount(0)

	local logSection = self.refs.logSection :: Components.SectionHandle
	self:_clearContainer(logSection.content)
	logSection.updateCount(0)

	-- Clear new sections
	local prSection = self.refs.prSection :: Components.SectionHandle
	prSection.updateCount(0)
	self:_clearContainer(self.refs.prListFrame)

	local actionsSection = self.refs.actionsSection :: Components.SectionHandle
	actionsSection.updateCount(0)
	self:_clearContainer(self.refs.actionsListFrame)

	local releasesSection = self.refs.releasesSection :: Components.SectionHandle
	releasesSection.updateCount(0)
	self:_clearContainer(self.refs.releasesListFrame)

	local activitySection = self.refs.activitySection :: Components.SectionHandle
	activitySection.updateCount(0)
	self:_clearContainer(self.refs.activityListFrame)

	self:_log("Disconnected", Theme.Color.Red)
	self:_setStatus("Disconnected", Theme.Color.TextMuted)
	self:_showView("connection")
end

--==============================--
--      REMOTE STATE            --
--==============================--

function App._fetchRemoteState(self: App)
	if not self.client then return end

	self:_log("Fetching remote state...")
	local stagingStatus = self.refs.stagingStatus :: TextLabel
	stagingStatus.Text = "Fetching remote..."
	stagingStatus.Visible = true

	task.spawn(function()
		local ok, err = pcall(function()
			local client = self.client :: GitHubClientModule.GitHubClient
			local treeR = client:pullTree()
			if not treeR.ok then
				self:_log(`Remote fetch failed: {treeR.error}`, Theme.Color.Red)
				stagingStatus.Text = "Failed to fetch remote"
				return
			end

			local entries = treeR.data :: { TreeEntry }

			-- Filter out entries from excluded services before downloading blobs.
			-- This is where the real API savings happen (1 request per blob skipped).
			local excludedRaw = (self.refs.excludedInput :: TextBox).Text
			local excludedSet: { [string]: boolean } = {}
			for svc in excludedRaw:gmatch("[^,]+") do
				local trimmed = svc:gsub("^%s+", ""):gsub("%s+$", "")
				if trimmed ~= "" then excludedSet[trimmed] = true end
			end
			if next(excludedSet) then
				local filtered: { TreeEntry } = {}
				for _, entry in entries do
					local firstSeg = entry.path:match("^([^/]+)")
					if not firstSeg or not excludedSet[firstSeg] then
						table.insert(filtered, entry)
					end
				end
				local skipped = #entries - #filtered
				if skipped > 0 then
					self:_log(`Skipped {skipped} files from excluded services`, Theme.Color.TextDim)
				end
				entries = filtered
			end

			self.remoteTreeEntries = entries
			self:_log(`Found {#entries} remote files, downloading...`)

			local contents = client:pullFileContents(entries, function(done, total)
				stagingStatus.Text = `Fetching... {done}/{total}`
			end)

			self.remoteFiles = contents
			self.remoteReady = true
			self:_log(`Remote state cached ({#entries} files)`, Theme.Color.Green)
			self:_refreshStaging()
			-- Only fetch metadata for sections that are expanded (visible).
			-- Saves 4-5 API calls when sections are collapsed, avoiding rate limits.
			local function sectionVisible(ref: string): boolean
				local s = self.refs[ref]
				return s and (s :: Components.SectionHandle).content.Visible
			end
			self:_refreshLog() -- Always load commit history (1 API call, always useful)
			if sectionVisible("prSection") then self:_refreshPRs() end
			if sectionVisible("actionsSection") then self:_refreshActions() end
			if sectionVisible("releasesSection") then self:_refreshReleases() end
			if sectionVisible("activitySection") then self:_refreshActivity() end
		end)

		if not ok then
			self:_log(`Fetch error: {err}`, Theme.Color.Red)
			stagingStatus.Text = "Error fetching remote"
		end
	end)
end

function App._refreshBranches(self: App)
	if not self.client then return end
	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):getBranches()
		if not r.ok then return end
		local names: { string } = {}
		for _, b in r.data :: { BranchInfo } do table.insert(names, b.name) end
		self.branches = names
		local dropdown = self.refs.branchDropdown :: Components.DropdownHandle
		dropdown.setItems(names)
		dropdown.setSelected(self.currentBranch)

		-- Update merge dropdown with other branches (exclude current)
		local mergeNames: { string } = {}
		for _, name in names do
			if name ~= self.currentBranch then table.insert(mergeNames, name) end
		end
		local mergeDropdown = self.refs.mergeDropdown :: Components.DropdownHandle
		mergeDropdown.setItems(mergeNames)
	end)
end

function App._switchBranch(self: App, name: string)
	if not self.client or name == self.currentBranch then return end
	task.spawn(function()
		self:_log(`Switching to: {name}`)
		local refR = (self.client :: GitHubClientModule.GitHubClient):getRef(name)
		if not refR.ok then self:_log(`Branch '{name}' not found: {refR.error}`, Theme.Color.Red); return end
		(self.client :: GitHubClientModule.GitHubClient).config.branch = name
		self.currentBranch = name
		self.remoteReady = false
		self:_saveSettings()
		self:_log(`Switched to {name}`, Theme.Color.Green)
		self:_fetchRemoteState()
	end)
end

function App._createBranch(self: App, name: string)
	if not self.client then return end
	task.spawn(function()
		self:_log(`Creating branch: {name}`)
		local refR = (self.client :: GitHubClientModule.GitHubClient):getRef(self.currentBranch)
		if not refR.ok then self:_log(`Failed: {refR.error}`, Theme.Color.Red); return end
		local createR = (self.client :: GitHubClientModule.GitHubClient):createBranch(name, refR.data :: string)
		if not createR.ok then self:_log(`Failed: {createR.error}`, Theme.Color.Red); return end
		self:_log(`Created branch: {name}`, Theme.Color.Green)
		-- Immediately add to dropdown so it's selectable
		if not table.find(self.branches, name) then
			table.insert(self.branches, name)
		end
		local dropdown = self.refs.branchDropdown :: Components.DropdownHandle
		dropdown.setItems(self.branches)
		self:_switchBranch(name)
		-- Also refresh from GitHub to get full list
		self:_refreshBranches()
	end)
end

--==============================--
--      REFRESH / STAGING       --
--==============================--

function App.refresh(self: App)
	if not self.client or self.busy then return end
	self:_fetchRemoteState()
	self:_refreshBranches()
end

function App._refreshStaging(self: App)
	local stagingStatus = self.refs.stagingStatus :: TextLabel
	local section = self.refs.stagingSection :: Components.SectionHandle
	local checkboxList = self.refs.stagingCheckboxes :: Components.CheckboxListHandle

	if not self.remoteReady then
		stagingStatus.Text = "Fetch remote first (click Ref)"
		stagingStatus.Visible = true
		checkboxList.setItems({})
		section.updateCount(0)
		return
	end

	local localFiles = self.serializer:getFileContentsMap()
	local remoteFiles = self.remoteFiles

	-- Build excluded services set so remote-only paths from excluded services
	-- don't show as [D] deleted in staging.
	local excludedRaw = (self.refs.excludedInput :: TextBox).Text
	local excludedSet: { [string]: boolean } = {}
	for svc in excludedRaw:gmatch("[^,]+") do
		local trimmed = svc:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then excludedSet[trimmed] = true end
	end
	local function isExcludedPath(path: string): boolean
		local firstSeg = path:match("^([^/]+)")
		return firstSeg ~= nil and excludedSet[firstSeg] == true
	end

	local STATUS_COLORS: { [string]: Color3 } = { added = Theme.Color.Green, modified = Theme.Color.Yellow, deleted = Theme.Color.Red }
	local STATUS_PREFIX: { [string]: string } = { added = "[A] ", modified = "[M] ", deleted = "[D] " }

	local changed: { ChangedFile } = {}
	local allLocalPaths: { [string]: boolean } = {}

	-- Normalize both sides before comparing to avoid phantom diffs
	-- from trailing whitespace, CRLF, or invisible character differences.
	local function normalize(s: string): string
		return s:gsub(string.char(13) .. "\n", "\n"):gsub(string.char(13), "\n"):gsub("%s+$", "")
	end

	for path, content in localFiles do
		allLocalPaths[path] = true
		local remoteContent = remoteFiles[path]
		if not remoteContent then
			table.insert(changed, { path = path, status = "added", localContent = content })
		elseif normalize(content) ~= normalize(remoteContent) then
			table.insert(changed, { path = path, status = "modified", localContent = content })
		end
	end

	for path, _ in remoteFiles do
		if not allLocalPaths[path] and not isExcludedPath(path) then
			table.insert(changed, { path = path, status = "deleted", localContent = nil })
		end
	end

	table.sort(changed, function(a, b)
		if a.status ~= b.status then
			local order = { added = 1, modified = 2, deleted = 3 }
			return (order[a.status] or 4) < (order[b.status] or 4)
		end
		return a.path < b.path
	end)

	self.changedFiles = changed

	if #changed == 0 then
		stagingStatus.Text = "No changes detected"
		stagingStatus.Visible = true
		checkboxList.setItems({})
		section.updateCount(0)
		return
	end

	stagingStatus.Visible = false

	local items: { { path: string, color: Color3? } } = {}
	for _, file in changed do
		table.insert(items, { path = (STATUS_PREFIX[file.status] or "") .. file.path, color = STATUS_COLORS[file.status] or Theme.Color.Text })
	end

	checkboxList.setItems(items)
	section.updateCount(#changed)
end

function App._refreshLog(self: App)
	if not self.client then return end
	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):getCommits(self.currentBranch, 20)
		if not r.ok then self:_log(`Log: {r.error}`, Theme.Color.Red); return end
		local commits = r.data :: { CommitInfo }
		local section = self.refs.logSection :: Components.SectionHandle
		self:_clearContainer(section.content)
		section.updateCount(#commits)
		for i, commit in commits do
			Components.createCommitRow(section.content, {
				shortSha = commit.shortSha, message = commit.message,
				author = commit.author, date = commit.date, layoutOrder = i,
				onRevert = function(sha: string) self:_revertCommit(sha, commit.sha) end,
			})
		end
	end)
end

--==============================--
--      COMMIT & PUSH           --
--==============================--

function App.commitAndPush(self: App)
	if not self.client or self.busy then return end

	local commitInput = self.refs.commitInput :: TextBox
	local message = commitInput.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if message == "" then self:_log("Commit message required", Theme.Color.Red); return end

	local checkboxList = self.refs.stagingCheckboxes :: Components.CheckboxListHandle
	local selectedLabels = checkboxList.getChecked()
	if #selectedLabels == 0 then self:_log("No files selected", Theme.Color.Red); return end

	-- Build selected paths from changedFiles by matching label prefixes
	local selectedChanges: { ChangedFile } = {}
	local STATUS_PREFIX: { [string]: string } = { added = "[A] ", modified = "[M] ", deleted = "[D] " }
	local labelSet: { [string]: boolean } = {}
	for _, label in selectedLabels do labelSet[label] = true end

	for _, file in self.changedFiles do
		local prefix = STATUS_PREFIX[file.status] or ""
		if labelSet[prefix .. file.path] then
			table.insert(selectedChanges, file)
		end
	end

	if #selectedChanges == 0 then self:_log("No valid changes", Theme.Color.Red); return end

	self.busy = true
	task.spawn(function()
		local pushOk, pushErr = pcall(function()
			local hasDeletions = false
			local entries: { TreeEntry } = {}

			for _, file in selectedChanges do
				if file.status == "deleted" then
					hasDeletions = true
					table.insert(entries, { path = file.path, mode = "100644", type = "blob" })
				else
					table.insert(entries, { path = file.path, mode = "100644", type = "blob", content = file.localContent })
				end
			end

			self:_log(`Pushing {#entries} changes...`)
			self.refs.updateProgress(0.3)

			local r = (self.client :: GitHubClientModule.GitHubClient):pushChanges(
				entries, if hasDeletions then self.remoteTreeEntries else nil, hasDeletions, message
			)

			self.refs.updateProgress(1)
			task.delay(1, function() self.refs.updateProgress(0) end)

			if r.ok then
				local sha = (r.data :: string):sub(1, 7)
				self:_log(`Pushed {sha}: {message}`, Theme.Color.Green)
				commitInput.Text = ""
				self.remoteReady = false
				ChangeHistoryService:SetWaypoint(`RoGit: {message}`)
				task.delay(1.5, function()
					if not self.destroyed then self:_fetchRemoteState() end
				end)
			else
				self:_log(`Push failed: {r.error}`, Theme.Color.Red)
			end
		end)

		if not pushOk then
			self:_log(`Push error: {pushErr}`, Theme.Color.Red)
		end
		self.busy = false
	end)
end

function App._quickPush(self: App)
	if not self.client or self.busy then return end
	if not self.remoteReady then
		self:_log("Remote not ready, fetching...", Theme.Color.Yellow)
		self:_fetchRemoteState()
		return
	end

	local commitInput = self.refs.commitInput :: TextBox
	local msg = commitInput.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then msg = `Update from Studio ({os.date("%Y-%m-%d %H:%M")})` end

	local fileCount = #self.changedFiles
	if fileCount == 0 then
		self:_log("No changes to push", Theme.Color.Yellow)
		return
	end
	-- Confirm dialog before pushing all
	Components.showConfirmDialog(self.widget, {
		title = "Push All Changes",
		message = `Push {fileCount} file(s) to {self.currentBranch}?\n\nMessage: "{msg}"`,
		confirmText = "Push",
		cancelText = "Cancel",
		onConfirm = function()
			commitInput.Text = msg
			local checkboxList = self.refs.stagingCheckboxes :: Components.CheckboxListHandle
			checkboxList.setAll(true)
			task.defer(function() self:commitAndPush() end)
		end,
	})
end

--==============================--
--           PULL               --
--==============================--

function App.pull(self: App)
	if not self.client or self.busy then return end
	-- Gate cold pull: force remote state fetch first
	if not self.remoteReady then
		self:_log("Fetching remote state before pull (first sync)...", Theme.Color.Yellow)
		self.busy = true
		task.spawn(function()
			local ok, err = pcall(function()
				local client = self.client :: GitHubClientModule.GitHubClient
				local treeR = client:pullTree()
				if not treeR.ok then
					self:_log(`Remote fetch failed: {treeR.error}`, Theme.Color.Red)
					return
				end
				local entries = treeR.data :: { TreeEntry }
				self.remoteTreeEntries = entries
				local contents = client:pullFileContents(entries)
				self.remoteFiles = contents
				self.remoteReady = true
				self:_log("Remote state cached. Pull is now safe.", Theme.Color.Green)
			end)
			if not ok then self:_log(`Fetch error: {err}`, Theme.Color.Red) end
			self.busy = false
			-- Now do the actual pull with conflict detection enabled
			if self.remoteReady then self:pull() end
		end)
		return
	end

	self.busy = true
	task.spawn(function()
		-- pcall wrapper with guaranteed busy reset
		local pullOk, pullErr = pcall(function()
			self:_log("Fetching tree...")
			self.refs.updateProgress(0.1)
			local client = self.client :: GitHubClientModule.GitHubClient
			local treeR = client:pullTree()
			if not treeR.ok then
				self:_log(`Pull failed: {treeR.error}`, Theme.Color.Red)
				self.refs.updateProgress(0)
				return
			end
			local entries = treeR.data :: { TreeEntry }
			self.remoteTreeEntries = entries
			self:_log(`Found {#entries} files...`)
			self.refs.updateProgress(0.2)

			local newRemote = client:pullFileContents(entries, function(done, total)
				self.refs.updateProgress(0.2 + 0.6 * (done / total))
			end)

			-- Conflict detection (only when we have cached remote)
			local conflicts: { { path: string, localContent: string, remoteContent: string } } = {}
			if self.remoteReady then
				local localFiles = self.serializer:getFileContentsMap()
				for path, localContent in localFiles do
					local oldRemote = self.remoteFiles[path]
					local newRemoteContent = newRemote[path]
					if oldRemote and localContent ~= oldRemote then
						if newRemoteContent and newRemoteContent ~= oldRemote then
							table.insert(conflicts, {
								path = path,
								localContent = localContent,
								remoteContent = newRemoteContent,
							})
						end
					end
				end
			end

			if #conflicts > 0 then
				local conflictPaths: { [string]: boolean } = {}
				for _, c in conflicts do conflictPaths[c.path] = true end
				-- Build safe apply set: skip conflicts and dirty local-only
				-- edits (preserve them just like in the no-conflict path).
				local oldRemoteForFilter = self.remoteFiles
				local localFilesForFilter = self.serializer:getFileContentsMap()
				local safeRemote: { [string]: string } = {}
				local preservedCount = 0
				for path, content in newRemote do
					if conflictPaths[path] then continue end
					local localContent = localFilesForFilter[path]
					local oldContent = oldRemoteForFilter[path]
					if localContent == nil or localContent == oldContent then
						safeRemote[path] = content
					else
						preservedCount += 1
					end
				end
				if preservedCount > 0 then
					self:_log(`Preserved {preservedCount} file(s) with unpushed local edits`, Theme.Color.Yellow)
				end

				-- Apply non-conflicting with ChangeHistoryService recording
				self.applyingRemote = true
				local oldRemote = self.remoteFiles
				local recordId = ChangeHistoryService:TryBeginRecording("RoGit: Pull (non-conflicting)")
				local created, updated, _ = self.serializer:applyFromFiles(safeRemote)

				-- Reconcile non-conflicting deletions
				if oldRemote and next(oldRemote) ~= nil then
					-- Skip conflicting files (pending resolution)
					local newWithConflicts = {}
					for path, content in newRemote do newWithConflicts[path] = content end
					for path in conflictPaths do newWithConflicts[path] = oldRemote[path] or "" end
					local delCount = self.serializer:reconcileDeleted(oldRemote, newWithConflicts)
					if delCount > 0 then
						self:_log(`Deleted {delCount} remotely-removed file(s)`, Theme.Color.Yellow)
					end
				end

				if recordId then ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Commit) end
				self.applyingRemote = false

				self:_log(`Applied {created + updated} non-conflicting files`, Theme.Color.Green)

				self.remoteFiles = newRemote
				self.remoteReady = true
				self.refs.updateProgress(1)
				task.delay(1, function() self.refs.updateProgress(0) end)
				self:_log(`{#conflicts} conflict(s) need resolution`, Theme.Color.Yellow)
				self.busy = false

				self:_showConflictResolver(conflicts, newRemote)
				return
			end

			-- No conflicts: apply remote changes while preserving local-only edits.
			-- Only writes when local is missing or matches the cached remote baseline.
			-- Dirty local edits (local ~= oldRemote) are skipped so that an
			-- accidental Pull never clobbers unpushed work.
			local oldRemote = self.remoteFiles
			local localFilesForFilter = self.serializer:getFileContentsMap()
			local toApply: { [string]: string } = {}
			local preservedCount = 0
			for path, content in newRemote do
				local localContent = localFilesForFilter[path]
				local oldContent = oldRemote[path]
				if localContent == nil or localContent == oldContent then
					toApply[path] = content
				else
					preservedCount += 1
				end
			end
			self.remoteFiles = newRemote
			self.remoteReady = true
			self:_log("Applying...")
			self.refs.updateProgress(0.85)

			if preservedCount > 0 then
				self:_log(`Preserved {preservedCount} file(s) with unpushed local edits`, Theme.Color.Yellow)
			end

			self.applyingRemote = true
			local recordId = ChangeHistoryService:TryBeginRecording("RoGit: Pull")
			local created, updated, _ = self.serializer:applyFromFiles(toApply)

			-- Reconcile deletions: files in old remote but not in new remote
			local deleted = 0
			if oldRemote and next(oldRemote) ~= nil then
				deleted = self.serializer:reconcileDeleted(oldRemote, newRemote)
			end

			if recordId then ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Commit) end
			self.applyingRemote = false

			self.refs.updateProgress(1)
			task.delay(1, function() self.refs.updateProgress(0) end)

			self:_log(`Pull: {created} created, {updated} updated, {deleted} deleted`, Theme.Color.Green)
			self:_refreshStaging()
			self:_refreshLog()
		end)

		if not pullOk then
			self:_log(`Pull error: {pullErr}`, Theme.Color.Red)
			self.applyingRemote = false
		end
		self.busy = false
	end)
end

--==============================--
--   DIFF WIDGET STATE MGMT    --
--==============================--

-- Centralized cleanup: removes all overlay panels and restores the diff viewer
function App._cleanDiffOverlays(self: App)
	local root = self.refs.diffRoot :: Frame
	for _, name in { "HistoryScroll", "SearchPanel", "ConflictPanel" } do
		local existing = root:FindFirstChild(name)
		if existing then existing:Destroy() end
	end
	local diffViewer = self.refs.diffViewer :: Components.DiffViewerHandle
	diffViewer.frame.Visible = true
end

-- Opens the diff widget fresh, cleaning any previous overlay state
function App._openDiffWidget(self: App, title: string)
	if self.diffWidget.Enabled then
		self.diffWidget.Enabled = false
		task.wait()
	end
	self.diffWidget.Enabled = true
	self.diffWidget.Title = title
	self:_cleanDiffOverlays()
end

--==============================--
--     CONFLICT RESOLUTION      --
--==============================--

function App._showConflictResolver(self: App, conflicts: { { path: string, localContent: string, remoteContent: string } }, newRemote: { [string]: string })
	self:_openDiffWidget(`Resolve {#conflicts} Conflict(s)`)

	local diffViewer = self.refs.diffViewer :: Components.DiffViewerHandle
	diffViewer.frame.Visible = false
	self.refs.diffStatus.Text = `{#conflicts} conflicts`

	local root = self.refs.diffRoot :: Frame

	-- Resolution state: track per-file choice
	local resolutions: { [string]: string } = {} -- path -> "theirs" | "mine"
	local resolvedCount = 0

	-- Build the conflict panel
	local conflictPanel = Instance.new("Frame")
	conflictPanel.Name = "ConflictPanel"
	conflictPanel.Size = UDim2.new(1, 0, 1, -32)
	conflictPanel.Position = UDim2.fromOffset(0, 32)
	conflictPanel.BackgroundColor3 = Theme.Color.InputBg
	conflictPanel.BorderSizePixel = 0
	conflictPanel.ClipsDescendants = true
	conflictPanel.Parent = root

	-- Left: file list (180px)
	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 180, 1, 0)
	sidebar.BackgroundColor3 = Theme.Color.Background
	sidebar.BorderSizePixel = 0
	sidebar.Parent = conflictPanel

	local sbBorder = Instance.new("Frame")
	sbBorder.Size = UDim2.new(0, 1, 1, 0)
	sbBorder.Position = UDim2.new(1, -1, 0, 0)
	sbBorder.BackgroundColor3 = Theme.Color.Border
	sbBorder.BorderSizePixel = 0
	sbBorder.Parent = sidebar

	local sbHeader = Instance.new("Frame")
	sbHeader.Size = UDim2.new(1, 0, 0, 28)
	sbHeader.BackgroundColor3 = Theme.Color.Surface
	sbHeader.BorderSizePixel = 0
	sbHeader.Parent = sidebar

	local sbTitle = Instance.new("TextLabel")
	sbTitle.Size = UDim2.new(1, -8, 1, 0)
	sbTitle.Position = UDim2.fromOffset(8, 0)
	sbTitle.BackgroundTransparency = 1
	sbTitle.Text = `Conflicts ({#conflicts})`
	sbTitle.TextColor3 = Theme.Color.Red
	sbTitle.Font = Theme.Font.Bold
	sbTitle.TextSize = Theme.Size.TextSmall
	sbTitle.TextXAlignment = Enum.TextXAlignment.Left
	sbTitle.Parent = sbHeader

	local sbScroll = Instance.new("ScrollingFrame")
	sbScroll.Size = UDim2.new(1, 0, 1, -28)
	sbScroll.Position = UDim2.fromOffset(0, 28)
	sbScroll.BackgroundTransparency = 1
	sbScroll.BorderSizePixel = 0
	sbScroll.ScrollBarThickness = 3
	sbScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sbScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	sbScroll.Parent = sidebar

	local sbLayout = Instance.new("UIListLayout")
	sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sbLayout.Parent = sbScroll

	-- Right: diff content area
	local contentArea = Instance.new("Frame")
	contentArea.Size = UDim2.new(1, -180, 1, 0)
	contentArea.Position = UDim2.fromOffset(180, 0)
	contentArea.BackgroundColor3 = Theme.Color.InputBg
	contentArea.BorderSizePixel = 0
	contentArea.ClipsDescendants = true
	contentArea.Parent = conflictPanel

	-- Top action bar
	local actionBar = Instance.new("Frame")
	actionBar.Size = UDim2.new(1, 0, 0, 32)
	actionBar.BackgroundColor3 = Theme.Color.Surface
	actionBar.BorderSizePixel = 0
	actionBar.Parent = contentArea

	local actionPad = Instance.new("UIPadding")
	actionPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	actionPad.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	actionPad.Parent = actionBar

	local fileLabel = Instance.new("TextLabel")
	fileLabel.Name = "FileLabel"
	fileLabel.Size = UDim2.new(1, -200, 1, 0)
	fileLabel.BackgroundTransparency = 1
	fileLabel.Text = "Select a conflicting file"
	fileLabel.TextColor3 = Theme.Color.TextMuted
	fileLabel.Font = Theme.Font.Mono
	fileLabel.TextSize = Theme.Size.TextSmall
	fileLabel.TextXAlignment = Enum.TextXAlignment.Left
	fileLabel.TextTruncate = Enum.TextTruncate.AtEnd
	fileLabel.Parent = actionBar

	-- Accept buttons
	local btnLayout = Instance.new("UIListLayout")
	-- (we'll position buttons manually)

	local acceptTheirsBtn = Instance.new("TextButton")
	acceptTheirsBtn.Size = UDim2.fromOffset(85, 22)
	acceptTheirsBtn.Position = UDim2.new(1, -180, 0, 5)
	acceptTheirsBtn.BackgroundColor3 = Theme.Color.Accent
	acceptTheirsBtn.BorderSizePixel = 0
	acceptTheirsBtn.Text = "Accept Theirs"
	acceptTheirsBtn.TextColor3 = Theme.Color.Background
	acceptTheirsBtn.Font = Theme.Font.Bold
	acceptTheirsBtn.TextSize = 10
	acceptTheirsBtn.AutoButtonColor = false
	acceptTheirsBtn.Parent = actionBar
	Instance.new("UICorner", acceptTheirsBtn).CornerRadius = UDim.new(0, 3)

	local acceptMineBtn = Instance.new("TextButton")
	acceptMineBtn.Size = UDim2.fromOffset(80, 22)
	acceptMineBtn.Position = UDim2.new(1, -90, 0, 5)
	acceptMineBtn.BackgroundColor3 = Theme.Color.Green
	acceptMineBtn.BorderSizePixel = 0
	acceptMineBtn.Text = "Accept Mine"
	acceptMineBtn.TextColor3 = Theme.Color.Background
	acceptMineBtn.Font = Theme.Font.Bold
	acceptMineBtn.TextSize = 10
	acceptMineBtn.AutoButtonColor = false
	acceptMineBtn.Parent = actionBar
	Instance.new("UICorner", acceptMineBtn).CornerRadius = UDim.new(0, 3)

	-- Side-by-side diff scroll
	local diffArea = Instance.new("Frame")
	diffArea.Size = UDim2.new(1, 0, 1, -64)
	diffArea.Position = UDim2.fromOffset(0, 32)
	diffArea.BackgroundTransparency = 1
	diffArea.ClipsDescendants = true
	diffArea.Parent = contentArea

	-- Left pane: theirs (remote)
	local leftPane = Instance.new("Frame")
	leftPane.Size = UDim2.new(0.5, -1, 1, 0)
	leftPane.BackgroundColor3 = Theme.Color.InputBg
	leftPane.BorderSizePixel = 0
	leftPane.Parent = diffArea

	local leftHeader = Instance.new("Frame")
	leftHeader.Size = UDim2.new(1, 0, 0, 20)
	leftHeader.BackgroundColor3 = Theme.Color.DiffRemove
	leftHeader.BorderSizePixel = 0
	leftHeader.Parent = leftPane

	local leftTitle = Instance.new("TextLabel")
	leftTitle.Size = UDim2.new(1, -8, 1, 0)
	leftTitle.Position = UDim2.fromOffset(8, 0)
	leftTitle.BackgroundTransparency = 1
	leftTitle.Text = "THEIRS (Remote)"
	leftTitle.TextColor3 = Theme.Color.DiffRemoveText
	leftTitle.Font = Theme.Font.Bold
	leftTitle.TextSize = 10
	leftTitle.TextXAlignment = Enum.TextXAlignment.Left
	leftTitle.Parent = leftHeader

	local leftScroll = Instance.new("ScrollingFrame")
	leftScroll.Size = UDim2.new(1, 0, 1, -20)
	leftScroll.Position = UDim2.fromOffset(0, 20)
	leftScroll.BackgroundTransparency = 1
	leftScroll.BorderSizePixel = 0
	leftScroll.ScrollBarThickness = 4
	leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leftScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	leftScroll.Parent = leftPane

	local leftBox = Instance.new("TextBox")
	leftBox.Name = "Code"
	leftBox.Text = ""
	leftBox.Size = UDim2.new(1, 0, 0, 0)
	leftBox.AutomaticSize = Enum.AutomaticSize.Y
	leftBox.BackgroundTransparency = 1
	leftBox.TextColor3 = Theme.Color.TextMuted
	leftBox.Font = Theme.Font.Mono
	leftBox.TextSize = 11
	leftBox.TextXAlignment = Enum.TextXAlignment.Left
	leftBox.TextYAlignment = Enum.TextYAlignment.Top
	leftBox.TextWrapped = true
	leftBox.TextEditable = false
	leftBox.ClearTextOnFocus = false
	leftBox.MultiLine = true
	leftBox.BorderSizePixel = 0
	leftBox.Parent = leftScroll

	local leftPad = Instance.new("UIPadding")
	leftPad.PaddingLeft = UDim.new(0, 6)
	leftPad.PaddingTop = UDim.new(0, 4)
	leftPad.Parent = leftScroll

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0, 2, 1, 0)
	divider.Position = UDim2.new(0.5, -1, 0, 0)
	divider.BackgroundColor3 = Theme.Color.Border
	divider.BorderSizePixel = 0
	divider.Parent = diffArea

	-- Right pane: mine (local)
	local rightPane = Instance.new("Frame")
	rightPane.Size = UDim2.new(0.5, -1, 1, 0)
	rightPane.Position = UDim2.new(0.5, 1, 0, 0)
	rightPane.BackgroundColor3 = Theme.Color.InputBg
	rightPane.BorderSizePixel = 0
	rightPane.Parent = diffArea

	local rightHeader = Instance.new("Frame")
	rightHeader.Size = UDim2.new(1, 0, 0, 20)
	rightHeader.BackgroundColor3 = Theme.Color.DiffAdd
	rightHeader.BorderSizePixel = 0
	rightHeader.Parent = rightPane

	local rightTitle = Instance.new("TextLabel")
	rightTitle.Size = UDim2.new(1, -8, 1, 0)
	rightTitle.Position = UDim2.fromOffset(8, 0)
	rightTitle.BackgroundTransparency = 1
	rightTitle.Text = "MINE (Local)"
	rightTitle.TextColor3 = Theme.Color.DiffAddText
	rightTitle.Font = Theme.Font.Bold
	rightTitle.TextSize = 10
	rightTitle.TextXAlignment = Enum.TextXAlignment.Left
	rightTitle.Parent = rightHeader

	local rightScroll = Instance.new("ScrollingFrame")
	rightScroll.Size = UDim2.new(1, 0, 1, -20)
	rightScroll.Position = UDim2.fromOffset(0, 20)
	rightScroll.BackgroundTransparency = 1
	rightScroll.BorderSizePixel = 0
	rightScroll.ScrollBarThickness = 4
	rightScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightScroll.Parent = rightPane

	local rightBox = Instance.new("TextBox")
	rightBox.Name = "Code"
	rightBox.Text = ""
	rightBox.Size = UDim2.new(1, 0, 0, 0)
	rightBox.AutomaticSize = Enum.AutomaticSize.Y
	rightBox.BackgroundTransparency = 1
	rightBox.TextColor3 = Theme.Color.TextMuted
	rightBox.Font = Theme.Font.Mono
	rightBox.TextSize = 11
	rightBox.TextXAlignment = Enum.TextXAlignment.Left
	rightBox.TextYAlignment = Enum.TextYAlignment.Top
	rightBox.TextWrapped = true
	rightBox.TextEditable = false
	rightBox.ClearTextOnFocus = false
	rightBox.MultiLine = true
	rightBox.BorderSizePixel = 0
	rightBox.Parent = rightScroll

	local rightPad = Instance.new("UIPadding")
	rightPad.PaddingLeft = UDim.new(0, 6)
	rightPad.PaddingTop = UDim.new(0, 4)
	rightPad.Parent = rightScroll

	-- Bottom bar: apply all + status
	local bottomBar = Instance.new("Frame")
	bottomBar.Size = UDim2.new(1, 0, 0, 32)
	bottomBar.Position = UDim2.new(0, 0, 1, -32)
	bottomBar.BackgroundColor3 = Theme.Color.Surface
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = contentArea

	local bottomPad = Instance.new("UIPadding")
	bottomPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	bottomPad.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	bottomPad.Parent = bottomBar

	local resolveStatus = Instance.new("TextLabel")
	resolveStatus.Size = UDim2.new(1, -120, 1, 0)
	resolveStatus.BackgroundTransparency = 1
	resolveStatus.Text = `0 / {#conflicts} resolved`
	resolveStatus.TextColor3 = Theme.Color.Yellow
	resolveStatus.Font = Theme.Font.Regular
	resolveStatus.TextSize = Theme.Size.TextSmall
	resolveStatus.TextXAlignment = Enum.TextXAlignment.Left
	resolveStatus.Parent = bottomBar

	local applyAllBtn = Instance.new("TextButton")
	applyAllBtn.Size = UDim2.fromOffset(110, 22)
	applyAllBtn.Position = UDim2.new(1, -112, 0, 5)
	applyAllBtn.BackgroundColor3 = Theme.Color.Green
	applyAllBtn.BackgroundTransparency = 0.5
	applyAllBtn.BorderSizePixel = 0
	applyAllBtn.Text = "Apply All"
	applyAllBtn.TextColor3 = Theme.Color.Background
	applyAllBtn.Font = Theme.Font.Bold
	applyAllBtn.TextSize = 11
	applyAllBtn.AutoButtonColor = false
	applyAllBtn.Parent = bottomBar
	Instance.new("UICorner", applyAllBtn).CornerRadius = UDim.new(0, 3)

	-- State
	local selectedConflict: number = 0
	local sidebarButtons: { TextButton } = {}

	local function updateResolveStatus()
		resolvedCount = 0
		for _ in resolutions do resolvedCount += 1 end
		resolveStatus.Text = `{resolvedCount} / {#conflicts} resolved`
		resolveStatus.TextColor3 = if resolvedCount == #conflicts then Theme.Color.Green else Theme.Color.Yellow
		applyAllBtn.BackgroundTransparency = if resolvedCount == #conflicts then 0 else 0.5

		-- Update sidebar badges
		for i, btn in sidebarButtons do
			local conf = conflicts[i]
			local res = resolutions[conf.path]
			local badge = btn:FindFirstChild("Badge") :: TextLabel
			if badge then
				if res == "theirs" then
					badge.Text = "T"
					badge.TextColor3 = Theme.Color.Accent
				elseif res == "mine" then
					badge.Text = "M"
					badge.TextColor3 = Theme.Color.Green
				else
					badge.Text = "!"
					badge.TextColor3 = Theme.Color.Red
				end
			end
		end

		self.refs.diffStatus.Text = `{resolvedCount}/{#conflicts} resolved`
	end

	local function selectConflict(index: number)
		selectedConflict = index
		local conf = conflicts[index]
		fileLabel.Text = conf.path
		fileLabel.TextColor3 = Theme.fileColor(conf.path)
		leftBox.Text = conf.remoteContent
		rightBox.Text = conf.localContent

		-- Highlight selected in sidebar
		for i, btn in sidebarButtons do
			btn.BackgroundTransparency = if i == index then 0 else 1
			btn.BackgroundColor3 = Theme.Color.SurfaceHover
		end
	end

	-- Build sidebar file list
	for i, conf in conflicts do
		local parts = conf.path:split("/")
		local fileName = parts[#parts] or conf.path

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 26)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.LayoutOrder = i
		btn.Parent = sbScroll

		local badge = Instance.new("TextLabel")
		badge.Name = "Badge"
		badge.Size = UDim2.fromOffset(14, 26)
		badge.Position = UDim2.fromOffset(4, 0)
		badge.BackgroundTransparency = 1
		badge.Text = "!"
		badge.TextColor3 = Theme.Color.Red
		badge.Font = Theme.Font.Bold
		badge.TextSize = 10
		badge.Parent = btn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -22, 1, 0)
		nameLabel.Position = UDim2.fromOffset(20, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = fileName
		nameLabel.TextColor3 = Theme.fileColor(conf.path)
		nameLabel.Font = Theme.Font.Mono
		nameLabel.TextSize = 10
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = btn

		btn.MouseEnter:Connect(function()
			if selectedConflict ~= i then btn.BackgroundTransparency = 0.6; btn.BackgroundColor3 = Theme.Color.SurfaceHover end
		end)
		btn.MouseLeave:Connect(function()
			if selectedConflict ~= i then btn.BackgroundTransparency = 1 end
		end)

		local idx = i
		btn.MouseButton1Click:Connect(function() selectConflict(idx) end)
		table.insert(sidebarButtons, btn)
	end

	-- Button handlers
	acceptTheirsBtn.MouseButton1Click:Connect(function()
		if selectedConflict == 0 then return end
		local conf = conflicts[selectedConflict]
		resolutions[conf.path] = "theirs"
		updateResolveStatus()
		self:_log(`Conflict: accepting theirs for {conf.path}`)
		-- Auto-advance to next unresolved
		for i, c in conflicts do
			if not resolutions[c.path] then selectConflict(i); return end
		end
	end)

	acceptMineBtn.MouseButton1Click:Connect(function()
		if selectedConflict == 0 then return end
		local conf = conflicts[selectedConflict]
		resolutions[conf.path] = "mine"
		updateResolveStatus()
		self:_log(`Conflict: accepting mine for {conf.path}`)
		for i, c in conflicts do
			if not resolutions[c.path] then selectConflict(i); return end
		end
	end)

	applyAllBtn.MouseButton1Click:Connect(function()
		-- Check all resolved
		for _, conf in conflicts do
			if not resolutions[conf.path] then
				self:_log("Resolve all conflicts before applying", Theme.Color.Yellow)
				return
			end
		end

		-- Build final file map with resolutions applied
		local resolvedFiles: { [string]: string } = {}
		for _, conf in conflicts do
			if resolutions[conf.path] == "theirs" then
				resolvedFiles[conf.path] = conf.remoteContent
			else
				resolvedFiles[conf.path] = conf.localContent
			end
		end

		-- Apply resolved files to Studio
		local created, updated, _ = self.serializer:applyFromFiles(resolvedFiles)
		self:_log(`Resolved: {created} created, {updated} updated`, Theme.Color.Green)
		ChangeHistoryService:SetWaypoint("RoGit: Resolve Conflicts")

		-- Close conflict panel
		self.diffWidget.Enabled = false
		self:_cleanDiffOverlays()
		self:_refreshStaging()
		self:_refreshLog()
	end)

	-- Select first conflict
	if #conflicts > 0 then
		selectConflict(1)
	end
	updateResolveStatus()

	-- Cleanup on widget close without resolving
	local conn
	conn = self.diffWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not self.diffWidget.Enabled then
			self:_cleanDiffOverlays()
			conn:Disconnect()
			if resolvedCount < #conflicts then
				self:_log("Conflict resolution cancelled. Remote changes not applied for conflicting files.", Theme.Color.Yellow)
			end
		end
	end)
end

--==============================--
--       REVERT COMMIT          --
--==============================--

function App._revertCommit(self: App, shortSha: string, fullSha: string)
	if not self.client or self.busy then return end
	self.busy = true
	self:_log(`Reverting commit {shortSha}...`, Theme.Color.Yellow)

	task.spawn(function()
		local ok, err = pcall(function()
			local r = (self.client :: GitHubClientModule.GitHubClient):revertCommit(fullSha)
			if r.ok then
				local newSha = (r.data :: string):sub(1, 7)
				self:_log(`Reverted {shortSha} -> {newSha}`, Theme.Color.Green)
				ChangeHistoryService:SetWaypoint(`RoGit: Revert {shortSha}`)
				self.remoteReady = false
				task.delay(1.5, function()
					if not self.destroyed then self:_fetchRemoteState() end
				end)
			else
				self:_log(`Revert failed: {r.error}`, Theme.Color.Red)
			end
		end)
		if not ok then self:_log(`Revert error: {err}`, Theme.Color.Red) end
		self.busy = false
	end)
end

--==============================--
--       MERGE BRANCH           --
--==============================--

function App._mergeBranch(self: App)
	if not self.client or self.busy then return end

	local mergeDropdown = self.refs.mergeDropdown :: Components.DropdownHandle
	local source = mergeDropdown.getSelected()
	local mergeStatus = self.refs.mergeStatus :: TextLabel

	if not source or source == "" then
		mergeStatus.Text = "Select a branch to merge"
		mergeStatus.TextColor3 = Theme.Color.Red
		return
	end

	self.busy = true
	mergeStatus.Text = `Merging {source} into {self.currentBranch}...`
	mergeStatus.TextColor3 = Theme.Color.Yellow
	self:_log(`Merging {source} into {self.currentBranch}...`)

	task.spawn(function()
		local ok, mergeErr = pcall(function()
			local r = (self.client :: GitHubClientModule.GitHubClient):merge(
				self.currentBranch, source, `Merge {source} into {self.currentBranch}`
			)
			if r.ok then
				local sha = (r.data :: string):sub(1, 7)
				self:_log(`Merge complete: {sha}`, Theme.Color.Green)
				mergeStatus.Text = `Merged! ({sha})`
				mergeStatus.TextColor3 = Theme.Color.Green
				self.remoteReady = false
				ChangeHistoryService:SetWaypoint(`RoGit: Merge {source}`)
				task.delay(1.5, function()
					if not self.destroyed then
						self:_fetchRemoteState()
						mergeStatus.Text = ""
					end
				end)
			else
				local err = r.error or "Unknown"
				if err:find("409") or err:lower():find("conflict") then
					self:_log(`Merge conflict: {source} cannot be cleanly merged into {self.currentBranch}`, Theme.Color.Red)
					mergeStatus.Text = "Merge conflict! Resolve on GitHub."
				else
					self:_log(`Merge failed: {err}`, Theme.Color.Red)
					mergeStatus.Text = `Failed: {err}`
				end
				mergeStatus.TextColor3 = Theme.Color.Red
			end
		end)
		if not ok then self:_log(`Merge error: {mergeErr}`, Theme.Color.Red) end
		self.busy = false
	end)
end

--==============================--
--       FILE HISTORY           --
--==============================--

function App._showFileHistory(self: App, filePath: string)
	if not self.client then return end

	self:_log(`Fetching history for: {filePath}`)
	self:_openDiffWidget(`History: {filePath}`)

	local diffViewer = self.refs.diffViewer :: Components.DiffViewerHandle
	diffViewer.frame.Visible = false
	diffViewer.clear()
	self.refs.diffStatus.Text = "Loading..."

	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):getFileCommits(filePath, self.currentBranch, 20)
		if not r.ok then
			self.refs.diffStatus.Text = `Failed: {r.error}`
			self:_log(`File history failed: {r.error}`, Theme.Color.Red)
			return
		end

		local commits = r.data :: { CommitInfo }
		if #commits == 0 then
			self.refs.diffStatus.Text = "No commits"
			self:_log(`No history found for {filePath}`, Theme.Color.Yellow)
		else
			self.refs.diffStatus.Text = `{#commits} commits`
			self:_log(`Found {#commits} commits for {filePath}`, Theme.Color.Green)
		end

		-- Build commit list in the diff viewer's content area
		local root = self.refs.diffRoot :: Frame

		local histScroll = Instance.new("ScrollingFrame")
		histScroll.Name = "HistoryScroll"
		histScroll.Size = UDim2.new(1, 0, 1, -32)
		histScroll.Position = UDim2.fromOffset(0, 32)
		histScroll.BackgroundTransparency = 1
		histScroll.BorderSizePixel = 0
		histScroll.ScrollBarThickness = 4
		histScroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
		histScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		histScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		histScroll.Parent = root

		local hl = Instance.new("UIListLayout")
		hl.SortOrder = Enum.SortOrder.LayoutOrder
		hl.Parent = histScroll

		-- Header
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 28)
		header.BackgroundColor3 = Theme.Color.Surface
		header.BorderSizePixel = 0
		header.LayoutOrder = 0
		header.Parent = histScroll

		local headerLabel = Instance.new("TextLabel")
		headerLabel.Size = UDim2.new(1, -16, 1, 0)
		headerLabel.Position = UDim2.fromOffset(8, 0)
		headerLabel.BackgroundTransparency = 1
		headerLabel.Text = `Commit history for {filePath}`
		headerLabel.TextColor3 = Theme.Color.Accent
		headerLabel.Font = Theme.Font.Mono
		headerLabel.TextSize = Theme.Size.TextSmall
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.TextTruncate = Enum.TextTruncate.AtEnd
		headerLabel.Parent = header

		for i, commit in commits do
			Components.createCommitRow(histScroll, {
				shortSha = commit.shortSha, message = commit.message,
				author = commit.author, date = commit.date, layoutOrder = i,
			})
		end

		if #commits == 0 then
			Components.createLabel(histScroll, "No commits found for this file", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 1 })
		end

		-- When diff widget closes, clean up
		local conn
		conn = self.diffWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not self.diffWidget.Enabled then
				self:_cleanDiffOverlays()
				conn:Disconnect()
			end
		end)
	end)
end

--==============================--
--           DIFF               --
--==============================--

function App._showDiff(self: App)
	if not self.client or self.busy then return end
	if not self.remoteReady then
		self:_log("Fetching remote first...", Theme.Color.Yellow)
		self:_fetchRemoteState()
		return
	end

	self.busy = true
	self:_log("Opening diff view...")
	self:_openDiffWidget(`RoGit Diff - {self.currentBranch}`)

	local diffViewer = self.refs.diffViewer :: Components.DiffViewerHandle
	self.refs.diffStatus.Text = "Computing..."

	task.spawn(function()
		local ok, err = pcall(function()
			local localFiles = self.serializer:getFileContentsMap()
			local fileDiffs = DiffEngine.computeFileDiffs(localFiles, self.remoteFiles)

			if #fileDiffs == 0 then
				self.refs.diffStatus.Text = "No changes"
				diffViewer.clear()
				self:_log("Diff: no changes detected")
			else
				local totalAdds, totalDels = 0, 0
				for _, fd in fileDiffs do totalAdds += fd.diff.additions; totalDels += fd.diff.deletions end
				self.refs.diffStatus.Text = `{#fileDiffs} files | +{totalAdds} -{totalDels}`
				diffViewer.showFileDiffs(fileDiffs)
				self:_log(`Diff: {#fileDiffs} files, +{totalAdds} -{totalDels}`, Theme.Color.Green)
			end
		end)
		if not ok then self:_log(`Diff error: {err}`, Theme.Color.Red) end
		self.busy = false
	end)
end

--==============================--
--         GIT CLONE            --
--==============================--

-- Parse "owner/repo", "https://github.com/owner/repo.git", "https://github.com/owner/repo"
function App._parseCloneInput(_self: App, input: string): (string?, string?)
	local trimmed = input:gsub("%s", "")

	-- https://github.com/owner/repo.git or https://github.com/owner/repo
	local httpsOwner, httpsRepo = trimmed:match("^https?://github%.com/([^/]+)/([^/%.]+)")
	if httpsOwner and httpsRepo then
		return httpsOwner, httpsRepo
	end

	-- owner/repo format
	local parts = trimmed:split("/")
	if #parts == 2 and parts[1] ~= "" and parts[2] ~= "" then
		-- Strip .git suffix if present
		local repo = parts[2]:gsub("%.git$", "")
		return parts[1], repo
	end

	return nil, nil
end

function App._performClone(self: App)
	if self.busy then return end

	local raw = (self.refs.cloneRepoInput :: TextBox).Text
	local branch = (self.refs.cloneBranchInput :: TextBox).Text:gsub("%s", "")
	local token = (self.refs.cloneTokenInput :: TextBox).Text:gsub("%s", "")

	if raw == "" or token == "" then
		self.refs.cloneStatus.Text = "Repository and token required"
		self.refs.cloneStatus.TextColor3 = Theme.Color.Red
		return
	end

	local owner, repo = self:_parseCloneInput(raw)
	if not owner or not repo then
		self.refs.cloneStatus.Text = "Invalid format. Use owner/repo or https://github.com/owner/repo.git"
		self.refs.cloneStatus.TextColor3 = Theme.Color.Red
		return
	end

	if branch == "" then branch = "main" end

	self.refs.cloneStatus.Text = "Cloning..."
	self.refs.cloneStatus.TextColor3 = Theme.Color.Yellow
	self.busy = true

	task.spawn(function()
		local cloneOk, cloneErr = pcall(function()
			local config: GitHubConfig = { owner = owner, repo = repo, token = token, branch = branch }
			local client = GitHubClientModule.new(config)

			local testR = client:testConnection()
			if not testR.ok then
				self.refs.cloneStatus.Text = `Failed: {testR.error}`
				self.refs.cloneStatus.TextColor3 = Theme.Color.Red
				return
			end

			self:_log(`Cloning {owner}/{repo} ({branch})...`, Theme.Color.Accent)

			local treeR = client:pullTree()
			if not treeR.ok then
				self.refs.cloneStatus.Text = `Tree: {treeR.error}`
				self.refs.cloneStatus.TextColor3 = Theme.Color.Red
				return
			end

			local entries = treeR.data :: { TreeEntry }
			self.refs.cloneStatus.Text = `Downloading {#entries} files...`
			self:_log(`Downloading {#entries} files...`)

			local contents = client:pullFileContents(entries, function(done, total)
				self.refs.cloneStatus.Text = `Downloading {done}/{total}...`
			end)

			self.refs.cloneStatus.Text = "Applying to Studio..."

			self.applyingRemote = true
			local recordId = ChangeHistoryService:TryBeginRecording(`RoGit: Clone {owner}/{repo}`)
			local created, updated, _ = self.serializer:applyFromFiles(contents)
			if recordId then ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Commit) end
			self.applyingRemote = false

			self:_log(`Clone complete: {created} created, {updated} updated`, Theme.Color.Green)
			self.refs.cloneStatus.Text = `Done! {created} created, {updated} updated`
			self.refs.cloneStatus.TextColor3 = Theme.Color.Green

			-- Auto-connect after clone
			self.client = client
			self.connected = true
			self.currentBranch = branch
			self.remoteFiles = contents
			self.remoteTreeEntries = entries
			self.remoteReady = true

			-- Fill in the connection fields
			(self.refs.ownerInput :: TextBox).Text = owner;
			(self.refs.repoInput :: TextBox).Text = repo;
			(self.refs.branchInput :: TextBox).Text = branch;
			(self.refs.tokenInput :: TextBox).Text = token

			self:_saveSettings()
			self:_refreshBranches()

			task.delay(1.5, function()
				if not self.destroyed then
					self:_showView("main")
					self:_refreshStaging()
					self:_refreshLog()
				end
			end)
		end)

		if not cloneOk then
			self:_log(`Clone error: {cloneErr}`, Theme.Color.Red)
			self.refs.cloneStatus.Text = `Error: {cloneErr}`
			self.refs.cloneStatus.TextColor3 = Theme.Color.Red
			self.applyingRemote = false
		end
		self.busy = false
	end)
end

--==============================--
--       PULL REQUESTS          --
--==============================--

function App._createPR(self: App)
	if not self.client or self.busy then return end
	local title = (self.refs.prTitleInput :: TextBox).Text:gsub("^%s+", ""):gsub("%s+$", "")
	local body = (self.refs.prBodyInput :: TextBox).Text
	local prStatus = self.refs.prStatus :: TextLabel

	if title == "" then
		prStatus.Text = "Title is required"
		prStatus.TextColor3 = Theme.Color.Red
		return
	end

	local baseDropdown = self.refs.prBaseDropdown :: Components.DropdownHandle
	local base = baseDropdown.getSelected() or "main"

	self.busy = true
	prStatus.Text = "Creating PR..."
	prStatus.TextColor3 = Theme.Color.Yellow

	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):createPullRequest(title, body, self.currentBranch, base)
		if r.ok then
			local pr = r.data :: GitHubClientModule.PullRequest
			self:_log(`PR #{pr.number} created: {title}`, Theme.Color.Green)
			prStatus.Text = `Created PR #{pr.number}`
			prStatus.TextColor3 = Theme.Color.Green;
			(self.refs.prTitleInput :: TextBox).Text = "";
			(self.refs.prBodyInput :: TextBox).Text = ""
			self:_refreshPRs()
		else
			self:_log(`PR creation failed: {r.error}`, Theme.Color.Red)
			prStatus.Text = `Failed: {r.error}`
			prStatus.TextColor3 = Theme.Color.Red
		end
		self.busy = false
	end)
end

function App._refreshPRs(self: App)
	if not self.client then return end
	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):getPullRequests("open")
		if not r.ok then return end
		local prs = r.data :: { GitHubClientModule.PullRequest }
		local section = self.refs.prSection :: Components.SectionHandle
		section.updateCount(#prs)
		local listFrame = self.refs.prListFrame :: Frame
		self:_clearContainer(listFrame)

		-- Also update the PR base dropdown with branches
		local baseDropdown = self.refs.prBaseDropdown :: Components.DropdownHandle
		local otherBranches: { string } = {}
		for _, name in self.branches do
			if name ~= self.currentBranch then table.insert(otherBranches, name) end
		end
		baseDropdown.setItems(otherBranches)

		for i, pr in prs do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 32)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.Parent = listFrame

			local prPad = Instance.new("UIPadding")
			prPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
			prPad.Parent = row

			local numberLabel = Instance.new("TextLabel")
			numberLabel.Size = UDim2.fromOffset(36, 16)
			numberLabel.Position = UDim2.fromOffset(0, 2)
			numberLabel.BackgroundTransparency = 1
			numberLabel.Text = `#{pr.number}`
			numberLabel.TextColor3 = Theme.Color.Green
			numberLabel.Font = Theme.Font.Mono
			numberLabel.TextSize = 10
			numberLabel.TextXAlignment = Enum.TextXAlignment.Left
			numberLabel.Parent = row

			local titleLabel = Instance.new("TextLabel")
			titleLabel.Size = UDim2.new(1, -40, 0, 16)
			titleLabel.Position = UDim2.fromOffset(38, 2)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Text = pr.title
			titleLabel.TextColor3 = Theme.Color.Text
			titleLabel.Font = Theme.Font.Regular
			titleLabel.TextSize = Theme.Size.TextSmall
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
			titleLabel.Parent = row

			local metaLabel = Instance.new("TextLabel")
			metaLabel.Size = UDim2.new(1, -40, 0, 12)
			metaLabel.Position = UDim2.fromOffset(38, 18)
			metaLabel.BackgroundTransparency = 1
			metaLabel.Text = `{pr.head} -> {pr.base} by {pr.author}`
			metaLabel.TextColor3 = Theme.Color.TextDim
			metaLabel.Font = Theme.Font.Regular
			metaLabel.TextSize = 9
			metaLabel.TextXAlignment = Enum.TextXAlignment.Left
			metaLabel.Parent = row
		end

		if #prs == 0 then
			Components.createLabel(listFrame, "No open pull requests", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 0 })
		end
	end)
end

--==============================--
--      ACTIONS STATUS          --
--==============================--

function App._refreshActions(self: App)
	if not self.client then return end
	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):getWorkflowRuns(self.currentBranch, 5)
		if not r.ok then self:_log(`Actions: {r.error}`, Theme.Color.Red); return end
		local runs = r.data :: { GitHubClientModule.WorkflowRun }
		local section = self.refs.actionsSection :: Components.SectionHandle
		section.updateCount(#runs)
		local listFrame = self.refs.actionsListFrame :: Frame
		self:_clearContainer(listFrame)

		local STATUS_ICONS: { [string]: { text: string, color: Color3 } } = {
			success = { text = "OK", color = Theme.Color.Green },
			failure = { text = "X", color = Theme.Color.Red },
			cancelled = { text = "--", color = Theme.Color.TextDim },
			in_progress = { text = "..", color = Theme.Color.Yellow },
			queued = { text = "?", color = Theme.Color.TextMuted },
		}

		for i, run in runs do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.Parent = listFrame

			local rPad = Instance.new("UIPadding")
			rPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
			rPad.Parent = row

			local statusInfo = STATUS_ICONS[run.conclusion or run.status] or { text = "?", color = Theme.Color.TextMuted }

			local statusLabel = Instance.new("TextLabel")
			statusLabel.Size = UDim2.fromOffset(22, 28)
			statusLabel.BackgroundTransparency = 1
			statusLabel.Text = statusInfo.text
			statusLabel.TextColor3 = statusInfo.color
			statusLabel.Font = Theme.Font.Bold
			statusLabel.TextSize = 10
			statusLabel.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -26, 0, 14)
			nameLabel.Position = UDim2.fromOffset(24, 1)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = run.name
			nameLabel.TextColor3 = Theme.Color.Text
			nameLabel.Font = Theme.Font.Regular
			nameLabel.TextSize = Theme.Size.TextSmall
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = row

			local dateStr = run.createdAt
			if dateStr:find("T") then dateStr = dateStr:split("T")[1] end
			local metaLabel = Instance.new("TextLabel")
			metaLabel.Size = UDim2.new(1, -26, 0, 12)
			metaLabel.Position = UDim2.fromOffset(24, 15)
			metaLabel.BackgroundTransparency = 1
			metaLabel.Text = `{run.event} - {dateStr}`
			metaLabel.TextColor3 = Theme.Color.TextDim
			metaLabel.Font = Theme.Font.Regular
			metaLabel.TextSize = 9
			metaLabel.TextXAlignment = Enum.TextXAlignment.Left
			metaLabel.Parent = row
		end

		if #runs == 0 then
			Components.createLabel(listFrame, "No workflow runs found", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 0 })
		end
	end)
end

--==============================--
--      TAGS / RELEASES         --
--==============================--

function App._createRelease(self: App)
	if not self.client or self.busy then return end
	local tag = (self.refs.releaseTagInput :: TextBox).Text:gsub("%s", "")
	local name = (self.refs.releaseNameInput :: TextBox).Text:gsub("^%s+", ""):gsub("%s+$", "")
	local body = (self.refs.releaseBodyInput :: TextBox).Text
	local releaseStatus = self.refs.releaseStatus :: TextLabel

	if tag == "" then
		releaseStatus.Text = "Tag is required (e.g. v1.0.0)"
		releaseStatus.TextColor3 = Theme.Color.Red
		return
	end

	if name == "" then name = tag end
	self.busy = true
	releaseStatus.Text = "Creating release..."
	releaseStatus.TextColor3 = Theme.Color.Yellow

	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):createRelease(tag, name, body, self.currentBranch)
		if r.ok then
			local rel = r.data :: GitHubClientModule.Release
			self:_log(`Release {rel.tag} created`, Theme.Color.Green)
			releaseStatus.Text = `Created: {rel.tag}`
			releaseStatus.TextColor3 = Theme.Color.Green;
			(self.refs.releaseTagInput :: TextBox).Text = "";
			(self.refs.releaseNameInput :: TextBox).Text = "";
			(self.refs.releaseBodyInput :: TextBox).Text = ""
			self:_refreshReleases()
		else
			self:_log(`Release failed: {r.error}`, Theme.Color.Red)
			releaseStatus.Text = `Failed: {r.error}`
			releaseStatus.TextColor3 = Theme.Color.Red
		end
		self.busy = false
	end)
end

function App._refreshReleases(self: App)
	if not self.client then return end
	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):getReleases(10)
		if not r.ok then return end
		local releases = r.data :: { GitHubClientModule.Release }
		local section = self.refs.releasesSection :: Components.SectionHandle
		section.updateCount(#releases)
		local listFrame = self.refs.releasesListFrame :: Frame
		self:_clearContainer(listFrame)

		for i, rel in releases do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.Parent = listFrame

			local rPad = Instance.new("UIPadding")
			rPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
			rPad.Parent = row

			local tagLabel = Instance.new("TextLabel")
			tagLabel.Size = UDim2.fromOffset(60, 28)
			tagLabel.BackgroundTransparency = 1
			tagLabel.Text = rel.tag
			tagLabel.TextColor3 = Theme.Color.Accent
			tagLabel.Font = Theme.Font.Mono
			tagLabel.TextSize = Theme.Size.TextSmall
			tagLabel.TextXAlignment = Enum.TextXAlignment.Left
			tagLabel.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -100, 0, 14)
			nameLabel.Position = UDim2.fromOffset(62, 1)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = rel.name
			nameLabel.TextColor3 = Theme.Color.Text
			nameLabel.Font = Theme.Font.Regular
			nameLabel.TextSize = Theme.Size.TextSmall
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = row

			local dateStr = rel.createdAt
			if dateStr:find("T") then dateStr = dateStr:split("T")[1] end
			local metaLabel = Instance.new("TextLabel")
			metaLabel.Size = UDim2.new(1, -62, 0, 12)
			metaLabel.Position = UDim2.fromOffset(62, 15)
			metaLabel.BackgroundTransparency = 1
			metaLabel.Text = `by {rel.author} - {dateStr}{if rel.prerelease then " (pre-release)" else ""}`
			metaLabel.TextColor3 = Theme.Color.TextDim
			metaLabel.Font = Theme.Font.Regular
			metaLabel.TextSize = 9
			metaLabel.TextXAlignment = Enum.TextXAlignment.Left
			metaLabel.Parent = row
		end

		if #releases == 0 then
			Components.createLabel(listFrame, "No releases yet", { color = Theme.Color.TextDim, textSize = Theme.Size.TextSmall, layoutOrder = 0 })
		end
	end)
end

--==============================--
--      TEAM ACTIVITY           --
--==============================--

function App._refreshActivity(self: App)
	if not self.client then return end
	task.spawn(function()
		local r = (self.client :: GitHubClientModule.GitHubClient):getCommits(self.currentBranch, 10)
		if not r.ok then return end
		local commits = r.data :: { CommitInfo }
		local section = self.refs.activitySection :: Components.SectionHandle
		section.updateCount(#commits)
		local listFrame = self.refs.activityListFrame :: Frame
		self:_clearContainer(listFrame)

		-- Show as "Author did X at time" feed
		for i, commit in commits do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 24)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.Parent = listFrame

			local rPad = Instance.new("UIPadding")
			rPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
			rPad.Parent = row

			local dateStr = commit.date
			if dateStr:find("T") then
				local timePart = dateStr:split("T")[2] or ""
				dateStr = timePart:split("Z")[1] or timePart
				if #dateStr > 5 then dateStr = dateStr:sub(1, 5) end
			end

			local firstLine = commit.message:split("\n")[1] or commit.message
			-- Escape RichText-unsafe characters
			local safeAuthor = commit.author:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
			local safeMessage = firstLine:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
			local actLabel = Instance.new("TextLabel")
			actLabel.Size = UDim2.new(1, 0, 1, 0)
			actLabel.BackgroundTransparency = 1
			actLabel.RichText = true
			actLabel.Text = `<font color="#{string.format("%02x%02x%02x", math.floor(Theme.Color.Accent.R*255), math.floor(Theme.Color.Accent.G*255), math.floor(Theme.Color.Accent.B*255))}">{safeAuthor}</font> <font color="#{string.format("%02x%02x%02x", math.floor(Theme.Color.TextDim.R*255), math.floor(Theme.Color.TextDim.G*255), math.floor(Theme.Color.TextDim.B*255))}">{dateStr}</font>  {safeMessage}`
			actLabel.TextColor3 = Theme.Color.TextMuted
			actLabel.Font = Theme.Font.Regular
			actLabel.TextSize = 10
			actLabel.TextXAlignment = Enum.TextXAlignment.Left
			actLabel.TextTruncate = Enum.TextTruncate.AtEnd
			actLabel.Parent = row
		end
	end)
end

--==============================--
--       SEARCH FILES           --
--==============================--

function App._showSearch(self: App)
	self:_openDiffWidget("RoGit - Search")

	local root = self.refs.diffRoot :: Frame
	local diffViewer = self.refs.diffViewer :: Components.DiffViewerHandle
	diffViewer.frame.Visible = false
	self.refs.diffStatus.Text = ""

	local searchPanel = Instance.new("Frame")
	searchPanel.Name = "SearchPanel"
	searchPanel.Size = UDim2.new(1, 0, 1, -32)
	searchPanel.Position = UDim2.fromOffset(0, 32)
	searchPanel.BackgroundColor3 = Theme.Color.InputBg
	searchPanel.BorderSizePixel = 0
	searchPanel.Parent = root

	local spLayout = Instance.new("UIListLayout")
	spLayout.SortOrder = Enum.SortOrder.LayoutOrder
	spLayout.Padding = UDim.new(0, Theme.Size.SpacingS)
	spLayout.Parent = searchPanel

	local spPad = Instance.new("UIPadding")
	spPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	spPad.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	spPad.PaddingTop = UDim.new(0, Theme.Size.SpacingM)
	spPad.Parent = searchPanel

	-- Search input row
	local searchRow = Instance.new("Frame")
	searchRow.Size = UDim2.new(1, 0, 0, 28)
	searchRow.BackgroundTransparency = 1
	searchRow.LayoutOrder = 0
	searchRow.Parent = searchPanel

	local searchInput = Components.createInput(searchRow, { placeholder = "Search in files...", layoutOrder = 0 })
	searchInput.Size = UDim2.new(1, -60, 1, 0)

	local searchGoBtn = Components.createButton(searchRow, {
		text = "Search", size = UDim2.fromOffset(55, 28), layoutOrder = 1,
		color = Theme.Color.Accent, textColor = Theme.Color.Background,
		onClick = function()
			local query = (searchInput :: TextBox).Text:gsub("^%s+", ""):gsub("%s+$", "")
			if query == "" then return end
			self:_performSearch(query, searchPanel)
		end,
	})
	searchGoBtn.Position = UDim2.new(1, -55, 0, 0)

	local resultsLabel = Instance.new("TextLabel")
	resultsLabel.Name = "ResultsLabel"
	resultsLabel.Size = UDim2.new(1, 0, 0, 16)
	resultsLabel.BackgroundTransparency = 1
	resultsLabel.Text = ""
	resultsLabel.TextColor3 = Theme.Color.TextDim
	resultsLabel.Font = Theme.Font.Regular
	resultsLabel.TextSize = 10
	resultsLabel.TextXAlignment = Enum.TextXAlignment.Left
	resultsLabel.LayoutOrder = 1
	resultsLabel.Parent = searchPanel

	local resultsScroll = Instance.new("ScrollingFrame")
	resultsScroll.Name = "ResultsScroll"
	resultsScroll.Size = UDim2.new(1, 0, 1, -52)
	resultsScroll.BackgroundTransparency = 1
	resultsScroll.BorderSizePixel = 0
	resultsScroll.ScrollBarThickness = 4
	resultsScroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
	resultsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	resultsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	resultsScroll.LayoutOrder = 2
	resultsScroll.Parent = searchPanel

	local rsLayout = Instance.new("UIListLayout")
	rsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rsLayout.Parent = resultsScroll

	-- Cleanup on close
	local conn
	conn = self.diffWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not self.diffWidget.Enabled then
			self:_cleanDiffOverlays()
			conn:Disconnect()
		end
	end)
end

function App._performSearch(self: App, query: string, searchPanel: Frame)
	local resultsLabel = searchPanel:FindFirstChild("ResultsLabel") :: TextLabel
	local resultsScroll = searchPanel:FindFirstChild("ResultsScroll") :: ScrollingFrame

	if not resultsLabel or not resultsScroll then return end

	-- Clear previous results
	for _, child in resultsScroll:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	resultsLabel.Text = "Searching..."
	resultsLabel.TextColor3 = Theme.Color.Yellow

	task.spawn(function()
		local localFiles = self.serializer:getFileContentsMap()
		local queryLower = query:lower()
		local matches: { { path: string, lineNum: number, line: string } } = {}
		local fileCount = 0

		for path, content in localFiles do
			local fileHit = false
			local lineNum = 0
			for line in (content .. "\n"):gmatch("([^\n]*)\n") do
				lineNum += 1
				if line:lower():find(queryLower, 1, true) then
					table.insert(matches, { path = path, lineNum = lineNum, line = line })
					if not fileHit then fileCount += 1; fileHit = true end
					if #matches >= 200 then break end
				end
			end
			if #matches >= 200 then break end
		end

		resultsLabel.Text = `{#matches} results in {fileCount} files`
		resultsLabel.TextColor3 = if #matches > 0 then Theme.Color.Green else Theme.Color.TextDim

		for i, match in matches do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 30)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.ClipsDescendants = true
			row.Parent = resultsScroll

			local pathLabel = Instance.new("TextLabel")
			pathLabel.Size = UDim2.new(1, -4, 0, 14)
			pathLabel.Position = UDim2.fromOffset(4, 1)
			pathLabel.BackgroundTransparency = 1
			pathLabel.Text = `{match.path}:{match.lineNum}`
			pathLabel.TextColor3 = Theme.fileColor(match.path)
			pathLabel.Font = Theme.Font.Mono
			pathLabel.TextSize = 9
			pathLabel.TextXAlignment = Enum.TextXAlignment.Left
			pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
			pathLabel.Parent = row

			local lineLabel = Instance.new("TextLabel")
			lineLabel.Size = UDim2.new(1, -4, 0, 14)
			lineLabel.Position = UDim2.fromOffset(4, 15)
			lineLabel.BackgroundTransparency = 1
			lineLabel.Text = match.line:gsub("^%s+", "")
			lineLabel.TextColor3 = Theme.Color.TextMuted
			lineLabel.Font = Theme.Font.Mono
			lineLabel.TextSize = 10
			lineLabel.TextXAlignment = Enum.TextXAlignment.Left
			lineLabel.TextTruncate = Enum.TextTruncate.AtEnd
			lineLabel.Parent = row
		end
	end)
end

--==============================--
--       AUTO-BACKUP            --
--==============================--

function App._toggleAutoBackup(self: App, enabled: boolean)
	self.autoBackupEnabled = enabled
	self.pluginRef:SetSetting(SETTING_AUTOBACKUP, enabled)

	if enabled then
		self:_log("Auto-backup enabled (every 5 min)", Theme.Color.Green)
		self.autoBackupThread = task.spawn(function()
			while self.autoBackupEnabled and not self.destroyed do
				task.wait(300) -- 5 minutes
				if self.destroyed or not self.autoBackupEnabled or not self.connected or not self.remoteReady or self.busy then continue end

				local localFiles = self.serializer:getFileContentsMap()
				local hasChanges = false
				for path, content in localFiles do
					if self.remoteFiles[path] ~= content then hasChanges = true; break end
				end
				if not hasChanges then
					for path in self.remoteFiles do
						if not localFiles[path] then hasChanges = true; break end
					end
				end

				if hasChanges then
					self:_log("Auto-backup: pushing changes...", Theme.Color.Yellow)
					local msg = `Auto-backup {os.date("%Y-%m-%d %H:%M")}`
					local checkboxList = self.refs.stagingCheckboxes :: Components.CheckboxListHandle
					checkboxList.setAll(true)
					self.refs.commitInput.Text = msg
					self:commitAndPush()
				end
			end
		end)
	else
		self:_log("Auto-backup disabled")
		if self.autoBackupThread then
			task.cancel(self.autoBackupThread)
			self.autoBackupThread = nil
		end
	end
end

--==============================--
--         DESTROY              --
--==============================--

function App.destroy(self: App)
	self.destroyed = true
	-- Stop auto-backup
	self.autoBackupEnabled = false
	if self.autoBackupThread then
		task.cancel(self.autoBackupThread)
		self.autoBackupThread = nil
	end
	for _, conn in self.connections do conn:Disconnect() end
	self.connections = {}
	if self.refs.root then self.refs.root:Destroy() end
	if self.refs.outputRoot then self.refs.outputRoot:Destroy() end
	if self.refs.diffRoot then self.refs.diffRoot:Destroy() end
end

return App