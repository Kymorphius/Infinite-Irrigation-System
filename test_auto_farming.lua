local function objectList(items)
	return {
		size = function() return #items end,
		get = function(_, index) return items[index + 1] end,
	}
end

local storedItems = {}
SandboxVars = { WaterPipes = { EnableAutoFarming = true } }
local function newItem(fullType)
	return { getFullType = function() return fullType end }
end

local container = {}
function container:getItems() return objectList(storedItems) end
function container:AddItems(fullType, count)
	local added = {}
	for _ = 1, count do
		local item = newItem(fullType)
		table.insert(storedItems, item)
		table.insert(added, item)
	end
	return objectList(added)
end
function container:Remove(item)
	for i = #storedItems, 1, -1 do
		if storedItems[i] == item then table.remove(storedItems, i) return end
	end
end

for _ = 1, 3 do table.insert(storedItems, newItem("Base.TestSeed")) end
for _ = 1, 3 do table.insert(storedItems, newItem("Base.TestProduce")) end

-- Build 42.12 requires an ItemTag enum for Food:hasTag().  Keep an unrelated
-- food item in the pipe to ensure inventory scans never use the obsolete string.
ItemTag = { IS_CUTTING = {} }
local ordinaryFood = newItem("Base.Potato")
ordinaryFood._isFood = true
function ordinaryFood:isRotten() return false end
function ordinaryFood:isCooked() return false end
function ordinaryFood:isBurnt() return false end
function ordinaryFood:hasTag(tag)
	assert(tag == ItemTag.IS_CUTTING, "Food:hasTag must receive the Build 42 ItemTag enum")
	return false
end
function ordinaryFood:isFresh() return true end
function ordinaryFood:getBaseHunger() return -0.2 end
function ordinaryFood:getHungerChange() return -0.2 end
table.insert(storedItems, ordinaryFood)
instanceof = function(item, className)
	return className == "Food" and item._isFood == true
end

local pipeObject = {
	getContainer = function() return container end,
}
local pipeSquare = {
	getObjects = function() return objectList({ pipeObject }) end,
}

WaterPipe = {
	irrigationRangeSizes = { 1, 3, 5, 7, 9, 11, 15 },
	pipeByKey = {},
	getPipeKey = function(x, y, z) return x .. "," .. y .. "," .. z end,
	getPipeIrrigationRadius = function() return 1 end,
	findAnyServicePipeObject = function(square)
		return square == pipeSquare and pipeObject or nil
	end,
	isPipeAutoTillEnabled = function() return true end,
}
local retillCoordinates = nil
WaterPipe.tryAutoTillPosition = function(x, y, z)
	retillCoordinates = { x = x, y = y, z = z }
	return false
end
local pipe = {
	x = 10, y = 20, z = 0, owner = 0,
	autoSowEnabled = true,
	autoHarvestEnabled = true,
	autoFarmSettings = {
		TestCrop = {
			enabled = true,
			produceLimit = 5,
			keepSeeds = true,
			seedLimit = 4,
		},
	},
}
WaterPipe.pipeByKey[WaterPipe.getPipeKey(10, 20, 0)] = pipe

WaterSupplyPipe = {
	ensureStorage = function(object)
		return object == pipeObject and container or nil
	end,
}

getCell = function()
	return {
		getGridSquare = function(_, x, y, z)
			if x == 10 and y == 20 and z == 0 then return pipeSquare end
		end,
	}
end
isClient = function() return false end
isServer = function() return false end
Perks = { Farming = "Farming" }
local xpGained = 0
local owner = { getPerkLevel = function() return 3 end }
getSpecificPlayer = function(index) return index == 0 and owner or nil end
sendAddItemsToContainer = function() end
sendRemoveItemFromContainer = function() end
getVegetablesNumber = function() return 7 end

