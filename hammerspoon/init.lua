
-- hotkey mash
local mash   = {"ctrl", "alt"}
local mash_app   = {"cmd", "alt", "ctrl"}
local mash_shift = {"ctrl", "alt", "shift"}
local main_monitor = "Color LCD"
local second_monitor = "HP P201"

hs.grid.MARGINX = 0
hs.grid.MARGINY = 0
hs.grid.GRIDWIDTH = 7
hs.grid.GRIDHEIGHT = 3

-- disable animation
hs.window.animationDuration = 0

-- Set grid size.
hs.grid.GRIDWIDTH  = 12
hs.grid.GRIDHEIGHT = 12
hs.grid.MARGINX    = 0
hs.grid.MARGINY    = 0
-- Set window animation off. It's much smoother.
hs.window.animationDuration = 0
-- Set volume increments
local volumeIncrement = 5

function reloadConfig(files)
    doReload = false
    for _,file in pairs(files) do
        if file:sub(-4) == ".lua" then
            doReload = true
        end
    end
    if doReload then
        hs.reload()
    end
end
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
hs.alert.show("Hammerspoon: konfiguracja przeladowana")


local usbWatcher = nil

function usbDeviceCallback(data)
    if (data["productName"] == "ScanSnap S1300i") then
        if (data["eventType"] == "added") then
            hs.application.launchOrFocus("ScanSnap Manager")
        elseif (data["eventType"] == "removed") then
            app = hs.appfinder.appFromName("ScanSnap Manager")
            app:kill()
        end
    end
end

usbWatcher = hs.usb.watcher.new(usbDeviceCallback)
usbWatcher:start()

local mouseCircle = nil
local mouseCircleTimer = nil

function mouseHighlight()
    -- Delete an existing highlight if it exists
    if mouseCircle then
        mouseCircle:delete()
        if mouseCircleTimer then
            mouseCircleTimer:stop()
        end
    end
    -- Get the current co-ordinates of the mouse pointer
    mousepoint = hs.mouse.getAbsolutePosition()
    -- Prepare a big red circle around the mouse pointer
    mouseCircle = hs.drawing.circle(hs.geometry.rect(mousepoint.x-40, mousepoint.y-40, 80, 80))
    mouseCircle:setStrokeColor({["red"]=1,["blue"]=0,["green"]=0,["alpha"]=1})
    mouseCircle:setFill(false)
    mouseCircle:setStrokeWidth(5)
    mouseCircle:show()

    -- Set a timer to delete the circle after 3 seconds
    mouseCircleTimer = hs.timer.doAfter(3, function() mouseCircle:delete() end)
end

hs.hotkey.bind(mash, "d", mouseHighlight)


hs.hotkey.bind(mash, ';', function() hs.grid.snap(hs.window.focusedWindow()) end)
hs.hotkey.bind(mash, "'", function() hs.fnutils.map(hs.window.visibleWindows(), hs.grid.snap) end)

-- application help
local function open_help()
  help_str = "1 - Safari, 2 - Mail, " ..
            "3 - Pathfinder, 5 - Slack, 6 - Adium"        
  hs.alert.show(
   help_str, 2)
end

-- Launch applications
hs.hotkey.bind(mash_app, 'D', function () hs.application.launchOrFocus("Safari") end)
hs.hotkey.bind(mash_app, '1', function () hs.application.launchOrFocus("Safari") end)
hs.hotkey.bind(mash_app, '2', function () hs.application.launchOrFocus("Mail") end)
hs.hotkey.bind(mash_app, '3', function () hs.application.launchOrFocus("Path Finder") end)
-- mash_app '4' reserved for dash global key
hs.hotkey.bind(mash_app, '5', function () hs.application.launchOrFocus("Slack") end)
hs.hotkey.bind(mash_app, '6', function () hs.application.launchOrFocus("Adium") end)
hs.hotkey.bind(mash_app, '/', open_help)

hs.hotkey.bind(mash, 'M', hs.grid.maximizeWindow)
hs.hotkey.bind(mash, 'F', function() hs.window.focusedWindow():toggleFullScreen() end)

