


-- function frameBegin(dt, gameDT)
--   collectgarbage()
--   ac.perfBegin('perf 2')
--   testClass()
--   ac.perfEnd('perf 2')
--   runGC()
-- end

-- function arrayPerf1Test()
--   local t = {}
--   for i = 1, 10000 do
--     t[#t + 1] = i
--   end

--   local n = 0
--   for j = 1, 100 do
--     for i = 1, 10000 do
--       n = n + t[i]
--     end
--   end

--   ac.debug('n1', n)
-- end

-- function arrayPerf2Test()
--   local t = Array()
--   for i = 1, 10000 do
--     t:push(i)
--   end

--   local n = 0
--   for j = 1, 100 do
--     for i = 1, 10000 do
--       n = n + t[i]
--     end
--   end

--   ac.debug('n2', n)
-- end

  -- local m = ac.findMeshes('aclogo')
  -- m:setMaterialTexture('txDiffuse', {
  --   textureSize = vec2(512, 512), -- although optional, I recommend to set it: skin could replace texture by one with different resolution
  --   background = rgbm(1, 0, 0, 1),  -- set to nil (or remove) to reuse original texture as background, set to skip background preparation completely
  --   region = {                      -- if not set, whole texture will be repainted
  --     from = vec2(100, 100),
  --     size = vec2(100, 100)
  --   },
  --   callback = function (dt)
  --     ac.debug('dt', dt)
  --     -- display.rect{ pos = vec2(), size = vec2(300, 300), color = rgbm(math.random(), math.random(), math.random(), 1) }
  --   end
  -- })



  

  --[[ local start, startSide = 0, 0
  local loopStart, loopStartPos = 0, nil
  local startPos = nil
  local i = 2
  while i <= lane.size do
    local p1 = lane.points[i - 1]
    local p2 = lane.points[i]
    local c1 = self.shape:contains(p1)
    local c2 = self.shape:contains(p2)

    if i == 2 and c1 and lane.loop then
      while c2 do
        i = i + 1
        p1, p2 = p2, lane.points[i]
        c1, c2 = c2, self.shape:contains(p2)
      end

      local h = self.shape:intersect(p1, p2)
      if not h then
        error('Failed to find an intersection')
      end
      loopStart, loopStartPos = calculateDistanceAndPos(lane.size, p1, p2, h)

    elseif c1 ~= c2 then

      local h, side = self.shape:intersect(c2 and p1 or p2, c2 and p2 or p1)
      if not h then
        error('Failed to find an intersection')
      end

      local distance, pos = calculateDistanceAndPos(i - 1, p1, p2, h)
      if c2 then
        start, startSide = distance, side
        startPos = pos
      else
        local item = IntersectionLink(self, lane, start, distance, startPos, pos, startSide, side)
        lane:addIntersectionLink(item)
        self:_addLink(item)
        start = 0
      end

    elseif not c1 and not c2 then
      if start ~= 0 then
        error('Intersections intersect?')
      end

      local h1, side1 = self.shape:intersect(p1, p2)
      if h1 ~= nil then
        local h2, side2 = self.shape:intersect(p2, p1)
        if h2 == nil then
          error('Failed to find a second intersection')
        end

        local distance1, pos1 = calculateDistanceAndPos(i - 1, p1, p2, h1)
        local distance2, pos2 = calculateDistanceAndPos(i - 1, p1, p2, h2)
        local item = IntersectionLink(self, lane, distance1, distance2, pos1, pos2, side1, side2)
        lane:addIntersectionLink(item)
        self:_addLink(item)
      end
    end

    i = i + 1
  end

  if loopStartPos ~= nil then
    local item = IntersectionLink(self, lane, start, loopStart,
      startPos, loopStartPos, startSide, 0)
    lane:addIntersectionLink(item)
    self:_addLink(item)
  elseif start ~= 0 then
    local item = IntersectionLink(self, lane, start, lane.totalDistance,
      startPos, lane.loop and lane.points[1] or nil, startSide, 0)
    lane:addIntersectionLink(item)
    self:_addLink(item)
  end ]]