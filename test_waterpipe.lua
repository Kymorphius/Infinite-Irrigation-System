local function newEvent()
    local handlers = {}
    return {
        handlers = handlers,
        Add = function(handler)
            table.insert(handlers, handler)
        end,
    }
end

package.path = "Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/?.lua;"
    .. "Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/shared/?.lua;"
    .. package.path

Events = {
    OnGameBoot = newEvent(),
    OnGameStart = newEvent(),
    OnGameTimeLoaded = newEvent(),
    LoadGridsquare = newEvent(),
    EveryOneMinute = newEvent(),
	EveryTenMinutes = newEvent(),
    OnClientCommand = newEvent(),
	OnObjectAboutToBeRemoved = newEvent(),
}

isClient = function() return false end
isServer = function() return true end
getTexture = function() end

local originalPrint = print
dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/WaterPipe.lua")
assert(print == originalPrint, "WaterPipe.lua must not replace the global print function")
assert(#Events.EveryOneMinute.handlers == 1 and #Events.EveryTenMinutes.handlers == 2,
	"plant care and cleanup should stay low-frequency while their queued work uses minute batches")

SandboxVars = {
	WaterPipes = {
		EnableAutoFarming = true,
        InfiniteNoRotten = true,
        InfinitePestCare = false,
        InfiniteRevive = false,
        InfiniteReviveToSeeded = false,
        InfiniteInstantGrowUp = false,
        InfiniteCompost = false,
    },
}
assert(WaterPipe.getGlobalIrrigationRange() == 3,
	"old worlds without the new enum should keep the historical 3x3 range")
SandboxVars.WaterPipes.IrrigationRange = 1
assert(WaterPipe.getGlobalIrrigationRange() == 1)
SandboxVars.WaterPipes.IrrigationRange = 4
assert(WaterPipe.getGlobalIrrigationRange() == 7)
SandboxVars.WaterPipes.IrrigationRange = 7
assert(WaterPipe.getGlobalIrrigationRange() == 15)
SandboxVars.WaterPipes.IrrigationRange = nil
SandboxVars.WaterPipes.InfiniteAutoPlow = false
assert(not WaterPipe.getGlobalAutoTillEnabled())
assert(not WaterPipe.isPipeAutoTillEnabled({}))
assert(WaterPipe.isPipeAutoTillEnabled({ autoTillOverride = true }))
SandboxVars.WaterPipes.InfiniteAutoPlow = true
assert(WaterPipe.isPipeAutoTillEnabled({}))
assert(not WaterPipe.isPipeAutoTillEnabled({ autoTillOverride = false }))
local initialAutoTillPipes = WaterPipe.pipes
WaterPipe.pipes = { { autoTillOverride = false }, { autoTillOverride = false } }
WaterPipe.refreshAutoTillOverridePipeCount()
assert(not WaterPipe.hasAnyAutoTillEnabled(),
	"a global enable must not override pipes that are all explicitly disabled")
WaterPipe.pipes[2].autoTillOverride = nil
WaterPipe.refreshAutoTillOverridePipeCount()
assert(WaterPipe.hasAnyAutoTillEnabled(),
	"a follow-global pipe should become enabled with the global setting")
WaterPipe.pipes = initialAutoTillPipes
WaterPipe.refreshAutoTillOverridePipeCount()
SandboxVars.WaterPipes.InfiniteAutoPlow = false
SFarmingSystem = { instance = { hoursElapsed = 100 } }
farming_vegetableconf = {
    props = {
        TestCrop = {
            fullGrown = 6,
            harvestLevel = 5,
            mature = 5,
            timeToGrow = 48,
            rotTime = 24,
        },
    },
    getSpriteName = function() return "test-crop-sprite" end,
}

local function newPlant(state, growth)
    local plant = {
        typeOfSeed = "TestCrop",
        state = state,
        nbOfGrow = growth,
        health = state == "rotten" and 0 or 100,
        nextGrowing = 101,
        saved = 0,
    }
    function plant:isAlive()
        return self.state ~= "dead" and self.state ~= "rotten"
            and self.state ~= "destroyed" and self.state ~= "harvested"
    end
    function plant:saveData() self.saved = self.saved + 1 end
    function plant:setSpriteName(sprite) self.spriteName = sprite end
    function plant:updateSprite() self.spriteUpdated = true end
    return plant
end

local originalPlantClass = SPlantGlobalObject
local originalPipesForSeedHook = WaterPipe.pipes
local originalPipeIndexForSeedHook = WaterPipe.pipeByKey
local originalCareForSeedHook = WaterPipe.careForPlant
local seedCalls = 0
SPlantGlobalObject = {}
function SPlantGlobalObject:seed(typeOfSeed)
	seedCalls = seedCalls + 1
	self.state = "seeded"
	self.typeOfSeed = typeOfSeed
	return "seeded-result"
end
WaterPipe.pipes = { { x = 20, y = 20, z = 0 } }
WaterPipe.rebuildPipeIndex()
local seedCareCalls = 0
WaterPipe.careForPlant = function(plant, context)
	assert(plant.state == "seeded", "seed care must run after the original seed implementation")
	assert(context == "seed", "seed care should identify its direct-event context")
	seedCareCalls = seedCareCalls + 1
	return true
end
assert(WaterPipe.installSeedHook(), "the seed hook should install when the vanilla plant class is available")
local installedSeedWrapper = SPlantGlobalObject.seed
assert(WaterPipe.installSeedHook() and SPlantGlobalObject.seed == installedSeedWrapper,
	"installing the seed hook repeatedly must not wrap the method more than once")
local coveredSeedPlant = setmetatable(
	{ x = 21, y = 20, z = 0, state = "plow", typeOfSeed = "none" },
	{ __index = SPlantGlobalObject }
)
assert(coveredSeedPlant:seed("TestCrop") == "seeded-result",
	"the seed wrapper should preserve the original return value")
assert(seedCalls == 1 and seedCareCalls == 1,
	"a newly seeded covered plant should receive exactly one immediate care pass")
local uncoveredSeedPlant = setmetatable(
	{ x = 99, y = 99, z = 0, state = "plow", typeOfSeed = "none" },
	{ __index = SPlantGlobalObject }
)
uncoveredSeedPlant:seed("TestCrop")
assert(seedCalls == 2 and seedCareCalls == 1,
	"seeding outside pipe coverage should not run plant care")

WaterPipe.careForPlant = function() error("simulated care failure") end
local seedSucceeded, seedResult = pcall(function()
	return coveredSeedPlant:seed("TestCrop")
end)
assert(seedSucceeded and seedResult == "seeded-result" and seedCalls == 3,
	"a care failure must never interrupt or roll back vanilla seeding")
local laterModSeed = function() return "later-mod" end
SPlantGlobalObject.seed = laterModSeed
assert(not WaterPipe.installSeedHook() and SPlantGlobalObject.seed == laterModSeed,
	"a later direct replacement should not be wrapped again; periodic care remains the fallback")
WaterPipe.careForPlant = originalCareForSeedHook
WaterPipe.pipes = originalPipesForSeedHook
WaterPipe.pipeByKey = originalPipeIndexForSeedHook
SPlantGlobalObject = originalPlantClass

local originalHarvestMethod = SFarmingSystem.harvest
local originalCareForHarvestHook = WaterPipe.careForPlant
local originalPipesForHarvestHook = WaterPipe.pipes
local originalPipeIndexForHarvestHook = WaterPipe.pipeByKey
local originalInfiniteReviveForHarvestHook = SandboxVars.WaterPipes.InfiniteRevive
SandboxVars.WaterPipes.InfiniteRevive = true
local harvestCalls = 0
function SFarmingSystem:harvest(plant)
	harvestCalls = harvestCalls + 1
	plant.state = "harvested"
	return "harvest-result"
end
WaterPipe.pipes = { { x = 20, y = 20, z = 0 } }
WaterPipe.rebuildPipeIndex()
local harvestCareCalls = 0
local harvestCareState = nil
local harvestCareContext = nil
WaterPipe.careForPlant = function(plant, context)
	harvestCareState = plant.state
	harvestCareContext = context
	harvestCareCalls = harvestCareCalls + 1
	return true
end
assert(WaterPipe.installHarvestHook(),
	"the harvest hook should install when the vanilla farming method is available")
local installedHarvestWrapper = SFarmingSystem.harvest
assert(WaterPipe.installHarvestHook() and SFarmingSystem.harvest == installedHarvestWrapper,
	"installing the harvest hook repeatedly must not wrap the method more than once")
local coveredHarvestPlant = {
	x = 21, y = 20, z = 0, state = "seeded", typeOfSeed = "TestCrop",
}
assert(SFarmingSystem:harvest(coveredHarvestPlant) == "harvest-result",
	"the harvest wrapper should preserve the original return value")
assert(harvestCalls == 1 and harvestCareCalls == 1
	and harvestCareState == "harvested" and harvestCareContext == "harvest",
	"a covered crop should receive exactly one immediate post-harvest care pass")
local uncoveredHarvestPlant = {
	x = 99, y = 99, z = 0, state = "seeded", typeOfSeed = "TestCrop",
}
SFarmingSystem:harvest(uncoveredHarvestPlant)
assert(harvestCalls == 2 and harvestCareCalls == 1,
	"harvesting outside pipe coverage should not run plant care")

WaterPipe.careForPlant = function() error("simulated harvest care failure") end
local harvestSucceeded, harvestResult = pcall(function()
	return SFarmingSystem:harvest(coveredHarvestPlant)
end)
assert(harvestSucceeded and harvestResult == "harvest-result" and harvestCalls == 3,
	"a post-harvest care failure must never interrupt vanilla rewards or state changes")
