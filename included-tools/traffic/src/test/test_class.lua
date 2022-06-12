---@diagnostic disable: undefined-field
local generic_utils = require "src/generic_utils"

-- naive capture: 2.6 ms, 288 KB of garbage
function TestBasic(v1, v2)
  return {
    doItsThing = function (self, arg)
      return arg > v2 and arg + v1 or -v2
    end
  }
end

-- inline metatable: 3.6 ms, 110 KB of garbage
function TestInlineMetatable(v1, v2)
  return setmetatable({ v1 = v1, v2 = v2 }, {
    __index = {
      doItsThing = function (self, arg)
        return arg > self.v2 and arg + self.v1 or -self.v2
      end
    }
  })
end

-- proper metatable: 1.4 ms, 167 KB of garbage
local _testMt = {
  __index = {
    doItsThing = function (self, arg)
      return arg > self.v2 and arg + self.v1 or -self.v2
    end
  }
}
function TestProperMetatable(v1, v2)
  return setmetatable({ v1 = v1, v2 = v2 }, _testMt)
end

-- middleclass: 2.1 ms, 620 KB of garbage
local middleclass = require('src/test/middleclass')
local TestMiddleclass = middleclass('TestMiddleclass')

function TestMiddleclass:initialize(v1, v2)
  self.v1 = v1
  self.v2 = v2
end

function TestMiddleclass:doItsThing(arg)
  return arg > self.v2 and arg + self.v1 or -self.v2
end

-- own solution: 1.4 ms, 140 KB of garbage
local function class2(name, super)
  local ret
  local base = {
    __className = name,
    super = super,
    allocate = function() return {} end,
    new = function (_, ...) return _ == ret and ret(...) or ret(_, ...) end,
    subclass = function (self, name) return class2(name, self) end,
    isSubclassOf = function (self, parent)
      while true do
        local mt = getmetatable(self)
        self = mt and mt.__index
        if self == parent then return true end
        if self == nil then return false end
      end
    end,
    isInstanceOf = function (self, parent) return self.__index == parent or self.__index:isSubclassOf(parent) end,
    include = function (self, mixin) 
      for key, value in pairs(mixin) do
        if key == 'included' then value(self) else self[key] = value end
      end
      return self
    end,
    __tostring = super ~= nil and super.__tostring or function (self) return 'instance of class '..self.__index.__className end,
    __call = super and super.__call
  }
  ret = setmetatable(base, {
    __call = function(self, ...)
      local ret = setmetatable(self.allocate(...), self)
      if ret.initialize ~= nil then ret:initialize(...) end
      return ret
    end,
    __index = super,
    __tostring = function (self) return 'class '..self.__className end
  })
  ret.__index = ret
  ret.class = ret
  if super ~= nil and super.subclassed ~= nil then super.subclassed(ret) end
  return ret
end


local TestCustom = class2('TestCustom')

function TestCustom.allocate(v1, v2)
  return { v1 = v1, v2 = v2 }
end

function TestCustom:doItsThing(arg)
  return arg > self.v2 and arg + self.v1 or -self.v2
end

local TestCustomBuiltIn = class('TestCustomBuiltIn', function (v1, v2)
  return { v1 = v1, v2 = v2 }
end, class.NoInitialize)

function TestCustomBuiltIn:doItsThing(arg)
  return arg > self.v2 and arg + self.v1 or -self.v2
end

local TestCustomBuiltIn2 = class('TestCustomBuiltIn2')

function TestCustomBuiltIn2:initialize(v1, v2)
  self.v1 = v1
  self.v2 = v2
end

function TestCustomBuiltIn2:doItsThing(arg)
  return arg > self.v2 and arg + self.v1 or -self.v2
end

local TestCustomBuiltIn3 = class('TestCustomBuiltIn3', function (v1, v2) return table.new(0, 2) end)

function TestCustomBuiltIn3:initialize(v1, v2)
  self.v1 = v1
  self.v2 = v2
end

function TestCustomBuiltIn3:doItsThing(arg)
  return arg > self.v2 and arg + self.v1 or -self.v2
end

local TestCustomBuiltRec = class('TestCustomBuiltRec', class.Pool, function (self, v1, v2)
  self.v1 = v1
  self.v2 = v2
end)

-- function TestCustomBuiltRec:initialize(v1, v2)
-- end

function TestCustomBuiltRec:dispose()
  class.recycle(self)
end

function TestCustomBuiltRec:doItsThing(arg)
  return arg > self.v2 and arg + self.v1 or -self.v2
end

if true then
  return function ()
    collectgarbage()
    local v = 1
    for j = 1, 10000 do
      local t = TestCustomBuiltIn3(17.4, 12.1 + j)
      -- local t = TestMiddleclass(17.4, 12.1 + j)
      for i = 1, 4 do
        v = t:doItsThing(v)
      end
      -- class.recycle(t)
    end
    generic_utils.runGC()
    ac.debug('v', v)
  end
end




-- function print(v)
--   ac.log(v)
-- end

-- local SomeMixin = { foo = function(self) return ('foo: '..tostring(self)) end, included  = function(class) ac.log('MIXIN:'..tostring(class)) end }

