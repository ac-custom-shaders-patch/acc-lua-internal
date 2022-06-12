--[[
  Version of table which is slightly faster than regular table (it keeps track of number of elements
  in its .length property and just in general relies on a fact that it’s a regular table). Has a few
  QOL methods as well.

  Please note: due to the way it works (sometimes removal only changes length without actually removing
  anything to speed things up), you might be able to access elements outside of its size. So don’t check
  for nils to estimate size of an array. And it also means you can’t add new elements by indexing above
  array length as well. This issue could be solved by custom override of indexing operators, but as I’m
  trying everything to make things slightly faster, just use the methods.

  Also, if you want to create an array filled with values, you can use syntax like this: array{ 1, 2, 3 }
  But, again, be careful: constructor would steal that object as a new array without copying, so be sure
  to pass a unique array. This, again, should help with performance.

  All methods with callback receive an additional callbackData argument which they will pass to callbacks
  when calling. You can use it to avoid creating a capture and thus reduce amount of garbage generated.
]]

local _tinsert = table.insert
local _tremove = table.remove
local _mmax = math.max
local _mmin = math.min
local _mfloor = math.floor
local _mrandom = math.random
local _tclear = require('table.clear')
local _tisarray = require('table.isarray')
local _dtable = {}

---@alias ArrayInitMapCallback nil|fun(item: any): any

---@class Array : ClassBase
---@field length integer
local Array = class('Array', class.NoInitialize)

---@param table nil|any[]
---@param mapCallback ArrayInitMapCallback
---@param mapCallbackData any
---@return Array
function Array.allocate(table, mapCallback, mapCallbackData)
  if table == nil then return { length = 0 } end
  if type(table) == 'table' then
    local l = #table
    if mapCallback ~= nil then
      local n, ni = {}, 1
      for i = 1, l do
        local j = mapCallback(table[i], i, mapCallbackData)
        if j ~= nil then
          n[ni], ni = j, ni + 1
        end
      end
      n.length = ni - 1
      return n
    else
      table.length = l
      return table
    end
  elseif type(table) == 'number' then
    return { length = table }
  else
    error('Unexpected argument: '..type(table))
  end
end

local function outArray(out, length)
  if out == nil then return Array(length) end
  if out.length ~= nil then out.length = length or 0 end
  return out
end

function Array.isArray(obj)
  return getmetatable(obj) == Array
end

-- Turning to string JS style.
function Array:__tostring() return '['..self:join()..']' end

-- Use #arrayInstance or arrayInstance.length to get the length.
function Array:__len() return self.length end

--[[
  Basic array-altering operations.
]]

---Returns an element or nil if element is outside of boundaries.
---@param index integer Index of an element.
function Array:at(index)
  return index and index <= self.length and self[index] or nil
end

---Adds a new item to the array.
---@param item any Item to add.
function Array:push(item)
  local n = self.length + 1
  self.length = n
  self[n] = item
end

-- Adds multiple items to the array.
---@param items Array Item to add.
function Array:pushArray(items)
  local n = self.length
  local m = #items
  for i = 1, m do
    n = n + 1
    self[n] = m[i]
  end
  self.length = n
end

---Inserts a new element to a given position. If position is below one, element will be inserted at the beginning. If it
---exceeds array length, element would be inserted at the end.
---@param index integer Index of where to put the element.
---@param item any Element to add.
function Array:insert(index, item)
  local n = self.length + 1
  if index >= n then
    self[n] = item
  else
    if index < 1 then index = 1 end
    _tinsert(self, index, item)
  end
  self.length = n
end

---Removes last item from the array and returns it.
---@return any Last element.
function Array:pop()
  local n = self.length
  local r = self[n]
  if n > 0 then self.length = n - 1 end
  return r
end

---Returns true if item is in the array.
---@param item any Item to check.
---@return boolean
---@nodiscard
function Array:contains(item)
  for i = 1, self.length do
    if self[i] == item then
      return true
    end
  end
  return false
end

---Returns index of an element or nil if element is missing.
---@param item any Item to check.
---@return integer|nil
---@nodiscard
function Array:indexOf(item)
  for i = 1, self.length do
    if self[i] == item then
      return i
    end
  end
  return nil
end

---Sets length to zero while keeping items, should be faster this way. Optional callback will be called for each element.
---@param itemDisposeCallback fun(item: any, index: integer, callbackData: any)
function Array:clear(itemDisposeCallback, itemDisposeCallbackData)
  if itemDisposeCallback ~= nil then
    self:forEach(itemDisposeCallback, itemDisposeCallbackData)
  end
  self.length = 0
