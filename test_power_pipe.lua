local handlers = {}
Events = setmetatable({}, {
	__index = function(events, name)
		local event = { Add = function(callback) handlers[name] = callback end }
		rawset(events, name, event)
		return event
	end,
})

isClient = function() return false end
isServer = function() return false end
SandboxVars = { GeneratorTileRange = 20 }
getChunkSizeInSquares = function() return 8 end
local NATIVE_CHUNK_SIZE = getChunkSizeInSquares()

local function newList()
	local values = {}
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
		add = function(_, value) values[#values + 1] = value end,
		remove = function(_, value)
			for i, current in ipairs(values) do
				if current == value then table.remove(values, i) return true end
			end
			return false
		end,
	}
end

local squares = {}
local function squareKey(x, y, z)
	return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function newSquare(x, y, z)
	local specialObjects = newList()
	local objects = newList()
	local building = { toxic = false }
	function building:isToxic() return self.toxic end
	function building:setToxic(value) self.toxic = value end
	local square = {}
	function square:getX() return x end
	function square:getY() return y end
	function square:getZ() return z end
	function square:getSpecialObjects() return specialObjects end
	function square:getObjects() return objects end
	function square:getBuilding() return building end
	function square:getGenerator()
		for i = 0, specialObjects:size() - 1 do
			local object = specialObjects:get(i)
			if object and object.isActivated then return object end
		end
		return nil
	end
	square.building = building
	squares[squareKey(x, y, z)] = square
	return square
end

IsoGenerator = {}
local setActivatedCalls = 0
local removeFromWorldCalls = 0
function IsoGenerator.new()
	local proxy = { modData = {}, activated = false }
	function proxy:setSquare(square) self.square = square end
	function proxy:getSquare() return self.square end
	function proxy:getModData() return self.modData end
	function proxy:setActivated(enabled)
		setActivatedCalls = setActivatedCalls + 1
		self.activated = enabled == true
		if self.activated and self.square and self.square:getBuilding() then
			self.square:getBuilding():setToxic(true)
		end
	end
	function proxy:isActivated() return self.activated end
	function proxy:removeFromWorld() removeFromWorldCalls = removeFromWorldCalls + 1 end
	return proxy
end

local chunks = {}
for wx = 8, 18 do
	for wy = 8, 18 do
		local chunk = { adds = 0, removes = 0, positions = {} }
		function chunk:addGeneratorPos(x, y, z)
			self.adds = self.adds + 1
			self.positions[x .. "," .. y .. "," .. z] = true
		end
		function chunk:removeGeneratorPos(x, y, z)
			self.removes = self.removes + 1
			self.positions[x .. "," .. y .. "," .. z] = nil
		end
		chunks[wx .. "," .. wy] = chunk
	end
end

local cell = {
	getChunk = function(_, wx, wy) return chunks[wx .. "," .. wy] end,
	getGridSquare = function(_, x, y, z) return squares[squareKey(x, y, z)] end,
}
getCell = function() return cell end

local function nativeHasPower(x, y, z)
	local wx, wy = math.floor(x / NATIVE_CHUNK_SIZE), math.floor(y / NATIVE_CHUNK_SIZE)
	local chunk = chunks[wx .. "," .. wy]
	if not chunk then return false end
	for position in pairs(chunk.positions) do
		local sourceX, sourceY, sourceZ = position:match("^(-?%d+),(-?%d+),(-?%d+)$")
		sourceX, sourceY, sourceZ = tonumber(sourceX), tonumber(sourceY), tonumber(sourceZ)
		local sourceSquare = squares[squareKey(sourceX, sourceY, sourceZ)]
		local generator = sourceSquare and sourceSquare:getGenerator() or nil
		local dx, dy = x - sourceX, y - sourceY
		if generator and generator:isActivated() and sourceZ == z
			and dx * dx + dy * dy <= SandboxVars.GeneratorTileRange ^ 2 then
			return true
		end
	end
	return false
end

-- Project Zomboid's Kahlua environment does not expose Lua's global next().
-- Keep it unavailable for the complete test so compatibility regressions fail.
next = nil
dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/shared/WaterPipe/PowerPipe.lua")

local function drainDirtyChunks()
	local passes = 0
	while PowerPipe.getPendingDirtyChunkCount() > 0 or PowerPipe.hasPendingMaintenance() do
		assert(handlers.OnTick, "dirty power chunks require the registered tick worker")
		handlers.OnTick()
		passes = passes + 1
		assert(passes < 1000, "dirty power chunk processing must make progress")
	end
end

local function mapSize(values)
	local count = 0
	for _ in pairs(values or {}) do count = count + 1 end
	return count
end