-- Person = class2('Person') --this is the same as class('Person', Object) or Object:subclass('Person')
-- function Person:initialize(name)
--   self.name = name or 'NIL'
-- end
-- function Person:speak()
--   print('Hi, I am ' .. self.name ..'.')
-- end
-- function Person:parentMethod()
--   print('Hello there from ' .. self.name)
-- end
-- function Person.subclassed(other)
--   print('CHILD IS BORN:'..tostring(other))
-- end
-- function Person:__len()
--   return 12345
-- end
-- function Person:__eq()
--   return false
-- end
-- function Person:__call()
--   return 'called:'..self.name
-- end
-- function Person:__tostring()
--   return 'WHOOP:'..self.name
-- end

-- AgedPerson = class2('AgedPerson', Person) -- or Person:subclass('AgedPerson')
-- AgedPerson.ADULT_AGE = 18 --this is a class variable
-- function AgedPerson:initialize(name, age)
--   Person.initialize(self, name) -- this calls the parent's constructor (Person.initialize) on self
--   self.age = age
-- end
-- function AgedPerson:speak()
--   Person.speak(self) -- prints "Hi, I am xx."
--   if(self.age < AgedPerson.ADULT_AGE) then --accessing a class variable from an instance method
--     print('I am underaged.')
--   else
--     print('I am an adult.')
--   end
-- end
-- function AgedPerson:__tostring()
--   return 'WHOOP2'
-- end

-- local p1 = AgedPerson:new('Billy the Kid', 13) -- this is equivalent to AgedPerson('Billy the Kid', 13) - the :new part is implicit
-- local p2 = AgedPerson:new('Luke Skywalker', 21)
-- p1:speak()
-- p2:speak()
-- p2:parentMethod()
-- print(p2)
-- print(Person('qw'))

-- local AgedPerson2 = class('AgedPerson2')

-- -- ac.debug('MW class', to_string(class('PPerson'):new().class))
-- -- ac.debug('NE class', to_string(class2('PPerson'):new().class))
-- ac.debug('class: MW', class('PPerson'))
-- ac.debug('class: NE', class2('PPerson'))
-- ac.debug('class.str: MW', class('PPerson')('smth'))
-- ac.debug('class.str: NE', class2('PPerson')('smth'))
-- ac.debug('class.name-field: MW', class('PPerson')('smth').name)
-- ac.debug('class.name-field: NE', class2('PPerson')('smth').name)
-- ac.debug('class.name: MW', class('PPerson').name)
-- ac.debug('class.name: NE', class2('PPerson').name)
-- ac.debug('class.super: MW', class('PPerson', AgedPerson2).super)
-- ac.debug('class.super: NE', class2('PPerson', AgedPerson).super)
-- ac.debug('class.isSubclassOf: MW', class('PPerson', AgedPerson2):isSubclassOf(AgedPerson2))
-- ac.debug('class.isSubclassOf: NE', class2('PPerson', AgedPerson):isSubclassOf(Person))
-- ac.debug('class.obj:isInstanceOf: MW', class('PPerson', AgedPerson2)():isInstanceOf(AgedPerson2))
-- ac.debug('class.obj:isInstanceOf: NE', class2('PPerson', AgedPerson)():isInstanceOf(Person))
-- ac.debug('class.subclass: MW', AgedPerson2:subclass('PPerson')())
-- ac.debug('class.subclass: NE', AgedPerson:subclass('PPerson')())
-- ac.debug('class.mixin: MW', class('PPerson'):include(SomeMixin):foo())
-- ac.debug('class.mixin: NE', class2('PPerson'):include(SomeMixin):foo())

-- print(#AgedPerson('test', 15))
-- print((Person('test'))())
-- print((AgedPerson('test', 15))())
-- print(Person('test') == Person('test'))
-- print(Person()())
-- print(AgedPerson()())








--- profiling:



local profilerStarted = false
local profilerAccumulatingData = {}
local profilerData = {}

local function tabProfile()
  ui.pushFont(ui.Font.Small)
  local profile = require('jit.profile')
  if not profilerStarted and ui.button('Start profiler') then
    profilerStarted = true
    profile.start('fi1', function(th, samples, vmmode)
      local d = profile.dumpstack(th, 'F\n\t', 5)
      profilerAccumulatingData[d] = (profilerAccumulatingData[d] or 0) + samples
    end)
  elseif profilerStarted and ui.button('Stop profiler') then
    profilerStarted = false
    profile.stop()
    profilerData = table.map(profilerAccumulatingData, function (count, fn)
      return { fn = fn, count = count }
    end)
    table.sort(profilerData, function (a, b) return a.count > b.count end)
  end

  ui.offsetCursorY(12)
  ui.header('Collected samples:')
  if #profilerData == 0 then
    ui.text('Empty')
  else
    ui.childWindow('collectedData', vec2(), function ()
      for i = 1, #profilerData do
        local e = profilerData[i]
        if e.count > 1 then
          ui.text(string.format('%03d: %s', e.count, e.fn))
        end
      end
    end)
  end
  ui.popFont()
end


ui.tabItem('Profile', tabProfile)