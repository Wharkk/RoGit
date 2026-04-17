local Base64 = {}

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENCODE: { [number]: string } = {}
local DECODE: { [string]: number } = {}

for i = 0, 63 do
	local c = CHARS:sub(i + 1, i + 1)
	ENCODE[i] = c
	DECODE[c] = i
end

function Base64.encode(data: string): string
	local out: { string } = {}
	local len = #data

	for i = 1, len - 2, 3 do
		local b1, b2, b3 = string.byte(data, i, i + 2)
		local n = b1 * 65536 + b2 * 256 + b3
		table.insert(out, ENCODE[math.floor(n / 262144) % 64])
		table.insert(out, ENCODE[math.floor(n / 4096) % 64])
		table.insert(out, ENCODE[math.floor(n / 64) % 64])
		table.insert(out, ENCODE[n % 64])
	end

	local r = len % 3
	if r == 1 then
		local b = string.byte(data, len)
		table.insert(out, ENCODE[math.floor(b / 4)])
		table.insert(out, ENCODE[(b % 4) * 16])
		table.insert(out, "==")
	elseif r == 2 then
		local b1, b2 = string.byte(data, len - 1, len)
		local n = b1 * 256 + b2
		table.insert(out, ENCODE[math.floor(n / 1024)])
		table.insert(out, ENCODE[math.floor(n / 16) % 64])
		table.insert(out, ENCODE[(n % 16) * 4])
		table.insert(out, "=")
	end

	return table.concat(out)
end

function Base64.decode(encoded: string): string
	local stripped = encoded:gsub("%s+", "")

	local padding = 0
	if stripped:sub(-2) == "==" then
		padding = 2
	elseif stripped:sub(-1) == "=" then
		padding = 1
	end

	local cleaned = stripped:gsub("=", "")
	local out: { string } = {}
	local len = #cleaned

	local i = 1
	while i + 3 <= len do
		local a = DECODE[cleaned:sub(i, i)] or 0
		local b = DECODE[cleaned:sub(i + 1, i + 1)] or 0
		local c = DECODE[cleaned:sub(i + 2, i + 2)] or 0
		local d = DECODE[cleaned:sub(i + 3, i + 3)] or 0

		table.insert(out, string.char(a * 4 + math.floor(b / 16)))
		table.insert(out, string.char((b % 16) * 16 + math.floor(c / 4)))
		table.insert(out, string.char((c % 4) * 64 + d))

		i += 4
	end

	local remaining = len - i + 1
	if remaining == 2 then
		local a = DECODE[cleaned:sub(i, i)] or 0
		local b = DECODE[cleaned:sub(i + 1, i + 1)] or 0
		table.insert(out, string.char(a * 4 + math.floor(b / 16)))
	elseif remaining == 3 then
		local a = DECODE[cleaned:sub(i, i)] or 0
		local b = DECODE[cleaned:sub(i + 1, i + 1)] or 0
		local c = DECODE[cleaned:sub(i + 2, i + 2)] or 0
		table.insert(out, string.char(a * 4 + math.floor(b / 16)))
		table.insert(out, string.char((b % 16) * 16 + math.floor(c / 4)))
	end

	return table.concat(out)
end

return Base64