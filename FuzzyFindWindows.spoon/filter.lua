local M = {}

function M.showRebuildMessage(self)
    if not self._chooser then 
        local logger = require("hs.logger").new("FuzzyFindWindows", "debug")
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

return M


