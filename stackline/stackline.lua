u = require 'utils'

local wf    = hs.window.filter
local timer = hs.timer.delayed
local click = hs.eventtap.event.types['leftMouseDown'] -- fyi, print hs.eventtap.event.types to see all event types
local log   = hs.logger.new('stackline', 'info')

log.i("Loading module")

stackline = {}
stackline.config = require 'stackline.configManager'
stackline.window = require 'stackline.window'

function stackline:init(userConfig)
    log.i('starting stackline')

    -- Default window filter controls what windows hs "sees"
    -- Required before initialization
    self.wf = wf.new():setOverrideFilter{  -- {{{
        visible = true, -- (i.e. not hidden and not minimized)
        fullscreen = false,
        currentSpace = true,
        allowRoles = 'AXStandardWindow',
    }  -- }}}

    userConfig = userConfig or {}
    self.config:init( -- init config with default conf + user overrides
        table.merge(require 'conf', userConfig)
    )

    -- init stackmanager, then run update
    self.manager = require 'stackline.stackmanager':init()
    self.manager:update()

    local maxRefreshRate = self.config:get('advanced.maxRefreshRate') or 0.3

    -- throttledUpdate() runs at most once every 0.3s
    -- NOTE: yabai is only queried if Hammerspoon query results are different than current state
    self.throttledUpdate = timer.new(maxRefreshRate, function()  -- {{{
        self.manager:update()
    end)  -- }}}

    self.updateOn = { -- {{{
        wf.windowCreated,      -- ↓ window added
        wf.windowUnhidden,
        wf.windowUnminimized,

        wf.windowFullscreened, -- ↓ window changed
        wf.windowUnfullscreened,
        wf.windowMoved, -- NOTE: winMoved includes move AND resize evts

        wf.windowDestroyed,    -- ↓ window removed
        wf.windowHidden,
        wf.windowMinimized,
    } -- }}}
    self.redrawOn = {  -- {{{
        wf.windowFocused,
        wf.windowNotVisible,
        wf.windowUnfocused,
    } -- }}}

    -- On each win evt above (or at most once every `maxRefreshRate`, which is 0.3s by default)
    -- query window state and check if refersh needed
    self.wf:subscribe(self.updateOn, function(_win, _app, _evt)
            self.throttledUpdate:start()
        end
    )

    -- On each win evt listed, simply *redraw* indicators
    -- No need for heavyweight query + refresh
    self.wf:subscribe(self.redrawOn, self.redrawWinIndicator)

    -- Activate clickToFocus if feature turned on
    if self.config:get('features.clickToFocus') then  -- {{{
        log.i('FEAT: ClickTracker starting')

        -- if indicator containing the clickAt position can be found, focus that indicator's window
        local function onClick(e)
            local x, y = e:location().x, e:location().y
            local clickAt = hs.geometry.point(x,y)
            local clickedWin = self.manager:getClickedWindow(clickAt)
            if clickedWin then
                clickedWin._win:focus()
                return true -- stops propogation
            end
        end

        -- Listen for left mouse click events
        self.clickTracker = hs.eventtap.new({click}, onClick)

        self.clickTracker:start()
    end  -- }}}

end

function stackline:refreshClickTracker() -- {{{
    local turnedOn = self.config:get('features.clickToFocus')

    if self.clickTracker:isEnabled() then
        self.clickTracker:stop() -- always stop if running
    end
    if turnedOn then -- only start if feature is enabled
        log.d('features.clickToFocus is enabled!')
        self.clickTracker:start()
    else
        log.d('features.clickToFocus is disabled')
        self.clickTracker:stop() -- double-stop if disabled
    end
end -- }}}

function stackline.redrawWinIndicator(hsWin, _app, _event) -- {{{
    -- u.p(_event)

    -- Dedicated redraw method to *adjust* the existing canvas element is WAY
    -- faster than deleting the entire indicator & rebuilding it from scratch,
    -- particularly since this skips querying the app icon & building the icon image.
    local stackedWin = stackline.manager:findWindow(hsWin:id())
    if stackedWin then -- if non-existent, the focused win is not stacked
        stackedWin.indicator:redraw(_event)
    end
end -- }}}

hs.spaces.watcher.new(function() -- {{{
    -- On space switch, query window state & refresh,
    -- plus refresh click tracker
    stackline.throttledUpdate:start()
    stackline:refreshClickTracker()
end):start() -- }}}

return stackline
