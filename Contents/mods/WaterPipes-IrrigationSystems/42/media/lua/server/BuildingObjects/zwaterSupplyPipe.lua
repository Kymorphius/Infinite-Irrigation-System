require "WaterPipe/PipeSprites"
require "WaterPipe/PowerPipe"
require "WaterPipe/WholeBuildingWater"
require "WaterPipe/StorageCapacity"

WaterSupplyPipe = WaterSupplyPipe or {}

WaterSupplyPipe.objectName = "WaterSupplyPipe"
WaterSupplyPipe.disabledObjectName = "WaterDisabledPipe"
WaterSupplyPipe.storageType = "InfiniteIrrigationPipe"
WaterSupplyPipe.storageCapacity = WaterPipeStorageCapacity.logicalCapacity
WaterSupplyPipe.physicalStorageCapacity = 100
WaterSupplyPipe.storageCapacityVersion = 2

function WaterSupplyPipe.getStorage(object)
	if not object or not object.getContainer then return nil end
	return object:getContainer()
end

function WaterSupplyPipe.ensureStorage(object)
	if not object or not object:getSquare() then return nil end
	local container = WaterSupplyPipe.getStorage(object)
	local created = false
	if not container then
		if not ItemContainer or not ItemContainer.new or not object.setContainer then
			return nil
		end
		-- Build 42.12 exposes the three-argument constructor to Lua.  Capacity is
		-- assigned below, so the obsolete width/height constructor is unnecessary.
		container = ItemContainer.new(
			WaterSupplyPipe.storageType,
			object:getSquare(),
			object
		)
		if not container then return nil end
		object:setContainer(container)
		created = true
	end
	-- Build 42 hard-limits the Java ItemContainer field to 100. Initialize new
	-- storage once and migrate old saves once; routine farm work must not read or
	-- rewrite the physical field. The version marker also avoids false mismatches
	-- when another capacity mod wraps ItemContainer accessors in a different order.
	local modData = object.getModData and object:getModData() or nil
	local needsMigration = not modData
		or modData.infinitePipeStorageCapacityVersion
			~= WaterSupplyPipe.storageCapacityVersion
	if created or needsMigration then
		local migrated = WaterPipeStorageCapacity.setPhysicalCapacity(
			container, WaterSupplyPipe.physicalStorageCapacity
		)
		if migrated and modData then
			modData.infinitePipeStorageCapacityVersion
				= WaterSupplyPipe.storageCapacityVersion
		end
	end
	if container.setExplored then container:setExplored(true) end
	return container
end

function WaterSupplyPipe.hasStoredItems(object)
	local container = WaterSupplyPipe.getStorage(object)
	if not container or not container.getItems then return false end
	local items = container:getItems()
	return items and items.size and items:size() > 0 or false
end

local function moveStorageItems(sourceObject, targetObject)
	local source = WaterSupplyPipe.getStorage(sourceObject)
	local target = WaterSupplyPipe.ensureStorage(targetObject)
	if not source or source == target then return target ~= nil end
	if not target or not source.getItems or not source.Remove or not target.AddItem then
		return false
	end

	local items = source:getItems()
	if not items or not items.size or not items.get then return false end
	for i = items:size() - 1, 0, -1 do
		local item = items:get(i)
		source:Remove(item)
		target:AddItem(item)
	end
	return true
end

function WaterSupplyPipe.findObject(square)
	if not square or not square:getObjects() then return nil end
	for i = 0, square:getObjects():size() - 1 do
		local object = square:getObjects():get(i)
		local name = object and object:getName()
		if name == WaterSupplyPipe.objectName or name == WaterSupplyPipe.disabledObjectName then
			return object
		end
	end
	return nil
end

function WaterSupplyPipe.onPickUp(supplyObject, player)
	if not supplyObject or not player then return false end
	local square = supplyObject:getSquare()
	if not square or WaterSupplyPipe.findObject(square) ~= supplyObject then return false end
	if WaterSupplyPipe.hasStoredItems(supplyObject) then return false end

	PowerPipe.unregisterSourceAt(square:getX(), square:getY(), square:getZ())
	WholeBuildingWater.unregisterSource(supplyObject)
	WaterPipe.removePipeDataAt(square:getX(), square:getY(), square:getZ())
	square:transmitRemoveItemFromSquare(supplyObject)
	square:RemoveTileObject(supplyObject)

	if isServer() then
		player:sendObjectChange("addItemOfType", { type = "WaterPipes.WaterPipe", count = 1 })
	else
		player:getInventory():AddItem("WaterPipes.WaterPipe")
	end
	return true
end

