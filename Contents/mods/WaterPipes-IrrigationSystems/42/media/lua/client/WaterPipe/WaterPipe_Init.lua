require "WaterPipe/PipeSprites"
require "WaterPipe/WholeBuildingWater"
require "WaterPipe/FarmingInfoGuard"

if not WaterPipe then WaterPipe = {} end
if not WaterPipe.pipes then WaterPipe.pipes = {} end

local function isWaterPipeObject(obj)
    if not obj or not instanceof(obj, "IsoObject") then return false end
    local name = obj:getName()
    if name == "WaterPipe" or name == "WaterSupplyPipe"
        or name == "WaterDisabledPipe" then return true end

    local modData = obj:getModData()
    if modData and modData["infinite"] and modData["pipeType"] then return true end

    local sprite = obj:getSprite()
    local spriteName = sprite and sprite:getName()
    return spriteName and string.match(spriteName, "WaterPipe") ~= nil
end

local function findPipeIndex(x, y, z)
    for index, pipe in ipairs(WaterPipe.pipes) do
        if pipe.x == x and pipe.y == y and pipe.z == z then
            return index
        end
    end
    return nil
end

local function onWaterPipeAdded(obj)
    if not isWaterPipeObject(obj) then return end
	if WaterPipeSprite.groundLayerEnabled then
		WaterPipeSprite.applyFloorSprite(obj)
	end
	WaterPipeSprite.registerDisplayObject(obj)
	-- Supply-only and disabled pipes need display tracking, but must not enter
	-- the irrigation coverage registry.
	if obj:getName() ~= "WaterPipe" then return end

    local square = obj:getSquare()
    if not square then return end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    local index = findPipeIndex(x, y, z)
    local pipe = index and WaterPipe.pipes[index] or {}

    pipe.x = x
    pipe.y = y
    pipe.z = z
    pipe.pipeType = obj:getModData()["pipeType"]
    pipe.infinite = true

    if not index then
        table.insert(WaterPipe.pipes, pipe)
    end
end

local function onWaterPipeRemoved(obj)
    if not isWaterPipeObject(obj) then return end
	WaterPipeSprite.unregisterDisplayObject(obj)
	if obj:getName() ~= "WaterPipe" then return end

    local square = obj:getSquare()
    if not square then return end

    local index = findPipeIndex(square:getX(), square:getY(), square:getZ())
    if index then
        table.remove(WaterPipe.pipes, index)
    end
end

-- Saved objects do not reliably emit OnObjectAdded when their chunk is loaded.
-- Register pipes from the square-load event so the persisted local display
-- preference is applied after every restart and whenever the player returns to
-- a previously unloaded area.
local function onGridSquareLoaded(square)
	WaterPipeSprite.registerSquareObjects(square)
end

Events.OnObjectAdded.Add(onWaterPipeAdded)
Events.OnObjectAboutToBeRemoved.Add(onWaterPipeRemoved)
Events.LoadGridsquare.Add(onGridSquareLoaded)
