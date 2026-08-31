WaterPipeSprite = WaterPipeSprite or {}

WaterPipeSprite.tilesetName = "infinite_irrigation_pipes_01"

-- The original release rendered ground pipes directly from these PNG files.
-- Keep that path available as a client-side display mode: unlike the
-- registered tiles below, these sprites do not own RenderLayer=Floor.
WaterPipeSprite.textureByPipeType = {
	lineOption = "media/textures/Item_PipeSE.png",
	lineOption2 = "media/textures/Item_PipeNorth.png",
	crossOption = "media/textures/Item_PipeCross.png",
	neOption = "media/textures/Item_PipeCornerNE.png",
	nwOption = "media/textures/Item_PipeCornerNW.png",
	seOption = "media/textures/Item_PipeCornerSE.png",
	swOption = "media/textures/Item_PipeCornerSW.png",
	tnOption = "media/textures/Item_PipeTN.png",
	tsOption = "media/textures/Item_PipeTS.png",
	teOption = "media/textures/Item_PipeTE.png",
	twOption = "media/textures/Item_PipeTW.png",
}

WaterPipeSprite.byPipeType = {
	lineOption = WaterPipeSprite.tilesetName .. "_0",
	lineOption2 = WaterPipeSprite.tilesetName .. "_1",
	crossOption = WaterPipeSprite.tilesetName .. "_2",
	neOption = WaterPipeSprite.tilesetName .. "_3",
	nwOption = WaterPipeSprite.tilesetName .. "_4",
	seOption = WaterPipeSprite.tilesetName .. "_5",
	swOption = WaterPipeSprite.tilesetName .. "_6",
	tnOption = WaterPipeSprite.tilesetName .. "_7",
	tsOption = WaterPipeSprite.tilesetName .. "_8",
	teOption = WaterPipeSprite.tilesetName .. "_9",
	twOption = WaterPipeSprite.tilesetName .. "_10",
	verticalNorthOption = WaterPipeSprite.tilesetName .. "_22",
	verticalEastOption = WaterPipeSprite.tilesetName .. "_23",
	verticalSouthOption = WaterPipeSprite.tilesetName .. "_24",
	verticalWestOption = WaterPipeSprite.tilesetName .. "_25",
	-- Compatibility for development saves made with the first single-riser draft.
	verticalOption = WaterPipeSprite.tilesetName .. "_22",
}

WaterPipeSprite.supplyByPipeType = {
	lineOption = WaterPipeSprite.tilesetName .. "_11",
	lineOption2 = WaterPipeSprite.tilesetName .. "_12",
	crossOption = WaterPipeSprite.tilesetName .. "_13",
	neOption = WaterPipeSprite.tilesetName .. "_14",
	nwOption = WaterPipeSprite.tilesetName .. "_15",
	seOption = WaterPipeSprite.tilesetName .. "_16",
	swOption = WaterPipeSprite.tilesetName .. "_17",
	tnOption = WaterPipeSprite.tilesetName .. "_18",
	tsOption = WaterPipeSprite.tilesetName .. "_19",
	teOption = WaterPipeSprite.tilesetName .. "_20",
	twOption = WaterPipeSprite.tilesetName .. "_21",
	verticalNorthOption = WaterPipeSprite.tilesetName .. "_26",
	verticalEastOption = WaterPipeSprite.tilesetName .. "_27",
	verticalSouthOption = WaterPipeSprite.tilesetName .. "_28",
	verticalWestOption = WaterPipeSprite.tilesetName .. "_29",
	verticalOption = WaterPipeSprite.tilesetName .. "_26",
}

WaterPipeSprite.byTexture = {
	["media/textures/Item_PipeSE.png"] = WaterPipeSprite.byPipeType.lineOption,
	["media/textures/Item_PipeNorth.png"] = WaterPipeSprite.byPipeType.lineOption2,
	["media/textures/Item_PipeCross.png"] = WaterPipeSprite.byPipeType.crossOption,
	["media/textures/Item_PipeCornerNE.png"] = WaterPipeSprite.byPipeType.neOption,
	["media/textures/Item_PipeCornerNW.png"] = WaterPipeSprite.byPipeType.nwOption,
	["media/textures/Item_PipeCornerSE.png"] = WaterPipeSprite.byPipeType.seOption,
	["media/textures/Item_PipeCornerSW.png"] = WaterPipeSprite.byPipeType.swOption,
	["media/textures/Item_PipeTN.png"] = WaterPipeSprite.byPipeType.tnOption,
	["media/textures/Item_PipeTS.png"] = WaterPipeSprite.byPipeType.tsOption,
	["media/textures/Item_PipeTE.png"] = WaterPipeSprite.byPipeType.teOption,
	["media/textures/Item_PipeTW.png"] = WaterPipeSprite.byPipeType.twOption,
	["media/textures/Item_PipeVerticalN.png"] = WaterPipeSprite.byPipeType.verticalNorthOption,
	["media/textures/Item_PipeVerticalE.png"] = WaterPipeSprite.byPipeType.verticalEastOption,
	["media/textures/Item_PipeVerticalS.png"] = WaterPipeSprite.byPipeType.verticalSouthOption,
	["media/textures/Item_PipeVerticalW.png"] = WaterPipeSprite.byPipeType.verticalWestOption,
}

