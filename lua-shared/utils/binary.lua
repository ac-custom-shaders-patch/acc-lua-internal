
--[[
  Library for simple and fast reading and writing of binary files. Works great with `ac.StructItem` in case you want to read whole structures instead
  of individual entities. Not available to scripts without full I/O access.

  Raises errors when failing to read or write data.

  Please do not fork it and copy it in your project directly, but always load it from “shared/…”: it uses a bit of internal API to better integrate
  to some other functions and be able to map files into RAM instead of loading files the usual way.
]]
---@diagnostic disable

if tostring(debug.gethook):find('function: builtin#', nil, true) ~= 1 then
  -- You can find a workaround, but please don’t waste precious time: this script relies on many things not available to I/O-less scripts. Maybe
  -- in the future it could at least partially support those.
  error('Not available for this type of script')
end

--------------------------------
-- Generic stuff used by both --
--------------------------------

---@diagnostic disable: invisible

---Namespace with some functions helpful for reading and writing binary data and files.
local binaryUtils = {}

local types = {
  bool = ffi.typeof('bool*'), ---@type boolean
  float = ffi.typeof('float*'), ---@type number
  double = ffi.typeof('double*'), ---@type number
  int8 = ffi.typeof('int8_t*'), ---@type integer
  uint8 = ffi.typeof('uint8_t*'), ---@type integer
  int16 = ffi.typeof('int16_t*'), ---@type integer
  uint16 = ffi.typeof('uint16_t*'), ---@type integer
  int32 = ffi.typeof('int32_t*'), ---@type integer
  uint32 = ffi.typeof('uint32_t*'), ---@type integer
  int64 = ffi.typeof('int64_t*'), ---@type integer
  uint64 = ffi.typeof('uint64_t*'), ---@type integer
  vec2 = ffi.typeof('vec2*'), ---@type vec2
  vec3 = ffi.typeof('vec3*'), ---@type vec3
  vec4 = ffi.typeof('vec4*'), ---@type vec4
  rgb = ffi.typeof('rgb*'), ---@type rgb
  rgbm = ffi.typeof('rgbm*'), ---@type rgbm
  hsv = ffi.typeof('hsv*'), ---@type hsv
  mat3x3 = ffi.typeof('mat3x3*'), ---@type mat3x3
  mat4x4 = ffi.typeof('mat4x4*'), ---@type mat4x4
}

---@type fun(start: any, end: any): binary
local _t_blobview = ffi.typeof('blob_view')

local function _mmfGC(item)
  if type(item) ~= 'cdata' then return end
  ffi.gc(item, nil)
  ffi.C.lj_connectmmf_gc(ffi.cast('void*', item))
end

local _structCache = setmetatable({}, {__mode = 'k'})
local _longString = '________________________________________________________________'

---@param targetType string|table
---@return {[1]: ffi.ctype*, [2]: integer}
local function _typeInfo(targetType)
  local h = _structCache[targetType]
  if h == nil then
    local t = ffi.typeof(targetType)
    h = {t, ffi.sizeof(t)}
    _structCache[targetType] = h
  end
  return h
end

---------------------------
-- Binary reader section --
---------------------------

---@param self binaryUtils.BinaryReader
---@param count integer
---@param resetCurTo integer?
---@return integer
local function _readerRequire(self, count, resetCurTo)
  local updatedCur = self.__cur + count
  local c = self.__size - updatedCur
  if c < 0 then 
    if resetCurTo then self.__cur = resetCurTo end
    error('Not enough data: %s bytes missing' % c, 3)
  end
  return updatedCur
end

---@param self binaryUtils.BinaryReader
---@param count integer
---@param resetCurTo integer?
---@return ffi.ct*
local function _readerAdvance(self, count, resetCurTo)
  local c = self.__cur
  self.__cur = _readerRequire(self, count, resetCurTo)
  return self.__data + c
end

