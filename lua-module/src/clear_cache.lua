if __justUpgraded__ and ConfigGeneral:get('CONFIGURATIONS', 'CLEAR_CSP_CACHE', false) then
  ac.startBackgroundWorker([[
    local function clearDir(dir, mask)
      print('Clearing cache dir: %s' % dir)
      local dirpath = ac.getFolder(ac.FolderID.ExtCache)..'/'..dir
      for i, v in ipairs(io.scanDir(dirpath)) do
        if not string.regfind(v, mask) then
          print('  Unexpected file: %s' % v)
        else
          io.deleteFile(dirpath..'/'..v)
        end
      end
    end
    clearDir('binaries', '^[0-9a-f]{32,80}$')
    clearDir('csp_configs', '\\.zip$')
    clearDir('lua', '^[0-9a-f]{4,20}$')
    clearDir('lua_shaders', '^[0-9a-f]{4,20}\\.zip')
    clearDir('meshes_metadata', '^[0-9a-fn]{4,20}\\.bin$')
    clearDir('preview_state', '\\.bin$')
    clearDir('web', '^[0-9a-f]{32,80}$')
  ]])
end