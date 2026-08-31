WholeBuildingWater = WholeBuildingWater or {}

WholeBuildingWater.sourcesByBuilding = WholeBuildingWater.sourcesByBuilding or {}
WholeBuildingWater.sourceBuildings = WholeBuildingWater.sourceBuildings
	 or setmetatable({}, { __mode = "k" })
WholeBuildingWater.linkedFixtures = WholeBuildingWater.linkedFixtures
	 or setmetatable({}, { __mode = "k" })
WholeBuildingWater.scanQueue = WholeBuildingWater.scanQueue or {}
WholeBuildingWater.scanBatchSize = WholeBuildingWater.scanBatchSize or 64
WholeBuildingWater.tickRegistered = WholeBuildingWater.tickRegistered or false

local function safeInstanceOf(object, className)
	if not object or not instanceof then return false end
	local ok, result = pcall(instanceof, object, className)
	return ok and result == true
end

local function safeBuilding(square)
	if not square or not square.getBuilding then return nil end
	local ok, building = pcall(function() return square:getBuilding() end)
	return ok and building or nil
end

function WholeBuildingWater.getBuildingKey(building)
	if not building then return nil end
	local def = building.getDef and building:getDef() or nil
	if def and def.getIDString then
		local ok, id = pcall(function() return def:getIDString() end)
		if ok and id then return tostring(id) end
	end
	return tostring(building)
end

function WholeBuildingWater.findConnectedBuilding(square)
	local building = safeBuilding(square)
	if building then return building end
	if not square or not getCell then return nil end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	local cell = getCell()
	for _, offset in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		local adjacent = cell:getGridSquare(x + offset[1], y + offset[2], z)
		building = safeBuilding(adjacent)
		if building then return building end
	end
	return nil
end

function WholeBuildingWater.isEnabledSource(object)
	if not object or not object.getModData then return false end
	local modData = object:getModData()
	return modData and modData.wholeBuildingWater == true
		and modData.waterSupplyPipe == true
end

local function hasProperty(properties, property)
	if not properties or not property then return false end
	local ok, result = pcall(function() return properties:has(property) end)
	return ok and result == true
end

function WholeBuildingWater.isWaterFixture(object)
	if not object or not object.getSprite or not object.getModData then return false end
	local modData = object:getModData()
	if modData and (modData.infinite or modData.pipeType) then return false end
	if safeInstanceOf(object, "IsoClothingWasher")
		or safeInstanceOf(object, "IsoCombinationWasherDryer") then return true end

	local sprite = object:getSprite()
	local properties = sprite and sprite.getProperties and sprite:getProperties() or nil
	if hasProperty(properties, IsoFlagType and IsoFlagType.waterPiped) then return true end
	if properties and properties.Is then
		local ok, result = pcall(function() return properties:Is("waterPiped") end)
		if ok and result == true then return true end
	end
	return modData and modData.canBeWaterPiped ~= nil
end

function WholeBuildingWater.setExternalSource(object, source)
	-- Build 42 exposes the Java Class object to Lua as userdata, but does not
	-- expose java.lang.Class reflection methods on it. Merely indexing
	-- getDeclaredField/getSuperclass produces a red Lua error even inside pcall.
	-- Keep this hook for tests or a future public game API; production uses the
	-- reserve-water fallback below, which relies only on supported IsoObject API.
	if WholeBuildingWater.externalSourceSetter then
		return WholeBuildingWater.externalSourceSetter(object, source) == true
	end
	return false
end

local function syncFixture(object)
	if isClient and isClient() then return end
	if object.transmitModData then object:transmitModData() end
	if object.sync then pcall(function() object:sync() end) end
end

local function refillFallbackFixture(object)
	if not object or not object.getModData then return end
	local modData = object:getModData()
	modData.canBeWaterPiped = false
	modData.waterAmount = 10000
	modData.waterMaxAmount = 10000
	local container = object.getFluidContainer and object:getFluidContainer() or nil
	if container and object.addFluid and FluidType and FluidType.Water then
		pcall(function()
			local amount = container:getAmount()
			local capacity = container:getCapacity()
			if capacity > amount then object:addFluid(FluidType.Water, capacity - amount) end
		end)
	end
	syncFixture(object)
end

