local function newEvent()
    local handlers = {}
    return {
        handlers = handlers,
        Add = function(handler)
            table.insert(handlers, handler)
        end,
    }
end

Events = {
    OnMainMenuEnter = newEvent(),
    OnGameStart = newEvent(),
}

local multiplayerClient = false
isClient = function() return multiplayerClient end

local sandboxUpdateCalls = 0
getSandboxOptions = function()
    return {
        updateFromLua = function()
            sandboxUpdateCalls = sandboxUpdateCalls + 1
        end,
    }
end

local autoTillRequests = 0
local autoTillProcesses = 0
local autoTillCancels = 0
local coverageDirtyCalls = 0
local cleanupRequests = 0
local cleanupProcesses = 0
local globalShrinkCalls = {}
WaterPipe = {
    hasAnyAutoTillEnabled = function()
        return SandboxVars and SandboxVars.WaterPipes
            and SandboxVars.WaterPipes.InfiniteAutoPlow == true
    end,
    requestAutoTillPass = function()
        autoTillRequests = autoTillRequests + 1
        return true
    end,
    processAutoTillPass = function()
        autoTillProcesses = autoTillProcesses + 1
    end,
    cancelAutoTillPass = function()
        autoTillCancels = autoTillCancels + 1
    end,
    markCoverageMapDirty = function()
        coverageDirtyCalls = coverageDirtyCalls + 1
    end,
    hasAnyCleanupEnabled = function() return true end,
    requestCleanupPass = function()
        cleanupRequests = cleanupRequests + 1
        return true
    end,
    processCleanupPass = function()
        cleanupProcesses = cleanupProcesses + 1
    end,
	queueGlobalRangeShrink = function(oldRange, newRange)
		table.insert(globalShrinkCalls, { oldRange = oldRange, newRange = newRange })
	end,
}

local Options = {}
Options.__index = Options

function Options:addDescription(text)
    table.insert(self.data, { type = "description", text = text })
end

function Options:addTitle(name)
    table.insert(self.data, { type = "title", name = name })
end

function Options:addTickBox(id, name, value, tooltip)
    local option = {
        id = id,
        name = name,
        value = value,
        tooltip = tooltip,
        isEnabled = true,
    }
    function option:getValue() return self.value end
    function option:setValue(newValue) self.value = newValue end
    function option:setEnabled(enabled) self.isEnabled = enabled end
    self.dict[id] = option
    table.insert(self.data, option)
    return option
end

function Options:addComboBox(id, name, tooltip)
    local option = {
        id = id,
        name = name,
        tooltip = tooltip,
        values = {},
        selected = 1,
        isEnabled = true,
    }
    function option:addItem(value, selected)
        table.insert(self.values, value)
        if selected then self.selected = #self.values end
    end
    function option:getValue() return self.selected end
    function option:setValue(newValue) self.selected = newValue end
    function option:setEnabled(enabled) self.isEnabled = enabled end
    self.dict[id] = option
    table.insert(self.data, option)
    return option
end

function Options:getOption(id)
    return self.dict[id]
end

PZAPI = {
    ModOptions = {
        Dict = {},
    },
}

function PZAPI.ModOptions:getOptions(id)
    return self.Dict[id]
end

function PZAPI.ModOptions:create(id, name)
    local created = setmetatable({ id = id, name = name, data = {}, dict = {} }, Options)
    self.Dict[id] = created
    return created
end

package.preload["PZAPI/ModOptions"] = function() return PZAPI.ModOptions end

local groundLayerValues = {}
WaterPipeSprite = {
    setGroundLayerEnabled = function(value)
        table.insert(groundLayerValues, value)
    end,
}
package.preload["WaterPipe/PipeSprites"] = function() return WaterPipeSprite end

