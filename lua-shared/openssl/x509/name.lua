local name = require"_openssl.x509.name"
local auxlib = require"shared.openssl.auxlib"

name.interpose("__tostring", function (self)
	local t = { }

	for k, v in auxlib.pairs(self) do
		t[#t + 1] = k .. "=" .. v
	end

	return table.concat(t, ", ")
end)

return name
