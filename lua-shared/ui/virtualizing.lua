--[[
  Library with some things related to make massive lists easier.

  To use, include with `local virtualizing = require('shared/ui/virtualizing')` and then call `virtualizing.List(…)`.
]]

local virtualizing = {}

---Renders large (up to 10k) lists of items. Takes a reference to the collection and a function that will be called for
---each item to render it on the screen, and returns a function which, when called, would draw the elements. If source
---collection has changed, call the returned function with `'refresh'` parameter to signal that recomputation is needed.
---
---Each item will be measured with its height stored for accurate scrolling.Note: if your list is more like 100k items, 
---consider using a fixed size for each item instead and just do a simple loop.
---@generic TSource
---@param source TSource[] @Source collection.
---@param render fun(item: TSource) @Function that will be called for each item to draw it on the screen.
---@return fun(param: string?) @Function for rendering the list. Alternatively, call it with `'refresh'` argument to refresh the list.
function virtualizing.List(source, render)
  return virtualizing.WrappedList(source, nil, render)
end

---Renders large (up to 10k) lists of items with a function that can do some precomputation and convert items into something
---else (like parsing a line of text into a bunch of words). Takes a reference to the collection, a function that will be called
---for each item to get its wrapped version and a function that will be called for each item to render it on the screen, and 
---returns a function which, when called, would draw the elements. If source collection has changed, call the returned function 
---with `'refresh'` parameter to signal that recomputation is needed.
---
---Each item will be measured with its height stored for accurate scrolling. Note: if your list is more like 100k items, 
---consider using a fixed size for each item instead and just do a simple loop.
---@generic TSource
---@generic TWrapped
---@generic TParam
---@param source TSource[] @Source collection.
---@param wrapper nil|fun(item: TSource): TWrapped @Wrapping function turning item into its wrapped version.
---@param render fun(item: TWrapped, posX: number, posY: number, param: TParam): number @Function that will be called for each item to draw it on the screen.
---@return fun(notify: TParam|string?, hint: string?) @Function for rendering the list. Alternatively, call it with `'refresh'` argument to refresh the list. For large or frequently updating lists `hint` parameter can specify refresh type to speed things up: `'pushBack'` for a single item added to the end of source list, `'popFront'` for a single item removed from the beginning of a list.
function virtualizing.WrappedList(source, wrapper, render)
  local sourceSize = #source
	local lastOffset, lastSkip = -1, 0
	local measuredHeight, measuredCount = 0, 0
	local cache = setmetatable({}, { __mode = 'kv' })
	local items = {}
  local itemsSize = 0
	local processingNext = 1
	local scrolledToBottom, scrollToBottom = 0, 0
  local dummySize = vec2(1, 1)
  local anyLastNotify, lastNotify = false, { push = 0, pop = 0 }
  local maxCurPos = -1

  local function getWrapped(raw)
    local cached = cache[raw]
    if not cached then
      cached = wrapper and wrapper(raw) or raw
      cache[raw] = cached
    end
    return cached
  end

  local function setItem(index, wrapped)
    items[index] = { wrapped = wrapped, height = -1, startsAt = 0 }
    if index > itemsSize then itemsSize = index end
  end

  local function removeItem(index)
    local removed = table.remove(items, index)
    itemsSize = itemsSize - 1
    if removed.height >= 0 then
      for i = index, itemsSize do
        if items[i].startsAt ~= 0 then
          items[i].startsAt = items[i].startsAt - removed.height
        end
      end
    end
  end

	local function findFirstItem(item, index, offset)
		return index > 0 and item.startsAt == 0 or item.startsAt > offset
	end

  local function processNotify(hint)
    if processingNext == 0 and hint == 'pushBack' then
      if source[sourceSize + 1] == nil then error('Invalid pushBack hint') end
      sourceSize = sourceSize + 1
      lastNotify.push = lastNotify.push + 1
      anyLastNotify = true
    elseif hint == 'popFront' then
      if source[sourceSize] ~= nil then error('Invalid pushBack hint') end
      sourceSize = sourceSize - 1
      lastNotify.pop = lastNotify.pop + 1
      anyLastNotify = true
    else
      sourceSize = #source
      processingNext = 1
      lastNotify.push, lastNotify.pop = 0, 0
      anyLastNotify = false
    end
    if scrolledToBottom > 0 then
      scrollToBottom = 5
    end
  end

  local function syncNotify()
    while lastNotify.pop > 0 do
      removeItem(1)
      lastNotify.pop = lastNotify.pop - 1
    end
    while lastNotify.push > 0 do
      setItem(itemsSize + 1, getWrapped(source[itemsSize + 1]))
      lastNotify.push = lastNotify.push - 1
    end
    anyLastNotify = false
  end

  local function updateData()
    local createUntil = os.preciseClock() + 0.001 -- 1 ms for creating items
    local testForRemoved = true
    while true do
      local raw = source[processingNext]
      local cached = getWrapped(raw)
      local existing = items[processingNext]
      if not existing or existing.wrapped ~= cached then
        if os.preciseClock() > createUntil then
          break
        end
        local next = testForRemoved and items[processingNext + 1]
        if next and next.wrapped == cached then
          removeItem(processingNext)
        else
          setItem(processingNext, cached)
        end
        testForRemoved = false
        lastOffset = -1
      end
      if processingNext == sourceSize then
        while itemsSize > sourceSize do
          table.remove(items, itemsSize)
          itemsSize = itemsSize - 1
        end
        processingNext = 0
        break
      else
        processingNext = processingNext + 1
      end
    end
  end

  local scrollingOffset = 0

	return function (notify, hint)
    if notify == 'refresh' then
      processNotify(hint)
      return
    end

    if sourceSize == 0 then
      return
    end

		if processingNext > 0 then
      updateData()
    elseif anyLastNotify then
      syncNotify()
		end

		local offset = ui.getScrollY()
    local scrollingNow = ui.mouseDown(ui.MouseButton.Left)
    ac.debug('scrollingOffset', scrollingOffset)
    if scrollingOffset ~= 0 then
      if scrollingNow then
        offset = offset - scrollingOffset
      else
        offset = offset - scrollingOffset
        ui.setScrollY(offset, false, false)
        scrollingOffset = 0
      end
    end

		local spaceX = ui.windowWidth()
		local renderUntil = offset + ui.availableSpaceY()
		local measureUntil = os.preciseClock() + 0.0005 -- 0.5 ms for measuring items

    local skip
    if lastOffset == offset then
      skip = lastSkip
    else
      skip = math.max(1, table.findLeftOfIndex(items, findFirstItem, offset))
			lastOffset, lastSkip = offset, skip
    end

    local startingItem = items[skip]
    if not startingItem then
      return
    end

    local posX = ui.getCursorX()
    local curPos = startingItem.startsAt
    local lastDrawn = 0
    local newPos
		for i = skip, itemsSize do
			local item = items[i]
      local oldStart, oldHeight = item.startsAt, item.height
			local needsMeasure = oldHeight == -1
			if needsMeasure or oldStart + oldHeight > offset and oldStart < renderUntil then
        if not newPos then ui.setCursorY(curPos + scrollingOffset) end
        newPos = render(item.wrapped, posX, curPos + scrollingOffset, notify)
        local newHeight = (newPos or ui.getCursorY()) - (curPos + scrollingOffset)
        if needsMeasure or newHeight ~= oldHeight then
          if not needsMeasure then
            local shift = newHeight - oldHeight
            for j = i + 1, itemsSize do
              if items[j].startsAt ~= 0 then
                items[j].startsAt = items[j].startsAt + shift
              end
            end
          end
          if scrollingNow and i == skip then
            scrollingOffset = scrollingOffset - newHeight + (needsMeasure and measuredHeight / measuredCount or oldHeight)
          end
          if not needsMeasure and spaceX == item.spaceX then
            ac.error('Same width, different size: %s≠%s' % {oldHeight, newHeight})
          end
          item.spaceX = spaceX
          item.height = newHeight
          item.startsAt = curPos
          measuredHeight, measuredCount = measuredHeight + newHeight, measuredCount + 1
          oldHeight = newHeight
        end
        curPos = curPos + oldHeight
        lastDrawn = i
        if needsMeasure and os.preciseClock() > measureUntil then
          break
        end
			elseif lastDrawn > 0 then
				break
			end
		end
    
		local lastItem = items[itemsSize]
    if lastItem.startsAt ~= 0 and processingNext == 0 then
      curPos = lastItem.startsAt + lastItem.height
    elseif measuredCount > 0 then
      curPos = curPos + measuredHeight / measuredCount * (sourceSize - lastDrawn)
    end

    ui.setCursorY(curPos - 1)
		ui.dummy(dummySize)

    if not scrollingNow then
      maxCurPos = curPos
    end
    ui.setMaxCursorY(maxCurPos - 1)

		if scrollToBottom > 0 then
      ui.setScrollY(1e9)
			scrollToBottom = scrollToBottom - 1
      scrolledToBottom = 2
    else
      scrolledToBottom = offset > ui.getScrollMaxY() - 5 and 2 or scrolledToBottom - 1
      if scrolledToBottom > 0 then
        ui.setScrollY(1e9)
      end
		end
	end
end

return virtualizing