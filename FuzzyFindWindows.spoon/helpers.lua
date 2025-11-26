local M = {}

local logger = require("hs.logger").new("FuzzyFindWindows", "debug")

-- Helper to load modules from the same directory
local function loadModule(name)
    local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
    if spoonPath then
        package.path = package.path .. ";" .. spoonPath .. "?.lua"
    end
    return require(name)
end

-- Import browser module for isBrowserApp
local browser = loadModule("browser")

function M.shouldExcludeWindow(win, appName)
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

function M.windowToMeta(win, selfObj)
    local app = win:application()
    if not app then return nil end

    local appName  = app:name() or ""
    local winTitle = win:title() or ""
    local bundleID = app:bundleID() or ""
    local winId    = win:id()
    local isMinimized = win:isMinimized()

    if not winId then return nil end
    if M.shouldExcludeWindow(win, appName) then return nil end

    -- Preserve existing score if meta already exists
    local existingMeta = selfObj and selfObj._indexById[winId]
    local existingScore = existingMeta and existingMeta.score or 0

    local meta = {
        id          = winId,
        title       = winTitle,
        appName     = appName,
        bundleID    = bundleID,
        isMinimized = isMinimized,
        win         = win,
        score       = existingScore,
    }
    
    if selfObj and browser.isBrowserApp(app) then
        meta.tabs = selfObj:_getTabsForWindow(win)
        -- Preserve scores for existing tabs
        if existingMeta and existingMeta.tabs then
            local tabScoresByTitle = {}
            for _, existingTab in ipairs(existingMeta.tabs) do
                if existingTab.title and existingTab.score then
                    tabScoresByTitle[existingTab.title] = existingTab.score
                end
            end
            -- Apply preserved scores to new tabs
            for _, tab in ipairs(meta.tabs) do
                if tab.title and tabScoresByTitle[tab.title] then
                    tab.score = tabScoresByTitle[tab.title]
                else
                    tab.score = 0
                end
            end
        else
            -- Initialize scores for new tabs
            for _, tab in ipairs(meta.tabs) do
                tab.score = 0
            end
        end
    end
    
    return meta
end

function M.metaToChoice(meta)
    return {
        text    = (meta.title ~= "" and meta.title) or "[Untitled]",
        subText = meta.appName,
        id      = meta.id,
        meta    = meta,
    }
end

return M

