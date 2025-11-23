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
local ax = require("hs.axuielement")
local logger  = require("hs.logger").new("FuzzyFindWindows", "debug")

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

obj.windowFilter      = nil

-- Default configuration
obj.defaultHotkeys = {
    search = { { "cmd", "alt", "ctrl", "shift" }, "w" },
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function isBrowserApp(app)
    if not app then return false end
    
    local bid = app:bundleID()
    
    return bid == "com.apple.Safari"
        or bid == "org.mozilla.firefox"
        or bid == "com.google.Chrome"
end

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


local function findTabButton(element, depth, maxDepth)
    if not element or depth > maxDepth then return nil end
    
    local role = element:attributeValue("AXRole")
    local subrole = element:attributeValue("AXSubrole")
    
    if role == "AXRadioButton" and subrole == "AXTabButton" then
        return element
    end
    
    local children = element:attributeValue("AXChildren")
    if not children then return nil end
    
    for _, child in ipairs(children) do
        local found = findTabButton(child, depth + 1, maxDepth)
        if found then return found end
    end
    
    return nil
end

function obj:_getTabsForBrowser(win)
    local axWin = ax.windowElement(win)
    if not axWin then
        return {}
    end
    
    local tabButton = findTabButton(axWin, 1, 12)
    if not tabButton then
        return {}
    end
    
    local tabGroup = tabButton:attributeValue("AXParent")
    if not tabGroup then
        return {}
    end
    
    local tabs = {}
    local children = tabGroup:attributeValue("AXChildren") or {}
    
    for _, child in ipairs(children) do
        local childRole = child:attributeValue("AXRole")
        local subrole = child:attributeValue("AXSubrole")
        
        if childRole == "AXRadioButton" and subrole == "AXTabButton" then
            local title = child:attributeValue("AXDescription") or ""
            if title == "" then
                title = child:attributeValue("AXTitle") or ""
            end
            
            if title ~= "" then
                table.insert(tabs, {
                    title = title,
                    win   = win,
                })
            else
                logger:w("_getTabsForBrowser: found tab button but title is empty")
            end
        end
    end
    
    return tabs
end

function obj:_getTabsForWindow(win)
    local app = win:application()
    if not app then
        return {}
    end
    
    if not isBrowserApp(app) then
        return {}
    end
    
    return self:_getTabsForBrowser(win)
end

local function windowToMeta(win, selfObj)
    local app = win:application()
    if not app then return nil end

    local appName  = app:name() or ""
    local winTitle = win:title() or ""
    local bundleID = app:bundleID() or ""
    local winId    = win:id()
    local isMinimized = win:isMinimized()

    if not winId then return nil end
    if shouldExcludeWindow(win, appName) then return nil end

    local meta = {
        id          = winId,
        title       = winTitle,
        appName     = appName,
        bundleID    = bundleID,
        isMinimized = isMinimized,
        win         = win,
    }
    
    if selfObj and isBrowserApp(app) then
        meta.tabs = selfObj:_getTabsForWindow(win)
    end
    
    return meta
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
    local totalTabs = 0
    for _, meta in pairs(self._indexById) do
        table.insert(choices, metaToChoice(meta))
        
        if meta.tabs and #meta.tabs > 0 then
            totalTabs = totalTabs + #meta.tabs
            for _, tab in ipairs(meta.tabs) do
                table.insert(choices, {
                    text = tab.title or "[Untitled Tab]",
                    subText = meta.appName .. " - Tab",
                    id = meta.id,
                    meta = {
                        type = "tab",
                        win = tab.win,
                        id = meta.id,
                        tabTitle = tab.title,
                        appName = meta.appName,
                    }
                })
            end
        end
    end
    table.sort(choices, function(a, b)
        return a.text:lower() < b.text:lower()
    end)
    self._choices = choices
end

function obj:_addWindowToCache(win)
    local meta = windowToMeta(win, self)
    if not meta then return end

    self._indexById[meta.id] = meta

    self:_rebuildChoicesFromIndex()

    if self._chooser and self._chooser:isVisible() then
        self._chooser:choices(self._choices)
    end
end

function obj:_removeWindowFromCacheById(winId)
    if not winId then return end

    self._indexById[winId] = nil

    self:_rebuildChoicesFromIndex()

    if self._chooser and self._chooser:isVisible() then
        self._chooser:choices(self._choices)
    end
end

----------------------------------------------------------------------
-- Filtering + rebuild UI helpers
----------------------------------------------------------------------

function obj:_showRebuildMessage()
    if not self._chooser then 
        logger:w("_showRebuildMessage: chooser is nil!")
        return 
    end
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
-- Full refresh
----------------------------------------------------------------------

function obj:_ensureWindowFilter()
    if self.windowFilter then return end

    -- setDefaultFilter{} => include invisible/minimized windows too, all Spaces
    -- ref: inv_wf = windowfilter.new():setDefaultFilter{}  (CommandPost docs)  [oai_citation:1‡CommandPost](https://commandpost.fcp.cafe/api-references/hammerspoon/hs.window.filter/?utm_source=chatgpt.com)
    self.windowFilter = wfilter.new():setDefaultFilter({})
end

function obj:_fullRefresh()
    if self._rescanInProgress then 
        logger:w("_fullRefresh: rescan already in progress, returning early")
        return 
    end
    self._rescanInProgress = true

    self:_ensureWindowFilter()

    if self._chooser and self._chooser:isVisible() then
        self._pendingQuery = self._chooser:query() or ""
    else
        self._pendingQuery = ""
    end

    local allWindows = self.windowFilter:getWindows()

    self._indexById = {}
    for _, win in ipairs(allWindows) do
        local meta = windowToMeta(win, self)
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

            local app = win:application()
            
            if app then
                app:activate(true)
            end

            win:focus()
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
                if self._rescanInProgress then 
                    logger:w("Ctrl-R: rescan already in progress, ignoring")
                    return 
                end
                self:_showRebuildMessage()
                timer.doAfter(0, function()
                    self:_fullRefresh()
                end)
            else
                logger:w("Ctrl-R: chooser not visible or nil (chooser=" .. tostring(self._chooser) .. ", visible=" .. tostring(self._chooser and self._chooser:isVisible()) .. ")")
            end
        end)
    end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function obj:init()
    return self
end

function obj:show()
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