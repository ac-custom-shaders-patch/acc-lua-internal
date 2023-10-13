---@ext
--[[
  Some common controls to use with WebBrowser library. No need to use these ones, but they might save some time 
  if you’re making an app and don’t want to, for example, implement custom error messages or dialog-handling logic.

  Usage:

  ```lua
  local WebBrowser = require('shared/web/browser')
  local WebUI = require('shared/web/ui')

  local browser = WebBrowser()
  browser:onFileDialog(WebUI.DefaultHandlers.onFileDialog)
  ```
]]

local WebBrowser = require('shared/web/browser')
local webUI = {}

---Some default event handlers for full UX (don’t use these if you want more blend-in seamless experience, these would, for example,
---show a fullscreen message if a webpage would want to show an alert).
webUI.DefaultHandlers = {}

---Some basic popup messages.
webUI.DefaultPopups = {}

---@type WebBrowser.Handler.Download
function webUI.DefaultHandlers.onDownload(tab, data, callback)
  os.saveFileDialog({
    title = 'Download',
    defaultFolder = ac.getFolder(ac.FolderID.Documents),
    fileName = data.suggestedName,
    addAllFilesFileType = true,
    fileTypes = {{name = 'Files', mask = '*'..data.suggestedName:regmatch('\\.\\w+$')}},
    fileTypeIndex = 1,
    defaultExtension = data.suggestedName:regmatch('\\.(\\w+)$')
  }, function (err, filename)
    callback(not err and filename or nil)
  end)
end

---@type WebBrowser.Handler.FileDialog
function webUI.DefaultHandlers.onFileDialog(tab, data, callback)
  if data.type == 'save' then
    os.saveFileDialog({
      title = data.title or 'Save',
      defaultFolder = data.defaultFilePath and io.getParentPath(data.defaultFilePath) or '',
      fileName = data.defaultFilePath,
      fileTypes = WebBrowser.convertAcceptFiltersToFileTypes(data.acceptFilters),
      defaultExtension = data.defaultFilePath and data.defaultFilePath:regmatch('\\.(\\w+)$'),
    }, function (err, filename) callback(not err and {filename} or nil) end)
  else
    os.openFileDialog({
      title = data.title or 'Open',
      defaultFolder = data.defaultFilePath and io.getParentPath(data.defaultFilePath) or '',
      fileName = data.defaultFilePath,
      fileTypes = WebBrowser.convertAcceptFiltersToFileTypes(data.acceptFilters),
      flags = data.type == 'openFolder'
        and bit.bor(os.DialogFlags.PickFolders, os.DialogFlags.FileMustExist, os.DialogFlags.PathMustExist)
        or data.type == 'openMultiple'
          and bit.bor(os.DialogFlags.AllowMultiselect, os.DialogFlags.FileMustExist, os.DialogFlags.PathMustExist)
          or nil
    }, function (err, ...) callback(not err and {...} or nil) end)
  end
end

---@type WebBrowser.Handler.AuthCredentials
function webUI.DefaultHandlers.onAuthCredentials(tab, data, callback)
  local username, password = '', ''
  ui.modalDialog('Sign in', function ()
    username = ui.inputText('Username', username, ui.InputTextFlags.Placeholder)
    password = ui.inputText('Password', password, bit.bor(ui.InputTextFlags.Placeholder, ui.InputTextFlags.Password))
    ui.newLine()
    ui.offsetCursorY(4)
    if ui.modernButton('OK', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Confirm) then
      callback(username, password)
      return true
    end
    ui.sameLine(0, 8)
    return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel)
  end, true, function ()
    callback(nil, nil)
  end)
end

