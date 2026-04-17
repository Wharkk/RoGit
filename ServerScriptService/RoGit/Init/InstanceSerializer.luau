local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Types = require(script.Parent.Types)
local DataTypes = require(script.Parent.DataTypes)
local PropertyMap = require(script.Parent.PropertyMap)

type TreeEntry = Types.TreeEntry
type SerializedInstance = Types.SerializedInstance
type ScriptMeta = Types.ScriptMeta

local SCRIPT_CLASSES: { [string]: boolean } = { Script = true, LocalScript = true, ModuleScript = true }

local SCRIPT_EXT: { [string]: string } = {
	Script = ".server.luau",
	LocalScript = ".client.luau",
	ModuleScript = ".luau",
}

local JSON_EXT = ".json"
local META_EXT = ".meta.json"
local INIT = "_init"

local IGNORED_CLASSES: { [string]: boolean } = {
	Camera = true,
	Terrain = true,
}

local UNCREATABLE_CLASSES: { [string]: boolean } = {
	Player = true,
	Workspace = true,
	StarterGui = true,
	StarterPack = true,
	StarterPlayer = true,
	ReplicatedStorage = true,
	ServerScriptService = true,
	ServerStorage = true,
	Lighting = true,
	SoundService = true,
	Teams = true,
	Chat = true,
	TestService = true,
	TouchInputService = true,
	VRService = true,
}

local DEFAULT_SERVICES: { string } = {
	"ServerScriptService", "ReplicatedStorage", "StarterGui",
	"StarterPlayer", "ServerStorage", "StarterPack",
	"Workspace", "Lighting", "SoundService",
}


