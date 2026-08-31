require "Farming/ISUI/ISFarmingMenu"

-- A stale or partially initialized unseeded furrow can briefly reach the
-- client before its repaired state is synchronized. Vanilla hides Info for a
-- normal state="plow" furrow, but Farming_none otherwise reaches
-- ISFarmingInfo and crashes while looking up farming_vegetableconf.props.none.
-- Chain the current handler and reject only that impossible info request.
if ISFarmingMenu and ISFarmingMenu.onInfo
	and not ISFarmingMenu.__InfiniteIrrigationInfoGuard then
	local originalOnInfo = ISFarmingMenu.onInfo
	local function guardedOnInfo(worldobjects, plant, square, playerObject)
		if not plant or plant.typeOfSeed == "none" then return end
		return originalOnInfo(worldobjects, plant, square, playerObject)
	end

	ISFarmingMenu.__InfiniteIrrigationInfoOriginal = originalOnInfo
	ISFarmingMenu.__InfiniteIrrigationInfoGuard = guardedOnInfo
	ISFarmingMenu.onInfo = guardedOnInfo
end

return ISFarmingMenu
