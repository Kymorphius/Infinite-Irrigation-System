local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local root = "Contents/mods/WaterPipes-IrrigationSystems/42/"
local waterPipe = readFile(root .. "media/lua/server/WaterPipe.lua")
local removeAction = readFile(root .. "media/lua/client/TimedActions/removePipeAction.lua")
local pipeObject = readFile(root .. "media/lua/server/BuildingObjects/zpipe.lua")
local supplyPipeObject = readFile(root .. "media/lua/server/BuildingObjects/zwaterSupplyPipe.lua")
local supplyRemoveAction = readFile(root .. "media/lua/client/TimedActions/removeWaterSupplyPipeAction.lua")
local worldPipeMenu = readFile(root .. "media/lua/client/ISUI/WaterPipeMenu.lua")
local networkUI = readFile(root .. "media/lua/client/WaterPipe/WaterPipeNetworksUI.lua")
local recipe = readFile(root .. "media/scripts/waterPipes.txt")
local pipeSprites = readFile(root .. "media/lua/shared/WaterPipe/PipeSprites.lua")
local powerPipe = readFile(root .. "media/lua/shared/WaterPipe/PowerPipe.lua")
local serverCommands = readFile(root .. "media/lua/server/waterPipesCommands.lua")
local farmingInfoGuard = readFile(root .. "media/lua/client/WaterPipe/FarmingInfoGuard.lua")

assert(not waterPipe:match("[^%w_]print%s*=%s*nop_print"),
    "production code must not replace global print")
assert(waterPipe:find("function WaterPipe.handleNoRotten", 1, true),
    "no-rotten must have an independent lifecycle handler")
assert(waterPipe:find("function WaterPipe.normalizePlowedLand", 1, true)
		and waterPipe:find('plant.typeOfSeed == "none"', 1, true)
		and waterPipe:find("plant:stateToIsoObject(isoObject)", 1, true),
	"auto-till must normalize and repair corrupted Farming_none furrows")
assert(farmingInfoGuard:find('plant.typeOfSeed == "none"', 1, true)
		and farmingInfoGuard:find("originalOnInfo", 1, true),
	"the client must reject impossible Farming_none info windows without replacing vanilla behavior")
assert(waterPipe:find("local noRottenDone = features.care == true", 1, true)
		and waterPipe:find("WaterPipe.handleNoRotten", 1, true),
    "plant care must run no-rotten before optional pest and revival care")
assert(not waterPipe:find('plant.state = "harvest"', 1, true),
    "server plant care must not create the non-native harvest state")
assert(removeAction:find("sendClientCommand(self.character, 'WaterPipe', 'pickUp', args)", 1, true),
    "client pickup command must use the canonical module name")
assert(pipeObject:find("WaterPipe.removePipeDataAt(x, y, z)", 1, true),
    "pipe removal must use the canonical server registry cleanup")
assert(waterPipe:find("Events.OnObjectAboutToBeRemoved.Add(WaterPipe.onObjectAboutToBeRemoved)", 1, true),
    "external pipe removal must be observed by the server registry")
assert(waterPipe:find("function WaterPipe.installHarvestHook", 1, true)
        and waterPipe:find('WaterPipe.careForPlant(plant, "harvest", features)', 1, true),
    "harvest completion must immediately care for only the harvested covered crop")
assert(pipeObject:find("local character = self.character or self.playerObject", 1, true),
    "Build 42 placement must use the server-provided action character")
assert(pipeObject:find('getModData()["waterPipeOwner"] = pipeOwner', 1, true)
		and waterPipe:find("function WaterPipe.bindPlantOwnerFromCoveringPipe", 1, true),
	"placed pipes must persist their owner and repair only ownerless covered plants")
assert(not pipeObject:find("transmitCompleteItemToServer", 1, true),
    "server-authoritative placement must not retransmit the object to the server")
assert(not networkUI:find("Barrel", 1, true),
    "infinite irrigation UI must not depend on obsolete barrel state")
assert(networkUI:find("WaterPipeNetworksUI.refreshContent(textPanel)", 1, true),
    "network UI should render content immediately when opened")
assert(recipe:find("item 16 WaterPipes.WaterPipe", 1, true),
    "recipe must match the documented output of 16 pipes")
assert(recipe:find("Tags = InHandCraft;CanBeDoneInDark", 1, true),
    "recipe must support in-hand crafting without a light source")
assert(not recipe:find("AnySurfaceCraft", 1, true),
    "recipe must not require a table, surface, or workstation")
assert(not recipe:find("item WaterSupplyPipe", 1, true)
        and not recipe:find("item WaterSupplyIrrigationPipe", 1, true),
    "all placed modes must use the single irrigation-pipe inventory item")
assert(supplyPipeObject:find("IsoThumpable.new", 1, true),
    "vanilla appliance plumbing only recognizes thumpable water-source objects")
assert(supplyPipeObject:find('newObject:getModData()["canBeWaterPiped"] = false', 1, true),
    "the supply pipe must be classified as an original clean piped-water source")
assert(not supplyPipeObject:find("EveryOneMinute", 1, true)
        and not supplyPipeObject:find("EveryTenMinutes", 1, true),
    "the native infinite source must not add a refill polling loop")
