require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISTextEntryBox"
require "ISUI/LootWindow/ISLootWindowContainerControls"
require "ISUI/LootWindow/ISLootWindowObjectControlHandler"
require "WaterPipe/MagicFridge"

AutoFarmSettingsUI = AutoFarmSettingsUI or {}

local SettingsWindow = ISCollapsableWindow:derive("WaterPipeAutoFarmSettingsWindow")
local PAD = 10
local ROW_HGT = 24
local BUTTON_HGT = 26
local DEFAULT_LIMIT = 9

local function isModuleEnabled()
	return SandboxVars and SandboxVars.WaterPipes
		and SandboxVars.WaterPipes.EnableAutoFarming == true
end

local function copySettings(settings)
	local result = {}
	if type(settings) ~= "table" then return result end
	for cropType, value in pairs(settings) do
		if type(cropType) == "string" and type(value) == "table" then
			result[cropType] = {
				enabled = value.enabled ~= false,
				produceLimit = math.max(-1,
					math.floor(tonumber(value.produceLimit) or DEFAULT_LIMIT)),
				keepSeeds = value.keepSeeds ~= false,
				seedLimit = math.max(-1,
					math.floor(tonumber(value.seedLimit) or DEFAULT_LIMIT)),
			}
		end
	end
	return result
end

local function getDisplayName(cropType, props)
	if props and props.vegetableName and getScriptManager then
		local item = getScriptManager():FindItem(props.vegetableName)
		if item then return item:getDisplayName() end
	end
	return tostring(cropType)
end

local function getCropRows(settings)
	local rows = {}
	local propsByCrop = farming_vegetableconf and farming_vegetableconf.props or {}
	for cropType, props in pairs(propsByCrop) do
		if props and props.vegetableName and (props.seedTypes or props.seedName) then
			local value = settings[cropType] or {}
			table.insert(rows, {
				cropType = cropType,
				name = getDisplayName(cropType, props),
				enabled = value.enabled ~= false,
				produceLimit = math.max(-1,
					math.floor(tonumber(value.produceLimit) or DEFAULT_LIMIT)),
				keepSeeds = value.keepSeeds ~= false,
				seedLimit = math.max(-1,
					math.floor(tonumber(value.seedLimit) or DEFAULT_LIMIT)),
			})
		end
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

local function limitText(value)
	value = tonumber(value) or -1
	return value < 0 and getText("IGUI_WaterPipe_AutoFarmUnlimited") or tostring(value)
end

function SettingsWindow:drawCropRow(y, item, alt)
	if y + self:getYScroll() + item.height < 0
		or y + self:getYScroll() >= self.height then return y + item.height end
	if self.selected == item.index then
		self:drawSelection(0, y, self:getWidth(), item.height - 1)
	elseif self.mouseoverselected == item.index and self:isMouseOver()
		and not self:isMouseOverScrollBar() then
		self:drawMouseOverHighlight(0, y, self:getWidth(), item.height - 1)
	end
	local row = item.item
	local tick = row.enabled and "✓" or "×"
	self:drawText(tick, 8, y + 4, row.enabled and 0.35 or 0.85,
		row.enabled and 0.85 or 0.35, 0.35, 1, UIFont.Small)
	self:drawText(row.name, 32, y + 4, 0.9, 0.9, 0.9, 1, UIFont.Small)
	self:drawText(limitText(row.produceLimit), self.fridgeMode and 505 or 300,
		y + 4, 0.9, 0.9, 0.9, 1, UIFont.Small)
	if self.fridgeMode then return y + item.height end
	local seeds = row.keepSeeds and "✓" or "×"
	self:drawText(seeds, 420, y + 4, row.keepSeeds and 0.35 or 0.85,
		row.keepSeeds and 0.85 or 0.35, 0.35, 1, UIFont.Small)
	self:drawText(limitText(row.seedLimit), 505, y + 4, 0.9, 0.9, 0.9, 1, UIFont.Small)
	return y + item.height
end

local function newTickBox(x, y, width, label, selected)
	local tick = ISTickBox:new(x, y, width, ROW_HGT, "")
	tick:initialise()
	tick:instantiate()
	tick:addOption(label)
	tick:setSelected(1, selected == true)
	return tick
