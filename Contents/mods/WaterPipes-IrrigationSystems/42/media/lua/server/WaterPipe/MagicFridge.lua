require "WaterPipe/StorageCapacity"
require "WaterPipe/PowerPipe"
require "WaterPipe/WholeBuildingWater"
require "WaterPipe/StorageFreshness"
require "WaterPipe/PipeSprites"

MagicFridge = MagicFridge or {}

local Fridge = MagicFridge

Fridge.objectName = "MagicFridge"
Fridge.itemType = "WaterPipes.MagicFridgePacked"
Fridge.containerType = "MagicFridge"
Fridge.capacity = 1000000
Fridge.cycleMinutes = { 10, 30, 60, 360, 720, 1440 }
Fridge.defaultCycleIndex = 1
Fridge.defaultProduceLimit = 9
Fridge.settingsModDataKey = "WaterPipesMagicFridgeSettings"
Fridge.maxFreshnessItemsPerPass = 1000
Fridge.objects = Fridge.objects or setmetatable({}, { __mode = "k" })
Fridge.freshnessCursors = Fridge.freshnessCursors or setmetatable({}, { __mode = "k" })
Fridge.seedMap = nil
Fridge.variantOrder = {
	"White", "Blue", "Green", "Industrial", "Mini",
	"Plain", "Red", "Steel", "WhiteIndustrial",
}
Fridge.variants = {
	White = { itemType = Fridge.itemType, legacyItemType = "WaterPipes.MagicFridge", iconItemType = "Base.Mov_WhiteFridge", recipe = "AskMagicFridge", south = "appliances_refrigeration_01_0", east = "appliances_refrigeration_01_1" },
	Blue = { itemType = "WaterPipes.MagicFridgeBluePacked", legacyItemType = "WaterPipes.MagicFridgeBlue", iconItemType = "Base.Mov_BlueFridge", recipe = "AskMagicFridgeBlue", south = "appliances_refrigeration_01_4", east = "appliances_refrigeration_01_5" },
	Green = { itemType = "WaterPipes.MagicFridgeGreenPacked", legacyItemType = "WaterPipes.MagicFridgeGreen", iconItemType = "Base.Mov_GreenFridge", recipe = "AskMagicFridgeGreen", south = "appliances_refrigeration_01_12", east = "appliances_refrigeration_01_13" },
	Industrial = { itemType = "WaterPipes.MagicFridgeIndustrialPacked", legacyItemType = "WaterPipes.MagicFridgeIndustrial", iconItemType = "Base.Mov_IndustrialFridge", recipe = "AskMagicFridgeIndustrial", south = "appliances_refrigeration_01_22", east = "appliances_refrigeration_01_23" },
	Mini = { itemType = "WaterPipes.MagicFridgeMiniPacked", legacyItemType = "WaterPipes.MagicFridgeMini", iconItemType = "Base.Mov_FridgeMini", recipe = "AskMagicFridgeMini", south = "appliances_refrigeration_01_25", east = "appliances_refrigeration_01_24" },
	Plain = { itemType = "WaterPipes.MagicFridgePlainPacked", legacyItemType = "WaterPipes.MagicFridgePlain", iconItemType = "Base.Mov_PlainFridge", recipe = "AskMagicFridgePlain", south = "appliances_refrigeration_01_28", east = "appliances_refrigeration_01_29" },
	Red = { itemType = "WaterPipes.MagicFridgeRedPacked", legacyItemType = "WaterPipes.MagicFridgeRed", iconItemType = "Base.Mov_RedFridge", recipe = "AskMagicFridgeRed", south = "appliances_refrigeration_01_32", east = "appliances_refrigeration_01_33" },
	Steel = { itemType = "WaterPipes.MagicFridgeSteelPacked", legacyItemType = "WaterPipes.MagicFridgeSteel", iconItemType = "Base.Mov_SteelFridge", recipe = "AskMagicFridgeSteel", south = "appliances_refrigeration_01_8", east = "appliances_refrigeration_01_9" },
	Trailer = { itemType = "WaterPipes.MagicFridgeTrailerPacked", legacyItemType = "WaterPipes.MagicFridgeTrailer", iconItemType = "Base.Mov_TrailerFridge", recipe = "AskMagicFridgeTrailer", south = "location_trailer_02_26", east = "location_trailer_02_26" },
	WhiteIndustrial = { itemType = "WaterPipes.MagicFridgeWhiteIndustrialPacked", legacyItemType = "WaterPipes.MagicFridgeWhiteIndustrial", iconItemType = "Base.Mov_WhiteIndustrialFridge", recipe = "AskMagicFridgeWhiteIndustrial", south = "appliances_refrigeration_01_40", east = "appliances_refrigeration_01_41" },
}
Fridge.variantByItemType = {}
for _, id in ipairs(Fridge.variantOrder) do
	local variant = Fridge.variants[id]
	variant.id = id
	Fridge.variantByItemType[variant.itemType] = variant
	Fridge.variantByItemType[variant.legacyItemType] = variant
