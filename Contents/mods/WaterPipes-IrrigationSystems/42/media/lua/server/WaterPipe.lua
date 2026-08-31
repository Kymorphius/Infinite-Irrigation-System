-- 发布版默认关闭本文件的调试输出，但绝不覆盖全局 print。
-- 覆盖全局函数会连带关闭原版和其他 Mod 的 Lua 日志。
require "WaterPipe/PipeSprites"

local systemPrint = print
local debugLoggingEnabled = false
local function print(...)
	if debugLoggingEnabled then
		systemPrint(...)
	end
end

WaterPipe = {}

-- 🚜 自动翻土模块初始化
WaterPipe.AutoTill = {}

-- 🔧 AutoTill配置参数
WaterPipe.AutoTill.config = {
    enableDebug = false           -- 启用调试日志
}

-- 🕐 安全的时间获取函数
function WaterPipe.getTimestamp()
	-- 尝试多种时间API，确保兼容性
	if getTimestampMs then
		return getTimestampMs()
	elseif os and os.clock then
		return os.clock() * 1000
	elseif getGameTime then
		return math.floor(getGameTime():getTimeOfDay() * 86400000) -- 转换为毫秒
	else
		-- 备用方案：使用简单的递增计数器
		WaterPipe.timeCounter = (WaterPipe.timeCounter or 0) + 1
		return WaterPipe.timeCounter
	end
end

-- list of our pipes in the world
WaterPipe.pipes = {}
WaterPipe.pipeByKey = {}
WaterPipe.needsInitialPipePrune = true
WaterPipe.coverageTimeBudgetMs = 2
WaterPipe.coverageBudgetCheckInterval = 5
WaterPipe.coverageBuildMaxWorkItems = 300
WaterPipe.autoTillPassPending = false
WaterPipe.autoTillProcessing = nil
WaterPipe.lastAutoTillEnabled = nil
WaterPipe.lastGlobalAutoTillEnabled = nil
WaterPipe.autoTillOverridePipeCount = 0
WaterPipe.autoTillFollowGlobalPipeCount = 0
WaterPipe.autoTillPositions = {}
WaterPipe.autoTillPositionCount = 0
WaterPipe.cleanupEnabledPipeCount = 0
WaterPipe.cleanupPositions = {}
WaterPipe.cleanupPositionCount = 0
WaterPipe.cleanupPassPending = false
WaterPipe.cleanupProcessing = nil
WaterPipe.shrunkFarmCleanupQueue = {}
WaterPipe.shrunkFarmCleanupIndex = 1
WaterPipe.irrigationRangeSizes = { 1, 3, 5, 7, 9, 11, 15 }

function WaterPipe.getPipeKey(x, y, z)
	return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

function WaterPipe.isValidIrrigationRange(size)
	size = tonumber(size)
	for _, validSize in ipairs(WaterPipe.irrigationRangeSizes) do
		if size == validSize then return true end
	end
	return false
end

function WaterPipe.getGlobalIrrigationRange()
	local selected = SandboxVars and SandboxVars.WaterPipes
		and tonumber(SandboxVars.WaterPipes.IrrigationRange) or 2
	selected = math.floor(selected)
	return WaterPipe.irrigationRangeSizes[selected] or 3
end

function WaterPipe.getPipeIrrigationRange(pipe)
	local override = pipe and tonumber(pipe.irrigationRange)
	if WaterPipe.isValidIrrigationRange(override) then return override end
	return WaterPipe.getGlobalIrrigationRange()
end

function WaterPipe.getPipeIrrigationRadius(pipe)
	return math.floor((WaterPipe.getPipeIrrigationRange(pipe) - 1) / 2)
end

function WaterPipe.getGlobalAutoTillEnabled()
	return SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.InfiniteAutoPlow == true
end

function WaterPipe.getPipeAutoTillOverride(pipe)
	local override = pipe and pipe.autoTillOverride
	if type(override) == "boolean" then return override end
	return nil
end

function WaterPipe.isPipeAutoTillEnabled(pipe)
	local override = WaterPipe.getPipeAutoTillOverride(pipe)
	if override ~= nil then return override end
	return WaterPipe.getGlobalAutoTillEnabled()
end

-- Farming services are independent. Missing values are treated as enabled for
-- old irrigation-pipe save data; newly created non-farming presets write an
-- explicit false value before they enter the registry.
function WaterPipe.isPipeIrrigationEnabled(pipe)
	return pipe and pipe.irrigationEnabled ~= false
end

function WaterPipe.isPipeCareEnabled(pipe)
	return pipe and pipe.careEnabled ~= false
end

function WaterPipe.isPipeFertilizationEnabled(pipe)
	return pipe and pipe.fertilizeEnabled ~= false
end

function WaterPipe.isAutoFarmingModuleEnabled()
	return SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.EnableAutoFarming == true
end

function WaterPipe.getPipePlantFeatures(pipe)
	local autoFarmingEnabled = WaterPipe.isAutoFarmingModuleEnabled()
	return {
		irrigation = WaterPipe.isPipeIrrigationEnabled(pipe),
		care = WaterPipe.isPipeCareEnabled(pipe),
		fertilize = WaterPipe.isPipeFertilizationEnabled(pipe),
		autoSow = autoFarmingEnabled and pipe and pipe.autoSowEnabled == true,
		autoHarvest = autoFarmingEnabled and pipe and pipe.autoHarvestEnabled == true,
	}
end

function WaterPipe.hasPlantService(features)
	if type(features) == "boolean" then return features end
	return features and (features.irrigation == true or features.care == true
		or features.fertilize == true or features.autoSow == true
		or features.autoHarvest == true)
end

function WaterPipe.isPipeCleanupEnabled(pipe)
	return pipe and pipe.cleanupEnabled == true
end

function WaterPipe.refreshCleanupEnabledPipeCount()
	local count = 0
	for _, pipe in ipairs(WaterPipe.pipes) do
		if WaterPipe.isPipeCleanupEnabled(pipe) then count = count + 1 end
	end
	WaterPipe.cleanupEnabledPipeCount = count
	return count
end

function WaterPipe.hasAnyCleanupEnabled()
	return (tonumber(WaterPipe.cleanupEnabledPipeCount) or 0) > 0
end

-- Keep the recurring minute check O(1). The count is refreshed only when a
-- pipe is loaded, removed, changes mode, or changes its per-pipe override.
function WaterPipe.refreshAutoTillOverridePipeCount()
	local enabledCount = 0
	local followGlobalCount = 0
	for _, pipe in ipairs(WaterPipe.pipes) do
		local override = WaterPipe.getPipeAutoTillOverride(pipe)
		if override == true then
			enabledCount = enabledCount + 1
		elseif override == nil then
			followGlobalCount = followGlobalCount + 1
		end
	end
	WaterPipe.autoTillOverridePipeCount = enabledCount
	WaterPipe.autoTillFollowGlobalPipeCount = followGlobalCount
	return enabledCount, followGlobalCount
end

function WaterPipe.hasAnyAutoTillEnabled()
	if #WaterPipe.pipes == 0 then return false end
	if (tonumber(WaterPipe.autoTillOverridePipeCount) or 0) > 0 then return true end
	return WaterPipe.getGlobalAutoTillEnabled()
		and (tonumber(WaterPipe.autoTillFollowGlobalPipeCount) or 0) > 0
end

function WaterPipe.indexPipe(pipe)
	if not pipe or pipe.x == nil or pipe.y == nil or pipe.z == nil then return end
	WaterPipe.pipeByKey[WaterPipe.getPipeKey(pipe.x, pipe.y, pipe.z)] = pipe
end

-- Plant ownership in Build 42 uses the local player number in single-player
-- and the online ID in multiplayer. Store the same value on placed pipes so
-- ownerless crops can inherit a valid vanilla owner.
function WaterPipe.getCharacterOwnerId(character)
	if not character then return nil end
	local multiplayer = (isClient and isClient()) or (isServer and isServer())
	local ownerId = nil
	if multiplayer and character.getOnlineID then
		ownerId = tonumber(character:getOnlineID())
	elseif character.getPlayerNum then
		ownerId = tonumber(character:getPlayerNum())
	end
	if ownerId == nil or ownerId < 0 then return nil end
	return ownerId
end

function WaterPipe.claimObjectOwner(pipeObject, character)
	if not pipeObject or not pipeObject.getModData then return nil, false end
	local modData = pipeObject:getModData()
	local currentOwner = tonumber(modData["waterPipeOwner"])
	if currentOwner ~= nil and currentOwner >= 0 then
		return currentOwner, false
	end
	local square = pipeObject.getSquare and pipeObject:getSquare()
	local pipe = square and WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	if pipe and pipe.owner ~= nil then
		currentOwner = tonumber(pipe.owner)
		if currentOwner ~= nil and currentOwner >= 0 then
			modData["waterPipeOwner"] = currentOwner
			if pipeObject.transmitModData then pipeObject:transmitModData() end
			return currentOwner, true
		end
	end

	local ownerId = WaterPipe.getCharacterOwnerId(character)
	if ownerId == nil then return nil, false end
	modData["waterPipeOwner"] = ownerId
	if pipeObject.transmitModData then pipeObject:transmitModData() end

	if pipe and pipe.owner == nil then pipe.owner = ownerId end
	return ownerId, true
end

function WaterPipe.rebuildPipeIndex()
	WaterPipe.pipeByKey = {}
	for _, pipe in ipairs(WaterPipe.pipes) do
		WaterPipe.indexPipe(pipe)
	end
end

-- where data are saved
WaterPipe.modData = nil

function WaterPipe.loadTextures()
	getTexture('WaterPipe.png')
	getTexture('PipeCornerNE.png')
	getTexture('PipeCornerNW.png')
	getTexture('PipeCornerSE.png')
	getTexture('PipeCornerSW.png')
	getTexture('PipeCross.png')
	getTexture('PipeNorth.png')
	getTexture('PipeSE.png')
	getTexture('PipeTN.png')
	getTexture('PipeTS.png')
	getTexture('PipeTE.png')
	getTexture('PipeTW.png')
end

Events.OnGameBoot.Add(WaterPipe.loadTextures)

-- Remove every runtime and persisted record for a pipe coordinate.  Keeping
-- this in the server registry (instead of only in the pickup action) also lets
-- us clean up pipes removed by a sledgehammer, an admin tool, or another mod.
function WaterPipe.removePipeDataAt(x, y, z, markDirty)
	local removed = false
	local pipeKey = WaterPipe.getPipeKey(x, y, z)

	for i = #WaterPipe.pipes, 1, -1 do
		local pipe = WaterPipe.pipes[i]
		if pipe and pipe.x == x and pipe.y == y and pipe.z == z then
			table.remove(WaterPipe.pipes, i)
			removed = true
		end
	end

	local waterPipeData = WaterPipe.modData and WaterPipe.modData.WaterPipes
	local persistedPipes = waterPipeData and waterPipeData.pipes
	if persistedPipes then
		for i = #persistedPipes, 1, -1 do
			local pipe = persistedPipes[i]
			if pipe and pipe.x == x and pipe.y == y and pipe.z == z then
				table.remove(persistedPipes, i)
				removed = true
			end
		end
	end

	WaterPipe.pipeByKey[pipeKey] = nil
	if removed then
		WaterPipe.refreshAutoTillOverridePipeCount()
		WaterPipe.refreshCleanupEnabledPipeCount()
	end

	if removed and markDirty ~= false and WaterPipe.markCoverageMapDirty then
		WaterPipe.markCoverageMapDirty()
	end

	return removed
end

-- � 自适应批次大小计算：根据网络规模动态调整处理效率
-- 基于性能分析结果，为不同规模的灌溉网络提供最优的批次大小
function WaterPipe.getOptimalBatchSize(totalPositions)
	if not totalPositions or totalPositions <= 0 then
		return 25  -- 默认最小批次
	end
	
	-- 🔧 自适应批次大小策略：
	-- 小型网络(≤50): 25个位置/帧 - 保证响应性
	-- 中型网络(51-200): 50个位置/帧 - 平衡性能与体验  
	-- 大型网络(201-500): 100个位置/帧 - 提升处理效率
	-- 超大网络(>500): 300个位置/帧 - 最大化吞吐量
	
	if totalPositions <= 50 then
		return 25
	elseif totalPositions <= 200 then
		return 50
	elseif totalPositions <= 500 then
		return 100
	else
		return 300
	end
end

local function getRotDelay(plantConfig)
	local growTime = tonumber(plantConfig.timeToGrow) or 48
	return math.max(2, tonumber(plantConfig.rotTime) or math.floor(growTime / 2))
end

-- Keep harvest-ready plants on the last healthy vanilla growth stage.
-- Build 42 increments nbOfGrow after processing fullGrown, so fullGrown + 1
-- is the seed-bearing stage immediately before rottenThis() is called.
function WaterPipe.handleNoRotten(plant, plantType, context, plantConfig)
	if not plant then return false end
	local noRottenEnabled = SandboxVars.WaterPipes.InfiniteNoRotten
	local isLegacyHarvest = plant.state == "harvest"
	if not noRottenEnabled and not isLegacyHarvest then return false end

	plantConfig = plantConfig
		or (farming_vegetableconf and farming_vegetableconf.props and farming_vegetableconf.props[plantType])
	local fullGrown = plantConfig and tonumber(plantConfig.fullGrown)
	local growth = tonumber(plant.nbOfGrow)
	if not fullGrown or not growth then return false end
	if plant.state == "dead" or plant.state == "destroyed"
		or plant.state == "harvested" or plant.state == "plow" then
		return false
	end

	local isRotten = plant.state == "rotten"
	local safeGrowth = fullGrown + 1
	if not isRotten and not isLegacyHarvest and growth < safeGrowth then
		return false
	end

	local changed = false
	if plant.state ~= "seeded" then
		plant.state = "seeded"
		changed = true
	end
	if plant.nbOfGrow ~= safeGrowth then
		plant.nbOfGrow = safeGrowth
		changed = true
	end
	if not plant.hasVegetable then
		plant.hasVegetable = true
		changed = true
	end
	if not plant.hasSeed then
		plant.hasSeed = true
		changed = true
	end
	-- Compatibility with old saves and mods that read the plural alias.
	if not plant.hasSeeds then
		plant.hasSeeds = true
		changed = true
	end

	if isRotten then
		if not plant.health or plant.health < 100 then
			plant.health = 100
			changed = true
		end
		plant.badCare = false
		plant.cursed = false
	end

	local currentHour = SFarmingSystem.instance.hoursElapsed
	local rotDelay = getRotDelay(plantConfig)
	local guardWindow = math.max(1, math.min(6, rotDelay - 1))
	if not plant.nextGrowing or plant.nextGrowing <= currentHour + guardWindow then
		plant.nextGrowing = currentHour + rotDelay
		changed = true
	end

	if changed then
		print("[No Rotten] " .. plantType .. " retained at harvest stage [" .. context .. "]")
	end
	return changed
