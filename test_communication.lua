local handlers = {}
Events = {
    OnClientCommand = {
        Add = function(handler)
            table.insert(handlers, handler)
        end,
    },
}

isServer = function() return true end

local expectedPipe = { x = 10, y = 20, z = 0 }
local ownerClaimCalls = 0
local autoTillModes = {}
local careModes = {}
local fertilizationModes = {}
local cleanupModes = {}
local wholeBuildingWaterModes = {}
WaterPipe = {
    getPipeAt = function(x, y, z)
        if x == expectedPipe.x and y == expectedPipe.y and z == expectedPipe.z then
            return expectedPipe
        end
        return nil
    end,
	claimObjectOwner = function(object, player)
		assert(object ~= nil and player ~= nil)
		ownerClaimCalls = ownerClaimCalls + 1
	end,
	setObjectAutoTill = function(object, mode)
		assert(object ~= nil)
		table.insert(autoTillModes, mode)
	end,
	setObjectCareEnabled = function(object, enabled)
		assert(object ~= nil and type(enabled) == "boolean")
		table.insert(careModes, enabled)
	end,
	setObjectFertilizationEnabled = function(object, enabled)
		assert(object ~= nil and type(enabled) == "boolean")
		table.insert(fertilizationModes, enabled)
	end,
	setObjectCleanupEnabled = function(object, enabled)
		assert(object ~= nil and type(enabled) == "boolean")
		table.insert(cleanupModes, enabled)
	end,
}

local pickupCalls = 0
Pipe = {
    onPickUp = function(pipe, player)
        assert(pipe == expectedPipe, "server should pass the resolved pipe")
        assert(player ~= nil, "server should pass the requesting player")
        pickupCalls = pickupCalls + 1
    end,
}

local expectedSupplyObject = {
	mode = "supply",
	getSquare = function() return "supply-square" end,
}
local supplyPickupCalls = 0
local magicFridgePickupCalls = 0
local magicFridgeSettingsCalls = 0
local allMagicFridgeSettingsCalls = 0
local modeCalls = {}
WaterSupplyPipe = {
	findAnyPipeObject = function(square)
		if square == "supply-square" then return expectedSupplyObject end
		return nil
	end,
    findObject = function(square)
        if square == "supply-square" then return expectedSupplyObject end
        return nil
    end,
    onPickUp = function(supplyObject, player)
        assert(supplyObject == expectedSupplyObject, "server should resolve the supply object")
        assert(player ~= nil, "server should pass the supply-pipe owner")
        supplyPickupCalls = supplyPickupCalls + 1
    end,
    togglePlacedPipe = function(square, mode)
        assert(square == "supply-square")
        table.insert(modeCalls, mode)
		expectedSupplyObject.mode = mode
		return true, expectedSupplyObject
    end,
	getPlacedMode = function(object) return object.mode end,
	setPlacedAutoTill = function(square, mode)
		assert(square == "supply-square")
		table.insert(autoTillModes, mode)
	end,
}
PowerPipe = {
	setObjectEnabled = function() end,
}
WholeBuildingWater = {
	setObjectEnabled = function(object, enabled)
		assert(object ~= nil and type(enabled) == "boolean")
		table.insert(wholeBuildingWaterModes, enabled)
	end,
}
MagicFridge = {
	findOnSquare = function(square)
		if square == "supply-square" then return "magic-fridge" end
	end,
	pickUp = function(object, player)
		assert(object == "magic-fridge" and player ~= nil)
		magicFridgePickupCalls = magicFridgePickupCalls + 1
	end,
	setObjectSettings = function(object, enabled, settings)
		assert(object == "magic-fridge" and type(enabled) == "boolean"
			and type(settings) == "table")
		magicFridgeSettingsCalls = magicFridgeSettingsCalls + 1
	end,
	setAllObjectSettings = function(enabled, settings)
		assert(type(enabled) == "boolean" and type(settings) == "table")
		allMagicFridgeSettingsCalls = allMagicFridgeSettingsCalls + 1
	end,
}
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            if x == 10 and y == 20 and z == 0 then return "supply-square" end
            return nil
        end,
    }
end