local RESERVED_NAMES: { [string]: boolean } = {}
for _, n in { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" } do
	RESERVED_NAMES[n] = true
end

--==============================--
--     PATH SANITIZATION        --
--==============================--


local function sanitizeName(name: string): string
	if name == "" then return "_unnamed" end
	local safe = name:gsub("[/\:*?\"<>|]", "_")
	if safe == ".." or safe == "." then safe = "_" .. safe end
	safe = safe:gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")
	if RESERVED_NAMES[safe:upper()] then safe = "_" .. safe end
	if safe == "" then safe = "_unnamed" end
	return safe
end


local function disambiguate(baseName: string, seen: { [string]: number }): (string, boolean)
	local count = (seen[baseName] or 0) + 1
	seen[baseName] = count
	if count == 1 then
		return baseName, false
	end
	return baseName .. "__" .. count, true
end

-- Strip disambiguation suffix from filename to recover instance name
local function stripDisambiguation(name: string): string
	return name:gsub("__%d+$", "")
end

-- Find the first child named `name` (and optionally matching `className`)
-- that hasn't been claimed by a previous file in this apply pass. Class-aware
-- matching keeps mixed-class same-name siblings correctly assigned.
local function findUnclaimed(parent: Instance, name: string, claimed: { [Instance]: boolean }, className: string?): Instance?
	for _, child in parent:GetChildren() do
		if child.Name == name and not claimed[child] then
			if className == nil or child.ClassName == className then
				return child
			end
		end
	end
	return nil
end

--==============================--
--      GITIGNORE SUPPORT       --
--==============================--

local function loadGitignore(service: Instance): { [string]: boolean }
	local ignored: { [string]: boolean } = {}
	local ignoreScript = service:FindFirstChild(".gitignore") or service:FindFirstChild("_gitignore")
	if not ignoreScript or not SCRIPT_CLASSES[ignoreScript.ClassName] then
		return ignored
	end

	local ok, patterns = pcall(function()
		return require(ignoreScript :: ModuleScript)
	end)

	if not ok or type(patterns) ~= "table" then return ignored end

	for _, pattern in patterns do
		if type(pattern) == "string" then
			ignored[pattern] = true
		end
	end

	return ignored
end

local function isIgnored(name: string, ignoreList: { [string]: boolean }): boolean
	if name == ".gitignore" or name == "_gitignore" then return true end
	return ignoreList[name] == true
end

--==============================--
--      README SUPPORT          --
--==============================--

local InstanceSerializer = {}
InstanceSerializer.__index = InstanceSerializer

export type InstanceSerializer = typeof(setmetatable({} :: {
	services: { string },
	_nodeCount: number,
}, InstanceSerializer))

function InstanceSerializer.new(services: { string }?): InstanceSerializer
	local self = setmetatable({}, InstanceSerializer)
	self.services = services or DEFAULT_SERVICES
	self._nodeCount = 0
	return self
end

-- Yield periodically to prevent freezing Studio
function InstanceSerializer._throttle(self: InstanceSerializer)
	self._nodeCount += 1
	if self._nodeCount % 200 == 0 then
		task.wait()
	end
end

function InstanceSerializer.getReadmeEntry(_self: InstanceSerializer): TreeEntry?
	local ss = game:FindService("ServerStorage")
	if not ss then return nil end

	local readmeModule = ss:FindFirstChild("README")
	if not readmeModule or readmeModule.ClassName ~= "ModuleScript" then return nil end

	local ok, data = pcall(function()
		return require(readmeModule :: ModuleScript)
	end)

	if not ok or type(data) ~= "table" then return nil end

	local content: string? = nil
	for _, v in data do
		if type(v) == "string" then content = v; break end
	end

	if not content then return nil end
	return { path = "README.md", mode = "100644", type = "blob", content = content }
end

function InstanceSerializer.applyReadme(_self: InstanceSerializer, content: string)
	local ss = game:FindService("ServerStorage")
	if not ss then return end

	local readmeModule = ss:FindFirstChild("README")
	if not readmeModule then
		readmeModule = Instance.new("ModuleScript")
		readmeModule.Name = "README"
		readmeModule.Parent = ss
	end

	if readmeModule:IsA("ModuleScript") then
		local escaped = content:gsub("]]", "] ]")
		readmeModule.Source = `local README = \{\n[[\n{escaped}\n]]\n\}\n\nreturn README`
	end
end

--==============================--
--    METADATA HELPERS          --
--==============================--

local function hasMetadata(inst: Instance): boolean
	if next(inst:GetAttributes()) ~= nil then return true end
	if #inst:GetTags() > 0 then return true end

	if SCRIPT_CLASSES[inst.ClassName] then
		if inst.ClassName ~= "ModuleScript" then
			local ok, enabled = pcall(function() return (inst :: any).Enabled end)
			if ok and enabled == false then return true end
			local ok2, rc = pcall(function() return (inst :: any).RunContext end)
			if ok2 and rc ~= Enum.RunContext.Legacy then return true end
		end
	end
	return false
end


local function serializeScriptMeta(inst: Instance, realName: string?): string?
	local attrs = inst:GetAttributes()
	local tags = inst:GetTags()

	local encAttrs: { [string]: any } = {}
	local hasAttrs = false
	for k, v in attrs do
		local enc = DataTypes.encode(v)
		if enc ~= nil then
			encAttrs[k] = enc
			hasAttrs = true
		else
			warn(`[RoGit] Attribute "{k}" on {inst:GetFullName()} has unencodable type, skipped`)
		end
	end


	local enabled: boolean? = nil
	local runContext: string? = nil
	if inst.ClassName ~= "ModuleScript" then
		local ok1, e = pcall(function() return (inst :: any).Enabled end)
		if ok1 and e == false then enabled = false end
		local ok2, rc = pcall(function() return (inst :: any).RunContext end)
		if ok2 and rc ~= Enum.RunContext.Legacy then runContext = rc.Name end
	end

	local hasMeta = hasAttrs or #tags > 0 or enabled ~= nil or runContext ~= nil or realName ~= nil
	if not hasMeta then return nil end

	local meta: ScriptMeta = {
		attributes = if hasAttrs then encAttrs else nil,
		tags = if #tags > 0 then tags else nil,
		enabled = enabled,
		runContext = runContext,
		name = realName,
	}

	local ok, json = pcall(function() return HttpService:JSONEncode(meta) end)
	return if ok then json else nil
end

local function applyScriptMeta(inst: Instance, meta: ScriptMeta)
	if meta.attributes then
		for k, v in meta.attributes do
			local dec = DataTypes.decode(v)
			if dec ~= nil then pcall(function() inst:SetAttribute(k, dec) end) end
		end
	end

	if meta.tags then
		for _, existingTag in inst:GetTags() do inst:RemoveTag(existingTag) end
		for _, tag in meta.tags do inst:AddTag(tag) end
	end


	if meta.enabled ~= nil and inst.ClassName ~= "ModuleScript" then
		pcall(function() (inst :: any).Enabled = meta.enabled end)
	end
	if meta.runContext and inst.ClassName ~= "ModuleScript" then
		pcall(function()
			(inst :: any).RunContext = (Enum.RunContext :: any)[meta.runContext]
		end)
	end
end

--==============================--
--   SERIALIZE TO FILES         --
--==============================--

function InstanceSerializer.serializeToFiles(self: InstanceSerializer): { TreeEntry }
	local entries: { TreeEntry } = {}
	self._nodeCount = 0

	local readmeEntry = self:getReadmeEntry()
	if readmeEntry then table.insert(entries, readmeEntry) end

	for _, svc in self.services do
		local service = game:FindService(svc)
		if service then
			local ignoreList = loadGitignore(service)
			self:_walk(service, svc, entries, ignoreList)
		end
	end
	return entries
end

function InstanceSerializer.getFileContentsMap(self: InstanceSerializer): { [string]: string }
	local map: { [string]: string } = {}
	self._nodeCount = 0

	local readmeEntry = self:getReadmeEntry()
	if readmeEntry and readmeEntry.content then map["README.md"] = readmeEntry.content end

	for _, svc in self.services do
		local service = game:FindService(svc)
		if service then
			local ignoreList = loadGitignore(service)
			self:_collectContents(service, svc, map, ignoreList)
		end
	end
	return map
end

function InstanceSerializer.getFileList(self: InstanceSerializer): { string }
	local paths: { string } = {}
	self._nodeCount = 0

	if self:getReadmeEntry() then table.insert(paths, "README.md") end

	for _, svc in self.services do
		local service = game:FindService(svc)
		if service then
			local ignoreList = loadGitignore(service)
			self:_collectPaths(service, svc, paths, ignoreList)
		end
	end
	return paths
end

-- Convert a Studio Instance to its git file path
function InstanceSerializer.getInstanceFilePath(_self: InstanceSerializer, inst: Instance): string?
	local segments: { string } = {}
	local current = inst
	local service: Instance? = nil

	while current do
		if current.Parent == game then service = current; break end
		table.insert(segments, 1, sanitizeName(current.Name))
		current = current.Parent :: Instance
	end

	if not service then return nil end
	table.insert(segments, 1, service.Name)

	if SCRIPT_CLASSES[inst.ClassName] then
		local ext = SCRIPT_EXT[inst.ClassName]
		local visibleChildren: { Instance } = {}
		for _, child in inst:GetChildren() do
			if not IGNORED_CLASSES[child.ClassName] then table.insert(visibleChildren, child) end
		end
		if #visibleChildren > 0 then
			return table.concat(segments, "/") .. "/" .. INIT .. ext
		else
			return table.concat(segments, "/") .. ext
		end
	else
		local visibleChildren: { Instance } = {}
		for _, child in inst:GetChildren() do
			if not IGNORED_CLASSES[child.ClassName] then table.insert(visibleChildren, child) end
		end
		if #visibleChildren > 0 then
			return table.concat(segments, "/") .. "/" .. INIT .. JSON_EXT
		else
			return table.concat(segments, "/") .. JSON_EXT
		end
	end
end

--==============================--
--       INTERNAL WALK          --
--==============================--

function InstanceSerializer._walk(self: InstanceSerializer, inst: Instance, path: string, entries: { TreeEntry }, ignoreList: { [string]: boolean })
	local ok, children = pcall(function() return inst:GetChildren() end)
	if not ok then return end


	local seen: { [string]: number } = {}

	for _, child in children do
		if IGNORED_CLASSES[child.ClassName] then continue end
		if isIgnored(child.Name, ignoreList) then continue end
		self:_throttle()

		local walkOk, walkErr = pcall(function()

			local safeName = sanitizeName(child.Name)

			if child.Name == INIT then
				warn(`[RoGit] Instance named "{INIT}" in {path} collides with folder sentinel. Prefixing with underscore.`)
				safeName = "_" .. safeName
			end

			local disambiguated, wasRenamed = disambiguate(safeName, seen)
			local childPath = path .. "/" .. disambiguated

			local realName: string? = if wasRenamed or safeName ~= child.Name then child.Name else nil

			local visibleChildren: { Instance } = {}
			for _, gc in child:GetChildren() do
				if not IGNORED_CLASSES[gc.ClassName] then table.insert(visibleChildren, gc) end
			end
			local hasKids = #visibleChildren > 0

			if SCRIPT_CLASSES[child.ClassName] then
				local ext = SCRIPT_EXT[child.ClassName]
				local filePath = if hasKids then childPath .. "/" .. INIT .. ext else childPath .. ext
				table.insert(entries, { path = filePath, mode = "100644", type = "blob", content = (child :: any).Source })


				local metaJson = serializeScriptMeta(child, realName)
				if metaJson then
					local metaPath = if hasKids then childPath .. "/" .. INIT .. META_EXT else childPath .. META_EXT
					table.insert(entries, { path = metaPath, mode = "100644", type = "blob", content = metaJson })
				end
			else
				local json = self:_serializeProps(child, realName)
				if json then
					local filePath = if hasKids then childPath .. "/" .. INIT .. JSON_EXT else childPath .. JSON_EXT
					table.insert(entries, { path = filePath, mode = "100644", type = "blob", content = json })
				end
			end

			if hasKids then self:_walk(child, childPath, entries, ignoreList) end
		end)

		if not walkOk then
			warn(`[RoGit] Error serializing {path}/{child.Name}: {walkErr}`)
		end
	end
end

function InstanceSerializer._serializeProps(_self: InstanceSerializer, inst: Instance, realName: string?): string?
	local propNames = PropertyMap.getProperties(inst.ClassName)
	local props: { [string]: any } = {}

	if propNames then
		for _, name in propNames do
			local ok, val = pcall(function() return (inst :: any)[name] end)
			if ok and val ~= nil then
				if PropertyMap.isObjectReference(name) then

					if typeof(val) == "Instance" then
						props[name] = { _t = "Ref", name = val.Name, path = val:GetFullName() }
					end
				else
					local enc = DataTypes.encode(val)
					if enc ~= nil then
						props[name] = enc
					end
				end
			end
		end
	end

	local attrs = inst:GetAttributes()
	local encAttrs: { [string]: any } = {}
	for k, v in attrs do
		local enc = DataTypes.encode(v)
		if enc ~= nil then
			encAttrs[k] = enc
		else
			warn(`[RoGit] Attribute "{k}" on {inst:GetFullName()} has unencodable type, skipped`)
		end
	end

	local tags = inst:GetTags()

	local data: SerializedInstance = {
		className = inst.ClassName,
		properties = props,
		attributes = encAttrs,
		tags = if #tags > 0 then tags else nil,
		name = realName,
	}
	local encOk, json = pcall(function() return HttpService:JSONEncode(data) end)
	return if encOk then json else nil
end

--==============================--
--       APPLY FROM FILES       --
--==============================--

function InstanceSerializer.applyFromFiles(self: InstanceSerializer, fileContents: { [string]: string }): (number, number, number)
	local created, updated, deleted = 0, 0, 0
	local tracked: { [Instance]: boolean } = {}
	-- Track claimed instances so same-name siblings don't collapse onto one FindFirstChild result.
	local claimed: { [Instance]: boolean } = {}

	local pendingRefs: { { inst: Instance, propName: string, targetPath: string } } = {}
	self._nodeCount = 0

	-- Pre-scan _init.json files to build a map of safe-path to real-name.
	-- Used during intermediate path walk so escaped segments resolve to the
	-- folder the user actually had instead of creating a duplicate.
	local intermediateNames: { [string]: string } = {}
	local INIT_JSON_SUFFIX = "/" .. INIT .. JSON_EXT
	for path, content in fileContents do
		if path:sub(-#INIT_JSON_SUFFIX) == INIT_JSON_SUFFIX then
			local folderSafePath = path:sub(1, -#INIT_JSON_SUFFIX - 1)
			local ok, data = pcall(function() return HttpService:JSONDecode(content) end)
			if ok and data and type(data.name) == "string" and data.name ~= "" then
				intermediateNames[folderSafePath] = data.name
			end
		end
	end

	if fileContents["README.md"] then
		self:applyReadme(fileContents["README.md"])
	end


	local regularFiles: { string } = {}
	local metaFiles: { string } = {}
	local packageLinkFiles: { string } = {}

	for path in fileContents do
		if path == "README.md" then
			-- already handled
		elseif path:sub(-#META_EXT) == META_EXT then
			table.insert(metaFiles, path)
		else
			local isPackageLink = false
			if path:sub(-#JSON_EXT) == JSON_EXT then
				local peekOk, peekData = pcall(function()
					return HttpService:JSONDecode(fileContents[path])
				end)
				if peekOk and peekData and peekData.className == "PackageLink" then
					isPackageLink = true
				end
			end

			if isPackageLink then
				table.insert(packageLinkFiles, path)
			else
				table.insert(regularFiles, path)
			end
		end
	end

	-- Sort by depth (shallow first), then alphabetically so same-name siblings
	-- (Foo.json before Foo__2.json) are applied in a deterministic order.
	table.sort(regularFiles, function(a, b)
		local da, db = #a:split("/"), #b:split("/")
		if da ~= db then return da < db end
		return a < b
	end)

	-- Pass 1: Regular files
	for _, path in regularFiles do
		self:_throttle()
		local ok, c, u = pcall(function()
			return self:_applySingleFile(path, fileContents[path], tracked, pendingRefs, claimed, intermediateNames)
		end)
		if ok then
			created += c; updated += u
		else
			warn(`[RoGit] Error applying {path}: {c}`)
		end
	end

	-- Pass 2: Package links
	for _, path in packageLinkFiles do
		self:_throttle()
		local ok, c, u = pcall(function()
			return self:_applySingleFile(path, fileContents[path], tracked, pendingRefs, claimed, intermediateNames)
		end)
		if ok then
			created += c; updated += u
		else
			warn(`[RoGit] Error applying package {path}: {c}`)
		end
	end

	-- Pass 3: Meta sidecars
	for _, metaPath in metaFiles do
		self:_throttle()
		local ok, err = pcall(function() self:_applyMetaFile(metaPath, fileContents[metaPath]) end)
		if not ok then
			warn(`[RoGit] Error applying meta {metaPath}: {err}`)
		end
	end

	-- Pass 4: Resolve deferred object references
	for _, ref in pendingRefs do
		pcall(function()
			local target = self:_resolveInstancePath(ref.targetPath)
			if target then
				(ref.inst :: any)[ref.propName] = target
			end
		end)
	end

	return created, updated, deleted
end


function InstanceSerializer._resolveInstancePath(_self: InstanceSerializer, fullName: string): Instance?
	local parts = fullName:split(".")
	local current: Instance? = game
	for _, part in parts do
		if not current then return nil end
		local child = (current :: Instance):FindFirstChild(part)
		if not child then return nil end
		current = child
	end
	return current :: Instance?
end

function InstanceSerializer._applySingleFile(
	_self: InstanceSerializer, filePath: string, content: string,
	tracked: { [Instance]: boolean }, pendingRefs: { { inst: Instance, propName: string, targetPath: string } },
	claimed: { [Instance]: boolean }, intermediateNames: { [string]: string }
): (number, number)
	local instPath, className = InstanceSerializer._parseFilePath(filePath)
	if not instPath or not className then return 0, 0 end

	local segments = instPath:split("/")
	if #segments < 2 then return 0, 0 end

	local service = game:FindService(segments[1])
	if not service then return 0, 0 end

	local parent: Instance = service
	local accPath: string = segments[1]
	for i = 2, #segments - 1 do
		accPath = accPath .. "/" .. segments[i]
		-- Pre-scanned real name overrides escaped segment so "_init" intermediates
		-- resolve to the actual folder instead of creating a duplicate.
		local lookupName = intermediateNames[accPath] or stripDisambiguation(segments[i])
		local child = parent:FindFirstChild(lookupName)
		if not child then
			local folderOk, folder = pcall(function() return Instance.new("Folder") end)
			if not folderOk or not folder then
				warn(`[RoGit] Cannot create folder for {filePath}`)
				return 0, 0
			end
			folder.Name = lookupName
			folder.Parent = parent
			child = folder
		end
		parent = child
	end


	local instName = stripDisambiguation(segments[#segments])

	if SCRIPT_CLASSES[className] then

		local existing = findUnclaimed(parent, instName, claimed, className)
		if existing then
			local setOk = pcall(function() (existing :: any).Source = content end)
			tracked[existing] = true
			claimed[existing] = true
			if setOk then return 0, 1 end
			return 0, 0
		end
		local nameMatch = findUnclaimed(parent, instName, claimed, nil)
		if nameMatch and nameMatch.ClassName == "Folder" then
			-- Intermediate walk created a Folder placeholder. Replace it with
			-- the correct script class and reparent its children.
			local createOk, s = pcall(function() return Instance.new(className) end)
			if createOk and s then
				s.Name = instName
				pcall(function() (s :: any).Source = content end)
				for _, child in nameMatch:GetChildren() do child.Parent = s end
				s.Parent = parent
				nameMatch:Destroy()
				tracked[s] = true
				claimed[s] = true
				return 1, 0
			end
		elseif nameMatch then
			warn(`[RoGit] Type mismatch: {filePath} is {className} but {nameMatch:GetFullName()} is {nameMatch.ClassName}. Creating new instance instead.`)
		end
		local createOk, s = pcall(function() return Instance.new(className) end)
		if not createOk or not s then
			warn(`[RoGit] Cannot create {className} for {filePath}`)
			return 0, 0
		end
		s.Name = instName
		pcall(function() (s :: any).Source = content end)
		s.Parent = parent
		tracked[s] = true
		claimed[s] = true
		return 1, 0
	end


	local decOk, data = pcall(function() return HttpService:JSONDecode(content) :: SerializedInstance end)
	if not decOk or not data then return 0, 0 end

	-- Use stored name if present (accept empty string -- the sanitizer
	-- may have replaced "" with "_unnamed").
	if type(data.name) == "string" then
		instName = data.name
	end

	-- Class-aware: find same-class same-name unclaimed sibling to prevent
	-- mixed-class siblings from shuffling class assignments across pulls.
	local existing = findUnclaimed(parent, instName, claimed, data.className)

	-- PackageLink special handling
	if data.className == "PackageLink" then
		if existing then
			InstanceSerializer._applyProps(existing, data, pendingRefs)
			tracked[existing] = true
			claimed[existing] = true
			return 0, 1
		end

		local packageUrl = data.properties and data.properties.PackageIdSerialize
		if not packageUrl or packageUrl == "" then
			warn(`[RoGit] PackageLink at {filePath} has no PackageIdSerialize, cannot restore`)
			return 0, 0
		end

		local assetId: string = packageUrl
		if type(packageUrl) == "table" and packageUrl._t == "Content" then
			assetId = packageUrl.uri or packageUrl.value or ""
		end
		if type(assetId) ~= "string" or assetId == "" then
			warn(`[RoGit] PackageLink at {filePath}: could not parse package URL`)
			return 0, 0
		end

		local loadOk, result = pcall(function()
			return InsertService:LoadPackageAsset(assetId)
		end)

		if not loadOk or not result or #result == 0 then
			warn(`[RoGit] Failed to load package {assetId} for {filePath}`)
			return 0, 0
		end

		local packageRoot = result[1]
		if packageRoot then
			local grandParent = parent.Parent
			if grandParent then
				local oldName = parent.Name
				parent:Destroy()
				packageRoot.Name = oldName
				packageRoot.Parent = grandParent
				tracked[packageRoot] = true
				claimed[packageRoot] = true
				local newLink = packageRoot:FindFirstChildWhichIsA("PackageLink")
				if newLink then
					tracked[newLink] = true
					claimed[newLink] = true
				end
				return 1, 0
			end
		end

		for _, inst in result do
			if inst.Parent == nil then inst:Destroy() end
		end
		return 0, 0
	end

	-- Skip uncreatable classes if instance doesn't exist
	if UNCREATABLE_CLASSES[data.className] then
		if existing then
			InstanceSerializer._applyProps(existing, data, pendingRefs)
			tracked[existing] = true
			claimed[existing] = true
			return 0, 1
		end
		return 0, 0
	end

	if existing then
		-- Class is guaranteed to match by findUnclaimed's filter
		InstanceSerializer._applyProps(existing, data, pendingRefs)
		tracked[existing] = true
		claimed[existing] = true
		return 0, 1
	end

	local nameCollision = findUnclaimed(parent, instName, claimed, nil)
	if nameCollision and nameCollision.ClassName == "Folder" and not UNCREATABLE_CLASSES[data.className] then
		-- Intermediate walk created a Folder placeholder. Replace it with
		-- the correct class (Configuration, Actor, Part, Model, etc.)
		-- and reparent its children.
		local createOk, inst = pcall(function() return Instance.new(data.className) end)
		if createOk and inst then
			inst.Name = instName
			InstanceSerializer._applyProps(inst, data, pendingRefs)
			for _, child in nameCollision:GetChildren() do child.Parent = inst end
			inst.Parent = parent
			nameCollision:Destroy()
			tracked[inst] = true
			claimed[inst] = true
			return 1, 0
		end
	elseif nameCollision then
		warn(`[RoGit] Sibling collision: {filePath} has {data.className} but {nameCollision:GetFullName()} is {nameCollision.ClassName}. Creating new instance.`)
	end

	local createOk, inst = pcall(function() return Instance.new(data.className) end)
	if not createOk or not inst then
		warn(`[RoGit] Cannot create instance of type "{data.className}" for {filePath}`)
		return 0, 0
	end
	inst.Name = instName
	InstanceSerializer._applyProps(inst, data, pendingRefs)
	inst.Parent = parent
	tracked[inst] = true
	claimed[inst] = true
	return 1, 0
end

function InstanceSerializer._applyMetaFile(_self: InstanceSerializer, metaPath: string, content: string)
	local stripped = metaPath:sub(1, -#META_EXT - 1)
	if stripped:match("/" .. INIT .. "$") then
		stripped = stripped:sub(1, -#INIT - 2)
	end


	local segments = stripped:split("/")
	if #segments >= 1 then
		segments[#segments] = stripDisambiguation(segments[#segments])
	end

	if #segments < 2 then return end

	local service = game:FindService(segments[1])
	if not service then return end

	local target: Instance = service
	for i = 2, #segments do
		local child = target:FindFirstChild(segments[i])
		if not child then return end
		target = child
	end

	local decOk, meta = pcall(function() return HttpService:JSONDecode(content) :: ScriptMeta end)
	if not decOk or not meta then return end


	if type(meta.name) == "string" and target.Name ~= meta.name then
		pcall(function() target.Name = meta.name end)
	end

	applyScriptMeta(target, meta)
end


function InstanceSerializer._applyProps(inst: Instance, data: SerializedInstance, pendingRefs: { { inst: Instance, propName: string, targetPath: string } }?)
	for k, v in data.properties do
		if PropertyMap.isObjectReference(k) then
			-- Defer reference resolution to after all instances are created
			if pendingRefs and type(v) == "table" and v._t == "Ref" and v.path then
				table.insert(pendingRefs, { inst = inst, propName = k, targetPath = v.path })
			end
			continue
		end
		local dec = DataTypes.decode(v)
		if dec ~= nil then pcall(function() (inst :: any)[k] = dec end) end
	end

	if data.attributes then
		for k, v in data.attributes do
			local dec = DataTypes.decode(v)
			if dec ~= nil then pcall(function() inst:SetAttribute(k, dec) end) end
		end
	end

	if data.tags then
		for _, existingTag in inst:GetTags() do inst:RemoveTag(existingTag) end
		for _, tag in data.tags do inst:AddTag(tag) end
	end
end

--==============================--
--       PARSE FILE PATH        --
--==============================--

function InstanceSerializer._parseFilePath(filePath: string): (string?, string?)

	if filePath:sub(-#META_EXT) == META_EXT then return nil, nil end

	local ORDERED_EXTS: { { string } } = {
		{ ".server.luau", "Script" },
		{ ".client.luau", "LocalScript" },
		{ ".luau", "ModuleScript" },
	}
	for _, pair in ORDERED_EXTS do
		local ext, cls = pair[1], pair[2]
		if filePath:sub(-#ext) == ext then
			local stripped = filePath:sub(1, -#ext - 1)
			if stripped:match("/" .. INIT .. "$") then stripped = stripped:sub(1, -#INIT - 2) end
			return stripped, cls
		end
	end
	if filePath:sub(-#JSON_EXT) == JSON_EXT then
		local stripped = filePath:sub(1, -#JSON_EXT - 1)
		if stripped:match("/" .. INIT .. "$") then stripped = stripped:sub(1, -#INIT - 2) end
		return stripped, "__json__"
	end
	return nil, nil
end

--==============================--
--     COLLECT PATHS/CONTENTS   --
--==============================--

function InstanceSerializer._collectPaths(self: InstanceSerializer, inst: Instance, path: string, out: { string }, ignoreList: { [string]: boolean })
	local ok, children = pcall(function() return inst:GetChildren() end)
	if not ok then return end

	local seen: { [string]: number } = {}

	for _, child in children do
		if IGNORED_CLASSES[child.ClassName] then continue end
		if isIgnored(child.Name, ignoreList) then continue end
		self:_throttle()

		local walkOk = pcall(function()
			local safeName = sanitizeName(child.Name)
			if child.Name == INIT then safeName = "_" .. safeName end
			local disambiguated = disambiguate(safeName, seen)
			local cp = path .. "/" .. disambiguated

			local visibleChildren: { Instance } = {}
			for _, gc in child:GetChildren() do
				if not IGNORED_CLASSES[gc.ClassName] then table.insert(visibleChildren, gc) end
			end
			local hasKids = #visibleChildren > 0

			if SCRIPT_CLASSES[child.ClassName] then
				local ext = SCRIPT_EXT[child.ClassName]
				table.insert(out, if hasKids then cp .. "/" .. INIT .. ext else cp .. ext)
				if hasMetadata(child) then
					table.insert(out, if hasKids then cp .. "/" .. INIT .. META_EXT else cp .. META_EXT)
				end
			else
				local reg = PropertyMap.isRegistered(child.ClassName)
				local hasMeta = hasMetadata(child)
				if reg or hasMeta then
					table.insert(out, if hasKids then cp .. "/" .. INIT .. JSON_EXT else cp .. JSON_EXT)
				end
			end
			if hasKids then self:_collectPaths(child, cp, out, ignoreList) end
		end)

		if not walkOk then
			warn(`[RoGit] Error collecting paths for {path}/{child.Name}`)
		end
	end
end

function InstanceSerializer._collectContents(self: InstanceSerializer, inst: Instance, path: string, map: { [string]: string }, ignoreList: { [string]: boolean })
	local ok, children = pcall(function() return inst:GetChildren() end)
	if not ok then return end

	local seen: { [string]: number } = {}

	for _, child in children do
		if IGNORED_CLASSES[child.ClassName] then continue end
		if isIgnored(child.Name, ignoreList) then continue end

		if child.Name == "README" and child.ClassName == "ModuleScript" and path == "ServerStorage" then
			continue
		end

		self:_throttle()

		local walkOk = pcall(function()
			local safeName = sanitizeName(child.Name)
			if child.Name == INIT then safeName = "_" .. safeName end
			local disambiguated, wasRenamed = disambiguate(safeName, seen)
			local cp = path .. "/" .. disambiguated
			local realName: string? = if wasRenamed or safeName ~= child.Name then child.Name else nil

			local visibleChildren: { Instance } = {}
			for _, gc in child:GetChildren() do
				if not IGNORED_CLASSES[gc.ClassName] then table.insert(visibleChildren, gc) end
			end
			local hasKids = #visibleChildren > 0

			if SCRIPT_CLASSES[child.ClassName] then
				local ext = SCRIPT_EXT[child.ClassName]
				local filePath = if hasKids then cp .. "/" .. INIT .. ext else cp .. ext
				map[filePath] = (child :: any).Source

				local metaJson = serializeScriptMeta(child, realName)
				if metaJson then
					local metaPath = if hasKids then cp .. "/" .. INIT .. META_EXT else cp .. META_EXT
					map[metaPath] = metaJson
				end
			else
				local json = self:_serializeProps(child, realName)
				if json then
					local filePath = if hasKids then cp .. "/" .. INIT .. JSON_EXT else cp .. JSON_EXT
					map[filePath] = json
				end
			end
			if hasKids then self:_collectContents(child, cp, map, ignoreList) end
		end)

		if not walkOk then
			warn(`[RoGit] Error collecting contents for {path}/{child.Name}`)
		end
	end
end

--==============================--
--    DELETED RECONCILIATION    --
--==============================--

-- Compare old and new remote file sets. Any path that existed in old but
-- not in new was deleted remotely -- find and destroy the local instance.
function InstanceSerializer.reconcileDeleted(_self: InstanceSerializer, oldRemote: { [string]: string }, newRemote: { [string]: string }): number
	local deleted = 0

	for path in oldRemote do
		if newRemote[path] then continue end
		if path == "README.md" then continue end
		-- Skip meta files -- they're sidecars, not standalone instances
		if path:sub(-#".meta.json") == ".meta.json" then continue end

		local instPath, _className = InstanceSerializer._parseFilePath(path)
		if not instPath then continue end

		local segments = instPath:split("/")
		if #segments < 2 then continue end

		local service = game:FindService(segments[1])
		if not service then continue end

		local target: Instance? = service
		for i = 2, #segments do
			if not target then break end
			local childName = stripDisambiguation(segments[i])
			target = (target :: Instance):FindFirstChild(childName)
		end

		if target and target ~= service then
			local ok = pcall(function() (target :: Instance):Destroy() end)
			if ok then
				deleted += 1
			end
		end
	end

	return deleted
end

return InstanceSerializer