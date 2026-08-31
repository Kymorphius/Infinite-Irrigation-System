local registeredContextHandler = nil
Events = {
	OnFillWorldObjectContextMenu = {
		Add = function(handler) registeredContextHandler = handler end,
	},
}

local function translated(key, value)
	if value ~= nil then return key .. "(" .. tostring(value) .. ")" end
	return key
end
getText = translated
getTexture = function(path) return path end

SandboxVars = {
	WaterPipes = {
		IrrigationRange = 2,
		InfiniteAutoPlow = false,
		ShowCleanup = true,
		EnableAutoFarming = true,
	},
}

isClient = function() return false end

WaterPipe = {
	getCurrentPipe = function(square) return square.irrigationPipe end,
	findPipeObject = function(square) return square.irrigationPipe end,
	setObjectCareEnabled = function(object, enabled)
		object:getModData().careEnabled = enabled
	end,
	setObjectFertilizationEnabled = function(object, enabled)
		object:getModData().fertilizeEnabled = enabled
	end,
	setObjectCleanupEnabled = function(object, enabled)
		object:getModData().cleanupEnabled = enabled
	end,
	setObjectCleanupShrunkFarmArea = function(object, enabled)
		object:getModData().cleanupShrunkFarmArea = enabled
	end,
}
PowerPipe = {
	isObjectEnabled = function() return false end,
}
local placedAutoTillCalls = {}
WaterSupplyPipe = {
	getPlacedMode = function(object) return object.mode end,
	findObject = function(square) return square.supplyPipe end,
	getModeAfterSupplyToggle = function(mode)
		if mode == "irrigation" then return "both" end
		if mode == "both" then return "irrigation" end
		if mode == "supply" then return "off" end
		return "supply"
	end,
	getModeAfterIrrigationToggle = function(mode)
		if mode == "supply" then return "both" end
		if mode == "off" then return "irrigation" end
		if mode == "both" then return "supply" end
		return "off"
	end,
	setPlacedAutoTill = function(square, mode)
		table.insert(placedAutoTillCalls, {
			square = square,
			mode = mode,
		})
	end,
	findAnyPipeObject = function(square)
		return square.irrigationPipe or square.supplyPipe
	end,
	hasStoredItems = function(object)
		return object and object.storedItems == true
	end,
}
WaterPipeNetworksUI = { toggleWindow = function() end }
AutoFarmSettingsUI = {
	save = function(_, object, autoSowEnabled, autoHarvestEnabled, settings)
		object:getModData().autoSowEnabled = autoSowEnabled
		object:getModData().autoHarvestEnabled = autoHarvestEnabled
		object:getModData().autoFarmSettings = settings
	end,
	open = function() end,
}
WholeBuildingWater = {
	setObjectEnabled = function(object, enabled)
		object:getModData().wholeBuildingWater = enabled and true or nil
		return true
	end,
}
ISWorldObjectContextMenu = {
	fetchVars = {},
	addToolTip = function()
		return {
			setName = function() end,
			setTexture = function() end,
		}
	end,
}

package.preload["BuildingObjects/zpipe"] = function() return {} end
package.preload["BuildingObjects/zwaterSupplyPipe"] = function() return WaterSupplyPipe end
package.preload["WaterPipe/PowerPipe"] = function() return PowerPipe end
package.preload["WaterPipe/WholeBuildingWater"] = function() return WholeBuildingWater end
package.preload["WaterPipe/WaterPipeNetworksUI"] = function() return WaterPipeNetworksUI end
package.preload["WaterPipe/AutoFarmSettingsUI"] = function() return AutoFarmSettingsUI end
package.preload["TimedActions/removeWaterSupplyPipeAction"] = function() return {} end

local function newMenu()
	local menu = { options = {}, submenus = {} }
	function menu:addOption(name, target, callback, ...)
		local option = {
			name = name,
			target = target,
			callback = callback,
			args = { ... },
		}
		table.insert(self.options, option)
		return option
	end
	function menu:getNew()
		return newMenu()
	end
	function menu:addSubMenu(option, submenu)
		self.submenus[option] = submenu
	end
	return menu
end

local function findOption(menu, name)
	for _, option in ipairs(menu.options) do
		if option.name == name then return option end
	end
	return nil
end

local context = newMenu()

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/client/ISUI/WaterPipeMenu.lua")
assert(registeredContextHandler == WaterPipeMenu.doPipeMenu,
	"the pipe context-menu handler should still be registered")

local square = {
	getX = function() return 10 end,
	getY = function() return 20 end,
	getZ = function() return 0 end,
}
local supplyOnly = {
	mode = "supply",
	getSquare = function() return square end,
	getModData = function()
		return {
			waterPipeOwner = 7, autoTillOverride = true, irrigationRange = 5,
			careEnabled = false, fertilizeEnabled = true,
			cleanupEnabled = false,
		}
	end,
}
local rootMenu = newMenu()
WaterPipeMenu.addPlacedModeSwitches(context, rootMenu, {}, 0, square, supplyOnly)