-- multi monitor
hs.hotkey.bind(mash, 'N', hs.grid.pushWindowNextScreen)
hs.hotkey.bind(mash, 'P', hs.grid.pushWindowPrevScreen)

-- move windows
hs.hotkey.bind(mash, 'H', hs.grid.pushWindowLeft)
hs.hotkey.bind(mash, 'J', hs.grid.pushWindowDown)
hs.hotkey.bind(mash, 'K', hs.grid.pushWindowUp)
hs.hotkey.bind(mash, 'L', hs.grid.pushWindowRight)

-- resize windows
hs.hotkey.bind(mash, 'Y', hs.grid.resizeWindowThinner)
hs.hotkey.bind(mash, 'U', hs.grid.resizeWindowShorter)
hs.hotkey.bind(mash, 'I', hs.grid.resizeWindowTaller)
hs.hotkey.bind(mash, 'O', hs.grid.resizeWindowWider)

-- Window Hints
hs.hotkey.bind(mash, '.', hs.hints.windowHints)

--------------------------------------------------------------------------------
-- LAYOUTS
-- SINTAX:
--  {
--    name = "App name" ou { "App name", "App name" }
--    func = function(index, win)
--      COMMANDS
--    end
--  },
--
-- It searches for application "name" and call "func" for each window object
--------------------------------------------------------------------------------
local layouts = {
  {
    name = {"Airmail", "Calendar", "iTunes", "Last.fm Scrobbler", "Messages", "Skype", "Dash", "Yummy FTP"},
    func = function(index, win)
      win:moveToScreen(hs.screen.get(main_monitor))
      win:maximize()
    end
  },
  {
    name = {"TextWrangler"},
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then
        win:moveToScreen(hs.screen.get(second_monitor))
        hs.window.fullscreenAlmostCenter(win)
      else
        win:maximize()
      end
    end
  },
  {
    name = {"Cocoa Rest Client", "MacDown", "Firefox"},
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then
        win:moveToScreen(hs.screen.get(second_monitor))
        hs.window.fullscreenCenter(win)
      else
        win:maximize()
      end
    end
  },
  {
    name = {"Evernote", "JSON Accelerator", "Preview", "Slack"},
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then
        win:moveToScreen(hs.screen.get(second_monitor))
        hs.window.fullscreenCenter(win)
      else
        win:maximize()
      end
    end
  },
  {
    name = {"Android Studio", "Xcode", "SourceTree"},
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then
        win:moveToScreen(hs.screen.get(second_monitor))
        hs.window.fullscreenWidth(win)
      else
        win:maximize()
      end
    end
  },
  {
    name = "Finder",
    func = function(index, win)

      if (index == 1) then
        if (#hs.screen.allScreens() > 1) then
          win:moveToScreen(hs.screen.get(second_monitor))
        end

        win:upLeft()
      elseif (index == 2) then
        if (#hs.screen.allScreens() > 1) then
          win:moveToScreen(hs.screen.get(second_monitor))
        end

        win:downLeft()
      elseif (index == 3) then
        if (#hs.screen.allScreens() > 1) then
          win:moveToScreen(hs.screen.get(second_monitor))
        end

        win:downRight()
      elseif (index == 4) then
        if (#hs.screen.allScreens() > 1) then
          win:moveToScreen(hs.screen.get(second_monitor))
        end

        win:upRight()
      elseif (index == 5) then
        win:moveToScreen(hs.screen.get(main_monitor))

        win:upLeft()
      elseif (index == 6) then
        win:moveToScreen(hs.screen.get(main_monitor))

        win:downLeft()
      elseif (index == 7) then
        win:moveToScreen(hs.screen.get(main_monitor))

        win:downRight()
      elseif (index == 8) then
        win:moveToScreen(hs.screen.get(main_monitor))

        win:upRight()
      else
        win:close()
      end
    end
  },
  {
    name = "iTerm",
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then
        win:moveToScreen(hs.screen.get(second_monitor))
      end

      if (index == 1) then
        win:left()
      elseif (index == 2) then
        win:right()
      end
    end
  },
  {
    name = "iOS Simulator",
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then
        win:moveToScreen(hs.screen.get(second_monitor))
      end

      local screen = win:screen()
      local screen_frame = screen:frame()
      local frame = win:frame()
      frame.x = screen_frame.w / 2
      frame.y = screen_frame.y
      win:setFrame(frame)
    end
  },
  {
    name = "Genymotion",
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then
        win:moveToScreen(hs.screen.get(second_monitor))
      end

      local screen = win:screen()
      local screen_frame = screen:frame()
      local frame = win:frame()
      frame.x = screen_frame.w / 2
      frame.y = screen_frame.y + 50
      frame.w = screen_frame.w / 3
      frame.h = screen_frame.h / 2
      win:setFrame(frame)
    end
  },
  {
    name = {"Atom", "Light Table"},
    func = function(index, win)
      if (#hs.screen.allScreens() > 1) then

        local allScreens = hs.screen.allScreens()
        for i, screen in ipairs(allScreens) do
          if screen:name() == second_monitor then
            win:moveToScreen(screen)
          end
        end

        local screen = win:screen()
        win:setFrame({
          x = screen:frame().x,
          y = hs.screen.minY(screen),
          w = hs.screen.minWidth(false) + hs.screen.minX(screen),
          h = hs.screen.minHeight(screen)
        })
      else
        win:maximize()
      end
    end
  },
}

local closeAll = {
  "iTunes",
  "Skype",
  "Messages",
  "XCode",
  "Android Studio",
  "Simulator",
  "Word",
  "Excel",
  "TextWrangler",
  "Cocoa Rest Client",
  "Last.fm",
  "Preview",
  "JSON Accelerator",
  "Yummy FTP",
  "player",
  "FileMerge",
  "Fabric",
  "Color Picker"
}

local openAll = {
  "iTunes",
  "Skype",
  "Messages",
  "Last.fm"
}



function config()
--[[  hs.hotkey.bind(cmd_alt, "right", function()
    local win = hs.window.focusedWindow()
    win:right()
  end)

  hs.hotkey.bind(cmd_alt, "left", function()
    local win = hs.window.focusedWindow()
    win:left()
  end)

  hs.hotkey.bind(cmd_alt, "up", function()
    local win = hs.window.focusedWindow()
    win:up()
  end)

  hs.hotkey.bind(cmd_alt, "down", function()
    local win = hs.window.focusedWindow()
    win:down()
  end)]]

  hs.hotkey.bind(mash, "left", function()
    local win = hs.window.focusedWindow()
    win:upLeft()
  end)

  hs.hotkey.bind(mash, "down", function()
    local win = hs.window.focusedWindow()
    win:downLeft()
  end)

  hs.hotkey.bind(mash, "right", function()
    local win = hs.window.focusedWindow()
    win:downRight()
  end)

  hs.hotkey.bind(mash, "up", function()
    local win = hs.window.focusedWindow()
    win:upRight()
  end)
    
    hs.hotkey.bind(mash_app, "left", function()
    local win = hs.window.focusedWindow()
    win:left()
  end)
  hs.hotkey.bind(mash_app, "down", function()
    local win = hs.window.focusedWindow()
    win:down()
  end)

  hs.hotkey.bind(mash_app, "right", function()
    local win = hs.window.focusedWindow()
    win:right()
  end)

  hs.hotkey.bind(mash_app, "up", function()
    local win = hs.window.focusedWindow()
    win:up()
  end)
-- VIM keys in all apps
--
hs.hotkey.bind({"ctrl"}, "j", function()
  hs.eventtap.keyStroke({""}, "down")
end)
hs.hotkey.bind({"ctrl"}, "h", function()
  hs.eventtap.keyStroke({""}, "left")
end)
hs.hotkey.bind({"ctrl"}, "k", function()
  hs.eventtap.keyStroke({""}, "up")
end)
hs.hotkey.bind({"ctrl"}, "l", function()
  hs.eventtap.keyStroke({""}, "right")
end)
--[[
  hs.hotkey.bind(cmd_alt, "c", function()
    local win = hs.window.focusedWindow()
    hs.window.fullscreenCenter(win)
  end)

  hs.hotkey.bind(mash_app, "c", function()
    local win = hs.window.focusedWindow()
    hs.window.fullscreenAlmostCenter(win)
  end)

  hs.hotkey.bind(cmd_alt, "f", function()
    local win = hs.window.focusedWindow()
    win:maximize()
  end)


  hs.hotkey.bind(mash_app, "f", function()
    local win = hs.window.focusedWindow()
    if (win) then
      hs.window.fullscreenWidth(win)
    end
  end)

  hs.hotkey.bind(mash_app, "h", function()
    hs.hints.windowHints()
  end)

  hs.hotkey.bind(mash_app, "1", function()
    local win = hs.window.focusedWindow()
    if (win) then
      win:moveToScreen(hs.screen.get(second_monitor))
    end
  end)

  hs.hotkey.bind(mash_app, "2", function()
    local win = hs.window.focusedWindow()
    if (win) then
      win:moveToScreen(hs.screen.get(main_monitor))
    end
  end)

  hs.hotkey.bind(cmd_alt_ctrl, "R", function()
    hs.reload()
    hs.alert.show("Config loaded")
  end)

  hs.hotkey.bind(cmd_alt_ctrl, "P", function()
    hs.alert.show("Closing")
    for i,v in ipairs(closeAll) do
      local app = hs.application(v)
      if (app) then
        if (app.name) then
          hs.alert.show(app:name())
        end
        if (app.kill) then
        app:kill()
      end
      end
    end
  end)

  hs.hotkey.bind(cmd_alt_ctrl, "O", function()
    hs.alert.show("Openning")
    for i,v in ipairs(openAll) do
      hs.alert.show(v)
      hs.application.open(v)
    end
  end)

  hs.hotkey.bind(cmd_alt_ctrl, "3", function()
    applyLayouts(layouts)
  end)

  hs.hotkey.bind(cmd_alt_ctrl, "4", function()

    local focusedWindow = hs.window.focusedWindow()
    local app = focusedWindow:application()
    if (app) then
      applyLayout(layouts, app)
    end
  end)
    ]]
end
--------------------------------------------------------------------------------
-- METHODS - BECAREFUL :)
--------------------------------------------------------------------------------

function applyLayout(layouts, app)
  if (app) then
    local appName = app:title()
    for i, layout in ipairs(layouts) do
      if (type(layout.name) == "table") then
        for i, layAppName in ipairs(layout.name) do
          if (layAppName == appName) then
            local wins = app:allWindows()
            local counter = 1
            for j, win in ipairs(wins) do
              if (win:isVisible() and layout.func) then
                layout.func(counter, win)
                counter = counter + 1
              end
            end
          end
        end
      elseif (type(layout.name) == "string") then
        if (layout.name == appName) then
          local wins = app:allWindows()
          local counter = 1
          for j, win in ipairs(wins) do
            if (win:isVisible() and layout.func) then
              layout.func(counter, win)
              counter = counter + 1
            end
          end
        end
      end
    end
  end
end

function applyLayouts(layouts)
  for i, layout in ipairs(layouts) do
    if (type(layout.name) == "table") then
      for i, appName in ipairs(layout.name) do
        local app = hs.appfinder.appFromName(appName)
        if (app) then
          local wins = app:allWindows()
          local counter = 1
          for j, win in ipairs(wins) do
            if (win:isVisible() and layout.func) then
              layout.func(counter, win)
              counter = counter + 1
            end
          end
        end
      end
    elseif (type(layout.name) == "string") then
      local app = hs.appfinder.appFromName(layout.name)
      if (app) then
        local wins = app:allWindows()
        local counter = 1
        for j, win in ipairs(wins) do
          if (win:isVisible() and layout.func) then
            layout.func(counter, win)
            counter = counter + 1
          end
        end
      end
    end
  end
end

function hs.screen.get(screen_name)
  local allScreens = hs.screen.allScreens()
  for i, screen in ipairs(allScreens) do
    if screen:name() == screen_name then
      return screen
    end
  end
end

-- Returns the width of the smaller screen size
-- isFullscreen = false removes the toolbar
-- and dock sizes
function hs.screen.minWidth(isFullscreen)
  local min_width = math.maxinteger
  local allScreens = hs.screen.allScreens()
  for i, screen in ipairs(allScreens) do
    local screen_frame = screen:frame()
    if (isFullscreen) then
      screen_frame = screen:fullFrame()
    end
    min_width = math.min(min_width, screen_frame.w)
  end
  return min_width
end

-- isFullscreen = false removes the toolbar
-- and dock sizes
-- Returns the height of the smaller screen size
function hs.screen.minHeight(isFullscreen)
  local min_height = math.maxinteger
  local allScreens = hs.screen.allScreens()
  for i, screen in ipairs(allScreens) do
    local screen_frame = screen:frame()
    if (isFullscreen) then
      screen_frame = screen:fullFrame()
    end
    min_height = math.min(min_height, screen_frame.h)
  end
  return min_height
end

-- If you are using more than one monitor, returns X
-- considering the reference screen minus smaller screen
-- = (MAX_REFSCREEN_WIDTH - MIN_AVAILABLE_WIDTH) / 2
-- If using only one monitor, returns the X of ref screen
function hs.screen.minX(refScreen)
  local min_x = refScreen:frame().x
  local allScreens = hs.screen.allScreens()
  if (#allScreens > 1) then
    min_x = refScreen:frame().x + ((refScreen:frame().w - hs.screen.minWidth()) / 2)
  end
  return min_x
end

-- If you are using more than one monitor, returns Y
-- considering the focused screen minus smaller screen
-- = (MAX_REFSCREEN_HEIGHT - MIN_AVAILABLE_HEIGHT) / 2
-- If using only one monitor, returns the Y of focused screen
function hs.screen.minY(refScreen)
  local min_y = refScreen:frame().y
  local allScreens = hs.screen.allScreens()
  if (#allScreens > 1) then
    min_y = refScreen:frame().y + ((refScreen:frame().h - hs.screen.minHeight()) / 2)
  end
  return min_y
end

-- If you are using more than one monitor, returns the
-- half of minX and 0
-- = ((MAX_REFSCREEN_WIDTH - MIN_AVAILABLE_WIDTH) / 2) / 2
-- If using only one monitor, returns the X of ref screen
function hs.screen.almostMinX(refScreen)
  local min_x = refScreen:frame().x
  local allScreens = hs.screen.allScreens()
  if (#allScreens > 1) then
    min_x = refScreen:frame().x + (((refScreen:frame().w - hs.screen.minWidth()) / 2) - ((refScreen:frame().w - hs.screen.minWidth()) / 4))
  end
  return min_x
end

-- If you are using more than one monitor, returns the
-- half of minY and 0
-- = ((MAX_REFSCREEN_HEIGHT - MIN_AVAILABLE_HEIGHT) / 2) / 2
-- If using only one monitor, returns the Y of ref screen
function hs.screen.almostMinY(refScreen)
  local min_y = refScreen:frame().y
  local allScreens = hs.screen.allScreens()
  if (#allScreens > 1) then
    min_y = refScreen:frame().y + (((refScreen:frame().h - hs.screen.minHeight()) / 2) - ((refScreen:frame().h - hs.screen.minHeight()) / 4))
  end
  return min_y
end

-- Returns the frame of the smaller available screen
-- considering the context of refScreen
-- isFullscreen = false removes the toolbar
-- and dock sizes
function hs.screen.minFrame(refScreen, isFullscreen)
  return {
    x = hs.screen.minX(refScreen),
    y = hs.screen.minY(refScreen),
    w = hs.screen.minWidth(isFullscreen),
    h = hs.screen.minHeight(isFullscreen)
  }
end

-- +-----------------+
-- |        |        |
-- |        |  HERE  |
-- |        |        |
-- +-----------------+
function hs.window.right(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  minFrame.x = minFrame.x + (minFrame.w/2)
  minFrame.w = minFrame.w/2
  win:setFrame(minFrame)
end

-- +-----------------+
-- |        |        |
-- |  HERE  |        |
-- |        |        |
-- +-----------------+
function hs.window.left(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  minFrame.w = minFrame.w/2
  win:setFrame(minFrame)
end

-- +-----------------+
-- |      HERE       |
-- +-----------------+
-- |                 |
-- +-----------------+
function hs.window.up(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  minFrame.h = minFrame.h/2
  win:setFrame(minFrame)
end

-- +-----------------+
-- |                 |
-- +-----------------+
-- |      HERE       |
-- +-----------------+
function hs.window.down(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  minFrame.y = minFrame.y + minFrame.h/2
  minFrame.h = minFrame.h/2
  win:setFrame(minFrame)
end

-- +-----------------+
-- |  HERE  |        |
-- +--------+        |
-- |                 |
-- +-----------------+
function hs.window.upLeft(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  minFrame.w = minFrame.w/2
  minFrame.h = minFrame.h/2
  win:setFrame(minFrame)
end

-- +-----------------+
-- |                 |
-- +--------+        |
-- |  HERE  |        |
-- +-----------------+
function hs.window.downLeft(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  win:setFrame({
    x = minFrame.x,
    y = minFrame.y + minFrame.h/2,
    w = minFrame.w/2,
    h = minFrame.h/2
  })
end

-- +-----------------+
-- |                 |
-- |        +--------|
-- |        |  HERE  |
-- +-----------------+
function hs.window.downRight(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  win:setFrame({
    x = minFrame.x + minFrame.w/2,
    y = minFrame.y + minFrame.h/2,
    w = minFrame.w/2,
    h = minFrame.h/2
  })
end

-- +-----------------+
-- |        |  HERE  |
-- |        +--------|
-- |                 |
-- +-----------------+
function hs.window.upRight(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  win:setFrame({
    x = minFrame.x + minFrame.w/2,
    y = minFrame.y,
    w = minFrame.w/2,
    h = minFrame.h/2
  })
end

-- +------------------+
-- |                  |
-- |    +--------+    +--> minY
-- |    |  HERE  |    |
-- |    +--------+    |
-- |                  |
-- +------------------+
-- Where the window's size is equal to
-- the smaller available screen size
function hs.window.fullscreenCenter(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  win:setFrame(minFrame)
end

-- +------------------+
-- |                  |
-- |  +------------+  +--> minY
-- |  |    HERE    |  |
-- |  +------------+  |
-- |                  |
-- +------------------+
function hs.window.fullscreenAlmostCenter(win)
  local offsetW = hs.screen.minX(win:screen()) - hs.screen.almostMinX(win:screen())
  win:setFrame({
    x = hs.screen.almostMinX(win:screen()),
    y = hs.screen.minY(win:screen()),
    w = hs.screen.minWidth(isFullscreen) + (2 * offsetW),
    h = hs.screen.minHeight(isFullscreen)
  })
end

-- It like fullscreen but with minY and minHeight values
-- +------------------+
-- |                  |
-- +------------------+--> minY
-- |       HERE       |
-- +------------------+--> minHeight
-- |                  |
-- +------------------+
function hs.window.fullscreenWidth(win)
  local minFrame = hs.screen.minFrame(win:screen(), false)
  win:setFrame({
    x = win:screen():frame().x,
    y = minFrame.y,
    w = win:screen():frame().w,
    h = minFrame.h
  })
end

function applicationWatcher(appName, eventType, appObject)
  if (eventType == hs.application.watcher.activated) then
    if (appName == "iTerm") then
        appObject:selectMenuItem({"Window", "Bring All to Front"})
    elseif (appName == "Finder") then
        appObject:selectMenuItem({"Window", "Bring All to Front"})
    end
  end

  if (eventType == hs.application.watcher.launched) then
    os.execute("sleep " .. tonumber(3))
    applyLayout(layouts, appObject)
  end
end

config()
local appWatcher = hs.application.watcher.new(applicationWatcher)
appWatcher:start()