end

local function newLimitEntry(x, y, width)
	local entry = ISTextEntryBox:new("", x, y, width, BUTTON_HGT)
	entry:initialise()
	entry:instantiate()
	entry:setOnlyNumbers(true)
	return entry
end

local function readLimitEntry(entry)
	local text = entry and entry:getText() or ""
	return text == "" and -1 or math.max(0, tonumber(text) or 0)
end

function SettingsWindow:createFridgeChildren(titleY)
	self.productionEnabled = newTickBox(PAD, titleY, 240,
		getText("IGUI_WaterPipe_MagicFridgeProductionEnabled"),
		self.initialProductionEnabled)
	self:addChild(self.productionEnabled)
	local bulkY = titleY + ROW_HGT + 5
	self.bulkProductEntry = newLimitEntry(320, bulkY, 80)
	self.bulkProductEntry:setText(tostring(DEFAULT_LIMIT))
	self:addChild(self.bulkProductEntry)
	self.bulkProductButton = ISButton:new(410, bulkY, 160, BUTTON_HGT,
		getText("IGUI_WaterPipe_AutoFarmApplyAll"), self,
		SettingsWindow.onApplyAllProducts)
	self.bulkProductButton:initialise()
	self.bulkProductButton:instantiate()
	self:addChild(self.bulkProductButton)
	local headerY = bulkY + BUTTON_HGT + 8
	self.list = ISScrollingListBox:new(PAD, headerY + 20, self.width - PAD * 2, 255)
	self.list:initialise()
	self.list:instantiate()
	self.list.fridgeMode = true
	self.list.itemheight = ROW_HGT
	self.list.font = UIFont.Small
	self.list.doDrawItem = self.drawCropRow
	self.list.drawBorder = true
	self:addChild(self.list)
	for _, row in ipairs(self.rows) do self.list:addItem(row.name, row) end
	self.list.selected = #self.rows > 0 and 1 or 0
	local editY = self.list:getBottom() + PAD
	self.cropEnabled = newTickBox(PAD, editY, 240,
		getText("IGUI_WaterPipe_MagicFridgeCropEnabled"), true)
	self:addChild(self.cropEnabled)
	local entryY = editY + ROW_HGT + 5
	self.productEntry = newLimitEntry(500, entryY, 90)
	self:addChild(self.productEntry)
	local buttonY = entryY + BUTTON_HGT + PAD
	self.saveButton = ISButton:new(PAD, buttonY, 120, BUTTON_HGT,
		getText("IGUI_WaterPipe_AutoFarmSave"), self, SettingsWindow.onSave)
	self.saveButton:initialise()
	self.saveButton:instantiate()
	self:addChild(self.saveButton)
	self.saveAllButton = ISButton:new(140, buttonY, 250, BUTTON_HGT,
		getText("IGUI_WaterPipe_MagicFridgeSaveAll"), self,
		SettingsWindow.onSaveAll)
	self.saveAllButton:initialise()
	self.saveAllButton:instantiate()
	self:addChild(self.saveAllButton)
	self.cancelButton = ISButton:new(self.width - PAD - 120, buttonY, 120, BUTTON_HGT,
		getText("IGUI_WaterPipe_AutoFarmCancel"), self, SettingsWindow.onCancel)
	self.cancelButton:initialise()
	self.cancelButton:instantiate()
	self.cancelButton:enableCancelColor()
	self:addChild(self.cancelButton)
	self:setHeight(buttonY + BUTTON_HGT + PAD)
	self:loadSelectedRow()
end