SandboxVars = {
    WaterPipes = {
        IrrigationRange = 3,
        ShowCleanup = false,
        EnableAutoFarming = false,
        CleanupVegetation = true,
        CleanupTrees = true,
        CleanupZombies = true,
        CleanupCorpses = true,
        CleanupBlood = true,
        CleanupGroundItems = true,
        InfiniteRevive = false,
        InfiniteReviveToSeeded = true,
        InfiniteAutoPlow = false,
        InfinitePestCare = false,
        InfiniteCompost = false,
        InfiniteNoRotten = false,
        InfiniteInstantGrowUp = false,
        MagicFridgePreserveSeeds = true,
        MagicFridgeHarvestInterval = 1,
        PreventFarmlandDestruction = false,
    },
}

dofile("Contents/mods/WaterPipes-IrrigationSystems/42/media/lua/client/WaterPipe/WaterPipe_ModOptions.lua")

local options = PZAPI.ModOptions:getOptions("InfiniteIrrigationPipes")
assert(options ~= nil, "the native B42 Mods options page should be registered")

local optionCount = 0
for _, item in ipairs(options.data) do
    if item.id then optionCount = optionCount + 1 end
end
assert(optionCount == 20,
	"the two selectors, seventeen world switches, and local display switch should be shown")
assert(options:getOption("MagicFridgePreserveSeeds"):getValue() == true,
	"the magic fridge should preserve seeds by default")
assert(options:getOption("MagicFridgeHarvestInterval"):getValue() == 1
	and #options:getOption("MagicFridgeHarvestInterval").values == 6,
	"the magic fridge should default to the ten-minute cycle and expose every interval")
assert(options:getOption("PreventFarmlandDestruction"):getValue() == false,
    "farmland protection should be an explicit opt-in")
local protectionTitleIndex, protectionOptionIndex
for index, item in ipairs(options.data) do
    if item.name == "Sandbox_WaterPipes_FarmlandProtectionGroup" then protectionTitleIndex = index end
    if item.id == "PreventFarmlandDestruction" then protectionOptionIndex = index end
end
assert(protectionTitleIndex and protectionOptionIndex == protectionTitleIndex + 1,
    "farmland protection should have its own settings group")
assert(#options:getOption("IrrigationRange").values == 7,
    "the world range selector should expose every supported size through 15x15")
assert(options:getOption("ShowCleanup"):getValue() == false,
	"the destructive cleanup control should be hidden by default")
assert(options:getOption("EnableAutoFarming"):getValue() == false,
	"the automatic farming module should require an explicit global opt-in")
assert(options:getOption("CleanupGroundItems").tooltip
        == "Sandbox_WaterPipes_CleanupGroundItems_tooltip",
    "dangerous ground-item cleanup should have a dedicated explanation")

Events.OnMainMenuEnter.handlers[1]()
assert(options:getOption("InfiniteRevive"):getValue() == true,
    "the main menu should show the sandbox default rather than a previous world's value")
assert(options:getOption("InfiniteRevive").isEnabled == false,
    "main-menu defaults should be read-only because no world is active")
assert(options:getOption("IrrigationRange"):getValue() == 2,
    "the main menu should show the default 3x3 range")
assert(options:getOption("GroundLayerDisplay"):getValue() == true
    and options:getOption("GroundLayerDisplay").isEnabled == true,
    "the local display setting should remain editable in the main menu")

Events.OnGameStart.handlers[1]()
assert(options:getOption("InfiniteRevive"):getValue() == false,
    "single-player options should load the active world's sandbox values")
assert(options:getOption("InfiniteRevive").isEnabled == true,
    "single-player options should be editable")
assert(options:getOption("IrrigationRange"):getValue() == 3,
    "single-player options should load the world's 5x5 enum value")