local emptyOriginSquare = newSquare(80, 80, 0)
handlers.LoadGridsquare(emptyOriginSquare)
assert(PowerPipe.getPendingDirtyChunkCount() == 0,
	"loading an empty chunk must not enqueue power topology work")
assert(mapSize(PowerPipe.chunkSources) == 0,
	"a world without powered pipes must keep the power topology empty")

local square = newSquare(100, 100, 0)
assert(PowerPipe.registerSourceAt(100, 100, 0))
local firstProxy = PowerPipe.proxies["100,100,0"]
assert(firstProxy and firstProxy:isActivated(),
	"native cleanup requires an active IsoGenerator witness on the source square")
assert(square:getSpecialObjects():size() == 1
	and square:getSpecialObjects():get(0) == firstProxy,
	"the witness must live in the source square's special-object list")
assert(square:getGenerator() == firstProxy and square:getGenerator():isActivated(),
	"Build 42's missing-generator cleanup must retain the registered coordinate")
assert(square.building:isToxic() == false,
	"activating an invisible witness must preserve the building's toxicity state")
assert(setActivatedCalls == 1 and removeFromWorldCalls == 1,
	"the witness must set the native flag once and immediately leave generator processing")
assert(chunks["12,12"].positions["100,100,0"] == true,
	"Build 42 world coordinate 100,100 must register in its native 8x8 chunk")
assert(nativeHasPower(101, 100, 0),
	"a vanilla appliance beside the powered pipe must find electricity in its own chunk")
assert(PowerPipe.getPendingDirtyChunkCount() > 0,
	"a wide power radius should defer non-local chunks instead of rebuilding them all at once")
drainDirtyChunks()
local registeredChunks = 0
for _, chunk in pairs(chunks) do
	assert(chunk.adds == 0 or chunk.adds == 1)
	if chunk.adds == 1 then registeredChunks = registeredChunks + 1 end
end
assert(registeredChunks == 27,
	"the circular 20-tile range should omit non-powered corner chunks")

PowerPipe.refreshSources()
assert(PowerPipe.getPendingDirtyChunkCount() == 0,
	"unchanged periodic maintenance must not queue a full topology rebuild")
assert(PowerPipe.hasPendingMaintenance(),
	"wide periodic maintenance should be spread over ticks")
drainDirtyChunks()
for _, chunk in pairs(chunks) do
	assert(chunk.adds == 0 or chunk.adds == 2)
end

SandboxVars.GeneratorTileRange = 0
PowerPipe.refreshSources()
drainDirtyChunks()
for key, chunk in pairs(chunks) do
	if key == "12,12" then
		assert(chunk.adds == 3 and chunk.removes == 1)
	elseif chunk.adds == 2 then
		assert(chunk.removes == 1)
	else
		assert(chunk.adds == 0 and chunk.removes == 0)
	end
end

assert(PowerPipe.unregisterSourceAt(100, 100, 0))
assert(chunks["12,12"].removes == 2,
	"disabling a source must remove its vanilla generator position")
assert(PowerPipe.proxies["100,100,0"] == nil
	and square:getSpecialObjects():size() == 0,
	"disabling the last representative must remove its invisible witness")

local modData = {}
local transmitted = 0
local object = {
	getModData = function() return modData end,
	getSquare = function() return square end,
	transmitModData = function() transmitted = transmitted + 1 end,
}
assert(PowerPipe.setObjectEnabled(object, true))
assert(modData.powerSupplyPipe == true and transmitted == 1)
assert(PowerPipe.proxies["100,100,0"] ~= nil)
assert(PowerPipe.setObjectEnabled(object, false))
assert(modData.powerSupplyPipe == nil and transmitted == 2)
assert(PowerPipe.proxies["100,100,0"] == nil)

SandboxVars.GeneratorTileRange = 20
for x = 100, 109 do
	for y = 100, 109 do
		if not squares[squareKey(x, y, 0)] then newSquare(x, y, 0) end
		PowerPipe.registerSourceAt(x, y, 0)
	end
end
drainDirtyChunks()

local selectedCount = 0
for _ in pairs(PowerPipe.chunkSources["12,12"]) do selectedCount = selectedCount + 1 end
assert(selectedCount == 1,
	"one representative source is sufficient when 100 pipes all cover the chunk")
assert(mapSize(PowerPipe.chunkCandidates["12,12"]) == 100,
	"the chunk-local index must contain only sources capable of touching that chunk")

local selectedKey, selectedSource
for key, source in pairs(PowerPipe.chunkSources["12,12"]) do
	selectedKey, selectedSource = key, source
	break
