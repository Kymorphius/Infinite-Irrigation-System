PowerPipe = PowerPipe or {}
PowerPipe.sources = PowerPipe.sources or {}
PowerPipe.chunkSources = PowerPipe.chunkSources or {}
PowerPipe.proxies = PowerPipe.proxies or {}
PowerPipe.sourceSelectionCounts = PowerPipe.sourceSelectionCounts or {}
PowerPipe.chunkCandidates = PowerPipe.chunkCandidates or {}
PowerPipe.dirtyChunks = PowerPipe.dirtyChunks or {}
PowerPipe.dirtyChunkQueue = PowerPipe.dirtyChunkQueue or {}
PowerPipe.dirtyChunkHead = PowerPipe.dirtyChunkHead or 1
PowerPipe.dirtyTimeBudgetMs = PowerPipe.dirtyTimeBudgetMs or 2
PowerPipe.dirtyMaxChunksPerTick = PowerPipe.dirtyMaxChunksPerTick or 4
PowerPipe.activeChunkKeys = PowerPipe.activeChunkKeys or {}
PowerPipe.activeChunkIndex = PowerPipe.activeChunkIndex or {}
PowerPipe.maintenanceIndex = PowerPipe.maintenanceIndex or nil

-- Build 42 uses 8x8 chunks (older builds used 10x10).  Use the engine value so
-- generator positions are registered in the same chunk queried by vanilla
-- haveElectricity(), including after future chunk-size changes.
local CHUNK_SIZE = getChunkSizeInSquares and getChunkSizeInSquares() or 8
local PROXY_FLAG = "powerPipeGeneratorProxy"
local PROXY_SOURCE_KEY = "powerPipeGeneratorSourceKey"

local function sourceKey(x, y, z)
	return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function chunkKey(wx, wy)
	return tostring(wx) .. "," .. tostring(wy)
end

local function hasEntries(values)
	for _ in pairs(values or {}) do return true end
	return false
end

local function getTimestampMsSafe()
	if getTimestampMs then return getTimestampMs() end
	if os and os.clock then return os.clock() * 1000 end
	return 0
end

local function getTileRange()
	local value = SandboxVars and tonumber(SandboxVars.GeneratorTileRange) or 20
	return math.max(0, math.floor(value))
end

if PowerPipe.indexedTileRange == nil then
	PowerPipe.indexedTileRange = getTileRange()
end

local function getLoadedChunk(wx, wy)
	local cell = getCell and getCell() or nil
	local chunk = cell and cell:getChunk(wx, wy) or nil
	if not chunk and isServer and isServer() and ServerMap and ServerMap.instance then
		chunk = ServerMap.instance:getChunk(wx, wy)
	end
	return chunk
end

local function getLoadedSquare(x, y, z)
	local cell = getCell and getCell() or nil
	return cell and cell.getGridSquare and cell:getGridSquare(x, y, z) or nil
end

local function getSpecialObjects(square)
	return square and square.getSpecialObjects and square:getSpecialObjects() or nil
end

function PowerPipe.isProxyObject(object)
	return object and object.getModData and object:getModData()[PROXY_FLAG] == true
end

local function proxyIsAttached(proxy, square)
	local specialObjects = getSpecialObjects(square)
	if not proxy or not specialObjects or not proxy.getSquare
		or proxy:getSquare() ~= square then return false end
	for i = 0, specialObjects:size() - 1 do
		if specialObjects:get(i) == proxy then return true end
	end
	return false
end

local function findProxy(square, key)
	local specialObjects = getSpecialObjects(square)
	if not specialObjects then return nil end
	for i = 0, specialObjects:size() - 1 do
		local object = specialObjects:get(i)
		if PowerPipe.isProxyObject(object)
			and object:getModData()[PROXY_SOURCE_KEY] == key then
			return object
		end
	end
	return nil
end

local function detachProxy(key, proxy)
	if proxy and proxy.getSquare then
		local specialObjects = getSpecialObjects(proxy:getSquare())
		if specialObjects then specialObjects:remove(proxy) end
	end
	PowerPipe.proxies[key] = nil
end