end

-- �🌱 统一植物护理系统：重构版
function WaterPipe.careForPlant(plant, context, features)
	if not plant then return false end
	features = features or { irrigation = true, care = true, fertilize = true }
	if not WaterPipe.hasPlantService(features) then return false end

	local plantType = plant.typeOfSeed or "Unknown"
	if plantType == "none" then
		print("[Care] Detected invalid plant type: none, skipping care [" .. context .. "]")
		return false
	end

	-- The seed wrapper runs before the vanilla timed action writes the sowing
	-- player, so leave that one context to vanilla. All later care passes may
	-- repair a still-ownerless legacy or mod-created crop from its pipe owner.
	local careProvided = context ~= "seed"
		and WaterPipe.bindPlantOwnerFromCoveringPipe(plant) or false
	local needsTextureRefresh = false
	local plantConfig = farming_vegetableconf and farming_vegetableconf.props
		and farming_vegetableconf.props[plantType]
	local isAlive = plant.isAlive and plant:isAlive() or false

	-- 1. 独立防止成熟植物腐烂（不依赖病虫害或复活选项）
	local noRottenDone = features.care == true
		and WaterPipe.handleNoRotten(plant, plantType, context, plantConfig) or false
	if noRottenDone then
		careProvided = true
		needsTextureRefresh = true
		-- 防腐处理可能会把腐烂状态恢复为可存活状态。
		isAlive = plant.isAlive and plant:isAlive() or false
	end

	-- 2. 进行病虫害护理
	local pestCareDone = features.care == true
		and WaterPipe.handlePestAndDisease(plant, plantType, context) or false
	if pestCareDone then
		careProvided = true
		needsTextureRefresh = true
	end

	-- 3. 进行复活处理
	local revivalDone = features.care == true
		and WaterPipe.handleRevival(plant, plantType, context, plantConfig, isAlive) or false
	if revivalDone then
		careProvided = true
		needsTextureRefresh = true
		-- 复活后的植物应在同一轮继续接受浇水和施肥。
		isAlive = plant.isAlive and plant:isAlive() or false
	end

	-- 4. 进行灌溉处理
	local irrigationDone = features.irrigation == true
		and WaterPipe.handleIrrigation(plant, plantType, context, plantConfig, isAlive) or false
	if irrigationDone then
		careProvided = true
	end

	-- 5. 进行施肥处理
	local fertilizationDone = features.fertilize == true
		and WaterPipe.handleFertilization(plant, plantType, context, isAlive) or false
	if fertilizationDone then
		careProvided = true
	end

	-- 6. 根据状态护理的返回值决定是否需要刷新贴图
	if needsTextureRefresh then
		WaterPipe.refreshPlantSprite(plant, plantType, context)
	end

	-- 保存植物状态
	if careProvided then
		plant:saveData()
	end

	return careProvided
end

-- 灌溉处理
function WaterPipe.handleIrrigation(plant, plantType, context, plantConfig, isAlive)
	if isAlive == nil then
		isAlive = plant.isAlive and plant:isAlive() or false
	end
	if not isAlive then return false end

	plantConfig = plantConfig
		or (farming_vegetableconf and farming_vegetableconf.props and farming_vegetableconf.props[plantType])
	local careProvided = false

	-- 🚿 常规灌溉护理
	local isWateredToNeeded = true
	local waterMaxLowerBias = 2
	local overWateredBias = 15
	local waterNeededLineBias = 8

	if plant.waterNeeded and plant.waterNeeded > 0 then
		local currentWater = plant.waterLvl or 0
		local targetWater = 100

		if isWateredToNeeded and plantConfig and plantConfig.waterNeeded then
			targetWater = plantConfig.waterNeeded + overWateredBias
		end

		if plantConfig and plantConfig.waterLvlMax then
			targetWater = math.min(targetWater, plantConfig.waterLvlMax - waterMaxLowerBias)
		end

		local waterNeededLine = targetWater - waterNeededLineBias
		if currentWater < waterNeededLine then
			plant.waterLvl = targetWater
			plant.autoWatered = true
			plant.lastWaterHour = SFarmingSystem.instance.hoursElapsed
			careProvided = true
			local maxInfo = plantConfig and plantConfig.waterLvlMax and ("Max:" .. plantConfig.waterLvlMax) or "NoMax"
			print("[Plant Care] " .. plantType .. " (" .. maxInfo .. ") watered from " .. currentWater .. " to " .. targetWater .. " [" .. context .. "]")
		end
	end
	return careProvided
end

-- 施肥处理
function WaterPipe.handleFertilization(plant, plantType, context, isAlive)
	if isAlive == nil then
		isAlive = plant.isAlive and plant:isAlive() or false
	end
	if not isAlive then return false end

	local careProvided = false
	local isInfiniteCompost = SandboxVars.WaterPipes.InfiniteCompost
	if isInfiniteCompost and plant.state ~= "plow" and plant.state ~= "destroyed" and not plant.compost then
		plant:compostPlant(10)
		careProvided = true
		plant.bonusYield = true
		print("[Plant Care] " .. plantType .. " received compost fertilization [" .. context .. "]")
	end
	return careProvided
end

-- 刷新植物贴图
function WaterPipe.refreshPlantSprite(plant, plantType, context)
	if farming_vegetableconf and farming_vegetableconf.getSpriteName then
		local newSpriteName = farming_vegetableconf.getSpriteName(plant)
		if newSpriteName and plant.setSpriteName then
			plant:setSpriteName(newSpriteName)
			print("[Visual Sync] " .. plantType .. " sprite synced to: " .. newSpriteName .. " (nbOfGrow: " .. tostring(plant.nbOfGrow) .. ") [" .. context .. "]")
		end
	end

	if plant.updateSprite then
		plant:updateSprite()
		print("[Visual Sync] " .. plantType .. " sprite force synced with growth value [" .. context .. "]")
	end

	if plant.square and plant.square.RecalcProperties then
		plant.square:RecalcProperties()
		print("[Visual Recovery] " .. plantType .. " square properties recalculated [" .. context .. "]")
	end
end

function WaterPipe.handlePestAndDisease(plant, plantType, context)
	if not plant then return false end

	local isInfinitePestCare = SandboxVars.WaterPipes.InfinitePestCare
	if not isInfinitePestCare then return false end

	local treatmentProvided = false
	
	-- 重置所有负面状态
	if plant.mildewLvl and plant.mildewLvl > 0 then plant.mildewLvl = 0; treatmentProvided = true end
	if plant.aphidLvl and plant.aphidLvl > 0 then plant.aphidLvl = 0; treatmentProvided = true end
	if plant.fliesLvl and plant.fliesLvl > 0 then plant.fliesLvl = 0; treatmentProvided = true end
	if plant.slugsLvl and plant.slugsLvl > 0 then plant.slugsLvl = 0; treatmentProvided = true end
	if plant.hasWeeds then plant.hasWeeds = false; treatmentProvided = true end
	
	-- 移除诅咒和不良护理标记
	if plant.cursed then plant.cursed = false; treatmentProvided = true end
	if plant.badCare then plant.badCare = false; treatmentProvided = true end

	-- 恢复健康
	if plant.health < 100 then
		plant.health = 100
		treatmentProvided = true
		print("[Health Recovery] Plant health restored to 100")
	end

	if treatmentProvided then
		print("[Pest Control] " .. plantType .. " all pests and diseases cured.")
	end

	return treatmentProvided
end


-- 复活与立即成熟统一处理
function WaterPipe.handleRevival(plant, plantType, context, plantConfig, isAlive)
	if not plant then return false end

	plantConfig = plantConfig
		or (farming_vegetableconf and farming_vegetableconf.props and farming_vegetableconf.props[plantType])
	if not plantConfig then return false end
	if isAlive == nil then
		isAlive = plant.isAlive and plant:isAlive() or false
	end

	local treatmentProvided = false
	local isInfiniteInstantGrowUp = SandboxVars.WaterPipes.InfiniteInstantGrowUp
	local isInfiniteRevive = SandboxVars.WaterPipes.InfiniteRevive

	local isDeadPlant = plant.state == "dead"
	local isRottenPlant = plant.state == "rotten"
	local isHarvestedPlant = plant.state == "harvested"
	
	plantType = plantType or plant.typeOfSeed or "Unknown"

	local growth = tonumber(plant.nbOfGrow)
	local canInstantGrow = isInfiniteInstantGrowUp and growth and isAlive
		and growth <= plantConfig.fullGrown
	local canRevive = isInfiniteRevive and (isDeadPlant or isRottenPlant or isHarvestedPlant)

	if not canInstantGrow and not canRevive then
		return false
	end

	-- 准备恢复，设置通用属性
	print("[Plant Recovery] Processing " .. plantType .. " for revival/growth [" .. context .. "]")
	local currentHour = SFarmingSystem.instance.hoursElapsed
	plant.lastWaterHour = currentHour
	plant.health = 100
	local rotDelay = getRotDelay(plantConfig)
	
	-- 优先执行立即成熟
	if canInstantGrow then
		print("[Instant Grow Up] Forcing " .. plantType .. " to fullGrown stage.")
		plant.state = "seeded"
		plant.nbOfGrow = plantConfig.fullGrown + 1
		plant.hasVegetable = true
		plant.hasSeed = true
		plant.hasSeeds = true
		plant.nextGrowing = currentHour + rotDelay
		treatmentProvided = true
	-- 否则，执行标准复活
	elseif canRevive then
		print("[Standard Revival] Reviving " .. plantType .. ".")
		local isInfiniteReviveToSeeded = SandboxVars.WaterPipes.InfiniteReviveToSeeded
		local originalGrowth = tonumber(plant.nbOfGrow) or 1
		local seedingLevel = plantConfig.fullGrown + 1
		local harvestLevel = plantConfig.harvestLevel or plantConfig.mature or plantConfig.fullGrown
		local targetGrowth = seedingLevel

		if isHarvestedPlant and isInfiniteReviveToSeeded then
			targetGrowth = 1
			plant.state = "seeded"
		else
			if originalGrowth >= seedingLevel then
				targetGrowth = seedingLevel
			elseif originalGrowth >= harvestLevel then
				targetGrowth = harvestLevel
			else
				targetGrowth = originalGrowth or math.min(2, harvestLevel - 1)
			end
			plant.state = "seeded"
		end
		plant.nbOfGrow = targetGrowth

		plant.hasVegetable = targetGrowth >= harvestLevel
		plant.hasSeed = targetGrowth >= seedingLevel
		plant.hasSeeds = plant.hasSeed
		plant.nextGrowing = currentHour + (targetGrowth >= seedingLevel and rotDelay or 1)
		
		treatmentProvided = true
	end

	if treatmentProvided then
		print("[Plant Recovery] Action complete for " .. plantType)
	end

	return treatmentProvided
end


