--[[
  This is not a nicely written script to say the least, more of a testing and a proof-of-concept thing, but it should work.
]]

local car = ac.getCar(0) or error()
local sim = ac.getSim()
local uis = ac.getUI()
local carPos = car.position
local aiSpotted = false

local penaltyOffTrack = 5
local penaltyReset = 15

local config = ac.storage{
  displayTime = true,
  displayProgress = true,
  startingGatesStyle = 2,
  allTimeBest = true
}

require('shared/utils/appshelf').offer({
  id = 'RallyCopilot',
  name = 'Rally Copilot',
  reason = 'so it could show you the pace notes'
})

local settings = ac.INIConfig.scriptSettings():mapSection('SETTINGS', {
  RESET_AUTOMATICALLY = true,
  PENALISE_OFFTRACK = true,
  PENALISE_RESETS = true,
})

local con = ac.connect({
  ac.StructItem.key('app.RallyCopilot.extras'),
  distanceToNextHint = ac.StructItem.float(),
  speechPeak = ac.StructItem.float(),
  raceState = ac.StructItem.int32(), -- 0 for regular race, 1 for preparing to a start, 2 for a rally stage, 3 for a finish
  distanceToStart = ac.StructItem.float(),
  hintsCutoffFrom = ac.StructItem.float(),
  hintsCutoffTo = ac.StructItem.float(),
  countdownState = ac.StructItem.int32(),
  finalTime = ac.StructItem.int32(),
})
con.distanceToNextHint = 200
con.speechPeak = 0
con.raceState = 1
con.distanceToStart = 2
con.countdownState = 0
con.finalTime = 0

-- We’re handling recovery on our side (and it’s optional too)
ac.disableCarRecovery(true)

-- Storing results in an SQLite database to ensure it won’t get damaged (I really should
-- move `ac.storage` and such to using SQLite as well)
io.createDir('%s\\..\\savedData' % ac.getFolder(ac.FolderID.Cfg))
local dbStorage = require('shared/utils/dbstorage')
dbStorage.configure('%s\\..\\savedData\\rally-stages.db' % ac.getFolder(ac.FolderID.Cfg), {useWAL = false})

local personalBest = {
  dbKey = '%s:%s' % {ac.getTrackFullID('/'), ac.getCarID(0)},
  ---@type DbDictionaryStorage<number>
  stages = dbStorage.Dictionary('PersonalBest.State'),
  ---@type DbDictionaryStorage<number>
  sectors = dbStorage.Dictionary('PersonalBest.Sector'),
}

---@param p vec3
---@param a vec3
---@param ba vec3
local function distanceToLine(p, a, ba)
  local pax, paz = p.x - a.x, p.z - a.z
  local h = math.saturateN((pax * ba.x + paz * ba.z) / (ba.x * ba.x + ba.z * ba.z))
  local rx, rz = pax - ba.x * h, paz - ba.z * h
  return math.sqrt(rx * rx + rz * rz)
end

