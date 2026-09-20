WaterPipeStorageFreshness = WaterPipeStorageFreshness or {}

local Freshness = WaterPipeStorageFreshness

Freshness.maxItemsPerBatch = 1000
Freshness.timeBudgetMs = 1
Freshness.budgetCheckInterval = 50
Freshness.passPending = false
Freshness.processing = nil

local function safeCall(callback, fallback)
	local ok, result = pcall(callback)
	if ok then return result end
	return fallback
end

function Freshness.isPerishableFood(item)
	if not item or not instanceof
		or not safeCall(function() return instanceof(item, "Food") end, false) then
		return false
	end
	if not item.getOffAge or not item.getOffAgeMax
		or not item.getAge or not item.setAge then return false end
	local offAge = tonumber(safeCall(function() return item:getOffAge() end, nil))
	local offAgeMax = tonumber(safeCall(function() return item:getOffAgeMax() end, nil))
	return offAge ~= nil and offAge < 1000000000
		and offAgeMax ~= nil and offAgeMax < 1000000000
end

-- Keep only usable food fresh.  Rotten food is deliberately not restored;
-- preservation is preventative rather than a way to resurrect spoiled items.
function Freshness.preserveItem(item)
	if not Freshness.isPerishableFood(item) then return false end
	if item.isRotten and safeCall(function() return item:isRotten() end, false) then
		return false
	end
	local age = tonumber(safeCall(function() return item:getAge() end, nil))
	local offAge = tonumber(safeCall(function() return item:getOffAge() end, nil))
	-- Refresh halfway to the stale threshold.  This keeps food continuously
	-- fresh while avoiding a stat write for every item on every ten-minute pass.
	if not age or not offAge or age <= 0 or age < offAge * 0.5 then return false end
	local changed = safeCall(function()
		item:setAge(0)
		return true
	end, false)
	if changed and sendItemStats then
		pcall(function() sendItemStats(item) end)
	end
	return changed
end

function Freshness.getPipeStorage(pipe)
	if not pipe or pipe.x == nil or pipe.y == nil or pipe.z == nil
		or not getCell or not WaterSupplyPipe or not WaterPipe then return nil end
	local cell = getCell()
	local square = cell and cell:getGridSquare(pipe.x, pipe.y, pipe.z) or nil
	local object = square and WaterPipe.findAnyServicePipeObject(square) or nil
	if not object or not WaterSupplyPipe.ensureStorage then return nil end
	return WaterSupplyPipe.ensureStorage(object)
end

function Freshness.reset()
	Freshness.passPending = false
	Freshness.processing = nil
end

function Freshness.requestPass()
	if isClient and isClient() then return false end
	if Freshness.passPending then return false end
	if not WaterPipe or not WaterPipe.pipes or #WaterPipe.pipes == 0 then return false end
	Freshness.passPending = true
	Freshness.processing = nil
	return true
end

function Freshness.processPass()
	if (isClient and isClient()) or not Freshness.passPending then
		return false, 0, 0
	end
	local pipes = WaterPipe and WaterPipe.pipes or {}
	local state = Freshness.processing
	if not state or state.pipes ~= pipes then
		state = { pipes = pipes, pipeIndex = 1, itemIndex = 0 }
		Freshness.processing = state
	end

	local processed, preserved = 0, 0
	local maxItems = math.max(1, tonumber(Freshness.maxItemsPerBatch) or 1000)
	local budgetMs = math.max(0, tonumber(Freshness.timeBudgetMs) or 1)
	local checkInterval = math.max(1, tonumber(Freshness.budgetCheckInterval) or 50)
	local startTime = WaterPipe and WaterPipe.getTimestamp
		and WaterPipe.getTimestamp() or 0

	while state.pipeIndex <= #state.pipes and processed < maxItems do
		if not state.items then
			local container = Freshness.getPipeStorage(state.pipes[state.pipeIndex])
			state.items = container and container.getItems and safeCall(function()
				return container:getItems()
			end, false) or false
			state.itemIndex = math.max(0, tonumber(state.itemIndex) or 0)
		end

		local items = state.items
		local itemCount = items and items.size
			and safeCall(function() return items:size() end, 0) or 0
		if state.itemIndex >= itemCount then
			state.pipeIndex = state.pipeIndex + 1
			state.items = nil
			state.itemIndex = 0
		else
			local item = items.get and safeCall(function()
				return items:get(state.itemIndex)
			end, nil) or nil
			state.itemIndex = state.itemIndex + 1
			processed = processed + 1
			if Freshness.preserveItem(item) then preserved = preserved + 1 end
			if budgetMs > 0 and (preserved > 0 or processed % checkInterval == 0)
				and WaterPipe and WaterPipe.getTimestamp then
				local now = WaterPipe.getTimestamp() or startTime
				if now - startTime >= budgetMs then break end
			end
		end
	end
	-- If the batch ended exactly on the container's final item, finish that
	-- cursor now instead of spending another minute only to discover EOF.
	if state.items then
		local itemCount = state.items.size and safeCall(function()
			return state.items:size()
		end, 0) or 0
		if state.itemIndex >= itemCount then
			state.pipeIndex = state.pipeIndex + 1
			state.items = nil
			state.itemIndex = 0
		end
	end

	if state.pipeIndex > #state.pipes then
		Freshness.reset()
		return true, preserved, processed
	end
	-- Reacquire the live Java container list on the next minute batch; the pipe
	-- may unload or its inventory may be replaced while this cursor is paused.
	state.items = nil
	return false, preserved, processed
end

return Freshness