end

---Removes element, returns true if any such element was found. Set keepOrdered to true to swap deleted element with last
---one instead of moving the rest forward, might be faster if you don’t need to maintain order.
---@param item any Item to remove.
---@param unordered boolean? Set to true to operate in faster unordered mode.
function Array:remove(item, unordered)
  local n = self.length
  for i = 1, n do
    if self[i] == item then
      if i < n then
        if unordered then self[i] = self[n]
        else _tremove(self, i) end
      end
      self.length = n - 1
      return true
    end
  end
  return false
end

---Removes element at certain position, returns true there is such an element. Set unordered to true to swap deleted element with last
---one instead of moving the rest forward, might be faster if you don’t need to maintain order.
---@param index integer Index of an item to remove.
---@param unordered boolean? Set to true to operate in faster unordered mode.
function Array:removeAt(index, unordered)
  local n = self.length
  if index > 0 and index <= n then
    if index < n then
      if unordered then self[index] = self[n]
      else _tremove(self, index) end
    end
    self.length = n - 1
    return true
  end
  return false
end

---Removes all elements for which conditionCallback returns true. Set unordered to true to swap deleted element with last
---one instead of moving the rest forward, might be faster if you don’t need to maintain order.
---@param conditionCallback fun(item: any, index: integer, callbackData: any): boolean Filtering callback.
---@param conditionCallbackData any Filtering callback data.
---@param unordered boolean? Set to true to operate in faster unordered mode.
function Array:removeIf(conditionCallback, conditionCallbackData, unordered)
  local n = self.length
  if unordered then
    for i = 1, n do
      if conditionCallback(self[i], i, conditionCallbackData) then
        if i < n then
          self[i] = self[n]
          i = i - 1
        end
        n = n - 1
      end
    end
    self.length = n
  else
    for i = n, 1, -1 do
      if conditionCallback(self[i], i, conditionCallbackData) then
        if i < n then
          _tremove(self, i)
        end
        n = n - 1
      end
    end
    self.length = n
  end
end

---Joins elements to a string using custom separator.
---@param separator string?
---@param toStringCallback fun(item: any, index: integer, callbackData: any): string
---@param toStringCallbackData any?
---@return string
---@nodiscard
function Array:join(separator, toStringCallback, toStringCallbackData)
  if separator == nil then separator = ',' end
  toStringCallback = toStringCallback or tostring
  local n = self.length
  if toStringCallback == nil and n == rawlen(self) then
    return table.concat(self, separator)
  end
  local r = ''
  for i = 1, n do
    if i > 1 then r = r .. separator .. toStringCallback(self[i], i, toStringCallbackData)
    else r = toStringCallback(self[i], i, toStringCallbackData) end
  end
  return r
end

--[[
  Some advanced stuff.
]]

---Removes elements from underlying table until its internal size would match its array length.
function Array:fitToSize()
  local n = self.length
  local r = rawlen(self)
  if n == r then return end
  while n < r do
    self[r] = nil
    r = r - 1
  end
end

---Sorts items in an array using sortCallback.
---@param sortCallback fun(item1: any, item2: any): boolean
function Array:sort(sortCallback)
  self:fitToSize()
  table.sort(self, sortCallback)
end

---Finds first element for which `testCallback` returns true, returns index of an element before it.
---Elements should be ordered in such a way that there would be no more elements returning false to the right
---of an element returning true.
---
---If `testCallback` returns true for all elements, would return 0. If `testCallback` returns false for all,
---returns index of the latest element.
---@param testCallback fun(item: any, index: integer, callbackData: any): boolean
---@param testCallbackData any
---@return integer
---@nodiscard
function Array:findLeftOfIndex(testCallback, testCallbackData)
  local n = self.length
  local i = 0
  while n > 0 do
    local step = _mfloor(n / 2)
    if testCallback(self[i + step + 1], i + step + 1, testCallbackData) then
      n = step
    else
      i = i + step + 1
      n = n - step - 1
    end
  end
  return i
end

