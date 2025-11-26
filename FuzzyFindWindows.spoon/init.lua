local obj = {}
obj.__index = obj

-- Metadata
obj.name     = "FuzzyFindWindows"
obj.version  = "1.1"
obj.author   = ""
obj.license  = "MIT"
obj.homepage = "https://github.com/gerrard00/fuzzy-find-windows"

-- Dependencies
local timer   = require("hs.timer")
local hotkey  = require("hs.hotkey")

-- Helper to load modules from the same directory
local function loadModule(name)
    local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
    if spoonPath then
        local pathToAdd = spoonPath .. "?.lua"
        if not package.path:match(pathToAdd:gsub("%.", "%%.")) then
            package.path = package.path .. ";" .. pathToAdd
        end
    end
    return require(name)
end

-- Configuration: choose filter implementation
-- Set to "filter" for simple string matching, or "filter_fuzzy" for fzy-lua fuzzy matching
-- local FILTER_TYPE = "filter"  -- Change to "filter_fuzzy" to use fzy-lua
local FILTER_TYPE = "filter_fuzzy"

-- Load modules
local logger = require("hs.logger").new("FuzzyFindWindows", "debug")
logger:d("Loading filter module: " .. FILTER_TYPE)

local browser = loadModule("browser")
local cache   = loadModule("cache")
local filter  = loadModule(FILTER_TYPE)

if filter then
    logger:d("Successfully loaded filter module: " .. FILTER_TYPE)
else
    logger:e("Failed to load filter module: " .. FILTER_TYPE)
end
local watcher = loadModule("watcher")
local refresh = loadModule("refresh")
local chooser = loadModule("chooser")

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
obj._lastSelectedKey  = nil
obj._secondLastSelectedKey = nil
obj._filterModule     = filter  -- Store filter module reference for other modules

-- Default configuration
obj.defaultHotkeys = {
    search = { { "cmd", "alt", "ctrl", "shift" }, "w" },
}

----------------------------------------------------------------------
-- Attach module methods to object
----------------------------------------------------------------------

-- Browser methods
obj._getTabsForBrowser = function(self, win) return browser.getTabsForBrowser(win) end
obj._getTabsForWindow  = function(self, win) return browser.getTabsForWindow(self, win) end
obj._clickTabByTitle   = function(self, win, tabTitle) return browser.clickTabByTitle(self, win, tabTitle) end

-- Cache methods
obj._getChoiceKey            = function(self, choice) return cache.getChoiceKey(self, choice) end
obj._sortChoices              = function(self, choices) return cache.sortChoices(self, choices) end
obj._rebuildChoicesFromIndex  = function(self) return cache.rebuildChoicesFromIndex(self) end
obj._addWindowToCache         = function(self, win) return cache.addWindowToCache(self, win) end
obj._removeWindowFromCacheById = function(self, winId) return cache.removeWindowFromCacheById(self, winId) end

-- Filter methods
obj._showRebuildMessage = function(self) return filter.showRebuildMessage(self) end
obj._applyFilter        = function(self, query) return filter.applyFilter(self, query) end

-- Watcher methods
obj._ensureWindowFilter = function(self) return watcher.ensureWindowFilter(self) end
obj._setupWindowWatcher  = function(self) return watcher.setupWindowWatcher(self) end

-- Refresh methods
obj._fullRefresh = function(self) return refresh.fullRefresh(self) end

-- Chooser methods
obj._ensureChooser = function(self) return chooser.ensureChooser(self) end

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
    self._lastSelectedKey  = nil
    self._secondLastSelectedKey = nil

    return self
end

return obj
