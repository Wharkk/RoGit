local Theme = require(script.Parent.Theme)

local DiffEngineModule = require(script.Parent.DiffEngine)
type DiffLine = DiffEngineModule.DiffLine
type DiffResult = DiffEngineModule.DiffResult

local Components = {}

--==============================--
--          BUTTON              --
--==============================--

function Components.createButton(parent: GuiObject, config: {
	text: string,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	color: Color3?,
	textColor: Color3?,
	font: Enum.Font?,
	textSize: number?,
	autoSize: boolean?,
	onClick: (() -> ())?,
	}): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = config.text:gsub("%s+", "") .. "Btn"
	btn.Text = config.text
	btn.Size = config.size or UDim2.new(1, 0, 0, 32)
	btn.Position = config.position or UDim2.fromScale(0, 0)
	btn.LayoutOrder = config.layoutOrder or 0
	btn.BackgroundColor3 = config.color or Theme.Color.Accent
	btn.TextColor3 = config.textColor or Theme.Color.Background
	btn.Font = config.font or Theme.Font.Bold
	btn.TextSize = config.textSize or Theme.Size.TextNormal
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Parent = parent

	if config.autoSize then
		btn.AutomaticSize = Enum.AutomaticSize.X
		btn.Size = UDim2.new(0, 0, 0, 32)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, Theme.Size.SpacingL)
		pad.PaddingRight = UDim.new(0, Theme.Size.SpacingL)
		pad.Parent = btn
	end

	Instance.new("UICorner", btn).CornerRadius = Theme.Corner

	local base = config.color or Theme.Color.Accent
	local hover = base:Lerp(Color3.new(1, 1, 1), 0.15)
	btn.MouseEnter:Connect(function() btn.BackgroundColor3 = hover end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = base end)
	if config.onClick then btn.MouseButton1Click:Connect(config.onClick) end

	return btn
end

--==============================--
--       ICON BUTTON            --
--==============================--

function Components.createIconButton(parent: GuiObject, config: {
	icon: string,
	tooltip: string,
	size: UDim2?,
	layoutOrder: number?,
	color: Color3?,
	onClick: (() -> ())?,
	}): GuiButton
	local isImage = config.icon:sub(1, 13) == "rbxassetid://"
	local btnSize = config.size or UDim2.fromOffset(28, 28)
	local norm = config.color or Theme.Color.TextMuted

	local function addTooltip(btn: GuiButton)
		if not config.tooltip or config.tooltip == "" then return end
		local tip = Instance.new("TextLabel")
		tip.Name = "Tooltip"
		tip.Text = config.tooltip
		tip.Size = UDim2.fromOffset(0, 20)
		tip.AutomaticSize = Enum.AutomaticSize.X
		tip.Position = UDim2.new(0.5, 0, 1, 4)
		tip.AnchorPoint = Vector2.new(0.5, 0)
		tip.BackgroundColor3 = Theme.Color.Surface
		tip.BorderSizePixel = 0
		tip.TextColor3 = Theme.Color.Text
		tip.Font = Theme.Font.Regular
		tip.TextSize = 10
		tip.ZIndex = 100
		tip.Visible = false
		tip.Parent = btn

		Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 3)

		local tipPad = Instance.new("UIPadding")
		tipPad.PaddingLeft = UDim.new(0, 6)
		tipPad.PaddingRight = UDim.new(0, 6)
		tipPad.Parent = tip

		local tipStroke = Instance.new("UIStroke")
		tipStroke.Color = Theme.Color.Border
		tipStroke.Thickness = 1
		tipStroke.Parent = tip

		btn.MouseEnter:Connect(function()
			-- Clamp tooltip: flip above button if it would go off the bottom
			local widget = btn:FindFirstAncestorOfClass("DockWidgetPluginGui")
			if widget then
				local btnBottom = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y
				local widgetBottom = widget.AbsolutePosition.Y + widget.AbsoluteSize.Y
				if btnBottom + 24 > widgetBottom then
					tip.Position = UDim2.new(0.5, 0, 0, -24)
					tip.AnchorPoint = Vector2.new(0.5, 1)
				else
					tip.Position = UDim2.new(0.5, 0, 1, 4)
					tip.AnchorPoint = Vector2.new(0.5, 0)
				end
			end
			tip.Visible = true
		end)
		btn.MouseLeave:Connect(function() tip.Visible = false end)
	end

	if isImage then
		local btn = Instance.new("ImageButton")
		btn.Name = config.tooltip:gsub("%s+", "") .. "Icon"
		btn.Image = config.icon
		btn.Size = btnSize
		btn.LayoutOrder = config.layoutOrder or 0
		btn.BackgroundTransparency = 1
		btn.ImageColor3 = norm
		btn.ScaleType = Enum.ScaleType.Fit
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.ClipsDescendants = false
		btn.Parent = parent

		Instance.new("UICorner", btn).CornerRadius = Theme.CornerSmall
		local imgPad = Instance.new("UIPadding")
		imgPad.PaddingTop = UDim.new(0, 4)
		imgPad.PaddingBottom = UDim.new(0, 4)
		imgPad.PaddingLeft = UDim.new(0, 4)
		imgPad.PaddingRight = UDim.new(0, 4)
		imgPad.Parent = btn

		btn.MouseEnter:Connect(function()
			btn.BackgroundTransparency = 0.8
			btn.BackgroundColor3 = Theme.Color.SurfaceHover
			btn.ImageColor3 = Theme.Color.Text
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundTransparency = 1
			btn.ImageColor3 = norm
		end)
		if config.onClick then btn.MouseButton1Click:Connect(config.onClick) end
		addTooltip(btn)
		return btn
	else
		local btn = Instance.new("TextButton")
		btn.Name = config.tooltip:gsub("%s+", "") .. "Icon"
		btn.Text = config.icon
		btn.Size = btnSize
		btn.LayoutOrder = config.layoutOrder or 0
		btn.BackgroundTransparency = 1
		btn.TextColor3 = norm
		btn.Font = Theme.Font.Bold
		btn.TextSize = Theme.Size.TextNormal
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.ClipsDescendants = false
		btn.Parent = parent

		Instance.new("UICorner", btn).CornerRadius = Theme.CornerSmall
		btn.MouseEnter:Connect(function()
			btn.BackgroundTransparency = 0.8
			btn.BackgroundColor3 = Theme.Color.SurfaceHover
			btn.TextColor3 = Theme.Color.Text
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundTransparency = 1
			btn.TextColor3 = norm
		end)
		if config.onClick then btn.MouseButton1Click:Connect(config.onClick) end
		addTooltip(btn)
		return btn
	end
end

--==============================--
--         TEXT INPUT            --
--==============================--

function Components.createInput(parent: GuiObject, config: {
	placeholder: string,
	size: UDim2?,
	layoutOrder: number?,
	multiLine: boolean?,
	font: Enum.Font?,
	}): TextBox
	local isMulti = config.multiLine or false
	local wrapHeight = if isMulti then (config.size and config.size.Y.Offset or 60) else 32

	local wrap = Instance.new("Frame")
	wrap.Name = "InputWrap"
	wrap.Size = config.size or UDim2.new(1, 0, 0, wrapHeight)
	wrap.LayoutOrder = config.layoutOrder or 0
	wrap.BackgroundColor3 = Theme.Color.InputBg
	wrap.BorderSizePixel = 0
	wrap.ClipsDescendants = true
	wrap.Parent = parent

	Instance.new("UICorner", wrap).CornerRadius = Theme.CornerSmall
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Border
	stroke.Thickness = 1
	stroke.Parent = wrap

	local input: TextBox
	if isMulti then
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "InputScroll"
		scroll.Size = UDim2.new(1, 0, 1, 0)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 3
		scroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.Parent = wrap

		input = Instance.new("TextBox")
		input.Name = "Input"
		input.Text = ""
		input.Size = UDim2.new(1, -Theme.Size.SpacingM * 2, 0, 1000)
		input.Position = UDim2.fromOffset(Theme.Size.SpacingM, Theme.Size.SpacingS)
		input.AutomaticSize = Enum.AutomaticSize.Y
		input.BackgroundTransparency = 1
		input.PlaceholderText = config.placeholder
		input.PlaceholderColor3 = Theme.Color.TextDim
		input.TextColor3 = Theme.Color.Text
		input.Font = config.font or Theme.Font.Regular
		input.TextSize = Theme.Size.TextNormal
		input.TextXAlignment = Enum.TextXAlignment.Left
		input.TextYAlignment = Enum.TextYAlignment.Top
		input.ClearTextOnFocus = false
		input.MultiLine = true
		input.TextWrapped = true
		input.BorderSizePixel = 0
		input.Parent = scroll
	else
		input = Instance.new("TextBox")
		input.Name = "Input"
		input.Text = ""
		input.Size = UDim2.new(1, -Theme.Size.SpacingM * 2, 1, -Theme.Size.SpacingS * 2)
		input.Position = UDim2.fromOffset(Theme.Size.SpacingM, Theme.Size.SpacingS)
		input.BackgroundTransparency = 1
		input.PlaceholderText = config.placeholder
		input.PlaceholderColor3 = Theme.Color.TextDim
		input.TextColor3 = Theme.Color.Text
		input.Font = config.font or Theme.Font.Regular
		input.TextSize = Theme.Size.TextNormal
		input.TextXAlignment = Enum.TextXAlignment.Left
		input.TextYAlignment = Enum.TextYAlignment.Center
		input.ClearTextOnFocus = false
		input.MultiLine = false
		input.TextWrapped = false
		input.BorderSizePixel = 0
		input.Parent = wrap
	end

	input.Focused:Connect(function() stroke.Color = Theme.Color.Accent end)
	input.FocusLost:Connect(function() stroke.Color = Theme.Color.Border end)
	return input
