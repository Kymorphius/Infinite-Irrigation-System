require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/Maps/ISWorldMap"

WaterPipeNetworksUI = {}
WaterPipeNetworksUI.window = nil
WaterPipeNetworksUI.textPanel = nil
WaterPipeNetworksUI.networkCombo = nil
WaterPipeNetworksUI.locateButton = nil
WaterPipeNetworksUI.networks = {}
WaterPipeNetworksUI.mapMarker = nil
WaterPipeNetworksUI.mapMarkersAPI = nil

local function isVerticalPipeType(pipeType)
    return type(pipeType) == "string"
        and (pipeType == "verticalOption" or pipeType:find("^vertical") ~= nil)
end

function WaterPipeNetworksUI.arePipesConnectedForDisplay(a, b)
    if not a or not b then return false end
    local dx = math.abs((a.x or 0) - (b.x or 0))
    local dy = math.abs((a.y or 0) - (b.y or 0))
    local dz = math.abs((a.z or 0) - (b.z or 0))
    if dz == 0 then return dx + dy == 1 end
    return dx == 0 and dy == 0 and dz == 1
        and isVerticalPipeType(a.pipeType)
        and isVerticalPipeType(b.pipeType)
end

function WaterPipeNetworksUI.refreshContent(panel)
    if not panel then
        print("ERROR: panel is nil in refreshContent")
        return
    end
    if type(panel.paginate) ~= "function" then
        print("ERROR: panel.paginate is not a function! Got:", type(panel.paginate))
        return
    end

    local resultText = ""
    local networks = WaterPipeNetworksUI.getPipeNetworks()
    WaterPipeNetworksUI.networks = networks

    for i, group in ipairs(networks) do
        local networkTitleColor = "<RGB:1,0.9,0.3>"
        resultText = resultText .. string.format(
            "%s[OK] %s #%d (%d %s)</RGB><LINE><LINE>",
            networkTitleColor,
            getText("IGUI_WaterPipe_Network"),
            i,
            #group,
            getText("IGUI_WaterPipe_Pipes")
        )

        for _, pipe in ipairs(group) do
            resultText = resultText .. string.format(
                "<RGB:0.6,1,0.6>    - [%d,%d,%d] | %s: %s</RGB><LINE>",
                pipe.x or 0,
                pipe.y or 0,
                pipe.z or 0,
                getText("IGUI_WaterPipe_Infinite"),
                getText("IGUI_WaterPipe_InfiniteYes")
            )
        end
        resultText = resultText .. "<LINE>"
    end

    panel.text = resultText
    panel:paginate()

    local combo = WaterPipeNetworksUI.networkCombo
    if combo then
        local previousSelection = math.max(1, tonumber(combo.selected) or 1)
        combo:clear()
        for i, group in ipairs(networks) do
            combo:addOptionWithData(string.format(
                "%s #%d · %d %s",
                getText("IGUI_WaterPipe_Network"),
                i,
                #group,
                getText("IGUI_WaterPipe_Pipes")
            ), i)
        end
        if #networks > 0 then combo.selected = math.min(previousSelection, #networks) end
    end
    if WaterPipeNetworksUI.locateButton then
        local mapAllowed = ISWorldMap and ISWorldMap.IsAllowed and ISWorldMap.IsAllowed()
        WaterPipeNetworksUI.locateButton:setEnable(#networks > 0 and mapAllowed == true)
    end
end

function WaterPipeNetworksUI.getNetworkMapTarget(group)
    if not group or #group == 0 then return nil end
    local minX, maxX, minY, maxY
    for _, pipe in ipairs(group) do
        local x, y = tonumber(pipe.x), tonumber(pipe.y)
        if x and y then
            minX = minX and math.min(minX, x) or x
            maxX = maxX and math.max(maxX, x) or x
            minY = minY and math.min(minY, y) or y
            maxY = maxY and math.max(maxY, y) or y
        end
    end
    if not minX then return nil end

    local span = math.max(maxX - minX + 1, maxY - minY + 1)
    local zoom = 18.0
    if span > 100 then
        zoom = 13.5
    elseif span > 50 then
        zoom = 15.0
    elseif span > 20 then
        zoom = 16.5
    end
    return {
        x = (minX + maxX) / 2,
        y = (minY + maxY) / 2,
        radius = math.max(3, math.ceil(span / 2) + 1),
        zoom = zoom,
    }
end

function WaterPipeNetworksUI.showNetworkOnMap(group, playerNum)
    local target = WaterPipeNetworksUI.getNetworkMapTarget(group)
    if not target or not ISWorldMap or not ISWorldMap.ShowWorldMap
        or not ISWorldMap.IsAllowed or not ISWorldMap.IsAllowed() then return false end

    playerNum = tonumber(playerNum) or 0
    ISWorldMap.ShowWorldMap(playerNum, target.x, target.y, target.zoom)
    local worldMap = ISWorldMap_instance
    local mapAPI = worldMap and worldMap.mapAPI
    local markersAPI = mapAPI and mapAPI.getMarkersAPI and mapAPI:getMarkersAPI() or nil
    if markersAPI then
        if WaterPipeNetworksUI.mapMarker and WaterPipeNetworksUI.mapMarkersAPI then
            pcall(function()
                WaterPipeNetworksUI.mapMarkersAPI:removeMarker(WaterPipeNetworksUI.mapMarker)
            end)
        end
        WaterPipeNetworksUI.mapMarker = markersAPI:addGridSquareMarker(
            math.floor(target.x + 0.5),
            math.floor(target.y + 0.5),
            target.radius,
            1.0, 0.72, 0.18, 0.9
        )
        WaterPipeNetworksUI.mapMarkersAPI = markersAPI
    end
    return true
end

function WaterPipeNetworksUI.onLocateNetwork()
    local combo = WaterPipeNetworksUI.networkCombo
    if not combo then return end
    local networkIndex = combo:getOptionData(combo.selected)
    local group = networkIndex and WaterPipeNetworksUI.networks[networkIndex] or nil
    local player = getPlayer and getPlayer() or nil
    local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
    WaterPipeNetworksUI.showNetworkOnMap(group, playerNum)
end

function WaterPipeNetworksUI.getPipeNetworks()
    local result = {}
    local pipes = WaterPipe.pipes or {}

    local function getKey(x, y, z)
        return string.format("%d_%d_%d", x, y, z)
    end

    local pipeByKey = {}
    local uniquePipes = {}
    for _, pipe in ipairs(pipes) do
        if pipe.x and pipe.y and pipe.z then
            pipe.infinite = true
            local key = getKey(pipe.x, pipe.y, pipe.z)
            if not pipeByKey[key] then
                pipeByKey[key] = pipe
                table.insert(uniquePipes, pipe)
            end
        end
    end

    table.sort(uniquePipes, function(a, b)
        if a.z ~= b.z then return a.z < b.z end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)

    local function findConnected(startPipe, visited)
        local group = {}
        local queue = { startPipe }
        local dirs = { {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1} }

        while #queue > 0 do
            local pipe = table.remove(queue)
            local key = getKey(pipe.x, pipe.y, pipe.z)
            if not visited[key] then
                visited[key] = true
                table.insert(group, pipe)
                for _, dir in ipairs(dirs) do
                    local nx, ny, nz = pipe.x + dir[1], pipe.y + dir[2], pipe.z + dir[3]
                    local nkey = getKey(nx, ny, nz)
                    local other = pipeByKey[nkey]
                    if other and not visited[nkey]
                            and WaterPipeNetworksUI.arePipesConnectedForDisplay(pipe, other) then
                        table.insert(queue, other)
                    end
                end
            end
        end

        return group
    end

    local visited = {}
    for _, pipe in ipairs(uniquePipes) do
        local key = getKey(pipe.x, pipe.y, pipe.z)
        if not visited[key] then
            local group = findConnected(pipe, visited)
            table.insert(result, group)
        end
    end

    return result
end

function WaterPipeNetworksUI.createWindow()
    local width, height = 600, 500
    local x = getCore():getScreenWidth() / 2 - width / 2
    local y = getCore():getScreenHeight() / 2 - height / 2

    local ui = ISCollapsableWindow:new(x, y, width, height)
    ui.title = getText("IGUI_WaterPipe_NetworksTitle")
    ui.resizable = true
    ui:setVisible(true)
    ui:addToUIManager()
    ui.pin = true

    local textPanel = ISRichTextPanel:new(10, 30, width - 20, height - 75)
    textPanel:initialise()
    textPanel.autosetheight = false
    textPanel:setAnchorRight(true)
    textPanel:setAnchorBottom(true)

    WaterPipeNetworksUI.textPanel = textPanel
    ui:addChild(textPanel)

    local controlsY = height - 35
    local combo = ISComboBox:new(10, controlsY, 280, 25, ui, nil)
    combo:initialise()
    combo:instantiate()
    combo:setAnchorTop(false)
    combo:setAnchorBottom(true)
    ui:addChild(combo)
    WaterPipeNetworksUI.networkCombo = combo

    local locateBtn = ISButton:new(300, controlsY, 120, 25,
        getText("IGUI_WaterPipe_MapLocate"), ui, WaterPipeNetworksUI.onLocateNetwork)
    locateBtn:initialise()
    locateBtn:instantiate()
    locateBtn:setAnchorTop(false)
    locateBtn:setAnchorBottom(true)
    locateBtn.borderColor = { r = 1, g = 0.72, b = 0.18, a = 0.35 }
    ui:addChild(locateBtn)
    WaterPipeNetworksUI.locateButton = locateBtn

    local refreshBtn = ISButton:new(width - 90, height - 35, 80, 25, getText("IGUI_WaterPipe_Refresh"), ui, function()
        WaterPipeNetworksUI.refreshContent(WaterPipeNetworksUI.textPanel)
    end)

    refreshBtn:initialise()
    refreshBtn:instantiate()
    refreshBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    ui:addChild(refreshBtn)

	WaterPipeNetworksUI.refreshContent(textPanel)

    WaterPipeNetworksUI.window = ui
end

function WaterPipeNetworksUI.toggleWindow()
    if WaterPipeNetworksUI.window and WaterPipeNetworksUI.window:getIsVisible() then
        WaterPipeNetworksUI.window:setVisible(false)
        WaterPipeNetworksUI.window:removeFromUIManager()
        WaterPipeNetworksUI.window = nil
        WaterPipeNetworksUI.textPanel = nil
        WaterPipeNetworksUI.networkCombo = nil
        WaterPipeNetworksUI.locateButton = nil
    else
        WaterPipeNetworksUI.createWindow()
    end
end
