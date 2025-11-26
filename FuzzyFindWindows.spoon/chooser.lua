local M = {}

local chooser = require("hs.chooser")
local timer = require("hs.timer")
local hotkey = require("hs.hotkey")
local window = require("hs.window")
local logger = require("hs.logger").new("FuzzyFindWindows", "debug")

-- Helper to load modules from the same directory
local function loadModule(name)
    local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
    if spoonPath then
        package.path = package.path .. ";" .. spoonPath .. "?.lua"
    end
    return require(name)
end

local cache = loadModule("cache")
local refresh = loadModule("refresh")
local browser = loadModule("browser")

function M.ensureChooser(self)
    -- Use the filter module from init.lua, or fall back to loading "filter"
    local filter = self._filterModule or loadModule("filter")
    if not filter then
        logger:e("ensureChooser: Failed to get filter module!")
        return
    end
    logger:d("ensureChooser: Using filter module: " .. (self._filterModule and "from init.lua" or "fallback 'filter'"))
    if not self._chooser then
        self._chooser = chooser.new(function(choice)
            if not choice then
                return
            end

            if not choice.id and (choice.text or ""):find("Rebuilding index", 1, true) then
                return
            end

            local id = choice.id or (choice.meta and choice.meta.id)
            if type(id) == "string" then
                id = tonumber(id)
            end
            
            if not id then
                return
            end

            local win = nil
            
            if choice.meta and choice.meta.win then
                local cachedId = choice.meta.win:id()
                if cachedId == id then
                    win = choice.meta.win
                end
            end
            
            if not win then
                local cachedMeta = self._indexById[id]
                if cachedMeta and cachedMeta.win then
                    local cachedId = cachedMeta.win:id()
                    if cachedId == id then
                        win = cachedMeta.win
                    end
                end
            end
            
            if not win then
                win = window.get(id)
                if win then
                    local cachedMeta = self._indexById[id]
                    if cachedMeta then
                        cachedMeta.win = win
                    end
                    if choice.meta then
                        choice.meta.win = win
                    end
                end
            end
            
            if not win then
                return
            end

            -- Get the choice key for tracking
            local choiceKey = cache.getChoiceKey(self, choice)
            
            -- Update selection tracking
            if choiceKey ~= self._lastSelectedKey then
                -- Move current last to second-to-last, new selection becomes last
                self._secondLastSelectedKey = self._lastSelectedKey
                self._lastSelectedKey = choiceKey
            end
            
            -- Increment score for this choice
            if choice.meta and choice.meta.type == "tab" then
                -- Increment score on the tab object
                if choice.meta.tab then
                    choice.meta.tab.score = (choice.meta.tab.score or 0) + 1
                end
            else
                -- Increment score on the window meta object
                local cachedMeta = self._indexById[id]
                if cachedMeta then
                    cachedMeta.score = (cachedMeta.score or 0) + 1
                end
            end
            
            -- Rebuild and sort choices
            cache.rebuildChoicesFromIndex(self)
            if self._chooser and self._chooser:isVisible() then
                local q = self._chooser:query() or ""
                filter.applyFilter(self, q)
            end

            -- Check if this is a tab selection
            if choice.meta and choice.meta.type == "tab" then
                -- For tabs, activate app, focus window, then click the tab button
                local app = win:application()
                
                if app then
                    app:activate(true)
                end

                win:focus()
                
                local tabTitle = choice.meta.tabTitle
                if tabTitle then
                    -- Small delay to ensure window is focused before clicking tab
                    timer.doAfter(0.1, function()
                        browser.clickTabByTitle(self, win, tabTitle)
                    end)
                else
                    logger:w("Chooser callback: tab selected but tabTitle is missing")
                end
            else
                -- For regular windows, activate and focus
                local app = win:application()
                
                if app then
                    app:activate(true)
                end

                win:focus()
            end
        end)

        self._chooser:width(30)
        self._chooser:rows(15)
        self._chooser:searchSubText(true)
        self._chooser:placeholderText("Switch window…")

        self._chooser:queryChangedCallback(function(q)
            filter.applyFilter(self, q)
        end)
    end

    if not self._refreshHotkey then
        self._refreshHotkey = hotkey.bind({ "ctrl" }, "r", function()
            if self._chooser and self._chooser:isVisible() then
                if self._rescanInProgress then 
                    logger:w("Ctrl-R: rescan already in progress, ignoring")
                    return 
                end
                filter.showRebuildMessage(self)
                timer.doAfter(0, function()
                    refresh.fullRefresh(self)
                end)
            else
                logger:w("Ctrl-R: chooser not visible or nil (chooser=" .. tostring(self._chooser) .. ", visible=" .. tostring(self._chooser and self._chooser:isVisible()) .. ")")
            end
        end)
    end
end

return M