end

--==============================--
--         DROPDOWN             --
--==============================--

export type DropdownHandle = {
	frame: Frame,
	getSelected: () -> string?,
	setSelected: (value: string) -> (),
	setItems: (items: { string }) -> (),
	onChanged: (callback: (value: string) -> ()) -> (),
	close: () -> (),
}

function Components.createDropdown(parent: GuiObject, config: {
	items: { string },
	placeholder: string?,
	selected: string?,
	layoutOrder: number?,
	maxVisibleItems: number?,
	showCreateOption: boolean?,
	createPlaceholder: string?,
	onCreateNew: ((name: string) -> ())?,
	}): DropdownHandle
	local items = config.items
	local selected: string? = config.selected
	local isOpen = false
	local changeCallbacks: { (value: string) -> () } = {}
	local maxVisible = config.maxVisibleItems or 6
	local clickCatcher: TextButton? = nil
	local closeDropdown: () -> () = function() end

	local frame = Instance.new("Frame")
	frame.Name = "Dropdown"
	frame.Size = UDim2.new(1, 0, 0, 28)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = config.layoutOrder or 0
	frame.ClipsDescendants = false
	frame.Parent = parent

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.Size = UDim2.new(1, 0, 0, 28)
	toggle.BackgroundColor3 = Theme.Color.InputBg
	toggle.BorderSizePixel = 0
	toggle.AutoButtonColor = false
	toggle.Text = ""
	toggle.Parent = frame

	Instance.new("UICorner", toggle).CornerRadius = Theme.CornerSmall
	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Color = Theme.Color.Border
	toggleStroke.Thickness = 1
	toggleStroke.Parent = toggle

	local toggleLabel = Instance.new("TextLabel")
	toggleLabel.Name = "Label"
	toggleLabel.Size = UDim2.new(1, -28, 1, 0)
	toggleLabel.Position = UDim2.fromOffset(Theme.Size.SpacingM, 0)
	toggleLabel.BackgroundTransparency = 1
	toggleLabel.Text = selected or config.placeholder or "Select..."
	toggleLabel.TextColor3 = if selected then Theme.Color.Text else Theme.Color.TextDim
	toggleLabel.Font = Theme.Font.Regular
	toggleLabel.TextSize = Theme.Size.TextNormal
	toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
	toggleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	toggleLabel.Parent = toggle

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.fromOffset(20, 28)
	arrow.Position = UDim2.new(1, -24, 0, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "v"
	arrow.TextColor3 = Theme.Color.TextMuted
	arrow.Font = Theme.Font.Bold
	arrow.TextSize = Theme.Size.TextSmall
	arrow.Parent = toggle

	local listContainer = Instance.new("Frame")
	listContainer.Name = "ListContainer"
	listContainer.BackgroundColor3 = Theme.Color.Surface
	listContainer.BorderSizePixel = 0
	listContainer.Visible = false
	listContainer.ZIndex = 50
	listContainer.Parent = frame

	Instance.new("UICorner", listContainer).CornerRadius = Theme.CornerSmall
	local lcStroke = Instance.new("UIStroke")
	lcStroke.Color = Theme.Color.Border
	lcStroke.Thickness = 1
	lcStroke.Parent = listContainer

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 51
	scroll.Parent = listContainer

	Instance.new("UIListLayout", scroll).SortOrder = Enum.SortOrder.LayoutOrder

	local createRow: Frame? = nil
	local createInput: TextBox? = nil

	if config.showCreateOption then
		createRow = Instance.new("Frame")
		createRow.Name = "CreateRow"
		createRow.Size = UDim2.new(1, 0, 0, 28)
		createRow.BackgroundColor3 = Theme.Color.Surface
		createRow.BorderSizePixel = 0
		createRow.ZIndex = 51
		createRow.Parent = listContainer

		local divider = Instance.new("Frame")
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.BackgroundColor3 = Theme.Color.Border
		divider.BorderSizePixel = 0
		divider.ZIndex = 51
		divider.Parent = createRow

		local ci = Instance.new("TextBox")
		ci.Name = "NewInput"
		ci.Text = ""
		ci.Size = UDim2.new(1, -36, 0, 26)
		ci.Position = UDim2.fromOffset(4, 1)
		ci.BackgroundTransparency = 1
		ci.PlaceholderText = config.createPlaceholder or "+ New..."
		ci.PlaceholderColor3 = Theme.Color.TextDim
		ci.TextColor3 = Theme.Color.Text
		ci.Font = Theme.Font.Regular
		ci.TextSize = Theme.Size.TextSmall
		ci.TextXAlignment = Enum.TextXAlignment.Left
		ci.ClearTextOnFocus = true
		ci.BorderSizePixel = 0
		ci.ZIndex = 52
		ci.Parent = createRow
		createInput = ci

		local addBtn = Instance.new("TextButton")
		addBtn.Size = UDim2.fromOffset(28, 26)
		addBtn.Position = UDim2.new(1, -30, 0, 1)
		addBtn.BackgroundTransparency = 1
		addBtn.Text = "+"
		addBtn.TextColor3 = Theme.Color.Green
		addBtn.Font = Theme.Font.Bold
		addBtn.TextSize = Theme.Size.TextLarge
		addBtn.ZIndex = 52
		addBtn.Parent = createRow

		addBtn.MouseButton1Click:Connect(function()
			local name = ci.Text:gsub("%s", "")
			if name ~= "" and config.onCreateNew then
				config.onCreateNew(name)
				ci.Text = ""
			end
		end)
	end

	local function updateListSize()
		local itemCount = #items
		local visibleCount = math.min(itemCount, maxVisible)
		local listHeight = visibleCount * 26
		local createHeight = if createRow then 29 else 0
		local totalHeight = listHeight + createHeight

		listContainer.Size = UDim2.new(1, 0, 0, totalHeight)
		listContainer.Position = UDim2.fromOffset(0, 30)

		scroll.Size = UDim2.new(1, 0, 0, listHeight)
		scroll.Position = UDim2.fromOffset(0, 0)

		if createRow then
			createRow.Position = UDim2.fromOffset(0, listHeight)
		end
	end

	local function renderItems()
		for _, child in scroll:GetChildren() do
			if child:IsA("TextButton") then child:Destroy() end
		end

		for i, item in items do
			local isCurrent = item == selected

			local btn = Instance.new("TextButton")
			btn.Name = "Item_" .. item
			btn.Size = UDim2.new(1, 0, 0, 26)
			btn.BackgroundColor3 = if isCurrent then Theme.Color.SurfaceHover else Theme.Color.Surface
			btn.BackgroundTransparency = if isCurrent then 0 else 1
			btn.Text = ""
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = false
			btn.LayoutOrder = i
			btn.ZIndex = 52
			btn.Parent = scroll

			local itemLabel = Instance.new("TextLabel")
			itemLabel.Size = UDim2.new(1, -8, 1, 0)
			itemLabel.Position = UDim2.fromOffset(Theme.Size.SpacingM, 0)
			itemLabel.BackgroundTransparency = 1
			itemLabel.Text = item
			itemLabel.TextColor3 = if isCurrent then Theme.Color.Accent else Theme.Color.Text
			itemLabel.Font = if isCurrent then Theme.Font.Bold else Theme.Font.Regular
			itemLabel.TextSize = Theme.Size.TextSmall
			itemLabel.TextXAlignment = Enum.TextXAlignment.Left
			itemLabel.TextTruncate = Enum.TextTruncate.AtEnd
			itemLabel.ZIndex = 52
			itemLabel.Parent = btn

			if not isCurrent then
				btn.MouseEnter:Connect(function()
					btn.BackgroundTransparency = 0.5
					btn.BackgroundColor3 = Theme.Color.SurfaceHover
				end)
				btn.MouseLeave:Connect(function()
					btn.BackgroundTransparency = 1
				end)
			end

			btn.MouseButton1Click:Connect(function()
				selected = item
				toggleLabel.Text = item
				toggleLabel.TextColor3 = Theme.Color.Text
				for _, cb in changeCallbacks do cb(item) end
				closeDropdown()
			end)
		end

		updateListSize()
	end

	closeDropdown = function()
		if not isOpen then return end
		isOpen = false
		listContainer.Visible = false
		arrow.Text = "v"
		toggleStroke.Color = Theme.Color.Border
		if clickCatcher then
			clickCatcher:Destroy()
			clickCatcher = nil
		end
	end

	local function openDropdown()
		if isOpen then return end
		isOpen = true
		listContainer.Visible = true
		arrow.Text = "^"
		toggleStroke.Color = Theme.Color.Accent
		renderItems()

		-- Click-catcher overlay for dismiss-on-outside.
		-- Plugins can't connect to widget.InputBegan (capability-restricted),
		-- so we parent a transparent TextButton behind the dropdown list.
		local widget = frame:FindFirstAncestorOfClass("DockWidgetPluginGui")
		if widget then
			local catcher = Instance.new("TextButton")
			catcher.Name = "DropdownClickCatcher"
			catcher.Size = UDim2.fromScale(1, 1)
			catcher.BackgroundTransparency = 1
			catcher.Text = ""
			catcher.AutoButtonColor = false
			catcher.ZIndex = 49
			catcher.Parent = widget
			catcher.MouseButton1Click:Connect(closeDropdown)
			clickCatcher = catcher
		end
	end

	toggle.MouseButton1Click:Connect(function()
		if isOpen then closeDropdown() else openDropdown() end
	end)

	toggle.MouseEnter:Connect(function() toggle.BackgroundColor3 = Theme.Color.SurfaceHover end)
	toggle.MouseLeave:Connect(function() toggle.BackgroundColor3 = Theme.Color.InputBg end)

	renderItems()

	return {
		frame = frame,
		getSelected = function(): string? return selected end,
		setSelected = function(value: string)
			selected = value
			toggleLabel.Text = value
			toggleLabel.TextColor3 = Theme.Color.Text
		end,
		setItems = function(newItems: { string })
			items = newItems
			if isOpen then renderItems() end
		end,
		onChanged = function(callback: (value: string) -> ())
			table.insert(changeCallbacks, callback)
		end,
		close = closeDropdown,
	}
end

--==============================--
--         CHECKBOX             --
--==============================--

export type CheckboxHandle = {
	frame: Frame,
	getValue: () -> boolean,
	setValue: (value: boolean) -> (),
	onChanged: (callback: (value: boolean) -> ()) -> (),
}

function Components.createCheckbox(parent: GuiObject, config: {
	label: string,
	checked: boolean?,
	layoutOrder: number?,
	labelColor: Color3?,
	labelFont: Enum.Font?,
	}): CheckboxHandle
	local checked = config.checked or false
	local callbacks: { (value: boolean) -> () } = {}

	local frame = Instance.new("TextButton")
	frame.Name = "Checkbox_" .. config.label:sub(1, 20):gsub("%s+", "")
	frame.Size = UDim2.new(1, 0, 0, 22)
	frame.BackgroundTransparency = 1
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.LayoutOrder = config.layoutOrder or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent

	frame.MouseEnter:Connect(function()
		frame.BackgroundTransparency = 0.6
		frame.BackgroundColor3 = Theme.Color.SurfaceHover
	end)
	frame.MouseLeave:Connect(function()
		frame.BackgroundTransparency = 1
	end)

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromOffset(16, 16)
	box.Position = UDim2.fromOffset(Theme.Size.SpacingM, 3)
	box.BackgroundColor3 = if checked then Theme.Color.Accent else Theme.Color.InputBg
	box.BorderSizePixel = 0
	box.Parent = frame

	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = if checked then Theme.Color.Accent else Theme.Color.Border
	boxStroke.Thickness = 1
	boxStroke.Parent = box

	local checkMark = Instance.new("TextLabel")
	checkMark.Size = UDim2.fromScale(1, 1)
	checkMark.BackgroundTransparency = 1
	checkMark.Text = if checked then "x" else ""
	checkMark.TextColor3 = Theme.Color.Background
	checkMark.Font = Theme.Font.Bold
	checkMark.TextSize = 11
	checkMark.Parent = box

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -32, 0, 22)
	label.Position = UDim2.fromOffset(30, 0)
	label.BackgroundTransparency = 1
	label.Text = config.label
	label.TextColor3 = config.labelColor or Theme.Color.Text
	label.Font = config.labelFont or Theme.Font.Mono
	label.TextSize = Theme.Size.TextSmall
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = frame

	local function updateVisuals()
		box.BackgroundColor3 = if checked then Theme.Color.Accent else Theme.Color.InputBg
		checkMark.Text = if checked then "x" else ""
		boxStroke.Color = if checked then Theme.Color.Accent else Theme.Color.Border
	end

	local function toggle()
		checked = not checked
		updateVisuals()
		for _, cb in callbacks do cb(checked) end
	end

	frame.MouseButton1Click:Connect(toggle)

	return {
		frame = frame :: any,
		getValue = function(): boolean return checked end,
		setValue = function(value: boolean)
			checked = value
			updateVisuals()
		end,
		onChanged = function(callback: (value: boolean) -> ())
			table.insert(callbacks, callback)
		end,
	}