local laterModHarvest = function() return "later-harvest-mod" end
SFarmingSystem.harvest = laterModHarvest
assert(not WaterPipe.installHarvestHook() and SFarmingSystem.harvest == laterModHarvest,
	"a later harvest replacement should remain untouched; periodic care is the fallback")
SandboxVars.WaterPipes.InfiniteRevive = false
assert(not WaterPipe.careForRecentlyHarvestedPlant(coveredHarvestPlant),
	"harvested crops should remain inert when revival is disabled")
SandboxVars.WaterPipes.InfiniteRevive = originalInfiniteReviveForHarvestHook
SFarmingSystem.harvest = originalHarvestMethod
WaterPipe.careForPlant = originalCareForHarvestHook
WaterPipe.pipes = originalPipesForHarvestHook
WaterPipe.pipeByKey = originalPipeIndexForHarvestHook

local originalOwnershipPipes = WaterPipe.pipes
local originalOwnershipIndex = WaterPipe.pipeByKey
WaterPipe.pipes = {
	{ x = 10, y = 10, z = 0, owner = 42, irrigationRange = 7 },
	{ x = 12, y = 10, z = 0, owner = 84, irrigationRange = 3 },
	{ x = 14, y = 10, z = 0, irrigationRange = 1 },
}
WaterPipe.rebuildPipeIndex()
local ownerlessPlant = newPlant("seeded", 4)
ownerlessPlant.x, ownerlessPlant.y, ownerlessPlant.z = 12, 10, 0
assert(WaterPipe.careForPlant(ownerlessPlant, "seed") == false
	and ownerlessPlant.owner == nil and ownerlessPlant.saved == 0,
	"immediate seed care must leave ownership for the vanilla sowing action")
assert(WaterPipe.careForPlant(ownerlessPlant, "owner-repair") == true,
	"an ownerless covered plant should be repaired even when no other care is needed")
assert(ownerlessPlant.owner == 84 and ownerlessPlant.saved == 1,
	"an ownerless plant should inherit and persist the nearest covering pipe owner")
local ownedPlant = newPlant("seeded", 4)
ownedPlant.x, ownedPlant.y, ownedPlant.z = 12, 10, 0
ownedPlant.owner = 7
assert(WaterPipe.careForPlant(ownedPlant, "owner-preserve") == false
	and ownedPlant.owner == 7 and ownedPlant.saved == 0,
	"existing vanilla plant ownership must never be overwritten")

local ownerObjectData = {}
local ownerObjectTransmits = 0
local ownerObject = {
	getModData = function() return ownerObjectData end,
	getSquare = function()
		return { getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end }
	end,
	transmitModData = function() ownerObjectTransmits = ownerObjectTransmits + 1 end,
}
local claimedOwner, ownerChanged = WaterPipe.claimObjectOwner(ownerObject, {
	getOnlineID = function() return 55 end,
})
assert(claimedOwner == 42 and ownerChanged and ownerObjectData.waterPipeOwner == 42
	and WaterPipe.getPipeAt(10, 10, 0).owner == 42 and ownerObjectTransmits == 1,
	"an object missing owner metadata should recover the persisted registry owner")
local preservedOwner, changedAgain = WaterPipe.claimObjectOwner(ownerObject, {
	getOnlineID = function() return 99 end,
})
assert(preservedOwner == 42 and not changedAgain and ownerObjectTransmits == 1,
	"a later player must not be able to take ownership of an already claimed pipe")
local oldObjectData = {}
local oldObject = {
	getModData = function() return oldObjectData end,
	getSquare = function()
		return { getX = function() return 14 end, getY = function() return 10 end, getZ = function() return 0 end }
	end,
	transmitModData = function() end,
}
local migratedOwner, migrated = WaterPipe.claimObjectOwner(oldObject, {
	getOnlineID = function() return 55 end,
})
assert(migratedOwner == 55 and migrated and oldObjectData.waterPipeOwner == 55
	and WaterPipe.getPipeAt(14, 10, 0).owner == 55,
	"the first player interacting with an ownerless multiplayer pipe should claim it")
WaterPipe.pipes = originalOwnershipPipes
WaterPipe.pipeByKey = originalOwnershipIndex

local maturePlant = newPlant("seeded", 7)
assert(WaterPipe.careForPlant(maturePlant, "test") == true,
    "no-rotten care should run even when pest care and revival are disabled")
assert(maturePlant.state == "seeded" and maturePlant.nbOfGrow == 7,
    "mature plants should remain on the final healthy vanilla growth stage")
assert(maturePlant.hasVegetable and maturePlant.hasSeed and maturePlant.nextGrowing == 124,
    "no-rotten care should retain harvest flags and postpone the vanilla rot deadline")
assert(maturePlant.saved == 1, "no-rotten changes should be persisted")
assert(WaterPipe.careForPlant(maturePlant, "test") == false and maturePlant.saved == 1,
    "no-rotten should not rewrite an already-safe plant every minute")
SFarmingSystem.instance.hoursElapsed = 119
assert(WaterPipe.careForPlant(maturePlant, "test") == true and maturePlant.nextGrowing == 143,
    "no-rotten should extend the deadline before vanilla can call rottenThis")
SFarmingSystem.instance.hoursElapsed = 100

local rottenPlant = newPlant("rotten", 8)
assert(WaterPipe.careForPlant(rottenPlant, "test") == true,
    "no-rotten should recover an already-rotten plant without InfiniteRevive")
assert(rottenPlant.state == "seeded" and rottenPlant.nbOfGrow == 7 and rottenPlant.health == 100,
    "rotten plants should recover to the native seed-bearing harvest stage")

local legacyPlant = newPlant("harvest", 7)
assert(WaterPipe.handleNoRotten(legacyPlant, "TestCrop", "migration") == true,
    "legacy harvest-state plants should be migrated")
assert(legacyPlant.state == "seeded" and legacyPlant.hasVegetable and legacyPlant.hasSeed,
    "legacy migration should use the native Build 42 state and harvest flags")

local youngPlant = newPlant("seeded", 4)
assert(WaterPipe.handleNoRotten(youngPlant, "TestCrop", "test") == false,
    "no-rotten should not freeze crops before their final mature stage")

local deadPlant = newPlant("dead", 8)
assert(WaterPipe.handleNoRotten(deadPlant, "TestCrop", "test") == false,
    "no-rotten should not replace the separate revival option for dead plants")

SandboxVars.WaterPipes.InfiniteNoRotten = false
local unprotectedPlant = newPlant("rotten", 8)
assert(WaterPipe.handleNoRotten(unprotectedPlant, "TestCrop", "test") == false,
    "disabled no-rotten should preserve vanilla rot behavior")
local legacyWithoutProtection = newPlant("harvest", 7)
assert(WaterPipe.handleNoRotten(legacyWithoutProtection, "TestCrop", "migration") == true,
    "legacy state migration should not depend on the current no-rotten option")
assert(legacyWithoutProtection.state == "seeded",
    "legacy state migration should always restore the native lifecycle state")

local cachedAlivePlant = newPlant("seeded", 4)
local aliveChecks = 0
function cachedAlivePlant:isAlive()
    aliveChecks = aliveChecks + 1
    return true
end
assert(WaterPipe.careForPlant(cachedAlivePlant, "cache-test") == false,
    "an unchanged healthy plant should not be persisted")
assert(aliveChecks == 1,
    "one care pass should reuse the cached alive state across care handlers")

SandboxVars.WaterPipes.InfiniteInstantGrowUp = true
local instantPlant = newPlant("seeded", 2)
assert(WaterPipe.handleRevival(instantPlant, "TestCrop", "test") == true,
    "instant growth should make a young plant harvestable")
assert(instantPlant.state == "seeded" and instantPlant.nbOfGrow == 7,
    "instant growth should keep the native Build 42 lifecycle state")

SandboxVars.WaterPipes.InfiniteInstantGrowUp = false
SandboxVars.WaterPipes.InfiniteRevive = true
local revivedPlant = newPlant("rotten", 8)
assert(WaterPipe.handleRevival(revivedPlant, "TestCrop", "test") == true,
    "InfiniteRevive should still recover rotten plants when no-rotten is disabled")
assert(revivedPlant.state == "seeded" and revivedPlant.nbOfGrow == 7,
    "revival should no longer create the non-native harvest state")
local harvestedPlant = newPlant("harvested", 7)
harvestedPlant.health = 0
assert(WaterPipe.handleRevival(harvestedPlant, "TestCrop", "harvest") == true,
	"immediate post-harvest care should revive a harvested covered crop")
assert(harvestedPlant.state == "seeded" and harvestedPlant.nbOfGrow == 7
	and harvestedPlant.hasVegetable and harvestedPlant.hasSeed
	and harvestedPlant.health == 100,
	"post-harvest revival should immediately restore the configured harvest stage")

package.preload["BuildingObjects/ISBuildingObject"] = function() return true end
package.preload["BuildingObjects/zwaterSupplyPipe"] = function()
	dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/BuildingObjects/zwaterSupplyPipe.lua")
	return WaterSupplyPipe
end
ISBuildingObject = {}
function ISBuildingObject:derive()
    local class = {}
    class.__index = class
    setmetatable(class, { __index = self })
    return class
end

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/BuildingObjects/zpipe.lua")

