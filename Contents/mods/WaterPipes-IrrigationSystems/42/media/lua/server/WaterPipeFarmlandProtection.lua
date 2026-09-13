require "Farming/SPlantGlobalObject"

local destroyThis = SPlantGlobalObject.destroyThis

function SPlantGlobalObject:destroyThis()
    if SandboxVars and SandboxVars.WaterPipes
        and SandboxVars.WaterPipes.PreventFarmlandDestruction == true then
        return
    end
    return destroyThis(self)
end