function WaterPipe.loadPipes()
	if isClient() then return end

	WaterPipe.modData = GameTime:getInstance():getModData()

	WaterPipe.pipes = {}
	WaterPipe.pipeByKey = {}

	local pipeCount = 0
	if WaterPipe.modData and WaterPipe.modData.WaterPipes and WaterPipe.modData.WaterPipes.pipes then
		local persistedPipes = WaterPipe.modData.WaterPipes.pipes
		local uniquePersistedPipes = {}
		for i=1, #persistedPipes do
			local pipe = persistedPipes[i]
			if pipe and pipe.x ~= nil and pipe.y ~= nil and pipe.z ~= nil then
				if pipe.owner ~= nil then
					pipe.owner = tonumber(pipe.owner)
					if pipe.owner ~= nil and pipe.owner < 0 then pipe.owner = nil end
				end
				local key = WaterPipe.getPipeKey(pipe.x, pipe.y, pipe.z)
				if not WaterPipe.pipeByKey[key] then
					pipe.infinite = true
					if not WaterPipe.isValidIrrigationRange(pipe.irrigationRange) then
						pipe.irrigationRange = nil
					end
					if type(pipe.autoTillOverride) ~= "boolean" then
						pipe.autoTillOverride = nil
					end
					if type(pipe.irrigationEnabled) ~= "boolean" then
						pipe.irrigationEnabled = true
					end
					if type(pipe.careEnabled) ~= "boolean" then pipe.careEnabled = true end
					if type(pipe.fertilizeEnabled) ~= "boolean" then pipe.fertilizeEnabled = true end
					if type(pipe.cleanupEnabled) ~= "boolean" then pipe.cleanupEnabled = false end
					if type(pipe.cleanupShrunkFarmArea) ~= "boolean" then
						pipe.cleanupShrunkFarmArea = false
					end
					if type(pipe.autoSowEnabled) ~= "boolean" then pipe.autoSowEnabled = true end
					if type(pipe.autoHarvestEnabled) ~= "boolean" then pipe.autoHarvestEnabled = true end
					if WaterPipeAutoFarming then
						pipe.autoFarmSettings = WaterPipeAutoFarming.sanitizeSettings(
							pipe.autoFarmSettings
						)
					end
					table.insert(WaterPipe.pipes, pipe)
					table.insert(uniquePersistedPipes, pipe)
					WaterPipe.pipeByKey[key] = pipe
					pipeCount = pipeCount + 1
				end
			end
		end
		WaterPipe.modData.WaterPipes.pipes = uniquePersistedPipes
	end
	WaterPipe.needsInitialPipePrune = true
	WaterPipe.lastCoverageMap = nil
	WaterPipe.coveragePositions = nil
	WaterPipe.coveragePositionCount = 0
	WaterPipe.coverageProcessing = nil
	WaterPipe.coverageBuildState = nil
	WaterPipe.coverageMapNeedsUpdate = true
	WaterPipe.autoTillPassPending = false
	WaterPipe.autoTillProcessing = nil
	WaterPipe.lastAutoTillEnabled = nil
	WaterPipe.lastGlobalAutoTillEnabled = nil
	WaterPipe.autoTillPositions = {}
	WaterPipe.autoTillPositionCount = 0
	WaterPipe.cleanupPositions = {}
	WaterPipe.cleanupPositionCount = 0
	WaterPipe.cleanupPassPending = false
	WaterPipe.cleanupProcessing = nil
	WaterPipe.shrunkFarmCleanupQueue = {}
	WaterPipe.shrunkFarmCleanupIndex = 1
	WaterPipe.refreshAutoTillOverridePipeCount()
	WaterPipe.refreshCleanupEnabledPipeCount()
	if WaterPipe.hasAnyCleanupEnabled() and WaterPipe.requestCleanupPass then
		WaterPipe.requestCleanupPass()
	end

	print("WaterPipes: " .. pipeCount .. " loaded")
end

Events.OnGameStart.Add(WaterPipe.loadPipes)
Events.OnGameTimeLoaded.Add(WaterPipe.loadPipes)
Events.OnGameBoot.Add(WaterPipe.loadPipes)

-- load the pipe
function WaterPipe.loadPipe(pipeObject)
	print("XDEBUG: WaterPipe.loadPipe called", pipeObject)
    if not pipeObject or not pipeObject:getSquare() then return end
	if WaterSupplyPipe and WaterSupplyPipe.ensureStorage then
		WaterSupplyPipe.ensureStorage(pipeObject)
	end
	local shouldUseCanonicalFloor = isServer()
		or WaterPipeSprite.groundLayerEnabled ~= false
	local spriteChanged = shouldUseCanonicalFloor
		and WaterPipeSprite.applyFloorSprite(pipeObject) or false
	if spriteChanged and isServer() then
		pipeObject:transmitUpdatedSpriteToClients()
	end
	-- In single-player this server-side loader shares the world object with the
	-- client.  Reapply the local display preference after canonical migration so
	-- a saved pipe cannot be left on the Floor layer merely because this handler
	-- ran after the client square-load handler.
	if not isServer() and WaterPipeSprite.registerDisplayObject then
		WaterPipeSprite.registerDisplayObject(pipeObject)
	end
    local square = pipeObject:getSquare()
	local objectModData = pipeObject:getModData()
	local objectName = pipeObject.getName and pipeObject:getName() or "WaterPipe"
	local objectIrrigationEnabled = objectName == "WaterPipe"
	local defaultFarmEnabled = objectIrrigationEnabled
	local objectCareEnabled = objectModData["careEnabled"]
	local objectFertilizeEnabled = objectModData["fertilizeEnabled"]
	local objectCleanupEnabled = objectModData["cleanupEnabled"]
	local objectCleanupShrunkFarmArea = objectModData["cleanupShrunkFarmArea"]
	local objectAutoSowEnabled = objectModData["autoSowEnabled"]
	local objectAutoHarvestEnabled = objectModData["autoHarvestEnabled"]
	local objectAutoFarmSettings = WaterPipeAutoFarming
		and WaterPipeAutoFarming.sanitizeSettings(objectModData["autoFarmSettings"]) or {}
	local objectOwner = tonumber(objectModData["waterPipeOwner"])
	-- Old single-player pipes can be migrated unambiguously to player 0.
	if objectOwner == nil and not isClient() and not isServer() then
		objectOwner = 0
		objectModData["waterPipeOwner"] = objectOwner
	end
    local pipe = WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	if type(objectAutoSowEnabled) ~= "boolean" then
		if pipe and type(pipe.autoSowEnabled) == "boolean" then
			objectAutoSowEnabled = pipe.autoSowEnabled
		else
			objectAutoSowEnabled = true
		end
	end
	if type(objectAutoHarvestEnabled) ~= "boolean" then
		if pipe and type(pipe.autoHarvestEnabled) == "boolean" then
			objectAutoHarvestEnabled = pipe.autoHarvestEnabled
		else
			objectAutoHarvestEnabled = true
		end
	end
	if type(objectCareEnabled) ~= "boolean" then
		if pipe and type(pipe.careEnabled) == "boolean" then
			objectCareEnabled = pipe.careEnabled
		else
			objectCareEnabled = defaultFarmEnabled
		end
	end
	if type(objectFertilizeEnabled) ~= "boolean" then
		if pipe and type(pipe.fertilizeEnabled) == "boolean" then
			objectFertilizeEnabled = pipe.fertilizeEnabled
		else
			objectFertilizeEnabled = defaultFarmEnabled
		end
	end
	if type(objectCleanupEnabled) ~= "boolean" then
		objectCleanupEnabled = pipe and pipe.cleanupEnabled == true or false
	end
	if type(objectCleanupShrunkFarmArea) ~= "boolean" then
		objectCleanupShrunkFarmArea = pipe and pipe.cleanupShrunkFarmArea == true or false
	end
	objectModData["careEnabled"] = objectCareEnabled
	objectModData["fertilizeEnabled"] = objectFertilizeEnabled
	objectModData["cleanupEnabled"] = objectCleanupEnabled
	objectModData["cleanupShrunkFarmArea"] = objectCleanupShrunkFarmArea
	objectModData["autoSowEnabled"] = objectAutoSowEnabled
	objectModData["autoHarvestEnabled"] = objectAutoHarvestEnabled
	objectModData["autoFarmSettings"] = objectAutoFarmSettings

    if not pipe then -- if we don't have the pipe, it's basically when you load your saved game the first time
        pipe = {}
        pipe.x = square:getX()
        pipe.y = square:getY()
		pipe.z = square:getZ()
		pipe.pipeType = pipeObject:getModData()["pipeType"]
		pipe.owner = objectOwner
		pipe.irrigationEnabled = objectIrrigationEnabled
		pipe.careEnabled = objectCareEnabled
		pipe.fertilizeEnabled = objectFertilizeEnabled
		pipe.cleanupEnabled = objectCleanupEnabled
		pipe.cleanupShrunkFarmArea = objectCleanupShrunkFarmArea
		pipe.autoSowEnabled = objectAutoSowEnabled
		pipe.autoHarvestEnabled = objectAutoHarvestEnabled
		pipe.autoFarmSettings = objectAutoFarmSettings
		pipe.irrigationRange = WaterPipe.isValidIrrigationRange(
			pipeObject:getModData()["irrigationRange"]
		) and tonumber(pipeObject:getModData()["irrigationRange"]) or nil
		local objectAutoTillOverride = pipeObject:getModData()["autoTillOverride"]
		if type(objectAutoTillOverride) == "boolean" then
			pipe.autoTillOverride = objectAutoTillOverride
		else
			pipe.autoTillOverride = nil
		end
		pipe.infinite = true
		pipeObject:getModData()["infinite"] = true

		-- Ensure the persistent registry exists before recording a newly placed pipe.
        if not WaterPipe.modData or type(WaterPipe.modData) ~= "table" then
            WaterPipe.modData = {}
        end

        if not WaterPipe.modData.WaterPipes or type(WaterPipe.modData.WaterPipes) ~= "table" then
            WaterPipe.modData.WaterPipes = {}
        end

        if not WaterPipe.modData.WaterPipes.pipes or type(WaterPipe.modData.WaterPipes.pipes) ~= "table" then
            WaterPipe.modData.WaterPipes.pipes = {}
        end

        table.insert(WaterPipe.pipes, pipe)
        table.insert(WaterPipe.modData.WaterPipes.pipes, pipe)
		WaterPipe.indexPipe(pipe)
        
        -- 🌊 标记覆盖图需要更新
        WaterPipe.markCoverageMapDirty()

        -- 🚜 只立即处理新管道自己的 3x3 区域。全局覆盖图由每分钟任务统一重建，
        -- 避免大型农场放管道时扫描无关区域，也保证新覆盖范围立即生效。
        WaterPipe.careForPipeArea(pipe, "placement")

        print("pipe : new pipe created " .. pipe.x .. "," .. pipe.y)
	else
		pipe.infinite = true
		local servicesChanged = pipe.irrigationEnabled ~= objectIrrigationEnabled
			or pipe.careEnabled ~= objectCareEnabled
			or pipe.fertilizeEnabled ~= objectFertilizeEnabled
			or pipe.cleanupEnabled ~= objectCleanupEnabled
			or pipe.autoSowEnabled ~= objectAutoSowEnabled
			or pipe.autoHarvestEnabled ~= objectAutoHarvestEnabled
		pipe.irrigationEnabled = objectIrrigationEnabled
		pipe.careEnabled = objectCareEnabled
		pipe.fertilizeEnabled = objectFertilizeEnabled
		pipe.cleanupEnabled = objectCleanupEnabled
		pipe.cleanupShrunkFarmArea = objectCleanupShrunkFarmArea
		pipe.autoSowEnabled = objectAutoSowEnabled
		pipe.autoHarvestEnabled = objectAutoHarvestEnabled
		pipe.autoFarmSettings = objectAutoFarmSettings
		if servicesChanged then WaterPipe.markCoverageMapDirty() end
		if pipe.owner ~= nil then pipe.owner = tonumber(pipe.owner) end
		if pipe.owner == nil and objectOwner ~= nil then
			pipe.owner = objectOwner
		elseif pipe.owner ~= nil and objectOwner == nil then
			objectModData["waterPipeOwner"] = pipe.owner
		end
		local objectRange = tonumber(pipeObject:getModData()["irrigationRange"])
		if WaterPipe.isValidIrrigationRange(objectRange) then
			pipe.irrigationRange = objectRange
		elseif WaterPipe.isValidIrrigationRange(pipe.irrigationRange) then
			pipeObject:getModData()["irrigationRange"] = pipe.irrigationRange
		else
			pipe.irrigationRange = nil
			pipeObject:getModData()["irrigationRange"] = nil
		end
		local objectAutoTillOverride = pipeObject:getModData()["autoTillOverride"]
		if type(objectAutoTillOverride) == "boolean" then
			pipe.autoTillOverride = objectAutoTillOverride
		elseif type(pipe.autoTillOverride) == "boolean" then
			pipeObject:getModData()["autoTillOverride"] = pipe.autoTillOverride
		else
			pipe.autoTillOverride = nil
			pipeObject:getModData()["autoTillOverride"] = nil
		end
		pipeObject:getModData()["infinite"] = true
        pipeObject:transmitModData()
		print("pipe : found existing pipe " .. pipe.x .. "," .. pipe.y)
    end
	WaterPipe.refreshAutoTillOverridePipeCount()
	WaterPipe.refreshCleanupEnabledPipeCount()
	if WaterPipe.isPipeCleanupEnabled(pipe) and WaterPipe.requestCleanupPass then
		WaterPipe.requestCleanupPass()
	end
end

function WaterPipe.LoadGridsquare(square)
    if isClient() then return end
	-- does this square have a pipe ?
	for i=0,square:getObjects():size() - 1 do
		local obj = square:getObjects():get(i)
		if WaterPipe.isServicePipeObject(obj) then
			WaterPipe.loadPipe(obj)
			return
		end
	end

	-- The square is loaded and therefore safe to inspect.  If the save still
	-- contains a pipe record here but the world object is gone, remove only
	-- this coordinate instead of rescanning every known pipe.
	local x, y, z = square:getX(), square:getY(), square:getZ()
	if WaterPipe.getPipeAt(x, y, z) then
		WaterPipe.removePipeDataAt(x, y, z)
	end
end

Events.LoadGridsquare.Add(WaterPipe.LoadGridsquare)

function WaterPipe.getPipeAt(x,y,z)
	if isClient() then return nil end
	local key = WaterPipe.getPipeKey(x, y, z)
	local indexedPipe = WaterPipe.pipeByKey[key]
	if indexedPipe then return indexedPipe end

	-- Compatibility fallback for old saves or another mod that directly edits
	-- WaterPipe.pipes without updating the index.  Future lookups become O(1).
	for _, vCur in ipairs(WaterPipe.pipes) do
		if vCur.x == x and vCur.y == y and vCur.z == z then
			WaterPipe.pipeByKey[key] = vCur
			return vCur
		end
	end
	return nil
end

function WaterPipe.findPipeObject(square)
	if square ~= nil and square:getObjects() ~= nil and square:getObjects():size() ~= nil then
		for i=0,square:getObjects():size()-1 do
			local object = square:getObjects():get(i)
			if object:getName() == "WaterPipe" then
				return object
			end
		end
		return nil
	end
	return nil
end

function WaterPipe.isServicePipeObject(object)
	if not object then return false end
	local name = object:getName()
	return name == "WaterPipe" or name == "WaterSupplyPipe"
		or name == "WaterDisabledPipe"
end

