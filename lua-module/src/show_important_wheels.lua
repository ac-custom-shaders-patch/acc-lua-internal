if Config:get('MISCELLANEOUS', 'SHOW_IMPORTANT_STEERING_WHEELS', false) then
  local steer = ac.findNodes('carRoot:0'):findNodes('STEER_HR'):findAny('{ class:display, class:text }')
  if #steer > 0 then
    ac.applyLiveConfigEdit('video.ini', '[ASSETTOCORSA] HIDE_STEER=0')
  end
end