options:getOption("GroundLayerDisplay"):setValue(false)
options:apply()
assert(groundLayerValues[#groundLayerValues] == false,
    "applying options should immediately switch the local pipe display mode")
assert(SandboxVars.WaterPipes.GroundLayerDisplay == nil,
    "the local display preference must never be written into server SandboxVars")

options:getOption("InfiniteRevive"):setValue(true)
options:getOption("InfiniteNoRotten"):setValue(true)
options:getOption("MagicFridgePreserveSeeds"):setValue(false)
options:getOption("MagicFridgeHarvestInterval"):setValue(3)
options:getOption("IrrigationRange"):setValue(4)
options:apply()
assert(SandboxVars.WaterPipes.InfiniteRevive == true
    and SandboxVars.WaterPipes.InfiniteNoRotten == true
    and SandboxVars.WaterPipes.MagicFridgePreserveSeeds == false
    and SandboxVars.WaterPipes.MagicFridgeHarvestInterval == 3
    and SandboxVars.WaterPipes.IrrigationRange == 4,
    "single-player changes should write back to SandboxVars")
assert(coverageDirtyCalls == 1,
    "changing the global range should invalidate the shared coverage map")
assert(sandboxUpdateCalls == 2,
    "single-player changes should update the game's persistent sandbox options")

options:getOption("InfiniteAutoPlow"):setValue(true)
options:apply()
assert(autoTillRequests == 1 and autoTillProcesses == 1,
    "enabling auto-till should immediately start the first one-shot batch")
assert(coverageDirtyCalls == 2,
    "changing the global auto-till state should rebuild per-position till eligibility")
options:getOption("IrrigationRange"):setValue(3)
options:apply()
assert(autoTillRequests == 2 and coverageDirtyCalls == 3,
    "changing the global range while auto-till is enabled should schedule the new area")
assert(#globalShrinkCalls == 1
	and globalShrinkCalls[1].oldRange == 7 and globalShrinkCalls[1].newRange == 5,
	"only a global range reduction should queue the exact retired area")
options:getOption("InfiniteAutoPlow"):setValue(false)
options:apply()
assert(autoTillCancels == 1,
    "disabling auto-till should cancel an unfinished one-shot pass")
assert(coverageDirtyCalls == 4,
    "disabling global auto-till should remove till eligibility from follow-global positions")

options:getOption("CleanupGroundItems"):setValue(false)
options:apply()
assert(SandboxVars.WaterPipes.CleanupGroundItems == false,
    "cleanup category choices should write back to the active world's sandbox settings")
assert(cleanupRequests == 1 and cleanupProcesses == 1,
    "changing cleanup categories should immediately start one bounded refresh pass")

options:getOption("EnableAutoFarming"):setValue(true)
options:apply()
assert(SandboxVars.WaterPipes.EnableAutoFarming == true,
	"single-player settings should enable the optional automatic-farming module")
assert(coverageDirtyCalls == 5,
	"changing the automatic-farming module state should rebuild service coverage")

multiplayerClient = true
SandboxVars.WaterPipes.InfiniteRevive = false
Events.OnGameStart.handlers[1]()
assert(options:getOption("InfiniteRevive"):getValue() == false,
    "multiplayer options should reflect the server-provided sandbox value")
assert(options:getOption("InfiniteRevive").isEnabled == false,
    "multiplayer sandbox options should be read-only")

options:getOption("InfiniteRevive"):setValue(true)
options:apply()
assert(SandboxVars.WaterPipes.InfiniteRevive == false,
    "a multiplayer client must not change server-owned sandbox values")
assert(options:getOption("InfiniteRevive"):getValue() == false,
    "a multiplayer apply attempt should restore the authoritative server value")
assert(sandboxUpdateCalls == 7,
    "a multiplayer client must not update local sandbox persistence")
assert(options:getOption("GroundLayerDisplay").isEnabled == true,
    "the local display setting should remain editable on multiplayer clients")
assert(autoTillRequests == 2 and autoTillProcesses == 1 and autoTillCancels == 1,
    "a multiplayer client must not schedule or cancel server auto-till work")

print("WaterPipe native mod-options tests passed")