function WaterPipe.findAnyServicePipeObject(square)
	if not square or not square:getObjects() then return nil end
	for i = 0, square:getObjects():size() - 1 do
		local object = square:getObjects():get(i)
		if WaterPipe.isServicePipeObject(object) then return object end
	end
	return nil
end

-- Remove stale records only when their square is currently loaded and can be
-- inspected safely.  Records in unloaded chunks are intentionally preserved.
function WaterPipe.pruneMissingLoadedPipes()
	local removedCoordinates = 0
	for i = #WaterPipe.pipes, 1, -1 do
		local pipe = WaterPipe.pipes[i]
		if pipe then
			local square = getCell():getGridSquare(pipe.x, pipe.y, pipe.z)
			if square and not WaterPipe.findAnyServicePipeObject(square) then
				if WaterPipe.removePipeDataAt(pipe.x, pipe.y, pipe.z, false) then
					removedCoordinates = removedCoordinates + 1
				end
			end
		end
	end
	return removedCoordinates
end

function WaterPipe.getCurrentPipe(square)
	if square == nil then
		square = getPlayer():getCurrentSquare()
	end
	if isClient() then
		local object = WaterPipe.findPipeObject(square)
		if object then
			-- print("pipe object found, creating pipe")
			-- Client doesn't have a list of plants, just make a new one each time
			local pipe = {}
			pipe.x = square:getX()
			pipe.y = square:getY()
			pipe.z = square:getZ()
			pipe.pipeType = object:getModData()["pipeType"]
			
			return pipe
		end
		return nil
	end
	return WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
end

function WaterPipe.isValidPlant(plant)
    if not plant then
        return false
    end

    -- 核心判断：一个有效的植物必须有种子类型，且不能是 "none"，同时其状态不能是 "plow"
    if plant.typeOfSeed and plant.typeOfSeed ~= "none" and plant.state ~= "plow" then
        return true
    end

    return false
end

-- An unseeded vanilla furrow must always remain state="plow" with the
-- localized plowed-land name.  A partially initialized furrow (typeOfSeed is
-- still "none", but state/name were changed) is offered as a real plant by
-- the vanilla context menu.  Opening its Info window then indexes the missing
-- farming_vegetableconf.props.none entry and throws at ISFarmingInfo:new().
-- Normalize both newly auto-tilled furrows and already-corrupted save data.
function WaterPipe.normalizePlowedLand(plant)
	if not plant then return false end
	local seedType = plant.typeOfSeed
	local isEmptyFurrow = seedType == "none"
		or (plant.state == "plow" and (seedType == nil or seedType == ""))
	if not isEmptyFurrow then return false end

	local objectName = getText and getText("Farming_Plowed_Land")
		or "Farming_Plowed_Land"
	local spriteName = "vegetation_farming_01_1"
	local isoObject = nil
	if plant.getIsoObject then
		isoObject = plant:getIsoObject()
	elseif plant.getObject then
		isoObject = plant:getObject()
	end
	local isoObjectName = isoObject and isoObject.getName and isoObject:getName() or nil
	local isoSpriteName = isoObject and isoObject.getSpriteName and isoObject:getSpriteName() or nil
	local needsRepair = plant.state ~= "plow"
		or plant.typeOfSeed ~= "none"
		or plant.objectName ~= objectName
		or plant.spriteName ~= spriteName
		or (isoObjectName ~= nil and isoObjectName ~= objectName)
		or (isoSpriteName ~= nil and isoSpriteName ~= spriteName)
	if not needsRepair then return false end

	if SPlantGlobalObject and SPlantGlobalObject.initModData then
		SPlantGlobalObject.initModData(plant)
	else
		plant.state = "plow"
		plant.nbOfGrow = -1
		plant.fertilizer = 0
		plant.mildewLvl = 0
		plant.aphidLvl = 0
		plant.fliesLvl = 0
		plant.slugsLvl = 0
		plant.hasWeeds = false
		plant.waterLvl = 0
		plant.waterNeeded = 0
		plant.waterNeededMax = nil
		plant.lastWaterHour = 0
		plant.hasSeed = false
		plant.hasVegetable = false
		plant.cursed = false
		plant.compost = false
		plant.bonusYield = false
		plant.badCare = false
		plant.spriteName = "vegetation_farming_01_1"
		plant.objectName = objectName
	end

	-- Keep these values explicit even if another mod supplied initModData.
	plant.state = "plow"
	plant.typeOfSeed = "none"
	plant.spriteName = spriteName
	plant.objectName = objectName

	-- saveData() only transmits ModData; it does not update the IsoObject name
	-- or sprite.  Write the repaired state through vanilla's full world-object
	-- path so old saves and multiplayer clients stop displaying Farming_none.
	if isoObject and plant.stateToIsoObject then
		plant:stateToIsoObject(isoObject)
	elseif isoObject then
		if isoObject.setName then isoObject:setName(objectName) end
		if isoObject.setSpriteFromName then isoObject:setSpriteFromName(spriteName) end
		if plant.toModData and isoObject.getModData then
			plant:toModData(isoObject:getModData())
		end
		if isServer and isServer() then
			if isoObject.sendObjectChange and IsoObjectChange then
				isoObject:sendObjectChange(IsoObjectChange.NAME)
				isoObject:sendObjectChange(IsoObjectChange.SPRITE)
			end
			if isoObject.transmitModData then isoObject:transmitModData() end
		end
	elseif plant.saveData then
		plant:saveData()
	end
	return true
end

-- 🔍 统一植物检测函数：支持所有类型的植物和生长阶段
function WaterPipe.detectPlantAt(x, y, z, showDebug)
	local plant = nil
	if SFarmingSystem and SFarmingSystem.instance then
		plant = SFarmingSystem.instance:getLuaObjectAt(x, y, z)
	end
	

	if plant then
		if plant.typeOfSeed == "none"
			or (plant.state == "plow" and (plant.typeOfSeed == nil or plant.typeOfSeed == "")) then
			WaterPipe.normalizePlowedLand(plant)
			return nil
		end
		-- 新的、更精准的验证逻辑
		if WaterPipe.isValidPlant(plant) then
			if showDebug then
				local plantType = plant.typeOfSeed or "Unknown"
				local plantState = plant.state or "NoState"
				local waterLvl = plant.waterLvl or "N/A"
				local waterNeeded = plant.waterNeeded or "N/A"
				local isAlive = (plant.isAlive and plant:isAlive()) and "Alive" or "Dead"
				local compost = plant.compost and "Yes" or "No"
				
				print("[Plant Detected] At (" .. x .. "," .. y .. "," .. z .. "): " .. plantType)
				print("  State: " .. plantState .. " | Alive: " .. isAlive .. " | Compost: " .. compost)
				print("  Water: " .. waterLvl .. "/" .. waterNeeded)
			end
			return plant
		else
			-- 检查是否需要自动翻土
			if SandboxVars.WaterPipes.InfiniteAutoPlow and plant.state == "plow" then
				-- 这里是未来实现自动翻土功能的地方
				-- 例如，可以调用一个函数来处理翻土
				-- WaterPipe.handleAutoPlow(plant)
				print("[Auto Plow] Detected plow at (" .. x .. "," .. y .. "," .. z .. "). Auto-plowing logic can be added here.")
			end
			-- 如果不是有效植物（例如，只是一块耕地），则返回 nil
			return nil
		end
	end
	
	return nil
end

-- 🌱 统一处理一个覆盖位置，供分批扫描和新管道即时处理共用。
function WaterPipe.careForPosition(x, y, z, context, features, autoTillEnabled)
	-- Compatibility for callers using the former fifth auto-till argument.
	if type(features) == "boolean" and autoTillEnabled == nil then
		autoTillEnabled = features
		features = nil
	end
	local plant = WaterPipe.detectPlantAt(x, y, z)
	if plant then
		local automated = WaterPipeAutoFarming
			and WaterPipeAutoFarming.processPlant(plant) or false
		local cared = WaterPipe.isValidPlant(plant)
			and WaterPipe.careForPlant(plant, context, features) or false
		-- Care/instant-growth can promote a harvestable crop to its seed-bearing
		-- stage after the first automation check.  Recheck only when care actually
		-- changed the plant and automation did not already consume it, so a seed
		-- stock deficit is filled in this maintenance pass instead of ten minutes
		-- later.  This adds no extra area scan.
		if cared and not automated and WaterPipeAutoFarming then
			automated = WaterPipeAutoFarming.processPlant(plant) or false
		end
		return automated or cared
	end

	-- 🚜 没有植物时，按沙盒选项尝试翻土准备种植。
	WaterPipe.tryAutoTillPosition(x, y, z, autoTillEnabled)
	if WaterPipeAutoFarming then WaterPipeAutoFarming.trySowAt(x, y, z) end

	return false
end

-- 🌊 新管道放置或范围变化后立即处理自己的可调覆盖范围。
function WaterPipe.careForPipeArea(pipe, context)
	if not pipe then return 0 end
	if WaterPipeAutoFarming then WaterPipeAutoFarming.beginCycle() end

	local caredPositions = 0
	local radius = WaterPipe.getPipeIrrigationRadius(pipe)
	local autoTillEnabled = WaterPipe.isPipeAutoTillEnabled(pipe)
	local features = WaterPipe.getPipePlantFeatures(pipe)
	for dx = -radius, radius do
		for dy = -radius, radius do
			if WaterPipe.careForPosition(
				pipe.x + dx, pipe.y + dy, pipe.z, context, features, autoTillEnabled
			) then
				caredPositions = caredPositions + 1
			end
		end
	end

	return caredPositions
end

function WaterPipe.setObjectFarmFeature(pipeObject, feature, enabled)
	if isClient() or not pipeObject or not pipeObject:getSquare() then return false end
	if feature ~= "careEnabled" and feature ~= "fertilizeEnabled" then return false end
	if type(enabled) ~= "boolean" then return false end

	local square = pipeObject:getSquare()
	pipeObject:getModData()[feature] = enabled
	pipeObject:transmitModData()
	local pipe = WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	if pipe then
		pipe[feature] = enabled
		WaterPipe.markCoverageMapDirty()
		if enabled then WaterPipe.careForPipeArea(pipe, feature .. "-enabled") end
	end
	return true
end

function WaterPipe.setObjectCareEnabled(pipeObject, enabled)
	return WaterPipe.setObjectFarmFeature(pipeObject, "careEnabled", enabled)
end

function WaterPipe.setObjectFertilizationEnabled(pipeObject, enabled)
	return WaterPipe.setObjectFarmFeature(pipeObject, "fertilizeEnabled", enabled)
end

function WaterPipe.setObjectCleanupEnabled(pipeObject, enabled)
	if isClient() or not pipeObject or not pipeObject:getSquare()
		or type(enabled) ~= "boolean" then return false end

	local square = pipeObject:getSquare()
	pipeObject:getModData()["cleanupEnabled"] = enabled
	pipeObject:transmitModData()
	local pipe = WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	if pipe then pipe.cleanupEnabled = enabled end
	WaterPipe.refreshCleanupEnabledPipeCount()
	WaterPipe.markCoverageMapDirty()
	if enabled then
		WaterPipe.requestCleanupPass()
		WaterPipe.processCleanupPass()
	elseif not WaterPipe.hasAnyCleanupEnabled() then
		WaterPipe.cancelCleanupPass()
	end
	return true
end

function WaterPipe.setObjectCleanupShrunkFarmArea(pipeObject, enabled)
	if isClient() or not pipeObject or not pipeObject:getSquare()
		or type(enabled) ~= "boolean" then return false end

	local square = pipeObject:getSquare()
	pipeObject:getModData()["cleanupShrunkFarmArea"] = enabled
	pipeObject:transmitModData()
	local pipe = WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	if pipe then pipe.cleanupShrunkFarmArea = enabled end
	return true
end

function WaterPipe.setObjectAutoTill(pipeObject, requestedMode)
	if isClient() or not pipeObject or not pipeObject:getSquare() then return false end
	if requestedMode ~= "global" and requestedMode ~= "enabled"
		and requestedMode ~= "disabled" then return false end

	local override = nil
	if requestedMode == "enabled" then
		override = true
	elseif requestedMode == "disabled" then
		override = false
	end

	local square = pipeObject:getSquare()
	pipeObject:getModData()["autoTillOverride"] = override
	pipeObject:transmitModData()

	local pipe = WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	if pipe then pipe.autoTillOverride = override end
	WaterPipe.refreshAutoTillOverridePipeCount()
	WaterPipe.markCoverageMapDirty()
	if WaterPipe.hasAnyAutoTillEnabled() then
		WaterPipe.requestAutoTillPass()
	else
		WaterPipe.cancelAutoTillPass()
	end
	return true
end

local function pipeHasFarmingWork(pipe)
	return WaterPipe.hasPlantService(WaterPipe.getPipePlantFeatures(pipe))
		or WaterPipe.isPipeAutoTillEnabled(pipe)
end

function WaterPipe.isPositionCoveredByOtherFarmPipe(x, y, z, excludedPipe)
	for _, candidate in ipairs(WaterPipe.pipes) do
		if candidate ~= excludedPipe and candidate.z == z and pipeHasFarmingWork(candidate) then
			local radius = WaterPipe.getPipeIrrigationRadius(candidate)
			if math.abs(candidate.x - x) <= radius
				and math.abs(candidate.y - y) <= radius then
				return true
			end
		end
	end
	return false
end

