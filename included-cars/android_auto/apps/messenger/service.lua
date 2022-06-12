---@alias MessengerContact { carIndex: integer, name: string, history: { message: string, time: integer, read: boolean|nil }[], anyUnread: boolean, sending: number, lastAccessTime: integer }

Messenger = {}

local contacts = stringify.tryParse(ac.storage.messengerData, nil, {})
local orderedContactsCache = {}
local orderedContactsDirty = true

for _, v in pairs(contacts) do
  v.sending = 0
  v.newMessageAdded = nil
  v.message = nil
  if v.anyUnread then
    system.notificationMark(true)
  end
end

function Messenger.saveContacts()
  ac.storage.messengerData = stringify(contacts, true)
end

local eventChatRead = ac.OnlineEvent({
  ac.StructItem.key('messenger:readFlag'),
  to = ac.StructItem.byte()
}, function (sender, data)
  if sender and data.to == car.sessionID then
    local h = Messenger.getContact(sender.index).history
    for i = 1, #h do
      if h[i].own then
        h[i].read = true
      end
    end
    Messenger.saveContacts()
  end
end)

local eventChatMessage = ac.OnlineEvent({
  ac.StructItem.key('messenger:message'),
  to = ac.StructItem.byte(),
  message = ac.StructItem.string(140)
}, function (sender, data)
  if sender and data.to == car.sessionID then
    setTimeout(function ()
      local c = Messenger.getContact(sender.index)
      table.insert(c.history, { message = data.message, time = tonumber(sim.timestamp) })
      c.newMessageAdded = ui.time()
      c.lastAccessTime = sim.timestamp
      c.anyUnread = true
      orderedContactsDirty = true
      Messenger.saveContacts()
      system.setNotification(function (size) system.contactIcon(c.carIndex, c.name, size) end, c.name, data.message, false, true, c)
      system.notificationMark(true)
    end, 0.1)
  end
end)

---@return MessengerContact
function Messenger.getContact(carIndex, driverName)
  if not driverName then driverName = ac.getDriverName(carIndex) end
  local ret = table.getOrCreate(contacts, driverName, function ()
    orderedContactsDirty = true
    return { carIndex = carIndex, name = driverName, history = {}, message = '', anyUnread = false, sending = 0, lastAccessTime = tonumber(sim.timestamp) }
  end)
  if ret.carIndex ~= carIndex then ret.carIndex = carIndex end
  return ret
end

---@return MessengerContact[]
function Messenger.orderedContacts()
  if orderedContactsDirty then
    orderedContactsDirty = false
    table.clear(orderedContactsCache)
    for _, i in pairs(contacts) do
      if #i.history > 0 then
        orderedContactsCache[#orderedContactsCache + 1] = i
      end
    end
    table.sort(orderedContactsCache, function (a, b) return a.lastAccessTime > b.lastAccessTime end)
  end
  return orderedContactsCache
end

---@param contact MessengerContact
function Messenger.tryReplyWithRead(contact)
  if not eventChatRead({ to = ac.getCar(contact.carIndex).sessionID }) then
    setTimeout(function () Messenger.tryReplyWithRead(contact) end, 1)
  end
end

---@param contact MessengerContact
---@param message string
function Messenger.trySend(contact, message)
  table.insert(contact.history, { own = true, message = message, time = tonumber(sim.timestamp) })
  contact.newMessageAdded = ui.time()
  contact.lastAccessTime = sim.timestamp
  orderedContactsDirty = true
  Messenger.saveContacts()
  if not eventChatMessage({ to = ac.getCar(contact.carIndex).sessionID, message = message }) then
    contact.sending = 1
    setTimeout(function () Messenger.trySend(contact, message) end, 0.5)
  else
    contact.sending = 0.5
  end
end

function Messenger.formatTime(timestamp)
  return os.dateGlobal('%H:%M', timestamp)
end

---@param contact MessengerContact
function Messenger.markContactAsRead(contact)
  if contact.anyUnread then
    setTimeout(function ()
      contact.anyUnread = false
      system.notificationMark(table.some(orderedContactsCache, function (item) return item.anyUnread end))
      Messenger.tryReplyWithRead(contact)
      Messenger.saveContacts()
    end, 0.5, 'markAsRead:'..contact.name)
  end
end

-- if next(contacts) == nil then
--   if math.random() > 0.8 then table.insert(Messenger.getContact(-1, 'T-Mobile').history, { message = 'T-Mobile SIM Card only $4.95', time = tonumber(sim.timestamp - 1e5 * math.random()) }) end
--   if math.random() > 0.8 then table.insert(Messenger.getContact(-1, 'MOVNOW').history, { message = 'Happy Newyear from MOVIES NOW!', time = tonumber(sim.timestamp - 1e5 * math.random()) }) end
-- end

-- setTimeout(function ()
--   system.setNotification(ui.Icons.Python, 'Test', 'Close me', false, true)
-- end, 0)
