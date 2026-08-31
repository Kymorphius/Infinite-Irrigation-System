
---- Garden Hoses By Kyun, thanks to Robert Johnson for it's rain collector barrel and farming mod (among others !)

require "BuildingObjects/zpipe"
require "BuildingObjects/zwaterSupplyPipe"
require "WaterPipe/PowerPipe"
require "WaterPipe/WholeBuildingWater"
require "WaterPipe/AutoFarmSettingsUI"

WaterPipeMenu = {};
WaterPipeMenu.info = nil;
WaterPipeMenu.currentBarrel = nil;
WaterPipeMenu.currentPipe = nil;
require "WaterPipe/WaterPipeNetworksUI"
require "TimedActions/removeWaterSupplyPipeAction"

local irrigationRangeSizes = { 1, 3, 5, 7, 9, 11, 15 }
local function isValidIrrigationRange(size)
	size = tonumber(size)
	for _, validSize in ipairs(irrigationRangeSizes) do
		if size == validSize then return true end
	end
	return false
end

local function getGlobalIrrigationRange()
	local selected = SandboxVars and SandboxVars.WaterPipes
		and tonumber(SandboxVars.WaterPipes.IrrigationRange) or 2
	return irrigationRangeSizes[math.floor(selected)] or 3
end

local function getGlobalAutoTillEnabled()
	return SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.InfiniteAutoPlow == true
end

local function getShowCleanupEnabled()
	return SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.ShowCleanup == true
end

local function getAutoFarmingModuleEnabled()
	return SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.EnableAutoFarming == true
end

local function getBooleanOrDefault(value, defaultValue)
	if type(value) == "boolean" then return value end
	return defaultValue
end

local function addStatusOption(menu, enabled, name, worldobjects, callback, ...)
	local option = menu:addOption(name, worldobjects, callback, ...)
	if enabled then
		-- ISContextMenu renders checkMark with the game's positive-highlight
		-- color, making enabled states green instead of a flat white texture.
		option.checkMark = true
	else
		option.iconTexture = getTexture("media/ui/inventoryPanes/Tickbox_Cross.png")
	end
	return option
end

