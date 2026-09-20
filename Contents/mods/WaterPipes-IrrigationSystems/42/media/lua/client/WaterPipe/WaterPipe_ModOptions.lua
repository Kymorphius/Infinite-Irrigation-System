require "PZAPI/ModOptions"
require "WaterPipe/PipeSprites"

WaterPipeModOptions = WaterPipeModOptions or {}

local MOD_OPTIONS_ID = "InfiniteIrrigationPipes"
local GROUND_LAYER_OPTION_ID = "GroundLayerDisplay"
local IRRIGATION_RANGE_SIZES = { 1, 3, 5, 7, 9, 11, 15 }
local OPTION_SPECS = {
    {
        id = "IrrigationRange", default = 2, kind = "combo",
        tooltip = "Sandbox_WaterPipes_IrrigationRange_tooltip",
        choices = {
            "IGUI_WaterPipe_IrrigationRange_1",
            "IGUI_WaterPipe_IrrigationRange_3",
            "IGUI_WaterPipe_IrrigationRange_5",
            "IGUI_WaterPipe_IrrigationRange_7",
            "IGUI_WaterPipe_IrrigationRange_9",
            "IGUI_WaterPipe_IrrigationRange_11",
            "IGUI_WaterPipe_IrrigationRange_15",
        },
    },
    { id = "ShowCleanup", default = false, tooltip = "Sandbox_WaterPipes_ShowCleanup_tooltip" },
    { id = "EnableAutoFarming", default = false,
        tooltip = "Sandbox_WaterPipes_EnableAutoFarming_tooltip" },
    { id = "CleanupVegetation", default = true, tooltip = "Sandbox_WaterPipes_CleanupVegetation_tooltip" },
    { id = "CleanupTrees", default = true, tooltip = "Sandbox_WaterPipes_CleanupTrees_tooltip" },
    { id = "CleanupZombies", default = true, tooltip = "Sandbox_WaterPipes_CleanupZombies_tooltip" },
    { id = "CleanupCorpses", default = true, tooltip = "Sandbox_WaterPipes_CleanupCorpses_tooltip" },
    { id = "CleanupBlood", default = true, tooltip = "Sandbox_WaterPipes_CleanupBlood_tooltip" },
    { id = "CleanupGroundItems", default = true, tooltip = "Sandbox_WaterPipes_CleanupGroundItems_tooltip" },
    { id = "InfiniteRevive", default = true },
    { id = "InfiniteReviveToSeeded", default = false },
    { id = "InfiniteAutoPlow", default = false },
    { id = "InfinitePestCare", default = true },
    { id = "InfiniteCompost", default = true },
    { id = "InfiniteNoRotten", default = true },
    { id = "InfiniteInstantGrowUp", default = true },
    {
        id = "MagicFridgePreserveSeeds", default = true,
        title = "Sandbox_WaterPipes_MagicFridgeGroup",
        tooltip = "Sandbox_WaterPipes_MagicFridgePreserveSeeds_tooltip",
    },
    {
        id = "MagicFridgeHarvestInterval", default = 1, kind = "combo",
        tooltip = "Sandbox_WaterPipes_MagicFridgeHarvestInterval_tooltip",
        choices = {
            "Sandbox_WaterPipes_MagicFridgeHarvestInterval_option1",
            "Sandbox_WaterPipes_MagicFridgeHarvestInterval_option2",
            "Sandbox_WaterPipes_MagicFridgeHarvestInterval_option3",
            "Sandbox_WaterPipes_MagicFridgeHarvestInterval_option4",
            "Sandbox_WaterPipes_MagicFridgeHarvestInterval_option5",
            "Sandbox_WaterPipes_MagicFridgeHarvestInterval_option6",
        },
    },
    {
        id = "PreventFarmlandDestruction", default = false,
        title = "Sandbox_WaterPipes_FarmlandProtectionGroup",
        tooltip = "Sandbox_WaterPipes_PreventFarmlandDestruction_tooltip",
    },
}

local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
local createdOptions = not options
if createdOptions then
    options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, "IGUI_WaterPipe_ModOptions_Title")
    options:addDescription("IGUI_WaterPipe_ModOptions_Description")
    options:addTitle("IGUI_WaterPipe_ModOptions_Settings")
end

local function addWorldOption(spec)
    local tooltip = spec.tooltip or "IGUI_WaterPipe_ModOptions_Tooltip"
    if spec.kind == "combo" then
        local option = options:addComboBox(
            spec.id,
            "Sandbox_WaterPipes_" .. spec.id,
            tooltip
        )
        for index, choice in ipairs(spec.choices) do
            option:addItem(choice, index == spec.default)
        end
    else
        options:addTickBox(
            spec.id,
            "Sandbox_WaterPipes_" .. spec.id,
            spec.default,
            tooltip
        )
    end
end

-- Add newly introduced world settings after a Lua reload even if an older
-- revision already created this Mod Options page.
for _, spec in ipairs(OPTION_SPECS) do
    if not options:getOption(spec.id) then
        if spec.title then options:addTitle(spec.title) end
        addWorldOption(spec)
    end
end

-- Also covers a Lua reload where the options object was created by an older
-- revision before this local-only setting existed.
if not options:getOption(GROUND_LAYER_OPTION_ID) then
    options:addTitle("IGUI_WaterPipe_ModOptions_LocalSettings")
    options:addTickBox(
        GROUND_LAYER_OPTION_ID,
        "IGUI_WaterPipe_GroundLayerDisplay",
        true,
        "IGUI_WaterPipe_GroundLayerDisplay_Tooltip"
    )
