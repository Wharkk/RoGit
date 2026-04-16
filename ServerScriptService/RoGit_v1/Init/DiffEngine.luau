local DiffEngine = {}

export type DiffLine = {
	tag: "keep" | "add" | "remove" | "hunk",
	text: string,
	oldLine: number?,
	newLine: number?,
}

export type DiffResult = {
	lines: { DiffLine },
	additions: number,
	deletions: number,
}

local LF = "\n"
local CR = string.char(13)
local CRLF = CR .. LF

local function splitLines(text: string): { string }
	local normalized = text:gsub(CRLF, LF):gsub(CR, LF)
	local lines: { string } = {}
	for line in (normalized .. LF):gmatch("([^" .. LF .. "]*)" .. LF) do
		-- Trim trailing whitespace so invisible differences (tabs, spaces,
		-- null bytes at end of line) don't cause every line to mismatch.
		table.insert(lines, (line:gsub("%s+$", "")))
	end
	if #lines > 0 and lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end
local function computeLCS(oldLines: { string }, newLines: { string }): { { number } }
	local m, n = #oldLines, #newLines
	if m == 0 or n == 0 then return {} end

	local dp: { { number } } = {}
	for i = 0, m do
		dp[i] = {}
		for j = 0, n do
			dp[i][j] = 0
		end
	end

	for i = m, 1, -1 do
		for j = n, 1, -1 do
			if oldLines[i] == newLines[j] then
				dp[i - 1][j - 1] = dp[i][j] + 1
			else
				dp[i - 1][j - 1] = math.max(dp[i][j - 1], dp[i - 1][j])
			end
		end
	end

	local matches: { { number } } = {}
	local i, j = 1, 1
	while i <= m and j <= n do
		if oldLines[i] == newLines[j] then
			table.insert(matches, { i, j })
			i += 1
			j += 1
		elseif dp[i][j - 1] >= dp[i - 1][j] then
			i += 1
		else
			j += 1
		end
	end

	return matches
end

function DiffEngine.diff(oldText: string, newText: string): DiffResult
	if oldText == newText then
		return { lines = {}, additions = 0, deletions = 0 }
	end

	local oldLines = splitLines(oldText)
	local newLines = splitLines(newText)

	local matches = computeLCS(oldLines, newLines)
	local additions, deletions = 0, 0

	local oldIdx, newIdx = 1, 1
	local matchIdx = 1

	while oldIdx <= #oldLines or newIdx <= #newLines do
		local matchOld: number? = nil
		local matchNew: number? = nil
		if matchIdx <= #matches then
			matchOld = matches[matchIdx][1]
			matchNew = matches[matchIdx][2]
		end

		if matchOld and oldIdx == matchOld and matchNew and newIdx == matchNew then
			table.insert(result, { tag = "keep", text = oldLines[oldIdx], oldLine = oldIdx, newLine = newIdx })
			oldIdx += 1
			newIdx += 1
			matchIdx += 1
		else
			local nextMatchOld = matchOld or (#oldLines + 1)
			local nextMatchNew = matchNew or (#newLines + 1)

			while oldIdx < nextMatchOld do
				table.insert(result, { tag = "remove", text = oldLines[oldIdx], oldLine = oldIdx })
				deletions += 1
				oldIdx += 1
			end

			while newIdx < nextMatchNew do
				table.insert(result, { tag = "add", text = newLines[newIdx], newLine = newIdx })
				additions += 1
				newIdx += 1
			end
		end
	end

	return { lines = result, additions = additions, deletions = deletions }
end

local CONTEXT_LINES = 3

function DiffEngine.unifiedHunks(diffResult: DiffResult): { DiffLine }
	local all = diffResult.lines
	if #all == 0 then return {} end

	local changeIndices: { number } = {}
	for i, line in all do
		if line.tag ~= "keep" then
			table.insert(changeIndices, i)
		end
	end

	if #changeIndices == 0 then return {} end

	local hunks: { { start: number, finish: number } } = {}
	local hunkStart = math.max(1, changeIndices[1] - CONTEXT_LINES)
	local hunkEnd = math.min(#all, changeIndices[1] + CONTEXT_LINES)

	for ci = 2, #changeIndices do
		local idx = changeIndices[ci]
		local expandedStart = math.max(1, idx - CONTEXT_LINES)

		if expandedStart <= hunkEnd + 1 then
			hunkEnd = math.min(#all, idx + CONTEXT_LINES)
		else
			table.insert(hunks, { start = hunkStart, finish = hunkEnd })
			hunkStart = expandedStart
			hunkEnd = math.min(#all, idx + CONTEXT_LINES)
		end
	end
	table.insert(hunks, { start = hunkStart, finish = hunkEnd })

	local output: { DiffLine } = {}

	for _, hunk in hunks do
		local oldStart, newStart = 0, 0
		local oldCount, newCount = 0, 0

		for i = hunk.start, hunk.finish do
			local line = all[i]
			if line.tag == "keep" then
				if oldStart == 0 and line.oldLine then oldStart = line.oldLine end
				if newStart == 0 and line.newLine then newStart = line.newLine end
				oldCount += 1
				newCount += 1
			elseif line.tag == "remove" then
				if oldStart == 0 and line.oldLine then oldStart = line.oldLine end
				oldCount += 1
			elseif line.tag == "add" then
				if newStart == 0 and line.newLine then newStart = line.newLine end
				newCount += 1
			end
		end

		if oldStart == 0 then oldStart = 1 end
		if newStart == 0 then newStart = 1 end

		table.insert(output, {
			tag = "hunk",
			text = `@@ -{oldStart},{oldCount} +{newStart},{newCount} @@`,
		})

		for i = hunk.start, hunk.finish do
			table.insert(output, all[i])
		end
	end

	return output
end

function DiffEngine.computeFileDiffs(
	localFiles: { [string]: string },
	remoteFiles: { [string]: string }
): { { path: string, status: string, diff: DiffResult } }
	local results: { { path: string, status: string, diff: DiffResult } } = {}
	local allPaths: { [string]: boolean } = {}

	for path in localFiles do allPaths[path] = true end
	for path in remoteFiles do allPaths[path] = true end

	local sorted: { string } = {}
	for path in allPaths do table.insert(sorted, path) end
	table.sort(sorted)

	for _, path in sorted do
		local localContent = localFiles[path]
		local remoteContent = remoteFiles[path]

		if localContent and not remoteContent then
			local lines = splitLines(localContent)
			local diffLines: { DiffLine } = {}
			for i, line in lines do
				table.insert(diffLines, { tag = "add", text = line, newLine = i })
			end
			table.insert(results, {
				path = path,
				status = "added",
				diff = { lines = diffLines, additions = #lines, deletions = 0 },
			})
		elseif not localContent and remoteContent then
			local lines = splitLines(remoteContent)
			local diffLines: { DiffLine } = {}
			for i, line in lines do
				table.insert(diffLines, { tag = "remove", text = line, oldLine = i })
			end
			table.insert(results, {
				path = path,
				status = "deleted",
				diff = { lines = diffLines, additions = 0, deletions = #lines },
			})
		elseif localContent ~= remoteContent then
			table.insert(results, {
				path = path,
				status = "modified",
				diff = DiffEngine.diff(remoteContent :: string, localContent :: string),
			})
		end
	end

	return results
end

return DiffEngine