function SettingsWindow:createChildren()
	ISCollapsableWindow.createChildren(self)
	local titleY = self:titleBarHeight() + PAD
	if self.fridgeMode then return self:createFridgeChildren(titleY) end
	self.autoSow = newTickBox(PAD, titleY, 220,
		getText("IGUI_WaterPipe_AutoSow"), self.initialAutoSow)
	self:addChild(self.autoSow)
	self.autoHarvest = newTickBox(250, titleY, 220,
		getText("IGUI_WaterPipe_AutoHarvest"), self.initialAutoHarvest)
	self:addChild(self.autoHarvest)

	-- Keep the two global limits on separate rows.  Their English/Russian labels
	-- are substantially wider than Chinese and must not overlap the controls.
	local bulkProductY = titleY + ROW_HGT + 5
	local bulkEntryX = 320
	local bulkButtonX = 410
	self.bulkProductEntry = newLimitEntry(bulkEntryX, bulkProductY, 80)
	self.bulkProductEntry:setText(tostring(DEFAULT_LIMIT))
	self:addChild(self.bulkProductEntry)
	self.bulkProductButton = ISButton:new(bulkButtonX, bulkProductY, 160, BUTTON_HGT,
		getText("IGUI_WaterPipe_AutoFarmApplyAll"), self,
		SettingsWindow.onApplyAllProducts)
	self.bulkProductButton:initialise()
	self.bulkProductButton:instantiate()
	self:addChild(self.bulkProductButton)
	local bulkSeedY = bulkProductY + BUTTON_HGT + 5
	self.bulkSeedEntry = newLimitEntry(bulkEntryX, bulkSeedY, 80)
	self.bulkSeedEntry:setText(tostring(DEFAULT_LIMIT))
	self:addChild(self.bulkSeedEntry)
	self.bulkSeedButton = ISButton:new(bulkButtonX, bulkSeedY, 160, BUTTON_HGT,
		getText("IGUI_WaterPipe_AutoFarmApplyAll"), self,
		SettingsWindow.onApplyAllSeeds)
	self.bulkSeedButton:initialise()
	self.bulkSeedButton:instantiate()
	self:addChild(self.bulkSeedButton)

	local headerY = bulkSeedY + BUTTON_HGT + 8
	self.list = ISScrollingListBox:new(PAD, headerY + 20, self.width - PAD * 2, 255)
	self.list:initialise()
	self.list:instantiate()
	self.list.itemheight = ROW_HGT
	self.list.font = UIFont.Small
	self.list.doDrawItem = self.drawCropRow
	self.list.drawBorder = true
	self:addChild(self.list)
	for _, row in ipairs(self.rows) do self.list:addItem(row.name, row) end
	self.list.selected = #self.rows > 0 and 1 or 0

	local editY = self.list:getBottom() + PAD
	self.cropEnabled = newTickBox(PAD, editY, 180,
		getText("IGUI_WaterPipe_AutoFarmCropEnabled"), true)
	self:addChild(self.cropEnabled)
	self.keepSeeds = newTickBox(210, editY, 220,
		getText("IGUI_WaterPipe_AutoFarmKeepSeeds"), true)
	self:addChild(self.keepSeeds)

	local entryY = editY + ROW_HGT + 5
	self.productEntry = newLimitEntry(165, entryY, 90)
	self:addChild(self.productEntry)
	self.seedEntry = newLimitEntry(455, entryY, 90)
	self:addChild(self.seedEntry)

	local buttonY = entryY + BUTTON_HGT + PAD
	self.saveButton = ISButton:new(PAD, buttonY, 120, BUTTON_HGT,
		getText("IGUI_WaterPipe_AutoFarmSave"), self, SettingsWindow.onSave)
	self.saveButton:initialise()
	self.saveButton:instantiate()
	self:addChild(self.saveButton)
	self.cancelButton = ISButton:new(self.width - PAD - 120, buttonY, 120, BUTTON_HGT,
		getText("IGUI_WaterPipe_AutoFarmCancel"), self, SettingsWindow.onCancel)
	self.cancelButton:initialise()
	self.cancelButton:instantiate()
	self.cancelButton:enableCancelColor()
	self:addChild(self.cancelButton)
	self:setHeight(buttonY + BUTTON_HGT + PAD)
	self:loadSelectedRow()
end

