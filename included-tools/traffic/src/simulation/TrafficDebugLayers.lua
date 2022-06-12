local AABB = require('AABB')

local sim = ac.getSim()

---@class TrafficDebugLayers : ClassBase
local TrafficDebugLayers = class('TrafficDebugLayers')

---@param root table|nil
---@return TrafficDebugLayers
function TrafficDebugLayers:initialize(root)
  self.root = { name = '', active = true, childrenMap = {}, children = {} }
  self.current = nil
  self.level = 1
  if root ~= nil then
    local function runNode(node)
      table.forEach(node, function (item)
        self:with(item.name, item.active, function ()
          runNode(item.children)
        end)
      end)
    end
    self:start()
    runNode(root)
  end
end

function TrafficDebugLayers:start()
  self.parent = nil
  self._mousePoint = nil
  self._mouseRay = nil
  self.current = self.root
  self.level = 1
end

function TrafficDebugLayers:mouseRay()
  if self._mouseRay == nil then
    self._mouseRay = render.createMouseRay()
  end
  return self._mouseRay
end

function TrafficDebugLayers:mousePoint()
  if self._mousePoint == nil then
    local ray = self:mouseRay()
    local rayDistance = ray:track()
    local _mousePoint = ray.dir * rayDistance + ray.pos
    self._mousePoint = _mousePoint
    render.debugCross(_mousePoint, 0.5)
  end
  return self._mousePoint
end

---@param position vec3|AABB
---@param radius number?
function TrafficDebugLayers:near(position, radius)
  if AABB.isInstanceOf(position) then
    return self:near(position.center, position.radius)
  end
  return sim.cameraPosition:closerToThan(position, (radius or 0) + 160)
end

function TrafficDebugLayers:serialize()
  local c = {}
  local function fn(arg, dest)
    table.forEach(arg.children, function(child)
      table.insert(dest, { name = child.name, active = child.active, children = {} })
      fn(child, dest[#dest].children)
    end)
  end
  fn(self.root, c)
  return c
end

function TrafficDebugLayers:with(name, activeByDefault, callback)
  if type(activeByDefault) == 'function' then activeByDefault, callback = callback, activeByDefault end
  local c, l = self.current, self.level
  local r = c.childrenMap[name]
  if r == nil then
    r = { name = name, active = not not activeByDefault, childrenMap = {}, children = {}, level = l }
    c.childrenMap[name] = r
    table.insert(c.children, r)
  end
  if r.active then
    self.current = r
    self.level = l + 1
    try(callback, function (err) ac.log(err) end)
    self.current = c
    self.level = l
  end
end

return class.emmy(TrafficDebugLayers, TrafficDebugLayers.initialize)

