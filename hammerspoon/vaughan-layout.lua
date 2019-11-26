require('util')
ax = require("hs._asm.axuielement")

local main_monitor = "Color LCD"
local work_monitor = "BenQ PD3200U"
local photo_monitor = "PA271Q"
local browsing_monitor = "CS230"

local enableAutoLayout = true

wifiWatcher = nil
homeSSID = "ABW-51ac"
lastSSID = hs.wifi.currentNetwork()

-- Screens table helpers.
------------------------------------------------------------------------------

function serialiseScreensTable(screens)
  if screens == nil then return end
  local screensString = ''
  for _, screen in pairs(screens) do
    screensString = screensString .. tostring(screen)
  end
  -- print(screensString)
  return screensString
end

function screensIsSame(screensA, screensB)
  return serialiseScreensTable(screensA) ~= serialiseScreensTable(screensB)
end

local lastScreens = null

function hasScreensChanged()
  local newScreens = hs.screen.allScreens()
  return not screensIsSame(newScreens, lastScreens)
end

-- Watch for changes to monitor layout.
------------------------------------------------------------------------------

local timer = null
-- It takes about 4s for macOS to finish its monitor re-org.
local DEBOUNCE_DELAY =10 

function debouncedLayout(reason)

  print('screens changed!')

  if (timer) then
    -- `stop` means callback will not be called.
    timer:stop()
  end

  -- If the screens change, do layout if no further screen
  -- change for X seconds.
  timer = hs.timer.doAfter(DEBOUNCE_DELAY, function()
    -- Alert with reason for relayout.
    if reason == 'screen' then
      hs.alert.show("Monitor layout changed")
    elseif reason == 'systemDidWake' then
      hs.alert.show("System woke up")
    elseif reason == 'screensDidUnlock' then
      hs.alert.show("Screens did unlock")
    elseif reason == 'newWiFi' then
      hs.alert.show("New WiFi connected")
    end

    universalLayout()
  end)

end

function handleScreenWatcher()
  lastScreens = hs.screen.allScreens()
  if (enableAutoLayout) then
    debouncedLayout('screen')
  end
end

-- NOTE: Can also detect when active screen changes with `newWithActiveScreen` if needed.
local screenWatcher = hs.screen.watcher.new(handleScreenWatcher)
screenWatcher:start()

debouncedLayout('screen')

-- Watch for changes to screens.
------------------------------------------------------------------------------

-- NOTE: `system wake` always followed by `screen unlock` when lock on sleep enabled.


function ssidChangedCallback()
    newSSID = hs.wifi.currentNetwork()

    if newSSID == homeSSID and lastSSID ~= homeSSID then
        -- We just joined our home WiFi network
        hs.audiodevice.defaultOutputDevice():setVolume(25)
        debouncedLayout('newWiFi')
    elseif newSSID ~= homeSSID and lastSSID == homeSSID then
        -- We just departed our home WiFi network
        hs.audiodevice.defaultOutputDevice():setVolume(0)
        debouncedLayout('newWiFi')
    end

    lastSSID = newSSID
end

wifiWatcher = hs.wifi.watcher.new(ssidChangedCallback)
wifiWatcher:start()


function handleCaffeinateEvent(event)
  if event == hs.caffeinate.watcher.systemDidWake then
    print('system did wake')
-- change on every wake
    debouncedLayout('systemDidWake')
    if hasScreensChanged() then
      print('screens have changed')
      if (enableAutoLayout) then
--        debouncedLayout('systemDidWake')
      end
    else
      print('screens have NOT changed. not laying out.')
    end
  elseif event == hs.caffeinate.watcher.screensDidUnlock then
    print('screens did unlock')
    -- debouncedLayout('screensDidUnlock')
  end
end

local caffeinateWatcher = hs.caffeinate.watcher.new(handleCaffeinateEvent)
caffeinateWatcher:start()

-- Fix stuck modifiers.
------------------------------------------------------------------------------


-- Determines whether to layout windows 2/3 or 1/2.
-- We have a separate shortcut for "pushing 2/3" now so name is probably incorrect now.
local pushWindowTwoThirds = true

------------------------------------------------------------------------------

-- We use this hash instead of `hs.layout` because we can invert things
-- depending on which side the secondary screen (or iPad) is placed.

positions = {
  maximized = hs.layout.maximized,
  centered = {x=0.2, y=0.2, w=0.6, h=0.6},
  centeredAlt = {x=0.1, y=0.1, w=0.8, h=0.8},

  left34 = {x=0, y=0, w=0.34, h=1},
  left50 = hs.layout.left50,
  left66 = {x=0, y=0, w=0.66, h=1},

  right34 = {x=0.66, y=0, w=0.34, h=1},
  right50 = hs.layout.right50,
  right66 = {x=0.34, y=0, w=0.66, h=1},
  right65 = {x=0.35, y=0, w=0.65, h=1},

  upper50 = {x=0, y=0, w=1, h=0.5},
  upper50Left50 = {x=0, y=0, w=0.5, h=0.5},
  upper50Right50 = {x=0.5, y=0, w=0.5, h=0.5},

  lower50 = {x=0, y=0.5, w=1, h=0.5},
  lower50Left50 = {x=0, y=0.5, w=0.5, h=0.5},
  lower50Right50 = {x=0.5, y=0.5, w=0.5, h=0.5}
}

