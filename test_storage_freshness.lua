package.path = "Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/?.lua;"
	.. package.path

local function objectList(values)
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
	}
end

local function food(age, offAge, offAgeMax, rotten)
	local item = {
		age = age, offAge = offAge, offAgeMax = offAgeMax,
		rotten = rotten, writes = 0,
	}
	function item:getAge() return self.age end
	function item:setAge(value) self.age = value; self.writes = self.writes + 1 end
	function item:getOffAge() return self.offAge end
	function item:getOffAgeMax() return self.offAgeMax end
	function item:isRotten() return self.rotten end
	return item
end

isClient = function() return false end
instanceof = function(item, className)
	return className == "Food" and item.isFood == true
end

local freshened = food(2, 3, 5, false)
freshened.isFood = true
local rotten = food(7, 3, 5, true)
rotten.isFood = true
local nonPerishable = food(12, 1000000000, 1000000000, false)
nonPerishable.isFood = true
local ordinaryItem = food(3, 3, 5, false)
local alreadyFresh = food(0, 3, 5, false)
alreadyFresh.isFood = true
local youngFood = food(0.5, 4, 7, false)
youngFood.isFood = true
local storedItems = {
	freshened, rotten, nonPerishable, ordinaryItem, alreadyFresh, youngFood,
}
local container = { getItems = function() return objectList(storedItems) end }
local pipeObject = {}

WaterPipe = {
	pipes = { { x = 1, y = 2, z = 0 } },
	findAnyServicePipeObject = function() return pipeObject end,
	getTimestamp = function() return 0 end,
}
WaterSupplyPipe = {
	ensureStorage = function(object)
		assert(object == pipeObject)
		return container
	end,
}
getCell = function()
	return { getGridSquare = function(_, x, y, z)
		assert(x == 1 and y == 2 and z == 0)
		return {}
	end }
end

local synchronized = {}
sendItemStats = function(item) table.insert(synchronized, item) end

local Freshness = require "WaterPipe/StorageFreshness"
Freshness.maxItemsPerBatch = 2
Freshness.timeBudgetMs = 0
assert(Freshness.requestPass(), "a pipe should schedule one freshness pass")
assert(not Freshness.requestPass(), "an active freshness pass must not restart")
local complete1, preserved1, processed1 = Freshness.processPass()
assert(not complete1 and preserved1 == 1 and processed1 == 2,
	"the first bounded batch should freshen usable food and stop at its item limit")
local complete2, preserved2, processed2 = Freshness.processPass()
assert(not complete2 and preserved2 == 0 and processed2 == 2,
	"rotten, non-perishable, and non-food items must remain unchanged")
local complete3, preserved3, processed3 = Freshness.processPass()
assert(complete3 and preserved3 == 0 and processed3 == 2,
	"the final bounded batch should avoid rewriting already-safe fresh food")
assert(freshened.age == 0 and freshened.writes == 1
	and rotten.age == 7 and rotten.writes == 0
	and nonPerishable.age == 12 and nonPerishable.writes == 0
	and ordinaryItem.age == 3 and ordinaryItem.writes == 0
	and alreadyFresh.writes == 0 and youngFood.age == 0.5 and youngFood.writes == 0,
	"freshness maintenance must affect only non-rotten perishable Food items")
assert(#synchronized == 1 and synchronized[1] == freshened,
	"changed food stats should be synchronized exactly once")
assert(not Freshness.passPending and Freshness.processing == nil,
	"a completed freshness pass should release its queue state")

print("WaterPipe storage-freshness tests passed")