WaterPipeSprite.groundLayerEnabled = WaterPipeSprite.groundLayerEnabled ~= false
WaterPipeSprite.displayObjects = WaterPipeSprite.displayObjects or {}
WaterPipeSprite.directSprites = WaterPipeSprite.directSprites or {
	irrigation = {},
	supply = {},
}

local function isVerticalPipeType(pipeType)
	return pipeType == "verticalOption"
		or pipeType == "verticalNorthOption"
		or pipeType == "verticalEastOption"
		or pipeType == "verticalSouthOption"
		or pipeType == "verticalWestOption"
end

local function isSupplyObject(obj, modData)
	if modData and modData["waterSupplyPipe"] then return true end
	if not obj or not obj.getName then return false end
	return obj:getName() == "WaterSupplyPipe"
end

function WaterPipeSprite.isDisplayPipeObject(obj)
	if not obj or not obj.getModData then return false end
	local modData = obj:getModData()
	if modData and modData["pipeType"]
		and (modData["infinite"] or modData["waterSupplyPipe"]
			or modData["pipeDisabled"]) then return true end
	if not obj.getName then return false end
	local name = obj:getName()
	return name == "WaterPipe" or name == "WaterSupplyPipe"
		or name == "WaterDisabledPipe"
end

local function addNativeWaterProperties(sprite)
	if not sprite or not sprite.getProperties then return end
	local properties = sprite:getProperties()
	if not properties then return end
	properties:set("waterAmount", "10000")
	properties:set("waterMaxAmount", "10000")
	if IsoFlagType and IsoFlagType.waterPiped then
		properties:set(IsoFlagType.waterPiped)
	else
		properties:set("waterPiped", "")
	end
	if properties.CreateKeySet then properties:CreateKeySet() end
end

-- Build one reusable direct-texture sprite for each shape and mode.  Supply
-- sprites are separate so the vanilla waterPiped property never leaks onto an
-- irrigation-only sprite that happens to use the same PNG.
function WaterPipeSprite.getDirectSprite(pipeType, supply)
	if isVerticalPipeType(pipeType) then return nil end
	local texture = WaterPipeSprite.textureByPipeType[pipeType]
		or WaterPipeSprite.textureByPipeType.lineOption
	local cache = supply and WaterPipeSprite.directSprites.supply
		or WaterPipeSprite.directSprites.irrigation
	if cache[pipeType] then return texture, cache[pipeType] end
	if not IsoSprite or not IsoSprite.new then return nil, nil end

	local sprite = IsoSprite.new()
	if not sprite then return nil, nil end
	sprite:LoadSingleTexture(texture)
	if sprite.setName then
		sprite:setName("WaterPipeDirect_" .. (supply and "Supply_" or "") .. pipeType)
	end
	if supply then addNativeWaterProperties(sprite) end
	cache[pipeType] = sprite
	return texture, sprite
end

function WaterPipeSprite.getFloorSprite(sourceSprite, pipeType)
	return WaterPipeSprite.byPipeType[pipeType] or WaterPipeSprite.byTexture[sourceSprite]
end

function WaterPipeSprite.getObjectSpriteName(obj)
	if not obj then return nil end

	local sprite = obj:getSprite()
	if sprite and sprite:getName() then
		return sprite:getName()
	end

	return obj:getSpriteName() or obj:getTile()
end

function WaterPipeSprite.getRegisteredFloorSprite(sourceSprite, pipeType)
	local spriteName = WaterPipeSprite.getFloorSprite(sourceSprite, pipeType)
	if not spriteName or type(getSprite) ~= "function" then return nil, nil end

	return spriteName, getSprite(spriteName)
