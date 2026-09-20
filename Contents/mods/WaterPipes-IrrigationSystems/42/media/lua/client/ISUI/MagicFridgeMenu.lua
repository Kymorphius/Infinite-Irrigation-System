require "BuildingObjects/zMagicFridge"
require "TimedActions/removeMagicFridgeAction"
require "Moveables/ISMoveableSpriteProps"

-- The display uses a vanilla refrigerator sprite, but pickup must go through
-- the magic-fridge action so its identity is retained instead of becoming an
-- ordinary white-fridge item.
if ISMoveableSpriteProps and not ISMoveableSpriteProps.__MagicFridgeCanPickUp then
	local originalCanPickUp = ISMoveableSpriteProps.canPickUpMoveable
	ISMoveableSpriteProps.__MagicFridgeCanPickUp = originalCanPickUp
	function ISMoveableSpriteProps:canPickUpMoveable(character, square, object)
		if MagicFridge.isObject(object) then return false end
		return originalCanPickUp(self, character, square, object)
	end
end

if ISMoveableSpriteProps and not ISMoveableSpriteProps.__MagicFridgeCanPlace then
	local originalCanPlace = ISMoveableSpriteProps.canPlaceMoveable
	ISMoveableSpriteProps.__MagicFridgeCanPlace = originalCanPlace
	function ISMoveableSpriteProps:canPlaceMoveable(character, square, item)
		if MagicFridge.isItem(item) then return false end
		return originalCanPlace(self, character, square, item)
	end
end

local function placeFridge(_, player, item)
	local character = getSpecificPlayer(player)
	getCell():setDrag(MagicFridgeBuild:new(player, item), character:getPlayerNum())
end

local function removeFridge(_, player, square)
	local character = getSpecificPlayer(player)
	if luautils.walkAdj(character, square) then
		ISTimedActionQueue.add(removeMagicFridgeAction:new(character, square))
	end
end

local function addMenu(player, context, worldObjects)
	local character = getSpecificPlayer(player)
	local inventory = character and character:getInventory() or nil
	if not inventory then return end
	local placed, square
	for _, worldObject in ipairs(worldObjects) do
		square = worldObject:getSquare()
		placed = MagicFridge.findOnSquare(square)
		if placed then break end
	end
	if placed then
		context:addOption(
			getText("ContextMenu_MagicFridge_PickUp"), worldObjects,
			removeFridge, player, square
		)
		return
	end
	for _, id in ipairs(MagicFridge.variantOrder) do
		local item = MagicFridge.findItem(inventory, id)
		if item then
			local name = item.getDisplayName and item:getDisplayName() or id
			context:addOption(
				getText("ContextMenu_MagicFridge_Place") .. ": " .. name,
				worldObjects, placeFridge, player, item
			)
		end
	end
end

Events.OnFillWorldObjectContextMenu.Add(addMenu)
