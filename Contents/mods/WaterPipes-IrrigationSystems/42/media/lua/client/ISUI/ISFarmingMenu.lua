-- Preserve the current vanilla Build 42 validation for all normal plants.
-- The only exception is the legacy custom "harvest" state written by older
-- releases of this mod; the server migrates those plants back to "seeded".
local vanillaIsHarvestValid = ISFarmingMenu.isHarvestValid

function ISFarmingMenu:isHarvestValid()
	local cursor = ISFarmingMenu.cursor
	if cursor then
		local plant = CFarmingSystem.instance:getLuaObjectOnSquare(cursor.sq)
		if plant and plant.state == "harvest"
				and ISFarmingMenu.isValidPlant(plant)
				and plant.canHarvest and plant:canHarvest() then
			cursor.tooltipTxt = ISFarmingMenu.getPlantName(plant) .. " "
			return true
		end
	end

	return vanillaIsHarvestValid(self)
end
