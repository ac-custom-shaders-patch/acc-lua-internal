--[[
  Module adding hotkeys to move seat and swap places live with hotkeys. Active only if
  at least a single hotkey is set.
]]

local cfg = Config:mapSection('ONBOARD_HOTKEYS', {
  MOVE_SPEED = 0.1,
  ROTATE_SPEED = 10,
  FOV_SPEED = 10,
  EYES_POSITION = vec3(0, 0.13, 0.14)
})

local buttons = table.filter({
  { ac.ControlButton('__EXT_SEAT_LEFT'), vec3(1, 0, 0) },
  { ac.ControlButton('__EXT_SEAT_RIGHT'), vec3(-1, 0, 0) },
  { ac.ControlButton('__EXT_SEAT_UP'), vec3(0, 1, 0) },
  { ac.ControlButton('__EXT_SEAT_DOWN'), vec3(0, -1, 0) },
  { ac.ControlButton('__EXT_SEAT_FORWARD'), vec3(0, 0, 1) },
  { ac.ControlButton('__EXT_SEAT_BACKWARD'), vec3(0, 0, -1) },
  { ac.ControlButton('__EXT_SEAT_PITCHUP'), 0 },
  { ac.ControlButton('__EXT_SEAT_PITCHDOWN'), 1 },
  { ac.ControlButton('__EXT_SEAT_YAWLEFT'), 2 },
  { ac.ControlButton('__EXT_SEAT_YAWRIGHT'), 3 },
  { ac.ControlButton('__EXT_SEAT_RESET'), 4 },
  { ac.ControlButton('__EXT_SEAT_AUTO'), 5 },
  { ac.ControlButton('__EXT_SEAT_FOV_INCREASE'), 6 },
  { ac.ControlButton('__EXT_SEAT_FOV_DECREASE'), 7 },
}, function (item)
  return item[1]:configured()
end)

local btnSwapSeats = ac.ControlButton('__EXT_SWAP_SEATS')

if #buttons == 0 and not btnSwapSeats:configured() then
  return
end

local function getEyesPos(carIndex)
  local neck = ac.findNodes('carRoot:0'):findNodes('DRIVER:RIG_Nek')
  local eyesPos = neck:getWorldTransformationRaw():transformPoint(cfg.EYES_POSITION)
  return ac.getCar(carIndex).worldToLocal:transformPoint(eyesPos)
end

local swappedSeat = {}
local swappedSeatPrev = {}

ac.onRelease(function ()
  for k, v in pairs(swappedSeat) do
    ac.setOnboardCameraParams(k, v, false)
    ac.forceVisibleHeadNodes(k, false)
  end
end)

Register('gameplay', function (dt)
  local carIndex = Sim.focusedCar
  if Sim.cameraMode ~= ac.CameraMode.Cockpit or carIndex == -1 then return end

  for i = 1, #buttons do
    local b = buttons[i]
    if b[1]:down() then
      local p, action, flipped = ac.getOnboardCameraParams(carIndex), b[2], swappedSeat[carIndex]

      if action == 0 then
        p.pitch = p.pitch + dt * cfg.ROTATE_SPEED
      elseif action == 1 then
        p.pitch = p.pitch - dt * cfg.ROTATE_SPEED
      elseif action == 2 then
        p.yaw = p.yaw - dt * cfg.ROTATE_SPEED
      elseif action == 3 then
        p.yaw = p.yaw + dt * cfg.ROTATE_SPEED
      elseif action == 4 then
        p.position = getEyesPos()
        if flipped then
          p.position.x = -p.position.x
        end
      elseif action == 5 then
        p = ac.getOnboardCameraDefaultParams(carIndex)
        if flipped then
          p.position.x = -p.position.x
        end
      elseif action == 6 then
        ac.debug('Sim.firstPersonCameraFOV', Sim.firstPersonCameraFOV)
        ac.setFirstPersonCameraFOV(math.clamp(Sim.firstPersonCameraFOV + dt * cfg.FOV_SPEED, 10, 120))
      elseif action == 7 then
        ac.setFirstPersonCameraFOV(math.clamp(Sim.firstPersonCameraFOV - dt * cfg.FOV_SPEED, 10, 120))
      else
        p.position:addScaled(action, dt * cfg.MOVE_SPEED)
      end

      ac.setOnboardCameraParams(carIndex, p, not flipped) -- not saving if seat is flipped
    end
  end

  if btnSwapSeats:pressed() then
    if swappedSeat[carIndex] then
      swappedSeatPrev[carIndex] = ac.getOnboardCameraParams(carIndex)
      ac.setOnboardCameraParams(carIndex, swappedSeat[carIndex], false)
      swappedSeat[carIndex] = nil
      ac.forceVisibleHeadNodes(carIndex, false)
    else
      -- Backup original config:
      swappedSeat[carIndex] = ac.getOnboardCameraParams(carIndex)

      -- And set new one flipped on X axis:
      local flipped = swappedSeatPrev[carIndex]
      if not flipped then
        flipped = ac.getOnboardCameraParams(carIndex)
        flipped.position.x = -flipped.position.x
      end
      ac.setOnboardCameraParams(carIndex, flipped, false)
      ac.forceVisibleHeadNodes(carIndex, true)
    end
  end
end)
