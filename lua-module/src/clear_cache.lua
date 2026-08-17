if not __script.cspUpgraded or not ConfigGeneral:get('CONFIGURATIONS', 'CLEAR_CSP_CACHE', false) then
  return
end

print('Clearing out CSP cache…')
ac.startBackgroundWorker([[
  local threshold = os.time() - 14 * 24 * 60 * 60
  local function fitForRemoval(attrs)
    return attrs.creationTime < threshold 
      and attrs.lastWriteTime < threshold
      and attrs.lastAccessTime < threshold
  end

  local function clearDir(dir, mask, includeSubdirs)
    if dir:sub(1, 1) == '/' then
      dir = ac.getFolder(ac.FolderID.ExtCache)..dir
    end
    print('Clearing out dir: %s' % dir)
    io.scanDir(dir, '*', function (fileName, fileAttributes, callbackData)
      if not fitForRemoval(fileAttributes) then
        -- file is too new
      elseif mask and not string.regfind(fileName, mask) then
        print('  Unexpected file: %s' % fileName)
      elseif not fileAttributes.isDirectory then
        ac.log('  Deleting %s' % fileName)
        io.deleteFile(dir..'/'..fileName)
      elseif includeSubdirs then
        ac.warn('  Deleting dir %s' % fileName)
        require('shared/utils/ioext').deleteUsingShell(dir..'/'..fileName)
      end
    end)
  end

  clearDir('/ai_payloads', '^.+__[0-9a-f]+\\.(?:bin|tmp)$')
  clearDir('/binaries', '^[0-9a-f]{32,80}(?:\\.tmp)?$')
  clearDir('/csp_configs', '\\.(?:zip|tmp)$')
  clearDir('/lua', '^[0-9a-f]{4,20}(?:\\.tmp)?$')
  clearDir('/lua_shaders', '^[0-9a-f]{4,20}\\.(?:zip|tmp)')
  clearDir('/meshes_metadata', '^[0-9a-fn]{4,20}\\.(?:bin|tmp)$')
  clearDir('/preview_state', '\\.(?:bin|tmp)$')
  clearDir('/track_logos', '^[0-9a-f]{4,20}\\.(?:dds|tmp)$')
  clearDir('/web', '^[0-9a-f]{32,80}(?:\\.tmp)?$')
  clearDir('/remote_assets', '^[0-9a-f]{64}(?:\\.tmp)?$', true)
  -- clearDir('/remote_animations', '^[0-9a-f]{64}(?:\\.tmp)?$')
  -- clearDir('/remote_models', '^[0-9a-f]{64}(?:\\.tmp)?$')

  clearDir(ac.getFolder(ac.FolderID.Logs), '^crash_.+\\.(?:dmp|zip|report)$')
]], function (err)
  print('Clearing is complete, err.=', err)
end)