assert(#rootMenu.options == 14,
	"placed-pipe controls should stay flat except for the range picker")
assert(rootMenu.options[1].name == "ContextMenu_WaterPipe_FarmingPartial"
	and rootMenu.options[1].args[3] == true
	and rootMenu.options[1].iconTexture:find("Partial", 1, true)
	and rootMenu.options[1].color.b > rootMenu.options[1].color.r,
	"partially enabled farming must use a blue group-checkbox state")
assert(rootMenu.options[2].name == "ContextMenu_WaterPipe_IrrigationClosed"
	and rootMenu.options[2].args[3] == "both",
	"irrigation must follow the farming group toggle")
assert(rootMenu.options[3].name == "ContextMenu_WaterPipe_AutoTillOpen"
	and rootMenu.options[3].args[3] == "disabled",
	"auto-till must remain effective without irrigation")
assert(rootMenu.options[4].name == "ContextMenu_WaterPipe_CareClosed"
	and rootMenu.options[4].args[3] == true,
	"crop care must remain independently toggleable")
assert(rootMenu.options[5].name == "ContextMenu_WaterPipe_FertilizationOpen"
	and rootMenu.options[5].args[3] == false,
	"fertilization must remain independently toggleable")
assert(rootMenu.options[2].iconTexture:find("Tickbox_Cross", 1, true)
	and rootMenu.options[3].checkMark == true
	and rootMenu.options[3].iconTexture == nil
	and rootMenu.options[4].iconTexture:find("Tickbox_Cross", 1, true)
	and rootMenu.options[5].checkMark == true
	and rootMenu.options[5].iconTexture == nil,
	"enabled rows should use the native green check while disabled rows use a cross")

assert(rootMenu.options[6].name == "ContextMenu_WaterPipe_AutoSowOpen"
	and rootMenu.options[6].args[3] == false
	and rootMenu.options[7].name == "ContextMenu_WaterPipe_AutoHarvestOpen"
	and rootMenu.options[7].args[3] == false
	and rootMenu.options[8].name == "ContextMenu_WaterPipe_AutoFarmSettings",
	"unset automatic farming switches should default on and remain independently toggleable")
assert(rootMenu.options[9].name == "ContextMenu_WaterPipe_CleanupClosed"
	and rootMenu.options[9].args[3] == true,
	"area cleanup must stay outside the farming group")
assert(rootMenu.options[10].name == "ContextMenu_WaterPipe_PowerClosed"
	and rootMenu.options[10].args[3] == true,
	"power must remain a direct status toggle")
assert(rootMenu.options[11].name == "ContextMenu_WaterPipe_WaterSupplyOpen"
	and rootMenu.options[11].args[3] == "off",
	"water supply must remain a direct status toggle")
assert(rootMenu.options[12].name == "ContextMenu_WaterPipe_WholeBuildingWaterClosed"
	and rootMenu.options[12].notAvailable == false,
	"whole-building water should follow water supply and remain independently switchable")
assert(rootMenu.options[13].name ==
	"ContextMenu_WaterPipe_RangeCurrent(ContextMenu_WaterPipe_IrrigationRange5)"
	and rootMenu.options[13].checkMark == true,
	"the range entry should expose the current value with a green check")
assert(context.submenus[rootMenu.options[13]],
	"only the range entry should need a selection submenu")
assert(#context.submenus[rootMenu.options[13]].options == 9,
	"the range submenu should expose follow-global, seven fixed sizes, and shrink cleanup")
assert(context.submenus[rootMenu.options[13]].options[1].name
		== "ContextMenu_WaterPipe_IrrigationRangeGlobal(ContextMenu_WaterPipe_IrrigationRange3)"
	and context.submenus[rootMenu.options[13]].options[1].checkMark ~= true
	and context.submenus[rootMenu.options[13]].options[4].checkMark == true
	and context.submenus[rootMenu.options[13]].options[4].notAvailable ~= true,
	"the selected custom 5x5 range should be checked without disabled styling")
assert(context.submenus[rootMenu.options[13]].options[9].name
		== "ContextMenu_WaterPipe_ShrinkCleanupClosed"
	and context.submenus[rootMenu.options[13]].options[9].iconTexture:find("Tickbox_Cross", 1, true)
	and context.submenus[rootMenu.options[13]].options[9].args[3] == true,
	"range-shrink cleanup must be the final row in the range picker")
assert(rootMenu.options[14].name == "ContextMenu_WaterPipe_Network"
	and rootMenu.options[14].callback == WaterPipeNetworksUI.toggleWindow,
	"network must appear directly below range on a placed pipe")

