local M = {}

local wfilter = require("hs.window.filter")
local timer = require("hs.timer")

function M.ensureWindowFilter(self)
    if self.windowFilter then return end

    -- setDefaultFilter{} => include invisible/minimized windows too, all Spaces
    -- ref: inv_wf = windowfilter.new():setDefaultFilter{}  (CommandPost docs)
    self.windowFilter = wfilter.new():setDefaultFilter({})
end

function M.setupWindowWatcher(self)
    if self._windowWatcher then return end

    M.ensureWindowFilter(self)

    self._windowWatcher = self.windowFilter:subscribe({
        wfilter.windowCreated,
        wfilter.windowDestroyed,
    }, function(win, appName, event)
        if event == wfilter.windowCreated then
            timer.doAfter(0.1, function()
                if win then self:_addWindowToCache(win) end
            end)
        elseif event == wfilter.windowDestroyed then
            if win then
                local id = win:id()
                self:_removeWindowFromCacheById(id)
            end
        end
    end)
end

return M


