require "WaterPipe"
require "WaterPipe/PowerPipe"
require "BuildingObjects/zwaterSupplyPipe"
require "WaterPipe/WholeBuildingWater"
require "WaterPipe/MagicFridge"

local Commands = {}

local function getNearbyPipeObject(player, args)
	if not player or type(args) ~= "table" then return nil end
	local x = tonumber(args.x)
	local y = tonumber(args.y)
	local z = tonumber(args.z)
	if not x or not y or not z then return nil end
	if math.abs(player:getX() - x) > 2 or
		math.abs(player:getY() - y) > 2 or
		math.abs(player:getZ() - z) > 0.1 then
		return nil
	end
	local square = getCell():getGridSquare(x, y, z)
	return WaterSupplyPipe.findAnyPipeObject(square)
end

local function canConfigureOwnedPipe(player, object)
	if not player or not object then return false end
	local access = player.getAccessLevel and tostring(player:getAccessLevel() or "") or ""
	if access ~= "" and access ~= "None" then return true end
	local ownerId = tonumber(object:getModData()["waterPipeOwner"])
	if ownerId == nil then
		ownerId = WaterPipe.claimObjectOwner(object, player)
	end
	return ownerId ~= nil and ownerId == WaterPipe.getCharacterOwnerId(player)
end

function Commands.claimPlacedPipe(player, args)
	local object = getNearbyPipeObject(player, args)
	if object then WaterPipe.claimObjectOwner(object, player) end
end

function Commands.pickUp(player, args)
	if not player or type(args) ~= "table" then return end

	local x = tonumber(args.x)
	local y = tonumber(args.y)
	local z = tonumber(args.z)
	if not x or not y or not z then return end

	-- 不信任客户端坐标：玩家只能拆除自己附近、同一楼层的管道。
	if math.abs(player:getX() - x) > 2 or
		math.abs(player:getY() - y) > 2 or
		math.abs(player:getZ() - z) > 0.1 then
		return
	end

	local pipe = WaterPipe.getPipeAt(x, y, z)
	if not pipe then return end

	Pipe.onPickUp(pipe, player);
end

function Commands.pickUpSupply(player, args)
	if not player or type(args) ~= "table" then return end

	local x = tonumber(args.x)
	local y = tonumber(args.y)
	local z = tonumber(args.z)
	if not x or not y or not z then return end

	-- Apply the same server-side proximity check as irrigation-pipe pickup.
	if math.abs(player:getX() - x) > 2 or
		math.abs(player:getY() - y) > 2 or
		math.abs(player:getZ() - z) > 0.1 then
		return
	end

	local square = getCell():getGridSquare(x, y, z)
	local supplyObject = WaterSupplyPipe.findObject(square)
	if supplyObject then
		WaterSupplyPipe.onPickUp(supplyObject, player)
	end
end

local function getNearbyMagicFridge(player, args)
	if not player or type(args) ~= "table" then return end
	local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
	if not x or not y or not z
		or math.abs(player:getX() - x) > 2
		or math.abs(player:getY() - y) > 2
		or math.abs(player:getZ() - z) > 0.1 then return end
	local square = getCell():getGridSquare(x, y, z)
	return MagicFridge.findOnSquare(square)
end

function Commands.pickUpMagicFridge(player, args)
	local object = getNearbyMagicFridge(player, args)
	if object then MagicFridge.pickUp(object, player) end
end

function Commands.setMagicFridgeProduction(player, args)
	if type(args) ~= "table" or type(args.enabled) ~= "boolean" then return end
	local object = getNearbyMagicFridge(player, args)
	if object then MagicFridge.setObjectSettings(object, args.enabled, args.settings) end
end

function Commands.setAllMagicFridgeProduction(player, args)
	if type(args) ~= "table" or type(args.enabled) ~= "boolean" then return end
	if getNearbyMagicFridge(player, args) then
		MagicFridge.setAllObjectSettings(args.enabled, args.settings)
	end
end

function Commands.setPlacedPipeMode(player, args)
	if not player or type(args) ~= "table" then return end
	if args.mode ~= "irrigation" and args.mode ~= "supply"
		and args.mode ~= "both" and args.mode ~= "off" then return end

	local x = tonumber(args.x)
	local y = tonumber(args.y)
	local z = tonumber(args.z)
	if not x or not y or not z then return end

	if math.abs(player:getX() - x) > 2 or
		math.abs(player:getY() - y) > 2 or
		math.abs(player:getZ() - z) > 0.1 then
		return
	end

	local square = getCell():getGridSquare(x, y, z)
	WaterSupplyPipe.togglePlacedPipe(square, args.mode)
end

