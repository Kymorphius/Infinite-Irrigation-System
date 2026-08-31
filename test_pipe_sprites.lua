local spriteSerial = 0
local registeredSprites = {}

local function newProperties()
    local values = {}
    return {
        values = values,
        set = function(self, key, value)
            self.values[key] = value == nil and true or value
        end,
        CreateKeySet = function(self)
            self.createdKeySet = true
        end,
    }
end

local function newSprite(name)
    spriteSerial = spriteSerial + 1
    local properties = newProperties()
    return {
        id = spriteSerial,
        name = name,
        properties = properties,
        getName = function(self) return self.name end,
        setName = function(self, value) self.name = value end,
        LoadSingleTexture = function(self, texture) self.texture = texture end,
        getProperties = function(self) return self.properties end,
    }
end

IsoFlagType = { waterPiped = "FLAG_waterPiped" }
IsoSprite = { new = function() return newSprite(nil) end }
getSprite = function(name)
    if not registeredSprites[name] then registeredSprites[name] = newSprite(name) end
    return registeredSprites[name]
end

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/shared/WaterPipe/PipeSprites.lua")

local function newObject(name, pipeType, supply)
    local sprite = getSprite(WaterPipeSprite.byPipeType[pipeType])
    local square = {}
    return {
        sprite = sprite,
        tile = nil,
        modData = {
            infinite = true,
            pipeType = pipeType,
            waterSupplyPipe = supply and true or nil,
        },
        getName = function() return name end,
        getModData = function(self) return self.modData end,
        getSprite = function(self) return self.sprite end,
        getSpriteName = function(self) return self.sprite and self.sprite:getName() end,
        getTile = function(self) return self.tile end,
        setSprite = function(self, value) self.sprite = value end,
        setTile = function(self, value) self.tile = value end,
        getSquare = function() return square end,
    }
end

local irrigation = newObject("WaterPipe", "crossOption", false)
local supply = newObject("WaterSupplyPipe", "lineOption", true)
local vertical = newObject("WaterPipe", "verticalNorthOption", false)

WaterPipeSprite.registerDisplayObject(irrigation)
WaterPipeSprite.registerDisplayObject(supply)
WaterPipeSprite.registerDisplayObject(vertical)
assert(irrigation.sprite == getSprite(WaterPipeSprite.byPipeType.crossOption),
    "ground-layer mode should use the registered irrigation tile")
assert(supply.sprite == getSprite(WaterPipeSprite.supplyByPipeType.lineOption),
    "ground-layer mode should retain the registered native supply tile")

WaterPipeSprite.setGroundLayerEnabled(false)
assert(irrigation.sprite.texture == "media/textures/Item_PipeCross.png",
    "disabling ground-layer mode should restore the original direct PNG sprite")
assert(supply.sprite.texture == "media/textures/Item_PipeSE.png",
    "supply pipes should use the same original artwork when ground-layer mode is off")
assert(irrigation.sprite ~= supply.sprite,
    "supply and irrigation must not share a mutable direct sprite")
assert(supply.sprite.properties.values[IsoFlagType.waterPiped] == true
    and supply.sprite.properties.values.waterAmount == "10000"
    and supply.sprite.properties.values.waterMaxAmount == "10000",
    "the direct supply sprite should preserve vanilla plumbing properties")
assert(vertical.sprite == getSprite(WaterPipeSprite.byPipeType.verticalNorthOption),
    "vertical risers should keep their registered normal-depth sprite")

WaterPipeSprite.setGroundLayerEnabled(true)
assert(irrigation.sprite == getSprite(WaterPipeSprite.byPipeType.crossOption)
    and supply.sprite == getSprite(WaterPipeSprite.supplyByPipeType.lineOption),
    "enabling ground-layer mode should restore both registered Floor sprites")

WaterPipeSprite.unregisterDisplayObject(irrigation)
local directIrrigation = irrigation.sprite
WaterPipeSprite.setGroundLayerEnabled(false)
assert(irrigation.sprite == directIrrigation,
    "removed objects should no longer be touched by local display refreshes")

local loadedPipe = newObject("WaterPipe", "twOption", false)
local squareObjects = {
    size = function() return 1 end,
    get = function(_, index) return index == 0 and loadedPipe or nil end,
}
WaterPipeSprite.registerSquareObjects({
    getObjects = function() return squareObjects end,
})
assert(loadedPipe.sprite.texture == "media/textures/Item_PipeTW.png",
    "a pipe discovered while its saved square loads should receive the persisted mode")

print("WaterPipe sprite display-mode tests passed")
