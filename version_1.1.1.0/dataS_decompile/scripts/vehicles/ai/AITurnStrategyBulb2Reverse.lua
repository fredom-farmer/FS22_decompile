AITurnStrategyBulb2Reverse = {}
local AITurnStrategyBulb2Reverse_mt = Class(AITurnStrategyBulb2Reverse, AITurnStrategy)

function AITurnStrategyBulb2Reverse.new(customMt)
	if customMt == nil then
		customMt = AITurnStrategyBulb2Reverse_mt
	end

	local self = AITurnStrategy.new(customMt)
	self.strategyName = "AITurnStrategyBulb2Reverse"
	self.isReverseStrategy = true
	self.turnBox = self:createTurningSizeBox()

	return self
end

function AITurnStrategyBulb2Reverse:delete()
	AITurnStrategyBulb2Reverse:superClass().delete(self)

	self.maxTurningSizeBox = {}
	self.maxTurningSizeBox2 = {}
end

function AITurnStrategyBulb2Reverse:startTurn(driveStrategyStraight)
	if not AITurnStrategyBulb2Reverse:superClass().startTurn(self, driveStrategyStraight) then
		return false
	end

	local turnData = driveStrategyStraight.turnData
	local sideOffset = nil

	if self.turnLeft then
		sideOffset = turnData.sideOffsetLeft
	else
		sideOffset = turnData.sideOffsetRight
	end

	local zOffset = self.distanceToCollision

	self:updateTurningSizeBox(self.turnBox, self.turnLeft, turnData, 0)

	zOffset = zOffset + 2 * self.turnBox.size[3]
	local c2X, c2Y, c2Z = nil

	if sideOffset >= 0 then
		c2Z = 0
		c2Y = 0
		c2X = turnData.radius + 2 * sideOffset
	else
		c2Z = 0
		c2Y = 0
		c2X = -turnData.radius + 2 * sideOffset
	end

	local alpha = math.acos(math.abs(sideOffset) / turnData.radius)
	local c1X, c1Y, c1Z = nil

	if sideOffset >= 0 then
		c1X = turnData.radius
	else
		c1X = -turnData.radius
	end

	c1Y = 0
	c1Z = math.sin(alpha) * 2 * turnData.radius
	c1Z = c1Z + turnData.zOffsetTurn
	c2Z = c2Z + turnData.zOffsetTurn
	local rvX, rvY, rvZ = getWorldRotation(self.vehicle:getAIDirectionNode())
	local xb = math.max(turnData.toolOverhang.front.xb, turnData.toolOverhang.back.xb)
	local zb = 0
	local xt = math.max(turnData.toolOverhang.front.xt, turnData.toolOverhang.back.xt)
	local zt = 0
	local delta = math.max(xb, zb, turnData.radius + xt, turnData.radius + zt)
	local fullBulbLength = c1Z + delta
	local bulbLength = math.max(0, fullBulbLength - zOffset)
	local segment = {
		isCurve = false,
		moveForward = c1Z - bulbLength > 0,
		slowDown = true
	}

	if segment.moveForward then
		segment.skipToNextSegmentDistanceThreshold = 3
	end

	segment.startPoint = self:getVehicleToWorld(0, 0, 0, true)
	segment.endPoint = self:getVehicleToWorld(0, 0, c1Z - bulbLength, true)

	table.insert(self.turnSegments, segment)

	local segment = {
		isCurve = true,
		moveForward = true,
		radius = turnData.radius,
		o = createTransformGroup("segment1")
	}

	link(getRootNode(), segment.o)
	setTranslation(segment.o, self:getVehicleToWorld(c1X, c1Y, c1Z - bulbLength))
	setRotation(segment.o, rvX, rvY, rvZ)

	if sideOffset >= 0 then
		segment.startAngle = math.pi
		segment.endAngle = -alpha
	else
		segment.startAngle = 0
		segment.endAngle = math.pi + alpha
	end

	table.insert(self.turnSegments, segment)

	local segment = {
		isCurve = true,
		moveForward = true,
		radius = turnData.radius,
		o = createTransformGroup("segment2")
	}

	link(getRootNode(), segment.o)
	setTranslation(segment.o, self:getVehicleToWorld(c2X, c2Y, c2Z - bulbLength))
	setRotation(segment.o, rvX, rvY, rvZ)

	if sideOffset >= 0 then
		segment.startAngle = math.pi - alpha
		segment.endAngle = math.pi
	else
		segment.startAngle = alpha
		segment.endAngle = 0
	end

	table.insert(self.turnSegments, segment)

	local segment = {
		isCurve = false,
		moveForward = c2Z - bulbLength > c2Z - 2 * fullBulbLength,
		slowDown = true,
		checkAlignmentToSkipSegment = true
	}
	local x = 2 * sideOffset
	segment.startPoint = self:getVehicleToWorld(x, 0, c2Z - bulbLength, true)
	segment.endPoint = self:getVehicleToWorld(x, 0, c2Z - 2 * fullBulbLength, true)

	table.insert(self.turnSegments, segment)

	local zFinal = turnData.zOffset
	local segment = {
		isCurve = false,
		moveForward = zFinal < c2Z - 2 * fullBulbLength,
		slowDown = true,
		startPoint = self:getVehicleToWorld(x, 0, c2Z - 2 * fullBulbLength, true),
		endPoint = self:getVehicleToWorld(x, 0, zFinal, true)
	}

	table.insert(self.turnSegments, segment)
	self:startTurnFinalization()

	return true
end

function AITurnStrategyBulb2Reverse:updateTurningSizeBox(box, turnLeft, turnData, lookAheadDistance)
	local sideOffset = nil

	if turnLeft then
		sideOffset = turnData.sideOffsetLeft
	else
		sideOffset = turnData.sideOffsetRight
	end

	local c2X, c2Y, c2Z = nil

	if sideOffset >= 0 then
		c2Z = 0
		c2Y = 0
		c2X = turnData.radius + 2 * sideOffset
	else
		c2Z = 0
		c2Y = 0
		c2X = -turnData.radius + 2 * sideOffset
	end

	local alpha = math.acos(math.abs(sideOffset) / turnData.radius)
	local c1X, c1Y, c1Z = nil

	if sideOffset >= 0 then
		c1X = turnData.radius
	else
		c1X = -turnData.radius
	end

	c1Y = 0
	c1Z = math.sin(alpha) * 2 * turnData.radius
	c1Z = c1Z + turnData.zOffsetTurn
	c2Z = c2Z + turnData.zOffsetTurn
	local xb = math.max(turnData.toolOverhang.front.xb, turnData.toolOverhang.back.xb)
	local xt = math.max(turnData.toolOverhang.front.xt, turnData.toolOverhang.back.xt)
	local delta = math.max(xb, turnData.radius + xt)
	local maxX = c1X + delta
	local minX = c1X - delta
	local maxZ = math.max(turnData.toolOverhang.front.zt, turnData.zOffset + turnData.toolOverhang.back.zt)
	box.center[3] = maxZ / 2 + lookAheadDistance / 2
	box.center[2] = 0
	box.center[1] = maxX - (maxX - minX) / 2
	box.size[3] = maxZ / 2 + lookAheadDistance / 2
	box.size[2] = 5
	box.size[1] = (maxX - minX) / 2

	self:adjustHeightOfTurningSizeBox(box)
end