local function copyModData(source, target)
	if not source or not target then return end
	for key, value in pairs(source) do
		target[key] = value
	end
end

-- Replace a placed irrigation object because vanilla appliance plumbing
-- requires an actual IsoThumpable source.  Merely changing modData on the old
-- IsoObject would make drinking work inconsistently and would never satisfy
-- FindExternalWaterSource().
function WaterSupplyPipe.getPlacedMode(object)
	if not object then return nil end
	local modData = object:getModData()
	if object:getName() == WaterSupplyPipe.objectName then return "supply" end
	if object:getName() == WaterSupplyPipe.disabledObjectName then return "off" end
	if modData and modData["supplyIrrigationPipe"] == true then return "both" end
	if object:getName() == "WaterPipe" then return "irrigation" end
	return nil
end

function WaterSupplyPipe.findAnyPipeObject(square)
	return WaterPipe.findPipeObject(square) or WaterSupplyPipe.findObject(square)
end

function WaterSupplyPipe.getModeAfterSupplyToggle(mode)
	if mode == "both" then return "irrigation" end
	if mode == "supply" then return "off" end
	if mode == "irrigation" then return "both" end
	if mode == "off" then return "supply" end
	return nil
end

function WaterSupplyPipe.getModeAfterIrrigationToggle(mode)
	if mode == "both" then return "supply" end
	if mode == "irrigation" then return "off" end
	if mode == "supply" then return "both" end
	if mode == "off" then return "irrigation" end
	return nil
end

function WaterSupplyPipe.isValidMode(mode)
	return mode == "irrigation" or mode == "supply"
		or mode == "both" or mode == "off"
end

local function newPlacedPipeObject(square, targetMode, pipeType, sourceModData)
	if not square or not WaterSupplyPipe.isValidMode(targetMode) then return nil end
	local dedicatedServer = isServer and isServer()
	pipeType = pipeType or "lineOption"
	local targetSpriteName, targetSprite
	if targetMode == "irrigation" or targetMode == "off" then
		targetSpriteName, targetSprite = WaterPipeSprite.getRegisteredFloorSprite(nil, pipeType)
	else
		targetSpriteName, targetSprite = WaterPipeSprite.getRegisteredSupplySprite(pipeType)
	end
	if not targetSpriteName or not targetSprite then return nil end
	sourceModData = sourceModData or {}
	local defaultFarmEnabled = targetMode == "irrigation" or targetMode == "both"
	if type(sourceModData.careEnabled) ~= "boolean" then
		sourceModData.careEnabled = defaultFarmEnabled
	end
	if type(sourceModData.fertilizeEnabled) ~= "boolean" then
		sourceModData.fertilizeEnabled = defaultFarmEnabled
	end
	if type(sourceModData.cleanupEnabled) ~= "boolean" then
		sourceModData.cleanupEnabled = false
	end
	if type(sourceModData.cleanupShrunkFarmArea) ~= "boolean" then
		sourceModData.cleanupShrunkFarmArea = false
	end
	if type(sourceModData.autoSowEnabled) ~= "boolean" then
		sourceModData.autoSowEnabled = true
	end
	if type(sourceModData.autoHarvestEnabled) ~= "boolean" then
		sourceModData.autoHarvestEnabled = true
	end
	if type(sourceModData.autoFarmSettings) ~= "table" then
		sourceModData.autoFarmSettings = {}
	end
	if targetMode ~= "supply" and targetMode ~= "both" then
		sourceModData.wholeBuildingWater = nil
	end

	local newObject
	if targetMode == "supply" or targetMode == "both" then
		newObject = IsoThumpable.new(getCell(), square, targetSpriteName, false, {})
		if not newObject then return nil end
		newObject:setName(targetMode == "both" and "WaterPipe" or WaterSupplyPipe.objectName)
		newObject:setCanPassThrough(true)
		newObject:setBlockAllTheSquare(false)
		newObject:setCanBarricade(false)
		newObject:setIsDismantable(false)
		newObject:setIsThumpable(false)
		newObject:setUsesExternalWaterSource(false)
		newObject:setMaxHealth(100)
		newObject:setHealth(100)
		newObject:setBreakSound("BreakObject")
		copyModData(sourceModData, newObject:getModData())
		newObject:getModData()["waterSupplyPipe"] = true
		newObject:getModData()["supplyIrrigationPipe"] = targetMode == "both" and true or nil
		newObject:getModData()["pipeDisabled"] = nil
		newObject:getModData()["canBeWaterPiped"] = false
		newObject:getModData()["pipeType"] = pipeType
		newObject:getModData()["infinite"] = true
	else -- irrigation-only or fully disabled
		if not dedicatedServer and WaterPipeSprite.groundLayerEnabled == false then
			targetSpriteName = WaterPipeSprite.textureByPipeType[pipeType]
				or WaterPipeSprite.textureByPipeType.lineOption
		end
		newObject = IsoObject.new(
			square,
			targetSpriteName,
			targetMode == "irrigation" and "WaterPipe" or WaterSupplyPipe.disabledObjectName
		)
		if not newObject then return nil end
		copyModData(sourceModData, newObject:getModData())
		newObject:getModData()["waterSupplyPipe"] = nil
		newObject:getModData()["supplyIrrigationPipe"] = nil
		newObject:getModData()["canBeWaterPiped"] = nil
		newObject:getModData()["pipeDisabled"] = targetMode == "off" and true or nil
		newObject:getModData()["pipeType"] = pipeType
		newObject:getModData()["infinite"] = true
	end
	-- IsoThumpable must be constructed from the registered supply tile so the
	-- native fluid components are initialized.  Before adding it to the square,
	-- replace only its display sprite when the single-player local option is off.
	if (targetMode == "supply" or targetMode == "both")
		and not dedicatedServer and WaterPipeSprite.groundLayerEnabled == false then
		local _, directSprite = WaterPipeSprite.getDirectSprite(pipeType, true)
		if directSprite then newObject:setSprite(directSprite) end
	end
	WaterSupplyPipe.ensureStorage(newObject)
	return newObject