local function enableFallbackFixture(object, originalUsesExternal)
	local modData = object:getModData()
	local fallback = {
		originalCanBeWaterPiped = modData.canBeWaterPiped,
		originalWaterAmount = modData.waterAmount,
		originalWaterMaxAmount = modData.waterMaxAmount,
	}
	if object.setUsesExternalWaterSource then object:setUsesExternalWaterSource(false) end
	refillFallbackFixture(object)
	return fallback
end

function WholeBuildingWater.linkFixture(object, source)
	if not WholeBuildingWater.isWaterFixture(object)
		or not WholeBuildingWater.isEnabledSource(source) then return false end
	local current = WholeBuildingWater.linkedFixtures[object]
	if current and current.source == source then return true end
	if current then WholeBuildingWater.unlinkFixture(object) end

	local originalUsesExternal = object.getUsesExternalWaterSource
		and object:getUsesExternalWaterSource() == true or false
	if object.setUsesExternalWaterSource then object:setUsesExternalWaterSource(true) end
	local nativeLink = WholeBuildingWater.setExternalSource(object, source)
	local fallback = nil
	if not nativeLink then fallback = enableFallbackFixture(object, originalUsesExternal) end
	WholeBuildingWater.linkedFixtures[object] = {
		source = source,
		originalUsesExternal = originalUsesExternal,
		nativeLink = nativeLink,
		fallback = fallback,
	}
	return true
end

function WholeBuildingWater.unlinkFixture(object)
	local current = object and WholeBuildingWater.linkedFixtures[object]
	if not current then return false end
	if current.nativeLink then WholeBuildingWater.setExternalSource(object, nil) end
	if current.fallback then
		local modData = object:getModData()
		modData.canBeWaterPiped = current.fallback.originalCanBeWaterPiped
		modData.waterAmount = current.fallback.originalWaterAmount
		modData.waterMaxAmount = current.fallback.originalWaterMaxAmount
		syncFixture(object)
	end
	if object.setUsesExternalWaterSource then
		object:setUsesExternalWaterSource(current.originalUsesExternal == true)
	end
	if current.originalUsesExternal and object.doFindExternalWaterSource then
		pcall(function() object:doFindExternalWaterSource() end)
	end
	WholeBuildingWater.linkedFixtures[object] = nil
	return true
end

local function firstEnabledSource(entry, excluded)
	if not entry then return nil end
	for source in pairs(entry.sources) do
		if source ~= excluded and WholeBuildingWater.isEnabledSource(source)
			and source.getSquare and source:getSquare() then return source end
	end
	return nil
end

function WholeBuildingWater.applySquare(square, preferredSource)
	if not square or not square.getObjects then return 0 end
	local building = safeBuilding(square)
	local key = WholeBuildingWater.getBuildingKey(building)
	local entry = key and WholeBuildingWater.sourcesByBuilding[key] or nil
	local source = preferredSource or firstEnabledSource(entry)
	if not source then return 0 end
	local count = 0
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		if WholeBuildingWater.linkFixture(objects:get(i), source) then count = count + 1 end
	end
	return count
end

local function queueBuildingScan(source, building)
	local def = building and building.getDef and building:getDef() or nil
	if not def then return false end
	table.insert(WholeBuildingWater.scanQueue, {
		source = source,
		building = building,
		x1 = def:getX(), x2 = def:getX2(),
		y1 = def:getY(), y2 = def:getY2(),
		z1 = def:getMinLevel(), z2 = def:getMaxLevel(),
		x = def:getX(), y = def:getY(), z = def:getMinLevel(),
	})
	if not WholeBuildingWater.tickRegistered and Events and Events.OnTick then
		Events.OnTick.Add(WholeBuildingWater.processPendingScans)
		WholeBuildingWater.tickRegistered = true
	end
	return true
end

function WholeBuildingWater.processPendingScans()
	local remaining = math.max(1, tonumber(WholeBuildingWater.scanBatchSize) or 64)
	while remaining > 0 and #WholeBuildingWater.scanQueue > 0 do
		local scan = WholeBuildingWater.scanQueue[1]
		if not WholeBuildingWater.isEnabledSource(scan.source) then
			table.remove(WholeBuildingWater.scanQueue, 1)
		else
			local square = getCell():getGridSquare(scan.x, scan.y, scan.z)
			if square and safeBuilding(square) == scan.building then
				WholeBuildingWater.applySquare(square, scan.source)
			end
			remaining = remaining - 1
			scan.x = scan.x + 1
			if scan.x > scan.x2 then scan.x, scan.y = scan.x1, scan.y + 1 end
			if scan.y > scan.y2 then scan.y, scan.z = scan.y1, scan.z + 1 end
			if scan.z > scan.z2 then table.remove(WholeBuildingWater.scanQueue, 1) end
		end
	end
	if #WholeBuildingWater.scanQueue == 0 and WholeBuildingWater.tickRegistered
		and Events and Events.OnTick and Events.OnTick.Remove then
		Events.OnTick.Remove(WholeBuildingWater.processPendingScans)
		WholeBuildingWater.tickRegistered = false
	end
