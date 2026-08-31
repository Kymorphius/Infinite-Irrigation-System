require "TimedActions/ISBaseTimedAction"

removeWaterSupplyPipeAction = ISBaseTimedAction:derive("removeWaterSupplyPipeAction")

function removeWaterSupplyPipeAction:isValid()
	return self.supplyObject and self.supplyObject:getSquare() == self.square
		and not WaterSupplyPipe.hasStoredItems(self.supplyObject)
end

function removeWaterSupplyPipeAction:update()
end

function removeWaterSupplyPipeAction:start()
end

function removeWaterSupplyPipeAction:stop()
	ISBaseTimedAction.stop(self)
end

function removeWaterSupplyPipeAction:perform()
	if isClient() then
		sendClientCommand(self.character, "WaterPipe", "pickUpSupply", {
			x = self.square:getX(),
			y = self.square:getY(),
			z = self.square:getZ(),
		})
	else
		WaterSupplyPipe.onPickUp(self.supplyObject, self.character)
	end

	ISBaseTimedAction.perform(self)
end

function removeWaterSupplyPipeAction:new(character, supplyObject, square, time)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character
	o.supplyObject = supplyObject
	o.square = square
	o.stopOnWalk = true
	o.stopOnRun = true
	o.maxTime = time
	return o
end
