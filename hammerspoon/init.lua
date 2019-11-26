-- hotkey mash
local mash   = {"ctrl", "alt", "shift", "cmd"} 
-- local mash_app   = {"cmd", "alt", "ctrl"} 
--local mash_shift = {"ctrl", "alt", "shift"}
require('keyboard') -- Load Hammerspoon bits from https://github.com/jasonrudolph/keyboard
hs.loadSpoon("SpoonInstall")
-- https://www.songofcode.com/posts/powerful-hammerspoon/


spoon.SpoonInstall.repos.zzspoons = {
  url = "https://github.com/zzamboni/zzSpoons",
  desc = "zzamboni's spoon repository",
}

spoon.SpoonInstall.use_syncinstall = true
Install=spoon.SpoonInstall

--Install:andUse("BetterTouchTool", { loglevel = 'info' })
--BTT = spoon.BetterTouchTool

Install:andUse("WinWin")

hs.grid.MARGINX = 0
hs.grid.MARGINY = 0
hs.grid.GRIDWIDTH = 7
hs.grid.GRIDHEIGHT = 3

col = hs.drawing.color.x11

-- disable animation
hs.window.animationDuration = 0 -- Set grid size.  hs.grid.GRIDWIDTH  = 12 hs.grid.GRIDHEIGHT = 12 hs.grid.MARGINX    = 0 hs.grid.MARGINY    = 0 -- Set window animation off. It's much smoother.
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


-- https://zzamboni.org/post/my-hammerspoon-configuration-with-commentary/
--

-- Install:andUse("Hammer",
--                {
--                  repo = 'zzspoons',
--                  config = { auto_reload_config = false },
--                  hotkeys = {
--                    config_reload = {mash, "h"},
--                    toggle_console = {mash, "y"}
--                  },
--                  fn = function(s)
--                    BTT:bindSpoonActions(s,
--                                         { config_reload = {
--                                             kind = 'touchbarButton',
--                                             uuid = "FF8DA717-737F-4C42-BF91-E8826E586FA1",
--                                             name = "Restart",
--                                             icon = hs.image.imageFromName(hs.image.systemImageNames.ApplicationIcon),
--                                             color = hs.drawing.color.x11.orange,
--                                         }
--                    })
--                  end,
--                  start = true
--                }
-- )
-- 
-- Install:andUse("Caffeine", {
--                  start = true,
--                  hotkeys = {
--                    toggle = { mash, "0" }
--                  },
--                  fn = function(s)
--                    BTT:bindSpoonActions(s, {
--                                           toggle = {
--                                             kind = 'touchbarWidget',
--                                             uuid = '72A96332-E908-4872-A6B4-8A6ED2E3586F',
--                                             name = 'Caffeine',
--                                             widget_code = [[
-- do
--   title = " "
--   icon = hs.image.imageFromPath(spoon.Caffeine.spoonPath.."/caffeine-off.pdf")
--   if (hs.caffeinate.get('displayIdle')) then
--     icon = hs.image.imageFromPath(spoon.Caffeine.spoonPath.."/caffeine-on.pdf")
--   end
--   print(hs.json.encode({ text = title, icon_data = BTT:hsimageToBTTIconData(icon) }))
-- end
--   ]],
--                                             code = "spoon.Caffeine.clicked()",
--                                             widget_interval = 1,
--                                             color = hs.drawing.color.x11.black,
--                                             icon_only = true,
--                                             icon_size = hs.geometry.size(15,15),
--                                             BTTTriggerConfig = {
--                                               BTTTouchBarFreeSpaceAfterButton = 0,
--                                               BTTTouchBarItemPadding = -6,
--                                             },
--                                           }
--                    })
--                  end
-- })
-- 
-- Install:andUse("TimeMachineProgress",
--                {
--                  start = true
--                }
-- )
-- 
-- Install:andUse("FadeLogo",
--                {
--                  config = {
--                    default_run = 1.0,
--                  },
--                  start = true
--                }
-- )
-- 
function applicationWatcher(appName, eventType, appObject)
  if (eventType == hs.application.watcher.activated) then
    if (appName == "Finder") then
      -- Bring all Finder windows forward when one gets activated
      appObject:selectMenuItem({"Window", "Bring All to Front"})
    end
  end
end
appWatcher = hs.application.watcher.new(applicationWatcher)
appWatcher:start()


-- require('vaughan-layout') -- Load Hammerspoon bits from https://github.com/jasonrudolph/keyboard


-- vim = hs.loadSpoon('VimMode')
-- 
-- -- Basic key binding to ctrl+;
-- -- You can choose any key binding you want here, see:
-- --   https://www.hammerspoon.org/docs/hs.hotkey.html#bind
-- 
-- hs.hotkey.bind({'ctrl'}, ';', function()
--   vim:enter()
-- end)
-- 
-- vim:enableKeySequence('j', 'j')
-- -- sometimes you need to check Activity Monitor to get the app's
-- -- real name
-- vim:disableForApp('Code')
-- vim:disableForApp('iTerm')
-- vim:disableForApp('MacVim')
-- vim:disableForApp('Terminal')
