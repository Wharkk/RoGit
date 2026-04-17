local HttpService = game:GetService("HttpService")
local Types = require(script.Parent.Types)
local Base64 = require(script.Parent.Base64)

type GitHubConfig = Types.GitHubConfig
type ApiResult<T> = Types.ApiResult<T>
type TreeEntry = Types.TreeEntry
type CommitInfo = Types.CommitInfo
type BranchInfo = Types.BranchInfo

local API = "https://api.github.com"

local GitHubClient = {}
GitHubClient.__index = GitHubClient

export type GitHubClient = typeof(setmetatable({} :: {
	config: GitHubConfig,
	_blobCache: { [string]: string },
}, GitHubClient))

function GitHubClient.new(config: GitHubConfig): GitHubClient
	local self = setmetatable({}, GitHubClient)
	self.config = config
	self._blobCache = {}
	return self
end

function GitHubClient._url(self: GitHubClient, path: string): string
	return `{API}/repos/{self.config.owner}/{self.config.repo}{path}`
end

function GitHubClient._headers(self: GitHubClient): { [string]: string }
	return {
		["Authorization"] = `Bearer {self.config.token}`,
		["Accept"] = "application/vnd.github+json",
		["X-GitHub-Api-Version"] = "2022-11-28",
		["Content-Type"] = "application/json",
	}
end

function GitHubClient._req(self: GitHubClient, method: string, url: string, body: { [string]: any }?): ApiResult<any>
	local params: { [string]: any } = { Url = url, Method = method, Headers = self:_headers() }
	if body then params.Body = HttpService:JSONEncode(body) end

	local ok, resp = pcall(function() return HttpService:RequestAsync(params) end)
	if not ok then return { ok = false, error = `Request failed: {resp}` } end

	local decoded: any = nil
	if resp.Body and #resp.Body > 0 then
		local dOk, dResult = pcall(function() return HttpService:JSONDecode(resp.Body) end)
		if dOk then decoded = dResult end
	end

	if resp.StatusCode >= 200 and resp.StatusCode < 300 then
		return { ok = true, data = decoded }
	end

	local msg = "Unknown error"
	if decoded and decoded.message then msg = decoded.message
	elseif resp.StatusMessage then msg = resp.StatusMessage end
	return { ok = false, error = `[{resp.StatusCode}] {msg}` }
end

function GitHubClient.testConnection(self: GitHubClient): ApiResult<string>
	local r = self:_req("GET", self:_url(""))
	if r.ok then return { ok = true, data = r.data.full_name } end
	return r :: ApiResult<string>
end

function GitHubClient.getRef(self: GitHubClient, branch: string): ApiResult<string>
	local r = self:_req("GET", self:_url(`/git/ref/heads/{branch}`))
	if r.ok then return { ok = true, data = r.data.object.sha } end
	return r :: ApiResult<string>
end

function GitHubClient.getCommitTree(self: GitHubClient, sha: string): ApiResult<string>
	local r = self:_req("GET", self:_url(`/git/commits/{sha}`))
	if r.ok then return { ok = true, data = r.data.tree.sha } end
	return r :: ApiResult<string>
end

function GitHubClient.getTreeRecursive(self: GitHubClient, treeSha: string): ApiResult<{ TreeEntry }>
	local r = self:_req("GET", self:_url(`/git/trees/{treeSha}?recursive=1`))
	if not r.ok then return r :: ApiResult<{ TreeEntry }> end
	if r.data.truncated then
		warn("[RoGit] GitHub tree response was truncated -- some files may be missing from the remote cache. Consider excluding large services to reduce tree size.")
	end
	local entries: { TreeEntry } = {}
	for _, item in r.data.tree do
		if item.type == "blob" then
			table.insert(entries, { path = item.path, mode = item.mode, type = item.type, sha = item.sha, size = item.size })
		end
	end
	return { ok = true, data = entries }
end

function GitHubClient.getBlob(self: GitHubClient, sha: string): ApiResult<string>
	local r = self:_req("GET", self:_url(`/git/blobs/{sha}`))
	if not r.ok then return r :: ApiResult<string> end
	local content = if r.data.encoding == "base64" then Base64.decode(r.data.content) else r.data.content
	-- Normalize line endings: GitHub may return CRLF, local serializer uses LF only.
	local CRLF = string.char(13) .. "\n"
	local CR = string.char(13)
	local LF = "\n"
	content = content:gsub(CRLF, LF):gsub(CR, LF)
	return { ok = true, data = content }