end

function WholeBuildingWater.registerSource(source)
	if not WholeBuildingWater.isEnabledSource(source) or not source.getSquare then return false end
	local building = WholeBuildingWater.findConnectedBuilding(source:getSquare())
	local key = WholeBuildingWater.getBuildingKey(building)
	if not key then return false end
	local oldKey = WholeBuildingWater.sourceBuildings[source]
	local existing = oldKey == key and WholeBuildingWater.sourcesByBuilding[key] or nil
	if existing and existing.sources[source] then return true end
	if oldKey and oldKey ~= key then WholeBuildingWater.unregisterSource(source) end
	local entry = WholeBuildingWater.sourcesByBuilding[key]
	if not entry then
		entry = { building = building, sources = setmetatable({}, { __mode = "k" }) }
		WholeBuildingWater.sourcesByBuilding[key] = entry
	end
	entry.sources[source] = true
	WholeBuildingWater.sourceBuildings[source] = key
	queueBuildingScan(source, building)
	return true
end

function WholeBuildingWater.unregisterSource(source)
	local key = source and WholeBuildingWater.sourceBuildings[source]
	local entry = key and WholeBuildingWater.sourcesByBuilding[key] or nil
	if entry then entry.sources[source] = nil end
	WholeBuildingWater.sourceBuildings[source] = nil
	local replacement = firstEnabledSource(entry, source)
	for fixture, link in pairs(WholeBuildingWater.linkedFixtures) do
		if link.source == source then
			if replacement then WholeBuildingWater.linkFixture(fixture, replacement)
			else WholeBuildingWater.unlinkFixture(fixture) end
		end
	end
	if entry and not firstEnabledSource(entry) then
		WholeBuildingWater.sourcesByBuilding[key] = nil
	end
	return key ~= nil
end

function WholeBuildingWater.syncSourceObject(object)
	if WholeBuildingWater.isEnabledSource(object) then
		return WholeBuildingWater.registerSource(object)
	end
	return WholeBuildingWater.unregisterSource(object)
end

function WholeBuildingWater.setObjectEnabled(object, enabled, transmit)
	if not object or type(enabled) ~= "boolean" or not object.getModData then return false end
	local modData = object:getModData()
	if enabled and modData.waterSupplyPipe ~= true then return false end
	modData.wholeBuildingWater = enabled and true or nil
	WholeBuildingWater.syncSourceObject(object)
	if transmit ~= false and object.transmitModData then object:transmitModData() end
	return true
end

function WholeBuildingWater.onGridSquareLoaded(square)
	if not square or not square.getObjects then return end
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if WholeBuildingWater.isEnabledSource(object) then
			WholeBuildingWater.registerSource(object)
		end
	end
	WholeBuildingWater.applySquare(square)
end

function WholeBuildingWater.onObjectAboutToBeRemoved(object)
	if WholeBuildingWater.sourceBuildings[object]
		or WholeBuildingWater.isEnabledSource(object) then
		WholeBuildingWater.unregisterSource(object)
	end
	WholeBuildingWater.unlinkFixture(object)
end

function WholeBuildingWater.onWaterAmountChange(object)
	local link = object and WholeBuildingWater.linkedFixtures[object]
	if link and link.fallback and WholeBuildingWater.isEnabledSource(link.source) then
		refillFallbackFixture(object)
	end
end

if not WholeBuildingWater.eventsRegistered and Events then
	if Events.LoadGridsquare then
		Events.LoadGridsquare.Add(WholeBuildingWater.onGridSquareLoaded)
	end
	if Events.OnObjectAboutToBeRemoved then
		Events.OnObjectAboutToBeRemoved.Add(WholeBuildingWater.onObjectAboutToBeRemoved)
	end
	if Events.OnWaterAmountChange then
		Events.OnWaterAmountChange.Add(WholeBuildingWater.onWaterAmountChange)
	end
	WholeBuildingWater.eventsRegistered = true
end

return WholeBuildingWater
