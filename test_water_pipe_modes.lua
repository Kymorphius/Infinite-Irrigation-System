package.path = "Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/shared/?.lua;" .. package.path

WholeBuildingWater = {
	unregisterSource = function() end,
	syncSourceObject = function() end,
}
package.preload["WaterPipe/WholeBuildingWater"] = function() return WholeBuildingWater end

local function objectList(items)
	return {
		size = function() return #items end,
		get = function(_, index) return items[index + 1] end,
	}
end

local objects = {}
local removedObjects = 0
local recalculations = 0
local square = {
	getX = function() return 10 end,
	getY = function() return 20 end,
	getZ = function() return 1 end,
	getObjects = function() return objectList(objects) end,
	transmitRemoveItemFromSquare = function(_, object)
		assert(object == objects[1])
		removedObjects = removedObjects + 1
	end,
	RemoveTileObject = function(_, object)
		assert(object == objects[1])
		table.remove(objects, 1)
	end,
	AddSpecialObject = function(_, object) table.insert(objects, object) end,
	AddTileObject = function(_, object) table.insert(objects, object) end,
	RecalcAllWithNeighbours = function(_, value)
		assert(value == true)
		recalculations = recalculations + 1
	end,
}

local function newObject(name, modData, spriteName)
	local object = {
		name = name,
		modData = modData or {},
		spriteName = spriteName,
		square = square,
	}
	function object:getName() return self.name end
	function object:setName(value) self.name = value end
	function object:getModData() return self.modData end
	function object:getSquare() return self.square end
	function object:getContainer() return self.container end
	function object:setContainer(value) self.container = value end
	function object:setCanPassThrough(value) self.canPassThrough = value end
	function object:setBlockAllTheSquare(value) self.blockAllTheSquare = value end
	function object:setCanBarricade(value) self.canBarricade = value end
	function object:setIsDismantable(value) self.dismantable = value end
	function object:setIsThumpable(value) self.thumpable = value end
	function object:setUsesExternalWaterSource(value) self.usesExternalWaterSource = value end
	function object:setMaxHealth(value) self.maxHealth = value end
	function object:setHealth(value) self.health = value end
	function object:setBreakSound(value) self.breakSound = value end
	function object:transmitCompleteItemToClients() self.transmitted = true end
	return object
end

ItemContainer = {
	new = function(containerType, targetSquare, parent)
		local storedItems = {}
		local container = {
			type = containerType,
			square = targetSquare,
			parent = parent,
		}
		function container:getItems() return objectList(storedItems) end
		function container:AddItem(item)
			table.insert(storedItems, item)
			item.container = self
			return item
		end
		function container:Remove(item)
			for i = #storedItems, 1, -1 do
				if storedItems[i] == item then table.remove(storedItems, i) break end
			end
			if item.container == self then item.container = nil end
		end
		function container:setCapacity(value)
			self.capacityWrites = (self.capacityWrites or 0) + 1
			self.capacity = value
		end
		function container:getCapacity() return self.capacity end
		function container:setExplored(value) self.explored = value end
		return container
	end,
}

local irrigationRegistrations = 0
local irrigationRemovals = 0
WaterPipe = {
	findPipeObject = function(targetSquare)
		for _, object in ipairs(objects) do
			if targetSquare == square and object:getName() == "WaterPipe" then return object end
		end
		return nil
	end,
	loadPipe = function(object)
		assert(object:getName() == "WaterPipe"
			or object:getName() == "WaterSupplyPipe"
			or object:getName() == "WaterDisabledPipe")
		irrigationRegistrations = irrigationRegistrations + 1
	end,
	removePipeDataAt = function(x, y, z)
		assert(x == 10 and y == 20 and z == 1)
		irrigationRemovals = irrigationRemovals + 1
	end,
	setObjectAutoTill = function(object, mode)
		assert(object and object:getSquare() == square)
		local override = nil
		if mode == "enabled" then override = true end
		if mode == "disabled" then override = false end
		object:getModData().autoTillOverride = override
		return true
	end,
	getGlobalAutoTillEnabled = function() return false end,
}

getCell = function() return "cell" end
getSprite = function(name)
	if name == "infinite_irrigation_pipes_01_14"
		or name == "infinite_irrigation_pipes_01_3"
		or name == "infinite_irrigation_pipes_01_25"
		or name == "infinite_irrigation_pipes_01_29" then
		return { getName = function() return name end }
	end
	return nil
end

IsoThumpable = {
	new = function(cell, targetSquare, spriteName)
		assert(cell == "cell" and targetSquare == square)
		assert(spriteName == "infinite_irrigation_pipes_01_14"
			or spriteName == "infinite_irrigation_pipes_01_29")
		return newObject(nil, {}, spriteName)
	end,
}
IsoObject = {
	new = function(targetSquare, spriteName, name)
		assert(targetSquare == square and (spriteName == "infinite_irrigation_pipes_01_3"
			or spriteName == "infinite_irrigation_pipes_01_25"))
		assert(name == "WaterPipe" or name == "WaterDisabledPipe")
		return newObject(name, {}, spriteName)
	end,
}

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/BuildingObjects/zwaterSupplyPipe.lua")