end

--==============================--
--       CHECKBOX LIST          --
--==============================--

export type CheckboxListHandle = {
	frame: Frame,
	getChecked: () -> { string },
	setAll: (value: boolean) -> (),
	setItems: (items: { { path: string, color: Color3? } }) -> (),
	onChanged: (callback: (checkedPaths: { string }) -> ()) -> (),
}

function Components.createCheckboxList(parent: GuiObject, config: {
	items: { { path: string, color: Color3? } },
	layoutOrder: number?,
	allChecked: boolean?,
	}): CheckboxListHandle
	local checkboxes: { { path: string, handle: CheckboxHandle } } = {}
	local changeCallbacks: { (checkedPaths: { string }) -> () } = {}

	local frame = Instance.new("Frame")
	frame.Name = "CheckboxList"
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = config.layoutOrder or 0
	frame.Parent = parent

	Instance.new("UIListLayout", frame).SortOrder = Enum.SortOrder.LayoutOrder

	local headerRow = Instance.new("Frame")
	headerRow.Name = "Header"
	headerRow.Size = UDim2.new(1, 0, 0, 24)
	headerRow.BackgroundTransparency = 1
	headerRow.LayoutOrder = 0
	headerRow.Parent = frame

	local allBtn = Instance.new("TextButton")
	allBtn.Name = "SelectAll"
	allBtn.Size = UDim2.fromOffset(40, 20)
	allBtn.Position = UDim2.fromOffset(Theme.Size.SpacingM, 2)
	allBtn.BackgroundColor3 = Theme.Color.Surface
	allBtn.Text = "All"
	allBtn.TextColor3 = Theme.Color.TextMuted
	allBtn.Font = Theme.Font.Bold
	allBtn.TextSize = 10
	allBtn.BorderSizePixel = 0
	allBtn.AutoButtonColor = false
	allBtn.Parent = headerRow
	Instance.new("UICorner", allBtn).CornerRadius = UDim.new(0, 3)

	local noneBtn = Instance.new("TextButton")
	noneBtn.Name = "SelectNone"
	noneBtn.Size = UDim2.fromOffset(45, 20)
	noneBtn.Position = UDim2.fromOffset(Theme.Size.SpacingM + 44, 2)
	noneBtn.BackgroundColor3 = Theme.Color.Surface
	noneBtn.Text = "None"
	noneBtn.TextColor3 = Theme.Color.TextMuted
	noneBtn.Font = Theme.Font.Bold
	noneBtn.TextSize = 10
	noneBtn.BorderSizePixel = 0
	noneBtn.AutoButtonColor = false
	noneBtn.Parent = headerRow
	Instance.new("UICorner", noneBtn).CornerRadius = UDim.new(0, 3)

	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.fromOffset(50, 20)
	countLabel.Position = UDim2.new(1, -58, 0, 2)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0/0"
	countLabel.TextColor3 = Theme.Color.TextDim
	countLabel.Font = Theme.Font.Regular
	countLabel.TextSize = 10
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.Parent = headerRow

	local function fireChange()
		local checked: { string } = {}
		for _, cb in checkboxes do
			if cb.handle.getValue() then table.insert(checked, cb.path) end
		end
		countLabel.Text = `{#checked}/{#checkboxes}`
		for _, fn in changeCallbacks do fn(checked) end
	end

	local function buildItems(items: { { path: string, color: Color3? } })
		for _, child in frame:GetChildren() do
			if child.Name:match("^Checkbox_") then child:Destroy() end
		end
		checkboxes = {}

		for i, item in items do
			local handle = Components.createCheckbox(frame, {
				label = item.path,
				checked = config.allChecked or false,
				layoutOrder = i,
				labelColor = item.color,
			})
			handle.onChanged(function() fireChange() end)
			table.insert(checkboxes, { path = item.path, handle = handle })
		end

		fireChange()
	end

	allBtn.MouseButton1Click:Connect(function()
		for _, cb in checkboxes do cb.handle.setValue(true) end
		fireChange()
	end)

	noneBtn.MouseButton1Click:Connect(function()
		for _, cb in checkboxes do cb.handle.setValue(false) end
		fireChange()
	end)

	buildItems(config.items)

	return {
		frame = frame,
		getChecked = function(): { string }
			local result: { string } = {}
			for _, cb in checkboxes do
				if cb.handle.getValue() then table.insert(result, cb.path) end
			end
			return result
		end,
		setAll = function(value: boolean)
			for _, cb in checkboxes do cb.handle.setValue(value) end
			fireChange()
		end,
		setItems = function(items: { { path: string, color: Color3? } })
			buildItems(items)
		end,
		onChanged = function(callback: (checkedPaths: { string }) -> ())
			table.insert(changeCallbacks, callback)
		end,
	}
