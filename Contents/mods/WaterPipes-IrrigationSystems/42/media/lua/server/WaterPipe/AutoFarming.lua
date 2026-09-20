WaterPipeAutoFarming = WaterPipeAutoFarming or {}

local AutoFarming = WaterPipeAutoFarming

AutoFarming.UNLIMITED = -1
AutoFarming.DEFAULT_LIMIT = 9
AutoFarming.cycleCaches = {}
AutoFarming.cycleId = 0
AutoFarming.inventoryScanBatch = 1000
AutoFarming.inventoryScanBudgetMs = 1
AutoFarming.cropTypes = nil

function AutoFarming.isModuleEnabled()
	return SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.EnableAutoFarming == true
end

local function clampLimit(value)
	value = math.floor(tonumber(value) or AutoFarming.DEFAULT_LIMIT)
	if value < AutoFarming.UNLIMITED then return AutoFarming.UNLIMITED end
	return math.min(value, 100000)
end

local function getCropProps(cropType)
	return farming_vegetableconf and farming_vegetableconf.props
		and farming_vegetableconf.props[cropType] or nil
end

function AutoFarming.sanitizeSettings(settings)
	local sanitized = {}
	if type(settings) ~= "table" then return sanitized end
	local hasCatalog = farming_vegetableconf and type(farming_vegetableconf.props) == "table"
	local accepted = 0
	for cropType, value in pairs(settings) do
		local props = type(cropType) == "string" and getCropProps(cropType) or nil
		if type(cropType) == "string" and type(value) == "table"
			and (props or not hasCatalog) and accepted < 256 then
			sanitized[cropType] = {
				enabled = value.enabled ~= false,
				produceLimit = clampLimit(value.produceLimit),
				keepSeeds = value.keepSeeds ~= false,
				seedLimit = clampLimit(value.seedLimit),
			}
			accepted = accepted + 1
		end
	end
	return sanitized
end

function AutoFarming.getCropSetting(pipe, cropType)
	local configured = pipe and type(pipe.autoFarmSettings) == "table"
		and pipe.autoFarmSettings[cropType] or nil
	if type(configured) ~= "table" then
		return {
			enabled = true,
			produceLimit = AutoFarming.DEFAULT_LIMIT,
			keepSeeds = true,
			seedLimit = AutoFarming.DEFAULT_LIMIT,
		}
	end
	return {
		enabled = configured.enabled ~= false,
		produceLimit = clampLimit(configured.produceLimit),
		keepSeeds = configured.keepSeeds ~= false,
		seedLimit = clampLimit(configured.seedLimit),
	}
end

function AutoFarming.beginCycle()
	AutoFarming.cycleId = AutoFarming.cycleId + 1
end

local function getPipeKey(pipe)
	if not pipe then return nil end
	return WaterPipe.getPipeKey(pipe.x, pipe.y, pipe.z)
end

function AutoFarming.getPipeObject(pipe)
	if not pipe or not getCell then return nil end
	local square = getCell():getGridSquare(pipe.x, pipe.y, pipe.z)
	return square and WaterPipe.findAnyServicePipeObject(square) or nil
end

function AutoFarming.getStorage(pipe)
	local object = AutoFarming.getPipeObject(pipe)
	if not object or not WaterSupplyPipe then return nil end
	return WaterSupplyPipe.ensureStorage(object)
end

local function getItemFullType(item)
	if not item then return nil end
	if item.getFullType then return item:getFullType() end
	return item.getType and item:getType() or nil
end

local isUsableSeed

