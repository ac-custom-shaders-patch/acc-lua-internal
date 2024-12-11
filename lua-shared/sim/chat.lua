--[[
  Library with some extra features for online chats, allowing to recreate some functions for a custom chat app.
  More functions will be added later. Not available to car, track or physics scripts.

  To use, include with `local chat = require('shared/sim/chat')`.
]]
---@diagnostic disable

local chat = {
  extras = {
  }
}

---Checks if server allows to change car color.
---@return boolean
function chat.extras.canChangeCarColor()
  return __util.native('cui.canChangeCarColor')
end

---Changes car color in an online race, syncing change to other players automatically. Use `ac.getCar(0).customCarColor`
---to check the current color.
---@param color rgb? @Pass `nil` to reset color to default.
---@return boolean @Returns false if changing colors is not allowed.
function chat.extras.changeCarColor(color)
  return __util.native('cui.changeCarColor', color)
end

local td_c, td_p = -1, nil

---Returns list of teleport destinations configured in server.
---@return {ID: integer, group: string?, name: string, heading: number, position: vec3}[]
function chat.extras.teleportDestinations()
  local n_td_c, n_td_p = __util.native('cui.teleportDestinations', td_c)
  if n_td_p then
    td_c, td_p = n_td_c, n_td_p
  end
  return td_p
end

---Teleports car to a certain destination. Can be used by scripts with gameplay API access only.
---@param destinationID integer @Value from ID field of a target destination.
---@return boolean @Returns false if teleportation is not available.
function chat.extras.teleportTo(destinationID)
  return __util.native('cui.teleportTo', destinationID)
end

---Shares a setup in chat.
---@param setupFilename string @Full filename to the setup INI file.
---@return boolean @Returns false if teleportation is not available.
function chat.extras.shareCarSetup(setupFilename)
  return __util.native('cui.shareCarSetup', setupFilename)
end

return chat