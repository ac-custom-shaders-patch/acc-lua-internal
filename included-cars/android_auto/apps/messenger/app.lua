local activeDialogPopup

local bgOwnMessage = rgbm.new('#2B6AC1')
local bgOtherMessage = rgbm.new('#242529')
local accentColor = rgbm.new('#33B5E5')

local msgSizeCache = {}
local function dialogPopup(dt)
  local contact = system.getPopupData()
  Messenger.markContactAsRead(contact)
  system.closeNotificationWith(contact)

  local contactHere = contact.name == ac.getDriverName(contact.carIndex)
  if not contactHere then
    for i = 0, sim.carsCount - 1 do
      if ac.getDriverName(i) == contact.name then
        contact.carIndex = i
        contactHere = true
        break
      end
    end
  end

  local keyboardOffset = math.max(0, touchscreen.keyboardOffset() - system.bottomBarHeight)
  local messagesHeight = ui.availableSpaceY() - 44 - keyboardOffset

  ui.offsetCursorX(80)
  ui.childWindow('messages', vec2(ui.availableSpaceX() - 80, messagesHeight), function ()
    local sx = ui.availableSpaceX()
    local wrapWidth = sx * 0.8 - 48
    local lastHeight = 0
    for i = 1, #contact.history do
      local msg = contact.history[i]
      local msize = msgSizeCache[msg]
      if not msize then
        local size = ui.measureText(msg.message, wrapWidth) + vec2(16, 16)
        msize = { size = size, itemSize = vec2(size.x, size.y + (msg.own and 24 or 28)) }
        msgSizeCache[msg] = msize
      end

      lastHeight = msize.itemSize.y
      if not ui.areaVisible(msize.itemSize) then
        ui.offsetCursorY(msize.itemSize.y)
      elseif msg.own then
        ui.offsetCursorY(4)
        ui.offsetCursorX(sx - msize.size.x - 8)
        local c = ui.getCursor()
        ui.drawRectFilled(c, c + msize.size, bgOwnMessage, 12)
        ui.offsetCursor(vec2(8, 8))
        ui.textWrapped(msg.message, ui.getCursorX() + wrapWidth - 8)
        if msg.read then
          ui.offsetCursor(vec2(ui.availableSpaceX() - 57, 8))  
          ui.icon(ui.Icons.Confirm, 8)
          ui.sameLine(0, 0)
          ui.offsetCursorX(-3)
          ui.icon(ui.Icons.Confirm, 8)
          ui.sameLine()
        else
          ui.offsetCursor(vec2(ui.availableSpaceX() - 36, 8))  
        end
        ui.pushFont(ui.Font.Tiny)
        ui.text(Messenger.formatTime(msg.time))
        ui.popFont()
        ui.offsetCursorY(4)
      else
        ui.offsetCursorY(10)        
        local c = ui.getCursor()
        ui.drawRectFilled(c + vec2(48, 0), c + vec2(48, 0) + msize.size, bgOtherMessage, 12)
        ui.offsetCursor(vec2(48 + 8, 8))
        ui.textWrapped(msg.message, ui.getCursorX() + wrapWidth - 8)
        ui.offsetCursor(vec2(48 + 8, 8))
        ui.pushFont(ui.Font.Tiny)
        ui.text(Messenger.formatTime(msg.time))
        ui.popFont()
        ui.setCursor(vec2(c.x, c.y + msize.size.y - 36))
        system.contactIcon(contact.carIndex, contact.name)
        ui.offsetCursorY(10)
      end
    end
    
    system.scrollFadeTop()
    touchscreen.scrolling()

    if contact.forceScrolling > 0 then
      contact.forceScrolling = contact.forceScrolling - 1
      ui.setScrollY(ui.getScrollMaxY(), false, false)
    elseif not touchscreen.touched() and contact.newMessageAdded and ui.getScrollY() + keyboardOffset + lastHeight > ui.getScrollMaxY() - 10 then
      ui.setScrollY(ui.getScrollMaxY(), false, true)
    elseif touchscreen.scrollingVelocity() < -0.5 and keyboardOffset == 0 then
      contact.scrolledToBottom = false
    else
      if keyboardOffset == 0 then contact.scrolledToBottom = ui.getScrollY() + keyboardOffset > ui.getScrollMaxY() - 10 end
      if touchscreen.scrollingVelocity() < 0.1 and contact.scrolledToBottom then ui.setScrollY(ui.getScrollMaxY(), false, false) end
    end
  end)

  ui.offsetCursorX(4)
  if contact.sending > 0 then
    contact.sending = contact.sending - dt
    ui.drawRectFilled(ui.getCursor(), ui.getCursor() + vec2(ui.availableSpaceX() - 8, 32), rgbm(1, 1, 1, 0.05))
    ui.offsetCursor(vec2(8, 8))
    touchscreen.loading(16)
  elseif not contactHere then
    ui.drawRectFilled(ui.getCursor(), ui.getCursor() + vec2(ui.availableSpaceX() - 8, 32), rgbm(1, 1, 1, 0.05))
    ui.offsetCursor(vec2(12, 2))
    ui.pushFont(ui.Font.Title)
    ui.textColored('Contact is not available', rgbm.colors.gray)
    ui.popFont()
  else
    ui.pushFont(ui.Font.Title)
    ui.setNextItemWidth(ui.availableSpaceX() - 8)
    local changed
    contact.message, changed = touchscreen.inputText('Write a message', contact.message, ui.InputTextFlags.Placeholder)
    if changed or ui.itemDeactivatedAfterEdit() then
      Messenger.saveContacts()
    end
    if changed and #contact.message > 0 then
      Messenger.trySend(contact, contact.message)
      contact.message = ''
    end
    ui.popFont()
  end
