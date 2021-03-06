Propeller = class()
Propeller.maxParentCount = 0
Propeller.maxChildCount = 0
Propeller.connectionInput = sm.interactable.connectionType.none
Propeller.connectionOutput = sm.interactable.connectionType.none
Propeller.speed = 1

function Propeller:server_onCreate()
    self.trigger = sm.areaTrigger.createAttachedBox( self.interactable, sm.vec3.one() / 6, sm.vec3.zero(), sm.quat.identity(), 8 )
end

function Propeller:server_onFixedUpdate(dt)
	local isInWater = false
    for _, result in ipairs( self.trigger:getContents() ) do
        if sm.exists( result ) then
            local userData = result:getUserData()
            if userData and userData.water then
                isInWater = true
            end
        end
    end

	angular = self.shape:getBody():getAngularVelocity()

	vec = self.shape.at
	speed = sm.vec3.dot(angular, vec)

	--less power in air
	if not isInWater then
		speed = speed/10
	end

	speed = speed * self.speed

	if math.abs(speed) > 1 then
		sm.physics.applyImpulse( self.shape:getBody(), sm.vec3.new(10,10,10) * speed * self.shape:getAt(), true )

		--effects
		if sm.game.getCurrentTick() % 5 == 0 then
			if isInWater then
				local effect = "Water - HitWaterTiny"
				speed = math.abs(speed)

				if speed > 75 then
					effect = "Water - HitWaterMassive"
				elseif speed > 25 then
					effect = "Water - HitWaterBig"
				elseif speed > 5 then
					effect = "Water - HitWaterSmall"
				end

				self.network:sendToClients("cl_playEffect", effect)
			end
		end
	end
end

function Propeller:client_canInteract()
	return false
end

function Propeller:cl_playEffect( effect )
	sm.effect.playEffect( effect, self.shape:getWorldPosition(), sm.vec3.zero(), sm.quat.lookRotation(self.shape.at, self.shape.right), sm.vec3.one())
end

SmallPropeller = class(Propeller)
SmallPropeller.speed = 0.36016301579215486500254712175242 --radius 1.5 vs. radius 2.5