end
local trailerVariant = Fridge.variants.Trailer
trailerVariant.id = "Trailer"
Fridge.variantByItemType[trailerVariant.itemType] = trailerVariant
Fridge.variantByItemType[trailerVariant.legacyItemType] = trailerVariant

local function worldAgeHours()
	local gameTime = getGameTime and getGameTime() or nil
	return gameTime and gameTime.getWorldAgeHours
		and tonumber(gameTime:getWorldAgeHours()) or 0
end

local function itemFullType(item)
	if not item then return nil end
	if item.getFullType then return item:getFullType() end
	if item.getModule and item.getType then
		return tostring(item:getModule()) .. "." .. tostring(item:getType())
	end
	return nil
end

function Fridge.getVariant(id)
	return Fridge.variants[id] or Fridge.variants.White
end

function Fridge.getVariantForItem(item)
	return Fridge.variantByItemType[itemFullType(item)] or Fridge.variants.White
end

function Fridge.isItem(item)
	return Fridge.variantByItemType[itemFullType(item)] ~= nil
end

local function applyItemIcon(item, variant)
	if not instanceItem or not item or not item.setTexture then return false end
	local source = instanceItem(variant.iconItemType)
	local texture = source and source.getTexture and source:getTexture() or nil
	if not texture then return false end
	item:setTexture(texture)
	if item.setIcon then item:setIcon(texture) end
	return true
end

function Fridge.prepareCarryItem(item)
	local variant = Fridge.variantByItemType[itemFullType(item)]
	local inventory = item and item.getInventory and item:getInventory() or nil
	if not variant or not inventory then return nil end
	if inventory.setType then inventory:setType(Fridge.containerType) end
	WaterPipeStorageCapacity.setPhysicalCapacity(inventory, 100)
	applyItemIcon(item, variant)
	return inventory
end

function Fridge.onCreateItem(item)
	Fridge.prepareCarryItem(item)
end

function Fridge.configureIcons()
	if not instanceItem or not getScriptManager then return false end
	local manager = getScriptManager()
	for _, id in ipairs(Fridge.variantOrder) do
		local variant = Fridge.variants[id]
		local source = instanceItem(variant.iconItemType)
		local texture = source and source.getTexture and source:getTexture() or nil
		local recipe = manager and (manager:getCraftRecipe("WaterPipes." .. variant.recipe)
			or manager:getCraftRecipe(variant.recipe)) or nil
		if texture and recipe and recipe.overrideIconTexture then
			recipe:overrideIconTexture(texture)
		end
	end
	return true
end

function Fridge.configureContainerIcon()
	if not ContainerButtonIcons or not ContainerButtonIcons.fridge then return false end
	ContainerButtonIcons[Fridge.containerType] = ContainerButtonIcons.fridge
	return true
end