---@generic T
---@param self binaryUtils.BinaryReader
---@param typeInfo T
---@param typeSize integer
---@return T
local function _readType(self, typeInfo, typeSize)
  local c = self.__cur
  self.__cur = _readerRequire(self, typeSize)
  return ffi.cast(typeInfo, self.__data + c)[0]
end

---@class binaryUtils.BinaryReader
---@field private __cur integer
---@field private __size integer
---@field private __data any
---@field private __release fun()?
---@field private __blobify fun()?
local _readMt_index = {}

---Returns 0-based offset of a cursor.
---@return integer
function _readMt_index:offset() return self.__cur end

---Returns total size in bytes.
---@return integer
function _readMt_index:size() return self.__size end

---Returns number of bytes left to read.
---@return integer
function _readMt_index:remaining() return self.__size - self.__cur end

---Returns `true` if there is no more data left.
---@return boolean
function _readMt_index:finished() return self.__cur >= self.__size end

---Moves cursor to a different point in a file. Raises an error if final position is below 0 or exceeds file size.
---@param offset integer
---@param relative nil|true|'start'|'cursor'|'end' @Pass `true` to offset relative to cursor. By default offsets from the start.
---@return self
function _readMt_index:seek(offset, relative)
  if offset then
    local curNew = relative == 'end' and self.__size + offset or (relative and relative ~= 'start') and self.__cur + offset or offset
    if curNew < 0 or curNew >= self.__size then error('New position is out of boundaries: '..curNew, 2) end
    self.__cur = curNew
  end
  return self
end

---Reads `size` bytes and returns as a string.
---@param size integer
---@return string
---@overload fun(): string @If `size` is not specified, all the remaining data will be read.
function _readMt_index:raw(size)
  if not size then size = self:remaining() end
  return ffi.string(_readerAdvance(self, size), size)
end

---Be extra careful with this method! Better yet, don’t use it at all.
---
---Similar to `:raw()`, reads `size` bytes and returns as a binary view. However, there are three main differences:
---- Views don’t hold data and only refer to data in the parent reader.
---- That means creating a view doesn’t involve copying data around.
---- The moment parent `binaryUtils.BinaryReader` expires, all become views become not just expired, but cursed, and any interaction with them will lead to the crash at best. Be careful!
---- Views can’t be dealt with directly, but you can create new `binaryUtils.BinaryReader` instances to read data from them.
---- Main point of views is that they can be passed to CSP API if argument type is `binary` with zero overhead.
---
---So, as an example, if your binary file has a header followed by, let’s say, compressed data, you can simply pass the data to `ac.decompress()` like so:
---```
---local decompressedData = ac.decompress(mainFile:view())
---local decompressedReader = binaryUtils.process(decompressedData)
---```
---@param size integer
---@return binary
---@overload fun(): binary @If `size` is not specified, all the remaining data will be read.
function _readMt_index:view(size)
  if not size then size = self:remaining() end
  local c = _readerAdvance(self, size)
  return _t_blobview(c, c + size)
end

---Reads next byte without proceeding further.
---@return integer? @Returns `nil` if end has been reached.
function _readMt_index:peek()
  return self.__cur < self.__size and self.__data[self.__cur] or nil
end

---Returns `true` if `pattern` matches bytes coming next. Doesn’t proceed further. Helpful if you want to quickly compare a file header, for example.
---@param pattern string
---@return boolean
function _readMt_index:match(pattern)
  if self.__cur + #pattern > self.__size then return false end
  local o = self.__data + self.__cur - 1
  for i = 1, #pattern do
    if pattern:byte(i) ~= o[i] then return false end
  end
  return true
end

local _readerSizeMeasure

---@return integer
local function _computeReaderSize(targetType)
  if not targetType then return 1 end
  local h = _structCache[targetType]
  if h then return h[2] end
  if type(targetType) == 'cdata' or type(targetType) == 'string' then
    return _typeInfo(targetType)[2]
  end
  if type(targetType) == 'function' then
    if not _readerSizeMeasure then
      _readerSizeMeasure = setmetatable({__cur = 0, __size = 64, __data = ffi.cast('char*', _longString)}, _readMt_index)
    end
    _readerSizeMeasure.__cur = 0
    targetType(_readerSizeMeasure)
    _structCache[targetType] = {0, _readerSizeMeasure.__cur}
    return _readerSizeMeasure.__cur
  end
  error('Supported types: function, cdata, string', 3)