farming_vegetableconf = {
	props = {
		TestCrop = {
			vegetableName = "Base.TestProduce",
			seedName = "Base.TestSeed",
			seedTypes = { "Base.TestSeed" },
			minVeg = 1, maxVeg = 1, minVegAutorized = 1, maxVegAutorized = 1,
			seedPerVeg = 0.5,
		},
	},
	getSpriteName = function() return "crop" end,
}
SFarmingSystem = {
	instance = {
		gainXp = function(_, player)
			assert(player == owner)
			xpGained = xpGained + 1
		end,
		removePlant = function(_, plant)
			-- Match Build 42: removing the harvested server object invalidates its
			-- coordinates before the mod begins its next-cycle work.
			plant.x, plant.y, plant.z = nil, nil, nil
		end,
	},
}

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/WaterPipe/AutoFarming.lua")

local defaultSetting = WaterPipeAutoFarming.getCropSetting(
	{ autoFarmSettings = {} }, "TestCrop"
)
assert(defaultSetting.produceLimit == 9 and defaultSetting.seedLimit == 9,
	"new or previously unset crop limits should default to nine")

local plow = { x = 11, y = 20, z = 0, state = "plow" }
function plow:seed(cropType, skill)
	assert(cropType == "TestCrop" and skill == 3)
	self.typeOfSeed = cropType
	self.state = "seeded"
end
function plow:saveData() self.saved = true end

WaterPipeAutoFarming.beginCycle()
assert(WaterPipeAutoFarming.processPlant(plow), "a covered furrow should be auto-sown")
assert(plow.owner == 0 and plow.saved, "auto-sown crops must inherit the pipe owner")

local harvest = {
	x = 11, y = 20, z = 0,
	typeOfSeed = "TestCrop",
	state = "seeded",
	hasVegetable = true,
	hasSeed = true,
	owner = 0,
}
function harvest:canHarvest() return true end
function harvest:harvestThis() self.state = "harvested" end
function harvest:getSquare() return pipeSquare end

assert(WaterPipeAutoFarming.processPlant(harvest), "a covered ripe crop should be auto-harvested")
assert(harvest.state == "harvested" and xpGained == 1)
assert(retillCoordinates and retillCoordinates.x == 11 and retillCoordinates.y == 20
	and retillCoordinates.z == 0,
	"post-harvest work must use coordinates saved before Build 42 removes the plant")

local counts = {}
for _, item in ipairs(storedItems) do
	local fullType = item:getFullType()
	counts[fullType] = (counts[fullType] or 0) + 1
end
assert(counts["Base.TestProduce"] == 10,
	"a harvest below target must retain its full batch even when it crosses the target")
assert(counts["Base.TestSeed"] == 5,
	"seed restocking must retain the full harvested batch instead of trimming overflow")

local stockedHarvest = {
	x = 11, y = 20, z = 0,
	typeOfSeed = "TestCrop", state = "seeded",
	hasVegetable = true, hasSeed = true, owner = 0,
}
function stockedHarvest:canHarvest() return true end
function stockedHarvest:harvestThis() self.state = "harvested" end
function stockedHarvest:getSquare() return pipeSquare end
assert(not WaterPipeAutoFarming.processPlant(stockedHarvest)
	and stockedHarvest.state == "seeded" and xpGained == 1,
	"a ripe crop must remain available when both stock targets are already satisfied")

local disabledPipe = {
	x = 10, y = 20, z = 0, owner = 0,
	autoSowEnabled = true,
	autoFarmSettings = {
		TestCrop = { enabled = true, produceLimit = 0, keepSeeds = false, seedLimit = 0 },
	},
}
assert(WaterPipeAutoFarming.chooseCrop(
	disabledPipe, WaterPipeAutoFarming.getCache(pipe)
) == "TestCrop",
	"stock targets must not prevent auto-sowing from keeping empty farmland planted")

SandboxVars.WaterPipes.EnableAutoFarming = false
local globallyDisabledPlow = { x = 11, y = 20, z = 0, state = "plow" }
function globallyDisabledPlow:seed() self.state = "seeded" end
assert(not WaterPipeAutoFarming.processPlant(globallyDisabledPlow)
	and globallyDisabledPlow.state == "plow",
	"the disabled global module must stop automation even on enabled pipes")
SandboxVars.WaterPipes.EnableAutoFarming = true

print("auto farming tests passed")