local powerSynchronizations = 0
PowerPipe.syncObjectSource = function(object)
	assert(object:getModData().powerSupplyPipe == true,
		"mode replacement must preserve the independent power switch")
	powerSynchronizations = powerSynchronizations + 1
end

assert(WaterSupplyPipe.getModeAfterSupplyToggle("irrigation") == "both")
assert(WaterSupplyPipe.getModeAfterSupplyToggle("both") == "irrigation")
assert(WaterSupplyPipe.getModeAfterSupplyToggle("supply") == "off")
assert(WaterSupplyPipe.getModeAfterSupplyToggle("off") == "supply")
assert(WaterSupplyPipe.getModeAfterIrrigationToggle("irrigation") == "off")
assert(WaterSupplyPipe.getModeAfterIrrigationToggle("off") == "irrigation")
assert(WaterSupplyPipe.getModeAfterIrrigationToggle("supply") == "both")
assert(WaterSupplyPipe.getModeAfterIrrigationToggle("both") == "supply")

local legacy = newObject("WaterPipe", {}, "infinite_irrigation_pipes_01_3")
legacy:setContainer(ItemContainer.new("InfiniteIrrigationPipe", square, legacy))
legacy:getContainer().capacity = 50
legacy:getContainer().capacityWrites = 0
assert(WaterSupplyPipe.ensureStorage(legacy) == legacy:getContainer()
	and legacy:getContainer().capacity == 100
	and legacy:getContainer().capacityWrites == 1
	and legacy:getModData().infinitePipeStorageCapacityVersion == 2,
	"an existing pipe without a version marker must migrate exactly once")
WaterSupplyPipe.ensureStorage(legacy)
assert(legacy:getContainer().capacityWrites == 1,
	"a migrated legacy pipe must skip later physical-capacity maintenance")

local original = newObject("WaterPipe", {
	pipeType = "neOption",
	infinite = true,
	powerSupplyPipe = true,
	irrigationRange = 7,
	autoTillOverride = false,
	careEnabled = true,
	fertilizeEnabled = false,
	cleanupEnabled = true,
	cleanupShrunkFarmArea = true,
	autoSowEnabled = true,
	autoHarvestEnabled = true,
	autoFarmSettings = {
		Carrots = { enabled = true, produceLimit = 40, keepSeeds = true, seedLimit = 12 },
	},
	wholeBuildingWater = true,
	waterPipeOwner = 42,
	otherModValue = "preserved",
}, "infinite_irrigation_pipes_01_3")
local storedSeed = { type = "Base.CarrotSeed" }
local originalStorage = WaterSupplyPipe.ensureStorage(original)
assert(WaterSupplyPipe.ensureStorage(original) == originalStorage
	and originalStorage.capacityWrites == 1
	and original:getModData().infinitePipeStorageCapacityVersion == 2,
	"repeated farm access must not rewrite the physical container capacity")
originalStorage:AddItem(storedSeed)
table.insert(objects, original)
assert(WaterSupplyPipe.getPlacedMode(original) == "irrigation")