---@type WebBrowser.Handler.JavaScriptDialog
function webUI.DefaultHandlers.onJavaScriptDialog(tab, data, callback)
  if data.type == 'alert' then -- two other ones are ignored at the moment (also, there is no API to reply to a prompt yet)
    ui.modalDialog(tab:domain()..' says', function ()
      ui.textWrapped(data.message)
      ui.newLine()
      ui.offsetCursorY(4)
      return ui.modernButton('OK', vec2(-0.1, 40), ui.ButtonFlags.None, ui.Icons.Confirm)
    end, true, function () callback(true, nil) end)
  elseif data.type == 'confirm' then
    ui.modalPopup(tab:domain()..' says', data.message, 'Confirm', 'Cancel', ui.Icons.Confirm, ui.Icons.Cancel, function (okPressed)
      callback(okPressed, nil)
    end)
  elseif data.type == 'prompt' then
    ui.modalPrompt(tab:domain()..' asks', data.message, data.defaultPrompt, function (value)
      callback(value ~= nil, value)
    end)
  elseif data.type == 'beforeUnload' then
    ui.modalPopup('Leave site?', 'Changes you made may not be saved.', 'Confirm', 'Cancel', ui.Icons.Confirm, ui.Icons.Cancel, function (okPressed)
      callback(okPressed, nil)
    end)
  else
    callback(false, '')
  end
end

---Basic error message to be drawn in place of a tab if `WebBrowser:draw()` returns an error message.
---@param p1 vec2
---@param p2 vec2
---@param loadError WebBrowser.LoadError?
---@param drawError string?
---@return 'ignore'|'reload'
function webUI.drawErrorMessage(p1, p2, loadError, drawError)
  local ret, title, message, status
  local pivot = vec2(p1.x + 80, p1.y + 40)

  if loadError then
    title, message, status = 'This webpage can’t be loaded', 'Check your internet connection.', loadError.errorText
  else
    title, message, status = 'This webpage can’t be displayed', 'Browser engine had a malfunction.', 'ERR_ACEF_'..tostring(drawError):upper()
  end

  ui.pushFont(ui.Font.Title)
  ui.drawTextClipped(title, pivot, p2, rgbm.colors.white, 0)
  ui.popFont()
  ui.drawTextClipped(message, vec2(0, 40):add(pivot), p2, rgbm.colors.white, 0)
  ui.drawTextClipped(status, vec2(0, 60):add(pivot), p2, rgbm.colors.gray, 0)
  local c = ui.getCursor()
  ui.setItemAllowOverlap()
  ui.setCursor(vec2(0, 92):add(pivot))
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
  ac.debug('Error status', status)
  if status == 'ERR_CERT_COMMON_NAME_INVALID' then
    if ui.button('Proceed anyway') then
      ret = 'ignore'
    end
    ui.sameLine(0, 4)
  end
  if ui.button('Reload') then
    ret = 'reload'
  end
  ui.popStyleVar()
  ui.setCursor(c)
  return ret
end

local faviconCache = {}

---Loads a simple 32×32 PNG image ready to be drawn using CEF of a given tab. Unlike using URL to draw image directly, this way things
---like SVG icons would also work.
---@param tab WebBrowser
---@param favicon string?
function webUI.favicon(tab, favicon)
  favicon = favicon or tab:favicon()
  if not favicon then
    return nil
  end
  local v = faviconCache[favicon]
  if not v then
    if favicon:startsWith('http') then
      v = 'color::#00000000'
      tab:downloadImageAsync(favicon, true, 32, function (err, data)
        if err then
          faviconCache[favicon] = ui.Icons.Earth
        else
          faviconCache[favicon] = ui.decodeImage(data) or 'color::#ff0000'
        end
      end)
    else
      v = favicon or ''
    end
    faviconCache[favicon] = v
  end
  return v  
end