function SettingsWindow:prerender()
	ISCollapsableWindow.prerender(self)
	local headerY = self.list.y - 18
	if self.fridgeMode then
		self:drawText(getText("IGUI_WaterPipe_MagicFridgeAllProducts"), PAD,
			self.bulkProductEntry.y + 5, 0.8, 0.8, 0.8, 1, UIFont.Small)
		self:drawText(getText("IGUI_WaterPipe_AutoFarmCrop"), PAD + 32, headerY,
			0.8, 0.8, 0.8, 1, UIFont.Small)
		self:drawText(getText("IGUI_WaterPipe_MagicFridgeProductLimit"), 515, headerY,
			0.8, 0.8, 0.8, 1, UIFont.Small)
		self:drawText(getText("IGUI_WaterPipe_MagicFridgeProductTarget"), PAD,
			self.productEntry.y + 5, 0.8, 0.8, 0.8, 1, UIFont.Small)
		if self.editingIndex ~= self.list.selected then
			self:commitSelectedRow()
			self:loadSelectedRow()
		end
		return
	end
	self:drawText(getText("IGUI_WaterPipe_AutoFarmAllProducts"), PAD,
		self.bulkProductEntry.y + 5, 0.8, 0.8, 0.8, 1, UIFont.Small)
	self:drawText(getText("IGUI_WaterPipe_AutoFarmAllSeeds"), PAD,
		self.bulkSeedEntry.y + 5, 0.8, 0.8, 0.8, 1, UIFont.Small)
	self:drawText(getText("IGUI_WaterPipe_AutoFarmCrop"), PAD + 32, headerY,
		0.8, 0.8, 0.8, 1, UIFont.Small)
	self:drawText(getText("IGUI_WaterPipe_AutoFarmProductLimit"), PAD + 300, headerY,
		0.8, 0.8, 0.8, 1, UIFont.Small)
	self:drawText(getText("IGUI_WaterPipe_AutoFarmSeeds"), PAD + 420, headerY,
		0.8, 0.8, 0.8, 1, UIFont.Small)
	self:drawText(getText("IGUI_WaterPipe_AutoFarmSeedLimit"), PAD + 505, headerY,
		0.8, 0.8, 0.8, 1, UIFont.Small)
	local entryY = self.productEntry.y + 5
	self:drawText(getText("IGUI_WaterPipe_AutoFarmProductTarget"), PAD, entryY,
		0.8, 0.8, 0.8, 1, UIFont.Small)
	self:drawText(getText("IGUI_WaterPipe_AutoFarmSeedTarget"), 290, entryY,
		0.8, 0.8, 0.8, 1, UIFont.Small)
	if self.editingIndex ~= self.list.selected then
		self:commitSelectedRow()
		self:loadSelectedRow()
	end
end

function SettingsWindow:commitSelectedRow()
	local row = self.editingIndex and self.rows[self.editingIndex] or nil
	if not row then return end
	row.enabled = self.cropEnabled:isSelected(1)
	row.produceLimit = readLimitEntry(self.productEntry)
	if self.fridgeMode then return end
	row.keepSeeds = self.keepSeeds:isSelected(1)
	row.seedLimit = readLimitEntry(self.seedEntry)
end

function SettingsWindow:onApplyAllProducts()
	self:commitSelectedRow()
	local limit = readLimitEntry(self.bulkProductEntry)
	for _, row in ipairs(self.rows) do row.produceLimit = limit end
	self:loadSelectedRow()
end

function SettingsWindow:onApplyAllSeeds()
	self:commitSelectedRow()
	local limit = readLimitEntry(self.bulkSeedEntry)
	for _, row in ipairs(self.rows) do row.seedLimit = limit end
	self:loadSelectedRow()
end

function SettingsWindow:loadSelectedRow()
	local index = tonumber(self.list.selected) or 0
	local row = self.rows[index]
	self.editingIndex = row and index or nil
	if not row then return end
	self.cropEnabled:setSelected(1, row.enabled)
	self.productEntry:setText(row.produceLimit < 0 and "" or tostring(row.produceLimit))
	if self.fridgeMode then return end
	self.keepSeeds:setSelected(1, row.keepSeeds)
	self.seedEntry:setText(row.seedLimit < 0 and "" or tostring(row.seedLimit))
end