SandboxVars.WaterPipes.EnableAutoFarming = false
local moduleDisabledMenu = newMenu()
WaterPipeMenu.addPlacedModeSwitches(
	newMenu(), moduleDisabledMenu, {}, 0, square, supplyOnly
)
assert(#moduleDisabledMenu.options == 11
	and not findOption(moduleDisabledMenu, "ContextMenu_WaterPipe_AutoSowOpen")
	and not findOption(moduleDisabledMenu, "ContextMenu_WaterPipe_AutoHarvestOpen")
	and not findOption(moduleDisabledMenu, "ContextMenu_WaterPipe_AutoFarmSettings"),
	"the disabled global module must hide all three automatic-farming controls")
SandboxVars.WaterPipes.EnableAutoFarming = true

local allFarmingOn = {
	mode = "irrigation",
	getModData = function()
		return {
			autoTillOverride = true, careEnabled = true, fertilizeEnabled = true,
			autoSowEnabled = true, autoHarvestEnabled = true,
		}
	end,
}
local allFarmingOnMenu = newMenu()
WaterPipeMenu.addPlacedModeSwitches(
	newMenu(), allFarmingOnMenu, {}, 0, square, allFarmingOn
)
assert(allFarmingOnMenu.options[1].name == "ContextMenu_WaterPipe_FarmingOpen"
	and allFarmingOnMenu.options[1].checkMark == true
	and allFarmingOnMenu.options[1].args[3] == false,
	"a fully selected farming group should show a green check and toggle all off")

local allFarmingOff = {
	mode = "off",
	getModData = function()
		return {
			autoTillOverride = false, careEnabled = false, fertilizeEnabled = false,
			autoSowEnabled = false, autoHarvestEnabled = false,
		}
	end,
}
local allFarmingOffMenu = newMenu()
WaterPipeMenu.addPlacedModeSwitches(
	newMenu(), allFarmingOffMenu, {}, 0, square, allFarmingOff
)
assert(allFarmingOffMenu.options[1].name == "ContextMenu_WaterPipe_FarmingClosed"
	and allFarmingOffMenu.options[1].iconTexture:find("Tickbox_Cross", 1, true)
	and allFarmingOffMenu.options[1].args[3] == true,
	"an empty farming group should show a cross and toggle all on")

WaterPipeMenu.onSetPlacedPipeAutoTill({}, 0, square, "enabled")
assert(#placedAutoTillCalls == 1
	and placedAutoTillCalls[1].square == square
	and placedAutoTillCalls[1].mode == "enabled",
	"single-player auto-till must not alter irrigation mode")

SandboxVars.WaterPipes.InfiniteAutoPlow = false
local irrigationPipe = {
	mode = "irrigation",
	getModData = function()
		return { waterPipeOwner = 7 }
	end,
}
context = newMenu()
rootMenu = newMenu()
WaterPipeMenu.addPlacedModeSwitches(context, rootMenu, {}, 0, square, irrigationPipe)
assert(rootMenu.options[1].name == "ContextMenu_WaterPipe_FarmingPartial"
	and rootMenu.options[2].name == "ContextMenu_WaterPipe_IrrigationOpen"
	and rootMenu.options[3].name == "ContextMenu_WaterPipe_AutoTillClosed",
	"irrigation and auto-till should report their independent effective states")
local globalRangeMenu = context.submenus[rootMenu.options[13]]
assert(globalRangeMenu.options[1].checkMark == true,
	"follow-global should carry the range check when no per-pipe override exists")
assert(globalRangeMenu.options[1].notAvailable ~= true,
	"the active follow-global row should remain normally colored and clickable")

SandboxVars.WaterPipes.ShowCleanup = false
context = newMenu()
rootMenu = newMenu()
WaterPipeMenu.addPlacedModeSwitches(context, rootMenu, {}, 0, square, irrigationPipe)
assert(#rootMenu.options == 13
	and not findOption(rootMenu, "ContextMenu_WaterPipe_CleanupClosed"),
	"area cleanup must stay hidden unless the world setting explicitly exposes it")
SandboxVars.WaterPipes.ShowCleanup = true

local inventory = {
	contains = function(_, itemType) return itemType == "WaterPipe" end,
	FindAndReturn = function() return { getType = function() return "WaterPipe" end } end,
}
local character = {
	getInventory = function() return inventory end,
	getSecondaryHandItem = function() return nil end,
}
getSpecificPlayer = function() return character end

square.supplyPipe = supplyOnly
local worldObject = { getSquare = function() return square end }
local worldContext = newMenu()
WaterPipeMenu.doPipeMenu(0, worldContext, { worldObject })
assert(#worldContext.options == 1
	and worldContext.options[1].name == "ContextMenu_WaterPipe_InfinitePipe",
	"a placed supply pipe should create exactly one Infinite Pipe root menu")
