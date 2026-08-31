---- Garden Hoses By Kyun, thanks to Robert Johnson for it's rain collector barrel and farming mod (among others !)

require "BuildingObjects/ISBuildingObject"
require "WaterPipe/PipeSprites"
require "BuildingObjects/zwaterSupplyPipe"

Pipe = ISBuildingObject:derive("Pipe");

function Pipe:getCharacter()
	local character = self.character or self.playerObject
	if not character and self.player ~= nil and getSpecificPlayer then
		character = getSpecificPlayer(self.player)
	end
	return character
end

-- The build cursor remains active after a placement.  Its cached item is the
-- pipe consumed by the previous ISBuildAction, so refresh it from the player's
-- inventory before validating or executing the next placement.
function Pipe:refreshPipeItem(character)
	character = character or self:getCharacter()
	local inventory = character and character:getInventory()
	if not inventory then
		self.pipeItem = nil
		return nil, nil
	end

	if self.pipeItem and inventory:containsRecursive(self.pipeItem) then
		return self.pipeItem, self.pipeItem:getContainer() or inventory
	end

	self.pipeItem = inventory:getFirstTypeRecurse("WaterPipes.WaterPipe")
	if not self.pipeItem then
		return nil, nil
	end

	return self.pipeItem, self.pipeItem:getContainer() or inventory
end

function Pipe.checkForBarrel(square)
	for i = 0, square:getSpecialObjects():size() - 1 do
		if square:getSpecialObjects():get(i):getName() == "Rain Collector Barrel" then
			return true;
		end
	end
	return false;
end

function Pipe:create(x, y, z, north, sprite)
	-- Build 42 多人建造由服务器执行 create()。此时必须使用
	-- ISBuildAction 注入的 character，不能依赖仅在客户端 new() 中取得的玩家对象。
	local character = self:getCharacter()
	if not character then
		return false
	end

	local pipeItem, itemContainer = self:refreshPipeItem(character)
	if not pipeItem then
		self:reset();
		return false
	end

	local cell = getWorld():getCell();
	self.sq = cell:getGridSquare(x, y, z);
	if not self.sq then return false end

	local initialMode = WaterSupplyPipe.isValidMode(self.initialMode)
		and self.initialMode or "irrigation"
	if initialMode == "off" and not self.initialPower then initialMode = "irrigation" end
	local pipeOwner = WaterPipe.getCharacterOwnerId(character)
	local initialFarmEnabled = initialMode == "irrigation" or initialMode == "both"

	if initialMode == "irrigation" then
		-- The placement preview still uses the editable PNG, but the real world
		-- object uses a registered tile sprite.  Ground shapes own
		-- RenderLayer=Floor; the vertical riser keeps normal world depth sorting.
	local renderSprite, registeredSprite = WaterPipeSprite.getRegisteredFloorSprite(sprite, self.pipeType)
	-- In single-player, construct the object exactly like the pre-Floor version
	-- when the local display option is off.  Creating it with the PNG path keeps
	-- it out of the Floor render batch from its very first frame.
	if not isServer() and WaterPipeSprite.groundLayerEnabled == false then
		renderSprite = WaterPipeSprite.textureByPipeType[self.pipeType] or sprite
		registeredSprite = nil
	elseif not registeredSprite then
		renderSprite = sprite
	end
		self.javaObject = IsoObject.new(self.sq, renderSprite or sprite, "WaterPipe");
		if not self.javaObject then return false end

		self.javaObject:getModData()["pipeType"] = self.pipeType;
		self.javaObject:getModData()["infinite"] = true;
		self.javaObject:getModData()["powerSupplyPipe"] = self.initialPower and true or nil;
		self.javaObject:getModData()["waterPipeOwner"] = pipeOwner;
		self.javaObject:getModData()["careEnabled"] = true;
		self.javaObject:getModData()["fertilizeEnabled"] = true;
		self.javaObject:getModData()["cleanupEnabled"] = false;
		self.javaObject:getModData()["cleanupShrunkFarmArea"] = false;
		self.javaObject:getModData()["autoSowEnabled"] = true;
		self.javaObject:getModData()["autoHarvestEnabled"] = true;
		self.javaObject:getModData()["autoFarmSettings"] = {};
		WaterSupplyPipe.ensureStorage(self.javaObject)
		self.sq:AddTileObject(self.javaObject);
		WaterPipe.loadPipe(self.javaObject)
		PowerPipe.syncObjectSource(self.javaObject)
	else
		-- Supply-capable modes need an IsoThumpable whose registered sprite owns
		-- the native clean-water properties.  Create that final object directly so
		-- clients never see a temporary irrigation-only pipe.
		self.javaObject = WaterSupplyPipe.createPlacedPipe(
			self.sq,
			initialMode,
			self.pipeType,
			{
				pipeType = self.pipeType,
				infinite = true,
				powerSupplyPipe = self.initialPower and true or nil,
				waterPipeOwner = pipeOwner,
				careEnabled = initialFarmEnabled,
				fertilizeEnabled = initialFarmEnabled,
				cleanupEnabled = false,
				cleanupShrunkFarmArea = false,
				autoSowEnabled = true,
				autoHarvestEnabled = true,
				autoFarmSettings = {},
			}
		)
		if not self.javaObject then return false end
	end
	self.javaObject:transmitCompleteItemToClients();

	character:removeFromHands(pipeItem);
	itemContainer:Remove(pipeItem);
	if isServer() then
		sendRemoveItemFromContainer(itemContainer, pipeItem);
	end

	return true