end

---Returns `true` if there are at least `size` bytes (or entities) left to read. Doesn’t progress cursor further.
---@param targetType nil|table|string|fun(s: binaryUtils.BinaryReader): any @Could be a `ac.StructItem.combine()` output, a structure name, a data-reading `binaryUtils.BinaryReader` method or `nil` if you want to read a single char.
---@param size integer? @Default value: 1.
---@return boolean @Returns `false` if there is not enough data.
---@overload fun(s: binaryUtils.BinaryReader, size: integer): boolean
function _readMt_index:has(size, targetType)
  if type(targetType) == 'number' then
    targetType, size = nil, targetType
  end
  size = tonumber(size) or 1
  if size <= 0 then
    return true
  end
  if targetType then
    size = size * _computeReaderSize(targetType)
  end
  return self.__cur + size <= self.__size
end

---Skips specified number of bytes (or entities). Raises an error if there is not enough data.
---@param targetType nil|table|string|fun(s: binaryUtils.BinaryReader): any @Could be a `ac.StructItem.combine()` output, a structure name, a data-reading `binaryUtils.BinaryReader` method or `nil` if you want to read a single char.
---@param size integer? @Default value: 1.
---@return self
---@overload fun(s: binaryUtils.BinaryReader, size: integer): binaryUtils.BinaryReader
function _readMt_index:skip(targetType, size)
  if type(targetType) == 'number' then
    targetType, size = nil, targetType
  end
  size = tonumber(size) or 1
  if size > 0 then
    if targetType then
      size = size * _computeReaderSize(targetType)
    end
    self.__cur = _readerRequire(self, size)
  end
  return self
end

function _readMt_index:bool() return _readType(self, types.bool, 1) end
function _readMt_index:float() return _readType(self, types.float, 4) end
function _readMt_index:double() return _readType(self, types.double, 8) end
function _readMt_index:int8() return _readType(self, types.int8, 1) end
function _readMt_index:uint8() return _readType(self, types.uint8, 1) end
function _readMt_index:int16() return _readType(self, types.int16, 2) end
function _readMt_index:uint16() return _readType(self, types.uint16, 2) end
function _readMt_index:int32() return _readType(self, types.int32, 4) end
function _readMt_index:uint32() return _readType(self, types.uint32, 4) end
function _readMt_index:int64() return _readType(self, types.int64, 8) end
function _readMt_index:uint64() return _readType(self, types.uint64, 8) end
function _readMt_index:vec2() return _readType(self, types.vec2, 8) end
function _readMt_index:vec3() return _readType(self, types.vec3, 12) end
function _readMt_index:vec4() return _readType(self, types.vec4, 16) end
function _readMt_index:rgb() return _readType(self, types.rgb, 12) end
function _readMt_index:rgbm() return _readType(self, types.rgbm, 16) end
function _readMt_index:hsv() return _readType(self, types.hsv, 12) end
function _readMt_index:quat() return _readType(self, types.quat, 16) end
function _readMt_index:mat3x3() return _readType(self, types.mat3x3, 36) end
function _readMt_index:mat4x4() return _readType(self, types.mat4x4, 64) end

_readMt_index.char = _readMt_index.int8
_readMt_index.byte = _readMt_index.uint8

function _readMt_index:half() return ac.decodeHalf(self:uint16()) end
function _readMt_index:norm8() return self:int8() / 127 end
function _readMt_index:unorm8() return self:uint8() / 255 end
function _readMt_index:norm16() return self:int16() / 32767 end
function _readMt_index:unorm16() return self:uint16() / 65535 end