---Shows some info on SSL certificate status similar to the way Chrome does it.
---@param data WebBrowser.SSLStatus
function webUI.certificateDetails(data)
  local issue
  if not data.secure then
    issue = 'Connection is not secure'
  elseif data.faultsMask ~= 0 then
    issue = 'Certificate is not valid'
  elseif data.certificate and data.certificate.chainSize == 0 then
    issue = 'Self-signed certificate' % data.faultsMask
  end
  
  ui.pushFont(ui.Font.Title)
  ui.icon(issue and ui.Icons.Warning or ui.Icons.Confirm, 20, issue and rgbm.colors.orange or rgbm.colors.lime)
  ui.sameLine()
  ui.offsetCursorY(-2)
  ui.text(issue or 'Connection is secure')
  ui.popFont()
  if issue then
    ui.newLine()
    ui.textWrapped('Please don’t enter any confidential information on this website, because it could be stolen by the attackers.')
  end

  if data.certificate then
    local function row(label, value)
      ui.offsetCursorX(8)
      ui.textColored(label, rgbm(1, 1, 1, 0.6))
      ui.sameLine(190)
      if value == '<N/A>' then
        ui.textColored(value, rgbm(1, 1, 1, 0.6))
      else
        ui.text(value)
      end
    end

    ---@param item WebBrowser.CertificateActor
    local function actorDetails(item)
      row('Common name (CN)', item.commonName)
      row('Organization (O)', #item.organizationNames > 0 and table.concat(item.organizationNames, ',') or '<N/A>')
      row('Organizational Unit (OU)', #item.organizationUnitNames > 0 and table.concat(item.organizationUnitNames, ',') or '<N/A>')
    end

    ui.newLine()
    ui.header('Issued to')
    actorDetails(data.certificate.subject)
    
    ui.newLine()
    ui.header('Issued by')
    actorDetails(data.certificate.issuer)

    ui.newLine()
    ui.header('Validity period')
    row('Issued on', os.date('%A, %B %d, %Y at %X', data.certificate.validPeriod.creation))
    row('Expires on', os.date('%A, %B %d, %Y at %X', data.certificate.validPeriod.expiration))
  end
end

---@param tab WebBrowser
function webUI.DefaultPopups.SSLStatus(tab)
  local sslData ---@type WebBrowser.SSLStatus?
  tab:getSSLStatusAsync(function (d) sslData = d end)
  ui.modalDialog('Security', function ()
    if sslData then webUI.certificateDetails(sslData) end
    ui.newLine()
    return ui.modernButton('Close', vec2(-0.1, 40), ui.ButtonFlags.None, ui.Icons.ArrowLeft)
  end, true)
end

---@param tab WebBrowser
function webUI.DefaultPopups.Cookies(tab, count)
  local cookies ---@type WebBrowser.Cookie[]?
  if tab:cookiesAccessAllowed() then
    tab:getCookiesAsync('basic', tab:url(), function (d) cookies = d end)
  else
    cookies = count and {true} or {}
  end
  ui.modalDialog('Cookies', function ()
    if cookies then
      if cookies[1] == true then
        ui.textWrapped('Website has set %d cookie%s.' % {count, count > 1 and 's' or ''})
      elseif #cookies > 0 then
        local w = ui.availableSpaceX()
        ui.columns(3)
        ui.setColumnWidth(0, 80)
        ui.setColumnWidth(1, w - 100)
        ui.text('Name')
        ui.nextColumn()
        ui.text('Value')
        ui.nextColumn()
        ui.nextColumn()
        ui.separator()
        ui.pushFont(ui.Font.Small)
        for i, v in ipairs(cookies) do
          ui.pushID(i)
          ui.copyable(v.name)
          ui.nextColumn()
          ui.copyable(v.value)
          ui.nextColumn()
          if ui.iconButton(ui.Icons.Cancel, 20, 6) then
            tab:deleteCookies(tab:url(), v.name)
            tab:getCookiesAsync('basic', tab:url(), function (d) cookies = d end)
          end
          if ui.itemHovered() then
            ui.setTooltip('Remove cookie')
          end
          ui.nextColumn()
          ui.popID()
        end
        ui.popFont()
        ui.columns(1)
      else
        ui.text('No cookies are set.')
      end
    end
    ui.newLine()
    local r = ui.modernButton('Close', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.None, ui.Icons.ArrowLeft)
    ui.sameLine(0, 8)
    if ui.modernButton('Clear', vec2(-0.1, 40), cookies and #cookies > 0 and ui.ButtonFlags.Cancel or ui.ButtonFlags.Disabled, ui.Icons.Trash) then
      tab:deleteCookies(tab:domain(), nil)
      r = true
    end
    return r
  end, true)
end

return webUI