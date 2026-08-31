require "WaterPipe/WaterPipeNetworksUI"

local function openWaterPipeNetworkUI(key)
    if key == Keyboard.KEY_U then
        WaterPipeNetworksUI.toggleWindow()
    end
end

Events.OnKeyPressed.Add(openWaterPipeNetworkUI)
