if not Sim.isOnlineRace then return end

local settings = Config:mapSection('MUMBLE', { AUTOCONNECT = true, AUTOCLOSE = true })
if not settings.AUTOCONNECT then return end

local function mumbleRun(commands)
  local knownPaths = {
    'C:/Program Files/Mumble/client/mumble.exe',
    'C:/Program Files (x86)/Mumble/client/mumble.exe',
  }
  local found = table.findFirst(knownPaths, io.fileExists)
  if found then
    os.runConsoleProcess({ filename = found, arguments = commands })
  end
end

setTimeout(function ()
  local url = ac.INIConfig.onlineExtras():get('MUMBLE', 'AUTOCONNECT', '')
  if url:startsWith('mumble://') then
    url = url:gsub('{([A-Za-z]+)}', function (k)
      if k == 'EntryIndex' then return ac.getCar(0).sessionID end
      if k == 'DriverName' then return ac.getDriverName(0):reggsub('[^a-zA-Z0-9_.-]', ' '):trim():gsub(' ', '_') end
      if k == 'ServerPassword' then return  ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg)..'/race.ini'):get('REMOTE', 'PASSWORD', '') end
    end)

    if settings.AUTOCLOSE then
      os.runConsoleProcess({ filename = 'C:/Windows/System32/tasklist.exe', arguments = { '/NH', '/FI', 'IMAGENAME eq mumble.exe' } }, function (err, data)
        if not err and not data.stdout:regfind('mumble.exe', 1, true) then
          ac.onRelease(function ()
            os.runConsoleProcess({ filename = 'C:/Windows/System32/taskkill.exe', arguments = { '/F', '/IM', 'mumble.exe' } })
          end)
        end
        mumbleRun{ url }
      end)
    else
      mumbleRun{ url }
    end
  end
end, 1)
