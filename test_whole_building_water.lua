local function newEvent()
	local handlers = {}
	return {
		handlers = handlers,
		Add = function(handler) table.insert(handlers, handler) end,
		Remove = function(handler)
			for i = #handlers, 1, -1 do
				if handlers[i] == handler then table.remove(handlers, i) end
			end
		end,
	}
end

Events = {
	LoadGridsquare = newEvent(),
	OnObjectAboutToBeRemoved = newEvent(),
	OnTick = newEvent(),
}
IsoFlagType = { waterPiped = "waterPiped" }
instanceof = function(object, className)
	return object and object.className == className
end

local function objectList(items)
	return {
		size = function() return #items end,
		get = function(_, index) return items[index + 1] end,
	}
end

local buildingDef = {
	getIDString = function() return "building-1" end,
	getX = function() return 10 end,
	getX2 = function() return 11 end,
	getY = function() return 10 end,
	getY2 = function() return 10 end,
	getMinLevel = function() return 0 end,
	getMaxLevel = function() return 1 end,
}
local building = { getDef = function() return buildingDef end }

local fixture = {
	className = "IsoObject",
	modData = {},
	usesExternal = false,
}
function fixture:getModData() return self.modData end
function fixture:getSprite()
	return {
		getProperties = function()
			return { has = function(_, flag) return flag == "waterPiped" end }
		end,
	}
end
function fixture:getUsesExternalWaterSource() return self.usesExternal end
function fixture:setUsesExternalWaterSource(value) self.usesExternal = value end
function fixture:doFindExternalWaterSource() self.refoundOriginalSource = true end

local decoration = {
	className = "IsoObject",
	getModData = function() return {} end,
	getSprite = function()
		return { getProperties = function()
			return { has = function() return false end }
		end }
	end,
}

local indoorSquare = {
	getX = function() return 10 end,
	getY = function() return 10 end,
	getZ = function() return 0 end,
	getBuilding = function() return building end,
	getObjects = function() return objectList({ fixture, decoration }) end,
}
local upperSquare = {
	getX = function() return 10 end,
	getY = function() return 10 end,
	getZ = function() return 1 end,
	getBuilding = function() return building end,
	getObjects = function() return objectList({}) end,
}
local outdoorSquare = {
	getX = function() return 9 end,
	getY = function() return 10 end,
	getZ = function() return 0 end,
	getBuilding = function() return nil end,
	getObjects = function() return objectList({}) end,
}

local source = {
	modData = { waterSupplyPipe = true },
	square = outdoorSquare,
	transmits = 0,
}
function source:getModData() return self.modData end
function source:getSquare() return self.square end
function source:transmitModData() self.transmits = self.transmits + 1 end

local squares = {
	["9,10,0"] = outdoorSquare,
	["10,10,0"] = indoorSquare,
	["10,10,1"] = upperSquare,
}
getCell = function()
	return {
		getGridSquare = function(_, x, y, z)
			return squares[tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)]
		end,
	}
end

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/shared/WaterPipe/WholeBuildingWater.lua")
WholeBuildingWater.externalSourceSetter = function(object, externalSource)
	object.externalSource = externalSource
	return true
end

assert(#Events.LoadGridsquare.handlers == 1
	and #Events.OnObjectAboutToBeRemoved.handlers == 1,
	"whole-building water should use load/removal events rather than permanent scans")
assert(WholeBuildingWater.findConnectedBuilding(outdoorSquare) == building,
	"an outdoor pipe beside an exterior wall should connect to the adjacent building")
assert(WholeBuildingWater.setObjectEnabled(source, true),
	"a water-supply pipe should allow whole-building water to be enabled")
assert(source.modData.wholeBuildingWater == true and source.transmits == 1,
	"the per-pipe switch should persist and synchronize its state")
assert(#Events.OnTick.handlers == 1,
	"the initial building scan should register temporary batched work")

while #WholeBuildingWater.scanQueue > 0 do
	WholeBuildingWater.processPendingScans()
end
assert(fixture.externalSource == source and fixture.usesExternal == true,
	"water fixtures on loaded floors should use the pipe as their native external source")
assert(decoration.externalSource == nil,
	"non-water furniture must never be linked")
assert(#Events.OnTick.handlers == 0,
	"the per-frame callback should remove itself after the finite building scan")

assert(WholeBuildingWater.setObjectEnabled(source, false),
	"whole-building water should be independently disabled")
assert(source.modData.wholeBuildingWater == nil and fixture.externalSource == nil
	and fixture.usesExternal == false,
	"disabling the source should unlink fixtures and restore their prior plumbing state")

WholeBuildingWater.externalSourceSetter = function() return false end
assert(WholeBuildingWater.setObjectEnabled(source, true))
while #WholeBuildingWater.scanQueue > 0 do
	WholeBuildingWater.processPendingScans()
end
assert(fixture:getModData().waterAmount == 10000
	and fixture:getModData().waterMaxAmount == 10000
	and fixture:getModData().canBeWaterPiped == false,
	"a reserve-water fallback should keep fixtures usable if private native linking is unavailable")
assert(WholeBuildingWater.setObjectEnabled(source, false)
	and fixture:getModData().waterAmount == nil
	and fixture:getModData().waterMaxAmount == nil
	and fixture:getModData().canBeWaterPiped == nil,
	"disabling fallback supply should restore the fixture's original water metadata")

WholeBuildingWater.externalSourceSetter = nil
fixture.getClass = function()
	error("production whole-building water must not attempt Java reflection")
end
assert(WholeBuildingWater.setObjectEnabled(source, true))
while #WholeBuildingWater.scanQueue > 0 do
	WholeBuildingWater.processPendingScans()
end
assert(fixture:getModData().waterAmount == 10000,
	"production should use the supported reserve-water path without reflection")
assert(WholeBuildingWater.setObjectEnabled(source, false))

local irrigationOnly = {
	getModData = function() return { waterSupplyPipe = false } end,
}
assert(not WholeBuildingWater.setObjectEnabled(irrigationOnly, true),
	"whole-building water cannot be enabled while ordinary water supply is off")

print("PASS test_whole_building_water.lua")