function AutoFarming.getCache(pipe)
	local key = getPipeKey(pipe)
	if not key then return nil end
	local container = AutoFarming.getStorage(pipe)
	if not container or not container.getItems then return nil end
	local items = container:getItems()
	if not items or not items.size or not items.get then return nil end
	local totalItems = items:size()
	local cache = AutoFarming.cycleCaches[key]
	if not cache or cache.container ~= container or cache.totalItems ~= totalItems then
		cache = {
			container = container,
			counts = {},
			usableCounts = {},
			totalItems = totalItems,
			scanIndex = 0,
			ready = totalItems == 0,
			lastScanCycle = nil,
		}
		AutoFarming.cycleCaches[key] = cache
	end
	if cache.ready then return cache end
	-- Advance a large inventory at most once per maintenance invocation.  This
	-- prevents a very large pipe inventory from becoming a single-frame scan.
	if cache.lastScanCycle == AutoFarming.cycleId then return nil end
	cache.lastScanCycle = AutoFarming.cycleId
	local startTime = WaterPipe.getTimestamp and WaterPipe.getTimestamp() or 0
	local endIndex = math.min(
		cache.scanIndex + AutoFarming.inventoryScanBatch - 1,
		cache.totalItems - 1
	)
	for i = cache.scanIndex, endIndex do
		local item = items:get(i)
		local fullType = getItemFullType(item)
		if fullType then
			cache.counts[fullType] = (cache.counts[fullType] or 0) + 1
			if isUsableSeed(item) then
				cache.usableCounts[fullType] = (cache.usableCounts[fullType] or 0) + 1
			end
		end
		cache.scanIndex = i + 1
		if AutoFarming.inventoryScanBudgetMs > 0 and i % 50 == 0
			and WaterPipe.getTimestamp
			and WaterPipe.getTimestamp() - startTime >= AutoFarming.inventoryScanBudgetMs then
			break
	end
		end
	cache.ready = cache.scanIndex >= cache.totalItems
	return cache.ready and cache or nil
end

local function getCount(cache, fullType)
	return cache and fullType and (tonumber(cache.counts[fullType]) or 0) or 0
end

local function notifyAdded(container, items)
	if items and sendAddItemsToContainer then sendAddItemsToContainer(container, items) end
end

local function isBelowTarget(cache, fullType, target)
	target = clampLimit(target)
	return target < 0 or getCount(cache, fullType) < target
end

-- Targets are restock thresholds, not hard caps.  If stock is below the
-- configured target, keep the whole output of this harvest; a natural harvest
-- may therefore cross the target slightly.  Once stock has reached the target,
-- later ripe plants remain in the field until the player removes some stock.
function AutoFarming.addTargetBatch(cache, fullType, wanted, target)
	if not cache or not fullType then return 0 end
	wanted = math.max(0, math.floor(tonumber(wanted) or 0))
	if not isBelowTarget(cache, fullType, target) then return 0 end
	if wanted <= 0 then return 0 end
	local items = cache.container:AddItems(fullType, wanted)
	notifyAdded(cache.container, items)
	local added = items and items.size and items:size() or wanted
	cache.counts[fullType] = getCount(cache, fullType) + added
	cache.usableCounts[fullType] = (cache.usableCounts[fullType] or 0) + added
	cache.totalItems = cache.totalItems + added
	return added
end

local function targetDeficitScore(cache, fullType, target)
	target = clampLimit(target)
	if target < 0 then return 1 end
	if target == 0 then return 0 end
	return math.max(0, target - getCount(cache, fullType)) / target
end

isUsableSeed = function(item)
	if not item then return false end
	if not instanceof or not instanceof(item, "Food") then return true end
	if item:isRotten() or item:isCooked() or item:isBurnt() then return false end
	-- Build 42.12 changed InventoryItem:hasTag() to accept ItemTag objects only;
	-- passing the old string form throws while scanning any ordinary Food item.
	local isCutting = ItemTag and ItemTag.IS_CUTTING
		and item.hasTag and item:hasTag(ItemTag.IS_CUTTING) or false
	if isCutting and not item:isFresh() then return false end
	local baseHunger = math.abs(item:getBaseHunger())
	local hungerChange = math.abs(item:getHungerChange())
	if item:isFresh() then return hungerChange >= baseHunger end
	return hungerChange >= baseHunger * 0.75
end

function AutoFarming.removeOne(cache, acceptedTypes)
	if not cache or type(acceptedTypes) ~= "table" then return nil end
	local items = cache.container:getItems()
	if not items or not items.size or not items.get then return nil end
	for _, fullType in ipairs(acceptedTypes) do
		if getCount(cache, fullType) > 0 then
			for i = 0, items:size() - 1 do
				local item = items:get(i)
				if getItemFullType(item) == fullType and isUsableSeed(item) then
					cache.container:Remove(item)
					if sendRemoveItemFromContainer then
						sendRemoveItemFromContainer(cache.container, item)
					end
					cache.counts[fullType] = getCount(cache, fullType) - 1
					cache.usableCounts[fullType] = math.max(
						0, (cache.usableCounts[fullType] or 0) - 1
					)
					cache.totalItems = math.max(0, cache.totalItems - 1)
					return fullType
				end
			end
		end
	end
	return nil
