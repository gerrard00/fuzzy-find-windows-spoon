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
else
    logger:d("filter_fuzzy: Successfully loaded fzy_lua module")
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
    logger:d("applyFilter: called with query='" .. q .. "'")
    
    if q == "" then
        logger:d("applyFilter: empty query, showing all " .. #self._choices .. " choices")
        self._chooser:choices(self._choices)
        return
    end

    local numChoices = #self._choices
    logger:d("applyFilter: filtering " .. numChoices .. " choices")

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
        if i <= 3 then
            logger:d("applyFilter: haystack[" .. i .. "] = '" .. searchableText .. "'")
        end
    end
    
    if numChoices > 3 then
        logger:d("applyFilter: ... and " .. (numChoices - 3) .. " more haystacks")
    end

    -- Use fzy.filter to get matches with scores
    if not fzy or not fzy.filter then
        logger:e("applyFilter: fzy.filter is not available!")
        return
    end
    
    logger:d("applyFilter: calling fzy.filter with needle='" .. q .. "' and " .. #haystacks .. " haystacks")
    local results = fzy.filter(q, haystacks)
    logger:d("applyFilter: fzy.filter returned " .. #results .. " matches")

    if #results > 0 then
        logger:d("applyFilter: sample results (first 3):")
        for i = 1, math.min(3, #results) do
            local result = results[i]
            local idx = result[1]
            local positions = result[2]
            local score = result[3]
            logger:d("  [" .. i .. "] idx=" .. idx .. ", score=" .. tostring(score) .. ", positions=" .. table.concat(positions, ","))
        end
    else
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

    logger:d("applyFilter: returning " .. #filtered .. " filtered choices")
    self._chooser:choices(filtered)
end

return M