end

WaterPipeModOptions.options = options
WaterPipeModOptions.inGame = false

local function setOptionValues(source, enabled)
    for _, spec in ipairs(OPTION_SPECS) do
        local option = options:getOption(spec.id)
        local value = source and source[spec.id]
        if spec.kind == "combo" then
            value = tonumber(value)
            if not value or value < 1 or value > #spec.choices then value = spec.default end
        elseif type(value) ~= "boolean" then
            value = spec.default
        end
        option:setValue(value)
        option:setEnabled(enabled)
    end
end

local function applyLocalDisplayOption()
    local option = options:getOption(GROUND_LAYER_OPTION_ID)
    option:setEnabled(true)
    if WaterPipeSprite and WaterPipeSprite.setGroundLayerEnabled then
        WaterPipeSprite.setGroundLayerEnabled(option:getValue() == true)
    end
end

function WaterPipeModOptions.showMainMenuDefaults()
    WaterPipeModOptions.inGame = false
    setOptionValues(nil, false)
    applyLocalDisplayOption()
end

function WaterPipeModOptions.syncFromSandbox()
    WaterPipeModOptions.inGame = true
    local sandbox = SandboxVars and SandboxVars.WaterPipes
    local editable = not (isClient and isClient())
    setOptionValues(sandbox, editable)
    applyLocalDisplayOption()
end

function options:apply()
    applyLocalDisplayOption()
    local sandbox = SandboxVars and SandboxVars.WaterPipes
    local isMultiplayerClient = isClient and isClient()

    if not WaterPipeModOptions.inGame or not sandbox or isMultiplayerClient then
        if WaterPipeModOptions.inGame and sandbox then
            setOptionValues(sandbox, false)
        else
            setOptionValues(nil, false)
        end
        return
    end

    local autoTillWasEnabled = sandbox.InfiniteAutoPlow == true
    local autoFarmingWasEnabled = sandbox.EnableAutoFarming == true
    local oldIrrigationRange = tonumber(sandbox.IrrigationRange) or 2
    local oldCleanupSettings = {}
    for _, id in ipairs({ "CleanupVegetation", "CleanupTrees", "CleanupZombies",
        "CleanupCorpses", "CleanupBlood", "CleanupGroundItems" }) do
        oldCleanupSettings[id] = sandbox[id] ~= false
    end
    for _, spec in ipairs(OPTION_SPECS) do
        sandbox[spec.id] = options:getOption(spec.id):getValue()
    end

    local sandboxOptions = getSandboxOptions and getSandboxOptions()
    if sandboxOptions and sandboxOptions.updateFromLua then
        sandboxOptions:updateFromLua()
    end

    local autoTillIsEnabled = sandbox.InfiniteAutoPlow == true
    local autoFarmingIsEnabled = sandbox.EnableAutoFarming == true
    local irrigationRangeChanged = oldIrrigationRange ~= (tonumber(sandbox.IrrigationRange) or 2)
    local autoTillChanged = autoTillWasEnabled ~= autoTillIsEnabled
    local autoFarmingChanged = autoFarmingWasEnabled ~= autoFarmingIsEnabled
    local cleanupSettingsChanged = false
    for id, oldValue in pairs(oldCleanupSettings) do
        if oldValue ~= (sandbox[id] ~= false) then cleanupSettingsChanged = true break end
    end
    if (irrigationRangeChanged or autoTillChanged or autoFarmingChanged)
        and WaterPipe and WaterPipe.markCoverageMapDirty then
        WaterPipe.markCoverageMapDirty()
    end
    if irrigationRangeChanged and WaterPipe and WaterPipe.queueGlobalRangeShrink then
        local oldRangeSize = IRRIGATION_RANGE_SIZES[math.floor(oldIrrigationRange)] or 3
        local newRangeIndex = math.floor(tonumber(sandbox.IrrigationRange) or 2)
        local newRangeSize = IRRIGATION_RANGE_SIZES[newRangeIndex] or 3
        if newRangeSize < oldRangeSize then
            WaterPipe.queueGlobalRangeShrink(oldRangeSize, newRangeSize)
        end
    end
    local anyAutoTillEnabled = WaterPipe and WaterPipe.hasAnyAutoTillEnabled
        and WaterPipe.hasAnyAutoTillEnabled()
    if WaterPipe then WaterPipe.lastGlobalAutoTillEnabled = autoTillIsEnabled end
    if autoTillChanged and WaterPipe then
        if anyAutoTillEnabled and WaterPipe.requestAutoTillPass then
            if WaterPipe.requestAutoTillPass() and WaterPipe.processAutoTillPass then
                WaterPipe.processAutoTillPass()
            end
        elseif WaterPipe.cancelAutoTillPass then
            WaterPipe.cancelAutoTillPass()
        end
    elseif irrigationRangeChanged and anyAutoTillEnabled
        and WaterPipe.requestAutoTillPass then
        WaterPipe.requestAutoTillPass()
    end
    if cleanupSettingsChanged and WaterPipe and WaterPipe.hasAnyCleanupEnabled
        and WaterPipe.hasAnyCleanupEnabled() and WaterPipe.requestCleanupPass then
        if WaterPipe.requestCleanupPass() and WaterPipe.processCleanupPass then
            WaterPipe.processCleanupPass()
        end
    end
end

Events.OnMainMenuEnter.Add(WaterPipeModOptions.showMainMenuDefaults)
Events.OnGameStart.Add(WaterPipeModOptions.syncFromSandbox)