end

--==============================--
--         SECTION              --
--==============================--

export type SectionHandle = {
	frame: Frame,
	content: Frame,
	updateCount: (count: number) -> (),
	setCollapsed: (collapsed: boolean) -> (),
}

function Components.createSection(parent: GuiObject, config: {
	title: string,
	count: number?,
	layoutOrder: number?,
	collapsible: boolean?,
	defaultCollapsed: boolean?,
	actionText: string?,
	onAction: (() -> ())?,
	}): SectionHandle
	local collapsed = config.defaultCollapsed or false

	local frame = Instance.new("Frame")
	frame.Name = config.title:gsub("%s+", "") .. "Section"
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = config.layoutOrder or 0
	frame.Parent = parent

	Instance.new("UIListLayout", frame).SortOrder = Enum.SortOrder.LayoutOrder

	-- Header is a TextButton so entire row is clickable (no separate hit area needed)
	local header: TextButton
	if config.collapsible then
		header = Instance.new("TextButton")
	else
		header = Instance.new("TextButton")
	end
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 28)
	header.BackgroundTransparency = 1
	header.Text = ""
	header.AutoButtonColor = false
	header.BorderSizePixel = 0
	header.LayoutOrder = 0
	header.Parent = frame

	-- Arrow indicator
	local arrowLabel: TextLabel? = nil
	if config.collapsible then
		arrowLabel = Instance.new("TextLabel")
		arrowLabel.Size = UDim2.fromOffset(14, 28)
		arrowLabel.Position = UDim2.fromOffset(Theme.Size.SpacingM, 0)
		arrowLabel.BackgroundTransparency = 1
		arrowLabel.Text = if collapsed then ">" else "v"
		arrowLabel.TextColor3 = Theme.Color.TextMuted
		arrowLabel.Font = Theme.Font.Bold
		arrowLabel.TextSize = Theme.Size.TextSmall
		arrowLabel.TextXAlignment = Enum.TextXAlignment.Left
		arrowLabel.Parent = header
	end

	local titleX = Theme.Size.SpacingM + (if config.collapsible then 14 else 0)

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0, 0, 0, 28)
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Position = UDim2.fromOffset(titleX, 0)
	title.BackgroundTransparency = 1
	title.Text = config.title:upper()
	title.TextColor3 = Theme.Color.TextMuted
	title.Font = Theme.Font.Bold
	title.TextSize = Theme.Size.TextSmall
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	-- Count badge
	local countLbl = Instance.new("TextLabel")
	countLbl.Name = "Count"
	countLbl.Size = UDim2.fromOffset(40, 28)
	countLbl.Position = UDim2.new(0, titleX + 90, 0, 0)
	countLbl.BackgroundTransparency = 1
	countLbl.Text = if config.count then `({config.count})` else ""
	countLbl.TextColor3 = Theme.Color.TextDim
	countLbl.Font = Theme.Font.Regular
	countLbl.TextSize = Theme.Size.TextSmall
	countLbl.TextXAlignment = Enum.TextXAlignment.Left
	countLbl.Parent = header

	-- Action button (absolute positioned, right side)
	if config.actionText and config.onAction then
		local isIcon = type(config.actionText) == "string" and config.actionText:sub(1, 13) == "rbxassetid://"
		if isIcon then
			local actionBtn = Instance.new("ImageButton")
			actionBtn.Name = "Action"
			actionBtn.Size = UDim2.fromOffset(20, 20)
			actionBtn.Position = UDim2.new(1, -28, 0, 4)
			actionBtn.BackgroundTransparency = 1
			actionBtn.Image = config.actionText
			actionBtn.ImageColor3 = Theme.Color.TextMuted
			actionBtn.BorderSizePixel = 0
			actionBtn.AutoButtonColor = false
			actionBtn.ZIndex = 3
			actionBtn.Parent = header
			actionBtn.MouseEnter:Connect(function() actionBtn.ImageColor3 = Theme.Color.Text end)
			actionBtn.MouseLeave:Connect(function() actionBtn.ImageColor3 = Theme.Color.TextMuted end)
			actionBtn.MouseButton1Click:Connect(config.onAction)
		else
			local actionBtn = Instance.new("TextButton")
			actionBtn.Name = "Action"
			actionBtn.Size = UDim2.fromOffset(30, 20)
			actionBtn.Position = UDim2.new(1, -38, 0, 4)
			actionBtn.BackgroundTransparency = 1
			actionBtn.Text = config.actionText
			actionBtn.TextColor3 = Theme.Color.TextMuted
			actionBtn.Font = Theme.Font.Bold
			actionBtn.TextSize = Theme.Size.TextSmall
			actionBtn.BorderSizePixel = 0
			actionBtn.AutoButtonColor = false
			actionBtn.ZIndex = 3
			actionBtn.Parent = header
			actionBtn.MouseEnter:Connect(function() actionBtn.TextColor3 = Theme.Color.Text end)
			actionBtn.MouseLeave:Connect(function() actionBtn.TextColor3 = Theme.Color.TextMuted end)
			actionBtn.MouseButton1Click:Connect(config.onAction)
		end
	end

	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.LayoutOrder = 1
	content.Visible = not collapsed
	content.Parent = frame

	Instance.new("UIListLayout", content).SortOrder = Enum.SortOrder.LayoutOrder

	-- Click handler for collapsible
	if config.collapsible then
		header.MouseButton1Click:Connect(function()
			collapsed = not collapsed
			content.Visible = not collapsed
			if arrowLabel then arrowLabel.Text = if collapsed then ">" else "v" end
			if not collapsed and config.onExpand then config.onExpand() end
		end)
		header.MouseEnter:Connect(function()
			header.BackgroundTransparency = 0.7
			header.BackgroundColor3 = Theme.Color.SurfaceHover
		end)
		header.MouseLeave:Connect(function()
			header.BackgroundTransparency = 1
		end)
	end

	return {
		frame = frame,
		content = content,
		updateCount = function(count: number) countLbl.Text = `({count})` end,
		setCollapsed = function(value: boolean)
			collapsed = value
			content.Visible = not collapsed
			if arrowLabel then arrowLabel.Text = if collapsed then ">" else "v" end
		end,
	}
