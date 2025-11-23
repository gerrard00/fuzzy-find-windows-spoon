local obj = {}
obj.__index = obj

-- Metadata
obj.name     = "FuzzyFindWindows"
obj.version  = "1.1"
obj.author   = ""
obj.license  = "MIT"
obj.homepage = "https://github.com/gerrard00/fuzzy-find-windows"

-- Dependencies
local window  = require("hs.window")
local wfilter = require("hs.window.filter")
local chooser = require("hs.chooser")
local timer   = require("hs.timer")
local hotkey  = require("hs.hotkey")

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------

obj._chooser          = nil
obj.hotkey            = nil
obj._indexById        = {}   -- id -> meta
obj._choices          = {}   -- flat list of chooser rows
obj._cacheBuilt       = false
obj._windowWatcher    = nil

obj._rescanInProgress = false
obj._refreshHotkey    = nil
obj._pendingQuery     = nil

obj.windowFilter      = nil  -- hs.window.filter instance

-- Default configuration
obj.defaultHotkeys = {
    search = { { "cmd", "alt", "ctrl", "shift" }, "w" },
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function shouldExcludeWindow(win, appName)
    if not win then return true end

    local app = win:application()
    appName = appName or (app and app:name() or "")

    -- filter out Hammerspoon chooser / popover windows
    if appName == "Hammerspoon" then
        local role = win:role()
        if role == "AXPopover" or role == "AXDialog" then
            return true
        end
    end

    return false
end

local function windowToMeta(win)
    local app = win:application()
    if not app then return nil end

    local appName  = app:name() or ""
    local winTitle = win:title() or ""
    local bundleID = app:bundleID() or ""
    local winId    = win:id()
    local isMinimized = win:isMinimized()

    if not winId then return nil end
    if shouldExcludeWindow(win, appName) then return nil end

    return {
        id          = winId,
        title       = winTitle,
        appName     = appName,
        bundleID    = bundleID,
        isMinimized = isMinimized,
        win         = win,  -- Cache the window object to avoid slow window.get(id) calls
    }
end

local function metaToChoice(meta)
    return {
        text    = (meta.title ~= "" and meta.title) or "[Untitled]",
        subText = meta.appName,
        id      = meta.id,
        meta    = meta,
    }
end

----------------------------------------------------------------------
-- Index + choices management
----------------------------------------------------------------------

function obj:_rebuildChoicesFromIndex()
    local choices = {}
    for _, meta in pairs(self._indexById) do
        table.insert(choices, metaToChoice(meta))
    end
    table.sort(choices, function(a, b)
        return a.text:lower() < b.text:lower()
    end)
    self._choices = choices
end

function obj:_addWindowToCache(win)
    local meta = windowToMeta(win)
    if not meta then return end

    self._indexById[meta.id] = meta

    table.insert(self._choices, metaToChoice(meta))
    table.sort(self._choices, function(a, b)
        return a.text:lower() < b.text:lower()
    end)

    if self._chooser and self._chooser:isVisible() then
        self._chooser:choices(self._choices)
    end
end

function obj:_removeWindowFromCacheById(winId)
    if not winId then return end

    self._indexById[winId] = nil

    for i, choice in ipairs(self._choices) do
        if choice.id == winId then
            table.remove(self._choices, i)
            break
        end
    end

    if self._chooser and self._chooser:isVisible() then
        self._chooser:choices(self._choices)
    end
end

----------------------------------------------------------------------
-- Filtering + rebuild UI helpers
----------------------------------------------------------------------

function obj:_showRebuildMessage()
    if not self._chooser then return end
    self._chooser:choices({
        {
            text    = "Rebuilding index…",
            subText = "This may take a few seconds",
            id      = nil,
        },
    })
end

function obj:_applyFilter(query)
    if not self._chooser then return end

    local q = (query or ""):lower()
    if q == "" then
        self._chooser:choices(self._choices)
        return
    end

    local filtered = {}
    for _, choice in ipairs(self._choices) do
        local text    = (choice.text or ""):lower()
        local subText = (choice.subText or ""):lower()
        if text:find(q, 1, true) or subText:find(q, 1, true) then
            table.insert(filtered, choice)
        end
    end
    self._chooser:choices(filtered)
end

----------------------------------------------------------------------
-- Full refresh via window.filter (includes invisible windows)
----------------------------------------------------------------------

function obj:_ensureWindowFilter()
    if self.windowFilter then return end

    -- setDefaultFilter{} => include invisible/minimized windows too, all Spaces
    -- ref: inv_wf = windowfilter.new():setDefaultFilter{}  (CommandPost docs)  [oai_citation:1‡CommandPost](https://commandpost.fcp.cafe/api-references/hammerspoon/hs.window.filter/?utm_source=chatgpt.com)
    self.windowFilter = wfilter.new():setDefaultFilter({})
end

function obj:_fullRefresh()
    if self._rescanInProgress then return end
    self._rescanInProgress = true

    self:_ensureWindowFilter()

    if self._chooser and self._chooser:isVisible() then
        self._pendingQuery = self._chooser:query() or ""
    else
        self._pendingQuery = ""
    end

    local startTime = timer.absoluteTime()
    local allWindows = self.windowFilter:getWindows()
    local elapsed = (timer.absoluteTime() - startTime) / 1e9
    print(string.format(
        "[FuzzyFindWindows] fullRefresh: windowFilter:getWindows() took %.3f s, %d windows",
        elapsed, #allWindows
    ))

    self._indexById = {}
    for _, win in ipairs(allWindows) do
        local meta = windowToMeta(win)
        if meta then
            self._indexById[meta.id] = meta
        end
    end

    self:_rebuildChoicesFromIndex()
    self._cacheBuilt       = true
    self._rescanInProgress = false

    self:_setupWindowWatcher()

    if self._chooser and self._chooser:isVisible() then
        local q = self._pendingQuery or ""
        self._pendingQuery = nil
        self:_applyFilter(q)
        self._chooser:query(q)
    else
        self._pendingQuery = nil
    end
end

----------------------------------------------------------------------
-- Window watcher
----------------------------------------------------------------------

function obj:_setupWindowWatcher()
    if self._windowWatcher then return end

    self:_ensureWindowFilter()

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

----------------------------------------------------------------------
-- Chooser
----------------------------------------------------------------------

function obj:_ensureChooser()
    if not self._chooser then
        self._chooser = chooser.new(function(choice)
            local callbackStartTime = timer.absoluteTime()
            print("[FuzzyFindWindows] Chooser callback started")
            
            if not choice then
                print("[FuzzyFindWindows] No choice selected")
                return
            end

            -- Ignore the "Rebuilding index…" pseudo-row
            if not choice.id and (choice.text or ""):find("Rebuilding index", 1, true) then
                return
            end

            print(string.format(
                "[FuzzyFindWindows] Choice selected: %q (id=%s, type=%s)",
                tostring(choice.text),
                tostring(choice.id),
                type(choice.id)
            ))

            local idExtractStart = timer.absoluteTime()
            local id = choice.id or (choice.meta and choice.meta.id)
            if type(id) == "string" then
                id = tonumber(id)
            end
            local idExtractElapsed = (timer.absoluteTime() - idExtractStart) / 1e9
            print(string.format("[FuzzyFindWindows] ID extraction took %.3f ms", idExtractElapsed * 1000))
            
            if not id then
                print("[FuzzyFindWindows] ERROR: no valid id for choice")
                return
            end

            local windowGetStart = timer.absoluteTime()
            -- Try to use cached window object first (much faster than window.get)
            local win = nil
            local usedCache = false
            
            -- First try choice.meta.win (if available)
            if choice.meta and choice.meta.win then
                local cachedId = choice.meta.win:id()
                if cachedId == id then
                    win = choice.meta.win
                    usedCache = true
                    print(string.format("[FuzzyFindWindows] Using cached window from choice.meta for id %s", tostring(id)))
                end
            end
            
            -- Fallback to index cache
            if not win then
                local cachedMeta = self._indexById[id]
                if cachedMeta and cachedMeta.win then
                    -- Validate cached window is still valid
                    local cachedId = cachedMeta.win:id()
                    if cachedId == id then
                        win = cachedMeta.win
                        usedCache = true
                        print(string.format("[FuzzyFindWindows] Using cached window from index for id %s", tostring(id)))
                    else
                        print(string.format("[FuzzyFindWindows] Cached window object invalid (id mismatch: %s vs %s), falling back to window.get", tostring(cachedId), tostring(id)))
                    end
                end
            end
            
            -- Fallback to window.get if cache miss or invalid
            if not win then
                win = window.get(id)
                if win then
                    -- Update cache with fresh window object
                    local cachedMeta = self._indexById[id]
                    if cachedMeta then
                        cachedMeta.win = win
                    end
                    -- Also update choice.meta if it exists
                    if choice.meta then
                        choice.meta.win = win
                    end
                end
            end
            
            local windowGetElapsed = (timer.absoluteTime() - windowGetStart) / 1e9
            print(string.format("[FuzzyFindWindows] window retrieval took %.3f ms (cached=%s)", windowGetElapsed * 1000, tostring(usedCache)))
            
            if not win then
                print("[FuzzyFindWindows] ERROR: Could not retrieve window for id " .. tostring(id))
                return
            end

            local appGetStart = timer.absoluteTime()
            local app = win:application()
            local appGetElapsed = (timer.absoluteTime() - appGetStart) / 1e9
            print(string.format("[FuzzyFindWindows] win:application() took %.3f ms", appGetElapsed * 1000))
            
            if app then
                local activateStart = timer.absoluteTime()
                -- true: better behavior across Spaces + hidden apps  [oai_citation:2‡hammerspoon.org](https://www.hammerspoon.org/docs/hs.application.html?utm_source=chatgpt.com)
                app:activate(true)
                local activateElapsed = (timer.absoluteTime() - activateStart) / 1e9
                print(string.format("[FuzzyFindWindows] app:activate(true) took %.3f ms", activateElapsed * 1000))
            end

            local focusStart = timer.absoluteTime()
            win:focus()
            local focusElapsed = (timer.absoluteTime() - focusStart) / 1e9
            print(string.format("[FuzzyFindWindows] win:focus() took %.3f ms", focusElapsed * 1000))

            local callbackTotalElapsed = (timer.absoluteTime() - callbackStartTime) / 1e9
            print(string.format("[FuzzyFindWindows] Total callback time: %.3f ms", callbackTotalElapsed * 1000))
        end)

        self._chooser:width(30)
        self._chooser:rows(15)
        self._chooser:searchSubText(true)
        self._chooser:placeholderText("Switch window…")

        self._chooser:queryChangedCallback(function(q)
            self:_applyFilter(q)
        end)
    end

    if not self._refreshHotkey then
        self._refreshHotkey = hotkey.bind({ "ctrl" }, "r", function()
            if self._chooser and self._chooser:isVisible() then
                if self._rescanInProgress then return end
                self:_showRebuildMessage()
                timer.doAfter(0, function()
                    self:_fullRefresh()
                end)
            end
        end)
    end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function obj:init()
    -- Defer filter creation until needed, but you *could* eagerly do:
    -- self:_ensureWindowFilter()
    return self
end

function obj:show()
    print("[FuzzyFindWindows] show() called; cacheBuilt=" .. tostring(self._cacheBuilt))

    self:_ensureChooser()

    self._chooser:query("")
    self:_applyFilter("")
    self._chooser:show()

    if not self._cacheBuilt then
        self:_showRebuildMessage()
        timer.doAfter(0, function()
            self:_fullRefresh()
        end)
    end
end

function obj:hide()
    if self._chooser then
        self._chooser:hide()
    end
end

function obj:bindHotkeys(mapping)
    local m = mapping or self.defaultHotkeys

    if self.hotkey then
        self.hotkey:delete()
        self.hotkey = nil
    end

    local spec = m.search
    if not spec then return end

    local mods = spec[1]
    local key  = spec[2]
    if not mods or not key then return end

    if type(mods) == "string" then mods = { mods } end
    if type(mods) ~= "table" or #mods == 0 then return end

    self.hotkey = hotkey.bind(mods, key, function()
        self:show()
    end)
end

function obj:start()
    return self
end

function obj:stop()
    self:hide()

    if self._windowWatcher then
        self._windowWatcher:unsubscribe()
        self._windowWatcher = nil
    end

    if self.hotkey then
        self.hotkey:delete()
        self.hotkey = nil
    end

    if self._refreshHotkey then
        self._refreshHotkey:delete()
        self._refreshHotkey = nil
    end

    self._rescanInProgress = false
    self._cacheBuilt       = false
    self._indexById        = {}
    self._choices          = {}

    return self
end

return obj