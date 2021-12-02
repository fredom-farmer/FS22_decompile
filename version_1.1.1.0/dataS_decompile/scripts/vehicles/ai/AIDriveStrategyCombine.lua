AIDriveStrategyCombine = {}
local AIDriveStrategyCombine_mt = Class(AIDriveStrategyCombine, AIDriveStrategy)

function AIDriveStrategyCombine.new(customMt)
	if customMt == nil then
		customMt = AIDriveStrategyCombine_mt
	end

	local self = AIDriveStrategy.new(customMt)
	self.combines = {}
	self.notificationFullGrainTankShown = false
	self.notificationGrainTankWarningShown = false
	self.beaconLightsActive = false
	self.slowDownFillLevel = 200
	self.slowDownStartSpeed = 20
	self.forageHarvesterFoundTimer = 0

	return self
end

function AIDriveStrategyCombine:setAIVehicle(vehicle)
	AIDriveStrategyCombine:superClass().setAIVehicle(self, vehicle)

	if SpecializationUtil.hasSpecialization(Combine, self.vehicle.specializations) then
		table.insert(self.combines, self.vehicle)
	end

	for _, implement in pairs(self.vehicle:getAttachedAIImplements()) do
		if SpecializationUtil.hasSpecialization(Combine, implement.object.specializations) then
			table.insert(self.combines, implement.object)
		end
	end
end

function AIDriveStrategyCombine:update(dt)
	for _, combine in pairs(self.combines) do
		if combine.spec_pipe ~= nil then
			local capacity = 0
			local dischargeNode = combine:getCurrentDischargeNode()

			if dischargeNode ~= nil then
				capacity = combine:getFillUnitCapacity(dischargeNode.fillUnitIndex)
			end

			if capacity == math.huge then
				local rootVehicle = self.vehicle.rootVehicle

				if rootVehicle.getAIFieldWorkerIsTurning ~= nil and not rootVehicle:getAIFieldWorkerIsTurning() then
					local trailer = NetworkUtil.getObject(combine.spec_pipe.nearestObjectInTriggers.objectId)

					if trailer ~= nil then
						local trailerFillUnitIndex = combine.spec_pipe.nearestObjectInTriggers.fillUnitIndex
						local fillType = combine:getDischargeFillType(dischargeNode)

						if fillType == FillType.UNKNOWN then
							fillType = trailer:getFillUnitFillType(trailerFillUnitIndex)

							if fillType == FillType.UNKNOWN then
								fillType = trailer:getFillUnitFirstSupportedFillType(trailerFillUnitIndex)
							end

							combine:setForcedFillTypeIndex(fillType)
						else
							combine:setForcedFillTypeIndex(nil)
						end
					end
				end
			end
		end
	end
end