local function timingLine(nameL, nameR)
  local startPos, startDelta ---@type vec3, vec3
  if type(nameL) == 'number' then
    local p1 = ac.trackProgressToWorldCoordinate(nameL)
    local p2 = (ac.trackProgressToWorldCoordinate(nameL + 1 / sim.trackLengthM) - p1):cross(vec3(0, 1, 0)):normalize()
    startPos = p1 - p2 * 10
    startDelta = p2:scale(20)
  else
    local nodeL = ac.findNodes(nameL)
    local nodeR = nodeL and ac.findNodes(nameR)
    if not nodeR then return nil end
    startPos = nodeL:getPosition()
    startDelta = nodeR:getPosition() - startPos
  end

  local startMiddle = startPos + startDelta * 0.5
  local trackProgress = ac.worldCoordinateToTrackProgress(startMiddle)
  local highlightState, highlightPos = 0, nil
  local highlightTex0, highlightTex1 ---@type ui.ExtraCanvas, ui.ExtraCanvas
  local needsHighlight, distanceToStartPrev = nil, 1

  local function updateHighlights()
    if needsHighlight and highlightTex0 and highlightTex1 then
      if needsHighlight[1] > 0 then
        local input = needsHighlight[1]
        local frac = math.min(1, (input % 1) * 2) * 10
        highlightTex1:clear(rgbm.colors.transparent):updateWithShader({textures = {}, values = {gState = 0 and math.floor(input) + frac / (1 + frac * (10 - 1) / 10)}, shader = [[
          float sdEquilateralTriangle(float2 p, float r) {
            float k = sqrt(3);
            p.x = abs(p.x) - r;
            p.y = p.y + r / k;
            if (p.x + k * p.y > 0) p = float2(p.x - k * p.y, -k * p.x - p.y) / 2;
            p.x -= clamp(p.x, -2 * r, 0);
            return -length(p) * sign(p.y);
          }
   
          float computeShape(float2 uv) {
            float shape = lerp(length(uv * 2 - 1) - 1, sdEquilateralTriangle((uv * 2 - 1) * float2(1, -1) + float2(0, 0.2), 1), smoothstep(0, 1, saturate(gState * 2 - 8)));
            if (shape > 0 || shape < -0.1) return 0;
            if (gState < 4) {
              float a = atan2(uv.x * 2 - 1, uv.y * 2 - 1) / 3.141592 * 0.5 + 0.5;
              if ((a > frac(gState)) ^ (uint(gState + 1) % 2)) return 0;
            }
            return 1;
          }
  
          float4 main(PS_IN pin) {
            float v = computeShape(pin.Tex)
              + computeShape(pin.Tex + float2(0.5 / 512, 0))
              + computeShape(pin.Tex + float2(0.5 / 512, 0.5 / 512))
              + computeShape(pin.Tex + float2(0, 0.5 / 512));
            return float4(1, 1, 1, v / 4);
        }]]})
        highlightTex1:update(function ()
          ui.pushDWriteFont('@System;Weight=Thin')
          ui.dwriteDrawTextClipped(({'', '3', '2', '1', ''})[math.floor(needsHighlight[1]) + 1], 250, 0, vec2(512, 480), ui.Alignment.Center, ui.Alignment.Center)
          ui.popDWriteFont()
        end)
      else
        highlightTex0:clear(rgbm.colors.transparent):update(function (dt)
          ui.drawImage(needsHighlight[2] > 2 and 'res/forward.png' or needsHighlight[2] > 0 and 'res/handbrake.png' or 'res/back.png', 
            vec2((1024 - 286) / 2, 8), vec2((1024 - 286) / 2 + 286, 8 + 286))
          local px, py, cw, bh = 16, 368, 1024, 128
          ui.drawRect(vec2(px, py), vec2(cw - px, bh + py), rgbm.colors.white, 0, nil, 8)
          ui.drawRectFilled(vec2(px + (cw - px * 2) / 2, py), vec2(px + (cw - px * 2) * math.saturateN((needsHighlight[2] + 4) / 8), bh + py), rgbm(1, 1, 1, 0.25))
          ui.drawSimpleLine(vec2(px + (cw - px * 2) / 2, py), vec2(px + (cw - px * 2) / 2, bh + py), rgbm.colors.white, 4)
          for i = 1, 4 do
            ui.drawSimpleLine(vec2(px + (cw - px * 2) * 0.75, 16 * 2 * i - 24 + py), vec2(px + (cw - px * 2) * 0.75, 32 * i - 8 + py), rgbm.colors.white, 4)
          end
        end)
      end
      needsHighlight = nil
    end
  end

  local prevSignedDistance, signedDistance = 4, 4
  local crossed

  return {
    startMiddle = startMiddle,
    drawGreen = {true, true},
    sessionBest = math.huge,
    pos = function ()
      return startMiddle
    end,
    progress = function ()
      return trackProgress
    end,
    signedDistance = function ()
      return signedDistance
    end,
    signedDistanceTo = function (pos)
      local o = (pos.z - startPos.z) * startDelta.x - (pos.x - startPos.x) * startDelta.z
      return distanceToLine(pos, startPos, startDelta) * math.sign(o)
    end,
    distanceTo = function (line)
      return startMiddle:distance(line.startMiddle)
    end,
    distanceToPoint = function (point)
      return startMiddle:distance(point)
    end,
    updateCompute = function ()
      local o = (carPos.z - startPos.z) * startDelta.x - (carPos.x - startPos.x) * startDelta.z
      prevSignedDistance, signedDistance = signedDistance, distanceToLine(carPos, startPos, startDelta) * math.sign(o)
    end,
    updateCrossed = function (time, dt)
      if not crossed and signedDistance < 0 and prevSignedDistance > 0 and (prevSignedDistance - signedDistance) / sim.dt < 400
          and car.position:closerToThan(startMiddle, 50) then
        crossed = math.lerp(time - dt, time, math.lerpInvSat(0, prevSignedDistance, signedDistance))
        if highlightTex0 then
          ac.log('Starting line crossed in %s' % ac.lapTimeToString(crossed * 1e3))
        end
        return true
      end
      return false
    end,
    crossed = function ()
      return crossed
    end,
    renderDebug = function ()
      render.debugText(startMiddle * 0.5 + vec3(0, 12, 0), nameR and '%s\n%s' % {nameL, nameR} or nameL)
      render.debugArrow(startPos + vec3(0, 25, 0), startPos, -1, rgbm.colors.red * 3)
      render.debugArrow(startPos + startDelta + vec3(0, 25, 0), startPos + startDelta, -1, rgbm.colors.red * 3)
    end,
    renderHighlight = function (startingState, distanceToStart)
      if not highlightTex0 then
        highlightTex0 = ui.ExtraCanvas(vec2(1024, 512), math.huge):setName('Overlay 0')
        highlightTex1 = ui.ExtraCanvas(vec2(512, 512), math.huge):setName('Overlay 1')
        highlightPos = vec3()
        if physics.raycastTrack(startMiddle + vec3(0, 100, 0), vec3(0, -1, 0), 200, highlightPos) <= 0 then
          highlightPos = startMiddle + vec3(0, 1.1, 0)
        else
          highlightPos.y = highlightPos.y + 1.1
        end
        setInterval(updateHighlights)
      end
      if startingState > 0 then
        distanceToStart = distanceToStartPrev
      else
        distanceToStartPrev = distanceToStart
      end
      needsHighlight = {startingState, distanceToStart}
      highlightState = math.applyLag(highlightState, math.ceil(startingState), 0.85, sim.dt)
      render.setBlendMode(render.BlendMode.AlphaBlend)
      render.setCullMode(render.CullMode.Back)
      render.setDepthMode(render.DepthMode.ReadOnly)
      render.shaderedQuad({
        p1 = startPos + vec3(0, 6, 0),
        p2 = startPos + vec3(0, 6, 0) + startDelta,
        p3 = startPos + startDelta - vec3(0, 6, 0),
        p4 = startPos - vec3(0, 6, 0),
        textures = {
          gTex0 = highlightTex0,
          gTex1 = highlightTex1,
        },
        values = {
          gDir = math.normalize(startDelta),
          gDistance = startDelta:length(),
          gHighlightState = math.max(0, highlightState - 1),
          gColor = distanceToStart < 0 and rgb(1, 0.5, 0) or distanceToStart > 2 and rgb(0, 0.3, 0.1) or rgb(0, 0.1, 0.5),
          gCameraPos0 = highlightPos - vec3(0, highlightState * 3, 0),
          gCameraPos1 = highlightPos + vec3(0, 3 - (highlightState > 2 and math.lerp(math.max(highlightState - 3, 1), 1, 0.5) or highlightState - 1) * 3, 0),
        },
        defines = {
          GATES_STYLE = config.startingGatesStyle
        },
        cacheKey = config.startingGatesStyle,
        shader = [[
          float4 main(PS_IN pin) {
            float3 posW = pin.PosC + gCameraPosition;
            float v1 = posW.y;
            float v2 = dot(posW, gDir);
            float alpha = pin.Tex.y * saturate(GATES_STYLE == 2 ? 0.05 + 0.5 * pow(abs(pin.Tex.x * 2 - 1), 2) : -0.15 + 0.7 * pow(abs(pin.Tex.x * 2 - 1), 2));
            alpha *= frac(v1 - v2) > 0.5 ? 1 : 0.5;
            alpha *= abs(pin.Tex.x * 2 - 1) > gHighlightState * 0.25 ? lerp(1 + saturate(gHighlightState), 1, saturate((abs(pin.Tex.x * 2 - 1) - gHighlightState * 0.2) * 100)) : 0;
            alpha = saturate(alpha) * (1 - abs(pin.Tex.x * 2 - 1));
            alpha = max(alpha, gTex0.Sample(samLinearBorder0, float2(dot(posW - gCameraPos0, gDir) * 0.5, -(posW - gCameraPos0).y) * 1.55 + 0.5).w);
            alpha = max(alpha, gTex1.Sample(samLinearBorder0, float2(dot(posW - gCameraPos1, gDir), -(posW - gCameraPos1).y) * 1.5 + 0.5).w);
            return pin.ApplyFog(float4(gColor * gWhiteRefPoint * (USE_LINEAR_COLOR_SPACE ? 8 : 5), alpha));
          }
        ]]
      })
    end,
  }