local keepPipe = { x = 9, y = 9, z = 0 }
WaterPipe.pipes = {
    { x = 1, y = 2, z = 0 },
    keepPipe,
    { x = 1, y = 2, z = 0 },
}
WaterPipe.modData = {
    WaterPipes = {
        pipes = {
            { x = 1, y = 2, z = 0 },
            keepPipe,
            { x = 1, y = 2, z = 0 },
        },
    },
}

local originalMarkCoverageMapDirty = WaterPipe.markCoverageMapDirty
local dirtyCalls = 0
WaterPipe.markCoverageMapDirty = function()
    dirtyCalls = dirtyCalls + 1
end

assert(Pipe.pipeRemove(1, 2, 0, false) == true, "existing pipe should be removed")
assert(#WaterPipe.pipes == 1 and WaterPipe.pipes[1] == keepPipe,
    "all matching runtime pipe records should be removed")
assert(#WaterPipe.modData.WaterPipes.pipes == 1,
    "all matching persisted pipe records should be removed")
assert(dirtyCalls == 1, "removing pipes should invalidate the coverage map once")

assert(Pipe.pipeRemove(99, 99, 0, false) == false, "missing pipe should not report removal")
assert(dirtyCalls == 1, "missing pipe should not invalidate the coverage map")

WaterPipe.pipes = { { x = 4, y = 5, z = 0 } }
WaterPipe.modData = { WaterPipes = { pipes = { { x = 4, y = 5, z = 0 } } } }
dirtyCalls = 0
local removedSquare = {
	getX = function() return 4 end,
	getY = function() return 5 end,
	getZ = function() return 0 end,
}
local removedObject = {
	getName = function() return "WaterPipe" end,
	getSquare = function() return removedSquare end,
}
WaterPipe.onObjectAboutToBeRemoved(removedObject)
assert(#WaterPipe.pipes == 0 and #WaterPipe.modData.WaterPipes.pipes == 0,
	"external object removal should clear runtime and persisted pipe records")
assert(dirtyCalls == 1, "external object removal should invalidate coverage")

local function objectList(items)
	return {
		size = function() return #items end,
		get = function(_, index) return items[index + 1] end,
	}
end

local presentObject = { getName = function() return "WaterPipe" end }
local missingSquare = { getObjects = function() return objectList({}) end }
local presentSquare = { getObjects = function() return objectList({ presentObject }) end }
getCell = function()
	return {
		getGridSquare = function(_, x)
			if x == 10 then return missingSquare end
			if x == 20 then return presentSquare end
			return nil
		end,
	}
end
WaterPipe.pipes = {
	{ x = 10, y = 10, z = 0 },
	{ x = 20, y = 20, z = 0 },
}
WaterPipe.modData = {
	WaterPipes = {
		pipes = {
			{ x = 10, y = 10, z = 0 },
			{ x = 20, y = 20, z = 0 },
		},
	},
}
assert(WaterPipe.pruneMissingLoadedPipes() == 1,
	"loaded squares without pipe objects should prune stale records")
assert(#WaterPipe.pipes == 1 and WaterPipe.pipes[1].x == 20,
	"pruning should preserve real pipes and records in unloaded chunks")
assert(#WaterPipe.modData.WaterPipes.pipes == 1,
	"pruning should update persisted records")

local indexedPipe = { x = 6, y = 7, z = 0 }
local duplicateIndexedPipe = { x = 6, y = 7, z = 0 }
local secondIndexedPipe = { x = 8, y = 9, z = 0 }
local savedModData = {
	WaterPipes = {
		pipes = { indexedPipe, duplicateIndexedPipe, secondIndexedPipe },
	},
}
GameTime = {
	getInstance = function()
		return {
			getModData = function() return savedModData end,
		}
	end,
}
WaterPipe.loadPipes()
assert(#WaterPipe.pipes == 2 and #savedModData.WaterPipes.pipes == 2,
	"loading saved pipes should remove duplicate coordinate records")
assert(WaterPipe.getPipeAt(6, 7, 0) == indexedPipe
	and WaterPipe.pipeByKey["6,7,0"] == indexedPipe,
	"saved pipes should be available through the coordinate index")

WaterPipe.pipes = {
	{ x = 30, y = 30, z = 0 },
	{ x = 40, y = 40, z = 0 },
}
WaterPipe.modData = {
	WaterPipes = {
		pipes = {
			{ x = 30, y = 30, z = 0 },
			{ x = 40, y = 40, z = 0 },
		},
	},
}
WaterPipe.rebuildPipeIndex()
dirtyCalls = 0
local loadedEmptySquare = {
	getX = function() return 30 end,
	getY = function() return 30 end,
	getZ = function() return 0 end,
	getObjects = function() return objectList({}) end,
}
WaterPipe.LoadGridsquare(loadedEmptySquare)
assert(WaterPipe.getPipeAt(30, 30, 0) == nil and WaterPipe.getPipeAt(40, 40, 0) ~= nil,
	"loading an empty square should remove only its stale indexed pipe record")
assert(#WaterPipe.pipes == 1 and #WaterPipe.modData.WaterPipes.pipes == 1,
	"targeted stale cleanup should update runtime and persisted lists")
assert(dirtyCalls == 1, "targeted stale cleanup should invalidate coverage once")
WaterPipe.markCoverageMapDirty = originalMarkCoverageMapDirty

-- Coverage construction should create the lookup map, deterministic processing
-- order, embedded index, and count in one pass without retaining unused tables.
getCell = function()
	return {
		getGridSquare = function() return nil end,
	}
end
WaterPipe.pipes = {
	{ x = 10, y = 10, z = 0 },
	{ x = 11, y = 10, z = 0 },
}
WaterPipe.modData = { WaterPipes = { pipes = WaterPipe.pipes } }
WaterPipe.rebuildPipeIndex()
WaterPipe.needsInitialPipePrune = false
local coverageMap, coveragePositions, coverageCount = WaterPipe.buildCoverageMap()
assert(coverageCount == 12 and #coveragePositions == 12,
	"two adjacent 3x3 pipe areas should contain 12 unique positions")
assert(coveragePositions[1].key == "9,9,0" and coveragePositions[12].key == "12,11,0",
	"coverage processing order should follow pipe and coordinate insertion order")
for index, coverageData in ipairs(coveragePositions) do
	assert(coverageMap[coverageData.key] == coverageData,
		"coverage map and processing list should share the same position record")
	assert(coverageData.index == index,
		"coverage record should contain its deterministic list position")
	assert(coverageData.pipes == nil,
		"coverage records should not retain unused per-position pipe lists")
end

local originalCoverageTimestamp = WaterPipe.getTimestamp
local incrementalClock = 0
local previousCoverageMap = { ["old"] = true }
WaterPipe.getTimestamp = function()
	incrementalClock = incrementalClock + 1
	return incrementalClock
end
WaterPipe.lastCoverageMap = previousCoverageMap
WaterPipe.coverageMapNeedsUpdate = true
WaterPipe.coverageBuildState = nil
WaterPipe.coverageTimeBudgetMs = 2
WaterPipe.coverageBudgetCheckInterval = 1
WaterPipe.coverageBuildMaxWorkItems = 300
WaterPipe.checkAndWaterNewPlantsWithCoverage()
assert(WaterPipe.coverageBuildState ~= nil and WaterPipe.coverageMapNeedsUpdate,
	"coverage rebuilding should pause and preserve its cursor when the time budget is exhausted")
assert(WaterPipe.lastCoverageMap == previousCoverageMap,
	"a partial rebuild should not expose an incomplete coverage map")

WaterPipe.markCoverageMapDirty()
assert(WaterPipe.coverageBuildState == nil,
	"a pipe-network change should discard an in-progress rebuild")
WaterPipe.coverageTimeBudgetMs = 0
WaterPipe.checkAndWaterNewPlantsWithCoverage()
assert(not WaterPipe.coverageMapNeedsUpdate and WaterPipe.coverageBuildState == nil,
	"an incremental rebuild should publish its result atomically when complete")
assert(WaterPipe.coveragePositionCount == 12 and WaterPipe.lastCoverageMap["9,9,0"],
	"the completed incremental map should contain the full deterministic coverage")
WaterPipe.getTimestamp = originalCoverageTimestamp
WaterPipe.coverageTimeBudgetMs = 2
WaterPipe.coverageBudgetCheckInterval = 5

local previousProcessing = {
	positions = {
		{ key = "old,1,0" },
		{ key = "11,10,0" },
		{ key = "old,3,0" },
	},
	currentIndex = 2,
}
assert(WaterPipe.getCoverageResumeIndex(previousProcessing, coverageMap, coverageCount)
	== coverageMap["11,10,0"].index,
	"coverage rebuild should resume from the same coordinate when it still exists")
previousProcessing.positions[2].key = "removed,10,0"
assert(WaterPipe.getCoverageResumeIndex(previousProcessing, coverageMap, coverageCount) == 2,
	"coverage rebuild should preserve the clamped numeric cursor when its coordinate disappeared")
previousProcessing.positions[2].key = "still-covered,10,0"
coverageMap["still-covered,10,0"] = { autoTill = true }
assert(WaterPipe.getCoverageResumeIndex(previousProcessing, coverageMap, coverageCount) == 2,
	"coverage rebuild should ignore a matching coordinate that is no longer plant-indexed")

local originalTimestamp = WaterPipe.getTimestamp
local originalBudgetCare = WaterPipe.careForPosition
local budgetClock = 0
local budgetCareCalls = 0
WaterPipe.getTimestamp = function()
	budgetClock = budgetClock + 4
	return budgetClock
end
WaterPipe.careForPosition = function()
	budgetCareCalls = budgetCareCalls + 1
	return false
