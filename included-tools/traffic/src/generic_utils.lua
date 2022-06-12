local gcSmooth = 0
local gcRuns = 0
local function runGC()
  local before = collectgarbage("count")
  collectgarbage()
  gcSmooth = math.applyLag(gcSmooth, before - collectgarbage("count"), gcRuns < 50 and 0.5 or 0.8, 0.01)
  gcRuns = gcRuns + 1
  ac.debug("GC", math.floor(gcSmooth * 100) / 100 .. " KB")
end

local function table_print(tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
    for key, value in pairs(tt) do
      table.insert(sb, string.rep(" ", indent)) -- indent it
      if type(value) == "table" and not done[value] then
        done[value] = true
        table.insert(sb, key .. " = {\n")
        table.insert(sb, table_print(value, indent + 2, done))
        table.insert(sb, string.rep(" ", indent)) -- indent it
        table.insert(sb, "}\n")
      elseif "number" == type(key) then
        table.insert(sb, string.format('"%s"\n', tostring(value)))
      else
        table.insert(sb, string.format('%s = "%s"\n', tostring(key), tostring(value)))
      end
    end
    return table.concat(sb)
  else
    return tt .. "\n"
  end
end
local function stringify(tbl)
  if "nil" == type(tbl) then
    return tostring(nil)
  elseif "table" == type(tbl) then
    return table_print(tbl)
  elseif "string" == type(tbl) then
    return tbl
  else
    return tostring(tbl)
  end
end

local GenericUtils = {
  runGC = runGC,
  stringify = stringify
}

return GenericUtils
