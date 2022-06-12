package.add 'src'

local RailroadEditor = require 'RailroadEditor'
local Railroad = require 'Railroad'
local RailroadTrainObject = require 'RailroadTrainObject'

local filename = ac.getTrackDataFilename('railworks.data')
local railroad ---@type Railroad

local editor = RailroadEditor(io.load(filename, ''), function (data) io.save(filename, data) end)
editor.onReload = function ()
  if railroad then
    RailroadTrainObject.disposePool()
    railroad:dispose()
    railroad = nil
  end
end

function script.update(dt)
  editor:drawUI(dt)
end

function script.simUpdate(dt)
  if editor:isBusy() then
    editor.onReload()
    return
  end

  if railroad == nil and not ac.getUI().wantCaptureKeyboard then
    railroad = false
    local data = stringify.tryParse(io.load(filename), nil, {})
    if data.trains then
      railroad = Railroad(data)
    end
  end

  if railroad then
    railroad:update(ac.getGameDeltaT())
  end
end

function script.draw3D(dt)
  render.setDepthMode(render.DepthMode.Off)
  editor:draw3D(dt)
end

