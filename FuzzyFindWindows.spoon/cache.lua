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

function M.getChoiceKey(self, choice)
    if choice.meta and choice.meta.type == "tab" then
        return tostring(choice.meta.id) .. ":" .. (choice.meta.tabTitle or "")
    else
        return tostring(choice.id or "")
    end
end

function M.sortChoices(self, choices)
    -- Separate choices into three groups:
    -- 1. Second-to-last selected (goes first)
    -- 2. All others except last selected (sorted by score/name)
    -- 3. Last selected (goes last)
    local secondLastChoice = nil
    local lastChoice = nil
    local otherChoices = {}
    
    for _, choice in ipairs(choices) do
        local key = M.getChoiceKey(self, choice)
        if self._secondLastSelectedKey and key == self._secondLastSelectedKey then
            secondLastChoice = choice
        elseif self._lastSelectedKey and key == self._lastSelectedKey then
            lastChoice = choice
        else
            table.insert(otherChoices, choice)
        end
    end
    
    -- Sort other choices by score descending, then by name
    table.sort(otherChoices, function(a, b)
        local scoreA = a.score or 0
        local scoreB = b.score or 0
        
        if scoreA ~= scoreB then
            return scoreA > scoreB
        end
        
        return a.text:lower() < b.text:lower()
    end)
    
    -- Rebuild choices list: [second-to-last] + [sorted others] + [last]
    choices = {}
    if secondLastChoice then
        table.insert(choices, secondLastChoice)
    end
    for _, choice in ipairs(otherChoices) do
        table.insert(choices, choice)
    end
    if lastChoice then
        table.insert(choices, lastChoice)
    end
    
    return choices
end

function M.rebuildChoicesFromIndex(self)
    local choices = {}
    for _, meta in pairs(self._indexById) do
        local choice = helpers.metaToChoice(meta)
        choice.score = meta.score or 0
        table.insert(choices, choice)
        
        if meta.tabs and #meta.tabs > 0 then
            for _, tab in ipairs(meta.tabs) do
                local tabTitle = tab.title or "[Untitled Tab]"
                local choice = {
                    text = tabTitle,
                    subText = meta.appName .. " - Tab",
                    id = meta.id,
                    score = tab.score or 0,
                    meta = {
                        type = "tab",
                        win = tab.win,
                        id = meta.id,
                        tabTitle = tab.title,
                        appName = meta.appName,
                        tab = tab,  -- Reference to the tab object for score updates
                    }
                }
                table.insert(choices, choice)
            end
        end
    end
    
    choices = M.sortChoices(self, choices)
    self._choices = choices
end

function M.addWindowToCache(self, win)
    local meta = helpers.windowToMeta(win, self)
    if not meta then return end

    self._indexById[meta.id] = meta

    M.rebuildChoicesFromIndex(self)

    if self._chooser and self._chooser:isVisible() then
        self._chooser:choices(self._choices)
    end
end

function M.removeWindowFromCacheById(self, winId)
    if not winId then return end

    self._indexById[winId] = nil

    M.rebuildChoicesFromIndex(self)

    if self._chooser and self._chooser:isVisible() then
        self._chooser:choices(self._choices)
    end
end

return M