---Selects a random element from an array. If optional filterCallback is passed, it would be used as a filter and
---only elements for which it would return true would count. Alternatively, it can return a number to represent a
---weight of each element.
---@param filterCallback fun(item: any, index: integer, callbackData: any): boolean
---@param filterCallbackData any
---@return integer
---@nodiscard
function Array:random(filterCallback, filterCallbackData)
  if filterCallback == nil then
    local i = _mrandom(self.length)
    return self[i], i
  end

  local r, k = nil, nil
  local nc = 0
  for i = 1, self.length do
    local value = self[i]
    local f = filterCallback(value, i, filterCallbackData)
    if f then
      local w = type(f) == 'number' and f or 1
      nc = nc + w
      if w / nc >= _mrandom() then
        r, k = value, i
      end
    end
  end
  return r, k
end

--[[
  Non-modifying non-creating array queries.
]]

---Calls callback for each item in the array.
---@param callback fun(item: any, index: integer, callbackData: any)
---@param callbackData any?
function Array:forEach(callback, callbackData)
  for i = 1, self.length do
    callback(self[i], i, callbackData)
  end
end

---Returns first element for which callback would return true.
---@param callback fun(item: any, index: integer, callbackData: any): boolean
---@param callbackData any?
---@return any
---@nodiscard
function Array:findFirst(callback, callbackData)
  for i = 1, self.length do
    local e = self[i]
    if callback(e, i, callbackData) then
      return e
    end
  end
  return nil
end

---Returns true if there is any element for which callback() returns true.
---@param callback fun(item: any, index: integer, callbackData: any): boolean
---@param callbackData any?
---@return boolean
---@nodiscard
function Array:some(callback, callbackData)
  for i = 1, self.length do
    if callback(self[i], i, callbackData) then
      return true
    end
  end
  return false
end

---Counts number of elements for which callback() returns true.
---@param callback fun(item: any, index: integer, callbackData: any): boolean
---@param callbackData any?
---@return integer
---@nodiscard
function Array:count(callback, callbackData)
  local r = 0
  for i = 1, self.length do
    if callback(self[i], i, callbackData) then
      r = r + 1
    end
  end
  return r
end

---Sums values returned by callback() which is called for every item.
---@param callback fun(item: any, index: integer, callbackData: any): boolean
---@param callbackData any?
---@return integer
---@nodiscard
function Array:sum(callback, callbackData)
  local r = 0
  for i = 1, self.length do
    local v = callback(self[i], i, callbackData)
    if v then
      r = r + v
    end
  end
  return r
end

---Returns false if there is any element for which callback() returns false.
---@param callback fun(item: any, index: integer, callbackData: any): boolean
---@param callbackData any?
---@return boolean
---@nodiscard
function Array:every(callback, callbackData)
  for i = 1, self.length do
    if not callback(self[i], i, callbackData) then
      return false
    end
  end
  return true
end

---Returns value and index of a value for which callback returns the largest number.
---@param callback fun(item: any, index: integer, callbackData: any): number
---@param callbackData any?
---@return any
---@return integer
---@nodiscard
function Array:maxEntry(callback, callbackData)
  local r, k = nil, nil
  local v = -1/0
  for i = 1, self.length do
    local e = self[i]
    local l = callback(e, i, callbackData)
    if l > v then
      v = l
      r, k = e, i
    end
  end
  return r, k
end

---Returns value and index of a value for which callback returns the smallest number.
---@param callback fun(item: any, index: integer, callbackData: any): number
---@param callbackData any?
---@return any
---@return integer
---@nodiscard
function Array:minEntry(callback, callbackData)
  local r, k = nil, nil
  local v = 1/0
  for i = 1, self.length do
    local e = self[i]
    local l = callback(e, i, callbackData)
    if l < v then
      v = l
      r, k = e, i
    end
  end
  return r, k
end

---Same as JavaScript .reduce() method, but starting value goes first.
---@generic T
---@param startingValue T
---@param callback fun(previousValue: T, arrayValue: any, arrayIndex: integer, callbackData: any): T
---@param callbackData any?
---@return T
---@nodiscard
function Array:reduce(startingValue, callback, callbackData)
  local v = startingValue
  for i = 1, self.length do
    v = callback(v, self[i], i, callbackData)
  end
  return v
end

--[[
  Non-modifying methods creating new arrays based on existing one. All methods have an additional
  out argument receiving an array to overwrite if you’d prefer to reuse existing array instead of allocating
  a new one. For some extra special cases, array can also be an output: arrayInstance:distinct(nil, arrayInstance).
]]