function Fridge.moveContents(source, destination)
	local items = source and source.getItems and source:getItems() or nil
	if not items or not destination or not destination.AddItem then return {} end
	local moved = {}
	while items:size() > 0 do
		local item = items:get(0)
		source:Remove(item)
		destination:AddItem(item)
		moved[#moved + 1] = item
	end
	return moved
end

function Fridge.syncAdded(container, items)
	if not sendAddItemToContainer then return end
	for _, item in ipairs(items) do sendAddItemToContainer(container, item) end
end

function Fridge.getCycleHours()
	local options = SandboxVars and SandboxVars.WaterPipes
	local index = math.floor(tonumber(options and options.MagicFridgeHarvestInterval)
		or Fridge.defaultCycleIndex)
	return (Fridge.cycleMinutes[index] or Fridge.cycleMinutes[Fridge.defaultCycleIndex]) / 60
end

local function clampProduceLimit(value)
	value = math.floor(tonumber(value) or Fridge.defaultProduceLimit)
	return math.max(-1, math.min(value, Fridge.capacity))
end

function Fridge.sanitizeSettings(settings)
	local result = {}
	if type(settings) ~= "table" then return result end
	local propsByCrop = farming_vegetableconf and farming_vegetableconf.props or nil
	local accepted = 0
	for cropType, value in pairs(settings) do
		if type(cropType) == "string" and type(value) == "table"
			and (not propsByCrop or propsByCrop[cropType]) and accepted < 256 then
			result[cropType] = {
				enabled = value.enabled ~= false,
				produceLimit = clampProduceLimit(value.produceLimit),
			}
			accepted = accepted + 1
		end
	end
	return result
end

function Fridge.getCropSetting(object, cropType)
	local modData = object and object.getModData and object:getModData() or nil
	local setting = modData and type(modData.magicFridgeSettings) == "table"
		and modData.magicFridgeSettings[cropType] or nil
	return {
		enabled = type(setting) ~= "table" or setting.enabled ~= false,
		produceLimit = type(setting) == "table"
			and clampProduceLimit(setting.produceLimit) or Fridge.defaultProduceLimit,
	}
end

local function globalSettings()
	return ModData and ModData.getOrCreate
		and ModData.getOrCreate(Fridge.settingsModDataKey) or nil
end

local function applySettings(object, enabled, settings, revision)
	local modData = object:getModData()
	modData.magicFridgeProductionEnabled = enabled
	modData.magicFridgeSettings = settings
	modData.magicFridgeSettingsRevision = revision
	if object.transmitModData then object:transmitModData() end
	return true
end

function Fridge.setObjectSettings(object, enabled, settings)
	if isClient and isClient() then return false end
	if not Fridge.isObject(object) or not object:getSquare()
		or type(enabled) ~= "boolean" then return false end
	local shared = globalSettings()
	return applySettings(object, enabled, Fridge.sanitizeSettings(settings),
		tonumber(shared and shared.revision) or 0)
end

function Fridge.setAllObjectSettings(enabled, settings)
	if (isClient and isClient()) or type(enabled) ~= "boolean" then return 0 end
	local sanitized = Fridge.sanitizeSettings(settings)
	local shared = globalSettings()
	local revision = (tonumber(shared and shared.revision) or 0) + 1
	if shared then
		shared.revision = revision
		shared.enabled = enabled
		shared.settings = sanitized
		if ModData.transmit then ModData.transmit(Fridge.settingsModDataKey) end
	end
	local updated = 0
	for object in pairs(Fridge.objects) do
		if object.getSquare and object:getSquare() then
			applySettings(object, enabled, Fridge.sanitizeSettings(sanitized), revision)
			updated = updated + 1
		end
	end
	return updated
end

function Fridge.applyGlobalSettings(object)
	if isClient and isClient() then return false end
	local shared = globalSettings()
	local revision = tonumber(shared and shared.revision)
	local objectRevision = tonumber(object:getModData().magicFridgeSettingsRevision) or 0
	if not revision or revision <= objectRevision then return false end
	return applySettings(object, shared.enabled ~= false,
		Fridge.sanitizeSettings(shared.settings), revision)
end

local function ensureSchedule(object, now)
	local modData = object:getModData()
	local cycleHours = Fridge.getCycleHours()
	if tonumber(modData.magicFridgeCycleHours) ~= cycleHours
		or tonumber(modData.magicFridgeNextHarvestHour) == nil then
		modData.magicFridgeCycleHours = cycleHours
		modData.magicFridgeNextHarvestHour = now + cycleHours
	end
	return modData, cycleHours
end

function Fridge.findItem(inventory, variantId)
	if not inventory or not inventory.getFirstTypeRecurse then return nil end
	if variantId then
		local variant = Fridge.getVariant(variantId)
		local item = inventory:getFirstTypeRecurse(variant.itemType)
			or inventory:getFirstTypeRecurse(variant.legacyItemType)
		if item then Fridge.prepareCarryItem(item) end
		return item
	end
	for _, id in ipairs(Fridge.variantOrder) do
		local variant = Fridge.variants[id]
		local item = inventory:getFirstTypeRecurse(variant.itemType)
			or inventory:getFirstTypeRecurse(variant.legacyItemType)
		if item then Fridge.prepareCarryItem(item) return item end
	end
	return nil
end

function Fridge.isObject(object)
	if not object or not object.getModData then return false end
	return object:getName() == Fridge.objectName
		or object:getModData().magicFridge == true
end

function Fridge.ensureContainer(object)
	if not Fridge.isObject(object) or not object.getSquare or not object:getSquare() then
		return nil
	end
	local container = object.getContainer and object:getContainer() or nil
	if not container then
		if not ItemContainer or not ItemContainer.new or not object.setContainer then return nil end
		container = ItemContainer.new(Fridge.containerType, object:getSquare(), object)
		if not container then return nil end
		object:setContainer(container)
	end
	-- The vanilla refrigerator sprite may initialize a normal "fridge"
	-- container before Lua runs. Re-tag that same container so its contents are
	-- preserved while the shared logical-capacity patch recognizes it.
	if container.getType and container.setType
		and container:getType() ~= Fridge.containerType then
		container:setType(Fridge.containerType)
	end
	local modData = object:getModData()
	if modData.magicFridgeCapacityVersion ~= 1 then
		if WaterPipeStorageCapacity.setPhysicalCapacity(container, 100) then
			modData.magicFridgeCapacityVersion = 1
		end
	end
	if container.setExplored then container:setExplored(true) end
	return container
end

function Fridge.findOnSquare(square)
	local objects = square and square.getObjects and square:getObjects() or nil
	if not objects then return nil end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if Fridge.isObject(object) then return object end
	end
	return nil
end

function Fridge.applyDisplaySprite(object)
	if not Fridge.isObject(object) or not object.setSprite or not getSprite then return false end
	local modData = object:getModData()
	local variant = Fridge.getVariant(modData.magicFridgeVariant)
	local spriteName = modData.magicFridgeNorth and variant.east or variant.south
	local sprite = getSprite(spriteName)
	if not sprite then return false end
	object:setSprite(sprite)
	return true
end

function Fridge.refillWater(object)
	if not Fridge.isObject(object) or not object.getFluidContainer
		or not object.addFluid or not FluidType or not FluidType.Water then return false end
	local container = object:getFluidContainer()
	if not container then return false end
	local amount = container:getAmount()
	local capacity = container:getCapacity()
	if capacity > amount then object:addFluid(FluidType.Water, capacity - amount) end
	return true
end

function Fridge.register(object)
	if not Fridge.isObject(object) or not object.getSquare or not object:getSquare() then
		return false
	end
	Fridge.objects[object] = true
	Fridge.applyGlobalSettings(object)
	Fridge.ensureContainer(object)
	Fridge.applyDisplaySprite(object)
	Fridge.refillWater(object)
	ensureSchedule(object, worldAgeHours())
	PowerPipe.syncObjectSource(object)
	WholeBuildingWater.syncSourceObject(object)
	return true
end

function Fridge.unregister(object)
	if not object then return false end
	Fridge.objects[object] = nil
	Fridge.freshnessCursors[object] = nil
	local square = object.getSquare and object:getSquare() or nil
	if square then
		PowerPipe.unregisterSourceAt(square:getX(), square:getY(), square:getZ())
	end
	WholeBuildingWater.unregisterSource(object)
	return true
end

function Fridge.createObject(square, north, variantId)
	if not square or not IsoThumpable or not IsoThumpable.new then return nil end
	local variant = Fridge.getVariant(variantId)
	local sourceSprite = WaterPipeSprite.supplyByPipeType.lineOption
	local object = IsoThumpable.new(getCell(), square, sourceSprite, north == true, {})
	if not object then return nil end
	if object.removeAllContainers then object:removeAllContainers() end
	object:setName(Fridge.objectName)
	object:setCanPassThrough(false)
	object:setBlockAllTheSquare(true)
	object:setCanBarricade(false)
	object:setIsDismantable(false)
	object:setIsThumpable(false)
	object:setUsesExternalWaterSource(false)
	object:setMaxHealth(1000)
	object:setHealth(1000)
	local modData = object:getModData()
	modData.magicFridge = true
	modData.magicFridgeVariant = variant.id
	modData.magicFridgeNorth = north == true
	modData.powerSupplyPipe = true
	modData.waterSupplyPipe = true
	modData.wholeBuildingWater = true
	modData.canBeWaterPiped = false
	modData.magicFridgeCycleHours = Fridge.getCycleHours()
	modData.magicFridgeNextHarvestHour = worldAgeHours() + modData.magicFridgeCycleHours
	square:AddSpecialObject(object)
	Fridge.register(object)
	return object
end

local function seedMap()
	if Fridge.seedMap then return Fridge.seedMap end
	local map, cropTypes = {}, {}
	for cropType, props in pairs(farming_vegetableconf and farming_vegetableconf.props or {}) do
		if props and props.vegetableName then cropTypes[#cropTypes + 1] = cropType end
	end
	table.sort(cropTypes)
	for _, cropType in ipairs(cropTypes) do
		local props = farming_vegetableconf.props[cropType]
		local seeds = type(props.seedTypes) == "table" and props.seedTypes
			or (props.seedName and { props.seedName } or {})
		for _, fullType in ipairs(seeds) do
			if not map[fullType] then
				map[fullType] = { cropType = cropType, props = props }
			end
		end
	end
	Fridge.seedMap = map
	return map
end

local function usableSeed(item)
	if not item or not instanceof or not instanceof(item, "Food") then return true end
	return not (item.isRotten and item:isRotten())
		and not (item.isCooked and item:isCooked())
		and not (item.isBurnt and item:isBurnt())
end

local function preserveSeeds()
	local options = SandboxVars and SandboxVars.WaterPipes
	return not options or options.MagicFridgePreserveSeeds ~= false
end

function Fridge.processSeeds(object)
	local modData = object and object.getModData and object:getModData() or nil
	if not modData or modData.magicFridgeProductionEnabled == false then return 0, 0 end
	local container = Fridge.ensureContainer(object)
	local items = container and container.getItems and container:getItems() or nil
	if not items or not items.size or not items.get then return 0, 0 end
	local converted, produced = 0, 0
	local originalCount = items:size()
	local counts = {}
	for i = 0, originalCount - 1 do
		local fullType = itemFullType(items:get(i))
		if fullType then counts[fullType] = (counts[fullType] or 0) + 1 end
	end
	local crops = seedMap()
	for i = originalCount - 1, 0, -1 do
		local item = items:get(i)
		local crop = crops[itemFullType(item)]
		local setting = crop and Fridge.getCropSetting(object, crop.cropType) or nil
		local props = crop and crop.props or nil
		if props and setting.enabled and usableSeed(item) then
			local minimum = tonumber(props.minVeg) or 1
			local maximum = tonumber(props.maxVeg) or minimum
			local count = math.max(1, math.floor((minimum + maximum) / 2))
			if setting.produceLimit >= 0 then
				count = math.min(count, math.max(
					0, setting.produceLimit - (counts[props.vegetableName] or 0)
				))
			end
			local added = count > 0 and container:AddItems(props.vegetableName, count) or nil
			local addedCount = added and added.size and added:size() or count
			if addedCount > 0 then
				counts[props.vegetableName] = (counts[props.vegetableName] or 0) + addedCount
				if not preserveSeeds() then
					container:Remove(item)
					if sendRemoveItemFromContainer then
						sendRemoveItemFromContainer(container, item)
					end
				end
				if sendAddItemsToContainer then sendAddItemsToContainer(container, added) end
				converted = converted + 1
				produced = produced + addedCount
			end
		end
	end
	return converted, produced
end

function Fridge.preserveContents(object)
	local container = Fridge.ensureContainer(object)
	local items = container and container.getItems and container:getItems() or nil
	if not items or not items.size or not items.get then return 0 end
	local count = items:size()
	if count == 0 then Fridge.freshnessCursors[object] = 0 return 0 end
	local cursor = math.max(0, tonumber(Fridge.freshnessCursors[object]) or 0) % count
	local limit = math.min(count, Fridge.maxFreshnessItemsPerPass)
	local preserved = 0
	for offset = 0, limit - 1 do
		local item = items:get((cursor + offset) % count)
		if WaterPipeStorageFreshness.preserveItem(item) then preserved = preserved + 1 end
	end
	Fridge.freshnessCursors[object] = (cursor + limit) % math.max(1, count)
	return preserved
end

function Fridge.process()
	if isClient and isClient() then return end
	local now = worldAgeHours()
	for object in pairs(Fridge.objects) do
		if object.getSquare and object:getSquare() then
			Fridge.refillWater(object)
			Fridge.preserveContents(object)
			local modData, cycleHours = ensureSchedule(object, now)
			if now >= (tonumber(modData.magicFridgeNextHarvestHour) or now) then
				Fridge.processSeeds(object)
				modData.magicFridgeNextHarvestHour = now + cycleHours
				if object.transmitModData then object:transmitModData() end
			end
		else
			Fridge.unregister(object)
		end
	end
end

function Fridge.pickUp(object, player)
	if not Fridge.isObject(object) or not player then return false end
	local container = Fridge.ensureContainer(object)
	local square = object:getSquare()
	if not square then return false end
	local variant = Fridge.getVariant(object:getModData().magicFridgeVariant)
	local carried = instanceItem and instanceItem(variant.itemType) or nil
	local carriedInventory = Fridge.prepareCarryItem(carried)
	local playerInventory = player.getInventory and player:getInventory() or nil
	if not carriedInventory or not playerInventory then return false end
	Fridge.moveContents(container, carriedInventory)
	local carriedData = carried:getModData()
	local objectData = object:getModData()
	carriedData.magicFridgeNextHarvestHour = objectData.magicFridgeNextHarvestHour
	carriedData.magicFridgeCycleHours = objectData.magicFridgeCycleHours
	carriedData.magicFridgeProductionEnabled = objectData.magicFridgeProductionEnabled
	carriedData.magicFridgeSettings = objectData.magicFridgeSettings
	carriedData.magicFridgeSettingsRevision = objectData.magicFridgeSettingsRevision
	playerInventory:AddItem(carried)
	if sendAddItemToContainer then sendAddItemToContainer(playerInventory, carried) end
	Fridge.unregister(object)
	square:transmitRemoveItemFromSquare(object)
	square:RemoveTileObject(object)
	return true
end

function Fridge.onGridSquareLoaded(square)
	local object = Fridge.findOnSquare(square)
	if object then Fridge.register(object) end
end

function Fridge.onObjectAdded(object)
	if Fridge.isObject(object) then Fridge.register(object) end
end

function Fridge.onObjectAboutToBeRemoved(object)
	if Fridge.isObject(object) then Fridge.unregister(object) end
end

function Fridge.onWaterAmountChange(object)
	if Fridge.isObject(object) then Fridge.refillWater(object) end
end

if Events then
	if Events.OnGameBoot then
		Events.OnGameBoot.Add(Fridge.configureIcons)
		Events.OnGameBoot.Add(Fridge.configureContainerIcon)
	end
	if Events.OnGameStart then
		Events.OnGameStart.Add(Fridge.configureIcons)
		Events.OnGameStart.Add(Fridge.configureContainerIcon)
	end
	if Events.LoadGridsquare then Events.LoadGridsquare.Add(Fridge.onGridSquareLoaded) end
	if Events.OnObjectAdded then Events.OnObjectAdded.Add(Fridge.onObjectAdded) end
	if Events.OnObjectAboutToBeRemoved then
		Events.OnObjectAboutToBeRemoved.Add(Fridge.onObjectAboutToBeRemoved)
	end
	if Events.OnWaterAmountChange then Events.OnWaterAmountChange.Add(Fridge.onWaterAmountChange) end
	if Events.EveryTenMinutes then Events.EveryTenMinutes.Add(Fridge.process) end
end

Fridge.configureIcons()
Fridge.configureContainerIcon()

return Fridge
