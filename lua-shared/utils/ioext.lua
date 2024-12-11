--[[
  Some extra functions to help deal with files. Available to scripts with I/O access only.
]]
---@diagnostic disable

local ioext = {}

---Recursive directory scan. Use carefully, as it would block execution until everything is scanned. Might be worth moving
---to a background worker.
---@generic TReturn
---@param dir string
---@param mask string?
---@param callback fun(relativeFilename: string, attrs: io.FileAttributes): TReturn?
---@return TReturn? @First non-nil value returned by callback.
function ioext.scanDirRec(dir, mask, callback)
  -- Turns Windows mask into regex so all folders would be iterated, but only files would be checked agaist mask.
  local function escapeRegExp(s) 
    return '^'..string.reggsub(s, '[.+?^${}()|[\\]\\\\]', '\\$&'):reggsub('\\*', '.*')..'$'
  end

  -- Using queue instead of recursion to prevent stack overflow errors.
  local queue = {''}
  local regex = mask and escapeRegExp(mask)
  while #queue > 0 do
    local item = table.remove(queue, 1)
    io.scanDir(item == '' and dir or dir..'/'..item, '*', function (fileName, attrs)
      if attrs.isDirectory then
        table.insert(queue, item == '' and fileName or item..'/'..fileName)
      elseif not regex or string.regfind(fileName, regex) then
        local ret = callback(item == '' and fileName or item..'/'..fileName, attrs)
        if ret ~= nil then
          return ret
        end
      end
    end)
  end
end

return ioext