-- IsoChunk.checkForMissingGenerators() removes every generator position whose
-- source square does not contain an active IsoGenerator.  A bare virtual
-- coordinate therefore disappears before haveElectricity() can use it.
--
-- Keep one invisible, non-updating IsoGenerator witness for every compressed
-- representative source.  It lives only in the square's special-object list:
-- it is not rendered, saved, transmitted, or placed in IsoGenerator's update
-- list.  Every Lua peer reconstructs these witnesses from the persistent pipe
-- modData when its squares load.
local function createProxy(source, key)
	if not IsoGenerator or not IsoGenerator.new then return nil end
	local square = getLoadedSquare(source.x, source.y, source.z)
	local specialObjects = getSpecialObjects(square)
	local cell = getCell and getCell() or nil
	if not square or not specialObjects or not cell then return nil end

	local existing = findProxy(square, key)
	if existing then
		PowerPipe.proxies[key] = existing
		return existing
	end

	local proxy = IsoGenerator.new(cell)
	if not proxy then return nil end
	proxy:setSquare(square)
	proxy:getModData()[PROXY_FLAG] = true
	proxy:getModData()[PROXY_SOURCE_KEY] = key
	specialObjects:add(proxy)

	-- setActivated(true) is the only non-debug Lua API that sets the native flag
	-- used by checkForMissingGenerators().  Restore the temporary indoor-toxicity
	-- change, then remove the witness from generator processing immediately.  It
	-- was never added to the normal object/process lists, so removeFromWorld()
	-- only stops/releases the one-shot start emitter; the active flag and its
	-- special-object attachment remain available to the native electricity check.
	local building = square.getBuilding and square:getBuilding() or nil
	local wasToxic
	if building and building.isToxic then wasToxic = building:isToxic() end
	local activated = pcall(function() proxy:setActivated(true) end)
	if building and wasToxic ~= nil and building.setToxic then
		building:setToxic(wasToxic)
	end
	if activated and proxy.removeFromWorld then
		pcall(function() proxy:removeFromWorld() end)
	end
	local active = activated and proxy.isActivated
		and proxy:isActivated() == true
	if not active then
		specialObjects:remove(proxy)
		return nil
	end

	PowerPipe.proxies[key] = proxy
	return proxy
end

local function incrementSourceSelection(key, source)
	local count = (PowerPipe.sourceSelectionCounts[key] or 0) + 1
	PowerPipe.sourceSelectionCounts[key] = count
	if count == 1 then createProxy(source, key) end
end

local function decrementSourceSelection(key, proxy)
	local count = math.max(0, (PowerPipe.sourceSelectionCounts[key] or 0) - 1)
	if count > 0 then
		PowerPipe.sourceSelectionCounts[key] = count
		return
	end
	PowerPipe.sourceSelectionCounts[key] = nil
	detachProxy(key, proxy or PowerPipe.proxies[key])
end

function PowerPipe.reconcileProxies()
	local required = {}
	for _, selected in pairs(PowerPipe.chunkSources) do
		for key, source in pairs(selected) do required[key] = source end
	end

	for key, proxy in pairs(PowerPipe.proxies) do
		local source = required[key]
		local square = source and getLoadedSquare(source.x, source.y, source.z) or nil
		if not source or not square or not proxyIsAttached(proxy, square) then
			detachProxy(key, proxy)
		end
	end

	for key, source in pairs(required) do
		local square = getLoadedSquare(source.x, source.y, source.z)
		if square then
			local proxy = PowerPipe.proxies[key]
			if not proxyIsAttached(proxy, square) then createProxy(source, key) end
		end
	end
end

local function sourceTouchesChunk(source, wx, wy, range)
	local minX, maxX = wx * CHUNK_SIZE, wx * CHUNK_SIZE + CHUNK_SIZE - 1
	local minY, maxY = wy * CHUNK_SIZE, wy * CHUNK_SIZE + CHUNK_SIZE - 1
	return maxX >= source.x - range and minX <= source.x + range
		and maxY >= source.y - range and minY <= source.y + range
end

local function getAffectedChunks(source, range)
	local chunks = {}
	local minWX = math.floor((source.x - range) / CHUNK_SIZE)
	local maxWX = math.floor((source.x + range) / CHUNK_SIZE)
	local minWY = math.floor((source.y - range) / CHUNK_SIZE)
	local maxWY = math.floor((source.y + range) / CHUNK_SIZE)
	for wx = minWX, maxWX do
		for wy = minWY, maxWY do
			chunks[chunkKey(wx, wy)] = { wx = wx, wy = wy }
		end
	end
	return chunks
