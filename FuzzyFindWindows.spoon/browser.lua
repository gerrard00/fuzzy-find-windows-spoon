local M = {}

local ax = require("hs.axuielement")
local logger = require("hs.logger").new("FuzzyFindWindows", "debug")

function M.isBrowserApp(app)
    if not app then return false end
    
    local bid = app:bundleID()
    
    return bid == "com.apple.Safari"
        or bid == "org.mozilla.firefox"
        or bid == "com.google.Chrome"
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

function M.getTabsForBrowser(win)
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
                    score = 0,
                })
            else
                logger:w("getTabsForBrowser: found tab button but title is empty")
            end
        end
    end
    
    return tabs
end

-- This function will be attached to the object as a method
function M.getTabsForWindow(self, win)
    local app = win:application()
    if not app then
        return {}
    end
    
    if not M.isBrowserApp(app) then
        return {}
    end
    
    return M.getTabsForBrowser(win)
end

-- This function will be attached to the object as a method
function M.clickTabByTitle(self, win, tabTitle)
    if not win or not tabTitle then
        logger:w("clickTabByTitle: missing win or tabTitle")
        return false
    end
    
    local axWin = ax.windowElement(win)
    if not axWin then
        logger:w("clickTabByTitle: could not get window element")
        return false
    end
    
    local tabButton = findTabButton(axWin, 1, 12)
    if not tabButton then
        logger:w("clickTabByTitle: could not find any tab button")
        return false
    end
    
    local tabGroup = tabButton:attributeValue("AXParent")
    if not tabGroup then
        logger:w("clickTabByTitle: could not find tab group")
        return false
    end
    
    local children = tabGroup:attributeValue("AXChildren") or {}
    for _, child in ipairs(children) do
        local childRole = child:attributeValue("AXRole")
        local subrole = child:attributeValue("AXSubrole")
        
        if childRole == "AXRadioButton" and subrole == "AXTabButton" then
            local title = child:attributeValue("AXDescription") or ""
            if title == "" then
                title = child:attributeValue("AXTitle") or ""
            end
            
            if title == tabTitle then
                -- Found the matching tab button, click it
                local success = child:performAction("AXPress")
                if success then
                    logger:d("clickTabByTitle: successfully clicked tab: " .. tabTitle)
                    return true
                else
                    logger:w("clickTabByTitle: failed to perform AXPress on tab: " .. tabTitle)
                    return false
                end
            end
        end
    end
    
    logger:w("clickTabByTitle: could not find tab with title: " .. tabTitle)
    return false
end

return M
