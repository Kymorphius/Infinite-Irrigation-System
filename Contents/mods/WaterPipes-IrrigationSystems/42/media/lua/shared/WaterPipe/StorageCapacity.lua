WaterPipeStorageCapacity = WaterPipeStorageCapacity or {}

local StorageCapacity = WaterPipeStorageCapacity

StorageCapacity.containerType = "InfiniteIrrigationPipe"
StorageCapacity.logicalCapacity = 10000
StorageCapacity.physicalCapacity = 100

local PATCH_KEY = "InfiniteIrrigationPipes_originalHasRoomFor"
local GET_CAPACITY_KEY = "InfiniteIrrigationPipes_originalGetCapacity"
local GET_EFFECTIVE_CAPACITY_KEY = "InfiniteIrrigationPipes_originalGetEffectiveCapacity"
local GET_MAX_WEIGHT_KEY = "InfiniteIrrigationPipes_originalGetMaxWeight"
local SET_CAPACITY_KEY = "InfiniteIrrigationPipes_originalSetCapacity"

local originalHasRoomFor
local originalGetCapacity
local originalGetEffectiveCapacity
local originalGetMaxWeight
local originalSetCapacity

local function safeCall(callback, fallback)
	local ok, result = pcall(callback)
	if ok then return result end
	return fallback
end

local function isPipeStorage(container)
	if not container then return false end
	return safeCall(function()
		return container:getType() == StorageCapacity.containerType
	end, false)
end

local function addedWeight(value)
	if type(value) == "number" then return value end
	if not value then return nil end
	local weight = safeCall(function() return value:getUnequippedWeight() end, nil)
	if weight == nil then
		weight = safeCall(function() return value:getActualWeight() end, nil)
	end
	return tonumber(weight)
end

local function unpackValue(...)
	-- Build 42 exposes both hasRoomFor(item) and hasRoomFor(character, item).
	if select("#", ...) >= 2 then return select(2, ...) end
	return select(1, ...)
end

function StorageCapacity.install()
	if not __classmetatables or not ItemContainer or not ItemContainer.class then
		return false
	end

	local classMetatable = __classmetatables[ItemContainer.class]
	local methods = classMetatable and classMetatable.__index
	if not methods or type(methods.hasRoomFor) ~= "function"
		or type(methods.getCapacity) ~= "function" then
		return false
	end

	if rawget(methods, PATCH_KEY) then
		originalHasRoomFor = rawget(methods, PATCH_KEY)
		originalGetCapacity = rawget(methods, GET_CAPACITY_KEY)
		originalGetEffectiveCapacity = rawget(methods, GET_EFFECTIVE_CAPACITY_KEY)
		originalGetMaxWeight = rawget(methods, GET_MAX_WEIGHT_KEY)
		originalSetCapacity = rawget(methods, SET_CAPACITY_KEY)
		return true
	end

	originalHasRoomFor = methods.hasRoomFor
	originalGetCapacity = methods.getCapacity
	originalGetEffectiveCapacity = methods.getEffectiveCapacity
	originalGetMaxWeight = methods.getMaxWeight
	originalSetCapacity = methods.setCapacity

	rawset(methods, PATCH_KEY, originalHasRoomFor)
	rawset(methods, GET_CAPACITY_KEY, originalGetCapacity)
	rawset(methods, GET_EFFECTIVE_CAPACITY_KEY, originalGetEffectiveCapacity)
	rawset(methods, GET_MAX_WEIGHT_KEY, originalGetMaxWeight)
	rawset(methods, SET_CAPACITY_KEY, originalSetCapacity)

	methods.getCapacity = function(container)
		if isPipeStorage(container) then return StorageCapacity.logicalCapacity end
		return originalGetCapacity(container)
	end

	if type(originalGetEffectiveCapacity) == "function" then
		methods.getEffectiveCapacity = function(container, character)
			if isPipeStorage(container) then return StorageCapacity.logicalCapacity end
			return originalGetEffectiveCapacity(container, character)
		end
	end

	if type(originalGetMaxWeight) == "function" then
		methods.getMaxWeight = function(container)
			if isPipeStorage(container) then return StorageCapacity.logicalCapacity end
			return originalGetMaxWeight(container)
		end
	end

	methods.hasRoomFor = function(container, ...)
		if not isPipeStorage(container) then
			return originalHasRoomFor(container, ...)
		end

		local value = unpackValue(...)
		local weight = addedWeight(value)
		if weight == nil then return originalHasRoomFor(container, ...) end
		if type(value) ~= "number" then
			local allowed = safeCall(function() return container:isItemAllowed(value) end, true)
			if not allowed then return false end
		end
		local currentWeight = tonumber(safeCall(function()
			return container:getCapacityWeight()
		end, nil))
		if currentWeight == nil then return originalHasRoomFor(container, ...) end
		return currentWeight + weight <= StorageCapacity.logicalCapacity
	end

	print("[InfiniteIrrigationPipes] Logical pipe storage capacity installed: "
		.. tostring(StorageCapacity.logicalCapacity)
		.. " (physical container: " .. tostring(StorageCapacity.physicalCapacity) .. ")")
	return true
end

function StorageCapacity.getPhysicalCapacity(container)
	if not container then return nil end
	StorageCapacity.install()
	if type(originalGetCapacity) == "function" then
		return tonumber(safeCall(function() return originalGetCapacity(container) end, nil))
	end
	return tonumber(safeCall(function() return container:getCapacity() end, nil))
end

function StorageCapacity.setPhysicalCapacity(container, capacity)
	if not container then return false end
	StorageCapacity.install()
	local setter = originalSetCapacity
	if type(setter) == "function" then
		return safeCall(function()
			setter(container, capacity)
			return true
		end, false)
	end
	if type(container.setCapacity) == "function" then
		return safeCall(function()
			container:setCapacity(capacity)
			return true
		end, false)
	end
	return false
end

StorageCapacity.install()
if Events and Events.OnGameBoot then
	Events.OnGameBoot.Add(StorageCapacity.install)
end

return StorageCapacity
