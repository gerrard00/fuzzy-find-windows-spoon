local M = {}

local logger = require("hs.logger").new("FuzzyFindWindows", "debug")

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

local fzy = loadModule("fzy_lua")
if not fzy then
    logger:e("filter_fuzzy: Failed to load fzy_lua module!")
end

function M.showRebuildMessage(self)
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

function M.applyFilter(self, query)
    if not self._chooser then 
        logger:w("applyFilter: chooser is nil!")
        return 
    end

    local q = query or ""
    
    if q == "" then
        self._chooser:choices(self._choices)
        return
    end

    -- Build haystack array from choices (combine text and subText for better matching)
    local haystacks = {}
    for i, choice in ipairs(self._choices) do
        local text = choice.text or ""
        local subText = choice.subText or ""
        -- Combine text and subText for matching, separated by space
        local searchableText = text
        if subText ~= "" then
            searchableText = text .. " " .. subText
        end
        table.insert(haystacks, searchableText)
    end

    -- Use fzy.filter to get matches with scores
    if not fzy or not fzy.filter then
        logger:e("applyFilter: fzy.filter is not available!")
        return
    end
    
    local results = fzy.filter(q, haystacks)

    if #results == 0 then
        logger:w("applyFilter: fzy.filter returned no matches for query='" .. q .. "'")
    end

    -- Sort results by score (descending - higher scores are better)
    table.sort(results, function(a, b)
        return a[3] > b[3]  -- Compare scores (third element)
    end)

    -- Map results back to original choices
    local filtered = {}
    for _, result in ipairs(results) do
        local idx = result[1]  -- Original index in haystacks/choices
        local choice = self._choices[idx]
        if choice then
            table.insert(filtered, choice)
        else
            logger:w("applyFilter: result idx " .. idx .. " does not correspond to a valid choice")
        end
    end

    self._chooser:choices(filtered)
end

return M