local placedMenu = worldContext.submenus[worldContext.options[1]]
assert(placedMenu and #placedMenu.options == 15,
	"an owned placed pipe should expose the farming group plus controls and pickup")
assert(placedMenu.options[1].name == "ContextMenu_WaterPipe_FarmingPartial"
	and placedMenu.options[2].name == "ContextMenu_WaterPipe_IrrigationClosed"
	and placedMenu.options[3].name == "ContextMenu_WaterPipe_AutoTillOpen"
	and placedMenu.options[4].name == "ContextMenu_WaterPipe_CareClosed"
	and placedMenu.options[5].name == "ContextMenu_WaterPipe_FertilizationOpen"
	and placedMenu.options[6].name == "ContextMenu_WaterPipe_AutoSowOpen"
	and placedMenu.options[7].name == "ContextMenu_WaterPipe_AutoHarvestOpen"
	and placedMenu.options[8].name == "ContextMenu_WaterPipe_AutoFarmSettings"
	and placedMenu.options[9].name == "ContextMenu_WaterPipe_CleanupClosed"
	and placedMenu.options[10].name == "ContextMenu_WaterPipe_PowerClosed"
	and placedMenu.options[11].name == "ContextMenu_WaterPipe_WaterSupplyOpen"
	and placedMenu.options[12].name == "ContextMenu_WaterPipe_WholeBuildingWaterClosed"
	and placedMenu.options[13].name:find("ContextMenu_WaterPipe_RangeCurrent", 1, true)
	and placedMenu.options[14].name == "ContextMenu_WaterPipe_Network"
	and placedMenu.options[15].name == "ContextMenu_WaterPipe_RemovePipe",
	"the placed-pipe menu must follow the independent feature order")
assert(not findOption(placedMenu, "ContextMenu_WaterPipe_PlacePipe")
	and not findOption(placedMenu, "ContextMenu_WaterPipe_ViewNetwork"),
	"the obsolete nested placement and long network entries must stay hidden")

square.supplyPipe = nil
local emptyContext = newMenu()
WaterPipeMenu.doPipeMenu(0, emptyContext, { worldObject })
assert(#emptyContext.options == 1,
	"an empty square with a pipe item should still create the Infinite Pipe root")
local placementMenu = emptyContext.submenus[emptyContext.options[1]]
assert(#placementMenu.options == 4
	and placementMenu.options[1].name == "ContextMenu_WaterPipe_PlaceFarming"
	and placementMenu.options[2].name == "ContextMenu_WaterPipe_PlaceWater"
	and placementMenu.options[3].name == "ContextMenu_WaterPipe_PlacePower"
	and placementMenu.options[4].name == "ContextMenu_WaterPipe_Network",
	"empty-ground placement must be the flat farming, water, power, network menu")
assert(emptyContext.submenus[placementMenu.options[1]]
	and emptyContext.submenus[placementMenu.options[2]]
	and emptyContext.submenus[placementMenu.options[3]]
	and not emptyContext.submenus[placementMenu.options[4]],
	"only the three placement presets should open shape menus")

context = newMenu()
local shapeMenu = newMenu()
WaterPipeMenu.addPipeShapeMenu(context, shapeMenu, {}, 0, {}, "both", true)
local verticalOption = findOption(shapeMenu, "ContextMenu_WaterPipe_Vertical")
assert(not verticalOption and #shapeMenu.options == 4,
	"unfinished vertical risers must stay hidden from the placement menu")
assert(shapeMenu.options[1].name == "ContextMenu_WaterPipe_Cross"
	and shapeMenu.options[1].callback == WaterPipeMenu.onPlacePipe
	and shapeMenu.options[2].name == "ContextMenu_WaterPipe_Lines"
	and shapeMenu.options[3].name == "ContextMenu_WaterPipe_Corner"
	and shapeMenu.options[4].name == "ContextMenu_WaterPipe_T",
	"shape selection must be ordered cross, line, corner, T with direct cross placement")
local lineMenu = context.submenus[shapeMenu.options[2]]
local cornerMenu = context.submenus[shapeMenu.options[3]]
local teeMenu = context.submenus[shapeMenu.options[4]]
assert(lineMenu.options[1].name == "ContextMenu_WaterPipe_EW"
	and lineMenu.options[2].name == "ContextMenu_WaterPipe_NS"
	and cornerMenu.options[1].name == "ContextMenu_WaterPipe_SW"
	and teeMenu.options[1].name == "ContextMenu_WaterPipe_North",
	"direction rows must omit repeated line, corner, and T prefixes")

print("PASS test_water_pipe_menu.lua")