local changed, hybrid = WaterSupplyPipe.togglePlacedPipe(square, "both")
assert(changed and #objects == 1 and objects[1] == hybrid)
assert(WaterSupplyPipe.getPlacedMode(hybrid) == "both"
	and hybrid:getName() == "WaterPipe",
	"enabling supply must create the combined mode")
assert(hybrid:getModData().wholeBuildingWater == true,
	"a supply-preserving mode change must keep whole-building water enabled")
assert(hybrid.spriteName == "infinite_irrigation_pipes_01_14"
	and hybrid:getModData().canBeWaterPiped == false
	and hybrid:getModData().otherModValue == "preserved",
	"combined mode must use the native clean-water sprite and preserve mod data")
assert(hybrid.canPassThrough == true and hybrid.blockAllTheSquare == false
	and hybrid.thumpable == false and hybrid.transmitted,
	"the native source object must remain a nonblocking floor object")
assert(hybrid:getContainer():getItems():size() == 1
	and hybrid:getContainer():getItems():get(0) == storedSeed
	and storedSeed.container == hybrid:getContainer()
	and hybrid:getContainer().capacity == 100,
	"mode replacement must move storage while keeping its physical capacity valid")

changed = WaterSupplyPipe.togglePlacedPipe(square, "supply")
local supplyOnly = objects[1]
assert(changed and WaterSupplyPipe.getPlacedMode(supplyOnly) == "supply"
	and supplyOnly:getName() == "WaterSupplyPipe",
	"disabling irrigation must enter supply-only mode")
assert(supplyOnly:getModData().supplyIrrigationPipe == nil
	and irrigationRemovals == 0,
	"supply-only mode must remain registered for independent farm services")
assert(WaterSupplyPipe.hasStoredItems(supplyOnly)
	and not WaterSupplyPipe.onPickUp(supplyOnly, {}),
	"a non-empty pipe must be rejected by the final server-side pickup path")
assert(objects[1] == supplyOnly,
	"rejected pickup must leave the pipe and its storage in the world")

changed = WaterSupplyPipe.togglePlacedPipe(square, "off")
local disabled = objects[1]
assert(changed and WaterSupplyPipe.getPlacedMode(disabled) == "off"
	and disabled:getName() == "WaterDisabledPipe",
	"disabling both functions must keep a discoverable plain floor pipe")
assert(disabled:getModData().waterSupplyPipe == nil
	and disabled:getModData().pipeDisabled == true
	and disabled:getModData().wholeBuildingWater == nil
	and irrigationRemovals == 0,
	"fully disabled mode must have neither native water nor irrigation registration")

changed = WaterSupplyPipe.togglePlacedPipe(square, "irrigation")
local irrigationOnly = objects[1]
assert(changed and WaterSupplyPipe.getPlacedMode(irrigationOnly) == "irrigation")
assert(irrigationOnly.spriteName == "infinite_irrigation_pipes_01_3"
	and irrigationOnly:getModData().waterSupplyPipe == nil
	and irrigationOnly:getModData().pipeType == "neOption",
	"disabling supply must restore the original irrigation shape and properties")
assert(irrigationRegistrations == 4 and removedObjects == 4 and recalculations == 4,
	"every mode replacement must synchronize the unified service registration")
assert(powerSynchronizations == 4 and irrigationOnly:getModData().powerSupplyPipe == true,
	"water and irrigation mode switches must not interrupt an enabled power source")
assert(irrigationOnly:getModData().irrigationRange == 7,
	"water and irrigation mode switches must preserve the pipe-specific irrigation range")
assert(irrigationOnly:getModData().autoTillOverride == false,
	"water and irrigation mode switches must preserve a disabled auto-till override")
assert(irrigationOnly:getModData().careEnabled == true
	and irrigationOnly:getModData().fertilizeEnabled == false
	and irrigationOnly:getModData().cleanupEnabled == true
	and irrigationOnly:getModData().cleanupShrunkFarmArea == true
	and irrigationOnly:getModData().autoSowEnabled == true
	and irrigationOnly:getModData().autoHarvestEnabled == true
	and irrigationOnly:getModData().autoFarmSettings.Carrots.produceLimit == 40,
	"mode switches must preserve all independent area-service switches")
assert(irrigationOnly:getModData().waterPipeOwner == 42,
	"water and irrigation mode switches must preserve the original pipe owner")
assert(irrigationOnly:getContainer():getItems():size() == 1
	and irrigationOnly:getContainer():getItems():get(0) == storedSeed,
	"stored items must survive repeated replacement in both directions")
assert(not WaterSupplyPipe.togglePlacedPipe(square, "irrigation"),
	"selecting the active mode should not replace the object again")
assert(not WaterSupplyPipe.togglePlacedPipe(square, "invalid"),
	"invalid mode names must be rejected")

changed = WaterSupplyPipe.togglePlacedPipe(square, "supply")
local pausedFarmPipe = objects[1]
assert(changed and WaterSupplyPipe.getPlacedMode(pausedFarmPipe) == "supply")
assert(WaterSupplyPipe.setPlacedAutoTill(square, "enabled"),
	"explicitly enabling auto-till should work without irrigation")
local resumedFarmPipe = objects[1]
assert(WaterSupplyPipe.getPlacedMode(resumedFarmPipe) == "supply"
	and resumedFarmPipe:getModData().autoTillOverride == true,
	"a supply-only pipe must stay supply-only when auto-till is enabled")

local supplyOnlyWithPreference = resumedFarmPipe
assert(WaterSupplyPipe.setPlacedAutoTill(square, "disabled")
	and objects[1] == supplyOnlyWithPreference
	and objects[1]:getModData().autoTillOverride == false,
	"changing auto-till must leave every other pipe feature untouched")

objects = {
	newObject("WaterPipe", {
		pipeType = "verticalWestOption",
		infinite = true,
		powerSupplyPipe = true,
	}, "infinite_irrigation_pipes_01_25"),
}
changed = WaterSupplyPipe.togglePlacedPipe(square, "both")
local verticalHybrid = objects[1]
assert(changed and verticalHybrid.spriteName == "infinite_irrigation_pipes_01_29"
	and verticalHybrid:getModData().pipeType == "verticalWestOption",
	"enabling water supply must preserve the vertical riser's direction")
changed = WaterSupplyPipe.togglePlacedPipe(square, "irrigation")
assert(changed and objects[1].spriteName == "infinite_irrigation_pipes_01_25"
	and objects[1]:getModData().pipeType == "verticalWestOption",
	"disabling water supply must restore the directional vertical irrigation sprite")

print("PASS test_water_pipe_modes.lua")