---Create a new struct using `ac.StructItem.combine()` and pass it here as a template, and this method will create a new
---copy with data from the file.
---@generic T
---@param targetType T @Could be a `ac.StructItem.combine()` output, a structure name, a data-reading `binaryUtils.BinaryReader` method or `nil` if you want to read a single char.
---@return T
function _readMt_index:struct(targetType)
  if type(targetType) == 'function' then
    return targetType(self)
  end
  if type(targetType) ~= 'cdata' and type(targetType) ~= 'string' then
    if not targetType then
      return self:char()
    end
    error('Supported types: function, cdata, string')
  end
  local h = _typeInfo(targetType)
  local c = _readerAdvance(self, h[2])
  local r = ffi.new(h[1])
  ffi.copy(r, c, h[2])
  return r
end

---Create a new array using either a structure similar to `:struct()`, or you can pass a type-reading method (as long as it doesn’t take arguments).
---A bit more efficient than reading lists on your side, and will return `nil` instantly if there is not enough data.
---@generic T
---@param targetType T @Could be a `ac.StructItem.combine()` output, a structure name, a data-reading `binaryUtils.BinaryReader` method or `nil` if you want to read a single char.
---@param size integer? @If not set, next 4-byte integer will be read (common AC arrays format).
---@return T[]
function _readMt_index:array(targetType, size)
  if size == nil then
    size = self:int32()
  end
  if size <= 0 then
    return {}
  end
  local curBak = self.__cur
  local ret = table.new(size, 0)
  if type(targetType) == 'function' then
    ret[1] = targetType(self)
    local requiredSize = (self.__cur - curBak) * (size - 1)
    _readerRequire(self, requiredSize, curBak)
    for i = 2, size do
      ret[i] = targetType(self)
    end
  elseif targetType then
    if type(targetType) ~= 'cdata' and type(targetType) ~= 'string' then
      error('Supported types: function, cdata, string')
    end
    local h = _typeInfo(targetType)
    local c = _readerAdvance(self, h[2] * size, curBak)
    for i = 1, size do
      local e = ffi.new(h[1])
      ffi.copy(e, c + (i - 1) * h[2], h[2])
      ret[i] = e
    end
  else
    local c = _readerAdvance(self, size, curBak)
    for i = 1, size do
      ret[i] = c + (i - 1)
    end
  end
  return ret
end

---Reads next string using a common AC format: four bytes for its length following by the actual content.
---@return string
function _readMt_index:string()
  local b = self.__cur
  local l = self:int32()
  return ffi.string(_readerAdvance(self, l, b), l)
end

function _readMt_index:__blobify()
  return self.__data, self.__size
end

---Disposes reader and closes any associated data. Doesn’t have to be called unless you want to close the file earlier, GC can take care of things too.
---Empties data so any future read calls won’t return anything.
function _readMt_index:dispose()
  if self.__release then
    self.__release(self)
    self.__release = nil
  end
  self.__data = ffi.cast('char*', _longString)
  self.__cur, self.__size = 0, 0
end

local _readMt = {
  __len = function (s) return s.__size end,
  __index = _readMt_index
}

local function _finalizeReader(ret)
  return setmetatable(ret, _readMt)
end

---Try to read a file on a disk using memory mapping for faster access. File will be locked until `:dispose()` is called. Raises an error if failed to open a file.
---@param filename string @Full filename.
---@return binaryUtils.BinaryReader
function binaryUtils.readFile(filename)
  local m = ffi.C.lj_connectmmf_new('\\~$$FS\\'..filename, 0, false)
  if m == nil then error('Failed to read a file', 2) end
  return _finalizeReader{
    __data = ffi.gc(m, _mmfGC),
    __cur = 0,
    __size = __util.native('io.lastMMFSize'),
    __release = function (o)
      o, o.__data = o.__data, nil
      _mmfGC(o)
    end
  }
end

