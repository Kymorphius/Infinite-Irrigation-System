local vanillaDestroyCalls = 0
SPlantGlobalObject = {
    destroyThis = function(self)
        vanillaDestroyCalls = vanillaDestroyCalls + 1
        self.state = "destroyed"
    end,
}

package.preload["Farming/SPlantGlobalObject"] = function()
    return SPlantGlobalObject
end

SandboxVars = { WaterPipes = { PreventFarmlandDestruction = true } }
dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/server/WaterPipeFarmlandProtection.lua")

local plant = { state = "seeded" }
SPlantGlobalObject.destroyThis(plant)
assert(plant.state == "seeded" and vanillaDestroyCalls == 0,
    "farmland protection should stop trampling at the shared destroy entry point")

SandboxVars.WaterPipes.PreventFarmlandDestruction = false
SPlantGlobalObject.destroyThis(plant)
assert(plant.state == "destroyed" and vanillaDestroyCalls == 1,
    "disabling farmland protection should preserve vanilla destruction")

print("WaterPipe farmland-protection tests passed")
