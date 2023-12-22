if Sim.isShowroomMode then return end

local loadRemote = Config:get('CUSTOM_DRIVER_MODELS', 'LOAD_REMOTE', 'NONE')
local ownKey = Config:get('CUSTOM_DRIVER_MODELS', 'DRIVER_MODEL_KEY', ''):trim()
if loadRemote == 'NONE' and ownKey == '' then return end

local serverSuggestsAll = nil
local anySet = false
local ev = ac.OnlineEvent({
  ac.StructItem.key('.smallTweaks.customDriverModels'),
  userID = ac.StructItem.string(16),
  modelData = ac.StructItem.string(150)
}, function (sender, message)
  if sender == nil or sender.index == 0 or loadRemote == 'NONE' then return end

  if serverSuggestsAll == nil then
    local cfg = ac.INIConfig.onlineExtras()
    if cfg then
      serverSuggestsAll = cfg:get('EXTRA_TWEAKS', 'ALLOW_ANY_CUSTOM_DRIVER_MODELS', false)
    else
      serverSuggestsAll = false
    end
  end

  local simfriendlyOnly = loadRemote ~= 'ALL' and (not serverSuggestsAll or loadRemote == 'SIMFRIENDLY')
  local url = ac.verifyCustomModel(message.modelData, message.userID, simfriendlyOnly)
  if url then
    ac.replaceDriverModel(sender.index, url)
    if not anySet then
      anySet = true
      ac.onClientConnected(function (connectedCarIndex, connectedSessionID)
        ac.replaceDriverModel(connectedCarIndex, nil)
      end)
    end
  end
end)

if ownKey ~= '' then
  ac.log('Own key: '..ownKey)
  ac.readCustomModel(ownKey, function (err, data, userID)
    if err then
      ac.warn('Failed to load custom model: '..err)
      return
    end

    ac.log('Response data', data)
    local url = ac.verifyCustomModel(data, userID, false)

    ac.log('Verified URL', url)
    if url then
      setTimeout(function ()
        ac.replaceDriverModel(0, url)
      end, 0)
      ev({ userID = userID, modelData = data }, true)
    else
      ac.warn('Failed to verify URL')
    end
  end)
end

