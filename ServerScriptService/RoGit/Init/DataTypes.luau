local DataTypes = {}

type TaggedValue = { _t: string, [string]: any }

local encoders: { [string]: (value: any) -> TaggedValue } = {
	Vector3 = function(v: Vector3)
		return { _t = "Vector3", x = v.X, y = v.Y, z = v.Z }
	end,
	Vector2 = function(v: Vector2)
		return { _t = "Vector2", x = v.X, y = v.Y }
	end,
	CFrame = function(cf: CFrame)
		return { _t = "CFrame", c = { cf:GetComponents() } }
	end,
	Color3 = function(c: Color3)
		return { _t = "Color3", r = c.R, g = c.G, b = c.B }
	end,
	BrickColor = function(bc: BrickColor)
		return { _t = "BrickColor", name = bc.Name }
	end,
	UDim = function(u: UDim)
		return { _t = "UDim", s = u.Scale, o = u.Offset }
	end,
	UDim2 = function(u: UDim2)
		return { _t = "UDim2", xs = u.X.Scale, xo = u.X.Offset, ys = u.Y.Scale, yo = u.Y.Offset }
	end,
	Rect = function(r: Rect)
		return { _t = "Rect", x0 = r.Min.X, y0 = r.Min.Y, x1 = r.Max.X, y1 = r.Max.Y }
	end,
	NumberRange = function(nr: NumberRange)
		return { _t = "NumberRange", min = nr.Min, max = nr.Max }
	end,
	NumberSequence = function(ns: NumberSequence)
		local kp = {}
		for _, k in ns.Keypoints do
			table.insert(kp, { t = k.Time, v = k.Value, e = k.Envelope })
		end
		return { _t = "NumberSequence", kp = kp }
	end,
	ColorSequence = function(cs: ColorSequence)
		local kp = {}
		for _, k in cs.Keypoints do
			table.insert(kp, { t = k.Time, r = k.Value.R, g = k.Value.G, b = k.Value.B })
		end
		return { _t = "ColorSequence", kp = kp }
	end,
	PhysicalProperties = function(pp: PhysicalProperties)
		return { _t = "PhysicalProperties", d = pp.Density, f = pp.Friction, e = pp.Elasticity, fw = pp.FrictionWeight, ew = pp.ElasticityWeight }
	end,
	Font = function(f: Font)
		return { _t = "Font", family = f.Family, weight = f.Weight.Name, style = f.Style.Name }
	end,
	EnumItem = function(e: EnumItem)
		return { _t = "Enum", et = tostring(e.EnumType), n = e.Name }
	end,
	Content = function(c: any)
		return { _t = "Content", uri = tostring(c) }
	end,
}

local decoders: { [string]: (data: TaggedValue) -> any } = {
	Vector3 = function(d) return Vector3.new(d.x, d.y, d.z) end,
	Vector2 = function(d) return Vector2.new(d.x, d.y) end,
	CFrame = function(d) return CFrame.new(table.unpack(d.c)) end,
	Color3 = function(d) return Color3.new(d.r, d.g, d.b) end,
	BrickColor = function(d) return BrickColor.new(d.name) end,
	UDim = function(d) return UDim.new(d.s, d.o) end,
	UDim2 = function(d) return UDim2.new(d.xs, d.xo, d.ys, d.yo) end,
	Rect = function(d) return Rect.new(d.x0, d.y0, d.x1, d.y1) end,
	NumberRange = function(d) return NumberRange.new(d.min, d.max) end,
	NumberSequence = function(d)
		local kp: { NumberSequenceKeypoint } = {}
		for _, k in d.kp do table.insert(kp, NumberSequenceKeypoint.new(k.t, k.v, k.e)) end
		return NumberSequence.new(kp)
	end,
	ColorSequence = function(d)
		local kp: { ColorSequenceKeypoint } = {}
		for _, k in d.kp do table.insert(kp, ColorSequenceKeypoint.new(k.t, Color3.new(k.r, k.g, k.b))) end
		return ColorSequence.new(kp)
	end,
	PhysicalProperties = function(d) return PhysicalProperties.new(d.d, d.f, d.e, d.fw, d.ew) end,
	Font = function(d) return Font.new(d.family, (Enum.FontWeight :: any)[d.weight], (Enum.FontStyle :: any)[d.style]) end,
	Enum = function(d) return (Enum :: any)[d.et][d.n] end,
	Content = function(d) return d.uri or d.value or "" end,
}

function DataTypes.encode(value: any): any
	local t = typeof(value)
	if t == "string" or t == "number" or t == "boolean" then return value end
	if t == "EnumItem" then return encoders.EnumItem(value) end
	local enc = encoders[t]
	return if enc then enc(value) else nil
end

function DataTypes.decode(value: any): any
	if type(value) ~= "table" then return value end
	local tag = (value :: TaggedValue)._t
	if not tag then return value end
	local dec = decoders[tag]
	if dec then
		local ok, result = pcall(dec, value)
		if ok then return result end
	end
	return nil
end

function DataTypes.isSerializable(typeName: string): boolean
	return typeName == "string" or typeName == "number" or typeName == "boolean"
		or typeName == "EnumItem" or encoders[typeName] ~= nil
end

return DataTypes