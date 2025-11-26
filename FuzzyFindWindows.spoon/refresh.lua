local M = {}

-- Helper to load modules from the same directory
local function loadModule(name)
    local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
    if spoonPath then
        package.path = package.path .. ";" .. spoonPath .. "?.lua"
    end
    return require(name)
end

local helpers = loadModule("helpers")
local watcher = loadModule("watcher")
local filter = loadModule("filter")

function M.fullRefresh(self)
    if self._rescanInProgress then 
        local logger = require("hs.logger").new("FuzzyFindWindows", "debug")
        logger:w("_fullRefresh: rescan already in progress, returning early")
        return 
    end
    self._rescanInProgress = true

    watcher.ensureWindowFilter(self)

    if self._chooser and self._chooser:isVisible() then
        self._pendingQuery = self._chooser:query() or ""
    else
        self._pendingQuery = ""
    end

    local allWindows = self.windowFilter:getWindows()

    self._indexById = {}
    for _, win in ipairs(allWindows) do
        local meta = helpers.windowToMeta(win, self)
        if meta then
            self._indexById[meta.id] = meta
        end
    end

    local cache = loadModule("cache")
    cache.rebuildChoicesFromIndex(self)
    self._cacheBuilt       = true
    self._rescanInProgress = false

    watcher.setupWindowWatcher(self)

    if self._chooser and self._chooser:isVisible() then
        local q = self._pendingQuery or ""
        self._pendingQuery = nil
        filter.applyFilter(self, q)
        self._chooser:query(q)
    else
        self._pendingQuery = nil
    end
end

return M

