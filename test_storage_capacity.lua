package.path = "Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/shared/?.lua;" .. package.path

local nativeSetCalls = 0
local methods = {}
function methods:getType() return self.type end
function methods:getCapacity() return self.capacity end
function methods:getEffectiveCapacity() return self.capacity end
function methods:getMaxWeight() return self.capacity end
function methods:setCapacity(value)
	nativeSetCalls = nativeSetCalls + 1
	self.capacity = value
end
function methods:hasRoomFor(value)
	return self.capacityWeight + (type(value) == "number" and value or value.weight) <= self.capacity
end
function methods:getCapacityWeight() return self.capacityWeight end
function methods:isItemAllowed(item) return item.allowed ~= false end

ItemContainer = { class = {} }
__classmetatables = {
	[ItemContainer.class] = { __index = methods },
}

local Capacity = require "WaterPipe/StorageCapacity"

local pipe = setmetatable({
	type = "InfiniteIrrigationPipe",
	capacity = 100,
	capacityWeight = 9990,
}, { __index = methods })
local crate = setmetatable({
	type = "crate",
	capacity = 50,
	capacityWeight = 45,
}, { __index = methods })
local magicFridge = setmetatable({
	type = "MagicFridge",
	capacity = 100,
	capacityWeight = 999990,
}, { __index = methods })

assert(pipe:getCapacity() == 10000)
assert(pipe:getEffectiveCapacity() == 10000)
assert(pipe:getMaxWeight() == 10000)
assert(pipe:hasRoomFor(10))
assert(not pipe:hasRoomFor(11))
assert(pipe:hasRoomFor({ weight = 10, allowed = true,
	getUnequippedWeight = function(self) return self.weight end }))
assert(not pipe:hasRoomFor({ weight = 1, allowed = false,
	getUnequippedWeight = function(self) return self.weight end }))

assert(magicFridge:getCapacity() == 1000000)
assert(magicFridge:getEffectiveCapacity() == 1000000)
assert(magicFridge:getMaxWeight() == 1000000)
assert(magicFridge:hasRoomFor(10))
assert(not magicFridge:hasRoomFor(11))

assert(crate:getCapacity() == 50)
assert(crate:getEffectiveCapacity() == 50)
assert(crate:getMaxWeight() == 50)
assert(crate:hasRoomFor(5))
assert(not crate:hasRoomFor(6))

assert(Capacity.getPhysicalCapacity(pipe) == 100,
	"the maintenance path must read the native field, not the logical accessor")
assert(Capacity.setPhysicalCapacity(pipe, 100))
assert(nativeSetCalls == 1 and Capacity.getPhysicalCapacity(pipe) == 100)

print("WaterPipe logical storage-capacity tests passed")