end

function WaterPipeSprite.getRegisteredSupplySprite(pipeType)
	if type(getSprite) ~= "function" then return nil, nil end
	local spriteName = WaterPipeSprite.supplyByPipeType[pipeType]
		or WaterPipeSprite.supplyByPipeType.lineOption
	return spriteName, getSprite(spriteName)
end

-- Convert old direct-texture objects to their registered sprite.  Ground pipes
-- own RenderLayer=Floor in the tile definition; the vertical riser deliberately
-- remains a normal world-sorted object so characters render in front of it.
function WaterPipeSprite.applyFloorSprite(obj)
	if not obj or not obj.setSprite then return false end

	local modData = obj:getModData()
	-- Hybrid supply/irrigation pipes intentionally retain the separate sprite
	-- that owns the native water properties.
	if modData and modData["waterSupplyPipe"] then return false end
	local sourceSprite = WaterPipeSprite.getObjectSpriteName(obj)
	local targetName, targetSprite = WaterPipeSprite.getRegisteredFloorSprite(
		sourceSprite,
		modData and modData["pipeType"]
	)
	if not targetSprite or sourceSprite == targetName then return false end

	obj:setSprite(targetSprite)
	if obj.setTile then
		obj:setTile(targetName)
	end
	return true
end

-- Change only the local display sprite.  The saved/networked object continues
-- to use the registered tile definition, so each player may choose a display
-- mode without changing the server or another client's preference.
function WaterPipeSprite.applyDisplaySprite(obj)
	if not obj or not obj.setSprite or not obj.getModData then return false end
	local modData = obj:getModData()
	local pipeType = modData and modData["pipeType"]
	if not pipeType then return false end
	local supply = isSupplyObject(obj, modData)
	local targetName, targetSprite

	-- Vertical risers already use normal world sorting and therefore need no
	-- alternate display sprite.
	if isVerticalPipeType(pipeType) or WaterPipeSprite.groundLayerEnabled then
		if supply then
			targetName, targetSprite = WaterPipeSprite.getRegisteredSupplySprite(pipeType)
		else
			targetName, targetSprite = WaterPipeSprite.getRegisteredFloorSprite(nil, pipeType)
		end
	else
		targetName, targetSprite = WaterPipeSprite.getDirectSprite(pipeType, supply)
	end
	if not targetSprite then return false end

	local currentSprite = obj:getSprite()
	if currentSprite == targetSprite then return false end
	obj:setSprite(targetSprite)
	return true
end

function WaterPipeSprite.registerDisplayObject(obj)
	if not obj then return end
	WaterPipeSprite.displayObjects[obj] = true
	WaterPipeSprite.applyDisplaySprite(obj)
end

function WaterPipeSprite.registerSquareObjects(square)
	if not square or not square.getObjects then return end
	local objects = square:getObjects()
	if not objects then return end
	for index = 0, objects:size() - 1 do
		local obj = objects:get(index)
		if WaterPipeSprite.isDisplayPipeObject(obj) then
			WaterPipeSprite.registerDisplayObject(obj)
		end
	end
end

function WaterPipeSprite.unregisterDisplayObject(obj)
	if obj then WaterPipeSprite.displayObjects[obj] = nil end
end

function WaterPipeSprite.refreshDisplayObjects()
	for obj in pairs(WaterPipeSprite.displayObjects) do
		if obj and obj.getSquare and obj:getSquare() then
			WaterPipeSprite.applyDisplaySprite(obj)
		else
			WaterPipeSprite.displayObjects[obj] = nil
		end
	end
end

function WaterPipeSprite.setGroundLayerEnabled(enabled)
	WaterPipeSprite.groundLayerEnabled = enabled == true
	-- Existing irrigation pipes have persisted coordinates even when their old
	-- world objects were loaded before OnObjectAdded became available.  Resolve
	-- only those known coordinates here; supply-only pipes are picked up by the
	-- per-square load event below.  This is a one-shot option change, not a scan
	-- performed during normal gameplay.
	if WaterPipe and WaterPipe.pipes and type(getCell) == "function" then
		local cell = getCell()
		if cell then
			for _, pipe in ipairs(WaterPipe.pipes) do
				local square = cell:getGridSquare(pipe.x, pipe.y, pipe.z)
				if square then WaterPipeSprite.registerSquareObjects(square) end
			end
		end
	end
	WaterPipeSprite.refreshDisplayObjects()
end

return WaterPipeSprite
