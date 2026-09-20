require "TimedActions/ISBaseTimedAction"
require "WaterPipe/MagicFridge"

removeMagicFridgeAction = ISBaseTimedAction:derive("removeMagicFridgeAction")

function removeMagicFridgeAction:isValid()
	return self.square and MagicFridge.findOnSquare(self.square) ~= nil
end

function removeMagicFridgeAction:perform()
	if isClient() then
		sendClientCommand(self.character, "WaterPipe", "pickUpMagicFridge", {
			x = self.square:getX(), y = self.square:getY(), z = self.square:getZ(),
		})
	else
		local object = MagicFridge.findOnSquare(self.square)
		if object then MagicFridge.pickUp(object, self.character) end
	end
	ISBaseTimedAction.perform(self)
end

function removeMagicFridgeAction:new(character, square)
	local object = {}
	setmetatable(object, self)
	self.__index = self
	object.character = character
	object.square = square
	object.stopOnWalk = true
	object.stopOnRun = true
	object.maxTime = 10
	return object
end
