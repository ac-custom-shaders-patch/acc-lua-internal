local opt = Config:get('MISCELLANEOUS', 'DISABLE_SHIFTING_PRELOAD_ANIMATION', 0)
if opt == 1 and ac.getCar(0).isDriftCar or opt == 2 then
  print('Disabling shift preload animation')
  ac.setDriverShiftAnimationPreloadThreshold(0, 1e10)
end