function WaterPipeMenu.addPlacedModeSwitches(context, menu, worldobjects, player, square, pipeObject)
	local mode = WaterSupplyPipe.getPlacedMode(pipeObject)
	if not mode then return end
	local supplyEnabled = mode == "supply" or mode == "both"
	local irrigationEnabled = mode == "irrigation" or mode == "both"
	local powerEnabled = PowerPipe.isObjectEnabled(pipeObject)
	local modData = pipeObject:getModData()
	local defaultFarmEnabled = irrigationEnabled
	local careEnabled = getBooleanOrDefault(modData["careEnabled"], defaultFarmEnabled)
	local fertilizationEnabled = getBooleanOrDefault(
		modData["fertilizeEnabled"], defaultFarmEnabled
	)
	local cleanupEnabled = getBooleanOrDefault(modData["cleanupEnabled"], false)
	local cleanupShrunkFarmArea = getBooleanOrDefault(
		modData["cleanupShrunkFarmArea"], false
	)
	local autoSowEnabled = getBooleanOrDefault(modData["autoSowEnabled"], true)
	local autoHarvestEnabled = getBooleanOrDefault(modData["autoHarvestEnabled"], true)
	local autoFarmingModuleEnabled = getAutoFarmingModuleEnabled()
	local autoTillOverride = modData["autoTillOverride"]
	if type(autoTillOverride) ~= "boolean" then autoTillOverride = nil end
	local configuredAutoTillEnabled = autoTillOverride
	if configuredAutoTillEnabled == nil then
		configuredAutoTillEnabled = getGlobalAutoTillEnabled()
	end
	local farmingAllEnabled = irrigationEnabled and configuredAutoTillEnabled
		and careEnabled and fertilizationEnabled
		and (not autoFarmingModuleEnabled
			or (autoSowEnabled and autoHarvestEnabled))
	local farmingAllDisabled = not irrigationEnabled and not configuredAutoTillEnabled
		and not careEnabled and not fertilizationEnabled
		and (not autoFarmingModuleEnabled
			or (not autoSowEnabled and not autoHarvestEnabled))
	local farmingOption = nil
	if farmingAllEnabled then
		farmingOption = addStatusOption(
			menu, true, getText("ContextMenu_WaterPipe_FarmingOpen"),
			worldobjects, WaterPipeMenu.onSetPlacedPipeFarming,
			player, square, false
		)
	elseif farmingAllDisabled then
		farmingOption = addStatusOption(
			menu, false, getText("ContextMenu_WaterPipe_FarmingClosed"),
			worldobjects, WaterPipeMenu.onSetPlacedPipeFarming,
			player, square, true
		)
	else
		farmingOption = menu:addOption(
			getText("ContextMenu_WaterPipe_FarmingPartial"),
			worldobjects, WaterPipeMenu.onSetPlacedPipeFarming,
			player, square, true
		)
		farmingOption.iconTexture = getTexture(
			"media/ui/Icon_RecipeGroup_Partial_48x48.png"
		)
		farmingOption.color = { r = 0.32, g = 0.62, b = 0.92 }
	end

	-- Keep the most common placed-pipe controls flat and ordered.  A click on
	-- the status row toggles that function directly.
	addStatusOption(menu, irrigationEnabled,
		getText(irrigationEnabled
			and "ContextMenu_WaterPipe_IrrigationOpen"
			or "ContextMenu_WaterPipe_IrrigationClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeMode,
		player,
		square,
		WaterSupplyPipe.getModeAfterIrrigationToggle(mode)
	)

	addStatusOption(menu, configuredAutoTillEnabled,
		getText(configuredAutoTillEnabled
			and "ContextMenu_WaterPipe_AutoTillOpen"
			or "ContextMenu_WaterPipe_AutoTillClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeAutoTill,
		player,
		square,
		configuredAutoTillEnabled and "disabled" or "enabled"
	)

	addStatusOption(menu, careEnabled,
		getText(careEnabled
			and "ContextMenu_WaterPipe_CareOpen"
			or "ContextMenu_WaterPipe_CareClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeCare,
		player,
		square,
		not careEnabled
	)

	addStatusOption(menu, fertilizationEnabled,
		getText(fertilizationEnabled
			and "ContextMenu_WaterPipe_FertilizationOpen"
			or "ContextMenu_WaterPipe_FertilizationClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeFertilization,
		player,
		square,
		not fertilizationEnabled
	)

	if autoFarmingModuleEnabled then
		addStatusOption(menu, autoSowEnabled,
		getText(autoSowEnabled
			and "ContextMenu_WaterPipe_AutoSowOpen"
			or "ContextMenu_WaterPipe_AutoSowClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeAutoSow,
		player,
		square,
		not autoSowEnabled
	)

		addStatusOption(menu, autoHarvestEnabled,
		getText(autoHarvestEnabled
			and "ContextMenu_WaterPipe_AutoHarvestOpen"
			or "ContextMenu_WaterPipe_AutoHarvestClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeAutoHarvest,
		player,
		square,
		not autoHarvestEnabled
	)

		local autoFarmSettingsOption = menu:addOption(
		getText("ContextMenu_WaterPipe_AutoFarmSettings"),
		worldobjects,
		WaterPipeMenu.onOpenAutoFarmSettings,
		player,
		pipeObject
	)
		autoFarmSettingsOption.iconTexture = getTexture(
			"media/ui/inventoryPanes/Button_Settings.png"
		)
	end

	if getShowCleanupEnabled() then
		addStatusOption(menu, cleanupEnabled,
			getText(cleanupEnabled
				and "ContextMenu_WaterPipe_CleanupOpen"
				or "ContextMenu_WaterPipe_CleanupClosed"),
			worldobjects,
			WaterPipeMenu.onSetPlacedPipeCleanup,
			player,
			square,
			not cleanupEnabled
		)
	end

	addStatusOption(menu, powerEnabled,
		getText(powerEnabled
			and "ContextMenu_WaterPipe_PowerOpen"
			or "ContextMenu_WaterPipe_PowerClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipePower,
		player,
		square,
		not powerEnabled
	)

	addStatusOption(menu, supplyEnabled,
		getText(supplyEnabled
			and "ContextMenu_WaterPipe_WaterSupplyOpen"
			or "ContextMenu_WaterPipe_WaterSupplyClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeMode,
		player,
		square,
		WaterSupplyPipe.getModeAfterSupplyToggle(mode)
	)

	local wholeBuildingWater = supplyEnabled
		and modData["wholeBuildingWater"] == true
	local wholeBuildingOption = addStatusOption(menu, wholeBuildingWater,
		getText(wholeBuildingWater
			and "ContextMenu_WaterPipe_WholeBuildingWaterOpen"
			or "ContextMenu_WaterPipe_WholeBuildingWaterClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeWholeBuildingWater,
		player,
		square,
		not wholeBuildingWater
	)
	wholeBuildingOption.notAvailable = not supplyEnabled
	if ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
		local tooltip = ISWorldObjectContextMenu.addToolTip()
		tooltip.description = getText("ContextMenu_WaterPipe_WholeBuildingWaterTooltip")
		wholeBuildingOption.toolTip = tooltip
	end

	local customRange = tonumber(pipeObject:getModData()["irrigationRange"])
	if not isValidIrrigationRange(customRange) then customRange = nil end
	local globalRange = getGlobalIrrigationRange()
	local effectiveRange = customRange or globalRange
	local rangeMenuOption = menu:addOption(getText(
		"ContextMenu_WaterPipe_RangeCurrent",
		getText("ContextMenu_WaterPipe_IrrigationRange" .. tostring(effectiveRange))
	))
	rangeMenuOption.checkMark = true
	local rangeMenu = menu:getNew(menu)
	context:addSubMenu(rangeMenuOption, rangeMenu)
	local followGlobal = rangeMenu:addOption(
		getText(
			"ContextMenu_WaterPipe_IrrigationRangeGlobal",
			getText("ContextMenu_WaterPipe_IrrigationRange" .. tostring(globalRange))
		),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeIrrigationRange,
		player,
		square,
		0
	)
	followGlobal.checkMark = customRange == nil
	for _, rangeSize in ipairs(irrigationRangeSizes) do
		local rangeOption = rangeMenu:addOption(
			getText("ContextMenu_WaterPipe_IrrigationRange" .. tostring(rangeSize)),
			worldobjects,
			WaterPipeMenu.onSetPlacedPipeIrrigationRange,
			player,
			square,
			rangeSize
		)
		rangeOption.checkMark = customRange == rangeSize
	end

	-- Keep this destructive switch at the bottom of the range picker, after all
	-- range choices, so it is visible without interrupting the size list.
	local shrinkCleanupOption = addStatusOption(
		rangeMenu,
		cleanupShrunkFarmArea,
		getText(cleanupShrunkFarmArea
			and "ContextMenu_WaterPipe_ShrinkCleanupOpen"
			or "ContextMenu_WaterPipe_ShrinkCleanupClosed"),
		worldobjects,
		WaterPipeMenu.onSetPlacedPipeCleanupShrunkFarmArea,
		player,
		square,
		not cleanupShrunkFarmArea
	)
	if ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
		local tooltip = ISWorldObjectContextMenu.addToolTip()
		tooltip.description = getText("ContextMenu_WaterPipe_ShrinkCleanupTooltip")
		shrinkCleanupOption.toolTip = tooltip
	end

	menu:addOption(
		getText("ContextMenu_WaterPipe_Network"),
		worldobjects,
		WaterPipeNetworksUI.toggleWindow
	)
end

local pipeShapeGroups = {
	{
		label = "ContextMenu_WaterPipe_Cross",
		tooltip = "ContextMenu_WaterPipe_Cross",
		direct = true,
		shapes = {
			{ label = "ContextMenu_WaterPipe_Cross", sprite = "media/textures/Item_PipeCross.png", pipeType = "crossOption" },
		},
	},
	{
		label = "ContextMenu_WaterPipe_Lines",
		tooltip = "ContextMenu_WaterPipe_Line",
		shapes = {
			{ label = "ContextMenu_WaterPipe_Line_Param", direction = "ContextMenu_WaterPipe_EW", sprite = "media/textures/Item_PipeSE.png", pipeType = "lineOption" },
			{ label = "ContextMenu_WaterPipe_Line_Param", direction = "ContextMenu_WaterPipe_NS", sprite = "media/textures/Item_PipeNorth.png", pipeType = "lineOption2" },
		},
	},
	{
		label = "ContextMenu_WaterPipe_Corner",
		tooltip = "ContextMenu_WaterPipe_Corner",
		shapes = {
			{ label = "ContextMenu_WaterPipe_Corner_Param", direction = "ContextMenu_WaterPipe_SW", sprite = "media/textures/Item_PipeCornerNE.png", pipeType = "neOption" },
			{ label = "ContextMenu_WaterPipe_Corner_Param", direction = "ContextMenu_WaterPipe_SE", sprite = "media/textures/Item_PipeCornerNW.png", pipeType = "nwOption" },
			{ label = "ContextMenu_WaterPipe_Corner_Param", direction = "ContextMenu_WaterPipe_NW", sprite = "media/textures/Item_PipeCornerSE.png", pipeType = "seOption" },
			{ label = "ContextMenu_WaterPipe_Corner_Param", direction = "ContextMenu_WaterPipe_NE", sprite = "media/textures/Item_PipeCornerSW.png", pipeType = "swOption" },
		},
	},
	{
		label = "ContextMenu_WaterPipe_T",
		tooltip = "ContextMenu_WaterPipe_T",
		shapes = {
			{ label = "ContextMenu_WaterPipe_T_Param", direction = "ContextMenu_WaterPipe_North", sprite = "media/textures/Item_PipeTN.png", pipeType = "tnOption" },
			{ label = "ContextMenu_WaterPipe_T_Param", direction = "ContextMenu_WaterPipe_South", sprite = "media/textures/Item_PipeTS.png", pipeType = "tsOption" },
			{ label = "ContextMenu_WaterPipe_T_Param", direction = "ContextMenu_WaterPipe_East", sprite = "media/textures/Item_PipeTE.png", pipeType = "teOption" },
			{ label = "ContextMenu_WaterPipe_T_Param", direction = "ContextMenu_WaterPipe_West", sprite = "media/textures/Item_PipeTW.png", pipeType = "twOption" },
		},
	},
}

local function addPipeShapeOption(menu, group, worldobjects, player, pipeItem, shape, initialMode, initialPower)
	local label = shape.direction
		and getText(shape.direction)
		or getText(shape.label)
	local shapeOption = menu:addOption(
		label,
		worldobjects,
		WaterPipeMenu.onPlacePipe,
		player,
		pipeItem,
		shape.sprite,
		shape.pipeType,
		initialMode,
		initialPower
	)
	local tooltip = ISWorldObjectContextMenu.addToolTip()
	tooltip:setName(getText(group.tooltip))
	tooltip.description = getText(group.tooltip)
	tooltip:setTexture(shape.sprite)
	shapeOption.toolTip = tooltip
end

function WaterPipeMenu.addPipeShapeMenu(context, parentMenu, worldobjects, player, pipeItem, initialMode, initialPower)
	for _, group in ipairs(pipeShapeGroups) do
		if group.direct then
			for _, shape in ipairs(group.shapes) do
				addPipeShapeOption(parentMenu, group, worldobjects, player, pipeItem, shape, initialMode, initialPower)
			end
		else
			local groupOption = parentMenu:addOption(getText(group.label), worldobjects, nil)
			local shapeMenu = parentMenu:getNew(parentMenu)
			context:addSubMenu(groupOption, shapeMenu)

			for _, shape in ipairs(group.shapes) do
				addPipeShapeOption(shapeMenu, group, worldobjects, player, pipeItem, shape, initialMode, initialPower)
			end
		end
	end
end

function WaterPipeMenu.addPlacementModeMenu(context, parentMenu, worldobjects, player, pipeItem)
	local modes = {
		{ key = "ContextMenu_WaterPipe_PlaceFarming", mode = "irrigation", power = false },
		{ key = "ContextMenu_WaterPipe_PlaceWater", mode = "supply", power = false },
		{ key = "ContextMenu_WaterPipe_PlacePower", mode = "off", power = true },
	}
	for _, mode in ipairs(modes) do
		local modeOption = parentMenu:addOption(getText(mode.key), worldobjects, nil)
		local shapeMenu = parentMenu:getNew(parentMenu)
		context:addSubMenu(modeOption, shapeMenu)
		WaterPipeMenu.addPipeShapeMenu(
			context, shapeMenu, worldobjects, player, pipeItem, mode.mode, mode.power
		)
	end
end

---
-- Create the contextual menu for piping
--
WaterPipeMenu.doPipeMenu = function(player, context, worldobjects)
	local character = getSpecificPlayer(player)
	local playerInventory = character:getInventory()
	local isWaterPipeMenu = false
	local supplyPipeObject = nil
	local supplyPipeSquare = nil
	local placedPipeObject = nil
	local placedPipeSquare = nil
	local placedPipeUsesSupplyRemoval = false
	local subMenu = context:getNew(context)

	for _, object in ipairs(worldobjects) do
		local square = object:getSquare()
		if not supplyPipeObject then
			supplyPipeObject = WaterSupplyPipe.findObject(square)
			if supplyPipeObject then supplyPipeSquare = square end
		end

		WaterPipeMenu.currentPipe = WaterPipe.getCurrentPipe(square)
		local specialObject = nil
		if WaterPipeMenu.currentPipe ~= nil then
			specialObject = WaterPipe.findPipeObject(square)
		end
		if WaterPipeMenu.currentPipe ~= nil and specialObject ~= nil then
			isWaterPipeMenu = true
			placedPipeObject = specialObject
			placedPipeSquare = square
			break
		end

		WaterPipeMenu.currentBarrel = ISWorldObjectContextMenu.fetchVars
	end

	if not placedPipeObject and supplyPipeObject then
		isWaterPipeMenu = true
		placedPipeObject = supplyPipeObject
		placedPipeSquare = supplyPipeSquare
		placedPipeUsesSupplyRemoval = true
	end

	if placedPipeObject then
		WaterPipeMenu.addPlacedModeSwitches(
			context, subMenu, worldobjects, player, placedPipeSquare, placedPipeObject
		)
		local pipeOwner = tonumber(placedPipeObject:getModData()["waterPipeOwner"])
		if pipeOwner == nil or pipeOwner < 0 then
			subMenu:addOption(
				getText("ContextMenu_WaterPipe_ClaimPipe"),
				worldobjects,
				WaterPipeMenu.onClaimPlacedPipe,
				player,
				placedPipeSquare
			)
		end
		local removeOption = subMenu:addOption(
			getText("ContextMenu_WaterPipe_RemovePipe"),
			worldobjects,
			placedPipeUsesSupplyRemoval
				and WaterPipeMenu.onRemoveWaterSupplyPipe
				or WaterPipeMenu.onRemovePipe,
			player,
			placedPipeObject,
			placedPipeSquare,
			10
		)
		if WaterSupplyPipe.hasStoredItems(placedPipeObject) then
			removeOption.notAvailable = true
			if ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
				local tooltip = ISWorldObjectContextMenu.addToolTip()
				tooltip.description = getText("ContextMenu_WaterPipe_StorageNotEmpty")
				removeOption.toolTip = tooltip
			end
		end
	end

	local pipeItem = nil
	local canUsepipeItem = false
	local handItem = character:getSecondaryHandItem()

	if handItem and handItem:getType() == "WaterPipe" then
		pipeItem = handItem
		canUsepipeItem = true
	elseif playerInventory:contains("WaterPipe") then
		pipeItem = playerInventory:FindAndReturn("WaterPipe")
		canUsepipeItem = true
	end
	if canUsepipeItem and not isWaterPipeMenu then
		WaterPipeMenu.addPlacementModeMenu(
			context, subMenu, worldobjects, player, pipeItem
		)
		subMenu:addOption(
			getText("ContextMenu_WaterPipe_Network"),
			worldobjects,
			WaterPipeNetworksUI.toggleWindow
		)
	end

	if canUsepipeItem or isWaterPipeMenu then
		local buildOption = context:addOption(
			getText("ContextMenu_WaterPipe_InfinitePipe"), worldobjects, nil
		)
		context:addSubMenu(buildOption, subMenu)
	end
end


---
-- Create a new pipe to drag
--
WaterPipeMenu.onPlacePipe = function(worldobjects, player, pipeItem, spritea, pipeType, initialMode, initialPower)
	local pipe = Pipe:new(player, pipeItem, spritea, pipeType, initialMode, initialPower);

	player = getSpecificPlayer(player);
	getCell():setDrag(pipe, player:getPlayerNum());
end

WaterPipeMenu.onRemovePipe = function(worldobjects, player, pipe, square, time)
	if luautils.walkAdj(getSpecificPlayer(player), square) then
		ISTimedActionQueue.add(removePipeAction:new(getSpecificPlayer(player), pipe, square, time));
	end
end

WaterPipeMenu.onRemoveWaterSupplyPipe = function(worldobjects, player, supplyObject, square, time)
	local character = getSpecificPlayer(player)
	if luautils.walkAdj(character, square) then
		ISTimedActionQueue.add(removeWaterSupplyPipeAction:new(
			character,
			supplyObject,
			square,
			time
		))
	end
end

WaterPipeMenu.onSetPlacedPipeMode = function(worldobjects, player, square, targetMode)
	if not square then return end
	if isClient() then
		sendClientCommand(getSpecificPlayer(player), "WaterPipe", "setPlacedPipeMode", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
			mode = targetMode,
		})
	else
		WaterSupplyPipe.togglePlacedPipe(square, targetMode)
	end
end

WaterPipeMenu.onClaimPlacedPipe = function(worldobjects, player, square)
	if not square then return end
	if isClient() then
		sendClientCommand(getSpecificPlayer(player), "WaterPipe", "claimPlacedPipe", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
		})
	else
		local object = WaterSupplyPipe.findAnyPipeObject(square)
		WaterPipe.claimObjectOwner(object, getSpecificPlayer(player))
	end
end

WaterPipeMenu.onSetPlacedPipePower = function(worldobjects, player, square, enabled)
	if not square then return end
	if isClient() then
		sendClientCommand(getSpecificPlayer(player), "WaterPipe", "setPlacedPipePower", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
			enabled = enabled == true,
		})
	else
		local object = WaterSupplyPipe.findAnyPipeObject(square)
		PowerPipe.setObjectEnabled(object, enabled == true)
	end
end

WaterPipeMenu.onSetPlacedPipeIrrigationRange = function(worldobjects, player, square, rangeSize)
	if not square then return end
	if isClient() then
		sendClientCommand(getSpecificPlayer(player), "WaterPipe", "setPlacedPipeIrrigationRange", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
			range = rangeSize,
		})
	else
		local object = WaterSupplyPipe.findAnyPipeObject(square)
		WaterPipe.setObjectIrrigationRange(object, rangeSize)
	end
end

WaterPipeMenu.onSetPlacedPipeCleanupShrunkFarmArea = function(
	worldobjects, player, square, enabled
)
	if not square then return end
	if isClient() then
		sendClientCommand(
			getSpecificPlayer(player),
			"WaterPipe",
			"setPlacedPipeCleanupShrunkFarmArea",
			{
				x = square:getX(),
				y = square:getY(),
				z = square:getZ(),
				enabled = enabled == true,
			}
		)
	else
		local object = WaterSupplyPipe.findAnyPipeObject(square)
		WaterPipe.setObjectCleanupShrunkFarmArea(object, enabled == true)
	end
end

WaterPipeMenu.onSetPlacedPipeAutoTill = function(worldobjects, player, square, mode)
	if not square then return end
	if isClient() then
		sendClientCommand(getSpecificPlayer(player), "WaterPipe", "setPlacedPipeAutoTill", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
			mode = mode,
		})
	else
		WaterSupplyPipe.setPlacedAutoTill(square, mode)
	end
end

local function setPlacedPipeFarmingGroup(square, enabled)
	if not square or type(enabled) ~= "boolean" then return false end
	local object = WaterSupplyPipe.findAnyPipeObject(square)
	if not object then return false end
	local mode = WaterSupplyPipe.getPlacedMode(object)
	local supplyEnabled = mode == "supply" or mode == "both"
	local targetMode = enabled
		and (supplyEnabled and "both" or "irrigation")
		or (supplyEnabled and "supply" or "off")
	if mode ~= targetMode then
		WaterSupplyPipe.togglePlacedPipe(square, targetMode)
		object = WaterSupplyPipe.findAnyPipeObject(square)
		if not object then return false end
	end
	WaterPipe.setObjectAutoTill(object, enabled and "enabled" or "disabled")
	WaterPipe.setObjectCareEnabled(object, enabled)
	WaterPipe.setObjectFertilizationEnabled(object, enabled)
	if getAutoFarmingModuleEnabled() and WaterPipeAutoFarming then
		WaterPipeAutoFarming.setObjectSettings(
			object, enabled, enabled, object:getModData()["autoFarmSettings"]
		)
	end
	return true
end

WaterPipeMenu.onSetPlacedPipeFarming = function(worldobjects, player, square, enabled)
	if not square or type(enabled) ~= "boolean" then return end
	if isClient() then
		sendClientCommand(getSpecificPlayer(player), "WaterPipe", "setPlacedPipeFarming", {
			x = square:getX(), y = square:getY(), z = square:getZ(),
			enabled = enabled,
		})
	else
		setPlacedPipeFarmingGroup(square, enabled)
	end
end

local function setPlacedPipeFarmFeature(player, square, command, setter, enabled)
	if not square then return end
	if isClient() then
		sendClientCommand(getSpecificPlayer(player), "WaterPipe", command, {
			x = square:getX(), y = square:getY(), z = square:getZ(),
			enabled = enabled == true,
		})
	else
		local object = WaterSupplyPipe.findAnyPipeObject(square)
		setter(object, enabled == true)
	end
end

WaterPipeMenu.onSetPlacedPipeCare = function(worldobjects, player, square, enabled)
	setPlacedPipeFarmFeature(
		player, square, "setPlacedPipeCare", WaterPipe.setObjectCareEnabled, enabled
	)
end

WaterPipeMenu.onSetPlacedPipeFertilization = function(worldobjects, player, square, enabled)
	setPlacedPipeFarmFeature(
		player, square, "setPlacedPipeFertilization",
		WaterPipe.setObjectFertilizationEnabled, enabled
	)
end

local function setAutoFarmSwitch(player, square, field, enabled)
	if not square then return end
	local object = WaterSupplyPipe.findAnyPipeObject(square)
	if not object then return end
	local modData = object:getModData()
	local autoSowEnabled = getBooleanOrDefault(modData["autoSowEnabled"], true)
	local autoHarvestEnabled = getBooleanOrDefault(modData["autoHarvestEnabled"], true)
	if field == "autoSowEnabled" then autoSowEnabled = enabled == true end
	if field == "autoHarvestEnabled" then autoHarvestEnabled = enabled == true end
	AutoFarmSettingsUI.save(
		getSpecificPlayer(player), object, autoSowEnabled, autoHarvestEnabled,
		modData["autoFarmSettings"] or {}
	)
end

WaterPipeMenu.onSetPlacedPipeAutoSow = function(worldobjects, player, square, enabled)
	setAutoFarmSwitch(player, square, "autoSowEnabled", enabled)
end

WaterPipeMenu.onSetPlacedPipeAutoHarvest = function(worldobjects, player, square, enabled)
	setAutoFarmSwitch(player, square, "autoHarvestEnabled", enabled)
end

WaterPipeMenu.onOpenAutoFarmSettings = function(worldobjects, player, pipeObject)
	AutoFarmSettingsUI.open(getSpecificPlayer(player), pipeObject)
end

WaterPipeMenu.onSetPlacedPipeCleanup = function(worldobjects, player, square, enabled)
	setPlacedPipeFarmFeature(
		player, square, "setPlacedPipeCleanup", WaterPipe.setObjectCleanupEnabled, enabled
	)
end

WaterPipeMenu.onSetPlacedPipeWholeBuildingWater = function(
	worldobjects, player, square, enabled
)
	if isClient() then
		local object = WaterSupplyPipe.findAnyPipeObject(square)
		if object then WholeBuildingWater.setObjectEnabled(object, enabled, false) end
		sendClientCommand(getSpecificPlayer(player), "WaterPipe",
			"setPlacedPipeWholeBuildingWater", {
			x = square:getX(), y = square:getY(), z = square:getZ(),
			enabled = enabled,
		})
	else
		local object = WaterSupplyPipe.findAnyPipeObject(square)
		if object then WholeBuildingWater.setObjectEnabled(object, enabled) end
	end
end

Events.OnFillWorldObjectContextMenu.Add(WaterPipeMenu.doPipeMenu);