function SettingsWindow:collectSettings()
	self:commitSelectedRow()
	local settings = {}
	for _, row in ipairs(self.rows) do
		local value = {
			enabled = row.enabled,
			produceLimit = row.produceLimit,
		}
		if not self.fridgeMode then
			value.keepSeeds = row.keepSeeds
			value.seedLimit = row.seedLimit
		end
		settings[row.cropType] = value
	end
	return settings
end

function SettingsWindow:onSave()
	local settings = self:collectSettings()
	if self.fridgeMode then
		AutoFarmSettingsUI.saveFridge(
			self.player, self.pipeObject,
			self.productionEnabled:isSelected(1), settings
		)
		self:close()
		return
	end
	AutoFarmSettingsUI.save(
		self.player, self.pipeObject,
		self.autoSow:isSelected(1), self.autoHarvest:isSelected(1), settings
	)
	self:close()
end

function SettingsWindow:onSaveAll()
	AutoFarmSettingsUI.saveAllFridges(
		self.player, self.pipeObject,
		self.productionEnabled:isSelected(1), self:collectSettings()
	)
	self:close()
end

function SettingsWindow:onCancel()
	self:close()
end

function SettingsWindow:close()
	self:setVisible(false)
	self:removeFromUIManager()
	if AutoFarmSettingsUI.window == self then AutoFarmSettingsUI.window = nil end
end

function SettingsWindow:new(player, pipeObject, fridgeMode)
	local width, height = 620, 540
	local x = math.max(0, (getCore():getScreenWidth() - width) / 2)
	local y = math.max(0, (getCore():getScreenHeight() - height) / 2)
	local o = ISCollapsableWindow.new(self, x, y, width, height)
	o.player = player
	o.pipeObject = pipeObject
	o.fridgeMode = fridgeMode == true
	o.title = getText(fridgeMode and "IGUI_WaterPipe_MagicFridgeSettingsTitle"
		or "IGUI_WaterPipe_AutoFarmTitle")
	o.resizable = false
	local modData = pipeObject:getModData()
	if fridgeMode then
		o.initialProductionEnabled = modData.magicFridgeProductionEnabled ~= false
		o.settings = copySettings(modData.magicFridgeSettings)
		o.rows = getCropRows(o.settings)
		return o
	end
	o.initialAutoSow = type(modData["autoSowEnabled"]) ~= "boolean"
		or modData["autoSowEnabled"] == true
	o.initialAutoHarvest = type(modData["autoHarvestEnabled"]) ~= "boolean"
		or modData["autoHarvestEnabled"] == true
	o.settings = copySettings(modData["autoFarmSettings"])
	o.rows = getCropRows(o.settings)
	return o
end

function AutoFarmSettingsUI.save(player, pipeObject, autoSowEnabled, autoHarvestEnabled, settings)
	if not isModuleEnabled() then return false end
	if not player or not pipeObject or not pipeObject:getSquare() then return false end
	local square = pipeObject:getSquare()
	local sanitized = copySettings(settings)
	if isClient() then
		sendClientCommand(player, "WaterPipe", "setPlacedPipeAutoFarming", {
			x = square:getX(), y = square:getY(), z = square:getZ(),
			autoSowEnabled = autoSowEnabled == true,
			autoHarvestEnabled = autoHarvestEnabled == true,
			settings = sanitized,
		})
	elseif WaterPipeAutoFarming then
		WaterPipeAutoFarming.setObjectSettings(
			pipeObject, autoSowEnabled == true, autoHarvestEnabled == true, sanitized
		)
	end
	return true
end

function AutoFarmSettingsUI.open(player, pipeObject)
	if not isModuleEnabled() then return end
	if not player or not pipeObject or not pipeObject:getSquare() then return end
	if AutoFarmSettingsUI.window then AutoFarmSettingsUI.window:close() end
	local window = SettingsWindow:new(player, pipeObject)
	window:initialise()
	window:addToUIManager()
	AutoFarmSettingsUI.window = window
end

function AutoFarmSettingsUI.saveFridge(player, object, enabled, settings)
	if not player or not object or not object:getSquare() then return false end
	local square = object:getSquare()
	local sanitized = copySettings(settings)
	if isClient() then
		sendClientCommand(player, "WaterPipe", "setMagicFridgeProduction", {
			x = square:getX(), y = square:getY(), z = square:getZ(),
			enabled = enabled == true,
			settings = sanitized,
		})
	else
		MagicFridge.setObjectSettings(object, enabled == true, sanitized)
	end
	return true