end

local function contactsPopup(dt)
  system.scrollList(dt, function ()
    local itemSize = vec2(ui.availableSpaceX(), 54)
    local any = false
    for i = 0, sim.carsCount - 1 do
      if i > 0 and ac.getCar(i).isRemote then
        any = true
        if ui.areaVisible(itemSize) then
          local driverName = ac.getDriverName(i)
          local color = rgbm.colors.white
          local c = ui.getCursor()
          if touchscreen.listItem(itemSize) then
            system.closePopup(nil, { driverName = driverName, carIndex = i })
          end
          ui.offsetCursorX(20)
          ui.offsetCursorY(6)
          system.contactIcon(i, driverName)
          ui.setCursor(c + vec2(74, 12))
          ui.dwriteText(driverName, 20, color)
          ui.offsetCursorY(12)
        else
          ui.dummy(itemSize)
        end
      end
    end
    if not any then
      ui.setCursor(0)
      ui.textAligned('No contacts found', 0.5, ui.windowSize() - vec2(0, 60))
    end
    system.scrollFadeTop()
  end)
end

local function openDialog(carIndex, driverName)
  local contact = Messenger.getContact(carIndex, driverName)
  Messenger.markContactAsRead(contact)
  contact.scrolledToBottom = true
  contact.forceScrolling = 10
  activeDialogPopup = system.openPopup(contact.name, dialogPopup)
  system.setPopupData(activeDialogPopup, contact)
end

return function (dt, contactToOpen)
  local ordered = Messenger.orderedContacts()

  if contactToOpen and contactToOpen.carIndex and contactToOpen.name then
    openDialog(contactToOpen.carIndex, contactToOpen.name)
  end

  if #ordered == 0 then
    ui.textAligned('No messages', 0.5, ui.availableSpace())
  else
    system.scrollList(dt, function ()
      local ww = ui.windowWidth()
      local itemSize = vec2(ww, 56)
      for i = 1, #ordered do
        if ui.areaVisible(itemSize) then
          -- i = (i - 1) % #ordered + 1
          local contact = ordered[i]
          if touchscreen.listItem(itemSize) then
            openDialog(contact.carIndex, contact.name)
          end
          ui.offsetCursorY(8)
          ui.offsetCursorX(12)
          system.contactIcon(contact.carIndex, contact.name)
          ui.sameLine(0, 12)
          ui.offsetCursorY(-4)
          ui.dwriteText(contact.name, 20)
          ui.sameLine(ww - 32-12)
          ui.offsetCursorY(8)
          local lastMessage = contact.history[#contact.history]
          ui.dwriteText(lastMessage and Messenger.formatTime(lastMessage.time) or '', 12, rgbm.colors.gray)
          ui.offsetCursorX(52+12)
          ui.offsetCursorY(-24)
          if contact.anyUnread then
            ui.pushDWriteFont('Segoe UI;Weight=Bold')
            ui.drawCircleFilled(ui.getCursor() + vec2(4, 8), 3, accentColor)
            ui.offsetCursorX(14)
          end
          ui.dwriteTextAligned(lastMessage and lastMessage.message or '', 12, ui.Alignment.Start, ui.Alignment.Start, vec2(ui.availableSpaceX() - 12, 0), false, rgbm.colors.gray)
          if contact.anyUnread then ui.popDWriteFont() end
          ui.offsetCursorY(20)
        else
          ui.offsetCursorY(itemSize.y)
        end
      end
    end)
  end

  ui.setCursor(ui.windowSize() + vec2(-100, ui.getScrollY() - 100))
  if touchscreen.addButton() then
    system.openPopup('Contacts', contactsPopup, function (selected)
      if selected then
        system.closePopup(activeDialogPopup)
        openDialog(selected.carIndex, selected.driverName)
      end
    end)
  end
end