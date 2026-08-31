package.preload["ISUI/ISCollapsableWindow"] = function() return {} end
package.preload["ISUI/ISRichTextPanel"] = function() return {} end
package.preload["ISUI/ISButton"] = function() return {} end
package.preload["ISUI/ISComboBox"] = function() return {} end
package.preload["ISUI/Maps/ISWorldMap"] = function() return {} end

WaterPipe = { pipes = {} }

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/client/WaterPipe/WaterPipeNetworksUI.lua")

local function pipe(x, y, z, pipeType)
	return { x = x, y = y, z = z, pipeType = pipeType }
end

assert(WaterPipeNetworksUI.arePipesConnectedForDisplay(
	pipe(10, 10, 0, "lineOption"), pipe(11, 10, 0, "crossOption")),
	"adjacent pipes on one floor should remain connected in the network display")
assert(WaterPipeNetworksUI.arePipesConnectedForDisplay(
	pipe(10, 10, 0, "verticalNorthOption"), pipe(10, 10, 1, "verticalSouthOption")),
	"stacked vertical risers on adjacent floors should connect")
assert(not WaterPipeNetworksUI.arePipesConnectedForDisplay(
	pipe(10, 10, 0, "verticalEastOption"), pipe(10, 10, 1, "lineOption")),
	"a normal floor pipe must not create a cross-floor connection")
assert(not WaterPipeNetworksUI.arePipesConnectedForDisplay(
	pipe(10, 10, 0, "verticalNorthOption"), pipe(10, 10, 2, "verticalWestOption")),
	"vertical risers must not jump over a missing floor")
assert(not WaterPipeNetworksUI.arePipesConnectedForDisplay(
	pipe(10, 10, 0, "verticalSouthOption"), pipe(11, 10, 1, "verticalSouthOption")),
	"offset vertical risers must not connect diagonally between floors")

WaterPipe.pipes = {
	pipe(10, 10, 0, "verticalNorthOption"),
	pipe(10, 10, 1, "verticalWestOption"),
	pipe(11, 10, 1, "lineOption"),
	pipe(20, 20, 0, "lineOption"),
}
local networks = WaterPipeNetworksUI.getPipeNetworks()
assert(#networks == 2 and #networks[1] == 3 and #networks[2] == 1,
	"network grouping should traverse a vertical riser and then continue horizontally")

local target = WaterPipeNetworksUI.getNetworkMapTarget(networks[1])
assert(target and target.x == 10.5 and target.y == 10 and target.radius == 3,
	"network map target should use the connected group's bounding center")

local markerArgs
local marker = {}
local markersAPI = {
	addGridSquareMarker = function(_, ...)
		markerArgs = { ... }
		return marker
	end,
	removeMarker = function() end,
}
ISWorldMap = {
	IsAllowed = function() return true end,
	ShowWorldMap = function(playerNum, x, y, zoom)
		assert(playerNum == 0 and x == 10.5 and y == 10 and zoom == 18.0)
	end,
}
ISWorldMap_instance = {
	mapAPI = { getMarkersAPI = function() return markersAPI end },
}
assert(WaterPipeNetworksUI.showNetworkOnMap(networks[1], 0))
assert(markerArgs and markerArgs[1] == 11 and markerArgs[2] == 10
	and markerArgs[3] == 3 and WaterPipeNetworksUI.mapMarker == marker,
	"locating a network should add one temporary marker at its center")

print("PASS test_water_pipe_networks.lua")