end

local function addSourceToChunkCandidates(key, source)
	for affectedKey in pairs(source.chunks or {}) do
		local candidates = PowerPipe.chunkCandidates[affectedKey]
		if not candidates then
			candidates = {}
			PowerPipe.chunkCandidates[affectedKey] = candidates
		end
		candidates[key] = source
	end
end

local function removeSourceFromChunkCandidates(key, source)
	for affectedKey in pairs(source.chunks or {}) do
		local candidates = PowerPipe.chunkCandidates[affectedKey]
		if candidates then
			candidates[key] = nil
			if not hasEntries(candidates) then
				PowerPipe.chunkCandidates[affectedKey] = nil
			end
		end
	end
end

local function markChunkDirty(wx, wy)
	local key = chunkKey(wx, wy)
	if PowerPipe.dirtyChunks[key] then return false end
	local position = { key = key, wx = wx, wy = wy }
	PowerPipe.dirtyChunks[key] = position
	PowerPipe.dirtyChunkQueue[#PowerPipe.dirtyChunkQueue + 1] = position
	return true
end

local function markSourceChunksDirty(source)
	local chunks = source and source.chunks or nil
	if not chunks then return end

	-- Rebuild the source's own chunk first so a newly enabled pipe powers nearby
	-- appliances immediately even when the remaining work is spread over ticks.
	local ownWX = math.floor(source.x / CHUNK_SIZE)
	local ownWY = math.floor(source.y / CHUNK_SIZE)
	local ownKey = chunkKey(ownWX, ownWY)
	if chunks[ownKey] then markChunkDirty(ownWX, ownWY) end
	for key, position in pairs(chunks) do
		if key ~= ownKey then markChunkDirty(position.wx, position.wy) end
	end
end

local function setChunkActive(key, active)
	local index = PowerPipe.activeChunkIndex[key]
	if active then
		if index then return end
		PowerPipe.activeChunkKeys[#PowerPipe.activeChunkKeys + 1] = key
		PowerPipe.activeChunkIndex[key] = #PowerPipe.activeChunkKeys
		return
	end
	if not index then return end

	local lastIndex = #PowerPipe.activeChunkKeys
	local lastKey = PowerPipe.activeChunkKeys[lastIndex]
	PowerPipe.activeChunkKeys[index] = lastKey
	PowerPipe.activeChunkKeys[lastIndex] = nil
	PowerPipe.activeChunkIndex[key] = nil
	if lastKey and lastKey ~= key then
		PowerPipe.activeChunkIndex[lastKey] = index
	end
end

local function getCoveredCells(source, wx, wy, range)
	local cells = {}
	local radiusSquared = range * range
	local startX, startY = wx * CHUNK_SIZE, wy * CHUNK_SIZE
	for localY = 0, CHUNK_SIZE - 1 do
		local dy = startY + localY - source.y
		for localX = 0, CHUNK_SIZE - 1 do
			local dx = startX + localX - source.x
			if dx * dx + dy * dy <= radiusSquared then
				cells[#cells + 1] = localY * CHUNK_SIZE + localX
			end
		end
	end
	return cells
end

-- Generator positions are stored separately in every chunk. For a dense area
-- only a subset whose circles reproduce the same powered tiles in that chunk
-- is needed. Sources on different floors are grouped separately because their
-- vanilla vertical power intervals differ.
local function chooseChunkSources(wx, wy, range)
	local groups = {}
	local candidatesForChunk = PowerPipe.chunkCandidates[chunkKey(wx, wy)] or {}
	for key, source in pairs(candidatesForChunk) do
		if sourceTouchesChunk(source, wx, wy, range) then
			local cells = getCoveredCells(source, wx, wy, range)
			if #cells > 0 then
				local group = groups[source.z]
				if not group then
					group = {}
					groups[source.z] = group
				end
				group[#group + 1] = { key = key, source = source, cells = cells }
			end
		end
	end

	local selected = {}
	for _, candidates in pairs(groups) do
		-- Prefer broad sources first, then use a stable key tie-breaker. Each
		-- candidate is considered once and every accepted source covers at least
		-- one still-uncovered cell, so a floor can select at most 64 witnesses.
		-- This preserves the exact union without repeatedly rescanning the full
		-- candidate set as dense pipe fields grow.
		table.sort(candidates, function(a, b)
			if #a.cells ~= #b.cells then return #a.cells > #b.cells end
			return a.key < b.key
		end)
		local uncovered = {}
		local remaining = 0
		for _, candidate in ipairs(candidates) do
			for _, cellIndex in ipairs(candidate.cells) do
				if not uncovered[cellIndex] then
					uncovered[cellIndex] = true
					remaining = remaining + 1
				end
			end
		end

		for _, candidate in ipairs(candidates) do
			local addsCoverage = false
			for _, cellIndex in ipairs(candidate.cells) do
				if uncovered[cellIndex] then
					addsCoverage = true
					break
				end
			end
			if addsCoverage then
				selected[candidate.key] = candidate.source
				for _, cellIndex in ipairs(candidate.cells) do
					if uncovered[cellIndex] then
					uncovered[cellIndex] = nil
					remaining = remaining - 1
					end
				end
			end
			if remaining <= 0 then break end
		end
	end
	return selected
end

function PowerPipe.rebuildChunk(wx, wy, deferProxyReconcile)
	local key = chunkKey(wx, wy)
	local chunk = getLoadedChunk(wx, wy)
	local previous = PowerPipe.chunkSources[key] or {}
	if not chunk then
		for oldKey in pairs(previous) do decrementSourceSelection(oldKey) end
		PowerPipe.chunkSources[key] = nil
		setChunkActive(key, false)
		if not deferProxyReconcile then PowerPipe.reconcileProxies() end
		return false
	end

	local selected = chooseChunkSources(wx, wy, getTileRange())
	for oldKey, source in pairs(previous) do
		if not selected[oldKey] then
			chunk:removeGeneratorPos(source.x, source.y, source.z)
			decrementSourceSelection(oldKey)
		end
	end
	for selectedKey, source in pairs(selected) do
		-- Vanilla cleanup can remove virtual positions during chunk loading.
		-- Re-adding is safe because addGeneratorPos deduplicates coordinates.
		chunk:addGeneratorPos(source.x, source.y, source.z)
		if not previous[selectedKey] then
			incrementSourceSelection(selectedKey, source)
		else
			local square = getLoadedSquare(source.x, source.y, source.z)
			if square and not proxyIsAttached(PowerPipe.proxies[selectedKey], square) then
				createProxy(source, selectedKey)
			end
		end
	end
	PowerPipe.chunkSources[key] = selected
	setChunkActive(key, hasEntries(selected))
	if not deferProxyReconcile then PowerPipe.reconcileProxies() end
	return true
end

function PowerPipe.processDirtyChunks(timeBudgetMs, maxChunks)
	local budgetMs = math.max(0, tonumber(timeBudgetMs) or PowerPipe.dirtyTimeBudgetMs)
	local chunkLimit = math.max(1, tonumber(maxChunks) or PowerPipe.dirtyMaxChunksPerTick)
	local startTime = getTimestampMsSafe()
	local processed = 0

	while PowerPipe.dirtyChunkHead <= #PowerPipe.dirtyChunkQueue do
		local position = PowerPipe.dirtyChunkQueue[PowerPipe.dirtyChunkHead]
		PowerPipe.dirtyChunkHead = PowerPipe.dirtyChunkHead + 1
		if position and PowerPipe.dirtyChunks[position.key] == position then
			PowerPipe.dirtyChunks[position.key] = nil
			PowerPipe.rebuildChunk(position.wx, position.wy, true)
			processed = processed + 1
		end

		if processed >= chunkLimit then break end
		if budgetMs > 0 and processed > 0
			and getTimestampMsSafe() - startTime >= budgetMs then break end
	end

	if PowerPipe.dirtyChunkHead > #PowerPipe.dirtyChunkQueue then
		PowerPipe.dirtyChunkQueue = {}
		PowerPipe.dirtyChunkHead = 1
	end
	return processed
end

function PowerPipe.getPendingDirtyChunkCount()
	local count = 0
	for _ in pairs(PowerPipe.dirtyChunks) do count = count + 1 end
	return count
end

function PowerPipe.processMaintenance(timeBudgetMs, maxChunks)
	if not PowerPipe.maintenanceIndex then return 0 end
	local budgetMs = math.max(0, tonumber(timeBudgetMs) or PowerPipe.dirtyTimeBudgetMs)
	local chunkLimit = math.max(1, tonumber(maxChunks) or PowerPipe.dirtyMaxChunksPerTick)
	local startTime = getTimestampMsSafe()
	local processed = 0

	while PowerPipe.maintenanceIndex <= #PowerPipe.activeChunkKeys do
		local key = PowerPipe.activeChunkKeys[PowerPipe.maintenanceIndex]
		PowerPipe.maintenanceIndex = PowerPipe.maintenanceIndex + 1
		local selected = key and PowerPipe.chunkSources[key] or nil
		local wx, wy
		if key then wx, wy = key:match("^(-?%d+),(-?%d+)$") end
		local chunk = wx and getLoadedChunk(tonumber(wx), tonumber(wy)) or nil
		if chunk and selected then
			for sourceKeyValue, source in pairs(selected) do
				chunk:addGeneratorPos(source.x, source.y, source.z)
				local square = getLoadedSquare(source.x, source.y, source.z)
				local proxy = PowerPipe.proxies[sourceKeyValue]
				if square and not proxyIsAttached(proxy, square) then
					createProxy(source, sourceKeyValue)
				end
			end
		elseif selected and wx then
			-- Forget representatives for chunks that have left memory. Candidate
			-- membership remains indexed and the chunk-load hook will rebuild them.
			PowerPipe.rebuildChunk(tonumber(wx), tonumber(wy), true)
		end
		processed = processed + 1

		if processed >= chunkLimit then break end
		if budgetMs > 0 and getTimestampMsSafe() - startTime >= budgetMs then break end
	end

	if PowerPipe.maintenanceIndex > #PowerPipe.activeChunkKeys then
		PowerPipe.maintenanceIndex = nil
	end
	return processed
end

function PowerPipe.hasPendingMaintenance()
	return PowerPipe.maintenanceIndex ~= nil
end

local function sourceAddsCoverage(source, selected, wx, wy, range)
	local newCells = getCoveredCells(source, wx, wy, range)
	if #newCells == 0 then return false end

	local covered = {}
	for _, activeSource in pairs(selected) do
		if activeSource.z == source.z then
			for _, cellIndex in ipairs(getCoveredCells(activeSource, wx, wy, range)) do
				covered[cellIndex] = true
			end
		end
	end
	for _, cellIndex in ipairs(newCells) do
		if not covered[cellIndex] then return true end
	end
	return false
end

local function addNewSourceToChunk(source, wx, wy, range)
	local key = chunkKey(wx, wy)
	local chunk = getLoadedChunk(wx, wy)
	if not chunk then return end
	local selected = PowerPipe.chunkSources[key]
	if not selected or sourceAddsCoverage(source, selected, wx, wy, range) then
		markChunkDirty(wx, wy)
	end
end

function PowerPipe.registerSourceAt(x, y, z)
	x, y, z = math.floor(x), math.floor(y), math.floor(z)
	if PowerPipe.indexedTileRange ~= getTileRange() and PowerPipe.refreshSources then
		PowerPipe.refreshSources()
	end
	local key = sourceKey(x, y, z)
	local source = PowerPipe.sources[key]
	if source then
		-- Object-added and grid-load events may discover the same pipe twice.
		-- Restore it only if this source is the representative for that chunk.
		for chunkKeyValue, position in pairs(source.chunks) do
			local selected = PowerPipe.chunkSources[chunkKeyValue]
			local chunk = getLoadedChunk(position.wx, position.wy)
			if selected and selected[key] and chunk then
				chunk:addGeneratorPos(x, y, z)
				local square = getLoadedSquare(x, y, z)
				if square and not proxyIsAttached(PowerPipe.proxies[key], square) then
					createProxy(source, key)
				end
			elseif not selected and chunk then
				markChunkDirty(position.wx, position.wy)
			end
		end
		PowerPipe.processDirtyChunks()
		return true
	end

	source = { x = x, y = y, z = z, chunks = {} }
	PowerPipe.sources[key] = source
	local range = getTileRange()
	source.chunks = getAffectedChunks(source, range)
	addSourceToChunkCandidates(key, source)
	local ownWX = math.floor(source.x / CHUNK_SIZE)
	local ownWY = math.floor(source.y / CHUNK_SIZE)
	local ownKey = chunkKey(ownWX, ownWY)
	local ownPosition = source.chunks[ownKey]
	if ownPosition then
		addNewSourceToChunk(source, ownPosition.wx, ownPosition.wy, range)
	end
	for _, position in pairs(source.chunks) do
		if position ~= ownPosition then
			addNewSourceToChunk(source, position.wx, position.wy, range)
		end
	end
	PowerPipe.processDirtyChunks()
	return true
end

function PowerPipe.unregisterSourceAt(x, y, z)
	x, y, z = math.floor(x), math.floor(y), math.floor(z)
	if PowerPipe.indexedTileRange ~= getTileRange() and PowerPipe.refreshSources then
		PowerPipe.refreshSources()
	end
	local key = sourceKey(x, y, z)
	local source = PowerPipe.sources[key]
	if not source then return false end

	removeSourceFromChunkCandidates(key, source)
	PowerPipe.sources[key] = nil
	local ownWX = math.floor(source.x / CHUNK_SIZE)
	local ownWY = math.floor(source.y / CHUNK_SIZE)
	local ownKey = chunkKey(ownWX, ownWY)
	local ownSelected = PowerPipe.chunkSources[ownKey]
	if ownSelected and ownSelected[key] then markChunkDirty(ownWX, ownWY) end
	for affectedKey, position in pairs(source.chunks) do
		if affectedKey ~= ownKey then
			local selected = PowerPipe.chunkSources[affectedKey]
			if selected and selected[key] then
				markChunkDirty(position.wx, position.wy)
			end
		end
	end
	PowerPipe.processDirtyChunks()
	return true
end

function PowerPipe.isObjectEnabled(object)
	return object and object:getModData()
		and object:getModData()["powerSupplyPipe"] == true
end

function PowerPipe.syncObjectSource(object)
	if not object or not object.getSquare then return end
	local square = object:getSquare()
	if not square then return end
	if PowerPipe.isObjectEnabled(object) then
		PowerPipe.registerSourceAt(square:getX(), square:getY(), square:getZ())
	else
		PowerPipe.unregisterSourceAt(square:getX(), square:getY(), square:getZ())
	end
end

function PowerPipe.setObjectEnabled(object, enabled)
	if not object then return false end
	local square = object:getSquare()
	if not square then return false end

	object:getModData()["powerSupplyPipe"] = enabled and true or nil
	if not isClient() then object:transmitModData() end
	PowerPipe.syncObjectSource(object)

	if isServer() then
		sendServerCommand("WaterPipe", "powerState", {
			x = square:getX(), y = square:getY(), z = square:getZ(),
			enabled = enabled and true or false,
		})
	end
	return true
end

local function isPipeObject(object)
	if not object then return false end
	local name = object:getName()
	return name == "WaterPipe" or name == "WaterSupplyPipe"
		or name == "WaterDisabledPipe"
end

local function syncSquare(square)
	if not square or not square:getObjects() then return end
	local pipeObject
	for i = 0, square:getObjects():size() - 1 do
		local object = square:getObjects():get(i)
		if isPipeObject(object) then
			pipeObject = object
			break
		end
	end

	local x, y, z = square:getX(), square:getY(), square:getZ()
	if pipeObject and PowerPipe.isObjectEnabled(pipeObject) then
		PowerPipe.registerSourceAt(x, y, z)
	elseif PowerPipe.sources[sourceKey(x, y, z)] then
		PowerPipe.unregisterSourceAt(x, y, z)
	end
end

function PowerPipe.onGridSquareLoaded(square)
	syncSquare(square)

	-- One square per chunk is enough to restore and recompress its source list.
	if not square or square:getZ() ~= 0
		or square:getX() % CHUNK_SIZE ~= 0
		or square:getY() % CHUNK_SIZE ~= 0 then return end
	local wx = math.floor(square:getX() / CHUNK_SIZE)
	local wy = math.floor(square:getY() / CHUNK_SIZE)
	local key = chunkKey(wx, wy)
	if not hasEntries(PowerPipe.chunkCandidates[key])
		and not hasEntries(PowerPipe.chunkSources[key]) then return end
	markChunkDirty(wx, wy)
	PowerPipe.processDirtyChunks(nil, 1)
end

function PowerPipe.onObjectAdded(object)
	if isPipeObject(object) then PowerPipe.syncObjectSource(object) end
end

function PowerPipe.onObjectAboutToBeRemoved(object)
	if not isPipeObject(object) then return end
	local square = object:getSquare()
	if square and (PowerPipe.isObjectEnabled(object)
		or PowerPipe.sources[sourceKey(square:getX(), square:getY(), square:getZ())]) then
		PowerPipe.unregisterSourceAt(square:getX(), square:getY(), square:getZ())
	end
end

function PowerPipe.refreshSources()
	local range = getTileRange()
	if PowerPipe.indexedTileRange ~= range then
		-- Range changes are rare. Remove the old native representatives first so
		-- stale power never survives while the new index is rebuilt incrementally.
		for key, selected in pairs(PowerPipe.chunkSources) do
			local wx, wy = key:match("^(-?%d+),(-?%d+)$")
			local chunk = getLoadedChunk(tonumber(wx), tonumber(wy))
			if chunk then
				for _, source in pairs(selected) do
					chunk:removeGeneratorPos(source.x, source.y, source.z)
				end
			end
		end
		PowerPipe.chunkSources = {}
		PowerPipe.sourceSelectionCounts = {}
		PowerPipe.chunkCandidates = {}
		PowerPipe.activeChunkKeys = {}
		PowerPipe.activeChunkIndex = {}
		PowerPipe.maintenanceIndex = nil
		PowerPipe.dirtyChunks = {}
		PowerPipe.dirtyChunkQueue = {}
		PowerPipe.dirtyChunkHead = 1
		for key, source in pairs(PowerPipe.sources) do
			source.chunks = getAffectedChunks(source, range)
			addSourceToChunkCandidates(key, source)
			markSourceChunksDirty(source)
		end
		PowerPipe.indexedTileRange = range
		PowerPipe.reconcileProxies()
		PowerPipe.processDirtyChunks()
		return
	end

	-- Vanilla may prune generator positions while chunks load. Restore only the
	-- already-compressed representatives, spread across ticks without rebuilding
	-- topology or walking every source at once.
	PowerPipe.maintenanceIndex = #PowerPipe.activeChunkKeys > 0 and 1 or nil
	PowerPipe.processMaintenance()
end

function PowerPipe.onTick()
	if PowerPipe.dirtyChunkHead <= #PowerPipe.dirtyChunkQueue then
		PowerPipe.processDirtyChunks()
	elseif PowerPipe.hasPendingMaintenance() then
		PowerPipe.processMaintenance()
	end
end

function PowerPipe.onServerCommand(module, command, args)
	if module ~= "WaterPipe" or command ~= "powerState" or type(args) ~= "table" then return end
	local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
	if not x or not y or not z then return end
	if args.enabled == true then
		PowerPipe.registerSourceAt(x, y, z)
	else
		PowerPipe.unregisterSourceAt(x, y, z)
	end
end

if Events then
	if Events.LoadGridsquare then Events.LoadGridsquare.Add(PowerPipe.onGridSquareLoaded) end
	if Events.OnObjectAdded then Events.OnObjectAdded.Add(PowerPipe.onObjectAdded) end
	if Events.OnObjectAboutToBeRemoved then
		Events.OnObjectAboutToBeRemoved.Add(PowerPipe.onObjectAboutToBeRemoved)
	end
	if Events.EveryTenMinutes then Events.EveryTenMinutes.Add(PowerPipe.refreshSources) end
	if Events.OnTick then Events.OnTick.Add(PowerPipe.onTick) end
	if isClient and isClient() and Events.OnServerCommand then
		Events.OnServerCommand.Add(PowerPipe.onServerCommand)
	end
end