function AIDriveStrategyCombine:getDriveData(dt, vX, vY, vZ)
	local rootVehicle = self.vehicle.rootVehicle
	local isTurning = rootVehicle.getAIFieldWorkerIsTurning ~= nil and rootVehicle:getAIFieldWorkerIsTurning()
	local allowedToDrive = true
	local waitForStraw = false
	local maxSpeed = math.huge

	for _, combine in pairs(self.combines) do
		if combine.spec_pipe ~= nil then
			local fillLevel = 0
			local capacity = 0
			local trailerInTrigger = false
			local invalidTrailerInTrigger = false
			local dischargeNode = combine:getCurrentDischargeNode()

			if dischargeNode ~= nil then
				fillLevel = combine:getFillUnitFillLevel(dischargeNode.fillUnitIndex)
				capacity = combine:getFillUnitCapacity(dischargeNode.fillUnitIndex)
			end

			local trailer = NetworkUtil.getObject(combine.spec_pipe.nearestObjectInTriggers.objectId)

			if trailer ~= nil then
				trailerInTrigger = true
			end

			if combine.spec_pipe.nearestObjectInTriggerIgnoreFillLevel then
				invalidTrailerInTrigger = true
			end

			local currentPipeTargetState = combine.spec_pipe.targetState

			if capacity == math.huge then
				if currentPipeTargetState ~= 2 then
					combine:setPipeState(2)
				end

				if not isTurning then
					local targetObject, _ = combine:getDischargeTargetObject(dischargeNode)
					allowedToDrive = trailerInTrigger and targetObject ~= nil

					if VehicleDebug.state == VehicleDebug.DEBUG_AI then
						if not trailerInTrigger then
							self.vehicle:addAIDebugText("COMBINE -> Waiting for trailer enter the trigger")
						elseif trailerInTrigger and targetObject == nil then
							self.vehicle:addAIDebugText("COMBINE -> Waiting for pipe hitting the trailer")
						end
					end
				end
			else
				local pipeState = currentPipeTargetState

				if fillLevel > 0.8 * capacity then
					if not self.beaconLightsActive then
						self.vehicle:setAIMapHotspotBlinking(true)
						self.vehicle:setBeaconLightsVisibility(true)

						self.beaconLightsActive = true
					end

					if not self.notificationGrainTankWarningShown then
						g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, string.format(g_i18n:getText("ai_messageErrorGrainTankIsNearlyFull"), self.vehicle:getCurrentHelper().name))

						self.notificationGrainTankWarningShown = true
					end
				else
					if self.beaconLightsActive then
						self.vehicle:setAIMapHotspotBlinking(false)
						self.vehicle:setBeaconLightsVisibility(false)

						self.beaconLightsActive = false
					end

					self.notificationGrainTankWarningShown = false
				end

				if fillLevel == capacity then
					pipeState = 2
					self.wasCompletelyFull = true

					if self.notificationFullGrainTankShown ~= true then
						g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, string.format(g_i18n:getText("ai_messageErrorGrainTankIsFull"), self.vehicle:getCurrentHelper().name))

						self.notificationFullGrainTankShown = true
					end
				else
					self.notificationFullGrainTankShown = false
				end

				if trailerInTrigger then
					pipeState = 2
				end

				if not trailerInTrigger and fillLevel < capacity * 0.8 then
					self.wasCompletelyFull = false

					if not combine:getIsTurnedOn() and combine:getCanBeTurnedOn() then
						combine:aiImplementStartLine()
					end
				end

				if not trailerInTrigger and not invalidTrailerInTrigger and fillLevel < capacity then
					pipeState = 1
				end

				if fillLevel < 0.1 then
					if not combine.spec_pipe.aiFoldedPipeUsesTrailerSpace then
						if not trailerInTrigger and not invalidTrailerInTrigger then
							pipeState = 1
						end

						if not combine:getIsTurnedOn() and combine:getCanBeTurnedOn() then
							combine:aiImplementStartLine()
						end
					end

					self.wasCompletelyFull = false
				end

				if currentPipeTargetState ~= pipeState then
					combine:setPipeState(pipeState)
				end

				allowedToDrive = fillLevel < capacity

				if pipeState == 2 and self.wasCompletelyFull then
					allowedToDrive = false

					if VehicleDebug.state == VehicleDebug.DEBUG_AI then
						self.vehicle:addAIDebugText("COMBINE -> Waiting for trailer to unload")
					end
				end

				if isTurning and trailerInTrigger and combine:getCanDischargeToObject(dischargeNode) then
					allowedToDrive = fillLevel == 0

					if VehicleDebug.state == VehicleDebug.DEBUG_AI and not allowedToDrive then
						self.vehicle:addAIDebugText("COMBINE -> Unload to trailer on headland")
					end
				end

				local freeFillLevel = capacity - fillLevel

				if freeFillLevel < self.slowDownFillLevel then
					maxSpeed = 2 + freeFillLevel / self.slowDownFillLevel * self.slowDownStartSpeed

					if VehicleDebug.state == VehicleDebug.DEBUG_AI then
						self.vehicle:addAIDebugText(string.format("COMBINE -> Slow down because nearly full: %.2f", maxSpeed))
					end
				end
			end

			if not trailerInTrigger and combine.spec_combine.isSwathActive and combine.spec_combine.strawPSenabled then
				waitForStraw = true
			end
		end
	end

	if isTurning and waitForStraw then
		if VehicleDebug.state == VehicleDebug.DEBUG_AI then
			self.vehicle:addAIDebugText("COMBINE -> Waiting for straw to drop")
		end

		local h = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, self.vehicle.aiDriveTarget[1], 0, self.vehicle.aiDriveTarget[2])
		local x, _, z = worldToLocal(self.vehicle:getAIDirectionNode(), self.vehicle.aiDriveTarget[1], h, self.vehicle.aiDriveTarget[2])
		local dist = MathUtil.vector2Length(vX - x, vZ - z)

		return x, z, false, 10, dist
	elseif not allowedToDrive then
		return 0, 1, true, 0, math.huge
	else
		return nil, , , maxSpeed, nil
	end
end

function AIDriveStrategyCombine:updateDriving(dt)
end