assert(pipeSprites:find('WaterPipeSprite.tilesetName .. "_11"', 1, true),
    "the supply pipe must use a separate registered sprite from irrigation pipes")
assert(supplyRemoveAction:find('"WaterPipe", "pickUpSupply"', 1, true),
    "non-irrigating mode pickup must use the server-authoritative command")
assert(supplyPipeObject:find('mode == "off"', 1, true)
        and supplyPipeObject:find("WaterDisabledPipe", 1, true),
    "placed pipes must support a fully disabled fourth mode")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_WaterSupplyOpen", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_WaterSupplyClosed", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_IrrigationOpen", 1, true)
        and worldPipeMenu:find('"setPlacedPipeMode"', 1, true),
    "placed pipes must expose independent supply plus server-authoritative farming controls")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_FarmingPartial", 1, true)
		and worldPipeMenu:find("Icon_RecipeGroup_Partial_48x48.png", 1, true)
		and worldPipeMenu:find('"setPlacedPipeFarming"', 1, true)
		and serverCommands:find("function Commands.setPlacedPipeFarming", 1, true),
	"the tri-state farming group must use one server-authoritative multiplayer command")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_PlaceFarming", 1, true)
        and worldPipeMenu:find("ContextMenu_WaterPipe_PlaceWater", 1, true)
        and worldPipeMenu:find("ContextMenu_WaterPipe_Network", 1, true)
        and pipeObject:find('o.initialMode = initialMode or "irrigation"', 1, true)
        and pipeObject:find("WaterSupplyPipe.createPlacedPipe", 1, true),
	"one inventory item must offer the flat farming and water placement presets")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_PowerOpen", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_PowerClosed", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_PlacePower", 1, true)
		and serverCommands:find("function Commands.setPlacedPipePower", 1, true),
	"power must be independently selectable during placement and server-authoritative after placement")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_RangeCurrent", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_IrrigationRangeGlobal", 1, true)
		and serverCommands:find("function Commands.setPlacedPipeIrrigationRange", 1, true),
	"placed pipes must offer server-authoritative farming ranges plus a follow-global choice")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_AutoTillOpen", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_AutoTillClosed", 1, true)
		and worldPipeMenu:find('"setPlacedPipeAutoTill"', 1, true)
		and serverCommands:find("function Commands.setPlacedPipeAutoTill", 1, true)
		and supplyPipeObject:find("function WaterSupplyPipe.setPlacedAutoTill", 1, true)
		and waterPipe:find("function WaterPipe.setObjectAutoTill", 1, true),
	"auto-till must persist independently without restoring irrigation")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_CareOpen", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_FertilizationOpen", 1, true)
		and worldPipeMenu:find("ContextMenu_WaterPipe_CleanupOpen", 1, true)
		and serverCommands:find("function Commands.setPlacedPipeCare", 1, true)
		and serverCommands:find("function Commands.setPlacedPipeFertilization", 1, true)
		and serverCommands:find("function Commands.setPlacedPipeCleanup", 1, true),
	"care, fertilization, and cleanup must have independent server-authoritative switches")
assert(worldPipeMenu:find("ContextMenu_WaterPipe_ClaimPipe", 1, true)
		and worldPipeMenu:find('"claimPlacedPipe"', 1, true)
		and serverCommands:find("function Commands.claimPlacedPipe", 1, true),
	"ownerless multiplayer pipes must require an explicit server-authoritative claim")
assert(powerPipe:find("chunk:addGeneratorPos", 1, true)
		and powerPipe:find("SandboxVars.GeneratorTileRange", 1, true),
	"power pipes must use the vanilla generator range and chunk electricity mechanism")
assert(not powerPipe:find("EveryOneMinute", 1, true)
		and powerPipe:find("Events.EveryTenMinutes.Add", 1, true),
	"power maintenance must be low-frequency and never scan every minute")
assert(pipeSprites:find("WaterPipeSprite.supplyByPipeType", 1, true)
        and pipeSprites:find('twOption = WaterPipeSprite.tilesetName .. "_21"', 1, true),
    "every supply-capable mode must preserve the selected pipe shape")
assert(pipeSprites:find('verticalNorthOption = WaterPipeSprite.tilesetName .. "_22"', 1, true)
		and pipeSprites:find('verticalWestOption = WaterPipeSprite.tilesetName .. "_25"', 1, true)
		and pipeSprites:find('verticalNorthOption = WaterPipeSprite.tilesetName .. "_26"', 1, true)
		and pipeSprites:find('verticalWestOption = WaterPipeSprite.tilesetName .. "_29"', 1, true),
	"dormant riser assets must retain their irrigation and native-water sprite mappings")
assert(not worldPipeMenu:find("ContextMenu_WaterPipe_Vertical", 1, true)
		and not worldPipeMenu:find("Item_PipeVertical", 1, true),
	"unfinished vertical risers must not appear in the player placement menu")
assert(networkUI:find("WaterPipeNetworksUI.arePipesConnectedForDisplay", 1, true)
		and networkUI:find('pipeType:find("^vertical")', 1, true),
	"cross-floor network display connections must be limited to vertical risers")

print("PASS test_communication_simple.lua")