function WaterPipe.queueShrunkFarmCleanup(pipe, oldRange, newRange)
	if isClient() or not pipe or pipe.cleanupShrunkFarmArea ~= true then return 0 end
	oldRange = tonumber(oldRange)
	newRange = tonumber(newRange)
	if not WaterPipe.isValidIrrigationRange(oldRange)
		or not WaterPipe.isValidIrrigationRange(newRange)
		or newRange >= oldRange then return 0 end

	local oldRadius = math.floor((oldRange - 1) / 2)
	local newRadius = math.floor((newRange - 1) / 2)
	local queue = WaterPipe.shrunkFarmCleanupQueue or {}
	WaterPipe.shrunkFarmCleanupQueue = queue
	local queued = 0
	for dx = -oldRadius, oldRadius do
		for dy = -oldRadius, oldRadius do
			if math.abs(dx) > newRadius or math.abs(dy) > newRadius then
				table.insert(queue, {
					x = pipe.x + dx,
					y = pipe.y + dy,
					z = pipe.z,
					pipeX = pipe.x,
					pipeY = pipe.y,
					pipeZ = pipe.z,
				})
				queued = queued + 1
			end
		end
	end
	return queued
end

function WaterPipe.queueGlobalRangeShrink(oldRange, newRange)
	if isClient() or not WaterPipe.isValidIrrigationRange(oldRange)
		or not WaterPipe.isValidIrrigationRange(newRange)
		or newRange >= oldRange then return 0 end

	local queued = 0
	for _, pipe in ipairs(WaterPipe.pipes) do
		-- Only pipes without a valid override follow the changed global range.
		if not WaterPipe.isValidIrrigationRange(pipe.irrigationRange) then
			queued = queued + WaterPipe.queueShrunkFarmCleanup(pipe, oldRange, newRange)
		end
	end
	if queued > 0 then WaterPipe.processShrunkFarmCleanup() end
	return queued
end

local function isFarmingIsoObject(object)
	if not object or WaterPipe.isServicePipeObject(object) then return false end
	local spriteName = object.getSpriteName and object:getSpriteName() or nil
	if (not spriteName or spriteName == "") and object.getSprite then
		local sprite = object:getSprite()
		spriteName = sprite and sprite.getName and sprite:getName() or nil
	end
	return type(spriteName) == "string"
		and spriteName:sub(1, 19) == "vegetation_farming_"
end

-- Remove both a normally registered farming object and orphaned farming
-- sprites left by old Farming_none saves.  SFarmingSystem:removePlant() can
-- silently return without deleting, so success is verified against the square.
function WaterPipe.removeFarmAt(x, y, z, farmingSystem)
	farmingSystem = farmingSystem or (SFarmingSystem and SFarmingSystem.instance)
	local found = false
	local plant = farmingSystem and farmingSystem.getLuaObjectAt
		and farmingSystem:getLuaObjectAt(x, y, z) or nil
	local cell = getCell and getCell()
	local square = cell and cell:getGridSquare(x, y, z) or nil
	if not square and plant and plant.getSquare then square = plant:getSquare() end
	if plant and farmingSystem.removePlant then
		found = true
		pcall(function() farmingSystem:removePlant(plant) end)
	end

	-- A valid removePlant() already transmits/removes its IsoObject.  Walk the
	-- current list afterwards so only an actual leftover farming sprite is sent.
	local objects = square and square.getObjects and square:getObjects() or nil
	if objects and objects.size and objects.get then
		for objectIndex = objects:size() - 1, 0, -1 do
			local object = objects:get(objectIndex)
			if isFarmingIsoObject(object) then
				found = true
				pcall(function() square:transmitRemoveItemFromSquare(object) end)
			end
		end
	end
	return found
end