end
WaterPipe.lastCoverageMap = coverageMap
WaterPipe.coveragePositions = coveragePositions
WaterPipe.coveragePositionCount = coverageCount
WaterPipe.coverageMapNeedsUpdate = false
WaterPipe.coverageProcessing = {
	positions = coveragePositions,
	currentIndex = nil,
	totalPositions = coverageCount,
}
WaterPipe.coverageTimeBudgetMs = 3
WaterPipe.coverageBudgetCheckInterval = 3
WaterPipe.checkAndWaterNewPlantsWithCoverage()
assert(budgetCareCalls == 3 and WaterPipe.coverageProcessing.currentIndex == 4,
	"coverage processing should repair an empty cursor, stop at its time budget, and preserve the next cursor")
WaterPipe.getTimestamp = originalTimestamp
WaterPipe.careForPosition = originalBudgetCare
WaterPipe.coverageTimeBudgetMs = 2
WaterPipe.coverageBudgetCheckInterval = 5

local originalFarmingSystemInstance = SFarmingSystem.instance
local originalPlantListCare = WaterPipe.careForPlant
local listedPlants = {
    { x = 10, y = 10, z = 0, typeOfSeed = "TestCrop", state = "seeded" },
    { x = 99, y = 99, z = 0, typeOfSeed = "TestCrop", state = "seeded" },
}
SFarmingSystem.instance = {
    getLuaObjectCount = function() return #listedPlants end,
    getLuaObjectByIndex = function(_, index) return listedPlants[index] end,
}
WaterPipe.lastCoverageMap = { ["10,10,0"] = true, ["11,10,0"] = true }
WaterPipe.plantProcessing = nil
local caredPlants = {}
WaterPipe.careForPlant = function(plant, context)
    assert(context == "plant-list", "adaptive scanning should identify its care context")
    table.insert(caredPlants, plant)
    return true
end
local usePlantScan, adaptivePlantCount = WaterPipe.shouldUsePlantScan(9)
assert(usePlantScan and adaptivePlantCount == 2,
    "adaptive scanning should choose a smaller plant list over covered positions")
local caredCount, processedPlantCount = WaterPipe.processPlantBatch(adaptivePlantCount)
assert(processedPlantCount == 2 and caredCount == 1 and caredPlants[1] == listedPlants[1],
    "plant-list scanning should care only for plants inside the coverage map")