end

function AutoFarmSettingsUI.saveAllFridges(player, object, enabled, settings)
	if not player or not object or not object:getSquare() then return false end
	local square = object:getSquare()
	local sanitized = copySettings(settings)
	if isClient() then
		sendClientCommand(player, "WaterPipe", "setAllMagicFridgeProduction", {
			x = square:getX(), y = square:getY(), z = square:getZ(),
			enabled = enabled == true,
			settings = sanitized,
		})
	else
		MagicFridge.setAllObjectSettings(enabled == true, sanitized)
	end
	return true
end

function AutoFarmSettingsUI.openFridge(player, object)
	if not player or not MagicFridge.isObject(object) or not object:getSquare() then return end
	if AutoFarmSettingsUI.window then AutoFarmSettingsUI.window:close() end
	local window = SettingsWindow:new(player, object, true)
	window:initialise()
	window:addToUIManager()
	AutoFarmSettingsUI.window = window
end

-- Use the same native bottom control strip as the stove/microwave settings
-- button.  The handler is considered only while this exact container is open;
-- normal inventories do not receive a button or any update-time polling.
ISLootWindowObjectControlHandler_WaterPipeAutoFarm =
	ISLootWindowObjectControlHandler_WaterPipeAutoFarm
	or ISLootWindowObjectControlHandler:derive(
		"ISLootWindowObjectControlHandler_WaterPipeAutoFarm")
local AutoFarmHandler = ISLootWindowObjectControlHandler_WaterPipeAutoFarm

function AutoFarmHandler:shouldBeVisible()
	return isModuleEnabled()
		and self.container ~= nil and self.container.getType
		and self.container:getType() == "InfiniteIrrigationPipe"
		and self.object ~= nil and self.object.getModData and self.object:getSquare() ~= nil
end

function AutoFarmHandler:getControl()
	self.control = self:getButtonControl(getText("IGUI_WaterPipe_AutoFarmSettingsButton"))
	return self.control
end

function AutoFarmHandler:handleJoypadContextMenu(context)
	self:addJoypadContextMenuOption(
		context, getText("IGUI_WaterPipe_AutoFarmSettingsButton"))
end

function AutoFarmHandler:perform()
	AutoFarmSettingsUI.open(self.playerObj, self.object)
end

function AutoFarmHandler:new()
	local o = ISLootWindowObjectControlHandler.new(self)
	o.altColor = true
	return o
end

ISLootWindowContainerControls.AddHandler(AutoFarmHandler, true)

ISLootWindowObjectControlHandler_MagicFridgeSettings =
	ISLootWindowObjectControlHandler_MagicFridgeSettings
	or ISLootWindowObjectControlHandler:derive(
		"ISLootWindowObjectControlHandler_MagicFridgeSettings")
local MagicFridgeHandler = ISLootWindowObjectControlHandler_MagicFridgeSettings

function MagicFridgeHandler:shouldBeVisible()
	return self.container ~= nil and self.container.getType
		and self.container:getType() == MagicFridge.containerType
		and MagicFridge.isObject(self.object)
		and self.object:getSquare() ~= nil
end

function MagicFridgeHandler:getControl()
	self.control = self:getButtonControl(
		getText("IGUI_WaterPipe_MagicFridgeSettingsButton"))
	return self.control
end

function MagicFridgeHandler:handleJoypadContextMenu(context)
	self:addJoypadContextMenuOption(
		context, getText("IGUI_WaterPipe_MagicFridgeSettingsButton"))
end

function MagicFridgeHandler:perform()
	AutoFarmSettingsUI.openFridge(self.playerObj, self.object)
end

function MagicFridgeHandler:new()
	local o = ISLootWindowObjectControlHandler.new(self)
	o.altColor = true
	return o
end

ISLootWindowContainerControls.AddHandler(MagicFridgeHandler, true)

return AutoFarmSettingsUI