end

local timeLines = {}
if ac.INIConfig.trackData('surfaces.ini'):get('_EXTENSION', 'RALLY_STAGE_READY', false) then
  for i = 0, 99 do
    local line = timingLine('AC_TIME_%d_L' % i, 'AC_TIME_%d_R' % i)
    if line then
      timeLines[i + 1] = line
    else
      break
    end
  end
elseif sim.trackLengthM > 10 then
  timeLines[1] = timingLine(0.25)
  timeLines[2] = timingLine(0.5)
  timeLines[3] = timingLine(0.75)
end
do
  local start = timingLine('AC_AB_START_L', 'AC_AB_START_R')
  local finish = timingLine('AC_AB_FINISH_L', 'AC_AB_FINISH_R')
  if start and finish and start.distanceTo(finish) > 50 then
    table.insert(timeLines, 1, start)
    table.insert(timeLines, finish)
  else
    start = timingLine(0)
    if start then
      for i = 0, 100, 25 do
        finish = timingLine(1 - i / sim.trackLengthM)
        if start.distanceTo(finish) > 50 then
          table.insert(timeLines, 1, start)
          table.insert(timeLines, finish)
          goto done
        end
      end
    end
    timeLines = {}
  end
end

::done::
if #timeLines == 0 or sim.trackLengthM < 10 then
  setInterval(function ()
    ac.setMessage('Rally Stage', 'Track does not fit, please try a different one')
  end)
  return