end
assert(selectedKey and selectedSource)
assert(PowerPipe.unregisterSourceAt(selectedSource.x, selectedSource.y, selectedSource.z))
drainDirtyChunks()
assert(mapSize(PowerPipe.chunkSources["12,12"]) == 1 and nativeHasPower(101, 100, 0),
	"removing a compressed representative must choose a replacement without losing power")

newSquare(148, 148, 0)
assert(PowerPipe.registerSourceAt(148, 148, 0))
drainDirtyChunks()
assert(mapSize(PowerPipe.chunkCandidates["12,12"]) == 99,
	"a distant source must not enlarge an unrelated chunk's candidate scan")
assert(PowerPipe.unregisterSourceAt(148, 148, 0))
drainDirtyChunks()

for x = 90, 109 do
	for y = 90, 109 do
		if not squares[squareKey(x, y, 0)] then newSquare(x, y, 0) end
		assert(PowerPipe.registerSourceAt(x, y, 0))
	end
end
drainDirtyChunks()
assert(mapSize(PowerPipe.chunkCandidates["12,12"]) == 400,
	"a dense 400-pipe field must remain isolated in its local chunk index")
assert(mapSize(PowerPipe.chunkSources["12,12"]) == 1,
	"dense fields that share coverage should keep one native witness per chunk")
for loadedKey in pairs(chunks) do
	local wx, wy = loadedKey:match("^(%d+),(%d+)$")
	wx, wy = tonumber(wx), tonumber(wy)
	local selected = PowerPipe.chunkSources[loadedKey] or {}
	for localY = 0, NATIVE_CHUNK_SIZE - 1 do
		for localX = 0, NATIVE_CHUNK_SIZE - 1 do
			local x = wx * NATIVE_CHUNK_SIZE + localX
			local y = wy * NATIVE_CHUNK_SIZE + localY
			local coveredByAll = false
			for _, source in pairs(PowerPipe.sources) do
				local dx, dy = x - source.x, y - source.y
				if dx * dx + dy * dy <= 400 then coveredByAll = true break end
			end
			local coveredBySelected = false
			for _, source in pairs(selected) do
				local dx, dy = x - source.x, y - source.y
				if dx * dx + dy * dy <= 400 then coveredBySelected = true break end
			end
			assert(coveredBySelected == coveredByAll,
				"chunk-local compression must preserve every powered tile")
		end
	end
end

local selectedBeforeMaintenance = PowerPipe.chunkSources["12,12"]
PowerPipe.refreshSources()
assert(PowerPipe.chunkSources["12,12"] == selectedBeforeMaintenance,
	"periodic maintenance must reuse the compressed topology when range is unchanged")
assert(PowerPipe.getPendingDirtyChunkCount() == 0,
	"periodic maintenance must remain linear in selected representatives")
drainDirtyChunks()

local proxyCount = 0
for key, proxy in pairs(PowerPipe.proxies) do
	proxyCount = proxyCount + 1
	assert(proxy:isActivated(), "every compressed representative needs an active witness")
	local source = PowerPipe.sources[key]
	local proxySquare = proxy:getSquare()
	assert(source and proxySquare
		and proxySquare:getSpecialObjects():get(0) == proxy,
		"every witness must remain attached to its representative source square")
end
assert(proxyCount > 0 and proxyCount < 400,
	"dense pipe fields must share compressed native-power witnesses")

for y = 100, 109 do
	for x = 100, 109 do
		local coveredByAll = false
		for _, source in pairs(PowerPipe.sources) do
			local dx, dy = x - source.x, y - source.y
			if dx * dx + dy * dy <= 400 then coveredByAll = true break end
		end
		local coveredBySelected = false
		for _, source in pairs(PowerPipe.chunkSources["12,12"]) do
			local dx, dy = x - source.x, y - source.y
			if dx * dx + dy * dy <= 400 then coveredBySelected = true break end
		end
		assert(coveredBySelected == coveredByAll,
			"compressed sources must preserve the exact powered tiles")
	end
end

local fridgeSquare = newSquare(82, 80, 0)
local magicFridge = {
	getName = function() return "MagicFridge" end,
	getModData = function() return { magicFridge = true, powerSupplyPipe = true } end,
	getSquare = function() return fridgeSquare end,
}
fridgeSquare:getObjects():add(magicFridge)
handlers.OnObjectAdded(magicFridge)
drainDirtyChunks()
assert(PowerPipe.sources["82,80,0"],
	"a magic fridge should reuse the native pipe power source")
handlers.LoadGridsquare(fridgeSquare)
assert(PowerPipe.sources["82,80,0"],
	"grid loading must not prune a magic fridge power source")
handlers.OnObjectAboutToBeRemoved(magicFridge)
drainDirtyChunks()
assert(not PowerPipe.sources["82,80,0"],
	"removing a magic fridge should unregister its power source")

print("PASS test_power_pipe.lua")