-- app titles
titles = {
  messenger = 'Wiadomości',
  safari = 'Safari',
  omnifocus = 'OmniFocus',
  brave = 'Brave Browser',
  iterm = 'iTerm2',
  spotify = 'Spotify',
  mail = 'Mail',
  calendar = 'BusyCal',
  finder = 'Finder',
  
}

commonWindowLayout = {
  {'WhatsApp', nil, laptopScreen, positions.right50, nil, nil},
  {'Spotify', nil, laptopScreen, positions.centeredAlt, nil, nil},
  {titles.sourceTree, nil, laptopScreen, positions.centeredAlt, nil, nil},
  {titles.mail, nil, laptopScreen, positions.centeredAlt, nil, nil},
  {titles.calendar, nil, laptopScreen, positions.centeredAlt, nil, nil},
  {titles.finder, nil, laptopScreen, positions.left50, nil, nil},
}

------------------------------------------------------------------------------

function isVerticalScreenConnected()
  local allScreens = hs.screen.allScreens()
  for _, screen in pairs(allScreens) do
    local screenFrame = screen:fullFrame()
    local screenSize = screenFrame.size
    if (compareSize(screenSize, monitor1080pVertical)) then
      return true
    elseif (compareSize(screenSize, monitor1200pVertical)) then
      return true
    end
  end
  return false
end


function universalLayout()
  local allScreens = hs.screen.allScreens()
  local screenCount = tableLength(allScreens)
  local windowLayout

  print('Screen count:', screenCount)
  print('Dimensions:', dimensions)

  -- TODO(vjpr): Maybe use find to improve code.
  -- http://www.hammerspoon.org/docs/hs.screen.html#find.

  if (screenCount == 3) then

      windowLayout = screenLayoutPrimaryAnd1xNEC()

  elseif (screenCount == 2) then

      windowLayout = screenLayoutPrimaryAnd1xWork()

  elseif (screenCount == 1) then

    -- Only laptop display.
    windowLayout = screenLayoutPrimary()

  end

  local layout = {}
  tableConcat(layout, commonWindowLayout)
  tableConcat(layout, windowLayout)
  -- hs.layout.apply(layout)
  hs.layout.apply(layout, string.match)


end


------------------------------------------------------------------------------

function screenLayoutPrimary()
  hs.alert.show("screensPrimary layout")
  local laptopScreen = "Color LCD" -- hs.screen.primaryScreen()

  local brave1,chrome2 = hs.application.find'Brave Browser'

  local layoutRight
  if not pushWindowTwoThirds then
    layoutRight = hs.layout.right50
  else
    layoutRight = positions.right66
  end

  local windowLayout = {
    {titles.safari, nil, laptopScreen, layoutRight, nil, nil},
    {brave1, nil, laptopScreen, layoutRight, nil, nil},
    {brave2, nil, laptopScreen, layoutRight, nil, nil},
    {titles.messenger, nil, laptopScreen, hs.layout.left50, nil, nil},
    {titles.appCode, nil, laptopScreen, hs.layout.maximized, nil, nil},
    {titles.omnifocus, nil, laptopScreen, hs.layout.maximized, nil, nil},
    {titles.iterm, nil, laptopScreen, layoutRight, nil, nil},
  }
  return windowLayout
end


function screenLayoutPrimaryAnd1xNEC()
  hs.alert.show("You're at home")
  local windowLayout = {
    {titles.brave, nil, photo_monitor, hs.layout.maximized, nil, nil},
    {titles.iterm, nil, photo_monitor, positions.right50, nil, nil},
    {titles.spotify, nil, browsing_monitor, positions.maximized, nil, nil},
    {titles.calendar, nil, main_monitor, positions.maximized, nil, nil},
    {titles.omnifocus, nil, photo_monitor, positions.left65, nil, nil},
    {titles.mail, nil, main_monitor, positions.maximized, nil, nil},
  }
  return windowLayout
end

function screenLayoutPrimaryAnd1xWork()
  hs.alert.show("You're at work")
  local windowLayout = {
    {titles.brave, nil, work_monitor, hs.layout.centeredAlt, nil, nil},
    {titles.iterm, nil, work_monitor, positions.lower50Left50, nil, nil},
    {titles.spotify, nil, main_monitor, positions.maximized, nil, nil},
    {titles.mail, nil, work_monitor, positions.centered, nil, nil},
    {titles.calendar, nil, main_monitor, positions.maximized, nil, nil},
    {titles.omnifocus, nil, work_monitor, positions.right50, nil, nil},
  }
  return windowLayout
end