end

local function addPlacedPipeObject(square, object, targetMode)
	if targetMode == "supply" or targetMode == "both" then
		square:AddSpecialObject(object)
	else
		square:AddTileObject(object)
	end

	-- Every placed pipe remains in one lightweight registry. The coverage map
	-- independently indexes only the services enabled on that object.
	WaterPipe.loadPipe(object)
	PowerPipe.syncObjectSource(object)
	WholeBuildingWater.syncSourceObject(object)
	return object
end

function WaterSupplyPipe.createPlacedPipe(square, targetMode, pipeType, sourceModData)
	local newObject = newPlacedPipeObject(
		square, targetMode, pipeType or "lineOption", sourceModData
	)
	if not newObject then return nil end
	return addPlacedPipeObject(square, newObject, targetMode)
end

function WaterSupplyPipe.togglePlacedPipe(square, targetMode)
	if not square or not WaterSupplyPipe.isValidMode(targetMode) then return false end

	local oldObject = WaterSupplyPipe.findAnyPipeObject(square)
	if not oldObject then return false end
	local oldModData = oldObject:getModData()
	local oldMode = WaterSupplyPipe.getPlacedMode(oldObject)
	if oldMode == targetMode then return false end
	local oldFarmDefault = oldMode == "irrigation" or oldMode == "both"
	if type(oldModData.careEnabled) ~= "boolean" then
		oldModData.careEnabled = oldFarmDefault
	end
	if type(oldModData.fertilizeEnabled) ~= "boolean" then
		oldModData.fertilizeEnabled = oldFarmDefault
	end
	if type(oldModData.cleanupEnabled) ~= "boolean" then
		oldModData.cleanupEnabled = false
	end
	if type(oldModData.cleanupShrunkFarmArea) ~= "boolean" then
		oldModData.cleanupShrunkFarmArea = false
	end
	if targetMode ~= "supply" and targetMode ~= "both" then
		oldModData.wholeBuildingWater = nil
	end

	local pipeType = (oldModData and oldModData["pipeType"]) or "lineOption"
	-- Build the replacement before removing the old pipe so a missing sprite or
	-- constructor failure cannot make the placed pipe disappear.
	local newObject = newPlacedPipeObject(square, targetMode, pipeType, oldModData)
	if not newObject then return false end
	if not moveStorageItems(oldObject, newObject) then return false end

	square:transmitRemoveItemFromSquare(oldObject)
	square:RemoveTileObject(oldObject)
	addPlacedPipeObject(square, newObject, targetMode)
	newObject:transmitCompleteItemToClients()
	if square.RecalcAllWithNeighbours then
		square:RecalcAllWithNeighbours(true)
	end
	return true, newObject
end

-- Auto-tilling has its own coverage queue and no longer changes irrigation.
function WaterSupplyPipe.setPlacedAutoTill(square, requestedMode)
	if not square or (requestedMode ~= "global" and requestedMode ~= "enabled"
		and requestedMode ~= "disabled") then return false end

	local object = WaterSupplyPipe.findAnyPipeObject(square)
	if not object then return false end

	return WaterPipe.setObjectAutoTill(object, requestedMode)
end