end

--==============================--
--       COMMIT ROW             --
--==============================--

function Components.createCommitRow(parent: GuiObject, config: {
	shortSha: string,
	message: string,
	author: string,
	date: string,
	layoutOrder: number?,
	onRevert: ((sha: string) -> ())?,
	onViewFiles: ((sha: string) -> ())?,
	}): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Commit_" .. config.shortSha
	frame.Size = UDim2.new(1, 0, 0, 40)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = config.layoutOrder or 0
	frame.ClipsDescendants = false
	frame.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.Size.SpacingM)
	pad.PaddingRight = UDim.new(0, Theme.Size.SpacingM)
	pad.Parent = frame

	-- Action buttons (visible on hover)
	local actionsFrame = Instance.new("Frame")
	actionsFrame.Name = "Actions"
	actionsFrame.Size = UDim2.fromOffset(50, 20)
	actionsFrame.Position = UDim2.new(1, -52, 0, 2)
	actionsFrame.BackgroundTransparency = 1
	actionsFrame.Visible = false
	actionsFrame.ZIndex = 10
	actionsFrame.Parent = frame

	local actLayout = Instance.new("UIListLayout")
	actLayout.FillDirection = Enum.FillDirection.Horizontal
	actLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	actLayout.Padding = UDim.new(0, 2)
	actLayout.Parent = actionsFrame

	if config.onRevert then
		local revertBtn = Instance.new("TextButton")
		revertBtn.Size = UDim2.fromOffset(22, 18)
		revertBtn.BackgroundColor3 = Theme.Color.Red
		revertBtn.BackgroundTransparency = 0.3
		revertBtn.BorderSizePixel = 0
		revertBtn.Text = "R"
		revertBtn.TextColor3 = Theme.Color.Text
		revertBtn.Font = Theme.Font.Bold
		revertBtn.TextSize = 9
		revertBtn.AutoButtonColor = false
		revertBtn.ZIndex = 11
		revertBtn.Parent = actionsFrame
		Instance.new("UICorner", revertBtn).CornerRadius = UDim.new(0, 3)
		revertBtn.MouseButton1Click:Connect(function() config.onRevert(config.shortSha) end)

		local tip = Instance.new("TextLabel")
		tip.Text = "Revert"
		tip.Size = UDim2.fromOffset(0, 16)
		tip.AutomaticSize = Enum.AutomaticSize.X
		tip.Position = UDim2.new(0.5, 0, 1, 2)
		tip.AnchorPoint = Vector2.new(0.5, 0)
		tip.BackgroundColor3 = Theme.Color.Surface
		tip.BorderSizePixel = 0
		tip.TextColor3 = Theme.Color.Text
		tip.Font = Theme.Font.Regular
		tip.TextSize = 9
		tip.ZIndex = 100
		tip.Visible = false
		tip.Parent = revertBtn
		Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 2)
		local tipPad = Instance.new("UIPadding")
		tipPad.PaddingLeft = UDim.new(0, 4)
		tipPad.PaddingRight = UDim.new(0, 4)
		tipPad.Parent = tip
		revertBtn.MouseEnter:Connect(function() tip.Visible = true end)
		revertBtn.MouseLeave:Connect(function() tip.Visible = false end)
	end

	frame.MouseEnter:Connect(function()
		frame.BackgroundTransparency = 0.6
		frame.BackgroundColor3 = Theme.Color.SurfaceHover
		actionsFrame.Visible = true
	end)
	frame.MouseLeave:Connect(function()
		frame.BackgroundTransparency = 1
		actionsFrame.Visible = false
	end)

	-- Row 1: hash + single-line message (truncated)
	local hash = Instance.new("TextLabel")
	hash.Size = UDim2.fromOffset(52, 20)
	hash.Position = UDim2.fromOffset(0, 2)
	hash.BackgroundTransparency = 1
	hash.Text = config.shortSha
	hash.TextColor3 = Theme.Color.Accent
	hash.Font = Theme.Font.Mono
	hash.TextSize = Theme.Size.TextSmall
	hash.TextXAlignment = Enum.TextXAlignment.Left
	hash.Parent = frame

	local firstLine = config.message:split("\n")[1] or config.message
	local msg = Instance.new("TextLabel")
	msg.Size = UDim2.new(1, -110, 0, 20)
	msg.Position = UDim2.fromOffset(54, 2)
	msg.BackgroundTransparency = 1
	msg.Text = firstLine
	msg.TextColor3 = Theme.Color.Text
	msg.Font = Theme.Font.Regular
	msg.TextSize = Theme.Size.TextSmall
	msg.TextXAlignment = Enum.TextXAlignment.Left
	msg.TextTruncate = Enum.TextTruncate.AtEnd
	msg.Parent = frame

	-- Row 2: author + date
	local dateStr = config.date
	if dateStr:find("T") then dateStr = dateStr:split("T")[1] end

	local meta = Instance.new("TextLabel")
	meta.Size = UDim2.new(1, -54, 0, 14)
	meta.Position = UDim2.fromOffset(54, 22)
	meta.BackgroundTransparency = 1
	meta.Text = `{config.author} - {dateStr}`
	meta.TextColor3 = Theme.Color.TextDim
	meta.Font = Theme.Font.Regular
	meta.TextSize = 10
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.Parent = frame

	return frame
end

--==============================--
--     SYNTAX HIGHLIGHTING      --
--==============================--

local LUAU_KEYWORDS: { [string]: boolean } = {}
for _, kw in { "and", "break", "continue", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "type", "export", "typeof" } do
	LUAU_KEYWORDS[kw] = true
end

local LUAU_BUILTINS: { [string]: boolean } = {}
for _, bi in { "game", "workspace", "script", "plugin", "warn", "error", "print", "require", "pcall", "xpcall", "select", "unpack", "rawget", "rawset", "setmetatable", "getmetatable", "tostring", "tonumber", "type", "typeof", "pairs", "ipairs", "next", "table", "string", "math", "coroutine", "task", "Instance", "Enum", "Vector3", "Vector2", "CFrame", "Color3", "UDim2", "UDim", "BrickColor", "Ray", "Region3", "NumberRange", "NumberSequence", "ColorSequence", "TweenInfo", "tick", "os", "wait", "spawn", "delay", "assert" } do
	LUAU_BUILTINS[bi] = true
end