function Commands.setPlacedPipePower(player, args)
	if not player or type(args) ~= "table" or type(args.enabled) ~= "boolean" then return end

	local x = tonumber(args.x)
	local y = tonumber(args.y)
	local z = tonumber(args.z)
	if not x or not y or not z then return end

	if math.abs(player:getX() - x) > 2 or
		math.abs(player:getY() - y) > 2 or
		math.abs(player:getZ() - z) > 0.1 then
		return
	end

	local square = getCell():getGridSquare(x, y, z)
	local object = WaterSupplyPipe.findAnyPipeObject(square)
	PowerPipe.setObjectEnabled(object, args.enabled)
end

function Commands.setPlacedPipeIrrigationRange(player, args)
	if not player or type(args) ~= "table" then return end
	local requestedRange = tonumber(args.range)
	if requestedRange ~= 0 and not WaterPipe.isValidIrrigationRange(requestedRange) then return end

	local x = tonumber(args.x)
	local y = tonumber(args.y)
	local z = tonumber(args.z)
	if not x or not y or not z then return end
	if math.abs(player:getX() - x) > 2 or
		math.abs(player:getY() - y) > 2 or
		math.abs(player:getZ() - z) > 0.1 then
		return
	end

	local square = getCell():getGridSquare(x, y, z)
	local object = WaterSupplyPipe.findAnyPipeObject(square)
	WaterPipe.setObjectIrrigationRange(object, requestedRange)
end

function Commands.setPlacedPipeAutoTill(player, args)
	if not player or type(args) ~= "table" then return end
	if args.mode ~= "global" and args.mode ~= "enabled"
		and args.mode ~= "disabled" then return end

	local object = getNearbyPipeObject(player, args)
	if object then
		WaterSupplyPipe.setPlacedAutoTill(object:getSquare(), args.mode)
	end
end

function Commands.setPlacedPipeFarming(player, args)
	if type(args) ~= "table" or type(args.enabled) ~= "boolean" then return end
	local object = getNearbyPipeObject(player, args)
	if not object then return end
	local square = object:getSquare()
	local mode = WaterSupplyPipe.getPlacedMode(object)
	local supplyEnabled = mode == "supply" or mode == "both"
	local targetMode = args.enabled
		and (supplyEnabled and "both" or "irrigation")
		or (supplyEnabled and "supply" or "off")
	if mode ~= targetMode then
		WaterSupplyPipe.togglePlacedPipe(square, targetMode)
		object = WaterSupplyPipe.findAnyPipeObject(square)
		if not object then return end
	end
	WaterPipe.setObjectAutoTill(object, args.enabled and "enabled" or "disabled")
	WaterPipe.setObjectCareEnabled(object, args.enabled)
	WaterPipe.setObjectFertilizationEnabled(object, args.enabled)
	if SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.EnableAutoFarming == true then
		WaterPipeAutoFarming.setObjectSettings(
			object, args.enabled, args.enabled, object:getModData()["autoFarmSettings"]
		)
	end
end

local function setPlacedFarmFeature(player, args, setter)
	if type(args) ~= "table" or type(args.enabled) ~= "boolean" then return end
	local object = getNearbyPipeObject(player, args)
	if object then setter(object, args.enabled) end
end

function Commands.setPlacedPipeCare(player, args)
	setPlacedFarmFeature(player, args, WaterPipe.setObjectCareEnabled)
end

function Commands.setPlacedPipeFertilization(player, args)
	setPlacedFarmFeature(player, args, WaterPipe.setObjectFertilizationEnabled)
end

function Commands.setPlacedPipeCleanup(player, args)
	setPlacedFarmFeature(player, args, WaterPipe.setObjectCleanupEnabled)
end

function Commands.setPlacedPipeCleanupShrunkFarmArea(player, args)
	setPlacedFarmFeature(player, args, WaterPipe.setObjectCleanupShrunkFarmArea)
end

function Commands.setPlacedPipeWholeBuildingWater(player, args)
	setPlacedFarmFeature(player, args, WholeBuildingWater.setObjectEnabled)
end

function Commands.setPlacedPipeAutoFarming(player, args)
	if not SandboxVars or not SandboxVars.WaterPipes
		or SandboxVars.WaterPipes.EnableAutoFarming ~= true then return end
	if type(args) ~= "table" or type(args.autoSowEnabled) ~= "boolean"
		or type(args.autoHarvestEnabled) ~= "boolean" then return end
	local object = getNearbyPipeObject(player, args)
	if not canConfigureOwnedPipe(player, object) then return end
	WaterPipeAutoFarming.setObjectSettings(
		object, args.autoSowEnabled, args.autoHarvestEnabled, args.settings
	)
end

function WaterPipe.OnClientCommand(module, command, player, args)
	if module ~= 'WaterPipe' then return; end
	if Commands[command] then
		Commands[command](player, args)
	end
end

if isServer() then
	Events.OnClientCommand.Add(WaterPipe.OnClientCommand)
end