function WaterPipe.processShrunkFarmCleanup()
	if isClient() then return true, 0, 0 end
	local queue = WaterPipe.shrunkFarmCleanupQueue or {}
	local index = tonumber(WaterPipe.shrunkFarmCleanupIndex) or 1
	if index > #queue then
		WaterPipe.shrunkFarmCleanupQueue = {}
		WaterPipe.shrunkFarmCleanupIndex = 1
		return true, 0, 0
	end

	local remaining = #queue - index + 1
	local endIndex = math.min(#queue, index + WaterPipe.getOptimalBatchSize(remaining) - 1)
	local processed, removed = 0, 0
	local startTime = WaterPipe.getTimestamp() or 0
	local timeBudgetMs = tonumber(WaterPipe.coverageTimeBudgetMs) or 2
	local checkInterval = math.max(1, tonumber(WaterPipe.coverageBudgetCheckInterval) or 5)
	local farmingSystem = SFarmingSystem and SFarmingSystem.instance

	for i = index, endIndex do
		local position = queue[i]
		local sourcePipe = position and WaterPipe.getPipeAt(
			position.pipeX, position.pipeY, position.pipeZ
		) or nil
		if sourcePipe then
			local currentRadius = WaterPipe.getPipeIrrigationRadius(sourcePipe)
			local stillInsideSource = math.abs(position.x - sourcePipe.x) <= currentRadius
				and math.abs(position.y - sourcePipe.y) <= currentRadius
			if not stillInsideSource and not WaterPipe.isPositionCoveredByOtherFarmPipe(
				position.x, position.y, position.z, sourcePipe
			) then
				if WaterPipe.removeFarmAt(
					position.x, position.y, position.z, farmingSystem
				) then removed = removed + 1 end
			end
		end

		processed = processed + 1
		WaterPipe.shrunkFarmCleanupIndex = i + 1
		if timeBudgetMs > 0 and (removed > 0 or processed % checkInterval == 0) then
			local now = WaterPipe.getTimestamp() or startTime
			if now - startTime >= timeBudgetMs then break end
		end
	end

	if WaterPipe.shrunkFarmCleanupIndex > #queue then
		WaterPipe.shrunkFarmCleanupQueue = {}
		WaterPipe.shrunkFarmCleanupIndex = 1
		return true, removed, processed
	end
	return false, removed, processed
end

function WaterPipe.setObjectIrrigationRange(pipeObject, requestedRange)
	if isClient() or not pipeObject or not pipeObject:getSquare() then return false end
	requestedRange = tonumber(requestedRange)
	if requestedRange ~= 0 and not WaterPipe.isValidIrrigationRange(requestedRange) then
		return false
	end

	local square = pipeObject:getSquare()
	local pipe = WaterPipe.getPipeAt(square:getX(), square:getY(), square:getZ())
	local oldRange = pipe and WaterPipe.getPipeIrrigationRange(pipe)
		or WaterPipe.getGlobalIrrigationRange()
	local override = nil
	if requestedRange ~= 0 then override = requestedRange end
	pipeObject:getModData()["irrigationRange"] = override
	pipeObject:transmitModData()

	if pipe then
		pipe.irrigationRange = override
		local newRange = WaterPipe.getPipeIrrigationRange(pipe)
		local isShrinking = newRange < oldRange
		WaterPipe.queueShrunkFarmCleanup(pipe, oldRange, newRange)
		WaterPipe.processShrunkFarmCleanup()
		WaterPipe.markCoverageMapDirty()
		-- Expanding should activate the newly covered cells immediately.  Shrinking
		-- must not run farming automation on the retained center as a side effect:
		-- with auto-harvest enabled that made the 1x1 crop disappear while the
		-- retired ring (when its destructive cleanup switch was off) stayed visible.
		if not isShrinking then
			WaterPipe.careForPipeArea(pipe, "range-change")
		end
		if WaterPipe.isPipeCleanupEnabled(pipe) then WaterPipe.requestCleanupPass() end
	end
	return true
end

-- 🧪 调试函数：全面扫描指定区域的植物信息
function WaterPipe.debugScanArea(centerX, centerY, centerZ, radius)
	print("=== PLANT SCAN DEBUG START ===")
	print("Scanning area around (" .. centerX .. "," .. centerY .. "," .. centerZ .. ") with radius " .. radius)
	
	local plantsFound = 0
	local rawObjectsFound = 0
	
	for dx = -radius, radius do
		for dy = -radius, radius do
			local x, y, z = centerX + dx, centerY + dy, centerZ
			
			-- 原始对象检查
			local rawPlant = nil
			if SFarmingSystem and SFarmingSystem.instance then
				rawPlant = SFarmingSystem.instance:getLuaObjectAt(x, y, z)
			end
			
			if rawPlant then
				rawObjectsFound = rawObjectsFound + 1
				print("  Raw object at (" .. x .. "," .. y .. "," .. z .. "):")
				
				-- 检查所有可能的属性
				local attributes = {}
				if rawPlant.typeOfSeed then table.insert(attributes, "typeOfSeed=" .. rawPlant.typeOfSeed) end
				if rawPlant.state then table.insert(attributes, "state=" .. rawPlant.state) end
				if rawPlant.waterLvl then table.insert(attributes, "waterLvl=" .. rawPlant.waterLvl) end
				if rawPlant.waterNeeded then table.insert(attributes, "waterNeeded=" .. rawPlant.waterNeeded) end
				if rawPlant.compost ~= nil then table.insert(attributes, "compost=" .. tostring(rawPlant.compost)) end
				if rawPlant.isAlive then table.insert(attributes, "isAlive=" .. tostring(rawPlant:isAlive())) end
				if rawPlant.autoWatered then table.insert(attributes, "autoWatered=" .. tostring(rawPlant.autoWatered)) end
				if rawPlant.lastWaterHour then table.insert(attributes, "lastWaterHour=" .. rawPlant.lastWaterHour) end
				
				print("    Attributes: " .. table.concat(attributes, ", "))
				
				-- 使用我们的检测函数测试
				local detectedPlant = WaterPipe.detectPlantAt(x, y, z, false)
				if detectedPlant then
					plantsFound = plantsFound + 1
					print("    ✅ Successfully detected by our function")
				else
					print("    ❌ NOT detected by our function")
				end
			end
		end
	end
	
	print("=== SCAN SUMMARY ===")
	print("Raw objects found: " .. rawObjectsFound)
	print("Plants detected by our function: " .. plantsFound)
	print("=== PLANT SCAN DEBUG END ===")
	
	return plantsFound, rawObjectsFound
end

function WaterPipe.createCoverageBuildState(previousProcessing)
	return {
		phase = WaterPipe.needsInitialPipePrune and "prune" or "coverage",
		pruneIndex = #WaterPipe.pipes,
		pipeIndex = 1,
		dx = nil,
		dy = nil,
		coverageMap = {},
		coveragePositions = {},
		totalCoverage = 0,
		autoTillPositions = {},
		totalAutoTillCoverage = 0,
		cleanupPositions = {},
		totalCleanupCoverage = 0,
		previousProcessing = previousProcessing,
	}
end

local function shouldPauseCoverageWork(processedCount, startTime, timeBudgetMs,
		budgetCheckInterval, maxWorkItems)
	if maxWorkItems > 0 and processedCount >= maxWorkItems then return true end
	if timeBudgetMs <= 0 or processedCount % budgetCheckInterval ~= 0 then return false end
	local currentTime = WaterPipe.getTimestamp() or startTime
	return currentTime - startTime >= timeBudgetMs
end

-- 对初次旧记录清理和 3x3 覆盖图生成使用同一游标，两者都可以在预算耗尽时暂停。
function WaterPipe.advanceCoverageBuild(state, timeBudgetMs, maxWorkItems)
	if not state then return true, 0 end
	local processedCount = 0
	local startTime = WaterPipe.getTimestamp() or 0
	local budgetMs = math.max(0, tonumber(timeBudgetMs) or 0)
	local workLimit = math.max(0, tonumber(maxWorkItems) or 0)
	local checkInterval = math.max(1, tonumber(WaterPipe.coverageBudgetCheckInterval) or 5)

	while state.phase == "prune" do
		if state.pruneIndex <= 0 then
			WaterPipe.needsInitialPipePrune = false
			state.phase = "coverage"
			break
		end

		local pipe = WaterPipe.pipes[state.pruneIndex]
		if pipe then
			local square = getCell():getGridSquare(pipe.x, pipe.y, pipe.z)
			if square and not WaterPipe.findAnyServicePipeObject(square) then
				WaterPipe.removePipeDataAt(pipe.x, pipe.y, pipe.z, false)
			end
		end
		state.pruneIndex = state.pruneIndex - 1
		processedCount = processedCount + 1
		if shouldPauseCoverageWork(processedCount, startTime, budgetMs, checkInterval, workLimit) then
			return false, processedCount
		end
	end

	while state.phase == "coverage" do
		local pipe = WaterPipe.pipes[state.pipeIndex]
		if not pipe then
			state.phase = "complete"
			return true, processedCount
		end
		local radius = WaterPipe.getPipeIrrigationRadius(pipe)
		if state.dx == nil then
			state.dx = -radius
			state.dy = -radius
		end

		local coverX = pipe.x + state.dx
		local coverY = pipe.y + state.dy
		local coverZ = pipe.z
		local key = WaterPipe.getPipeKey(coverX, coverY, coverZ)
		local autoTillEnabled = WaterPipe.isPipeAutoTillEnabled(pipe)
		local cleanupEnabled = WaterPipe.isPipeCleanupEnabled(pipe)
		local pipeFeatures = WaterPipe.getPipePlantFeatures(pipe)
		local hasPlantService = WaterPipe.hasPlantService(pipeFeatures)
		if not state.coverageMap[key] then
			local coverageData = {
				x = coverX,
				y = coverY,
				z = coverZ,
				key = key,
				irrigation = pipeFeatures.irrigation,
				care = pipeFeatures.care,
				fertilize = pipeFeatures.fertilize,
				autoSow = pipeFeatures.autoSow,
				autoHarvest = pipeFeatures.autoHarvest,
				autoTill = autoTillEnabled,
				cleanup = cleanupEnabled,
			}
			state.coverageMap[key] = coverageData
			if hasPlantService then
				state.totalCoverage = state.totalCoverage + 1
				coverageData.index = state.totalCoverage
				coverageData.plantIndexed = true
				table.insert(state.coveragePositions, coverageData)
			end
			if autoTillEnabled then
				coverageData.autoTillIndexed = true
				state.totalAutoTillCoverage = state.totalAutoTillCoverage + 1
				table.insert(state.autoTillPositions, coverageData)
			end
			if cleanupEnabled then
				coverageData.cleanupIndexed = true
				state.totalCleanupCoverage = state.totalCleanupCoverage + 1
				table.insert(state.cleanupPositions, coverageData)
			end
		else
			-- Overlapping pipes contribute their independently enabled services.
			local coverageData = state.coverageMap[key]
			coverageData.irrigation = coverageData.irrigation or pipeFeatures.irrigation
			coverageData.care = coverageData.care or pipeFeatures.care
			coverageData.fertilize = coverageData.fertilize or pipeFeatures.fertilize
			coverageData.autoSow = coverageData.autoSow or pipeFeatures.autoSow
			coverageData.autoHarvest = coverageData.autoHarvest or pipeFeatures.autoHarvest
			if hasPlantService and not coverageData.plantIndexed then
				state.totalCoverage = state.totalCoverage + 1
				coverageData.index = state.totalCoverage
				coverageData.plantIndexed = true
				table.insert(state.coveragePositions, coverageData)
			end
			coverageData.autoTill = coverageData.autoTill or autoTillEnabled
			if autoTillEnabled and not coverageData.autoTillIndexed then
				coverageData.autoTillIndexed = true
				state.totalAutoTillCoverage = state.totalAutoTillCoverage + 1
				table.insert(state.autoTillPositions, coverageData)
			end
			coverageData.cleanup = coverageData.cleanup or cleanupEnabled
			if cleanupEnabled and not coverageData.cleanupIndexed then
				coverageData.cleanupIndexed = true
				state.totalCleanupCoverage = state.totalCleanupCoverage + 1
				table.insert(state.cleanupPositions, coverageData)
			end
		end

		state.dy = state.dy + 1
		if state.dy > radius then
			state.dy = -radius
			state.dx = state.dx + 1
			if state.dx > radius then
				state.dx = nil
				state.dy = nil
				state.pipeIndex = state.pipeIndex + 1
			end
		end

		processedCount = processedCount + 1
		if shouldPauseCoverageWork(processedCount, startTime, budgetMs, checkInterval, workLimit) then
			return false, processedCount
		end
	end

	return true, processedCount
end

-- 保留同步构建接口供测试和外部诊断使用；运行时主循环使用下面的分时版本。
function WaterPipe.buildCoverageMap()
	local state = WaterPipe.createCoverageBuildState(nil)
	WaterPipe.advanceCoverageBuild(state, 0, 0)
	return state.coverageMap, state.coveragePositions, state.totalCoverage
end

function WaterPipe.continueCoverageMapBuild()
	if not WaterPipe.coverageBuildState then
		WaterPipe.coverageBuildState = WaterPipe.createCoverageBuildState(WaterPipe.coverageProcessing)
		print("🌊 [Coverage] Started incremental coverage-map rebuild")
	end

	local state = WaterPipe.coverageBuildState
	local complete = WaterPipe.advanceCoverageBuild(
		state,
		WaterPipe.coverageTimeBudgetMs,
		WaterPipe.coverageBuildMaxWorkItems
	)
	if not complete then return false end

	WaterPipe.lastCoverageMap = state.coverageMap
	WaterPipe.coveragePositions = state.coveragePositions
	WaterPipe.coveragePositionCount = state.totalCoverage
	WaterPipe.autoTillPositions = state.autoTillPositions
	WaterPipe.autoTillPositionCount = state.totalAutoTillCoverage
	WaterPipe.cleanupPositions = state.cleanupPositions
	WaterPipe.cleanupPositionCount = state.totalCleanupCoverage
	WaterPipe.coverageProcessing = {
		positions = state.coveragePositions,
		currentIndex = WaterPipe.getCoverageResumeIndex(
			state.previousProcessing,
			state.coverageMap,
			state.totalCoverage
		),
		totalPositions = state.totalCoverage,
	}
	WaterPipe.coverageMapNeedsUpdate = false
	WaterPipe.coverageBuildState = nil

	print("🌊 [Coverage] Incremental rebuild complete: " .. state.totalCoverage .. " positions")
	return true
end

-- 🔄 覆盖图重建后尽量从上次坐标继续，避免频繁放置或移除管道时总从头扫描。
function WaterPipe.getCoverageResumeIndex(previousProcessing, coverageMap, totalPositions)
	if not totalPositions or totalPositions <= 0 then return 1 end

	local previousIndex = previousProcessing and previousProcessing.currentIndex or 1
	local previousPositions = previousProcessing and previousProcessing.positions
	local previousData = previousPositions and previousPositions[previousIndex]
	if previousData and previousData.key then
		local matchingPosition = coverageMap and coverageMap[previousData.key]
		-- A coordinate may remain in the shared coverage map for auto-till or
		-- cleanup after its final plant service is disabled. Only resume from
		-- its list index when it is still part of the plant-processing list.
		local matchingIndex = matchingPosition and tonumber(matchingPosition.index)
		if matchingIndex then
			return math.max(1, math.min(matchingIndex, totalPositions))
		end
	end

	previousIndex = tonumber(previousIndex) or 1
	return math.max(1, math.min(previousIndex, totalPositions))
end

-- 🌱 检查位置是否被管道覆盖
function WaterPipe.isPositionCovered(x, y, z, coverageMap)
	if not coverageMap then
		-- 如果没有预建的覆盖图，实时计算
		for _, pipe in ipairs(WaterPipe.pipes) do
			local dx = math.abs(pipe.x - x)
			local dy = math.abs(pipe.y - y)
			local dz = math.abs(pipe.z - z)
			
			local radius = WaterPipe.getPipeIrrigationRadius(pipe)
			if dx <= radius and dy <= radius and dz == 0
				and WaterPipe.hasPlantService(WaterPipe.getPipePlantFeatures(pipe)) then
				return true
			end
		end
		return false
	else
		-- 使用预建的覆盖图
		local key = x .. "," .. y .. "," .. z
		return WaterPipe.hasPlantService(coverageMap[key])
	end
end

function WaterPipe.getPlantFeaturesAtPosition(x, y, z, coverageMap)
	if coverageMap then
		local data = coverageMap[WaterPipe.getPipeKey(x, y, z)]
		if data == true then
			return { irrigation = true, care = true, fertilize = true }
		end
		if WaterPipe.hasPlantService(data) then return data end
		return nil
	end

	local features = {
		irrigation = false, care = false, fertilize = false,
		autoSow = false, autoHarvest = false,
	}
	local found = false
	local maxRadius = math.floor((WaterPipe.irrigationRangeSizes[#WaterPipe.irrigationRangeSizes] - 1) / 2)
	for dx = -maxRadius, maxRadius do
		for dy = -maxRadius, maxRadius do
			local pipe = WaterPipe.pipeByKey[WaterPipe.getPipeKey(x + dx, y + dy, z)]
			if pipe and math.abs(dx) <= WaterPipe.getPipeIrrigationRadius(pipe)
				and math.abs(dy) <= WaterPipe.getPipeIrrigationRadius(pipe) then
				local pipeFeatures = WaterPipe.getPipePlantFeatures(pipe)
				features.irrigation = features.irrigation or pipeFeatures.irrigation
				features.care = features.care or pipeFeatures.care
				features.fertilize = features.fertilize or pipeFeatures.fertilize
				features.autoSow = features.autoSow or pipeFeatures.autoSow
				features.autoHarvest = features.autoHarvest or pipeFeatures.autoHarvest
				found = found or WaterPipe.hasPlantService(pipeFeatures)
			end
		end
	end
	return found and features or nil
end

-- 播种路径已经提供准确坐标，只反查允许的最大 7x7 周边管道索引，
-- 不依赖覆盖图是否正处于重建阶段，也不扫描植物列表或整个管网。
function WaterPipe.isPositionCoveredByPipeIndex(x, y, z)
	return WaterPipe.getPlantFeaturesAtPosition(x, y, z, nil) ~= nil
end

-- Resolve overlap deterministically and prefer the nearest pipe. This scans at
-- most the configurable 7x7 neighborhood using direct coordinate lookups.
function WaterPipe.getCoveringPipeFromIndex(x, y, z, requireOwner, requirePlantService)
	if x == nil or y == nil or z == nil then return nil end
	local maxRadius = math.floor((WaterPipe.irrigationRangeSizes[#WaterPipe.irrigationRangeSizes] - 1) / 2)
	local bestPipe = nil
	local bestDistance = nil
	local bestKey = nil
	for dx = -maxRadius, maxRadius do
		for dy = -maxRadius, maxRadius do
			local pipe = WaterPipe.pipeByKey[WaterPipe.getPipeKey(x + dx, y + dy, z)]
			if pipe and math.abs(dx) <= WaterPipe.getPipeIrrigationRadius(pipe)
				and math.abs(dy) <= WaterPipe.getPipeIrrigationRadius(pipe)
				and (not requireOwner or pipe.owner ~= nil)
				and (not requirePlantService
					or WaterPipe.hasPlantService(WaterPipe.getPipePlantFeatures(pipe))) then
				local distance = dx * dx + dy * dy
				local key = WaterPipe.getPipeKey(pipe.x, pipe.y, pipe.z)
				if bestDistance == nil or distance < bestDistance
					or (distance == bestDistance and key < bestKey) then
					bestPipe = pipe
					bestDistance = distance
					bestKey = key
				end
			end
		end
	end
	return bestPipe
end

function WaterPipe.bindPlantOwnerFromCoveringPipe(plant)
	if not plant or plant.owner ~= nil then return false end
	local pipe = WaterPipe.getCoveringPipeFromIndex(plant.x, plant.y, plant.z, true, true)
	if not pipe then return false end
	local ownerId = tonumber(pipe.owner)
	if ownerId == nil or ownerId < 0 then return false end
	pipe.owner = ownerId
	plant.owner = ownerId
	return true
end

function WaterPipe.careForNewlySeededPlant(plant)
	if isClient() or not WaterPipe.isValidPlant(plant) then return false end
	local features = WaterPipe.getPlantFeaturesAtPosition(plant.x, plant.y, plant.z, nil)
	if not features then return false end
	return WaterPipe.careForPlant(plant, "seed", features)
end

function WaterPipe.careForRecentlyHarvestedPlant(plant)
	if isClient() or not WaterPipe.isValidPlant(plant) then return false end
	local features = WaterPipe.getPlantFeaturesAtPosition(plant.x, plant.y, plant.z, nil)
	if not features then return false end

	-- A non-regrowing crop is left in the native harvested state.  When revival
	-- is disabled there is intentionally nothing to do; this also avoids running
	-- unrelated pest care against an inert harvested object.
	if plant.state == "harvested"
		and not SandboxVars.WaterPipes.InfiniteRevive then
		return false
	end
	return WaterPipe.careForPlant(plant, "harvest", features)
end

-- B42 没有播种完成事件，因此使用可串联的后置包装。先完整执行当前 seed
-- 实现，再调用我们的处理；其他模组若同样保留旧函数，调用链可以正常共存。
-- 若后加载模组直接替换 seed，本包装自然失效，十分钟扫描仍会负责兜底。
function WaterPipe.installSeedHook()
	local plantClass = SPlantGlobalObject
	if not plantClass or not plantClass.seed then return false end

	plantClass.__InfiniteIrrigationAfterSeed = WaterPipe.careForNewlySeededPlant
	if plantClass.__InfiniteIrrigationSeedWrapper then
		-- 不重复包装未知的后续函数，避免和其他模组形成重复调用链。
		return plantClass.seed == plantClass.__InfiniteIrrigationSeedWrapper
	end

	local originalSeed = plantClass.seed
	local function seedWithInfiniteIrrigation(plant, ...)
		local result = originalSeed(plant, ...)
		local afterSeed = plantClass.__InfiniteIrrigationAfterSeed
		if afterSeed then
			local success, errorMessage = pcall(afterSeed, plant)
			if not success and debugLoggingEnabled then
				systemPrint("[WaterPipe] Seed care failed: " .. tostring(errorMessage))
			end
		end
		return result
	end

	plantClass.__InfiniteIrrigationSeedOriginal = originalSeed
	plantClass.__InfiniteIrrigationSeedWrapper = seedWithInfiniteIrrigation
	plantClass.seed = seedWithInfiniteIrrigation
	return true
end

-- B42 harvest has no completion event either.  Wrap the farming-system method
-- instead of the timed action so manual harvest, scything and multiplayer
-- commands all share the same server-authoritative path.  Original rewards and
-- crop state changes complete first, then only the harvested coordinate is
-- checked against the pipe index; no nearby or global scan is performed.
function WaterPipe.installHarvestHook()
	local farmingClass = SFarmingSystem
	if not farmingClass or not farmingClass.harvest then return false end

	farmingClass.__InfiniteIrrigationAfterHarvest = WaterPipe.careForRecentlyHarvestedPlant
	if farmingClass.__InfiniteIrrigationHarvestWrapper then
		return farmingClass.harvest == farmingClass.__InfiniteIrrigationHarvestWrapper
	end

	local originalHarvest = farmingClass.harvest
	local function harvestWithInfiniteIrrigation(system, plant, ...)
		local result = originalHarvest(system, plant, ...)
		local afterHarvest = farmingClass.__InfiniteIrrigationAfterHarvest
		if afterHarvest then
			local success, errorMessage = pcall(afterHarvest, plant)
			if not success and debugLoggingEnabled then
				systemPrint("[WaterPipe] Harvest care failed: " .. tostring(errorMessage))
			end
		end
		return result
	end

	farmingClass.__InfiniteIrrigationHarvestOriginal = originalHarvest
	farmingClass.__InfiniteIrrigationHarvestWrapper = harvestWithInfiniteIrrigation
	farmingClass.harvest = harvestWithInfiniteIrrigation
	return true
end

-- 通常服务器文件载入时原版植物类已经存在；启动事件是加载顺序异常时的补偿。
WaterPipe.installSeedHook()
WaterPipe.installHarvestHook()
Events.OnGameBoot.Add(WaterPipe.installSeedHook)
Events.OnGameStart.Add(WaterPipe.installSeedHook)
Events.OnGameTimeLoaded.Add(WaterPipe.installSeedHook)
Events.OnGameBoot.Add(WaterPipe.installHarvestHook)
Events.OnGameStart.Add(WaterPipe.installHarvestHook)
Events.OnGameTimeLoaded.Add(WaterPipe.installHarvestHook)

-- 自动耕地关闭时，直接扫描原版种植系统登记的植物通常比逐格检查更便宜。
-- 返回 nil 表示当前运行环境不支持原版的索引接口，此时继续使用覆盖格扫描。
function WaterPipe.getAdaptivePlantCount()
	local farmingSystem = SFarmingSystem and SFarmingSystem.instance
	if not farmingSystem or not farmingSystem.getLuaObjectCount
		or not farmingSystem.getLuaObjectByIndex then
		return nil
	end

	local plantCount = tonumber(farmingSystem:getLuaObjectCount())
	if not plantCount or plantCount < 0 then return nil end
	return math.floor(plantCount)
end

function WaterPipe.shouldUsePlantScan(totalPositions)
	local plantCount = WaterPipe.getAdaptivePlantCount()
	if plantCount == nil then return false, nil end
	return plantCount < (tonumber(totalPositions) or 0), plantCount
end

-- 原版新增耕地对象时会追加到全局列表，因此数量增加后优先处理旧列表末尾之后的对象。
-- 数量减少时从头开始，避免删除造成索引前移；已有耕地播种则由正常轮询发现状态变化。
function WaterPipe.refreshPlantProcessing(plantCount)
	local processing = WaterPipe.plantProcessing
	if not processing then
		processing = { currentIndex = 1, totalPlants = plantCount }
		WaterPipe.plantProcessing = processing
		return processing
	end

	local previousCount = tonumber(processing.totalPlants) or 0
	if plantCount > previousCount then
		processing.currentIndex = math.max(1, previousCount + 1)
	elseif plantCount < previousCount then
		processing.currentIndex = 1
	end
	processing.totalPlants = plantCount
	processing.currentIndex = math.max(1, math.min(processing.currentIndex or 1, math.max(1, plantCount)))
	return processing
end

function WaterPipe.processPlantBatch(plantCount)
	local farmingSystem = SFarmingSystem and SFarmingSystem.instance
	if not farmingSystem or plantCount <= 0 then
		WaterPipe.plantProcessing = { currentIndex = 1, totalPlants = math.max(0, plantCount or 0) }
		return 0, 0
	end

	local processing = WaterPipe.refreshPlantProcessing(plantCount)
	local maxPlantsPerCycle = WaterPipe.getOptimalBatchSize(plantCount)
	local caredCount = 0
	local processedCount = 0
	local startTime = WaterPipe.getTimestamp() or 0
	local timeBudgetMs = tonumber(WaterPipe.coverageTimeBudgetMs) or 2
	local budgetCheckInterval = math.max(1, tonumber(WaterPipe.coverageBudgetCheckInterval) or 5)
	local endIndex = math.min(processing.currentIndex + maxPlantsPerCycle - 1, plantCount)
	local nextIndex = processing.currentIndex

	for i = processing.currentIndex, endIndex do
		local plant = farmingSystem:getLuaObjectByIndex(i)
		if plant and (plant.typeOfSeed == "none"
			or (plant.state == "plow" and (plant.typeOfSeed == nil or plant.typeOfSeed == ""))) then
			WaterPipe.normalizePlowedLand(plant)
		end
		local automated = WaterPipeAutoFarming and WaterPipeAutoFarming.processPlant(plant) or false
		local caredForPlant = false
		local features = plant and plant.x ~= nil and plant.y ~= nil and plant.z ~= nil
			and WaterPipe.getPlantFeaturesAtPosition(
				plant.x, plant.y, plant.z, WaterPipe.lastCoverageMap
			) or nil
		if plant and WaterPipe.isValidPlant(plant)
			and plant.x ~= nil and plant.y ~= nil and plant.z ~= nil
			and features
			and WaterPipe.careForPlant(plant, "plant-list", features) then
			caredCount = caredCount + 1
			caredForPlant = true
		end
		-- A care pass may have just made this crop seed-bearing.  Retry only this
		-- already-loaded plant; do not schedule or perform another position scan.
		if caredForPlant and not automated and WaterPipeAutoFarming then
			automated = WaterPipeAutoFarming.processPlant(plant) or false
		end

		processedCount = processedCount + 1
		nextIndex = i + 1
		-- 状态写入和网络同步比空位置查询更重，护理发生后立即核对预算。
		if timeBudgetMs > 0 and (automated or caredForPlant
			or processedCount % budgetCheckInterval == 0) then
			local currentTime = WaterPipe.getTimestamp() or startTime
			if currentTime - startTime >= timeBudgetMs then break end
		end
	end

	processing.currentIndex = nextIndex
	if processing.currentIndex > plantCount then processing.currentIndex = 1 end
	return caredCount, processedCount
end

-- 🌊 帧率友好的分时综合护理系统。
function WaterPipe.checkAndWaterNewPlantsWithCoverage()
	if isClient() then return end
	if WaterPipeAutoFarming then WaterPipeAutoFarming.beginCycle() end
	
	-- 性能优化：如果没有管道，直接退出
	if #WaterPipe.pipes == 0 then
		WaterPipe.lastCoverageMap = {}
		WaterPipe.coveragePositions = {}
		WaterPipe.coveragePositionCount = 0
		WaterPipe.autoTillPositions = {}
		WaterPipe.autoTillPositionCount = 0
		WaterPipe.cleanupPositions = {}
		WaterPipe.cleanupPositionCount = 0
		WaterPipe.cleanupPassPending = false
		WaterPipe.cleanupProcessing = nil
		WaterPipe.coverageProcessing = nil
		WaterPipe.coverageBuildState = nil
		WaterPipe.coverageMapNeedsUpdate = false
		WaterPipe.needsInitialPipePrune = false
		return
	end
	
	-- 覆盖图重建也遵守单次时间预算；本轮只做重建，不叠加植物护理负载。
	if not WaterPipe.lastCoverageMap or WaterPipe.coverageMapNeedsUpdate then
		WaterPipe.continueCoverageMapBuild()
		return
	end
	
	-- 🎮 自适应分时处理：根据网络规模动态调整每次事件处理的位置数量
	-- 基于性能分析，不同规模网络需要不同的批次大小以优化性能和用户体验
	local totalPositions = WaterPipe.coveragePositionCount or 0
	local usePlantScan, plantCount = WaterPipe.shouldUsePlantScan(totalPositions)
	if usePlantScan then
		WaterPipe.processPlantBatch(plantCount)
		return
	end
	
	-- 获取自适应批次大小
	local maxPositionsPerCycle = WaterPipe.getOptimalBatchSize(totalPositions)

	-- 防御性初始化；正常路径在覆盖图构建时已同步生成有序列表。
	if not WaterPipe.coverageProcessing then
		WaterPipe.coverageProcessing = {
			positions = WaterPipe.coveragePositions or {},
			currentIndex = 1,
			totalPositions = totalPositions
		}
		
		print("🎮 [Frame-Friendly] Initialized batch processing for " .. WaterPipe.coverageProcessing.totalPositions .. " positions")
	end

	-- Recover old/in-flight processing state that may contain an empty cursor
	-- after a pipe loses its final plant service during a coverage rebuild.
	local processing = WaterPipe.coverageProcessing
	processing.positions = processing.positions or WaterPipe.coveragePositions or {}
	processing.totalPositions = math.max(0,
		tonumber(processing.totalPositions) or totalPositions)
	processing.currentIndex = math.max(1,
		tonumber(processing.currentIndex) or 1)
	
	-- 处理当前批次
	local wateredCount = 0
	local processedCount = 0
	local startTime = WaterPipe.getTimestamp() or 0
	local timeBudgetMs = tonumber(WaterPipe.coverageTimeBudgetMs) or 2
	local budgetCheckInterval = math.max(1, tonumber(WaterPipe.coverageBudgetCheckInterval) or 5)
	local endIndex = math.min(
		processing.currentIndex + maxPositionsPerCycle - 1,
		processing.totalPositions
	)
	local nextIndex = processing.currentIndex

	for i = processing.currentIndex, endIndex do
		local coverageData = processing.positions[i]
		local caredForPlant = false
		if coverageData then
			if WaterPipe.careForPosition(
				coverageData.x, coverageData.y, coverageData.z,
				"coverage", coverageData, false
			) then
				wateredCount = wateredCount + 1
				caredForPlant = true
			end
		end

		processedCount = processedCount + 1
		nextIndex = i + 1
		if timeBudgetMs > 0 and (caredForPlant or processedCount % budgetCheckInterval == 0) then
			local currentTime = WaterPipe.getTimestamp() or startTime
			if currentTime - startTime >= timeBudgetMs then
				break
			end
		end
	end
	
	-- 更新处理进度
	processing.currentIndex = nextIndex
	
	-- 检查是否处理完成
	if processing.currentIndex > processing.totalPositions then
		-- 重置处理状态，下一轮重新开始
		processing.currentIndex = 1

		if debugLoggingEnabled and wateredCount > 0 then
			local elapsed = 0
			local currentTime = WaterPipe.getTimestamp() or 0
			if currentTime > 0 and startTime > 0 then
				elapsed = currentTime - startTime
			end
			print("🌊 [Frame-Friendly] Batch complete - Provided care to " .. wateredCount .. " plants in " .. string.format("%.2f", elapsed) .. "ms")
		end
	else
		if debugLoggingEnabled and wateredCount > 0 then
			local progress = math.floor((processing.currentIndex / processing.totalPositions) * 100)
			-- 安全地计算耗时
			local elapsed = 0
			local currentTime = WaterPipe.getTimestamp() or 0
			if currentTime > 0 and startTime > 0 then
				elapsed = currentTime - startTime
			end
			print("🎮 [Frame-Friendly] Progress " .. progress .. "% - Provided care to " .. wateredCount .. " plants in " .. string.format("%.2f", elapsed) .. "ms")
		end
	end
end

-- 🔄 标记覆盖图需要更新（当管道网络变化时调用）
function WaterPipe.markCoverageMapDirty()
	WaterPipe.coverageMapNeedsUpdate = true
	WaterPipe.coverageBuildState = nil
	print("🔄 [Coverage] Coverage map marked as dirty - will rebuild on next check")
end

function WaterPipe.AutoTill.executeTill(square, x, y, z)
    if WaterPipe.AutoTill.config.enableDebug then
        print("🚜 [AutoTill] Executing till at (" .. x .. "," .. y .. "," .. z .. ")")
    end
    
    local success, errorMsg = pcall(function()
        -- Step 1: 清理准备
        if SFarmingSystem.removeTallGrass then
            SFarmingSystem:removeTallGrass(square)
        end
        if square.removeGrass then
            square:removeGrass()
        end
        
        -- Step 2: 执行翻土
        SFarmingSystem.instance:plow(square)
		local plowedLand = nil
		if SFarmingSystem.instance.getLuaObjectOnSquare then
			plowedLand = SFarmingSystem.instance:getLuaObjectOnSquare(square)
		end
		if not plowedLand and SFarmingSystem.instance.getLuaObjectAt then
			plowedLand = SFarmingSystem.instance:getLuaObjectAt(x, y, z)
		end
		WaterPipe.normalizePlowedLand(plowedLand)
    end)
    
    if success then
        if WaterPipe.AutoTill.config.enableDebug then
            print("✅ [AutoTill] SUCCESS at (" .. x .. "," .. y .. "," .. z .. ")")
        end
        return true
    else
        if WaterPipe.AutoTill.config.enableDebug then
            print("❌ [AutoTill] FAILED at (" .. x .. "," .. y .. "," .. z .. ") - " .. tostring(errorMsg))
        end
        return false
    end
end

-- 只处理空地，已经存在植物或耕地对象的位置不会重复翻土。
function WaterPipe.tryAutoTillPosition(x, y, z, autoTillEnabled)
	if autoTillEnabled == nil then
		autoTillEnabled = WaterPipe.getGlobalAutoTillEnabled()
	end
	if autoTillEnabled ~= true then return false end

	local farmingSystem = SFarmingSystem and SFarmingSystem.instance
	local cell = getCell and getCell()
	if not farmingSystem or not cell then return false end

	local square = cell:getGridSquare(x, y, z)
	if not square then return false end
	if farmingSystem:getLuaObjectOnSquare(square) then return false end

	return WaterPipe.AutoTill.executeTill(square, x, y, z)
end

function WaterPipe.cancelAutoTillPass()
	WaterPipe.autoTillPassPending = false
	WaterPipe.autoTillProcessing = nil
end

-- 开关从关闭变为开启时安排一次完整覆盖扫描。首批可由设置页立即调用，
-- 后续批次由每游戏分钟事件继续推进，不增加逐帧处理。
function WaterPipe.requestAutoTillPass()
	if isClient() then return false end
	if not WaterPipe.hasAnyAutoTillEnabled() then return false end

	WaterPipe.autoTillPassPending = true
	WaterPipe.autoTillProcessing = nil
	WaterPipe.lastAutoTillEnabled = true
	return true
end

function WaterPipe.processAutoTillPass()
	if isClient() or not WaterPipe.autoTillPassPending then return false, 0, 0 end
	if WaterPipeAutoFarming then WaterPipeAutoFarming.beginCycle() end
	if not WaterPipe.hasAnyAutoTillEnabled() then
		WaterPipe.cancelAutoTillPass()
		return true, 0, 0
	end

	-- 覆盖图重建本身也有时间预算，本轮不再叠加翻土负载。
	if not WaterPipe.lastCoverageMap or WaterPipe.coverageMapNeedsUpdate then
		WaterPipe.continueCoverageMapBuild()
		return false, 0, 0
	end

	local positions = WaterPipe.autoTillPositions or {}
	local totalPositions = WaterPipe.autoTillPositionCount or #positions
	local processing = WaterPipe.autoTillProcessing
	if not processing or processing.positions ~= positions then
		processing = {
			positions = positions,
			currentIndex = 1,
			totalPositions = totalPositions,
		}
		WaterPipe.autoTillProcessing = processing
	end

	if processing.totalPositions <= 0 then
		WaterPipe.cancelAutoTillPass()
		return true, 0, 0
	end

	local maxPositions = WaterPipe.getOptimalBatchSize(processing.totalPositions)
	local endIndex = math.min(
		processing.currentIndex + maxPositions - 1,
		processing.totalPositions
	)
	local processedCount = 0
	local tilledCount = 0
	local nextIndex = processing.currentIndex
	local startTime = WaterPipe.getTimestamp() or 0
	local timeBudgetMs = tonumber(WaterPipe.coverageTimeBudgetMs) or 2
	local checkInterval = math.max(1, tonumber(WaterPipe.coverageBudgetCheckInterval) or 5)

	for i = processing.currentIndex, endIndex do
		local position = processing.positions[i]
		local tilled = false
		if position and position.autoTill == true then
			tilled = WaterPipe.tryAutoTillPosition(position.x, position.y, position.z, true)
			if tilled and WaterPipeAutoFarming then
				WaterPipeAutoFarming.trySowAt(position.x, position.y, position.z)
			end
			if tilled then tilledCount = tilledCount + 1 end
		end

		processedCount = processedCount + 1
		nextIndex = i + 1
		if timeBudgetMs > 0 and (tilled or processedCount % checkInterval == 0) then
			local currentTime = WaterPipe.getTimestamp() or startTime
			if currentTime - startTime >= timeBudgetMs then break end
		end
	end

	processing.currentIndex = nextIndex
	if processing.currentIndex > processing.totalPositions then
		WaterPipe.cancelAutoTillPass()
		return true, tilledCount, processedCount
	end

	return false, tilledCount, processedCount
end

local function isInstanceOf(object, className)
	if not object or not instanceof then return false end
	local ok, result = pcall(instanceof, object, className)
	return ok and result == true
end

local function hasSpriteFlag(properties, flag)
	if not properties or not flag then return false end
	local ok, result = pcall(function() return properties:has(flag) end)
	return ok and result == true
end

function WaterPipe.isCleanupVegetation(object)
	if not object or WaterPipe.isServicePipeObject(object)
		or isInstanceOf(object, "IsoWorldInventoryObject") then return false end
	if isInstanceOf(object, "IsoTree") then return true end
	if IsoObjectType and object.getType and object:getType() == IsoObjectType.tree then return true end

	local sprite = object.getSprite and object:getSprite()
	if not sprite then return false end
	local spriteName = sprite.getName and sprite:getName() or ""
	-- Never treat planted crops as map vegetation.
	if spriteName:sub(1, 18) == "vegetation_farming" then return false end
	local properties = sprite.getProperties and sprite:getProperties()
	return hasSpriteFlag(properties, IsoFlagType and IsoFlagType.vegitation)
		or hasSpriteFlag(properties, IsoFlagType and IsoFlagType.canBeRemoved)
		or hasSpriteFlag(properties, IsoFlagType and IsoFlagType.canBeCut)
		or spriteName:sub(1, 20) == "blends_grassoverlays"
end

function WaterPipe.isCleanupTree(object)
	if not object then return false end
	if isInstanceOf(object, "IsoTree") then return true end
	return IsoObjectType and object.getType and object:getType() == IsoObjectType.tree
end

local function cleanupCategoryEnabled(optionName)
	local options = SandboxVars and SandboxVars.WaterPipes
	-- Keep old worlds and servers compatible: a missing category setting means
	-- enabled, matching the original all-category cleanup behavior.
	return not options or options[optionName] ~= false
end

function WaterPipe.removeCleanupZombie(zombie)
	if not isInstanceOf(zombie, "IsoZombie") then return false end
	local ok = pcall(function()
		if isServer and isServer() then
			local packerClass = NetworkZombiePacker
			if not packerClass and luajava and luajava.bindClass then
				packerClass = luajava.bindClass("zombie.popman.NetworkZombiePacker")
			end
			if packerClass then packerClass.getInstance():deleteZombie(zombie) end
		end
		if zombie.removeFromWorld then zombie:removeFromWorld() end
		if zombie.removeFromSquare then zombie:removeFromSquare() end
	end)
	return ok
end

function WaterPipe.cleanupSquare(square)
	local result = {
		zombies = 0, corpses = 0, vegetation = 0, groundItems = 0, blood = 0,
	}
	if not square then return result end

	local movingObjects = square.getMovingObjects and square:getMovingObjects()
	if cleanupCategoryEnabled("CleanupZombies") and movingObjects then
		for i = movingObjects:size() - 1, 0, -1 do
			if WaterPipe.removeCleanupZombie(movingObjects:get(i)) then
				result.zombies = result.zombies + 1
			end
		end
	end

	local staticObjects = square.getStaticMovingObjects and square:getStaticMovingObjects()
	if cleanupCategoryEnabled("CleanupCorpses") and staticObjects then
		for i = staticObjects:size() - 1, 0, -1 do
			local body = staticObjects:get(i)
			local isZombieBody = isInstanceOf(body, "IsoDeadBody")
			if isZombieBody and body.isZombie then
				local ok, zombieBody = pcall(function() return body:isZombie() end)
				isZombieBody = ok and zombieBody == true
			end
			if isZombieBody then
				local ok = pcall(function() square:removeCorpse(body, false) end)
				if ok then result.corpses = result.corpses + 1 end
			end
		end
	end

	local objects = square.getObjects and square:getObjects()
	if objects then
		for i = objects:size() - 1, 0, -1 do
			local object = objects:get(i)
			if cleanupCategoryEnabled("CleanupGroundItems")
				and isInstanceOf(object, "IsoWorldInventoryObject") then
				local ok = pcall(function()
					square:transmitRemoveItemFromSquare(object)
					if object.removeFromWorld then object:removeFromWorld() end
					if object.removeFromSquare then object:removeFromSquare() end
				end)
				if ok then result.groundItems = result.groundItems + 1 end
			elseif WaterPipe.isCleanupVegetation(object) then
				local isTree = WaterPipe.isCleanupTree(object)
				local categoryEnabled
				if isTree then
					categoryEnabled = cleanupCategoryEnabled("CleanupTrees")
				else
					categoryEnabled = cleanupCategoryEnabled("CleanupVegetation")
				end
				if categoryEnabled then
					local ok = pcall(function()
						square:transmitRemoveItemFromSquare(object)
						square:RemoveTileObject(object)
					end)
					if ok then result.vegetation = result.vegetation + 1 end
				end
			end
		end
	end

	if cleanupCategoryEnabled("CleanupBlood") and square.removeBlood then
		local ok = pcall(function() square:removeBlood(false, false) end)
		if ok then result.blood = 1 end
	end
	return result
end

function WaterPipe.cancelCleanupPass()
	WaterPipe.cleanupPassPending = false
	WaterPipe.cleanupProcessing = nil
end

function WaterPipe.requestCleanupPass()
	if isClient() or not WaterPipe.hasAnyCleanupEnabled() then return false end
	if not WaterPipe.cleanupPassPending then WaterPipe.cleanupProcessing = nil end
	WaterPipe.cleanupPassPending = true
	return true
end

function WaterPipe.processCleanupPass()
	if isClient() or not WaterPipe.cleanupPassPending then return false, 0, 0 end
	if not WaterPipe.hasAnyCleanupEnabled() then
		WaterPipe.cancelCleanupPass()
		return true, 0, 0
	end
	if not WaterPipe.lastCoverageMap or WaterPipe.coverageMapNeedsUpdate then
		WaterPipe.continueCoverageMapBuild()
		return false, 0, 0
	end

	local positions = WaterPipe.cleanupPositions or {}
	local totalPositions = WaterPipe.cleanupPositionCount or #positions
	local processing = WaterPipe.cleanupProcessing
	if not processing or processing.positions ~= positions then
		processing = { positions = positions, currentIndex = 1, totalPositions = totalPositions }
		WaterPipe.cleanupProcessing = processing
	end
	if processing.totalPositions <= 0 then
		WaterPipe.cancelCleanupPass()
		return true, 0, 0
	end

	local maxPositions = WaterPipe.getOptimalBatchSize(processing.totalPositions)
	local endIndex = math.min(processing.currentIndex + maxPositions - 1,
		processing.totalPositions)
	local processedCount, removedCount = 0, 0
	local nextIndex = processing.currentIndex
	local startTime = WaterPipe.getTimestamp() or 0
	local timeBudgetMs = tonumber(WaterPipe.coverageTimeBudgetMs) or 2
	local checkInterval = math.max(1, tonumber(WaterPipe.coverageBudgetCheckInterval) or 5)

	for i = processing.currentIndex, endIndex do
		local position = processing.positions[i]
		if position and position.cleanup == true then
			local square = getCell():getGridSquare(position.x, position.y, position.z)
			local result = WaterPipe.cleanupSquare(square)
			removedCount = removedCount + result.zombies + result.corpses
				+ result.vegetation + result.groundItems
		end
		processedCount = processedCount + 1
		nextIndex = i + 1
		if timeBudgetMs > 0 and processedCount % checkInterval == 0 then
			local currentTime = WaterPipe.getTimestamp() or startTime
			if currentTime - startTime >= timeBudgetMs then break end
		end
	end

	processing.currentIndex = nextIndex
	if processing.currentIndex > processing.totalPositions then
		WaterPipe.cancelCleanupPass()
		return true, removedCount, processedCount
	end
	return false, removedCount, processedCount
end

function WaterPipe.scheduleCleanupMaintenance()
	WaterPipe.requestCleanupPass()
end

function WaterPipe.updateAutoTillPass()
	if isClient() then return end
	if WaterPipe.shrunkFarmCleanupQueue
		and WaterPipe.shrunkFarmCleanupIndex <= #WaterPipe.shrunkFarmCleanupQueue then
		WaterPipe.processShrunkFarmCleanup()
	end
	local globalEnabled = WaterPipe.getGlobalAutoTillEnabled()
	local globalChanged = WaterPipe.lastGlobalAutoTillEnabled ~= nil
		and WaterPipe.lastGlobalAutoTillEnabled ~= globalEnabled
	if globalChanged then WaterPipe.markCoverageMapDirty() end
	WaterPipe.lastGlobalAutoTillEnabled = globalEnabled

	-- 范围、管道或功能变化后的覆盖图继续按原有时间预算分批重建，
	-- 不把 7x7 大范围一次性压到某个十分钟护理周期中。
	if WaterPipe.coverageMapNeedsUpdate and #WaterPipe.pipes > 0 then
		WaterPipe.continueCoverageMapBuild()
		if WaterPipe.coverageMapNeedsUpdate then return end
	end
	local enabled = WaterPipe.hasAnyAutoTillEnabled()

	if enabled and (WaterPipe.lastAutoTillEnabled ~= true
		or (globalChanged and globalEnabled)) then
		WaterPipe.requestAutoTillPass()
	elseif not enabled and WaterPipe.lastAutoTillEnabled == true then
		WaterPipe.cancelAutoTillPass()
	end
	WaterPipe.lastAutoTillEnabled = enabled

	if WaterPipe.autoTillPassPending then
		WaterPipe.processAutoTillPass()
	end
	if WaterPipe.cleanupPassPending then
		WaterPipe.processCleanupPass()
	end
end

require "WaterPipe/AutoFarming"

-- 与原版农业系统保持相同的十分钟节奏。植物生长也是在这个事件中推进，
-- 无需每个游戏分钟重复扫描；新管道仍由 loadPipe 立即护理自己的 3x3 区域。
Events.EveryOneMinute.Add(WaterPipe.updateAutoTillPass)
Events.EveryTenMinutes.Add(WaterPipe.checkAndWaterNewPlantsWithCoverage)
Events.EveryTenMinutes.Add(WaterPipe.scheduleCleanupMaintenance)

-- Keep the server registry in sync when a pipe disappears outside the normal
-- pickup action (sledgehammer, admin removal, map tools, or another mod).
function WaterPipe.onObjectAboutToBeRemoved(object)
	if isClient() or not object then return end
	if not WaterPipe.isServicePipeObject(object) then return end

	local square = object:getSquare()
	if not square then return end
	WaterPipe.removePipeDataAt(square:getX(), square:getY(), square:getZ())
end

Events.OnObjectAboutToBeRemoved.Add(WaterPipe.onObjectAboutToBeRemoved)

-- 🧪 开发者命令：手动触发植物扫描调试
-- 这是客户端发往服务端的命令，因此必须监听 OnClientCommand。
local function onDebugClientCommand(module, command, player, args)
	if module == "WaterPipe" and command == "debugScan" then
		if player and player:getAccessLevel() and player:getAccessLevel() == "admin" then
			args = args or {}
			local x = args.x or player:getX()
			local y = args.y or player:getY() 
			local z = args.z or player:getZ()
			local radius = args.radius or 3
			
			print("[Admin Debug] Starting plant scan around (" .. x .. "," .. y .. "," .. z .. ")")
			WaterPipe.debugScanArea(x, y, z, radius)
		end
	end
end

if isServer() then
	Events.OnClientCommand.Add(onDebugClientCommand)
end