local newlyPlanted = { x = 11, y = 10, z = 0, typeOfSeed = "TestCrop", state = "seeded" }
table.insert(listedPlants, newlyPlanted)
caredPlants = {}
WaterPipe.processPlantBatch(#listedPlants)
assert(#caredPlants == 1 and caredPlants[1] == newlyPlanted,
    "an increased plant count should prioritize newly appended plants")

originalAutoFarmingForCareRetry = WaterPipeAutoFarming
retryPlant = {
	x = 10, y = 10, z = 0, typeOfSeed = "TestCrop", state = "seeded",
}
listedPlants = { retryPlant }
SFarmingSystem.instance = {
	getLuaObjectCount = function() return 1 end,
	getLuaObjectByIndex = function(_, index) return listedPlants[index] end,
}
automationChecks = 0
WaterPipeAutoFarming = {
	processPlant = function(plant)
		automationChecks = automationChecks + 1
		return plant.seedBearing == true
	end,
}
WaterPipe.careForPlant = function(plant)
	plant.seedBearing = true
	return true
end
WaterPipe.plantProcessing = nil
retryCared, retryProcessed = WaterPipe.processPlantBatch(1)
assert(retryCared == 1 and retryProcessed == 1 and automationChecks == 2,
	"a care pass that makes a crop seed-bearing must retry harvest in the same cycle")
WaterPipeAutoFarming = originalAutoFarmingForCareRetry

SandboxVars.WaterPipes.InfiniteAutoPlow = true
assert(WaterPipe.shouldUsePlantScan(9),
	"one-shot auto-till should not force recurring plant care back to a full coverage scan")
SandboxVars.WaterPipes.InfiniteAutoPlow = false
WaterPipe.careForPlant = originalPlantListCare
SFarmingSystem.instance = originalFarmingSystemInstance
WaterPipe.plantProcessing = nil

local originalCareForPosition = WaterPipe.careForPosition
local visitedPositions = {}
WaterPipe.careForPosition = function(x, y, z, context)
	assert(context == "placement", "pipe-area care should preserve its context")
	visitedPositions[x .. "," .. y .. "," .. z] = true
	return true
end
assert(WaterPipe.careForPipeArea({ x = 3, y = 4, z = 0 }, "placement") == 9,
	"new-pipe care should visit all nine covered positions")
local visitedCount = 0
for _ in pairs(visitedPositions) do visitedCount = visitedCount + 1 end
assert(visitedCount == 9, "new-pipe care should not visit duplicate positions")

visitedPositions = {}
assert(WaterPipe.careForPipeArea({ x = 3, y = 4, z = 0, irrigationRange = 1 }, "placement") == 1,
	"a 1x1 override should care only for the pipe's own square")
visitedCount = 0
for _ in pairs(visitedPositions) do visitedCount = visitedCount + 1 end
assert(visitedCount == 1 and visitedPositions["3,4,0"])

visitedPositions = {}
assert(WaterPipe.careForPipeArea({ x = 3, y = 4, z = 0, irrigationRange = 7 }, "placement") == 49,
	"a 7x7 override should visit all 49 positions while using the same care path")
visitedCount = 0
for _ in pairs(visitedPositions) do visitedCount = visitedCount + 1 end
assert(visitedCount == 49)
WaterPipe.careForPosition = originalCareForPosition

local savedRangePipes = WaterPipe.pipes
local savedRangePipeIndex = WaterPipe.pipeByKey
WaterPipe.pipes = {
	{ x = 10, y = 10, z = 0, irrigationRange = 1 },
	{ x = 20, y = 20, z = 0, irrigationRange = 5 },
}
WaterPipe.rebuildPipeIndex()
assert(WaterPipe.isPositionCoveredByPipeIndex(10, 10, 0))
assert(not WaterPipe.isPositionCoveredByPipeIndex(11, 10, 0),
	"a 1x1 pipe must not cover an adjacent newly seeded plant")
assert(WaterPipe.isPositionCoveredByPipeIndex(22, 22, 0),
	"a 5x5 pipe should cover its radius-two corner")
assert(not WaterPipe.isPositionCoveredByPipeIndex(23, 20, 0))
WaterPipe.needsInitialPipePrune = false
local rangedMap, rangedPositions, rangedCount = WaterPipe.buildCoverageMap()
assert(rangedCount == 26 and #rangedPositions == 26
	and rangedMap["10,10,0"] and rangedMap["22,22,0"],
	"mixed 1x1 and 5x5 pipes should build one deduplicated variable-range map")

WaterPipe.pipes = {
	{ x = 10, y = 10, z = 0, irrigationRange = 3, autoTillOverride = false },
	{ x = 12, y = 10, z = 0, irrigationRange = 3, autoTillOverride = true },
}
WaterPipe.refreshAutoTillOverridePipeCount()
local autoTillMap = WaterPipe.buildCoverageMap()
assert(autoTillMap["9,10,0"].autoTill == false,
	"a square covered only by a disabled pipe must not be auto-tilled")
assert(autoTillMap["11,10,0"].autoTill == true,
	"an enabled overlapping pipe must win over a disabled pipe")
assert(autoTillMap["13,10,0"].autoTill == true,
	"a square covered by an enabled pipe must remain eligible for auto-till")

WaterPipe.pipes = {
	{
		x = 30, y = 30, z = 0, irrigationRange = 1,
		irrigationEnabled = false, careEnabled = false,
		fertilizeEnabled = false, autoTillOverride = true, cleanupEnabled = true,
	},
	{
		x = 40, y = 40, z = 0, irrigationRange = 1,
		irrigationEnabled = false, careEnabled = true,
		fertilizeEnabled = false, autoTillOverride = false,
	},
	{
		x = 40, y = 40, z = 0, irrigationRange = 1,
		irrigationEnabled = false, careEnabled = false,
		fertilizeEnabled = true, autoTillOverride = false,
	},
}
WaterPipe.rebuildPipeIndex()
local independentMap, independentPositions, independentCount = WaterPipe.buildCoverageMap()
assert(independentMap["30,30,0"].autoTill == true
	and not independentMap["30,30,0"].plantIndexed,
	"auto-till-only coverage must not enter recurring plant-care scans")
local independentState = WaterPipe.createCoverageBuildState(nil)
WaterPipe.advanceCoverageBuild(independentState, 0, 0)
assert(independentState.totalCleanupCoverage == 1
	and independentState.cleanupPositions[1].key == "30,30,0",
	"cleanup-only coverage must use its own deduplicated processing list")
assert(independentCount == 1 and #independentPositions == 1
	and independentMap["40,40,0"].care == true
	and independentMap["40,40,0"].fertilize == true
	and independentMap["40,40,0"].irrigation == false,
	"overlapping pipes must merge only their independently enabled farm services")
WaterPipe.pipes = savedRangePipes
WaterPipe.pipeByKey = savedRangePipeIndex
WaterPipe.refreshAutoTillOverridePipeCount()

local savedSetRangePipes = WaterPipe.pipes
local savedSetRangeIndex = WaterPipe.pipeByKey
local savedSetRangeDirty = WaterPipe.markCoverageMapDirty
local savedSetRangeCare = WaterPipe.careForPipeArea
local rangeRegistryPipe = { x = 50, y = 60, z = 0 }
WaterPipe.pipes = { rangeRegistryPipe }
WaterPipe.rebuildPipeIndex()
local rangeModData = {}
local rangeTransmits, rangeDirty, rangeCare = 0, 0, 0
local rangeSquare = {
	getX = function() return 50 end,
	getY = function() return 60 end,
	getZ = function() return 0 end,
}
local rangeObject = {
	getSquare = function() return rangeSquare end,
	getModData = function() return rangeModData end,
	transmitModData = function() rangeTransmits = rangeTransmits + 1 end,
}
WaterPipe.markCoverageMapDirty = function() rangeDirty = rangeDirty + 1 end
WaterPipe.careForPipeArea = function(pipe, context)
	assert(pipe == rangeRegistryPipe and context == "range-change")
	rangeCare = rangeCare + 1
end
assert(WaterPipe.setObjectIrrigationRange(rangeObject, 7))
assert(rangeModData.irrigationRange == 7 and rangeRegistryPipe.irrigationRange == 7
	and rangeTransmits == 1 and rangeDirty == 1 and rangeCare == 1,
	"a custom range should persist, invalidate coverage, and care for its new area immediately")
assert(WaterPipe.setObjectIrrigationRange(rangeObject, 0))
assert(rangeModData.irrigationRange == nil and rangeRegistryPipe.irrigationRange == nil
	and rangeCare == 1,
	"shrinking to the global range must not immediately harvest the retained center")
assert(WaterPipe.setObjectIrrigationRange(rangeObject, 15)
	and rangeModData.irrigationRange == 15 and rangeRegistryPipe.irrigationRange == 15
	and rangeCare == 2,
	"the largest supported 15x15 range should be accepted and persisted")
assert(not WaterPipe.setObjectIrrigationRange(rangeObject, 13),
	"unsupported or excessive ranges must be rejected")
SandboxVars.WaterPipes.InfiniteAutoPlow = false
WaterPipe.autoTillPassPending = false
assert(WaterPipe.setObjectAutoTill(rangeObject, "enabled"))
assert(rangeModData.autoTillOverride == true and rangeRegistryPipe.autoTillOverride == true
	and WaterPipe.autoTillPassPending,
	"a per-pipe enable override should persist and schedule a batched till pass")
assert(WaterPipe.setObjectAutoTill(rangeObject, "disabled"))
assert(rangeModData.autoTillOverride == false and rangeRegistryPipe.autoTillOverride == false
	and not WaterPipe.autoTillPassPending,
	"a per-pipe disable override must preserve false and cancel work when nothing remains enabled")
assert(WaterPipe.setObjectAutoTill(rangeObject, "global"))
assert(rangeModData.autoTillOverride == nil and rangeRegistryPipe.autoTillOverride == nil,
	"follow-global should remove the per-pipe auto-till override")
assert(not WaterPipe.setObjectAutoTill(rangeObject, "invalid"),
	"invalid per-pipe auto-till modes must be rejected")
local enabledFeatureContexts = {}
local savedCleanupRequest = WaterPipe.requestCleanupPass
local savedCleanupProcess = WaterPipe.processCleanupPass
local savedCleanupCancel = WaterPipe.cancelCleanupPass
local cleanupRequests, cleanupProcesses, cleanupCancels = 0, 0, 0
WaterPipe.requestCleanupPass = function() cleanupRequests = cleanupRequests + 1 return true end
WaterPipe.processCleanupPass = function() cleanupProcesses = cleanupProcesses + 1 return true end
WaterPipe.cancelCleanupPass = function() cleanupCancels = cleanupCancels + 1 end
WaterPipe.careForPipeArea = function(pipe, context)
	assert(pipe == rangeRegistryPipe)
	table.insert(enabledFeatureContexts, context)
end
assert(WaterPipe.setObjectCareEnabled(rangeObject, false)
	and rangeModData.careEnabled == false and rangeRegistryPipe.careEnabled == false,
	"care can be disabled without changing irrigation or auto-till")
assert(WaterPipe.setObjectCareEnabled(rangeObject, true)
	and enabledFeatureContexts[1] == "careEnabled-enabled",
	"enabling care should immediately process only this pipe's area")
assert(WaterPipe.setObjectFertilizationEnabled(rangeObject, false)
	and rangeModData.fertilizeEnabled == false
	and rangeRegistryPipe.fertilizeEnabled == false,
	"fertilization can be disabled independently")
assert(WaterPipe.setObjectFertilizationEnabled(rangeObject, true)
	and enabledFeatureContexts[2] == "fertilizeEnabled-enabled",
	"enabling fertilization should immediately process only this pipe's area")
assert(WaterPipe.setObjectCleanupEnabled(rangeObject, true)
	and rangeModData.cleanupEnabled == true and rangeRegistryPipe.cleanupEnabled == true
	and cleanupRequests == 1 and cleanupProcesses == 1,
	"enabling cleanup should immediately start one bounded cleanup pass")
assert(WaterPipe.setObjectCleanupEnabled(rangeObject, false)
	and rangeModData.cleanupEnabled == false and rangeRegistryPipe.cleanupEnabled == false
	and cleanupCancels == 1,
	"disabling the last cleanup pipe should cancel pending cleanup work")
WaterPipe.requestCleanupPass = savedCleanupRequest
WaterPipe.processCleanupPass = savedCleanupProcess
WaterPipe.cancelCleanupPass = savedCleanupCancel

local savedInstanceof = instanceof
local savedIsoFlagType = IsoFlagType
local savedIsoObjectType = IsoObjectType
IsoFlagType = { vegitation = "vegitation", canBeRemoved = "canBeRemoved", canBeCut = "canBeCut" }
IsoObjectType = { tree = "tree" }
instanceof = function(object, className) return object and object.className == className end
local function cleanupObject(className, spriteName, flags)
	local object = { className = className, removed = false }
	function object:getName() return nil end
	function object:getType() return self.className == "IsoTree" and "tree" or "object" end
	function object:getSprite()
		if not spriteName then return nil end
		return {
			getName = function() return spriteName end,
			getProperties = function()
				return { has = function(_, flag) return flags and flags[flag] == true end }
			end,
		}
	end
	function object:removeFromWorld() self.removedFromWorld = true end
	function object:removeFromSquare() self.removedFromSquare = true end
	return object
end
local cleanupZombie = cleanupObject("IsoZombie")
local cleanupCorpse = cleanupObject("IsoDeadBody")
function cleanupCorpse:isZombie() return true end
local animalCorpse = cleanupObject("IsoDeadBody")
function animalCorpse:isZombie() return false end
local cleanupTree = cleanupObject("IsoTree", "vegetation_trees_01_0")
local cleanupWeed = cleanupObject("IsoObject", "vegetation_groundcover_01_0", { vegitation = true })
local cleanupCrop = cleanupObject("IsoObject", "vegetation_farming_01_0", { vegitation = true })
local cleanupGroundItem = cleanupObject("IsoWorldInventoryObject")
local cleanupPipe = cleanupObject("IsoObject", "infinite_irrigation_pipes_01_0")
function cleanupPipe:getName() return "WaterPipe" end
local cleanupObjects = { cleanupTree, cleanupWeed, cleanupCrop, cleanupGroundItem, cleanupPipe }
local cleanupSquare = {}
cleanupSquare.getMovingObjects = function() return objectList({ cleanupZombie }) end
cleanupSquare.getStaticMovingObjects = function()
	return objectList({ cleanupCorpse, animalCorpse })
end
cleanupSquare.getObjects = function() return objectList(cleanupObjects) end
cleanupSquare.removeCorpse = function(_, body) body.removed = true end
cleanupSquare.transmitRemoveItemFromSquare = function(_, object)
	object.transmittedRemoval = true
end
cleanupSquare.RemoveTileObject = function(_, object)
	object.removed = true
	for i = #cleanupObjects, 1, -1 do
		if cleanupObjects[i] == object then table.remove(cleanupObjects, i) end
	end
end
cleanupSquare.removeBlood = function() cleanupSquare.bloodRemoved = true end
local cleanupResult = WaterPipe.cleanupSquare(cleanupSquare)
assert(cleanupResult.zombies == 1 and cleanupZombie.removedFromWorld
	and cleanupZombie.removedFromSquare,
	"cleanup must remove live zombies through the world and square paths")
assert(cleanupResult.corpses == 1 and cleanupCorpse.removed and not animalCorpse.removed,
	"cleanup must remove zombie corpses without deleting animal corpses")
assert(cleanupResult.vegetation == 2 and cleanupTree.removed and cleanupWeed.removed
	and not cleanupCrop.removed and not cleanupPipe.removed,
	"cleanup must remove trees and weeds while preserving crops and the pipe")
assert(cleanupResult.groundItems == 1 and cleanupGroundItem.transmittedRemoval
	and cleanupGroundItem.removedFromWorld and cleanupGroundItem.removedFromSquare,
	"cleanup must remove dropped world items through synchronized removal paths")
assert(cleanupResult.blood == 1 and cleanupSquare.bloodRemoved,
	"cleanup must clear blood on every covered square")

SandboxVars.WaterPipes.CleanupVegetation = false
SandboxVars.WaterPipes.CleanupTrees = true
SandboxVars.WaterPipes.CleanupZombies = false
SandboxVars.WaterPipes.CleanupCorpses = false
SandboxVars.WaterPipes.CleanupBlood = false
SandboxVars.WaterPipes.CleanupGroundItems = false
local selectiveTree = cleanupObject("IsoTree", "vegetation_trees_01_0")
local selectiveWeed = cleanupObject("IsoObject", "vegetation_groundcover_01_0",
	{ vegitation = true })
local selectiveItem = cleanupObject("IsoWorldInventoryObject")
local selectiveObjects = { selectiveTree, selectiveWeed, selectiveItem }
local selectiveSquare = {
	getMovingObjects = function() return objectList({ cleanupObject("IsoZombie") }) end,
	getStaticMovingObjects = function() return objectList({ cleanupObject("IsoDeadBody") }) end,
	getObjects = function() return objectList(selectiveObjects) end,
	transmitRemoveItemFromSquare = function(_, object) object.transmittedRemoval = true end,
	RemoveTileObject = function(_, object) object.removed = true end,
	removeCorpse = function(_, body) body.removed = true end,
	removeBlood = function() selectiveSquare.bloodRemoved = true end,
}
local selectiveResult = WaterPipe.cleanupSquare(selectiveSquare)
assert(selectiveResult.vegetation == 1 and selectiveTree.removed
	and not selectiveWeed.removed and not selectiveItem.removed,
	"tree and weed cleanup categories must be independently selectable")
assert(selectiveResult.zombies == 0 and selectiveResult.corpses == 0
	and selectiveResult.groundItems == 0 and selectiveResult.blood == 0,
	"disabled cleanup categories must leave their world objects untouched")
SandboxVars.WaterPipes.CleanupVegetation = true
SandboxVars.WaterPipes.CleanupTrees = false
local inverseTree = cleanupObject("IsoTree", "vegetation_trees_01_0")
local inverseWeed = cleanupObject("IsoObject", "vegetation_groundcover_01_0",
	{ vegitation = true })
local inverseObjects = { inverseTree, inverseWeed }
local inverseSquare = {
	getObjects = function() return objectList(inverseObjects) end,
	transmitRemoveItemFromSquare = function(_, object) object.transmittedRemoval = true end,
	RemoveTileObject = function(_, object) object.removed = true end,
}
local inverseResult = WaterPipe.cleanupSquare(inverseSquare)
assert(inverseResult.vegetation == 1 and not inverseTree.removed and inverseWeed.removed,
	"disabling tree cleanup must not disable the separately selected weed cleanup")
SandboxVars.WaterPipes.CleanupVegetation = nil
SandboxVars.WaterPipes.CleanupTrees = nil
SandboxVars.WaterPipes.CleanupZombies = nil
SandboxVars.WaterPipes.CleanupCorpses = nil
SandboxVars.WaterPipes.CleanupBlood = nil
SandboxVars.WaterPipes.CleanupGroundItems = nil
instanceof = savedInstanceof
IsoFlagType = savedIsoFlagType
IsoObjectType = savedIsoObjectType
WaterPipe.pipes = savedSetRangePipes
WaterPipe.pipeByKey = savedSetRangeIndex
WaterPipe.refreshAutoTillOverridePipeCount()
WaterPipe.refreshCleanupEnabledPipeCount()
WaterPipe.markCoverageMapDirty = savedSetRangeDirty
WaterPipe.careForPipeArea = savedSetRangeCare

local originalTryAutoTillPosition = WaterPipe.tryAutoTillPosition
local originalAutoTillTimestamp = WaterPipe.getTimestamp
local oneShotPositions = {}
for i = 1, 60 do
	table.insert(oneShotPositions, { x = i, y = 1, z = 0, autoTill = true })
end
local oneShotVisits = {}
WaterPipe.tryAutoTillPosition = function(x)
	table.insert(oneShotVisits, x)
	return true
end
WaterPipe.getTimestamp = function() return 0 end
WaterPipe.pipes = { { x = 1, y = 1, z = 0 } }
WaterPipe.coveragePositions = oneShotPositions
WaterPipe.coveragePositionCount = #oneShotPositions
WaterPipe.autoTillPositions = oneShotPositions
WaterPipe.autoTillPositionCount = #oneShotPositions
WaterPipe.lastCoverageMap = { ready = true }
WaterPipe.coverageMapNeedsUpdate = false
WaterPipe.coverageTimeBudgetMs = 0
SandboxVars.WaterPipes.InfiniteAutoPlow = true
assert(WaterPipe.requestAutoTillPass(), "enabling auto-till should schedule a one-shot pass")
local firstPassComplete, firstTilled, firstProcessed = WaterPipe.processAutoTillPass()
assert(not firstPassComplete and firstTilled == 50 and firstProcessed == 50,
	"the first auto-till batch should stop at the adaptive batch size")
assert(WaterPipe.autoTillPassPending and WaterPipe.autoTillProcessing.currentIndex == 51,
	"an incomplete auto-till pass should preserve its next position")
local secondPassComplete, secondTilled, secondProcessed = WaterPipe.processAutoTillPass()
assert(secondPassComplete and secondTilled == 10 and secondProcessed == 10,
	"later minute batches should finish the one-shot pass")
assert(not WaterPipe.autoTillPassPending and WaterPipe.autoTillProcessing == nil,
	"a completed one-shot auto-till pass should remove its scheduling state")
WaterPipe.tryAutoTillPosition = originalTryAutoTillPosition
WaterPipe.getTimestamp = originalAutoTillTimestamp
WaterPipe.coverageTimeBudgetMs = 2
SandboxVars.WaterPipes.InfiniteAutoPlow = false

local savedFarmingSystemForPlow = SFarmingSystem
local savedPlantClassForPlow = SPlantGlobalObject
local savedGetTextForPlow = getText
local corruptedFurrow = {
	typeOfSeed = "none", state = "seeded", objectName = "Farming_none",
	nbOfGrow = 2, hasSeed = true, hasVegetable = true, saved = 0,
}
local corruptedIsoObject = {
	name = "Farming_none", spriteName = "vegetation_farming_01_7", modData = {},
}
function corruptedIsoObject:getName() return self.name end
function corruptedIsoObject:getSpriteName() return self.spriteName end
function corruptedFurrow:getIsoObject() return corruptedIsoObject end
function corruptedFurrow:stateToIsoObject(isoObject)
	isoObject.name = self.objectName
	isoObject.spriteName = self.spriteName
	isoObject.modData.state = self.state
	isoObject.modData.typeOfSeed = self.typeOfSeed
	self.saved = self.saved + 1
end
function corruptedFurrow:saveData() self.saved = self.saved + 1 end
local furrowSquare = {}
SFarmingSystem = {
	instance = {
		plow = function() end,
		getLuaObjectOnSquare = function() return corruptedFurrow end,
		getLuaObjectAt = function() return corruptedFurrow end,
	},
}
SPlantGlobalObject = nil
getText = function(key)
	if key == "Farming_Plowed_Land" then return "Plowed Land" end
	return key
end
assert(WaterPipe.AutoTill.executeTill(furrowSquare, 4, 5, 0),
	"auto-till should complete while normalizing its resulting furrow")
assert(corruptedFurrow.state == "plow"
	and corruptedFurrow.typeOfSeed == "none"
	and corruptedFurrow.objectName == "Plowed Land"
	and corruptedFurrow.spriteName == "vegetation_farming_01_1"
	and corruptedFurrow.nbOfGrow == -1
	and corruptedFurrow.hasSeed == false
	and corruptedFurrow.hasVegetable == false
	and corruptedIsoObject.name == "Plowed Land"
	and corruptedIsoObject.spriteName == "vegetation_farming_01_1"
	and corruptedIsoObject.modData.state == "plow"
	and corruptedFurrow.saved == 1,
	"a Farming_none furrow must restore both vanilla data and its world object")
corruptedFurrow.state = "seeded"
corruptedFurrow.objectName = "Farming_none"
corruptedIsoObject.name = "Farming_none"
corruptedIsoObject.spriteName = "vegetation_farming_01_7"
assert(WaterPipe.detectPlantAt(4, 5, 0) == nil
	and corruptedFurrow.state == "plow"
	and corruptedFurrow.objectName == "Plowed Land"
	and corruptedIsoObject.name == "Plowed Land"
	and corruptedFurrow.saved == 2,
	"periodic detection should repair already-corrupted furrows from old saves")

corruptedFurrow.typeOfSeed = nil
corruptedFurrow.state = "plow"
corruptedFurrow.objectName = "Farming_none"
corruptedIsoObject.name = "Farming_none"
assert(WaterPipe.normalizePlowedLand(corruptedFurrow)
	and corruptedFurrow.typeOfSeed == "none"
	and corruptedIsoObject.name == "Plowed Land"
	and corruptedFurrow.saved == 3,
	"legacy empty furrows with a missing seed field should also migrate")
SFarmingSystem = savedFarmingSystemForPlow
SPlantGlobalObject = savedPlantClassForPlow
getText = savedGetTextForPlow

local originalCareForPipeArea = WaterPipe.careForPipeArea
local placementCarePipe = nil
local placementCareContext = nil
WaterPipe.careForPipeArea = function(pipe, context)
	placementCarePipe = pipe
	placementCareContext = context
end
WaterPipe.pipes = {}
WaterPipe.modData = { WaterPipes = { pipes = {} } }
WaterPipe.rebuildPipeIndex()
local registrySquare = {
	getX = function() return 30 end,
	getY = function() return 40 end,
	getZ = function() return 0 end,
}
local registryModData = { pipeType = "lineOption", autoTillOverride = false }
local registryObject = {
	getSquare = function() return registrySquare end,
	getModData = function() return registryModData end,
	transmitModData = function() end,
}
WaterPipe.loadPipe(registryObject)
assert(#WaterPipe.pipes == 1 and placementCarePipe == WaterPipe.pipes[1]
	and placementCareContext == "placement",
	"registering a new pipe should immediately care for only its own area")
assert(WaterPipe.getPipeAt(30, 40, 0) == WaterPipe.pipes[1],
	"registering a new pipe should update the coordinate index")
assert(WaterPipe.pipes[1].autoTillOverride == false,
	"loading a newly registered pipe must preserve an explicit false override")
assert(WaterPipe.pipes[1].autoSowEnabled == true
	and WaterPipe.pipes[1].autoHarvestEnabled == true
	and registryModData.autoSowEnabled == true
	and registryModData.autoHarvestEnabled == true,
	"new and legacy-unset pipe automation switches should migrate to enabled")
registryModData.autoSowEnabled = false
registryModData.autoHarvestEnabled = false
WaterPipe.loadPipe(registryObject)
assert(WaterPipe.pipes[1].autoSowEnabled == false
	and WaterPipe.pipes[1].autoHarvestEnabled == false,
	"loading a pipe must preserve switches that the player explicitly disabled")
WaterPipe.careForPipeArea = originalCareForPipeArea

assert(WaterPipeSprite.getFloorSprite(nil, "crossOption") == "infinite_irrigation_pipes_01_2",
	"pipe types should map to stable floor-layer tile sprites")
assert(WaterPipeSprite.getFloorSprite("media/textures/Item_PipeTW.png", nil)
	== "infinite_irrigation_pipes_01_10",
	"legacy direct-texture names should migrate to the matching tile sprite")

local hybridSpriteChanges = 0
local hybridSpriteObject = {
	getModData = function() return { waterSupplyPipe = true, pipeType = "lineOption" } end,
	setSprite = function() hybridSpriteChanges = hybridSpriteChanges + 1 end,
}
assert(not WaterPipeSprite.applyFloorSprite(hybridSpriteObject) and hybridSpriteChanges == 0,
	"hybrid pipes must retain the separate sprite that owns native water properties")

local inventory
local pipeItem = {}
local nextPipeItem = {}
local availablePipeItems = {
	[pipeItem] = true,
	[nextPipeItem] = true,
}
inventory = {
	containsRecursive = function(_, item) return availablePipeItems[item] == true end,
	getFirstTypeRecurse = function(_, itemType)
		assert(itemType == "WaterPipes.WaterPipe",
			"continuous placement should search for the full pipe item type")
		if availablePipeItems[pipeItem] then return pipeItem end
		if availablePipeItems[nextPipeItem] then return nextPipeItem end
		return nil
	end,
    Remove = function(_, item)
		assert(availablePipeItems[item], "placement should remove an available pipe item")
		availablePipeItems[item] = nil
    end,
}
pipeItem.getContainer = function() return inventory end
nextPipeItem.getContainer = function() return inventory end
local clearedHands = {}
local character = {
    getInventory = function() return inventory end,
    removeFromHands = function(_, item)
		clearedHands[item] = true
    end,
}
local objectModData = {}
local clientTransmits = 0
local placedObject = {
    getModData = function() return objectModData end,
    transmitCompleteItemToClients = function()
        clientTransmits = clientTransmits + 1
    end,
}
local addedObjects = 0
local square = {
	getX = function() return 3 end,
	getY = function() return 4 end,
	getZ = function() return 0 end,
    AddTileObject = function(_, object)
		assert(object == placedObject)
		addedObjects = addedObjects + 1
	end,
}
placedObject.getSquare = function() return square end
placedObject.getContainer = function(self) return self.container end
placedObject.setContainer = function(self, value) self.container = value end
ItemContainer = {
	new = function(containerType, targetSquare, parent)
		assert(containerType == "InfiniteIrrigationPipe"
			and targetSquare == square and parent == placedObject)
		local container = {}
		function container:getItems()
			return { size = function() return 0 end }
		end
		function container:setCapacity(value) self.capacity = value end
		function container:getCapacity() return self.capacity end
		function container:setExplored(value) self.explored = value end
		return container
	end,
}
getWorld = function()
    return {
        getCell = function()
            return {
                getGridSquare = function(_, x, y, z)
					assert((x == 3 or x == 4) and y == 4 and z == 0)
                    return square
                end,
            }
        end,
    }
end
IsoObject = {
    new = function(targetSquare, sprite, name)
        assert(targetSquare == square and sprite == "infinite_irrigation_pipes_01_0"
			and name == "WaterPipe")
        return placedObject
    end,
}
getSprite = function(name)
	if name == "infinite_irrigation_pipes_01_0" then
		return { getName = function() return name end }
	end
	return nil
end
local migratedSprite = nil
local migratedTile = nil
local legacyPipeObject = {
	getSprite = function()
		return { getName = function() return nil end }
	end,
	getSpriteName = function() return "media/textures/Item_PipeSE.png" end,
	getTile = function() return "media/textures/Item_PipeSE.png" end,
	getModData = function() return { pipeType = "lineOption" } end,
	setSprite = function(_, sprite) migratedSprite = sprite end,
	setTile = function(_, tile) migratedTile = tile end,
}
assert(WaterPipeSprite.applyFloorSprite(legacyPipeObject)
	and migratedSprite:getName() == "infinite_irrigation_pipes_01_0"
	and migratedTile == "infinite_irrigation_pipes_01_0",
	"legacy world objects should migrate to the registered floor-layer sprite")
local loadedObjects = 0
WaterPipe.loadPipe = function(object)
	assert(object == placedObject)
	loadedObjects = loadedObjects + 1
end
local inventorySyncs = 0
sendRemoveItemFromContainer = function(targetInventory, item)
	assert(targetInventory == inventory and clearedHands[item])
    inventorySyncs = inventorySyncs + 1
end

local builder = setmetatable({
    character = character,
    pipeItem = pipeItem,
    pipeType = "lineOption",
}, { __index = Pipe })
assert(builder:create(3, 4, 0, false, "pipe-sprite") == true,
    "server-authoritative placement should create the pipe")
assert(addedObjects == 1 and loadedObjects == 1,
    "placed pipe should be added to the square and irrigation registry")
assert(objectModData.pipeType == "lineOption" and objectModData.infinite == true,
    "placed pipe should carry its server-side mod data")
assert(clientTransmits == 1, "server should broadcast the completed pipe to clients")
assert(not availablePipeItems[pipeItem] and clearedHands[pipeItem] and inventorySyncs == 1,
    "server placement should consume and synchronize the pipe item")
assert(builder.pipeItem == pipeItem,
	"the persistent cursor should initially retain the consumed item reference")
assert(builder:create(4, 4, 0, false, "pipe-sprite") == true,
	"a second placement should replace the stale item reference and create another pipe")
assert(builder.pipeItem == nextPipeItem and not availablePipeItems[nextPipeItem]
	and clearedHands[nextPipeItem],
	"continuous placement should consume the next exact pipe item")
assert(addedObjects == 2 and loadedObjects == 2 and clientTransmits == 2
	and inventorySyncs == 2,
	"continuous placement should register and synchronize every placed pipe")
assert(builder:refreshPipeItem() == nil and builder:isValid(square, false) == false,
	"an exhausted pipe inventory should stop another empty placement action")

local presetPipeItem = {}
presetPipeItem.getContainer = function() return inventory end
availablePipeItems[presetPipeItem] = true
local originalCreatePlacedPipe = WaterSupplyPipe.createPlacedPipe
local presetModeCall = nil
WaterSupplyPipe.createPlacedPipe = function(targetSquare, mode, pipeType, modData)
	assert(targetSquare == square and mode == "both" and pipeType == "lineOption")
	assert(modData.pipeType == "lineOption" and modData.infinite == true)
	presetModeCall = mode
	return placedObject
end
local presetBuilder = setmetatable({
	character = character,
	pipeItem = presetPipeItem,
	pipeType = "lineOption",
	initialMode = "both",
}, { __index = Pipe })
assert(presetBuilder:create(3, 4, 0, false, "pipe-sprite") == true
	and presetModeCall == "both",
	"the selected initial mode should create its final supply-capable object directly")
assert(not availablePipeItems[presetPipeItem] and clearedHands[presetPipeItem],
	"preset placement should consume the same single pipe inventory item")
WaterSupplyPipe.createPlacedPipe = originalCreatePlacedPipe

ShrinkCleanupTest = {
	savedPipes = WaterPipe.pipes,
	savedPipeIndex = WaterPipe.pipeByKey,
	savedFarmingSystem = SFarmingSystem,
	savedQueue = WaterPipe.shrunkFarmCleanupQueue,
	savedIndex = WaterPipe.shrunkFarmCleanupIndex,
	savedCoverageBudget = WaterPipe.coverageTimeBudgetMs,
}
ShrinkCleanupTest.source = {
	x = 0, y = 0, z = 0, irrigationRange = 5,
	cleanupShrunkFarmArea = true,
	irrigationEnabled = true, careEnabled = false, fertilizeEnabled = false,
}
ShrinkCleanupTest.overlap = {
	x = 2, y = 0, z = 0, irrigationRange = 3,
	irrigationEnabled = true, careEnabled = false, fertilizeEnabled = false,
}
WaterPipe.pipes = { ShrinkCleanupTest.source, ShrinkCleanupTest.overlap }
WaterPipe.rebuildPipeIndex()
WaterPipe.shrunkFarmCleanupQueue = {}
WaterPipe.shrunkFarmCleanupIndex = 1
WaterPipe.coverageTimeBudgetMs = 0
ShrinkCleanupTest.farmObjects = {}
ShrinkCleanupTest.x = -2
while ShrinkCleanupTest.x <= 2 do
	ShrinkCleanupTest.y = -2
	while ShrinkCleanupTest.y <= 2 do
		ShrinkCleanupTest.farmObjects[WaterPipe.getPipeKey(
			ShrinkCleanupTest.x, ShrinkCleanupTest.y, 0
		)] = { x = ShrinkCleanupTest.x, y = ShrinkCleanupTest.y, z = 0 }
		ShrinkCleanupTest.y = ShrinkCleanupTest.y + 1
	end
	ShrinkCleanupTest.x = ShrinkCleanupTest.x + 1
end
ShrinkCleanupTest.removed = 0
SFarmingSystem = {
	instance = {
		getLuaObjectAt = function(_, x, y, z)
			return ShrinkCleanupTest.farmObjects[WaterPipe.getPipeKey(x, y, z)]
		end,
		removePlant = function(_, plant)
			ShrinkCleanupTest.key = WaterPipe.getPipeKey(plant.x, plant.y, plant.z)
			if ShrinkCleanupTest.farmObjects[ShrinkCleanupTest.key] then
				ShrinkCleanupTest.farmObjects[ShrinkCleanupTest.key] = nil
				ShrinkCleanupTest.removed = ShrinkCleanupTest.removed + 1
			end
		end,
	},
}
assert(WaterPipe.queueShrunkFarmCleanup(ShrinkCleanupTest.source, 5, 3) == 16,
	"shrinking 5x5 to 3x3 should queue only the sixteen retired outer cells")
ShrinkCleanupTest.source.irrigationRange = 3
ShrinkCleanupTest.complete, ShrinkCleanupTest.cleanupRemoved,
	ShrinkCleanupTest.processed = WaterPipe.processShrunkFarmCleanup()
assert(ShrinkCleanupTest.complete and ShrinkCleanupTest.processed == 16
	and ShrinkCleanupTest.cleanupRemoved == 13 and ShrinkCleanupTest.removed == 13,
	"retired farmland cleanup should remove the old ring in one bounded pass")
assert(ShrinkCleanupTest.farmObjects[WaterPipe.getPipeKey(2, -1, 0)]
	and ShrinkCleanupTest.farmObjects[WaterPipe.getPipeKey(2, 0, 0)]
	and ShrinkCleanupTest.farmObjects[WaterPipe.getPipeKey(2, 1, 0)],
	"retired cells still covered by another farming pipe must be preserved")
assert(WaterPipe.queueShrunkFarmCleanup(ShrinkCleanupTest.source, 3, 5) == 0,
	"growing a range must never schedule destructive cleanup")
ShrinkCleanupTest.source.cleanupShrunkFarmArea = false
assert(WaterPipe.queueShrunkFarmCleanup(ShrinkCleanupTest.source, 5, 1) == 0,
	"the destructive cleanup must remain opt-in per pipe")
ShrinkCleanupTest.source.cleanupShrunkFarmArea = true
ShrinkCleanupTest.source.irrigationRange = 5
assert(WaterPipe.queueShrunkFarmCleanup(ShrinkCleanupTest.source, 5, 3) == 16)
ShrinkCleanupTest.ignoreComplete, ShrinkCleanupTest.expandedRemoved =
	WaterPipe.processShrunkFarmCleanup()
assert(ShrinkCleanupTest.expandedRemoved == 0,
	"expanding back before a queued batch runs must cancel deletion for restored cells")

-- Exercise the minimum-range boundary explicitly: 3x3 -> 1x1 must retain the
-- center and remove exactly the eight retired surrounding cells.
ShrinkCleanupTest.source.irrigationRange = 3
ShrinkCleanupTest.source.cleanupShrunkFarmArea = true
WaterPipe.pipes = { ShrinkCleanupTest.source }
WaterPipe.rebuildPipeIndex()
WaterPipe.shrunkFarmCleanupQueue = {}
WaterPipe.shrunkFarmCleanupIndex = 1
ShrinkCleanupTest.farmObjects = {}
ShrinkCleanupTest.x = -1
while ShrinkCleanupTest.x <= 1 do
	ShrinkCleanupTest.y = -1
	while ShrinkCleanupTest.y <= 1 do
		ShrinkCleanupTest.farmObjects[WaterPipe.getPipeKey(
			ShrinkCleanupTest.x, ShrinkCleanupTest.y, 0
		)] = {
			x = ShrinkCleanupTest.x,
			y = ShrinkCleanupTest.y,
			z = 0,
			-- Mix planted crops and empty tilled farmland in the retired ring.
			state = (ShrinkCleanupTest.x + ShrinkCleanupTest.y) % 2 == 0
				and "seeded" or "plow",
		}
		ShrinkCleanupTest.y = ShrinkCleanupTest.y + 1
	end
	ShrinkCleanupTest.x = ShrinkCleanupTest.x + 1
end
-- One retired furrow intentionally has only a visible farming IsoObject and no
-- SFarmingSystem Lua object, matching old partially migrated Farming_none data.
ShrinkCleanupTest.orphanKey = WaterPipe.getPipeKey(1, 0, 0)
ShrinkCleanupTest.farmObjects[ShrinkCleanupTest.orphanKey] = nil
ShrinkCleanupTest.orphanRemoved = false
ShrinkCleanupTest.orphanObject = {
	getName = function() return "Farming_none" end,
	getSpriteName = function() return "vegetation_farming_01_1" end,
}
ShrinkCleanupTest.orphanObjects = { ShrinkCleanupTest.orphanObject }
ShrinkCleanupTest.orphanSquare = {
	getObjects = function() return objectList(ShrinkCleanupTest.orphanObjects) end,
	transmitRemoveItemFromSquare = function(_, object)
		if object == ShrinkCleanupTest.orphanObject then
			ShrinkCleanupTest.orphanObjects = {}
			ShrinkCleanupTest.orphanRemoved = true
		end
	end,
}
ShrinkCleanupTest.savedGetCell = getCell
getCell = function()
	return {
		getGridSquare = function(_, x, y, z)
			if x == 1 and y == 0 and z == 0 then return ShrinkCleanupTest.orphanSquare end
		end,
	}
end
ShrinkCleanupTest.removed = 0
assert(WaterPipe.queueShrunkFarmCleanup(ShrinkCleanupTest.source, 3, 1) == 8,
	"shrinking 3x3 to 1x1 should queue exactly the retired eight-cell ring")
ShrinkCleanupTest.source.irrigationRange = 1
ShrinkCleanupTest.minimumComplete, ShrinkCleanupTest.minimumRemoved,
	ShrinkCleanupTest.minimumProcessed = WaterPipe.processShrunkFarmCleanup()
assert(ShrinkCleanupTest.minimumComplete and ShrinkCleanupTest.minimumProcessed == 8
	and ShrinkCleanupTest.minimumRemoved == 8 and ShrinkCleanupTest.orphanRemoved,
	"the retired ring must remove both planted crops and empty tilled farmland")
assert(ShrinkCleanupTest.farmObjects[WaterPipe.getPipeKey(0, 0, 0)] ~= nil,
	"3x3 to 1x1 cleanup must always preserve the center farmland")
WaterPipe.pipes = ShrinkCleanupTest.savedPipes
WaterPipe.pipeByKey = ShrinkCleanupTest.savedPipeIndex
SFarmingSystem = ShrinkCleanupTest.savedFarmingSystem
WaterPipe.shrunkFarmCleanupQueue = ShrinkCleanupTest.savedQueue
WaterPipe.shrunkFarmCleanupIndex = ShrinkCleanupTest.savedIndex
WaterPipe.coverageTimeBudgetMs = ShrinkCleanupTest.savedCoverageBudget
getCell = ShrinkCleanupTest.savedGetCell
ShrinkCleanupTest = nil

package.preload["ISUI/ISCollapsableWindow"] = function() return true end
package.preload["ISUI/ISRichTextPanel"] = function() return true end
package.preload["ISUI/ISButton"] = function() return true end
package.preload["ISUI/ISComboBox"] = function() return true end
package.preload["ISUI/Maps/ISWorldMap"] = function() return true end
WaterPipe.pipes = {
    { x = 0, y = 0, z = 0 },
    { x = 1, y = 0, z = 0 },
    { x = 8, y = 8, z = 0 },
    { x = 0, y = 0, z = 0 },
}
dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/client/WaterPipe/WaterPipeNetworksUI.lua")
local networks = WaterPipeNetworksUI.getPipeNetworks()
assert(#networks == 2, "adjacent pipes should form one display group")
assert(#networks[1] == 2 and #networks[2] == 1,
    "network UI should deduplicate pipe coordinates")

local vanillaHarvestCalls = 0
local currentClientPlant = { state = "seeded" }
ISFarmingMenu = {
	cursor = { sq = {} },
	getPlantName = function() return "Test Crop" end,
	isValidPlant = function() return true end,
}
function ISFarmingMenu:isHarvestValid()
	vanillaHarvestCalls = vanillaHarvestCalls + 1
	return "vanilla-result"
end
CFarmingSystem = {
	instance = {
		getLuaObjectOnSquare = function() return currentClientPlant end,
	},
}
dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/client/ISUI/ISFarmingMenu.lua")
assert(ISFarmingMenu:isHarvestValid() == "vanilla-result" and vanillaHarvestCalls == 1,
	"normal plants should use the current vanilla harvest validation")
currentClientPlant = {
	state = "harvest",
	canHarvest = function() return true end,
}
assert(ISFarmingMenu:isHarvestValid() == true and vanillaHarvestCalls == 1,
	"legacy harvest-state plants should use only the narrow compatibility path")

originalPrint("PASS test_waterpipe.lua")
