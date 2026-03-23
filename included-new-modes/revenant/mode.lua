local sim = ac.getSim()
local cfg = ac.storage{ collisionsType = 2 }
local btn = ac.ControlButton('newmode.revenant/Revenant: recording')
local collisions = {
  {'disabled', 'Disabled collisions', 'Pass through ghost as if it’s not there', 'disabled'},
  {'pushable', 'Push ghost for a bit', 'On collisions, push ghost off a bit, for it to return back to the trajectory after a bit', 'pushable'},
  {'knockable', 'Knock ghost off entirely', 'Stop ghost entirely on colliding with it', 'knockable'},
  {'stiff', 'Entirely immovable ghost', 'Ghost ignores collisions and continues going, pushing you away', 'stiff'},
}

physics.teleportCarTo(0, ac.INIConfig.scriptSettings():get('SETTINGS', 'START_FROM', 'PIT'))

local start = -1
local startingTransform
local playing = false
local ghostVisible = false
local driveTime = 0

local replayStopTimeout

local function resetReplayStopTimeout()
  if replayStopTimeout then
    clearTimeout(replayStopTimeout)
    replayStopTimeout = nil
  end
end

local function hideAndStopGhost()
  resetReplayStopTimeout()
  ac.setReplayBasedGhost(1, -1)
  ac.setDriverVisible(1, false)
  ac.disableCar(1, true)
  physics.teleportCarTo(1, ac.SpawnSet.Pits)
  physics.setAINoInput(1, true, true)
  ghostVisible = false
end

local function resetGhost()
  resetReplayStopTimeout()
  hideAndStopGhost()
  playing = false
end

local function reset()
  start = -1
  startingTransform = nil
  resetGhost()
end

ac.addMainMenuSettings(function ()
  ui.pushAlignment(true, 0.5)
  ui.text('Start/play recording:')
  btn:control(vec2(-0.1, 40))
  ui.pushFont(ui.Font.Small)
  ui.textWrapped('When playing record, press button to restart playback, or hold button for a half a second to reset and start a new recording')
  ui.popFont()
  ui.offsetCursorY(12)
  ui.setNextItemWidth(ui.availableSpaceX())
  ui.setNextItemIcon(ui.Icons.Collision)
  ui.combo('##collisions', 'Collisions: %s' % collisions[cfg.collisionsType][1], function ()
    for i, v in ipairs(collisions) do
      if ui.selectable(v[2], cfg.collisionsType == i) then
        cfg.collisionsType = i
        reset()
      end
      if ui.itemHovered() then ui.setTooltip(v[3]) end
    end
  end)
  ui.popAlignment()
end, nil, 200)

physics.setAIDriverName(1, 'Revenant', ac.getDriverNationCode(0))
ac.disableQuickMenuPitstop(true)
ac.hideCarLabels(1, true)

reset()

local replayDuration = 0

local function startRecording()
  resetReplayStopTimeout()
  start = driveTime
  startingTransform = ac.getCar(0).bodyTransform:clone()
  resetGhost()
end

local function playRecordingFromStart()
  resetReplayStopTimeout()
  ac.setReplayBasedGhost(1, 0, driveTime - start, collisions[cfg.collisionsType][4])
  replayStopTimeout = setTimeout(hideAndStopGhost, replayDuration)
  ac.setDriverVisible(1, true)
  setTimeout(function ()
    ac.disableCar(1, false)
  end)
  playing = true
  ghostVisible = true
end

local function onShortPress()
  if start == -1 then
    startRecording()
  else
    if not playing then
      replayDuration = driveTime - start
    end
    playRecordingFromStart()
  end
end

local function onLongPress()
  startRecording()
end

local complexPress
btn:onPressed(function ()
  complexPress = setTimeout(function ()
    onLongPress()
    complexPress = nil
  end, 0.5)
end)
btn:onReleased(function ()
  if complexPress then
    clearTimeout(complexPress)
    complexPress = nil
    onShortPress()
  end
end)

render.on('main.track.transparent', function ()
  if startingTransform and not ac.getSim().isReplayActive and not ghostVisible then
    render.setBlendMode(render.BlendMode.AlphaBlend)
    render.setCullMode(render.CullMode.None)
    render.setDepthMode(render.DepthMode.ReadOnly)
    render.mesh({
      mesh = ac.SimpleMesh.carShape(1),
      transform = startingTransform,
      textures = {},
      values = {},
      shader = [[
        float4 main(PS_IN pin) {
          return float4((pin.NormalW.yyy + 1) * float3(0.5, 1, 0) * gWhiteRefPoint, 0.1 * pin.FogAlphaMultiplier());
        }
      ]]
    })
  end
end)

ac.onReplay(function (event)
  hideAndStopGhost()
  if event ~= 'stop' then
    ac.disableCar(1, false)
  end
end)

function script.update(dt)
  if not sim.isReplayActive then
    driveTime = driveTime + dt
  end
end
