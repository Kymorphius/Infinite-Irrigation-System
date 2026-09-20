require "BuildingObjects/ISBuildingObject"
require "WaterPipe/MagicFridge"

MagicFridgeBuild = ISBuildingObject:derive("MagicFridgeBuild")

function MagicFridgeBuild:getCharacter()
	return self.character or (getSpecificPlayer and getSpecificPlayer(self.player))
end

function MagicFridgeBuild:refreshItem(character)
	character = character or self:getCharacter()
	local inventory = character and character:getInventory() or nil
	if not inventory then self.item = nil return nil, nil end
	if self.item and inventory:containsRecursive(self.item) then
		return self.item, self.item:getContainer() or inventory
	end
	self.item = MagicFridge.findItem(inventory, self.variant and self.variant.id)
	return self.item, self.item and (self.item:getContainer() or inventory) or nil
end

function MagicFridgeBuild:create(x, y, z, north)
	local character = self:getCharacter()
	local item, container = self:refreshItem(character)
	if not character or not item then return false end
	local square = getWorld():getCell():getGridSquare(x, y, z)
	local object = MagicFridge.createObject(square, north, self.variant.id)
	if not object then return false end
	local itemData = item.getModData and item:getModData() or nil
	local objectData = object:getModData()
	if itemData and tonumber(itemData.magicFridgeNextHarvestHour) then
		objectData.magicFridgeNextHarvestHour = itemData.magicFridgeNextHarvestHour
		objectData.magicFridgeCycleHours = itemData.magicFridgeCycleHours
	end
	if itemData then
		objectData.magicFridgeProductionEnabled = itemData.magicFridgeProductionEnabled
		objectData.magicFridgeSettings = itemData.magicFridgeSettings
		objectData.magicFridgeSettingsRevision = itemData.magicFridgeSettingsRevision
	end
	MagicFridge.applyGlobalSettings(object)
	local destination = MagicFridge.ensureContainer(object)
	object:transmitCompleteItemToClients()
	local moved = MagicFridge.moveContents(MagicFridge.prepareCarryItem(item), destination)
	MagicFridge.syncAdded(destination, moved)
	character:removeFromHands(item)
	container:Remove(item)
	if sendRemoveItemFromContainer then
		sendRemoveItemFromContainer(container, item)
	end
	return true
end

function MagicFridgeBuild:isValid(square)
	if not square or not self:refreshItem() or MagicFridge.findOnSquare(square) then return false end
	return not square.isFree or square:isFree(false)
end

function MagicFridgeBuild:render(x, y, z, square, north)
	ISBuildingObject.render(self, x, y, z, square, north)
end

function MagicFridgeBuild:new(player, item)
	local object = {}
	setmetatable(object, self)
	self.__index = self
	object:init()
	object.variant = MagicFridge.getVariantForItem(item)
	object:setSprite(object.variant.south)
	object.northSprite = object.variant.east
	object.name = "Magic Fridge"
	object.dismantable = false
	object.canBarricade = false
	object.blockAllTheSquare = true
	object.canPassThrough = false
	object.maxTime = 10
	object.isContainer = true
	object.isThumpable = false
	object.noNeedHammer = true
	object.player = player
	object.item = item
	return object
end

return MagicFridgeBuild
