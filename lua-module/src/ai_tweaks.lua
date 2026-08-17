if not AIRace or not ConfigNewBehaviour then
  return
end

if Sim.customAISplinesAllowed then
  local aiFolder = '%s/ai' % ac.getFolder(ac.FolderID.CurrentTrackLayout)
  local altSplines = io.scanDir(aiFolder, 'ext_alt_fast_lane_*.ai')
  if #altSplines > 0 then
    math.randomseed(math.randomKey())
    for i = 0, Sim.carsCount - 1 do
      local s = math.random(#altSplines + 1)
      if s <= #altSplines then
        physics.setAISpline(i, '%s/%s' % {aiFolder, altSplines[s]})
        ac.log('AI #%s' % i, '%s/%s' % {aiFolder, altSplines[s]})
      end
    end
  end
end

