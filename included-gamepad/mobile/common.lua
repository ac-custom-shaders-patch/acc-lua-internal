SM = ac.writeMemoryMappedFile('AcTools.GamepadState.v1', [[
  uint8_t lightBarColor[4];
  uint8_t vibrationLeft;
  uint8_t vibrationRight;
  uint16_t relativeRpm;

  bool headlightsActive;
  bool lowBeamsActive;
  bool absOff;
  bool tcOff;
  bool absPresent;
  bool tcPresent;
  bool turboPresent;
  bool clutchPresent;
  bool wipersPresent;
  bool headlightsPresent;
  bool paused;
  bool needsDPad;
  bool driftMode;
  uint8_t gearsCount;
  uint8_t gear;

  int64_t currentTime;
  int64_t packetTime;
  float steer;
  float gas;
  float brake;
  float clutch;
  float handbrake;        
  float touch1X;
  float touch1Y;
  float touch2X;
  float touch2Y;
  bool gearUp;
  bool gearDown;
  bool headlightsSwitch;
  bool headlightsFlash;
  bool changingCamera;
  bool horn;
  bool absDown;
  bool absUp;
  bool tcDown;
  bool tcUp;
  bool turboDown;
  bool turboUp;
  bool wiperDown;
  bool wiperUp;
  bool pause;
  bool povClick;
  uint8_t povDir;
  bool neutralGear;
  bool lowBeams;
  bool modeSwitch;
  uint8_t batteryCharge;
  bool batteryCharging;
]])

DualSenseEmulator = ac.connect({
  ac.StructItem.key('dualSenseEmulator'),
  available = ac.StructItem.boolean(),
  batteryCharging = ac.StructItem.boolean(),
  batteryCharge = ac.StructItem.float(),
  carIndex = ac.StructItem.int32(),
  touch1Pos = ac.StructItem.vec2(),
  touch2Pos = ac.StructItem.vec2(),
  lightBarColor = ac.StructItem.rgbm()
}, false, ac.SharedNamespace.Global)

function IsOffline()
  return tonumber(SM.currentTime - SM.packetTime) > 2500 or SM.packetTime == 0
end
