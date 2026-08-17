local drawAIIcon

ac.onSharedEvent('$SmallTweaks.AIToggle', function ()
  if not drawAIIcon then
    drawAIIcon = Toggle.DrawUI()
    Register('drawGameUI', function (dt)
      drawAIIcon(Car.isAIControlled)
      if Car.isAIControlled then
        ui.drawCarIcon('AP:FORM_AI', rgbm(0.5, 1, 1, 1), 'Car is controlled by AI')
      end
    end)
  end
  drawAIIcon(true)
end)