---Slices array, basically acts like slicing thing in Python.
---@param from integer Starting index.
---@param to integer? Ending index.
---@param step integer? Step.
---@param out Array? Optional destination.
---@return Array
function Array:slice(from, to, step, out)
  local n = self.length
  local r = outArray(out)
  if from == nil or from == 0 then from = 1 elseif from < 0 then from = n + from else from = _mmax(from, 1) end
  if to == nil or to == 0 then to = n elseif to < 0 then to = n + to else to = _mmin(to, n) end
  if step == nil or step == 0 then step = 1 end
  if step > 0 and to > from or step < 0 and to < from then
    local j = 0
    for i = from, to, step do
      j = j + 1
      r[j] = self[i]
    end
    r.length = j
  end
  return r
end

---Reverses array.
---@param out Array? Optional destination.
---@return Array
function Array:reverse(out)
  local n = self.length
  if out == self then
    local t = math.floor(n / 2)
    for i = 1, t do
      self[i], self[n - i + 1] = self[n - i + 1], self[i]
    end
    return self
  end
  local r = outArray(out, n)
  for i = n, 1, -1 do
    r[n - i + 1] = self[i]
  end
  return r
end

---Makes a copy on an array.
---@param out Array? Optional destination.
---@return Array
function Array:clone(out)
  local n = self.length
  local r = outArray(out, n)
  for i = 1, n do
    r[i] = self[i]
  end
  return r
end

---Calls callback function for each of array elements, creates a new array containing all the resulting values.
---@param callback fun(item: any, index: integer, callbackData: any): any Mapping callback.
---@param callbackData any?
---@param out Array? Optional destination.
---@return Array
function Array:map(callback, callbackData, out)
  local n = self.length
  local r = outArray(out, n)
  for i = 1, n do
    r[i] = callback(self[i], i, callbackData)
  end
  return r
end

---Calls callback function for each of array elements, creates a new table containing all the resulting values.
---@param callback fun(item: any, index: integer, callbackData: any): any, any Mapping callback returning key and value. If either is nil, nothing would be added.
---@param callbackData any?
---@return table
function Array:mapTable(callback, callbackData)
  local n = self.length
  local r = {}
  for i = 1, n do
    local k, v = callback(self[i], i, callbackData)
    if k ~= nil and v ~= nil then r[k] = v end
  end
  return r
end

---Creates a new array out of all elements for which callback returns true.
---@param callback fun(item: any, index: integer, callbackData: any): boolean Filtering callback.
---@param callbackData any?
---@param out Array? Optional destination.
---@return Array
function Array:filter(callback, callbackData, out)
  local n = self.length
  local r = outArray(out)
  local j = 0
  for i = 1, n do
    local e = self[i]
    if callback(e, i, callbackData) then
      j = j + 1
      r[j] = e
    end
  end
  r.length = j
  return r
end

---Removes non-unique elements.
---@param callback fun(item: any, index: integer, callbackData: any): any Optional callback for custom uniqueness estimation (takes element, returns a key).
---@param callbackData any?
---@param out Array? Optional destination.
---@return Array
function Array:distinct(callback, callbackData, out)
  local n = self.length
  local r = outArray(out)
  local h = _dtable
  local j = 0
  for i = 1, n do
    local e = self[i]
    local u = callback and callback(e, i, callbackData) or e
    if u ~= nil then
      if not h[u] then
        h[u] = true
        j = j + 1
        r[j] = e
      end
    end
  end
  _tclear(h)
  r.length = j
  return r
end