end


---
-- Test if it's possible to place
--
function Pipe:isValid(square, north)
	if not square or not self:refreshPipeItem() then
		return false;
	end

	local testForPermitted = false;
	local specialObjectsCount = square:getSpecialObjects():size();
	local specialObjectsAllowed = 0;

	-- 检查所有功能状态的管道，供水、供电或全部关闭的管道也不能叠放。
	if WaterSupplyPipe.findAnyPipeObject(square) then
		return false;
	end

	-- 计算允许的特殊对象数量（仅墙体）
	for i = 0, specialObjectsCount - 1 do
		if (square:getSpecialObjects():get(i):getType() == IsoObjectType.wall) then
			specialObjectsAllowed = specialObjectsAllowed + 1;
		end
	end
	
	-- 修改：放宽限制，允许室内放置
	-- 原来的逻辑：specialObjectsAllowed >= specialObjectsCount（过于严格）
	-- 新逻辑：只要没有冲突的对象就允许放置
	if specialObjectsCount == 0 then
		-- 空地，允许放置
		return true;
	elseif specialObjectsAllowed > 0 then
		-- 有墙体但可以放置
		return true;
	elseif specialObjectsCount <= 2 then
		-- 少量特殊对象（如门、窗等），仍然允许放置
		return true;
	end

	return false;
end


---
--
--
function Pipe:render(x, y, z, square, north)
	ISBuildingObject.render(self, x, y, z, square, north)
	-- return true;
end


---
--
--
function Pipe:getHealth()
	return 100;
end


---
--
--
function Pipe:new(player, pipeItem, spritea, pipeType, initialMode, initialPower)
	local o = {};
	setmetatable(o, self);
	self.__index = self;
	o:init();

	o:setSprite(spritea);

	o.name = "Water Pipe";
	o.dismantable = false;
	o.canBarricade = false;
	o.blockAllTheSquare = false;
	o.canPassThrough = true;
	o.maxTime = 10;
	o.isContainer = false;
	o.isThumpable = false;
	o.noNeedHammer = true;

	o.pipeItem = pipeItem;
	o.player = player;

	o.pipeType = pipeType;
	o.initialMode = initialMode or "irrigation";
	o.initialPower = initialPower == true;

	return o;
end


----------------------

---
-- When pipe is removed / destroyed
--

-- delete sprite and call removal pipe from network
function Pipe.pipeRemoveTile(pipeObject)
	local square = pipeObject:getSquare();
	PowerPipe.unregisterSourceAt(square:getX(), square:getY(), square:getZ());
	square:transmitRemoveItemFromSquare(pipeObject);
	square:RemoveTileObject(pipeObject);
	square:DeleteTileObject(pipeObject);
	Pipe.pipeRemove(square:getX(), square:getY(), square:getZ());
end

-- delete pipe from network
function Pipe.pipeRemove(x, y , z, breakOnFind)
	return WaterPipe.removePipeDataAt(x, y, z)
end

-- not used (future for destroyin with sledge)
function Pipe.onPipeDestroy(pipe)
	local square = getWorld():getCell():getGridSquare(pipe.x, pipe.y, pipe.z);
	local pipeObject = WaterPipe.findPipeObject(square)
	if square and pipeObject ~= nil then
		Pipe.pipeRemoveTile(pipeObject)
	end
end

-- pipe pickup
function Pipe.onPickUp(pipe, player)
	if not pipe or not player then return false end

	--print('\t', "Pipe pickup", pipe.x, pipe.y, pipe.z)
	local square = getWorld():getCell():getGridSquare(pipe.x, pipe.y, pipe.z);
	if not square then return false end
	local pipeObject = WaterPipe.findPipeObject(square)

	if square and pipeObject ~= nil then
		if WaterSupplyPipe.hasStoredItems(pipeObject) then return false end
		Pipe.pipeRemoveTile(pipeObject)
		
		-- wp2
		if isServer() then
			player:sendObjectChange('addItemOfType', { type = "WaterPipes.WaterPipe", count = 1 });
		else
			player:getInventory():AddItem("WaterPipes.WaterPipe");
		end

		-- refund partial pipes mk1
		local waterPipeData = WaterPipe.modData and WaterPipe.modData.WaterPipes
		local removed = waterPipeData and waterPipeData.removedWaterPipes or 0
		if removed and removed > 0 then
			if isServer() then
				player:sendObjectChange('addItemOfType', { type = "WaterPipes.WaterPipe", count = removed });
			else
				for i = 1, removed do
					player:getInventory():AddItem("WaterPipes.WaterPipe");
				end
			end
			waterPipeData.removedWaterPipes = 0
		end

		return true
	end

	return false
end