end

local function isPipeEligible(pipe, feature)
	return pipe and pipe[feature] == true and AutoFarming.getPipeObject(pipe) ~= nil
end

function AutoFarming.getCoveringPipe(x, y, z, feature)
	if x == nil or y == nil or z == nil then return nil end
	local maxRadius = math.floor((WaterPipe.irrigationRangeSizes[#WaterPipe.irrigationRangeSizes] - 1) / 2)
	local best, bestDistance, bestKey = nil, nil, nil
	for dx = -maxRadius, maxRadius do
		for dy = -maxRadius, maxRadius do
			local pipe = WaterPipe.pipeByKey[WaterPipe.getPipeKey(x + dx, y + dy, z)]
			if isPipeEligible(pipe, feature)
				and math.abs(dx) <= WaterPipe.getPipeIrrigationRadius(pipe)
				and math.abs(dy) <= WaterPipe.getPipeIrrigationRadius(pipe) then
				local distance = dx * dx + dy * dy
				local key = getPipeKey(pipe)
				if bestDistance == nil or distance < bestDistance
					or (distance == bestDistance and key < bestKey) then
					best, bestDistance, bestKey = pipe, distance, key
				end
			end
		end
	end
	return best
end

local function cropTypesSorted()
	if AutoFarming.cropTypes then return AutoFarming.cropTypes end
	local result = {}
	if farming_vegetableconf and farming_vegetableconf.props then
		for cropType, props in pairs(farming_vegetableconf.props) do
			if props and props.vegetableName and (props.seedTypes or props.seedName) then
				table.insert(result, cropType)
			end
		end
	end
	table.sort(result)
	AutoFarming.cropTypes = result
	return AutoFarming.cropTypes
end

local function acceptedSeedTypes(props)
	if type(props.seedTypes) == "table" then return props.seedTypes end
	return props.seedName and { props.seedName } or {}
end

-- Build 42 has crops such as Tomato and Strawberry whose seedName is the
-- harvested fruit (used by the manual Extract Seeds recipe), while seedTypes
-- contains the actual items accepted by the sowing action.  Auto-farming must
-- replenish an item it can sow again.  Preserve seedName for crops such as
-- Corn where that item is itself listed as a valid seed.
function AutoFarming.getHarvestSeedType(props)
	if type(props) ~= "table" then return nil end
	local seedTypes = acceptedSeedTypes(props)
	if props.seedName then
		for _, seedType in ipairs(seedTypes) do
			if seedType == props.seedName then return props.seedName end
		end
	end
	return seedTypes[1] or props.seedName
end

function AutoFarming.chooseCrop(pipe, cache)
	if not pipe or not cache then return nil end
	local candidates = {}
	local bestScore = nil
	for _, cropType in ipairs(cropTypesSorted()) do
		local props = getCropProps(cropType)
		local setting = AutoFarming.getCropSetting(pipe, cropType)
		local available = false
		for _, seedType in ipairs(acceptedSeedTypes(props)) do
			if (cache.usableCounts[seedType] or 0) > 0 then available = true break end
		end
		if setting.enabled and available then
			local harvestSeedType = AutoFarming.getHarvestSeedType(props)
			local score = targetDeficitScore(
				cache, props.vegetableName, setting.produceLimit
			)
			if props.produceExtra then
				score = math.max(score, targetDeficitScore(
					cache, props.produceExtra, setting.produceLimit
				))
			end
			if setting.keepSeeds and harvestSeedType then
				score = math.max(score, targetDeficitScore(
					cache, harvestSeedType, setting.seedLimit
				))
			end
			-- Stock targets decide when ripe plants should be harvested, not
			-- whether empty farmland should be planted.  Even with every target
			-- satisfied, auto-sowing keeps the configured area visibly planted as
			-- long as an enabled crop has usable seeds.  Deficit remains a priority
			-- only when choosing between multiple available crops.
			if bestScore == nil or score > bestScore then
				bestScore = score
				candidates = { cropType }
			elseif score == bestScore then
				table.insert(candidates, cropType)
			end
		end
	end
	if #candidates == 0 then return nil end
	local cursor = math.max(0, math.floor(tonumber(pipe.autoSowCursor) or 0))
	local index = (cursor % #candidates) + 1
	pipe.autoSowCursor = cursor + 1
	return candidates[index]
end

local function resolveOwner(pipe)
	local ownerId = pipe and tonumber(pipe.owner) or nil
	if ownerId == nil or ownerId < 0 then return nil, 0 end
	local owner = nil
	if isServer and isServer() and getPlayerByOnlineID then
		owner = getPlayerByOnlineID(ownerId)
	elseif getSpecificPlayer then
		owner = getSpecificPlayer(ownerId)
	end
	local skill = owner and owner.getPerkLevel and owner:getPerkLevel(Perks.Farming) or 0
	return owner, math.max(0, tonumber(skill) or 0)
end

function AutoFarming.trySowPlant(plant, pipe)
	if not plant or plant.state ~= "plow" or not pipe or pipe.autoSowEnabled ~= true then return false end
	local cache = AutoFarming.getCache(pipe)
	local cropType = AutoFarming.chooseCrop(pipe, cache)
	if not cropType then return false end
	local props = getCropProps(cropType)
	if not props or not AutoFarming.removeOne(cache, acceptedSeedTypes(props)) then return false end
	local _, skill = resolveOwner(pipe)
	plant:seed(cropType, skill)
	if pipe.owner ~= nil then plant.owner = tonumber(pipe.owner) end
	if plant.saveData then plant:saveData() end
	return true
end

function AutoFarming.trySowAt(x, y, z)
	if not AutoFarming.isModuleEnabled() then return false end
	local farmingSystem = SFarmingSystem and SFarmingSystem.instance
	if not farmingSystem or not farmingSystem.getLuaObjectAt then return false end
	local plant = farmingSystem:getLuaObjectAt(x, y, z)
	if not plant or plant.state ~= "plow" then return false end
	local pipe = AutoFarming.getCoveringPipe(x, y, z, "autoSowEnabled")
	return AutoFarming.trySowPlant(plant, pipe)
end

local function canHarvest(plant)
	if not plant then return false end
	if plant.canHarvest then return plant:canHarvest() end
	return plant.hasVegetable == true
end

function AutoFarming.tryHarvestPlant(plant, pipe)
	if not canHarvest(plant) or not pipe or pipe.autoHarvestEnabled ~= true then return false end
	-- Build 42's harvest/remove path mutates the server plant object in-place.
	-- Keep the tile coordinates before harvestThis()/removePlant(), otherwise the
	-- post-harvest auto-till step receives nil coordinates and aborts the cycle.
	local plantX, plantY, plantZ = plant.x, plant.y, plant.z
	if plantX == nil or plantY == nil or plantZ == nil then return false end
	local props = getCropProps(plant.typeOfSeed)
	local setting = AutoFarming.getCropSetting(pipe, plant.typeOfSeed)
	if not props or not setting.enabled then return false end
	local cache = AutoFarming.getCache(pipe)
	if not cache then return false end
	local harvestSeedType = AutoFarming.getHarvestSeedType(props)
	local needsProduce = isBelowTarget(cache, props.vegetableName, setting.produceLimit)
		or (props.produceExtra
			and isBelowTarget(cache, props.produceExtra, setting.produceLimit))
	local needsSeeds = plant.hasSeed and setting.keepSeeds and harvestSeedType
		and isBelowTarget(cache, harvestSeedType, setting.seedLimit)
	-- Do not consume a ripe plant merely to discard every output.  It remains
	-- harvestable and becomes the next restock source after inventory is removed.
	if not needsProduce and not needsSeeds then return false end
	local owner, skill = resolveOwner(pipe)
	local numberOfVeg = getVegetablesNumber(
		props.minVeg, props.maxVeg, props.minVegAutorized,
		props.maxVegAutorized, plant, skill
	)
	numberOfVeg = math.max(0, math.floor(tonumber(numberOfVeg) or 0))
	AutoFarming.addTargetBatch(cache, props.vegetableName, numberOfVeg, setting.produceLimit)
	if props.produceExtra then
		AutoFarming.addTargetBatch(
			cache, props.produceExtra, numberOfVeg, setting.produceLimit
		)
	end
	if plant.hasSeed and setting.keepSeeds and harvestSeedType then
		local seedCount = math.max(math.floor(numberOfVeg * (props.seedPerVeg or 0.5)), 1)
		AutoFarming.addTargetBatch(cache, harvestSeedType, seedCount, setting.seedLimit)
	end
	if owner and SFarmingSystem.instance.gainXp
		and tonumber(plant.owner) == tonumber(pipe.owner) then
		SFarmingSystem.instance:gainXp(owner, plant)
	end

	plant.hasVegetable = false
	plant.hasSeed = false
	plant.hasSeeds = false
	if props.growBack then
		plant.nbOfGrow = props.growBack
		plant.fertilizer = 0
		SFarmingSystem.instance:growPlant(plant, nil, true)
		local sprite = farming_vegetableconf.getSpriteName(plant)
		if sprite then plant:setSpriteName(sprite) end
		plant:saveData()
	else
		plant:harvestThis()
		-- A fully automated pipe can begin the next crop cycle without waiting for
		-- the generic ten-minute scan to discover the harvested tile.  Re-plowing
		-- still respects this pipe's independent auto-till switch.
		if pipe.autoSowEnabled == true and WaterPipe.isPipeAutoTillEnabled
			and WaterPipe.isPipeAutoTillEnabled(pipe) then
			local square = plant.getSquare and plant:getSquare() or nil
			if square and SFarmingSystem.instance.removePlant then
				SFarmingSystem.instance:removePlant(plant)
				if WaterPipe.tryAutoTillPosition(plantX, plantY, plantZ, true) then
					AutoFarming.trySowAt(plantX, plantY, plantZ)
				end
			end
		end
	end
	return true
end

function AutoFarming.processPlant(plant)
	if not AutoFarming.isModuleEnabled() then return false end
	if not plant or plant.x == nil or plant.y == nil or plant.z == nil then return false end
	if plant.state == "plow" then
		local sowPipe = AutoFarming.getCoveringPipe(plant.x, plant.y, plant.z, "autoSowEnabled")
		return AutoFarming.trySowPlant(plant, sowPipe)
	end
	if canHarvest(plant) then
		local harvestPipe = AutoFarming.getCoveringPipe(
			plant.x, plant.y, plant.z, "autoHarvestEnabled"
		)
		return AutoFarming.tryHarvestPlant(plant, harvestPipe)
	end
	return false
end

function AutoFarming.setObjectSettings(pipeObject, autoSowEnabled, autoHarvestEnabled, settings)
	if isClient() or not pipeObject or not pipeObject:getSquare() then return false end
	if type(autoSowEnabled) ~= "boolean" or type(autoHarvestEnabled) ~= "boolean" then return false end
	local sanitized = AutoFarming.sanitizeSettings(settings)
	local modData = pipeObject:getModData()
	local servicesChanged = modData.autoSowEnabled ~= autoSowEnabled
		or modData.autoHarvestEnabled ~= autoHarvestEnabled
	modData.autoSowEnabled = autoSowEnabled
	modData.autoHarvestEnabled = autoHarvestEnabled
	modData.autoFarmSettings = sanitized
	pipeObject:transmitModData()
	local square = pipeObject:getSquare()
	local pipe = WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	if pipe then
		pipe.autoSowEnabled = autoSowEnabled
		pipe.autoHarvestEnabled = autoHarvestEnabled
		pipe.autoFarmSettings = sanitized
	end
	if servicesChanged then WaterPipe.markCoverageMapDirty() end
	-- A player enabling automation expects an already-plowed nearby tile to be
	-- seeded now, not after one cycle to rebuild coverage and another to scan it.
	-- This bounded one-off pass touches at most the selected pipe's 15x15 area.
	if pipe and (autoSowEnabled or autoHarvestEnabled) then
		WaterPipe.careForPipeArea(pipe, "auto-farming-settings")
	end
	return true
end

return AutoFarming