local function hexColor(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local SYN_COLORS = {
	keyword = hexColor(Theme.Color.SynKeyword),
	builtin = hexColor(Theme.Color.SynBuiltin),
	str = hexColor(Theme.Color.SynString),
	comment = hexColor(Theme.Color.SynComment),
	number = hexColor(Theme.Color.SynNumber),
	operator = hexColor(Theme.Color.SynOperator),
	self_kw = hexColor(Theme.Color.SynSelf),
	type_kw = hexColor(Theme.Color.SynType),
}

local function escapeRich(text: string): string
	local result = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
	return result
end

local function wrapColor(text: string, hex: string): string
	return `<font color="{hex}">{text}</font>`
end

local function highlightLuau(line: string): string
	-- Full-line comment
	if line:match("^%s*%-%-") then
		return wrapColor(escapeRich(line), SYN_COLORS.comment)
	end

	local parts: { string } = {}
	local i = 1
	local len = #line

	while i <= len do
		local c = line:sub(i, i)

		-- String: double quote
		if c == '"' then
			local j = i + 1
			while j <= len do
				local sc = line:sub(j, j)
				if sc == '\\' then j += 2
				elseif sc == '"' then j += 1; break
				else j += 1 end
			end
			table.insert(parts, wrapColor(escapeRich(line:sub(i, j - 1)), SYN_COLORS.str))
			i = j
			-- String: single quote
		elseif c == "'" then
			local j = i + 1
			while j <= len do
				local sc = line:sub(j, j)
				if sc == '\\' then j += 2
				elseif sc == "'" then j += 1; break
				else j += 1 end
			end
			table.insert(parts, wrapColor(escapeRich(line:sub(i, j - 1)), SYN_COLORS.str))
			i = j
			-- String: backtick (template)
		elseif c == '`' then
			local j = i + 1
			while j <= len do
				local sc = line:sub(j, j)
				if sc == '\\' then j += 2
				elseif sc == '`' then j += 1; break
				else j += 1 end
			end
			table.insert(parts, wrapColor(escapeRich(line:sub(i, j - 1)), SYN_COLORS.str))
			i = j
			-- Long string: [[
		elseif c == '[' and line:sub(i, i + 1) == '[[' then
			local closePos = line:find("]]", i + 2, true)
			local j = if closePos then closePos + 2 else len + 1
			table.insert(parts, wrapColor(escapeRich(line:sub(i, j - 1)), SYN_COLORS.str))
			i = j
			-- Comment: --
		elseif c == '-' and line:sub(i, i + 1) == '--' then
			table.insert(parts, wrapColor(escapeRich(line:sub(i)), SYN_COLORS.comment))
			break
			-- Number
		elseif c:match("%d") or (c == '.' and i + 1 <= len and line:sub(i + 1, i + 1):match("%d")) then
			local j = i
			if line:sub(i, i + 1) == '0x' or line:sub(i, i + 1) == '0X' then
				j = i + 2
				while j <= len and line:sub(j, j):match("[%da-fA-F_]") do j += 1 end
			else
				while j <= len and line:sub(j, j):match("[%d_]") do j += 1 end
				if j <= len and line:sub(j, j) == '.' then
					j += 1
					while j <= len and line:sub(j, j):match("[%d_]") do j += 1 end
				end
				if j <= len and line:sub(j, j):match("[eE]") then
					j += 1
					if j <= len and line:sub(j, j):match("[%+%-]") then j += 1 end
					while j <= len and line:sub(j, j):match("[%d_]") do j += 1 end
				end
			end
			table.insert(parts, wrapColor(escapeRich(line:sub(i, j - 1)), SYN_COLORS.number))
			i = j
			-- Identifier or keyword
		elseif c:match("[%a_]") then
			local j = i + 1
			while j <= len and line:sub(j, j):match("[%w_]") do j += 1 end
			local word = line:sub(i, j - 1)
			local escaped = escapeRich(word)
			if word == "self" then
				table.insert(parts, wrapColor(escaped, SYN_COLORS.self_kw))
			elseif LUAU_KEYWORDS[word] then
				table.insert(parts, wrapColor(escaped, SYN_COLORS.keyword))
			elseif LUAU_BUILTINS[word] then
				table.insert(parts, wrapColor(escaped, SYN_COLORS.builtin))
			elseif word:sub(1, 1):match("%u") then
				table.insert(parts, wrapColor(escaped, SYN_COLORS.type_kw))
			else
				table.insert(parts, escaped)
			end
			i = j
			-- Operators
		elseif c:match("[%(%)%{%}%[%]%.%,:;=#%+%-%*/%%^~<>|&!?@]") then
			table.insert(parts, wrapColor(escapeRich(c), SYN_COLORS.operator))
			i += 1
			-- Whitespace and other
		else
			table.insert(parts, escapeRich(c))
			i += 1
		end
	end

	return table.concat(parts)
end

--==============================--
--       DIFF VIEWER            --
--==============================--

export type DiffViewerHandle = {
	frame: Frame,
	showDiff: (path: string, diffResult: DiffResult) -> (),
	showFileDiffs: (diffs: { { path: string, status: string, diff: DiffResult } }) -> (),
	clear: () -> (),
}

function Components.createDiffViewer(parent: GuiObject, config: {
	size: UDim2?,
	layoutOrder: number?,
	}?): DiffViewerHandle
	local c = config or {}
	local LINE_HEIGHT = 18
	local GUTTER_W = 4
	local LINENUM_W = 40
	local SIDEBAR_W = 180
	local MINIMAP_W = 22

	local currentDiffs: { { path: string, status: string, diff: DiffResult } } = {}
	local selectedIndex: number = 0

	-- Root frame
	local frame = Instance.new("Frame")
	frame.Name = "DiffViewer"
	frame.Size = c.size or UDim2.fromScale(1, 1)
	frame.LayoutOrder = c.layoutOrder or 0
	frame.BackgroundColor3 = Theme.Color.InputBg
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = parent

	-- File sidebar
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
	sidebar.BackgroundColor3 = Theme.Color.Background
	sidebar.BorderSizePixel = 0
	sidebar.Parent = frame

	local sidebarBorder = Instance.new("Frame")
	sidebarBorder.Size = UDim2.new(0, 1, 1, 0)
	sidebarBorder.Position = UDim2.new(1, -1, 0, 0)
	sidebarBorder.BackgroundColor3 = Theme.Color.Border
	sidebarBorder.BorderSizePixel = 0
	sidebarBorder.Parent = sidebar

	local sidebarHeader = Instance.new("Frame")
	sidebarHeader.Size = UDim2.new(1, 0, 0, 28)
	sidebarHeader.BackgroundColor3 = Theme.Color.Surface
	sidebarHeader.BorderSizePixel = 0
	sidebarHeader.Parent = sidebar

	local sidebarTitle = Instance.new("TextLabel")
	sidebarTitle.Size = UDim2.new(1, -8, 1, 0)
	sidebarTitle.Position = UDim2.fromOffset(8, 0)
	sidebarTitle.BackgroundTransparency = 1
	sidebarTitle.Text = "Changed Files"
	sidebarTitle.TextColor3 = Theme.Color.TextMuted
	sidebarTitle.Font = Theme.Font.Bold
	sidebarTitle.TextSize = Theme.Size.TextSmall
	sidebarTitle.TextXAlignment = Enum.TextXAlignment.Left
	sidebarTitle.Parent = sidebarHeader

	local sidebarScroll = Instance.new("ScrollingFrame")
	sidebarScroll.Size = UDim2.new(1, 0, 1, -28)
	sidebarScroll.Position = UDim2.fromOffset(0, 28)
	sidebarScroll.BackgroundTransparency = 1
	sidebarScroll.BorderSizePixel = 0
	sidebarScroll.ScrollBarThickness = 3
	sidebarScroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
	sidebarScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sidebarScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	sidebarScroll.Parent = sidebar

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sidebarLayout.Parent = sidebarScroll

	-- Content area (right of sidebar)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -SIDEBAR_W, 1, 0)
	content.Position = UDim2.fromOffset(SIDEBAR_W, 0)
	content.BackgroundColor3 = Theme.Color.InputBg
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.Parent = frame

	-- Nav bar at top of content
	local navBar = Instance.new("Frame")
	navBar.Size = UDim2.new(1, 0, 0, 28)
	navBar.BackgroundColor3 = Theme.Color.Surface
	navBar.BorderSizePixel = 0
	navBar.Parent = content

	local navPath = Instance.new("TextLabel")
	navPath.Size = UDim2.new(1, -120, 1, 0)
	navPath.Position = UDim2.fromOffset(8, 0)
	navPath.BackgroundTransparency = 1
	navPath.Text = "Select a file"
	navPath.TextColor3 = Theme.Color.TextMuted
	navPath.Font = Theme.Font.Mono
	navPath.TextSize = Theme.Size.TextSmall
	navPath.TextXAlignment = Enum.TextXAlignment.Left
	navPath.TextTruncate = Enum.TextTruncate.AtEnd
	navPath.Parent = navBar

	local navStats = Instance.new("TextLabel")
	navStats.Size = UDim2.fromOffset(110, 28)
	navStats.Position = UDim2.new(1, -115, 0, 0)
	navStats.BackgroundTransparency = 1
	navStats.TextColor3 = Theme.Color.TextDim
	navStats.Font = Theme.Font.Mono
	navStats.TextSize = 10
	navStats.TextXAlignment = Enum.TextXAlignment.Right
	navStats.Text = ""
	navStats.Parent = navBar

	-- Diff scroll (code area)
	local diffScroll = Instance.new("ScrollingFrame")
	diffScroll.Size = UDim2.new(1, -MINIMAP_W, 1, -28)
	diffScroll.Position = UDim2.fromOffset(0, 28)
	diffScroll.BackgroundTransparency = 1
	diffScroll.BorderSizePixel = 0
	diffScroll.ScrollBarThickness = 6
	diffScroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
	diffScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	diffScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	diffScroll.Parent = content

	local diffLayout = Instance.new("UIListLayout")
	diffLayout.SortOrder = Enum.SortOrder.LayoutOrder
	diffLayout.Parent = diffScroll

	-- Minimap
	local minimap = Instance.new("Frame")
	minimap.Name = "Minimap"
	minimap.Size = UDim2.new(0, MINIMAP_W, 1, -28)
	minimap.Position = UDim2.new(1, -MINIMAP_W, 0, 28)
	minimap.BackgroundColor3 = Theme.Color.Background
	minimap.BorderSizePixel = 0
	minimap.Parent = content

	local minimapBorder = Instance.new("Frame")
	minimapBorder.Size = UDim2.new(0, 1, 1, 0)
	minimapBorder.BackgroundColor3 = Theme.Color.Border
	minimapBorder.BorderSizePixel = 0
	minimapBorder.Parent = minimap

	local minimapCanvas = Instance.new("Frame")
	minimapCanvas.Name = "Canvas"
	minimapCanvas.Size = UDim2.new(1, -3, 1, -4)
	minimapCanvas.Position = UDim2.fromOffset(3, 2)
	minimapCanvas.BackgroundTransparency = 1
	minimapCanvas.Parent = minimap

	-- Helpers
	local function clearChildren(container: GuiObject)
		for _, child in container:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
		end
	end

	local function buildMinimap(hunks: { DiffEngineModule.DiffLine })
		clearChildren(minimapCanvas)
		if #hunks == 0 then return end

		local mapHeight = minimapCanvas.AbsoluteSize.Y
		if mapHeight < 10 then mapHeight = 300 end

		local totalLines = #hunks
		local markerH = math.max(2, math.floor(mapHeight / math.max(totalLines, 1)))

		for i, line in hunks do
			if line.tag == "add" or line.tag == "remove" then
				local marker = Instance.new("TextButton")
				marker.Size = UDim2.new(1, 0, 0, markerH)
				marker.Position = UDim2.new(0, 0, (i - 1) / totalLines, 0)
				marker.BackgroundColor3 = if line.tag == "add" then Theme.Color.DiffAddText else Theme.Color.DiffRemoveText
				marker.BackgroundTransparency = 0.4
				marker.BorderSizePixel = 0
				marker.Text = ""
				marker.AutoButtonColor = false
				marker.Parent = minimapCanvas

				local lineIndex = i
				marker.MouseButton1Click:Connect(function()
					local scrollPos = (lineIndex - 1) * LINE_HEIGHT
					diffScroll.CanvasPosition = Vector2.new(0, math.max(0, scrollPos - 50))
				end)
			end
		end
	end

	local function renderDiffLines(hunks: { DiffEngineModule.DiffLine })
		clearChildren(diffScroll)

		for i, line in hunks do
			local row = Instance.new("Frame")
			row.Name = `Line_{i}`
			row.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.ClipsDescendants = true
			row.Parent = diffScroll

			-- Background color
			if line.tag == "add" then
				row.BackgroundColor3 = Theme.Color.DiffAdd
			elseif line.tag == "remove" then
				row.BackgroundColor3 = Theme.Color.DiffRemove
			elseif line.tag == "hunk" then
				row.BackgroundColor3 = Theme.Color.DiffHunkBg
			else
				row.BackgroundTransparency = 1
			end

			-- Gutter bar
			local gutter = Instance.new("Frame")
			gutter.Size = UDim2.new(0, GUTTER_W, 1, 0)
			gutter.BorderSizePixel = 0
			gutter.Parent = row
			if line.tag == "add" then
				gutter.BackgroundColor3 = Theme.Color.DiffAddText
			elseif line.tag == "remove" then
				gutter.BackgroundColor3 = Theme.Color.DiffRemoveText
			elseif line.tag == "hunk" then
				gutter.BackgroundColor3 = Theme.Color.DiffHunkText
			else
				gutter.BackgroundTransparency = 1
			end

			-- Line numbers
			local lineNum = Instance.new("TextLabel")
			lineNum.Size = UDim2.new(0, LINENUM_W, 1, 0)
			lineNum.Position = UDim2.fromOffset(GUTTER_W, 0)
			lineNum.BackgroundTransparency = 1
			lineNum.Font = Theme.Font.Mono
			lineNum.TextSize = 10
			lineNum.TextXAlignment = Enum.TextXAlignment.Right
			lineNum.TextColor3 = Theme.Color.TextDim
			lineNum.Parent = row

			if line.tag == "hunk" then
				lineNum.Text = "..."
			elseif line.tag == "remove" then
				lineNum.Text = if line.oldLine then tostring(line.oldLine) else ""
			elseif line.tag == "add" then
				lineNum.Text = if line.newLine then tostring(line.newLine) else ""
			else
				-- Show both line numbers for context
				local nums = {}
				if line.oldLine then table.insert(nums, tostring(line.oldLine)) end
				lineNum.Text = if line.oldLine then tostring(line.oldLine) else ""
			end

			-- Prefix (+/-/space)
			local prefix = Instance.new("TextLabel")
			prefix.Size = UDim2.new(0, 12, 1, 0)
			prefix.Position = UDim2.fromOffset(GUTTER_W + LINENUM_W + 2, 0)
			prefix.BackgroundTransparency = 1
			prefix.Font = Theme.Font.Mono
			prefix.TextSize = 11
			prefix.Parent = row

			if line.tag == "add" then
				prefix.Text = "+"
				prefix.TextColor3 = Theme.Color.DiffAddText
			elseif line.tag == "remove" then
				prefix.Text = "-"
				prefix.TextColor3 = Theme.Color.DiffRemoveText
			elseif line.tag == "hunk" then
				prefix.Text = ""
				prefix.TextColor3 = Theme.Color.DiffHunkText
			else
				prefix.Text = " "
				prefix.TextColor3 = Theme.Color.TextDim
			end

			-- Code text with syntax highlighting
			local codeLabel = Instance.new("TextLabel")
			codeLabel.Size = UDim2.new(1, -(GUTTER_W + LINENUM_W + 18), 1, 0)
			codeLabel.Position = UDim2.fromOffset(GUTTER_W + LINENUM_W + 16, 0)
			codeLabel.BackgroundTransparency = 1
			codeLabel.Font = Theme.Font.Mono
			codeLabel.TextSize = 11
			codeLabel.TextXAlignment = Enum.TextXAlignment.Left
			codeLabel.RichText = true
			codeLabel.Parent = row

			if line.tag == "hunk" then
				codeLabel.Text = escapeRich(line.text)
				codeLabel.TextColor3 = Theme.Color.DiffHunkText
				codeLabel.RichText = false
			elseif line.tag == "add" then
				codeLabel.TextColor3 = Theme.Color.DiffAddText
				codeLabel.Text = highlightLuau(line.text)
			elseif line.tag == "remove" then
				codeLabel.TextColor3 = Theme.Color.DiffRemoveText
				codeLabel.Text = highlightLuau(line.text)
			else
				codeLabel.TextColor3 = Theme.Color.Text
				codeLabel.Text = highlightLuau(line.text)
			end
		end
	end

	local function showFileAtIndex(index: number)
		if index < 1 or index > #currentDiffs then return end
		selectedIndex = index
		local fileDiff = currentDiffs[index]

		navPath.Text = fileDiff.path
		navPath.TextColor3 = Theme.fileColor(fileDiff.path)

		local parts: { string } = {}
		if fileDiff.diff.additions > 0 then table.insert(parts, `+{fileDiff.diff.additions}`) end
		if fileDiff.diff.deletions > 0 then table.insert(parts, `-{fileDiff.diff.deletions}`) end
		navStats.Text = `{table.concat(parts, " ")} [{fileDiff.status:upper()}]`

		local statusColors: { [string]: Color3 } = { added = Theme.Color.Green, deleted = Theme.Color.Red, modified = Theme.Color.Yellow }
		navStats.TextColor3 = statusColors[fileDiff.status] or Theme.Color.TextDim

		local hunks = DiffEngineModule.unifiedHunks(fileDiff.diff)
		renderDiffLines(hunks)
		task.defer(function() buildMinimap(hunks) end)

		-- Update sidebar selection highlighting
		for _, child in sidebarScroll:GetChildren() do
			if child:IsA("TextButton") then
				local isSelected = child.LayoutOrder == index
				child.BackgroundColor3 = if isSelected then Theme.Color.SurfaceHover else Theme.Color.Background
				child.BackgroundTransparency = if isSelected then 0 else 1
			end
		end
	end

	local function buildSidebar(diffs: { { path: string, status: string, diff: DiffResult } })
		clearChildren(sidebarScroll)
		sidebarTitle.Text = `Changed Files ({#diffs})`

		local statusIcons: { [string]: string } = { added = "[A]", modified = "[M]", deleted = "[D]" }
		local statusColors: { [string]: Color3 } = { added = Theme.Color.Green, deleted = Theme.Color.Red, modified = Theme.Color.Yellow }

		for i, fileDiff in diffs do
			local btn = Instance.new("TextButton")
			btn.Name = `File_{i}`
			btn.Size = UDim2.new(1, 0, 0, 24)
			btn.BackgroundTransparency = 1
			btn.BorderSizePixel = 0
			btn.Text = ""
			btn.AutoButtonColor = false
			btn.LayoutOrder = i
			btn.Parent = sidebarScroll

			btn.MouseEnter:Connect(function()
				if selectedIndex ~= i then btn.BackgroundTransparency = 0.6; btn.BackgroundColor3 = Theme.Color.SurfaceHover end
			end)
			btn.MouseLeave:Connect(function()
				if selectedIndex ~= i then btn.BackgroundTransparency = 1 end
			end)

			-- Status indicator
			local status = Instance.new("TextLabel")
			status.Size = UDim2.fromOffset(24, 24)
			status.Position = UDim2.fromOffset(4, 0)
			status.BackgroundTransparency = 1
			status.Text = statusIcons[fileDiff.status] or "?"
			status.TextColor3 = statusColors[fileDiff.status] or Theme.Color.TextMuted
			status.Font = Theme.Font.Mono
			status.TextSize = 9
			status.Parent = btn

			-- File name (just the filename, not full path)
			local parts = fileDiff.path:split("/")
			local fileName = parts[#parts] or fileDiff.path

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -32, 1, 0)
			nameLabel.Position = UDim2.fromOffset(28, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = fileName
			nameLabel.TextColor3 = Theme.fileColor(fileDiff.path)
			nameLabel.Font = Theme.Font.Mono
			nameLabel.TextSize = 10
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = btn

			local idx = i
			btn.MouseButton1Click:Connect(function()
				showFileAtIndex(idx)
			end)
		end
	end

	return {
		frame = frame,
		showDiff = function(path: string, diffResult: DiffResult)
			currentDiffs = { { path = path, status = "modified", diff = diffResult } }
			buildSidebar(currentDiffs)
			showFileAtIndex(1)
		end,
		showFileDiffs = function(diffs: { { path: string, status: string, diff: DiffResult } })
			currentDiffs = diffs
			buildSidebar(diffs)
			if #diffs > 0 then
				showFileAtIndex(1)
			else
				clearChildren(diffScroll)
				clearChildren(minimapCanvas)
				navPath.Text = "No changes"
				navStats.Text = ""
			end
		end,
		clear = function()
			currentDiffs = {}
			selectedIndex = 0
			clearChildren(sidebarScroll)
			clearChildren(diffScroll)
			clearChildren(minimapCanvas)
			sidebarTitle.Text = "Changed Files"
			navPath.Text = "Select a file"
			navStats.Text = ""
		end,
	}
end

--==============================--
--        UTILITIES             --
--==============================--

function Components.createDivider(parent: GuiObject, layoutOrder: number?): Frame
	local div = Instance.new("Frame")
	div.Name = "Divider"
	div.Size = UDim2.new(1, 0, 0, 1)
	div.BackgroundColor3 = Theme.Color.Border
	div.BorderSizePixel = 0
	div.LayoutOrder = layoutOrder or 0
	div.Parent = parent
	return div
end

function Components.createLabel(parent: GuiObject, text: string, config: {
	color: Color3?,
	font: Enum.Font?,
	textSize: number?,
	layoutOrder: number?,
	alignment: Enum.TextXAlignment?,
	}?): TextLabel
	local cfg = config or {}
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = cfg.color or Theme.Color.Text
	label.Font = cfg.font or Theme.Font.Regular
	label.TextSize = cfg.textSize or Theme.Size.TextNormal
	label.TextXAlignment = cfg.alignment or Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.LayoutOrder = cfg.layoutOrder or 0
	label.Parent = parent
	return label
end

function Components.createScrollFrame(parent: GuiObject, config: {
	size: UDim2?,
	layoutOrder: number?,
	}?): ScrollingFrame
	local cfg = config or {}
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = cfg.size or UDim2.fromScale(1, 1)
	scroll.LayoutOrder = cfg.layoutOrder or 0
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.Color.SurfaceActive
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent
	return scroll
end

function Components.createProgressBar(parent: GuiObject, config: { layoutOrder: number? }?): (Frame, (progress: number) -> ())
	local cfg = config or {}
	local container = Instance.new("Frame")
	container.Name = "ProgressBar"
	container.Size = UDim2.new(1, 0, 0, 4)
	container.BackgroundColor3 = Theme.Color.Surface
	container.BorderSizePixel = 0
	container.LayoutOrder = cfg.layoutOrder or 0
	container.Visible = false
	container.Parent = parent
	Instance.new("UICorner", container).CornerRadius = UDim.new(0, 2)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Theme.Color.Accent
	fill.BorderSizePixel = 0
	fill.Parent = container
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)

	return container, function(p: number)
		fill.Size = UDim2.new(math.clamp(p, 0, 1), 0, 1, 0)
		container.Visible = p > 0 and p < 1
	end
end

--==============================--
--      CONFIRM DIALOG          --
--==============================--

function Components.showConfirmDialog(parentWidget: DockWidgetPluginGui, config: {
	title: string,
	message: string,
	confirmText: string?,
	cancelText: string?,
	onConfirm: () -> (),
	onCancel: (() -> ())?,
	})
	-- Overlay covers entire widget
	local overlay = Instance.new("Frame")
	overlay.Name = "ConfirmDialog"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.ZIndex = 200
	overlay.Parent = parentWidget

	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(260, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = Theme.Color.Surface
	card.BorderSizePixel = 0
	card.ZIndex = 201
	card.Parent = overlay

	Instance.new("UICorner", card).CornerRadius = Theme.Corner

	local cardLayout = Instance.new("UIListLayout")
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Padding = UDim.new(0, Theme.Size.SpacingM)
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.Parent = card

	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingTop = UDim.new(0, Theme.Size.SpacingXL)
	cardPad.PaddingBottom = UDim.new(0, Theme.Size.SpacingXL)
	cardPad.PaddingLeft = UDim.new(0, Theme.Size.SpacingXL)
	cardPad.PaddingRight = UDim.new(0, Theme.Size.SpacingXL)
	cardPad.Parent = card

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0, 0)
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = config.title
	titleLabel.TextColor3 = Theme.Color.Text
	titleLabel.Font = Theme.Font.Bold
	titleLabel.TextSize = Theme.Size.TextNormal
	titleLabel.TextWrapped = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.LayoutOrder = 0
	titleLabel.ZIndex = 202
	titleLabel.Parent = card

	local msgLabel = Instance.new("TextLabel")
	msgLabel.Size = UDim2.new(1, 0, 0, 0)
	msgLabel.AutomaticSize = Enum.AutomaticSize.Y
	msgLabel.BackgroundTransparency = 1
	msgLabel.Text = config.message
	msgLabel.TextColor3 = Theme.Color.TextMuted
	msgLabel.Font = Theme.Font.Regular
	msgLabel.TextSize = Theme.Size.TextSmall
	msgLabel.TextWrapped = true
	msgLabel.TextXAlignment = Enum.TextXAlignment.Center
	msgLabel.LayoutOrder = 1
	msgLabel.ZIndex = 202
	msgLabel.Parent = card

	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, 0, 0, 32)
	btnRow.BackgroundTransparency = 1
	btnRow.LayoutOrder = 2
	btnRow.ZIndex = 202
	btnRow.Parent = card

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.Padding = UDim.new(0, Theme.Size.SpacingM)
	btnLayout.Parent = btnRow

	local function dismiss()
		overlay:Destroy()
	end

	local cancelBtn = Components.createButton(btnRow, {
		text = config.cancelText or "Cancel", size = UDim2.fromOffset(90, 28), layoutOrder = 0,
		color = Theme.Color.SurfaceActive, textColor = Theme.Color.TextMuted,
		onClick = function()
			dismiss()
			if config.onCancel then config.onCancel() end
		end,
	})
	cancelBtn.ZIndex = 203

	local confirmBtn = Components.createButton(btnRow, {
		text = config.confirmText or "Confirm", size = UDim2.fromOffset(90, 28), layoutOrder = 1,
		color = Theme.Color.Accent, textColor = Theme.Color.Background,
		onClick = function()
			dismiss()
			config.onConfirm()
		end,
	})
	confirmBtn.ZIndex = 203
end

return Components