Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldObjects)
    for _, obj in ipairs(worldObjects) do
        if instanceof(obj, "IsoObject") and obj:getSprite() then
            local name = obj:getSprite():getName()
            if name and string.match(name, "WaterPipe") then
                context:addOption(getText("ContextMenu_WaterPipe_ViewNetwork"), worldObjects, function()
                    WaterPipeNetworksUI.toggleWindow()
                end)
                break
            end
        end
    end
end)