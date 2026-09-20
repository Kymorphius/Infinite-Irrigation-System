package.path = "Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/?.lua;"
	.. package.path

local function list(values)
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
	}
end

local function item(fullType, isFood)
	return {
		fullType = fullType,
		isFood = isFood,
		getFullType = function(self) return self.fullType end,
		isRotten = function() return false end,
		isCooked = function() return false end,
		isBurnt = function() return false end,
	}
end

local stored = {
	item("Base.TomatoSeed"),
	item("Base.Corn"),
	item("Base.Apple", true),
}
local container = { physicalCapacity = 0 }
function container:getType() return self.type or "fridge" end
function container:setType(value) self.type = value end
function container:getItems() return list(stored) end
function container:AddItems(fullType, count)
	local added = {}
	for _ = 1, count do
		local value = item(fullType, true)
		stored[#stored + 1] = value
		added[#added + 1] = value
	end
	return list(added)
end
function container:AddItem(value)
	stored[#stored + 1] = value
	return value
end
function container:Remove(target)
	for index, value in ipairs(stored) do
		if value == target then table.remove(stored, index) return end
	end
end
function container:setExplored() end

local modData = { magicFridge = true, magicFridgeNextHarvestHour = 100 }
local fluid = {
	amount = 2,
	getAmount = function(self) return self.amount end,
	getCapacity = function() return 10 end,
}
local square = {
	getX = function() return 10 end,
	getY = function() return 20 end,
	getZ = function() return 0 end,
	transmitRemoveItemFromSquare = function(self, object) self.removed = object end,
	RemoveTileObject = function(self, object) self.deleted = object end,
}
local object = {
	getName = function() return "MagicFridge" end,
	getModData = function() return modData end,
	getSquare = function() return square end,
	getContainer = function() return container end,
	getFluidContainer = function() return fluid end,
	addFluid = function(_, fluidType, amount)
		assert(fluidType == "Water")
		fluid.amount = fluid.amount + amount
	end,
	transmitModData = function(self) self.transmitted = true end,
}

local powerSyncs, powerRemovals, waterSyncs, waterRemovals = 0, 0, 0, 0
PowerPipe = {
	syncObjectSource = function(value) assert(value == object); powerSyncs = powerSyncs + 1 end,
	unregisterSourceAt = function(x, y, z)
		assert(x == 10 and y == 20 and z == 0)
		powerRemovals = powerRemovals + 1
	end,
}
WholeBuildingWater = {
	syncSourceObject = function(value) assert(value == object); waterSyncs = waterSyncs + 1 end,
	unregisterSource = function(value) assert(value == object); waterRemovals = waterRemovals + 1 end,
}
WaterPipeStorageCapacity = {
	setPhysicalCapacity = function(value, capacity)
		assert(value and capacity == 100)
		value.physicalCapacity = capacity
		return true
	end,
}
local preserved = 0
WaterPipeStorageFreshness = {
	preserveItem = function(value)
		if value.fullType == "Base.Apple" then preserved = preserved + 1 return true end
		return false
	end,
}

package.preload["WaterPipe/StorageCapacity"] = function() return WaterPipeStorageCapacity end
package.preload["WaterPipe/PowerPipe"] = function() return PowerPipe end
package.preload["WaterPipe/WholeBuildingWater"] = function() return WholeBuildingWater end
package.preload["WaterPipe/StorageFreshness"] = function() return WaterPipeStorageFreshness end
WaterPipeSprite = { supplyByPipeType = { lineOption = "infinite_irrigation_pipes_01_11" } }
package.preload["WaterPipe/PipeSprites"] = function() return WaterPipeSprite end

Events = nil
ContainerButtonIcons = { fridge = "fridge-icon" }
local globalFridgeSettings, globalTransmits = {}, 0
ModData = {
	getOrCreate = function(key)
		assert(key == "WaterPipesMagicFridgeSettings")
		return globalFridgeSettings
	end,
	transmit = function(key)
		assert(key == "WaterPipesMagicFridgeSettings")
		globalTransmits = globalTransmits + 1
	end,
}
FluidType = { Water = "Water" }
SandboxVars = { WaterPipes = {} }
isClient = function() return false end
isServer = function() return true end
getGameTime = function()
	return { getWorldAgeHours = function() return 100 end }
end
instanceof = function(value, className)
	return className == "Food" and value.isFood == true
end
farming_vegetableconf = {
	props = {
		Tomato = {
			vegetableName = "Base.Tomato", seedTypes = { "Base.TomatoSeed" },
			minVeg = 2, maxVeg = 4,
		},
		Corn = {
			vegetableName = "Base.Corn", seedTypes = { "Base.CornSeed", "Base.Corn" },
			minVeg = 2, maxVeg = 4,
		},
	},
}

local removedNotifications, addedNotifications = 0, 0
sendRemoveItemFromContainer = function(value)
	assert(value == container)
	removedNotifications = removedNotifications + 1
end
sendAddItemsToContainer = function(value)
	assert(value == container)
	addedNotifications = addedNotifications + 1
end

local carriedStored = {}
local carriedInventory = {
	getItems = function() return list(carriedStored) end,
	AddItem = function(_, value) carriedStored[#carriedStored + 1] = value return value end,
	Remove = function(_, target)
		for index, value in ipairs(carriedStored) do
			if value == target then table.remove(carriedStored, index) return end
		end
	end,
	setType = function(self, value) self.type = value end,
}
local carriedData = {}
local carriedItem = {
	getFullType = function() return "WaterPipes.MagicFridgePacked" end,
	getInventory = function() return carriedInventory end,
	getModData = function() return carriedData end,
	setTexture = function(self, value) self.texture = value end,
	setIcon = function(self, value) self.icon = value end,
}
instanceItem = function(fullType)
	if fullType == "WaterPipes.MagicFridgePacked" then return carriedItem end
	return { getTexture = function() return "texture:" .. fullType end }
end
local addedCarriedItem
sendAddItemToContainer = function(value, added)
	addedCarriedItem = added
end

local Fridge = require "WaterPipe/MagicFridge"
assert(Fridge.capacity == 1000000 and Fridge.defaultProduceLimit == 9
	and Fridge.getCycleHours() == 10 / 60,
	"the default seed-to-crop cycle should be ten minutes")
assert(#Fridge.variantOrder == 9 and Fridge.isItem(item("WaterPipes.MagicFridgeBlue")))
assert(Fridge.isItem(item("WaterPipes.MagicFridgeTrailer"))
	and ContainerButtonIcons.MagicFridge == "fridge-icon",
	"trailer items should remain loadable while the container uses the fridge icon")
assert(Fridge.getVariantForItem(item("WaterPipes.MagicFridgeMini")).south
	== "appliances_refrigeration_01_25")
assert(Fridge.register(object) and container.physicalCapacity == 100)
assert(modData.magicFridgeCycleHours == 10 / 60
	and math.abs(modData.magicFridgeNextHarvestHour - (100 + 10 / 60)) < 0.000001,
	"registering should schedule the configured ten-minute cycle")
assert(modData.magicFridgeCapacityVersion == 1)
assert(container:getType() == "MagicFridge")
assert(powerSyncs == 1 and waterSyncs == 1,
	"registration should enable the existing power and whole-building-water systems")
assert(fluid.amount == 10, "registration should expose a full native water source")
fluid.amount = 1
Fridge.onWaterAmountChange(object)
assert(fluid.amount == 10, "drinking should immediately refill the magic fridge")

SandboxVars.WaterPipes.MagicFridgeHarvestInterval = 3
Fridge.process()
assert(modData.magicFridgeCycleHours == 1 and modData.magicFridgeNextHarvestHour == 101,
	"changing the interval should restart the current cycle with the new duration")
SandboxVars.WaterPipes.MagicFridgeHarvestInterval = 1

local converted, produced = Fridge.processSeeds(object)
assert(converted == 2 and produced == 6,
	"each recognized seed should become the crop's average native yield")
local counts = {}
for _, value in ipairs(stored) do counts[value.fullType] = (counts[value.fullType] or 0) + 1 end
assert(counts["Base.TomatoSeed"] == 1 and counts["Base.Tomato"] == 3)
assert(counts["Base.Corn"] == 4,
	"seeds, including directly sowable crops, should be preserved by default")
assert(removedNotifications == 0 and addedNotifications == 2)

preserved = 0
assert(Fridge.preserveContents(object) == 1 and preserved == 1,
	"perishable contents should use the existing permanent-freshness behavior")

for index = #stored, 1, -1 do table.remove(stored, index) end
stored[#stored + 1] = item("Base.TomatoSeed")
stored[#stored + 1] = item("Base.Corn")
SandboxVars.WaterPipes.MagicFridgePreserveSeeds = false
converted, produced = Fridge.processSeeds(object)
counts = {}
for _, value in ipairs(stored) do counts[value.fullType] = (counts[value.fullType] or 0) + 1 end
assert(converted == 2 and produced == 6 and counts["Base.TomatoSeed"] == nil)
assert(counts["Base.Tomato"] == 3 and counts["Base.Corn"] == 3,
	"disabling the option should consume one recognized seed per cycle")
assert(removedNotifications == 2 and addedNotifications == 4)

for index = #stored, 1, -1 do table.remove(stored, index) end
stored[#stored + 1] = item("Base.TomatoSeed")
for _ = 1, 8 do stored[#stored + 1] = item("Base.Tomato", true) end
stored[#stored + 1] = item("Base.Corn")
SandboxVars.WaterPipes.MagicFridgePreserveSeeds = true
assert(Fridge.setObjectSettings(object, true, {
	Tomato = { enabled = true, produceLimit = 9 },
	Corn = { enabled = false, produceLimit = 9 },
}))
converted, produced = Fridge.processSeeds(object)
counts = {}
for _, value in ipairs(stored) do counts[value.fullType] = (counts[value.fullType] or 0) + 1 end
assert(converted == 1 and produced == 1 and counts["Base.Tomato"] == 9
	and counts["Base.Corn"] == 1,
	"per-crop settings should enforce an exact stock cap and disable selected crops")
assert(Fridge.processSeeds(object) == 0,
	"a fridge at its configured stock cap should stop producing")
assert(Fridge.setObjectSettings(object, false, modData.magicFridgeSettings))
table.remove(stored, 2)
assert(Fridge.processSeeds(object) == 0,
	"the fridge-wide production switch should pause every crop")
assert(Fridge.setObjectSettings(object, true, modData.magicFridgeSettings))

local remoteData = { magicFridge = true }
local remoteObject = {
	getName = function() return "MagicFridge" end,
	getModData = function() return remoteData end,
	getSquare = function() return square end,
	transmitModData = function(self) self.transmitted = true end,
}
Fridge.objects[remoteObject] = true
assert(Fridge.setAllObjectSettings(true, {
	Tomato = { enabled = true, produceLimit = 6 },
}) == 2)
assert(globalTransmits == 1 and globalFridgeSettings.revision == 1
	and modData.magicFridgeSettings.Tomato.produceLimit == 6
	and remoteData.magicFridgeSettings.Tomato.produceLimit == 6,
	"save-all should update every loaded fridge and persist one world-wide revision")
local laterData = { magicFridge = true }
local laterObject = {
	getName = function() return "MagicFridge" end,
	getModData = function() return laterData end,
	getSquare = function() return square end,
	transmitModData = function() end,
}
assert(Fridge.applyGlobalSettings(laterObject)
	and laterData.magicFridgeSettings.Tomato.produceLimit == 6,
	"a previously unloaded fridge should adopt the newest save-all profile when loaded")
assert(Fridge.setObjectSettings(object, true, {
	Tomato = { enabled = true, produceLimit = 9 },
}))
assert(not Fridge.applyGlobalSettings(object),
	"an individual save should remain until a newer save-all revision exists")

for index = #stored, 1, -1 do table.remove(stored, index) end
local preservedItem = item("Base.Apple", true)
stored[#stored + 1] = preservedItem
local playerStored = {}
local player = {
	getInventory = function()
		return { AddItem = function(_, value) playerStored[#playerStored + 1] = value end }
	end,
}
assert(Fridge.pickUp(object, player))
assert(playerStored[1] == carriedItem and carriedStored[1] == preservedItem,
	"pickup should preserve the original item object inside one carried fridge container")
assert(carriedInventory.type == "MagicFridge" and carriedInventory.physicalCapacity == 100)
assert(addedCarriedItem == carriedItem and carriedItem.texture == "texture:Base.Mov_WhiteFridge")
assert(carriedData.magicFridgeNextHarvestHour == modData.magicFridgeNextHarvestHour)
assert(carriedData.magicFridgeProductionEnabled == true
	and carriedData.magicFridgeSettings.Tomato.produceLimit == 9
	and carriedData.magicFridgeSettingsRevision == 1)
assert(square.removed == object and square.deleted == object)
assert(powerRemovals == 1 and waterRemovals == 1)
Fridge.moveContents(carriedInventory, container)
assert(stored[1] == preservedItem and #carriedStored == 0,
	"placing should be able to restore the exact same item object")

local builtObject = {
	name = nil,
	modData = {},
	fluid = {
		amount = 10,
		getAmount = function(self) return self.amount end,
		getCapacity = function() return 10 end,
	},
	getName = function(self) return self.name end,
	setName = function(self, value) self.name = value end,
	getModData = function(self) return self.modData end,
	getSquare = function(self) return self.square end,
	getContainer = function() return container end,
	getFluidContainer = function(self) return self.fluid end,
	addFluid = function(self, _, amount) self.fluid.amount = self.fluid.amount + amount end,
	removeAllContainers = function() end,
	setCanPassThrough = function() end,
	setBlockAllTheSquare = function() end,
	setCanBarricade = function() end,
	setIsDismantable = function() end,
	setIsThumpable = function() end,
	setUsesExternalWaterSource = function(self, value) self.externalWater = value end,
	setMaxHealth = function() end,
	setHealth = function() end,
	setSprite = function(self, value) self.sprite = value end,
}
local buildSquare = {
	AddSpecialObject = function(self, value) self.added = value end,
}
builtObject.square = buildSquare
local constructionSprite
IsoThumpable = {
	new = function(_, _, sprite)
		constructionSprite = sprite
		return builtObject
	end,
}
getCell = function() return {} end
getSprite = function(name) return { name = name } end
PowerPipe.syncObjectSource = function() end
WholeBuildingWater.syncSourceObject = function() end
assert(Fridge.createObject(buildSquare, true, "Blue") == builtObject)
assert(constructionSprite == WaterPipeSprite.supplyByPipeType.lineOption,
	"construction should initialize the native supply-fluid component")
assert(builtObject.sprite.name == "appliances_refrigeration_01_5"
	and builtObject.modData.magicFridgeVariant == "Blue"
	and builtObject.externalWater == false,
	"the placed source should retain the fridge appearance and use its own water")

local recipe = assert(io.open(
	"Contents/mods/WaterPipes-IrrigationSystems/42/media/scripts/waterPipes.txt", "rb"
)):read("*a")
assert(recipe:find("craftRecipe AskMagicFridge", 1, true))
assert(recipe:find("item 1 [Base.RippedSheets;Base.RippedSheetsDirty]", 1, true))
local _, recipeCount = recipe:gsub("craftRecipe AskMagicFridge", "")
local _, categoryCount = recipe:gsub("category = MagicFridge", "")
local _, moveableCount = recipe:gsub("ItemType = base:moveable", "")
local _, containerCount = recipe:gsub("ItemType = base:container", "")
local _, onCreateCount = recipe:gsub("OnCreate = MagicFridge.onCreateItem", "")
assert(not recipe:find("craftRecipe AskMagicFridgeTrailer", 1, true),
	"the obsolete trailer-fridge recipe should stay removed")
assert(recipeCount == 9 and categoryCount == 9
	and moveableCount == 10 and containerCount == 10 and onCreateCount == 10,
	"legacy items should remain compatible while only current recipes are craftable")
for _, id in ipairs(Fridge.variantOrder) do
	local variant = Fridge.variants[id]
	assert(recipe:find("item " .. variant.itemType:match("[^.]+$"), 1, true))
	assert(recipe:find("item " .. variant.legacyItemType:match("[^.]+$"), 1, true))
end

print("Magic Fridge tests passed")