---Flattens an array, similar to how it works in JavaScript.
---@param maxLevel integer How deep should flattening go.
---@param out Array? Optional destination.
---@return any
function Array:flatten(maxLevel, out)
  local n = self.length
  local r = outArray(out)
  local j = 0

  local function flattenSub(t, N, levelsLeft)
    for i = 1, N do
      local value = t[i]
      if (type(value) == 'table' and _tisarray(value) or Array.isArray(value)) and levelsLeft > 0 then
        flattenSub(value, #value, levelsLeft - 1)
      else
        j = j + 1
        r[j] = value
      end
    end
  end

  flattenSub(self, n, maxLevel or 1)
  r.length = j
  return r
end

--[[
  Static methods creating new arrays. All methods have an additional out argument receiving an array to overwrite
  if you’d prefer to reuse existing array instead of allocating a new one.
]]

---Calls callback with argument i = from … to, step, collects output to a new array and
---returns it.
---@param to integer
---@param from integer?
---@param step integer?
---@param callback nil|fun(item: integer, callbackData: any): any
---@param callbackData any?
---@param out Array?
---@return Array
function Array.range(to, from, step, callback, callbackData, out)
  if type(from) == 'function' then from, step, callback = 1, 1, from end
  if type(step) == 'function' then step, callback = 1, step end
  to = to or 0
  from = from or 1
  step = step or 1
  local r = outArray(out)
  local j = 0
	for i = from, to, step do
    j = j + 1
		r[j] = callback(i, callbackData)
	end
  r.length = j
  return r
end

---Concatenates arrays together. Word .concat is already used for table.concat, so here we are.
---@param arrays Array[]
---@param out Array
---@return Array
function Array.chain(arrays, out)
  local r = outArray(out)
  local j = 0
  local n1 = #arrays
  for i1 = 1, n1 do
    local a = arrays[i1]
    local n2 = #a
    for i2 = 1, n2 do
      j = j + 1
      r[j] = a[i2]
    end
  end
  r.length = j
  return r
end

-- Some tests.
function Array.runTests()
  local function expect(v, t) if v ~= t then error(string.format('expected %s, got %s', t, v)) end end
  local arr = Array{1, 2, 3, 4}
  arr:removeIf(function (i) return i % 2 == 0 end)
  expect(#arr, 2)
  expect(arr[1], 1)
  expect(arr[2], 3)

  arr = Array()
  arr:push(1)
  expect(#arr, 1)
  arr:removeIf(function (i) return i % 2 == 1 end)
  expect(#arr, 0)

  arr = Array{1, 2, 3, 4}:slice(2, 3)
  expect(#arr, 2)
  expect(arr[1], 2)
  expect(arr[2], 3)

  arr = Array{1, 2, 3, 4}:slice(3, 2, -1)
  expect(#arr, 2)
  expect(arr[1], 3)
  expect(arr[2], 2)

  arr = Array{1, 2, 3, 4}:slice(3, 2)
  expect(#arr, 0)

  expect(Array.isArray(arr), true)
  expect(Array.isArray({}), false)

  expect(Array{1, 2, 1, 3}:join(), '1,2,1,3')
  expect(Array{1, 2, 1, 3}:distinct():join(), '1,2,3')
  expect(Array{1, 2, 1, 3}:distinct(function (i) return i % 2 == 1 end):join(), '1,2')

  arr = Array{1, 2, 1, 3}
  arr:distinct(nil, nil, arr)
  expect(arr:join('.'), '1.2.3')

  expect(Array{1, 2, 3}:reverse():join(), '3,2,1')
  expect(Array{1, 2, 3, 4}:reverse():join(), '4,3,2,1')

  arr = Array{1, 2, 3}
  arr:reverse(arr)
  expect(arr:join('.'), '3.2.1')

  arr = Array{1, 2, 3, 4}
  arr:reverse(arr)
  expect(arr:join('.'), '4.3.2.1')

  expect(Array{1, {2, 3}, 4}:flatten():join(), '1,2,3,4')
  expect(Array{1, Array{2, 3}, 4}:flatten():join(), '1,2,3,4')
  expect(Array{1, {2, Array{3}}, 4}:flatten():join(), '1,2,[3],4')
  expect(Array{1, {2, Array{3}}, 4}:flatten(2):join(), '1,2,3,4')

  local l = { 1, 2, 3, length = 4 }
  table.insert(l, 2, 0)
  expect(Array.join(l), '1,0,2,3')

  arr = Array{1, 2, 3, 4}
  arr:insert(2, 17)
  expect(arr:join(), '1,17,2,3,4')

  expect(Array({1, 2, 3}, function (i) return i * 2 end):join(), '2,4,6')

  -- arr = Array{1, 4, 2}
  -- arr:sort()
  -- expect(arr:join(), '1,2,4')

  arr = Array{1, 4, 2, 3, 1.5}
  arr:pop()
  arr:pop()
  arr:sort()
  expect(arr:join(), '1,2,4')

  arr = Array{1, 4, 2}
  arr:removeAt(2)
  expect(arr[1], 1)
  expect(arr[2], 2)
  expect(arr[3], nil)

  -- arr = Array{0,1,2,3,4,5,6,7,8,9,10}
  -- local v = 0
  -- for i = 1, 10000 do
  --   v = v + arr:random(function(i) return i % 2 == 1 end)
  -- end
  -- ac.debug('Random test', v)
end

Array.runTests()

return class.emmy(Array, Array.allocate)
