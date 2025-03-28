if Sim.isReplayOnlyMode then
  return
end

if Sim.inputMode == ac.UserInputMode.Wheel and Car.hShifter then
  ac.ControlButton('__EXT_SWITCH_HSHIFTER'):onPressed(function ()
    ac.setMessage('H-Shifter', Sim.controlsWithShifter and 'H-shifter disabled' or 'H-shifter enabled')
    ac.setHShifterActive(not Sim.controlsWithShifter)
  end)
end

if Sim.isOnlineRace or not ac.isCarResetAllowed() then
  return
end

ac.ControlButton('__EXT_CMD_RESET'):onPressed(function ()
  ac.resetCar()
end)

ac.ControlButton('__EXT_CMD_STEP_BACK'):onPressed(function ()
  ac.takeAStepBack()
end)