end

local TREE_BATCH_SIZE = 100

function GitHubClient.createTree(self: GitHubClient, entries: { TreeEntry }, baseSha: string?): ApiResult<string>
	if #entries <= TREE_BATCH_SIZE then
		local items: { { [string]: any } } = {}
		for _, e in entries do
			local item: { [string]: any } = { path = e.path, mode = e.mode or "100644", type = e.type or "blob" }
			if e.content ~= nil then item.content = e.content elseif e.sha ~= nil then item.sha = e.sha end
			table.insert(items, item)
		end
		local body: { [string]: any } = { tree = items }
		if baseSha then body.base_tree = baseSha end
		local r = self:_req("POST", self:_url("/git/trees"), body)
		if r.ok then return { ok = true, data = r.data.sha } end
		return r :: ApiResult<string>
	end

	-- Large tree: split into batches, chaining each result as the base
	-- for the next so entries accumulate into one final tree.
	local currentBase = baseSha
	for batchStart = 1, #entries, TREE_BATCH_SIZE do
		local batchEnd = math.min(batchStart + TREE_BATCH_SIZE - 1, #entries)
		local items: { { [string]: any } } = {}
		for i = batchStart, batchEnd do
			local e = entries[i]
			local item: { [string]: any } = { path = e.path, mode = e.mode or "100644", type = e.type or "blob" }
			if e.content ~= nil then item.content = e.content elseif e.sha ~= nil then item.sha = e.sha end
			table.insert(items, item)
		end
		local body: { [string]: any } = { tree = items }
		if currentBase then body.base_tree = currentBase end
		local r = self:_req("POST", self:_url("/git/trees"), body)
		if not r.ok then return r :: ApiResult<string> end
		currentBase = r.data.sha
	end
	return { ok = true, data = currentBase :: string }
end

function GitHubClient.createCommit(self: GitHubClient, treeSha: string, parentSha: string, message: string): ApiResult<string>
	local r = self:_req("POST", self:_url("/git/commits"), { message = message, tree = treeSha, parents = { parentSha } })
	if r.ok then return { ok = true, data = r.data.sha } end
	return r :: ApiResult<string>
end

function GitHubClient.updateRef(self: GitHubClient, branch: string, sha: string, force: boolean?): ApiResult<nil>
	local r = self:_req("PATCH", self:_url(`/git/refs/heads/{branch}`), { sha = sha, force = force or false })
	return { ok = r.ok, error = r.error }
end

function GitHubClient.getBranches(self: GitHubClient): ApiResult<{ BranchInfo }>
	local r = self:_req("GET", self:_url("/branches?per_page=100"))
	if not r.ok then return r :: ApiResult<{ BranchInfo }> end
	local branches: { BranchInfo } = {}
	for _, b in r.data do
		table.insert(branches, { name = b.name, sha = b.commit.sha, protected = b.protected or false })
	end
	return { ok = true, data = branches }
end

function GitHubClient.createBranch(self: GitHubClient, name: string, fromSha: string): ApiResult<nil>
	local r = self:_req("POST", self:_url("/git/refs"), { ref = `refs/heads/{name}`, sha = fromSha })
	return { ok = r.ok, error = r.error }
end

function GitHubClient.deleteBranch(self: GitHubClient, name: string): ApiResult<nil>
	local r = self:_req("DELETE", self:_url(`/git/refs/heads/{name}`))
	return { ok = r.ok, error = r.error }
end

function GitHubClient.merge(self: GitHubClient, base: string, head: string, message: string): ApiResult<string>
	local r = self:_req("POST", self:_url("/merges"), { base = base, head = head, commit_message = message })
	if r.ok then return { ok = true, data = r.data.sha } end
	return r :: ApiResult<string>
end

function GitHubClient.getCommits(self: GitHubClient, branch: string, limit: number): ApiResult<{ CommitInfo }>
	local r = self:_req("GET", self:_url(`/commits?sha={branch}&per_page={limit}`))
	if not r.ok then return r :: ApiResult<{ CommitInfo }> end
	local commits: { CommitInfo } = {}
	for _, item in r.data do
		local sha = item.sha :: string
		table.insert(commits, {
			sha = sha, shortSha = sha:sub(1, 7),
			message = item.commit.message, author = item.commit.author.name, date = item.commit.author.date,
		})
	end
	return { ok = true, data = commits }
end

function GitHubClient.getFileCommits(self: GitHubClient, path: string, branch: string, limit: number): ApiResult<{ CommitInfo }>
	local r = self:_req("GET", self:_url(`/commits?sha={branch}&path={path}&per_page={limit}`))
	if not r.ok then return r :: ApiResult<{ CommitInfo }> end
	local commits: { CommitInfo } = {}
	for _, item in r.data do
		local sha = item.sha :: string
		table.insert(commits, {
			sha = sha, shortSha = sha:sub(1, 7),
			message = item.commit.message, author = item.commit.author.name, date = item.commit.author.date,
		})
	end
	return { ok = true, data = commits }
end

function GitHubClient.getCommitDetail(self: GitHubClient, sha: string): ApiResult<{ treeSha: string, parentShas: { string }, message: string }>
	local r = self:_req("GET", self:_url(`/git/commits/{sha}`))
	if not r.ok then return r :: ApiResult<any> end
	local parents: { string } = {}
	if r.data.parents then
		for _, p in r.data.parents do table.insert(parents, p.sha) end
	end
	return { ok = true, data = { treeSha = r.data.tree.sha, parentShas = parents, message = r.data.message or "" } }
end

function GitHubClient.revertCommit(self: GitHubClient, commitSha: string): ApiResult<string>
	local branch = self.config.branch

	-- Get current HEAD
	local headR = self:getRef(branch)
	if not headR.ok then return { ok = false, error = `Ref: {headR.error}` } end
	local headSha = headR.data :: string

	-- Get the commit to revert
	local commitR = self:getCommitDetail(commitSha)
	if not commitR.ok then return { ok = false, error = `Commit: {commitR.error}` } end
	local commitData = commitR.data :: { treeSha: string, parentShas: { string }, message: string }

	if #commitData.parentShas == 0 then
		return { ok = false, error = "Cannot revert: initial commit has no parent" }
	end

	-- Get parent commit's tree (what we want to restore to)
	local parentR = self:getCommitDetail(commitData.parentShas[1])
	if not parentR.ok then return { ok = false, error = `Parent: {parentR.error}` } end
	local parentTree = (parentR.data :: { treeSha: string, parentShas: { string }, message: string }).treeSha

	-- Create revert commit
	local firstLine = commitData.message:split("\n")[1] or commitData.message
	local revertMsg = `Revert "{firstLine}"\n\nReverts commit {commitSha:sub(1, 7)}`
	local newCommitR = self:createCommit(parentTree, headSha, revertMsg)
	if not newCommitR.ok then return { ok = false, error = `Commit: {newCommitR.error}` } end

	-- Update ref
	local updateR = self:updateRef(branch, newCommitR.data :: string)
	if not updateR.ok then return { ok = false, error = `Ref update: {updateR.error}` } end

	return { ok = true, data = newCommitR.data :: string }
end

function GitHubClient.pushTree(self: GitHubClient, files: { TreeEntry }, message: string): ApiResult<string>
	local branch = self.config.branch

	local refR = self:getRef(branch)
	if not refR.ok then return { ok = false, error = `Ref: {refR.error}` } end
	local parentSha = refR.data :: string

	local treeR = self:createTree(files)
	if not treeR.ok then return { ok = false, error = `Tree: {treeR.error}` } end

	local commitR = self:createCommit(treeR.data :: string, parentSha, message)
	if not commitR.ok then return { ok = false, error = `Commit: {commitR.error}` } end

	local updateR = self:updateRef(branch, commitR.data :: string)
	if not updateR.ok then return { ok = false, error = `Ref update: {updateR.error}` } end

	return { ok = true, data = commitR.data }
end

function GitHubClient.pushChanges(
	self: GitHubClient,
	changedEntries: { TreeEntry },
	remoteEntries: { TreeEntry }?,
	hasDeletions: boolean,
	message: string
): ApiResult<string>
	local branch = self.config.branch

	local refR = self:getRef(branch)
	if not refR.ok then return { ok = false, error = `Ref: {refR.error}` } end
	local parentSha = refR.data :: string

	local treeR
	if hasDeletions and remoteEntries then
		local changedPaths: { [string]: TreeEntry } = {}
		for _, e in changedEntries do
			changedPaths[e.path] = e
		end
		local deletedSet: { [string]: boolean } = {}
		for _, e in changedEntries do
			if e.sha == nil and e.content == nil then
				deletedSet[e.path] = true
			end
		end
		local fullTree: { TreeEntry } = {}
		for _, remote in remoteEntries do
			if deletedSet[remote.path] then
				continue
			elseif changedPaths[remote.path] then
				table.insert(fullTree, changedPaths[remote.path])
			else
				table.insert(fullTree, { path = remote.path, mode = remote.mode, type = "blob", sha = remote.sha })
			end
		end
		for _, e in changedEntries do
			if not deletedSet[e.path] and e.content ~= nil then
				local found = false
				for _, r in remoteEntries do
					if r.path == e.path then found = true; break end
				end
				if not found then
					table.insert(fullTree, e)
				end
			end
		end
		treeR = self:createTree(fullTree)
	else
		local commitTreeR = self:getCommitTree(parentSha)
		if not commitTreeR.ok then return { ok = false, error = `Tree: {commitTreeR.error}` } end
		treeR = self:createTree(changedEntries, commitTreeR.data :: string)
	end

	if not treeR.ok then return { ok = false, error = `Tree: {treeR.error}` } end

	local commitR = self:createCommit(treeR.data :: string, parentSha, message)
	if not commitR.ok then return { ok = false, error = `Commit: {commitR.error}` } end

	local updateR = self:updateRef(branch, commitR.data :: string)
	if not updateR.ok then return { ok = false, error = `Ref update: {updateR.error}` } end

	return { ok = true, data = commitR.data }
end

function GitHubClient.pullTree(self: GitHubClient): ApiResult<{ TreeEntry }>
	local refR = self:getRef(self.config.branch)
	if not refR.ok then return { ok = false, error = `Ref: {refR.error}` } end
	local treeR = self:getCommitTree(refR.data :: string)
	if not treeR.ok then return { ok = false, error = `Tree: {treeR.error}` } end
	return self:getTreeRecursive(treeR.data :: string)
end

function GitHubClient.pullFileContents(self: GitHubClient, entries: { TreeEntry }, onProgress: ((number, number) -> ())?, onLog: ((string, Color3?) -> ())?): { [string]: string }
	local contents: { [string]: string } = {}
	local total = #entries
	local done = 0
	local errors: { string } = {}
	local cacheHits = 0

	-- Separate cached vs uncached entries
	local toFetch: { TreeEntry } = {}
	for _, entry in entries do
		local sha = entry.sha :: string
		if self._blobCache[sha] then
			contents[entry.path] = self._blobCache[sha]
			cacheHits += 1
			done += 1
		else
			table.insert(toFetch, entry)
		end
	end

	if onProgress and cacheHits > 0 then onProgress(done, total) end

	for batchStart = 1, #toFetch, 20 do
		local batchEnd = math.min(batchStart + 19, #toFetch)
		local batchTarget = done + (batchEnd - batchStart + 1)
		for i = batchStart, batchEnd do
			local entry = toFetch[i]
			task.spawn(function()
				local maxRetries = 3
				for attempt = 1, maxRetries do
					local r = self:getBlob(entry.sha :: string)
					if r.ok then
						local data = r.data :: string
						contents[entry.path] = data
						self._blobCache[entry.sha :: string] = data
						break
					end

					local errStr = r.error or ""
					if (errStr:find("403") or errStr:find("429")) and attempt < maxRetries then
						task.wait(2 ^ attempt)
					else
						if attempt == maxRetries then
							table.insert(errors, `{entry.path}: {errStr}`)
						end
						break
					end
				end
				done += 1
				if onProgress then onProgress(done, total) end
			end)
		end
		while done < batchTarget do task.wait(0.05) end
	end

	local function log(msg: string, color: Color3?)
		if onLog then onLog(msg, color) else warn(`[RoGit] ` .. msg) end
	end

	if #errors > 0 then
		log(`{#errors} file(s) failed to download:`)
		for _, e in errors do log(`  - {e}`) end
	end

	if cacheHits > 0 and #toFetch > 0 then
		log(`Blob cache: {cacheHits} cached, {#toFetch} downloaded`)
	end

	return contents
end

--==============================--
--       PULL REQUESTS          --
--==============================--

export type PullRequest = {
	number: number,
	title: string,
	state: string,
	author: string,
	head: string,
	base: string,
	createdAt: string,
	url: string,
	mergeable: boolean?,
}

function GitHubClient.createPullRequest(self: GitHubClient, title: string, body: string, head: string, base: string): ApiResult<PullRequest>
	local r = self:_req("POST", self:_url("/pulls"), { title = title, body = body, head = head, base = base })
	if not r.ok then return r :: ApiResult<PullRequest> end
	return { ok = true, data = {
		number = r.data.number, title = r.data.title, state = r.data.state,
		author = r.data.user.login, head = r.data.head.ref, base = r.data.base.ref,
		createdAt = r.data.created_at, url = r.data.html_url, mergeable = r.data.mergeable,
	} }
end

function GitHubClient.getPullRequests(self: GitHubClient, state: string?): ApiResult<{ PullRequest }>
	local st = state or "open"
	local r = self:_req("GET", self:_url(`/pulls?state={st}&per_page=20`))
	if not r.ok then return r :: ApiResult<{ PullRequest }> end
	local prs: { PullRequest } = {}
	for _, item in r.data do
		table.insert(prs, {
			number = item.number, title = item.title, state = item.state,
			author = item.user.login, head = item.head.ref, base = item.base.ref,
			createdAt = item.created_at, url = item.html_url, mergeable = item.mergeable,
		})
	end
	return { ok = true, data = prs }
end

--==============================--
--      ACTIONS STATUS          --
--==============================--

export type WorkflowRun = {
	id: number,
	name: string,
	status: string,
	conclusion: string?,
	branch: string,
	event: string,
	createdAt: string,
	url: string,
}

function GitHubClient.getWorkflowRuns(self: GitHubClient, branch: string?, limit: number?): ApiResult<{ WorkflowRun }>
	local query = `/actions/runs?per_page={limit or 5}`
	if branch then query ..= `&branch={branch}` end
	local r = self:_req("GET", self:_url(query))
	if not r.ok then return r :: ApiResult<{ WorkflowRun }> end
	local runs: { WorkflowRun } = {}
	for _, item in r.data.workflow_runs or {} do
		table.insert(runs, {
			id = item.id, name = item.name or "Workflow",
			status = item.status, conclusion = item.conclusion,
			branch = item.head_branch or "", event = item.event or "",
			createdAt = item.created_at or "", url = item.html_url or "",
		})
	end
	return { ok = true, data = runs }
end

--==============================--
--      TAGS / RELEASES         --
--==============================--

export type Release = {
	id: number,
	tag: string,
	name: string,
	body: string,
	author: string,
	createdAt: string,
	url: string,
	draft: boolean,
	prerelease: boolean,
}

function GitHubClient.createRelease(self: GitHubClient, tag: string, name: string, body: string, branch: string, prerelease: boolean?): ApiResult<Release>
	local r = self:_req("POST", self:_url("/releases"), {
		tag_name = tag, name = name, body = body,
		target_commitish = branch, prerelease = prerelease or false, draft = false,
	})
	if not r.ok then return r :: ApiResult<Release> end
	return { ok = true, data = {
		id = r.data.id, tag = r.data.tag_name, name = r.data.name or "",
		body = r.data.body or "", author = r.data.author.login,
		createdAt = r.data.created_at, url = r.data.html_url,
		draft = r.data.draft, prerelease = r.data.prerelease,
	} }
end

function GitHubClient.getReleases(self: GitHubClient, limit: number?): ApiResult<{ Release }>
	local r = self:_req("GET", self:_url(`/releases?per_page={limit or 10}`))
	if not r.ok then return r :: ApiResult<{ Release }> end
	local releases: { Release } = {}
	for _, item in r.data do
		table.insert(releases, {
			id = item.id, tag = item.tag_name, name = item.name or "",
			body = item.body or "", author = item.author.login,
			createdAt = item.created_at, url = item.html_url,
			draft = item.draft, prerelease = item.prerelease,
		})
	end
	return { ok = true, data = releases }
end

return GitHubClient