end

con.hintsCutoffFrom = timeLines[1].progress()
con.hintsCutoffTo = timeLines[#timeLines].progress()

local initialDistance = timeLines[1].distanceToPoint(car.position)
local best = personalBest.stages:get(personalBest.dbKey) or math.huge
local sessionBest = tonumber(ac.load('.mode.rallyStage.sessionBest')) or math.huge
for i, v in ipairs(timeLines) do
  v.best = personalBest.sectors:get('%s/%d' % {personalBest.dbKey, i}) or math.huge
end

local dirAcc, shiftAcc = 0, math.random()

local function computeGrabbedDir(speedMult)
  dirAcc = dirAcc + sim.dt * (speedMult or 1) --* (0.5 + 12 * math.smootherstep(math.lerpInvSat(math.perlin(os.preciseClock() * 0.45), -0.5, 0.5) ^ 3))
  local t, y = dirAcc * 0.251, dirAcc * 0.271 + shiftAcc
  return car.look * 5 * (math.cos(t) - 0.07 - 0.07 * math.cos(y)) + car.up * 2 * (0.75 + 0.25 * math.cos(y)) + car.side * 3 * math.sin(t)
end

local grabbed ---@type ac.GrabbedCamera?
local grabbedFadingOut = 0
local grabbedBasePos, grabbedNextPos
if sim.cameraMode == ac.CameraMode.Start then
  grabbed = ac.grabCamera('Rally start camera')
  if grabbed then
    grabbed.ownShare = 1
    local dir = computeGrabbedDir()
    grabbedBasePos = car.bodyTransform:transformPoint(car.aabbCenter * vec3(1, 0, 1) + vec3(0, 0, 0.5))
    grabbedNextPos = grabbedBasePos + dir
    grabbed.transform.position = grabbedNextPos
    grabbed.fov = 45
    grabbed.transform.look = grabbedBasePos - grabbed.transform.position
    grabbed.transform.up = vec3(0, 1, 0)
  end
end

local raceStarted = 0
local raceTimeStartPoint = 0
local raceTime = 0
local lastSectorTime, lastFine, lastWarning
local needsReset = 0
local lastValidOnTrackPosition = car.splinePosition
local offroadPenalty = 0
local offroadTime = 0
local offroadRawTime = 0

local function isCarOffRoad()
  for i = 0, 3 do
    if car.wheels[i].surfaceValidTrack then return false end
  end
  return true
end

setInterval(function ()
  -- Invalidate all laps because we’re counting time locally and don’t want to see those red messages when
  -- car is going off-track
  ac.markLapAsSpoiled(true)

  carPos = car.position + car.look * (car.aabbSize.z / 2 - car.aabbCenter.z)
  for _, v in ipairs(timeLines) do
    v.updateCompute()
  end
  if grabbed then
    if not sim.isInMainMenu or grabbedFadingOut > 0 then
      grabbedFadingOut = grabbedFadingOut + sim.dt
      grabbed.ownShare = 1 - math.smoothstep(grabbedFadingOut)
    end
    local dir = computeGrabbedDir(1 / math.max(0.01, grabbed.ownShare))
    grabbedBasePos = car.bodyTransform:transformPoint(car.aabbCenter * vec3(1, 0, 1) + vec3(0, 0, 0.5))
    grabbedNextPos = grabbedBasePos + dir
    grabbed.transform.position = grabbedNextPos
    grabbed.transform.look = grabbedBasePos - grabbed.transform.position
    grabbed.transform.up = vec3(0, 1, 0)
    if grabbedFadingOut > 1 then
      grabbed:dispose()
      grabbed = nil
    end
  end

  if isCarOffRoad() then
    local newTime = offroadRawTime + sim.dt
    if math.floor(newTime) ~= math.floor(offroadRawTime) and newTime > 1 and newTime < 10 then
      lastWarning = lastWarning or {'', 0}
      lastWarning[1] = 'Get back in %.0f s' % (9 - math.floor(offroadRawTime))
      lastWarning[2] = lastWarning[2] < 0.8 and lastWarning[2] or math.min(lastWarning[2], 0.8)
    end
    offroadRawTime = newTime
  else
    offroadRawTime = 0
    lastValidOnTrackPosition = car.splinePosition
  end

  if raceStarted == 2 then
    if car.justJumped and settings.PENALISE_RESETS then
      offroadPenalty = 0
      raceTime = raceTime + penaltyReset
      lastFine = {'+'..ac.lapTimeToString(penaltyReset * 1e3)}
    end
    if settings.PENALISE_OFFTRACK then
      if offroadRawTime > 0 then
        offroadPenalty = 0.5
        offroadTime = offroadTime + sim.dt
      elseif offroadPenalty > 0 then
        offroadPenalty = offroadPenalty - sim.dt
        if offroadPenalty <= 0 then
          if offroadTime > 1 then
            raceTime = raceTime + penaltyOffTrack
            lastFine = {'+'..ac.lapTimeToString(penaltyOffTrack * 1e3)}
          end
          offroadTime = 0
        end
      end
    end
  end

  if settings.RESET_AUTOMATICALLY then
    if offroadRawTime > 10 then
      offroadRawTime, needsReset = -15, -15
      ac.takeAStepBack((car.splinePosition - lastValidOnTrackPosition) * sim.trackLengthM)
    elseif (car.up.y < 0 or offroadRawTime > 10 or car.gas > 0.3 and car.speedKmh < 1 and car.engagedGear ~= 0) then
      needsReset = needsReset + sim.dt
      if needsReset > 5 then
        ac.warn('Resetting car…')
        ac.resetCar()
        needsReset = -15
      end
    else
      needsReset = 0
    end
  end
end)

ac.setStartMessage('Get to the start', 'INFO')

local brakesHeld = 0

function script.prepare()
-- This function is called before event activates. Once it returns true, it’ll run:
  local distance = timeLines[1].signedDistance()
  con.distanceToStart = distance
  local fits = car.speedKmh < 1 and distance > 0 and distance < 2
  ac.setStartMessage(distance < 0 and 'Take a step back' or distance > 2 and 'Get to the start' or 'Hold handbrake', 'INFO')
  if fits and (car.handbrake > 0.9 or car.brake > 0.9) then
    brakesHeld = brakesHeld + sim.dt * (car.handbrake > 0.9 and 2 or 1)
  else
    brakesHeld = 0
  end
  local curDistance = timeLines[1].distanceToPoint(car.position)
  -- ac.debug('curDistance', curDistance)
  -- ac.debug('initialDistance', initialDistance)
  if curDistance > initialDistance + 30 then
    ac.endSession('Please get to the starting line and wait', false, {
      summary = 'Disqualified',
      message = '• Please get to the starting line and wait'
    })
  end
  return os.preciseClock() > 1 and fits and brakesHeld > 1
end

local startingSequence = 0
local startingProgress = 'Get ready…' ---@type string?
local sectorTimes = {}
local finished = false
local startedLap = false

function script.update(dt)
  if raceStarted == 2 then
    raceTime = os.preciseClock() - raceTimeStartPoint
    for i, v in ipairs(timeLines) do
      if v.updateCrossed(raceTime, dt) then
        local ownTime = v.crossed() - (timeLines[i - 1] and timeLines[i - 1].crossed() or 0)
        if v ~= timeLines[1] and v ~= timeLines[#timeLines] then
          table.insert(sectorTimes, 'Sector #%d: %s' % {i - 1, ac.lapTimeToString(ownTime * 1e3)})
        end
        if ownTime <= v.best then
          v.best = ownTime
          v.drawGreen[1] = true
          personalBest.sectors:set('%s/%d' % {personalBest.dbKey, i}, ownTime)
        else
          v.drawGreen[1] = false
        end
        if ownTime <= v.sessionBest then
          v.sessionBest = ownTime
          v.drawGreen[2] = true
        else
          v.drawGreen[2] = false
        end
        lastSectorTime = {ac.lapTimeToString(ownTime * 1e3)}
      end
    end
    if not startedLap then
      if car.splinePosition < 0.9 then
        startedLap = true
      end
    elseif not finished and sim.trackLengthM > 10 then
      local prediction = car.splinePosition + car.speedMs * 3 / sim.trackLengthM
      if prediction > timeLines[#timeLines].progress() then
        finished = true
        ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'finish'})
        con.raceState = 3
      end
    end
    if timeLines[#timeLines]:crossed() then
      local currentTime = timeLines[#timeLines].crossed()
      raceStarted = 3
      con.raceState = 3
      con.finalTime = currentTime
      if currentTime < best then
        best = currentTime
        sessionBest = math.min(sessionBest, currentTime)
        personalBest.stages:set(personalBest.dbKey, currentTime)
        ac.store('.mode.rallyStage.sessionBest', sessionBest)
      end
      ac.endSession('%s time: %s' % {aiSpotted and 'AI' or 'Your', ac.lapTimeToString(currentTime * 1e3)}, true, {
        summary = 'Stage is complete',
        message = table.concat(table.flatten({
          '• Time: %s' % ac.lapTimeToString(currentTime * 1e3),
          table.map(sectorTimes, function (item) return '• %s' % item end),
          aiSpotted and '\n• AI was in control' or nil
        }, math.huge), '\n')
      })
    end
    if car.isAIControlled then
      aiSpotted = true
    end
  elseif raceStarted == 0 then
    con.countdownState = 1
    raceStarted = 1
    ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_getready'})
  else
    if car.speedKmh > 2 and car.gas > 0.1 then
      ac.endSession('Please wait for a race to start', false, {
        summary = 'Disqualified',
        message = '• Please wait for a race to start'
      })
    end
  end
  if raceStarted >= 1 and startingSequence < 6 then    
    local newStartingSequence = startingSequence + sim.dt
    if startingSequence < 1 and newStartingSequence >= 1 then
      con.countdownState = 2
      startingProgress = '3…'
      ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_3'})
    elseif startingSequence < 2 and newStartingSequence >= 2 then
      con.countdownState = 3
      startingProgress = '2…'
      ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_2'})
    elseif startingSequence < 3 and newStartingSequence >= 3 then
      con.countdownState = 4
      startingProgress = '1…'
      ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_1'})
    elseif startingSequence < 4 and newStartingSequence >= 4 then
      startingProgress = 'Go!'
      ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_go'})
      con.raceState = 2
      raceStarted = 2
      raceTimeStartPoint = os.preciseClock()
    elseif startingSequence < 5 and newStartingSequence >= 5 then
      startingProgress = nil
    end
    startingSequence = newStartingSequence
  end
end

render.on('main.track.transparent', function ()
  if startingSequence < 6 and timeLines[1].signedDistanceTo(sim.cameraPosition) > 0 and config.startingGatesStyle ~= 0 then
    timeLines[1].renderHighlight(startingSequence, timeLines[1].signedDistance())
  end

  -- for _, v in ipairs(timeLines) do
  --   v.renderDebug()
  -- end
end)

ui.addSettings({
  icon = 'res/settings-icon.png', name = 'Rally Stage mode', size = {automatic = true}
}, function ()
  ui.header('HUD settings')
  if ui.checkbox('Display section time', config.displayTime) then
    config.displayTime = not config.displayTime
  end
  if ui.checkbox('Display stage progress', config.displayProgress) then
    config.displayProgress = not config.displayProgress
  end
  if ui.checkbox('Use all-time best for sector coloring', config.allTimeBest) then
    config.allTimeBest = not config.allTimeBest
  end

  ui.offsetCursorY(12)
  ui.header('Visual settings')
  local styles = {[0] = 'Hidden', 'Partial', 'Full'}
  ui.combo('##gates', 'Starting gates style: %s' % (styles[config.startingGatesStyle] or '?'), ui.ComboFlags.None, function ()
    for i, v in pairs(styles) do
      if ui.selectable(v, i == config.startingGatesStyle) then
        config.startingGatesStyle = i
      end
    end
  end)

  ui.offsetCursorY(12)
  ui.header('Personal best')
  ui.alignTextToFramePadding()
  ui.text('Best time: %s' % ac.lapTimeToString(best * 1e3))
  ui.sameLine(200)
  if ui.button('Reset') then
    local bak = {best, table.map(timeLines, function (item, index)
      return {item.best, item.sessionBest}, index
    end)}
    best = math.huge
    personalBest.stages:remove(personalBest.dbKey)
    for i, v in ipairs(timeLines) do
      v.best, v.sessionBest = math.huge, math.huge
      personalBest.sectors:remove('%s/%d' % {personalBest.dbKey, i})
    end
    ui.toast(ui.Icons.Trash, 'Personal best removed', function ()
      best = bak[1]
      personalBest.stages:set(personalBest.dbKey, best[1])
      for i, v in ipairs(timeLines) do
        v.best, v.sessionBest = bak[2][i][1], bak[2][i][2]
        personalBest.sectors:set('%s/%d' % {personalBest.dbKey, i}, v.best)
      end
    end)
  end
end)

local uiIn = 0
local pbOut = 0

function script.drawUI()
  uiIn = math.applyLag(uiIn, 1, 0.85, sim.dt)
  pbOut = math.applyLag(pbOut, raceStarted >= 2 and 1 or 0, 0.85, sim.dt)
  if config.displayProgress then
    local pg = 3
    local px, py, pw, c = -20 + 60 * uiIn, 40 - pg, 12, 0
    local ph, ps, pi = ui.windowHeight() - py * 2, timeLines[1].progress(), ui.windowHeight()
    local pf = timeLines[#timeLines].progress() - ps
    local fn = true
    local carSplinePos = car.splinePosition
    for i = 2, #timeLines do
      local v = timeLines[i]
      local r1, r2 = vec2(px, pi - (py + ph * (v.progress() - ps) / pf - pg)), vec2(px + pw, pi - (py + ph * c + pg))
      ui.drawRectFilled(r1, r2, v.crossed() and (v.drawGreen[config.allTimeBest and 1 or 2] and rgbm.colors.lime or rgbm.colors.red) or fn and rgbm.colors.white or rgbm.colors.gray)
      c = (v.progress() - ps) / pf
      if not uis.wantCaptureMouse and ui.rectHovered(r1, r2) then
        ui.setTooltip('Best sector time: %s\nBest session sector time: %s' % {ac.lapTimeToString(v.best * 1e3), ac.lapTimeToString(v.sessionBest * 1e3)})
      end
      if not v.crossed() and fn then
        fn = false
        if i == 2 and carSplinePos > 0.98 then
          carSplinePos = 0
        elseif i == #timeLines and carSplinePos < 0.02 then
          carSplinePos = 1
        end
      end
    end
    local cp = vec2(px + pw, pi - (py + pg + (ph - pg * 2) * math.saturateN((carSplinePos - ps) / pf)))
    ui.drawTriangleFilled(cp, cp + vec2(20, -10), cp + vec2(20, 10), rgbm.colors.white)
  end
  if config.displayTime then
    ui.beginOutline()
    ui.setCursorY(-90 + 190 * uiIn)
    ui.pushAlignment()
    ui.icon(not startingProgress and ui.Icons.Clock or startingProgress == 'Go!' and ui.Icons.UpAlt or ui.Icons.Attention, 22)
    ui.sameLine(0, 12)
    ui.offsetCursorY(-8)
    ui.dwriteText(startingProgress or ac.lapTimeToString(raceTime * 1e3), 28)
    if not startingProgress then
      local r1, r2 = ui.itemRect()  
      if not uis.wantCaptureMouse and ui.rectHovered(r1, r2) then
        ui.setTooltip('Best time: %s\nBest session time: %s' % {ac.lapTimeToString(best * 1e3), ac.lapTimeToString(sessionBest * 1e3)})
      end
    end
    ui.popAlignment()
    local msgPopup = lastFine or lastWarning or lastSectorTime
    if msgPopup then
      if not msgPopup[2] then
        msgPopup[2] = 0
      end
      msgPopup[2] = math.applyLag(msgPopup[2], msgPopup[2] < 0.999997 and 1 or 2, 0.85, sim.dt)
      ui.setCursorY(150)
      ui.setCursorX(ui.availableSpaceX() / 2 - 500 + 40 * (msgPopup[2] - 1))
      ui.beginGroup(1000)
      ui.pushStyleVarAlpha((msgPopup[2] < 1 and msgPopup[2] or 2 - msgPopup[2]) ^ 2)
      ui.pushAlignment()
      ui.icon(lastFine and ui.Icons.Reset or ui.Icons.Flag, 22)
      ui.sameLine(0, 12)
      ui.offsetCursorY(-8)
      ui.dwriteText(msgPopup[1], 28, lastFine and rgbm.colors.red or rgbm.colors.white)
      ui.popAlignment()
      ui.endGroup()
      ui.popStyleVar(1)
      if msgPopup[2] > 1.9995 then
        if lastFine then lastFine = nil end
        if lastWarning then lastWarning = nil end
        if lastSectorTime then lastSectorTime = nil end
      end
    elseif startingProgress and best ~= math.huge then
      ui.setCursorY(-40 + 190 * uiIn - 190 * pbOut)
      ui.pushAlignment()
      ui.icon(ui.Icons.List, 22)
      ui.sameLine(0, 12)
      ui.offsetCursorY(-8)
      ui.dwriteText('Best time: %s' % ac.lapTimeToString(best * 1e3), 28)
      ui.popAlignment()
    end
    ui.endOutline(rgbm.colors.black)
  end
end

-- ui.onExclusiveHUD(script.drawUI)
