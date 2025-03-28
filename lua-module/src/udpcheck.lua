if Sim.isOnlineRace then
  local function isUDPLate()
    if Sim.timeSinceLastUDPPacket < 5 then return false end
    for _, c in ac.iterateCars.ordered() do
      if c.index ~= 0 and c.isConnected then
        return true
      end
    end
    return false
  end

  local drawUDPWarning = true and Toggle.DrawUI()
  local udpIsLate = 0
  Register('core', function (dt)
    if isUDPLate() then
      udpIsLate = 0.5
      drawUDPWarning(true)
    elseif udpIsLate > 0 then
      udpIsLate = udpIsLate - dt
      if udpIsLate <= 0 then
        drawUDPWarning(false)
      end
    end
  end)
  Register('drawGameUI', function (dt)
    if udpIsLate > 0 then
      ui.drawCarIcon(ui.Icons.Warning, rgbm.colors.orange, 'A delay in data stream from the server')
    end
  end)
end