---Read something (string, `ac.StructItem`, something like `ac.connect`) as binary data.
---@param data binary @Any binary data in a form of a string.
---@return binaryUtils.BinaryReader
function binaryUtils.readData(data)
  if type(data) ~= 'string' then
    if data == nil then
      error('Data is missing', 2)
    end
    local b = __util.cdata_blob(data)
    return _finalizeReader{
      __hold = {data, b},
      __data = b.p_begin,
      __cur = 0,
      __size = b.p_end - b.p_begin
    }
  end
  return _finalizeReader{
    __hold = data,
    __data = ffi.cast('char*', data),
    __cur = 0,
    __size = #data
  }
end

---------------------------
-- Binary writer section --
---------------------------

---@param s binaryUtils.BinaryWriter
---@param size integer
local function _fit(s, size)
  local c = s.__cur
  local n = c + size
  s.__cur = n
  if n > s.__size then
    if n > s.__capacity then
      s.__capacity = math.max(math.ceil(s.__capacity * 1.6), n) + 32
      if s.__reallocate then
        s:__reallocate()
      else
        error('Too much data to fit into a file')
      end
    end
    s.__size = n
  end
  return c
end

---@generic T
---@param s binaryUtils.BinaryWriter
---@param t T
---@param z integer
---@param v T
---@return binaryUtils.BinaryWriter
local function _writeType(s, t, z, v)
  local c = _fit(s, z)
  ffi.cast(t, s.__data + c)[0] = v
  return s
end

---@class binaryUtils.BinaryWriter
---@field private __cur integer
---@field private __capacity integer
---@field private __size integer
---@field private __data any
---@field private __reallocate fun()?
---@field private __release fun()?
---@field private __blobify fun()?
local _writeMt_index = {}

---Returns 0-based offset of a cursor.
---@return integer
function _writeMt_index:offset() return self.__cur end

---Returns total size in bytes.
---@return integer
function _writeMt_index:size() return self.__size end

---Returns total capacity in bytes. If created with `.writeData()`, more space will be allocated once the capacity has been exceeded.
---@return integer
function _writeMt_index:capacity() return self.__size end

---Returns number of bytes left to write until full. If created with `.writeData()`, more space will be allocated once the end is reached.
---@return integer
function _writeMt_index:remaining() return self.__capacity - self.__cur end

---Returns `true` if there is no more space left. If finished but created with `.writeData()`, more space will be allocated with the next write.
---@return boolean
function _writeMt_index:finished() return self.__cur >= self.__size end

---Moves cursor to a different point in a file. Raises an error if final position is below 0 or exceeds file size (if created with `.writeFile()`).
---@param offset integer
---@param relative nil|true|'start'|'cursor'|'end'|'capacity' @Pass `true` to offset relative to cursor. By default offsets from the start.
---@return self
function _writeMt_index:seek(offset, relative)
  if offset then
    local curNew = relative == 'capacity' and self.__capacity + offset or relative == 'end' and self.__size + offset or (relative and relative ~= 'start') and self.__cur + offset or offset
    if curNew < 0 or curNew >= (self.__reallocate and math.huge or self.__capacity) then error('New position is out of boundaries: '..curNew, 2) end
    self.__cur = curNew
  end
  return self
end

