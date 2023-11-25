if Sim.isOnlineRace or not ac.isCarResetAllowed() then
  return
end

ac.ControlButton('__EXT_CMD_RESET'):onPressed(function ()
  ac.resetCar()
end)

ac.ControlButton('__EXT_CMD_STEP_BACK'):onPressed(function ()
  ac.takeAStepBack()
end)