package.preload["WaterPipe"] = function() return WaterPipe end
package.preload["WaterPipe/PowerPipe"] = function() return PowerPipe end
package.preload["WaterPipe/WholeBuildingWater"] = function() return WholeBuildingWater end
package.preload["BuildingObjects/zwaterSupplyPipe"] = function() return WaterSupplyPipe end
package.preload["WaterPipe/MagicFridge"] = function() return MagicFridge end
package.loaded["WaterPipe"] = nil
dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/waterPipesCommands.lua")

assert(#handlers == 1, "server should register exactly one command handler")
local onClientCommand = handlers[1]
local player = {
    getX = function() return 10 end,
    getY = function() return 20 end,
    getZ = function() return 0 end,
}

onClientCommand("waterPipe", "pickUp", player, { x = 10, y = 20, z = 0 })
assert(pickupCalls == 0, "module names are case-sensitive and legacy casing must be rejected")

onClientCommand("WaterPipe", "pickUp", player, { x = 10, y = 20, z = 0 })
assert(pickupCalls == 1, "nearby valid pickup request should be accepted")

onClientCommand("WaterPipe", "pickUp", player, { x = 100, y = 200, z = 0 })
assert(pickupCalls == 1, "remote pickup request should be rejected")

onClientCommand("WaterPipe", "pickUp", player, { x = "bad", y = 20, z = 0 })
assert(pickupCalls == 1, "invalid coordinates should be rejected")

onClientCommand("WaterPipe", "pickUpSupply", player, { x = 10, y = 20, z = 0 })
assert(supplyPickupCalls == 1, "nearby valid supply-pipe pickup should be accepted")

onClientCommand("WaterPipe", "pickUpSupply", player, { x = 100, y = 200, z = 0 })
assert(supplyPickupCalls == 1, "remote supply-pipe pickup should be rejected")

onClientCommand("WaterPipe", "pickUpMagicFridge", player, { x = 10, y = 20, z = 0 })
onClientCommand("WaterPipe", "pickUpMagicFridge", player, { x = 100, y = 200, z = 0 })
assert(magicFridgePickupCalls == 1,
	"only a nearby magic-fridge pickup request should be accepted")

onClientCommand("WaterPipe", "setMagicFridgeProduction", player,
	{ x = 10, y = 20, z = 0, enabled = true, settings = {} })
onClientCommand("WaterPipe", "setMagicFridgeProduction", player,
	{ x = 100, y = 200, z = 0, enabled = true, settings = {} })
onClientCommand("WaterPipe", "setMagicFridgeProduction", player,
	{ x = 10, y = 20, z = 0, enabled = "yes", settings = {} })
assert(magicFridgeSettingsCalls == 1,
	"only nearby well-formed magic-fridge settings should reach the server")

onClientCommand("WaterPipe", "setAllMagicFridgeProduction", player,
	{ x = 10, y = 20, z = 0, enabled = true, settings = {} })
onClientCommand("WaterPipe", "setAllMagicFridgeProduction", player,
	{ x = 100, y = 200, z = 0, enabled = true, settings = {} })
onClientCommand("WaterPipe", "setAllMagicFridgeProduction", player,
	{ x = 10, y = 20, z = 0, enabled = "yes", settings = {} })
assert(allMagicFridgeSettingsCalls == 1,
	"save-all should require one nearby fridge and well-formed settings")

onClientCommand("WaterPipe", "setPlacedPipeMode", player,
    { x = 10, y = 20, z = 0, mode = "both" })
onClientCommand("WaterPipe", "setPlacedPipeMode", player,
    { x = 10, y = 20, z = 0, mode = "off" })
assert(#modeCalls == 2 and modeCalls[1] == "both" and modeCalls[2] == "off",
    "nearby requests should support combined and fully disabled placed modes")
assert(ownerClaimCalls == 0,
	"ordinary mode changes must not implicitly claim an ownerless pipe")

onClientCommand("WaterPipe", "claimPlacedPipe", player, { x = 10, y = 20, z = 0 })
assert(ownerClaimCalls == 1,
	"an explicit nearby claim request should bind an ownerless legacy pipe")
onClientCommand("WaterPipe", "claimPlacedPipe", player, { x = 100, y = 200, z = 0 })
assert(ownerClaimCalls == 1,
	"remote claim requests must be rejected")

onClientCommand("WaterPipe", "setPlacedPipeMode", player,
    { x = 10, y = 20, z = 0, mode = "invalid" })
onClientCommand("WaterPipe", "setPlacedPipeMode", player,
    { x = 100, y = 200, z = 0, mode = "supply" })
assert(#modeCalls == 2,
    "invalid modes and remote placed-pipe changes must be rejected")

onClientCommand("WaterPipe", "setPlacedPipeAutoTill", player,
	{ x = 10, y = 20, z = 0, mode = "enabled" })
onClientCommand("WaterPipe", "setPlacedPipeAutoTill", player,
	{ x = 10, y = 20, z = 0, mode = "disabled" })
onClientCommand("WaterPipe", "setPlacedPipeAutoTill", player,
	{ x = 10, y = 20, z = 0, mode = "global" })
assert(#autoTillModes == 3 and autoTillModes[1] == "enabled"
	and autoTillModes[2] == "disabled" and autoTillModes[3] == "global",
	"nearby players should be able to set every valid per-pipe auto-till mode")
onClientCommand("WaterPipe", "setPlacedPipeAutoTill", player,
	{ x = 10, y = 20, z = 0, mode = "invalid" })
onClientCommand("WaterPipe", "setPlacedPipeAutoTill", player,
	{ x = 100, y = 200, z = 0, mode = "enabled" })
assert(#autoTillModes == 3,
	"invalid and remote per-pipe auto-till requests must be rejected")

onClientCommand("WaterPipe", "setPlacedPipeCare", player,
	{ x = 10, y = 20, z = 0, enabled = false })
onClientCommand("WaterPipe", "setPlacedPipeFertilization", player,
	{ x = 10, y = 20, z = 0, enabled = true })
onClientCommand("WaterPipe", "setPlacedPipeCleanup", player,
	{ x = 10, y = 20, z = 0, enabled = true })
onClientCommand("WaterPipe", "setPlacedPipeWholeBuildingWater", player,
	{ x = 10, y = 20, z = 0, enabled = true })
onClientCommand("WaterPipe", "setPlacedPipeCare", player,
	{ x = 100, y = 200, z = 0, enabled = true })
assert(#careModes == 1 and careModes[1] == false
	and #fertilizationModes == 1 and fertilizationModes[1] == true,
	"care and fertilization switches must be validated and applied by the server")
assert(#cleanupModes == 1 and cleanupModes[1] == true,
	"area cleanup must be validated and applied by the server")
assert(#wholeBuildingWaterModes == 1 and wholeBuildingWaterModes[1] == true,
	"whole-building water must be validated and applied by the server")

local modeCountBeforeFarming = #modeCalls
local autoTillCountBeforeFarming = #autoTillModes
local careCountBeforeFarming = #careModes
local fertilizationCountBeforeFarming = #fertilizationModes
onClientCommand("WaterPipe", "setPlacedPipeFarming", player,
	{ x = 10, y = 20, z = 0, enabled = true })
assert(#modeCalls == modeCountBeforeFarming + 1
	and modeCalls[#modeCalls] == "irrigation"
	and autoTillModes[#autoTillModes] == "enabled"
	and careModes[#careModes] == true
	and fertilizationModes[#fertilizationModes] == true,
	"the server farming group command should atomically enable its four child services")
onClientCommand("WaterPipe", "setPlacedPipeFarming", player,
	{ x = 10, y = 20, z = 0, enabled = false })
assert(modeCalls[#modeCalls] == "off"
	and autoTillModes[#autoTillModes] == "disabled"
	and careModes[#careModes] == false
	and fertilizationModes[#fertilizationModes] == false,
	"the farming group command should disable the same four child services")
onClientCommand("WaterPipe", "setPlacedPipeFarming", player,
	{ x = 100, y = 200, z = 0, enabled = true })
onClientCommand("WaterPipe", "setPlacedPipeFarming", player,
	{ x = 10, y = 20, z = 0, enabled = "yes" })
assert(#autoTillModes == autoTillCountBeforeFarming + 2
	and #careModes == careCountBeforeFarming + 2
	and #fertilizationModes == fertilizationCountBeforeFarming + 2,
	"remote or malformed farming-group requests must be rejected")

print("PASS test_communication.lua")