---Writes data directly.
---@param data binary
---@return self
function _writeMt_index:raw(data)
  if type(data) == 'string' then
    local c = _fit(self, #data)
    ffi.copy(self.__data + c, data, #data)
  else
    local b = __util.cdata_blob(data)
    local s = b.p_end - b.p_begin
    local c = _fit(self, s)
    ffi.copy(self.__data + c, b.p_begin, s)
  end
  return self
end

---Reads next byte without proceeding further.
---@return integer? @Returns `nil` if there are no more written bytes ahead.
function _writeMt_index:peek()
  return self.__cur < self.__size and self.__data[self.__cur] or nil
end

local _writerSizeMeasure

---@return integer
local function _computeWriterSize(targetType)
  if not targetType then return 1 end
  local h = _structCache[targetType]
  if h then return h[2] end
  if type(targetType) == 'cdata' or type(targetType) == 'string' then
    return _typeInfo(targetType)[2]
  end
  if type(targetType) == 'function' then
    if not _writerSizeMeasure then
      _writerSizeMeasure = setmetatable({__cur = 0, __size = 64, __capacity = 64, __data = ffi.cast('char*', _longString)}, _writeMt_index)
    end
    _writerSizeMeasure.__cur = 0
    targetType(_writerSizeMeasure)
    _structCache[targetType] = {0, _writerSizeMeasure.__cur}
    return _writerSizeMeasure.__cur
  end
  error('Supported types: function, cdata, string', 3)
end

---Returns `true` if there are at least `size` bytes (or entities) left to write within capacity. Doesn’t progress cursor further.
---@param targetType nil|table|string|fun(s: binaryUtils.BinaryReader): any @Could be a `ac.StructItem.combine()` output, a structure name, a data-writing `binaryUtils.BinaryWriter` method or `nil` if you want to read a single char.
---@param size integer? @Default value: 1.
---@return boolean @Returns `false` if there is not enough data.
---@overload fun(s: binaryUtils.BinaryReader, size: integer): boolean
function _writeMt_index:has(size, targetType)
  if type(targetType) == 'number' then
    targetType, size = nil, targetType
  end
  size = tonumber(size) or 1
  if size <= 0 then
    return true
  end
  if targetType then
    size = size * _computeWriterSize(targetType)
  end
  return self.__cur + size <= self.__size
end

---Skips specified number of bytes (or entities). Fills space with zeroes. If for who knows what reason you want to keep existing data, use `:seek(offset, 'cursor')` instead, but it could leave you with
---garbage data. 
---@param targetType nil|table|string|fun(s: binaryUtils.BinaryReader): any @Could be a `ac.StructItem.combine()` output, a structure name, a data-writing `binaryUtils.BinaryWriter` method or `nil` if you want to read a single char.
---@param size integer? @Default value: 1.
---@return self
---@overload fun(s: binaryUtils.BinaryReader, size: integer): binaryUtils.BinaryReader
function _writeMt_index:skip(size, targetType)
  if type(targetType) == 'number' then
    targetType, size = nil, targetType
  end
  size = tonumber(size) or 1
  if size > 0 then
    if targetType then
      size = size * _computeWriterSize(targetType)
    end
    local c = _fit(self, size)
    ffi.fill(self.__data + c, size, 0)
  end
  return self
end

---@param value boolean
function _writeMt_index:bool(value) return _writeType(self, types.bool, 1, value) end
---@param value number
function _writeMt_index:float(value) return _writeType(self, types.float, 4, value) end
---@param value number
function _writeMt_index:double(value) return _writeType(self, types.double, 8, value) end
---@param value integer
function _writeMt_index:int8(value) return _writeType(self, types.int8, 1, value) end
---@param value integer
function _writeMt_index:uint8(value) return _writeType(self, types.uint8, 1, value) end
---@param value integer
function _writeMt_index:int16(value) return _writeType(self, types.int16, 2, value) end
---@param value integer
function _writeMt_index:uint16(value) return _writeType(self, types.uint16, 2, value) end
---@param value integer
function _writeMt_index:int32(value) return _writeType(self, types.int32, 4, value) end
---@param value integer
function _writeMt_index:uint32(value) return _writeType(self, types.uint32, 4, value) end
---@param value integer
function _writeMt_index:int64(value) return _writeType(self, types.int64, 8, value) end
---@param value integer
function _writeMt_index:uint64(value) return _writeType(self, types.uint64, 8, value) end
---@param value vec2
function _writeMt_index:vec2(value) return _writeType(self, types.vec2, 8, value) end
---@param value vec3
function _writeMt_index:vec3(value) return _writeType(self, types.vec3, 12, value) end
---@param value vec4
function _writeMt_index:vec4(value) return _writeType(self, types.vec4, 16, value) end
---@param value rgb
function _writeMt_index:rgb(value) return _writeType(self, types.rgb, 12, value) end
---@param value rgbm
function _writeMt_index:rgbm(value) return _writeType(self, types.rgbm, 16, value) end
---@param value hsv
function _writeMt_index:hsv(value) return _writeType(self, types.hsv, 12, value) end
---@param value quat
function _writeMt_index:quat(value) return _writeType(self, types.quat, 16, value) end
---@param value mat3x3
function _writeMt_index:mat3x3(value) return _writeType(self, types.mat3x3, 36, value) end
---@param value mat4x4
function _writeMt_index:mat4x4(value) return _writeType(self, types.mat4x4, 64, value) end

_writeMt_index.char = _writeMt_index.int8
_writeMt_index.byte = _writeMt_index.uint8

---@param value number
function _writeMt_index:half(value) return self:uint16(ac.encodeHalf(value)) end
---@param value number
function _writeMt_index:norm8(value) return self:int8(math.clampN(value, -1, 1) * 127) end
---@param value number
function _writeMt_index:unorm8(value) return self:uint8(math.saturateN(value) * 255) end
---@param value number
function _writeMt_index:norm16(value) return self:int16(math.clampN(value, -1, 1) * 32767) end
---@param value number
function _writeMt_index:unorm16(value) return self:uint16(math.saturateN(value) * 65535) end

---Writes a structure.
---@param data table|vec2|vec3|vec4|rgb|rgbm|hsv|quat|mat3x3|mat4x4 @Items could be a `ac.StructItem.combine()` output, or a structure such as a vec3.
---@return self
function _writeMt_index:struct(data)
  local h = _typeInfo(data)[2]
  local c = _fit(self, h)
  ffi.copy(self.__data + c, data, h)
  return self
end

---Writes array of entities.
---@generic T
---@param values T[] @Items could be a `ac.StructItem.combine()` output, or a structure such as a vec3.
---@param sizePrefix boolean? @If set, first four bytes with array size will be written.
---@return self
function _writeMt_index:array(values, sizePrefix)
  local startIndex = next(values)
  if startIndex == 0 or startIndex == 1 then
    local endIndex = #values
    local len = 1 + #values - startIndex
    local item = values[startIndex]
    if type(item) ~= 'cdata' then error('Unsupported data type', 2) end
    local itemSize = _typeInfo(item)[2]
    local fit = _fit(self, (sizePrefix and 4 or 0) + len * itemSize)
    if sizePrefix then
      ffi.cast(types.int32, self.__data + fit)[0] = len
    end
    local c = self.__data + (sizePrefix and fit + 4 or fit)
    for i = startIndex, endIndex do
      ffi.copy(c, values[i], itemSize)
      c = c + itemSize
    end
  elseif sizePrefix then
    self:int32(0)
  end
  return self
end

---Writes a string using a common AC format: 4 bytes for length and then the data.
---@param data any
---@return binaryUtils.BinaryWriter
function _writeMt_index:string(data)
  if type(data) == 'string' then
    local s = #data
    local c = _fit(self, 4 + s)
    ffi.cast(types.int32, self.__data + c)[0] = s
    ffi.copy(self.__data + (c + 4), data, s)
  else
    local b = __util.cdata_blob(data)
    local s = b.p_end - b.p_begin
    local c = _fit(self, 4 + s)
    ffi.cast(types.int32, self.__data + c)[0] = s
    ffi.copy(self.__data + (c + 4), b.p_begin, s)
  end
  return self
end

---Appends a string or binary data without any size prefixes.
---@param data any
---@return binaryUtils.BinaryWriter
function _writeMt_index:append(data)
  if type(data) == 'string' then
    local s = #data
    local c = _fit(self, s)
    ffi.copy(self.__data + c, data, s)
  else
    local b = __util.cdata_blob(data)
    local s = b.p_end - b.p_begin
    local c = _fit(self, s)
    ffi.copy(self.__data + c, b.p_begin, s)
  end
  return self
end

function _writeMt_index:__blobify()
  return self.__data, self.__size
end

---Disposes reader and closes any associated data. Doesn’t have to be called unless you want to close the file earlier, GC can take care of things too.
---Empties data so any future read calls won’t return anything.
function _writeMt_index:dispose()
  if self.__release then
    self.__release(self)
    self.__release = nil
  end
  self.__data = nil
  self.__reallocate = nil  
  self.__cur, self.__size, self.__capacity = 0, 0, 0
end

---Create a new `binaryUtils.BinaryReader` in the same position (with optional offset). Raises an error if position is below 0 or exceeds current file capacity.
---@param offset integer? @If not specified, current cursor position will be used.
---@param relative nil|true|'start'|'cursor'|'end'|'capacity' @Pass `true` to offset relative to cursor. By default offsets from the start.
function _writeMt_index:read(offset, relative)
  return _finalizeReader{
    __hold = self,
    __data = self.__data,
    __cur = offset
      and math.clamp(relative == 'capacity' and self.__capacity + offset or relative == 'end' and self.__size + offset or (relative and relative ~= 'start') and self.__cur + offset or offset, 0, self.__capacity)
      or self.__cur,
    __size = self.__capacity
  }
end

---Store all content in a file. Raises an error if failed to save.
---@param filename string @Full filename.
---@return self
function _writeMt_index:commit(filename)
  local m = ffi.C.lj_connectmmf_new('\\~$$FS\\'..filename, self.__size, true)
  if m == nil then
    error('Failed to save file', 2)
  end
  if self.__size > 0 then
    pcall(ffi.copy, m, self.__data, self.__size)
  end
  _mmfGC(m)
  return self
end

---Return all content as a string. Alternatively, you can use `:read(0):raw()`. Note: you can pass this writer (or reader) to functions expecting `binary` directly.
---@return string
function _writeMt_index:stringify()
  return ffi.string(self.__data, self.__size)
end

---Clear writer without deallocating memory.
---@return self
function _writeMt_index:clear()
  self.__cur = 0
  self.__size = 0
  return self
end

local _writeMt = {
  __len = function (s) return s.__size end,
  __index = _writeMt_index
}

local function _finalizeWriter(ret, setGC)
  if setGC and ret.__release then
    ret.__proxy = newproxy(true)
    getmetatable(ret.__proxy).__gc = function() ret.__release(ret) end
  end
  return setmetatable(ret, _writeMt)
end

---Create and write a new file. Pros: with this function writer will store things directly to a disk. Cons: you have to know size of your
---file beforehand unless you only need to edit a few bytes here and there. Raises an error if failed to create or open a file.
---@param filename string @Full filename.
---@param size integer? @File size. If not set, current file size will be used (and if there is no such file, an error will be raised).
---@return binaryUtils.BinaryWriter
function binaryUtils.writeFile(filename, size)
  -- TODO: Unknown size case
  local m = ffi.C.lj_connectmmf_new('\\~$$FS\\'..filename, tonumber(size) or -1, true) or error('Failed to write a file', 2)
  return _finalizeWriter{
    __data = ffi.gc(m, _mmfGC),
    __size = 0,
    __capacity = (tonumber(size) or -1) < 0 and __util.native('io.lastMMFSize') or tonumber(size),
    __cur = 0,
    __release = function (o)
      o, o.__data = o.__data, nil
      _mmfGC(o)
    end
  } or m
end

---Write binary stuff into memory, occasionally allocating more and more space as new data gets added. Can grow to any size, but saving things
---to disk will require a copy (not that it matters that much though).
---@param sizeHint integer? @Specify amount of bytes to allocate from the start. Default value: 256 (can’t be less than that).
---@return binaryUtils.BinaryWriter
function binaryUtils.writeData(sizeHint)
  sizeHint = math.max(256, tonumber(sizeHint) or 0)
  return _finalizeWriter({
    __data = ffi.cast('char*', ffi.C.lj_calloc(1, sizeHint)),
    __size = 0,
    __capacity = sizeHint,
    __cur = 0,
    __reallocate = function (o)
      o.__data = ffi.cast('char*', ffi.C.lj_realloc(o.__data, o.__capacity))
    end,
    __release = function (o)
      o, o.__data = o.__data, nil
      if o ~= nil then ffi.C.lj_free2(o, 'b') end
    end
  }, true)
end

return binaryUtils