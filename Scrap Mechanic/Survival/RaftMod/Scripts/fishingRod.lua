dofile "$GAME_DATA/Scripts/game/AnimationUtil.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_loot.lua"

Rod = class()

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Barrel/Barrel_basic/char_spudgun_barrel_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Sight/Sight_basic/char_spudgun_sight_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Stock/Stock_broom/char_spudgun_stock_broom.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Tank/Tank_basic/char_spudgun_tank_basic.rend"
}

local renderablesTp = {"$GAME_DATA/Character/Char_Male/Animations/char_male_tp_spudgun.rend", "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_tp_animlist.rend"}
local renderablesFp = {"$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_fp_animlist.rend"}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

local normalLoot = {
	{ uuid = obj_fish,						chance = 100,			quantity = 1 },
	{ uuid = blk_scrapwood, 				chance = 20,			quantity = function() return math.random(5, 10) end },
	{ uuid = blk_scrapmetal, 				chance = 10,			quantity = function() return math.random(2, 5) end },
	{ uuid = obj_decor_boot, 				chance = 5,				quantity = 1 }
}

local rareLoot = {
	{ uuid = obj_consumable_component,		chance = 1,				quantity = function() return math.random(1, 2) end },
	{ uuid = obj_consumable_fertilizer, 	chance = 1,				quantity = function() return math.random(1, 3) end },
	{ uuid = obj_consumable_gas, 			chance = 1,				quantity = function() return math.random(2, 5) end },
	{ uuid = obj_consumable_chemical, 		chance = 1,				quantity = function() return math.random(1, 10) end }
}

function vec3Num( num )
	return sm.vec3.new(num,num,num)
end

local hookSize = vec3Num(0.1)
local premiumDropChance = 0.1
local maxThrowForce = 5
local minThrowForce = 0.25
local minWaitTime = 10.001
local maxWaitTime = 30.001

local CatchTime = 0.5
local minBites = 1
local maxBites = 6


function Rod.client_onCreate( self )
	self.player = sm.localPlayer.getPlayer()

	self.ropeEffect = sm.effect.createEffect("ShapeRenderable")
	self.ropeEffect:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
	self.ropeEffect:setParameter("color", sm.color.new(0,0,0))

	self.hookEffect = sm.effect.createEffect("ShapeRenderable")
	self.hookEffect:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
	self.hookEffect:setParameter("color", sm.color.new(1,0,0))
	self.hookEffect:setScale(hookSize)
	self.hookOffset = 0

	self.throwForce = 0
	self.primaryState = 0
	self.canFishOutLootThreshold = 0
	self.isThrowing = false
	self.isFishing = false
	self.hookPos = sm.vec3.zero()
	self.hookDir = sm.vec3.zero()
	self.lookDir = sm.vec3.zero()
	self.trigger = nil

	self.dropTimer = { timer = 0, effectTimer = 1, valid = maxWaitTime }
	self.useCD = { active = false, timer = 1 }
end

function Rod.client_onRefresh( self )
	self:loadAnimations()
end

function Rod.loadAnimations( self )
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "spudgun_idle" },
			pickup = { "spudgun_pickup", { nextAnimation = "idle" } },
			putdown = { "spudgun_putdown" }
		}
	)
	local movementAnimations = {
		idle = "spudgun_idle",
		idleRelaxed = "spudgun_relax",

		sprint = "spudgun_sprint",
		runFwd = "spudgun_run_fwd",
		runBwd = "spudgun_run_bwd",

		jump = "spudgun_jump",
		jumpUp = "spudgun_jump_up",
		jumpDown = "spudgun_jump_down",

		land = "spudgun_jump_land",
		landFwd = "spudgun_jump_land_fwd",
		landBwd = "spudgun_jump_land_bwd",

		crouchIdle = "spudgun_crouch_idle",
		crouchFwd = "spudgun_crouch_fwd",
		crouchBwd = "spudgun_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.tool:isLocal() then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "spudgun_pickup", { nextAnimation = "idle" } },
				unequip = { "spudgun_putdown" },
				idle = { "spudgun_idle", { looping = true } },

				sprintInto = { "spudgun_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintExit = { "spudgun_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "spudgun_sprint_idle", { looping = true } },
			}
		)
	end


	--Remove?
	self.movementDispersion = 0.0
	self.sprintCooldownTimer = 0.0
	self.sprintCooldown = 0.3
	self.blendTime = 0.2
	self.jointWeight = 0.0
	self.spineWeight = 0.0
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
end

function Rod:sv_itemDrop()
	local lootList = normalLoot
	if math.random() <= premiumDropChance then
		lootList = rareLoot
	end
	local drop = SelectOne(lootList)

	sm.container.beginTransaction()
	sm.container.collect( self.player:getInventory(), drop.uuid, drop.quantity, 1 )
	sm.container.endTransaction()

	self.network:sendToClient(self.player, "cl_itemDrop", drop )
end

function Rod:cl_itemDrop( drop )
	sm.gui.displayAlertText( "Fished item: #ff9d00"..sm.shape.getShapeTitle(drop.uuid).." #df7f00x"..tostring(drop.quantity) )
end

function Rod:sv_manageTrigger( action )
	if action ~= nil then
		if action == "create" then
			self.trigger = sm.areaTrigger.createBox( hookSize * 4, self.hookPos, sm.quat.identity(), 8 )
		else
			sm.areaTrigger.destroy(self.trigger)
			return
		end
	end

	self.trigger:setWorldPosition( self.hookPos )
end

function Rod:sv_playEffect( args )
	self.network:sendToClients("cl_playEffect", args)
end

function Rod:cl_playEffect( args )
	if args.type == "effect" then
		sm.effect.playEffect( args.effect, args.pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one())
	else
		sm.audio.play( args.effect, args.pos )
	end
end

function Rod:sv_playWaterSplash( args )
	self.network:sendToClients("cl_playWaterSplash", { pos = self.hookPos, effect = args.effect, force = args.force })
end

function Rod:cl_playWaterSplash( args )
	local params = {
		["Size"] = min( 1.0, args.force * 0.5 / 76800.0 ),
		["Velocity_max_50"] = sm.vec3.new(0,0,10 * args.force * 0.1 ):length(),
		["Phys_energy"] = args.force / 1000.0
	}
	sm.effect.playEffect( args.effect, args.pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	self.hookOffset = 0.25
	if args.effect == "Water - HitWaterBig" then
		self.hookOffset = 1
	end
end

function Rod:cl_reset()
	self.throwForce = 0
	self.isThrowing = false
	self.isFishing = false
	self.hookPos = sm.vec3.zero()
	self.hookDir = sm.vec3.zero()
	self.dropTimer = { timer = 0, effectTimer = 1, valid = maxWaitTime }
	self.ropeEffect:stop()
	self.hookEffect:stop()
end

function Rod:cl_cancel( state )
	if (state == 1 or state == 2) then
		if (self.dropTimer.valid - self.dropTimer.timer) < CatchTime and self.isFishing then
			self.network:sendToServer("sv_itemDrop")
			sm.effect.playEffect("Loot - Pickup", self.hookPos)

			--sm.effect.playEffect("Water - HitWaterMassive", self.hookPos)
			--self.network:sendToServer("sv_playWaterSplash", { effect = "Loot - Pickup", force = 10000 } )
			self.network:sendToServer("sv_playWaterSplash", { effect = "Water - HitWaterMassive", force = 10000 } )
			--sm.effect.playEffect( "Water - HitWaterMassive", self.hookPos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
		else
			self.network:sendToServer("sv_playWaterSplash", { effect = "Water - HitWaterTiny", force = 10000 } )
			--sm.effect.playEffect( "Water - HitWaterTiny", self.hookPos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
		end

		if self.isFishing or self.isThrowing then
			self.useCD.active = true
			sm.audio.play( "Sledgehammer - Swing" )
		end

		self:cl_reset()
	end
	return self.useCD.active
end

function Rod:cl_calculateRodEffectData()
	local offset = self.hookPos - sm.vec3.new(0, 0, self.hookOffset)

	local delta = ( self:calculateFirePosition() - offset )
	local rot = sm.vec3.getRotation(sm.vec3.new(0, 0, 1), delta)
	local distance = sm.vec3.new(0.01, 0.01, delta:length())

	self.ropeEffect:setPosition(offset + delta * 0.5)
	self.ropeEffect:setScale(distance)
	self.ropeEffect:setRotation(rot)

	self.hookEffect:setPosition(offset)
	self.hookEffect:setRotation(rot)
end

function Rod:client_onFixedUpdate( dt )
	local owner = self.tool:getOwner()
	if self.useCD.active or owner.character:isSwimming() or owner.character:isDiving() then
		self.throwForce = 0
		return
	end

	if self.tool:isEquipped() and self.primaryState == 1 or self.primaryState == 2 then
		self.throwForce = self.throwForce < maxThrowForce and self.throwForce + dt*2 or maxThrowForce
	end
end

function Rod.client_onUpdate( self, dt )
	self.lookDir = sm.localPlayer.getDirection()

	if self.useCD.active then
		self.useCD.timer = self.useCD.timer - dt
		if self.useCD.timer <= 0 then
			self.useCD = { active = false, timer = 1 }
		end
	end

	if sm.exists(self.ropeEffect) and self.ropeEffect:isPlaying() then
		if self.isThrowing then
			if self.hookDir.z > -1 then
				self.hookDir = self.hookDir - sm.vec3.new(0,0,0.05 / self.throwForce)
			end
			self.hookPos = self.hookPos + vec3Num(self.throwForce) * 3 * self.hookDir * dt
			self.network:sendToServer("sv_manageTrigger")

			local hitWater = false
			if sm.exists(self.trigger) then
				for _, result in ipairs( self.trigger:getContents() ) do
					if sm.exists( result ) then
						local userData = result:getUserData()
						if userData then
							hitWater = true
						end
					end
				end
			end
			local hit, result = sm.physics.raycast( self.hookPos, self.hookPos + self.hookDir * self.throwForce * (dt*2) )

			if hitWater then
				self.isThrowing = false
				self.isFishing = true
				self.throwForce = 0
				self.dropTimer.timer = math.random(minWaitTime,maxWaitTime)
				self.dropTimer.valid = maxWaitTime
				self.network:sendToServer("sv_manageTrigger", "destroy")
				self.network:sendToServer("sv_playWaterSplash", { effect = "Water - HitWaterTiny", force = 10000 / math.ceil(self.dropTimer.timer) } )
			elseif not hitWater and hit then
				self:cl_reset()
			end
		end

		if self.hookDir:length() > 0 and self.hookPos:length() > 0 then
			self:cl_calculateRodEffectData()
		end
	end

	self.hookOffset = self.hookOffset * (1 - dt*4)

	if self.dropTimer.timer > 0 then
		self.dropTimer.timer = self.dropTimer.timer - dt

		if self.dropTimer.timer <= self.canFishOutLootThreshold + 1 and self.dropTimer.timer > 0 then
			self.dropTimer.effectTimer = self.dropTimer.effectTimer - dt

			if self.dropTimer.effectTimer <= 0 and self.dropTimer.timer > 1 then
				self.dropTimer.effectTimer = 1
				if self.dropTimer.timer > 2 then
					self.network:sendToServer("sv_playWaterSplash", { effect = "Water - HitWaterTiny", force = 10000 / math.ceil(self.dropTimer.timer) } )
					self.network:sendToServer("sv_playEffect", { effect = "Eat - MunchSound", pos = self.hookPos, type = "effect" } )
				else
					self.network:sendToServer("sv_playWaterSplash", { effect = "Water - HitWaterBig", force = 10000 / math.ceil(self.dropTimer.timer) } )
					self.network:sendToServer("sv_playEffect", { effect = "Eat - MunchSound", pos = self.hookPos, type = "effect" } )
					self.network:sendToServer("sv_playEffect", { effect = "Retrofmblip", pos = self.hookPos, type = "sound" } )
					self.dropTimer.valid = self.dropTimer.timer
				end
			end
		end

		sm.gui.displayAlertText(tostring(math.floor(self.dropTimer.timer)), 1)
		if self.dropTimer.timer <= 0 then
			self.dropTimer.timer = math.random(minWaitTime,maxWaitTime)
			self.dropTimer.valid = maxWaitTime
			self.canFishOutLootThreshold = math.random(minBites, maxBites)
		end
	end

	-- First person animation
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()

	if self.tool:isLocal() then
		if self.equipped then
			if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
				swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
			elseif not self.tool:isSprinting() and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
				swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
			end
		end
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end
	-- Timers
	self.sprintCooldownTimer = math.max( self.sprintCooldownTimer - dt, 0.0 )

	-- Sprint block
	local blockSprint = self.sprintCooldownTimer > 0.0
	self.tool:setBlockSprint( blockSprint )

	local playerDir = self.tool:getDirection()
	local angle = math.asin( playerDir:dot( sm.vec3.new( 0, 0, 1 ) ) ) / ( math.pi / 2 )
	local linareAngle = playerDir:dot( sm.vec3.new( 0, 0, 1 ) )

	local linareAngleDown = clamp( -linareAngle, 0.0, 1.0 )

	down = clamp( -angle, 0.0, 1.0 )
	fwd = ( 1.0 - math.abs( angle ) )
	up = clamp( angle, 0.0, 1.0 )

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight

	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
				if name == "pickup" then
					setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		else
			animation.weight = math.max( animation.weight - ( self.tpAnimations.blendSpeed * dt ), 0.0 )
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs( self.tpAnimations.animations ) do
		local weight = animation.weight / totalWeight
		if name == "idle" then
			self.tool:updateMovementAnimation( animation.time, weight )
		elseif animation.crouch then
			self.tool:updateAnimation( animation.info.name, animation.time, weight * normalWeight )
			self.tool:updateAnimation( animation.crouch.name, animation.time, weight * crouchWeight )
		else
			self.tool:updateAnimation( animation.info.name, animation.time, weight )
		end
	end

	-- Third Person joint lock
	local relativeMoveDirection = self.tool:getRelativeMoveDirection()
	self.jointWeight = math.max( self.jointWeight - ( 6.0 * dt ), 0.0 )

	if ( not isSprinting ) then
		self.spineWeight = math.min( self.spineWeight + ( 10.0 * dt ), 1.0 )
	else
		self.spineWeight = math.max( self.spineWeight - ( 10.0 * dt ), 0.0 )
	end

	local finalAngle = ( 0.5 + angle * 0.5 )
	self.tool:updateAnimation( "spudgun_spine_bend", finalAngle, self.spineWeight )

	local totalOffsetZ = lerp( -22.0, -26.0, crouchWeight )
	local totalOffsetY = lerp( 6.0, 12.0, crouchWeight )
	local crouchTotalOffsetX = clamp( ( angle * 60.0 ) -15.0, -60.0, 40.0 )
	local normalTotalOffsetX = clamp( ( angle * 50.0 ), -45.0, 50.0 )
	local totalOffsetX = lerp( normalTotalOffsetX, crouchTotalOffsetX , crouchWeight )

	local finalJointWeight = ( self.jointWeight )


	self.tool:updateJoint( "jnt_hips", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.35 * finalJointWeight * ( normalWeight ) )

	local crouchSpineWeight = ( 0.35 / 3 ) * crouchWeight

	self.tool:updateJoint( "jnt_spine1", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight )  * finalJointWeight )
	self.tool:updateJoint( "jnt_spine2", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_spine3", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.45 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_head", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.3 * finalJointWeight )
end

function Rod.client_onEquip( self, animate )

	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.wantEquipped = true
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	currentRenderablesTp = {}
	currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	self.tool:setTpRenderables( currentRenderablesTp )

	self:loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )

	if self.tool:isLocal() then
		-- Sets Rod renderable, change this to change the mesh
		self.tool:setFpRenderables( currentRenderablesFp )
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function Rod.client_onUnequip( self, animate )
	self:cl_reset()

	if animate then
		sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
	end

	self.wantEquipped = false
	self.equipped = false
	setTpAnimation( self.tpAnimations, "putdown" )
	if self.tool:isLocal() and self.fpAnimations.currentAnimation ~= "unequip" then
		swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
	end
end

function Rod.cl_onPrimaryUse( self, state )
	local owner = self.tool:getOwner()
	if owner.character == nil or self.lookDir == sm.vec3.zero() or self.useCD.active or owner.character:isSwimming() or owner.character:isDiving() then
		return
	end

	local shouldReturn = self:cl_cancel( state )
	if shouldReturn then return end

	if state == 3 then
		if self.throwForce < minThrowForce then
			self.throwForce = minThrowForce
		end

		self.isThrowing = true
		self.hookPos = self:calculateFirePosition() + self.lookDir / 2
		self.hookDir = self.lookDir
		self.network:sendToServer("sv_manageTrigger", "create")

		self:cl_calculateRodEffectData()
		self.ropeEffect:start()
		self.hookEffect:start()

		self.canFishOutLootThreshold = math.random(minBites, maxBites)
		sm.audio.play( "Sledgehammer - Swing" )
	end
end

function Rod.cl_onSecondaryUse( self, state )
	self:cl_cancel( state )
end

function Rod.client_onEquippedUpdate( self, primaryState, secondaryState)
	if primaryState ~= self.prevPrimaryState then
		self:cl_onPrimaryUse( primaryState )
		self.prevPrimaryState = primaryState
	end

	self.primaryState = primaryState
	if self.throwForce > 0 and not self.isThrowing then
		sm.gui.setProgressFraction(self.throwForce/maxThrowForce)
	end

	if secondaryState ~= self.prevSecondaryState then
		self:cl_onSecondaryUse( secondaryState )
		self.prevSecondaryState = secondaryState
	end

	return true, true
end

function Rod.calculateFirePosition( self )
	local crouching = self.tool:isCrouching()
	local firstPerson = self.tool:isInFirstPersonView()
	local dir = sm.localPlayer.getDirection()
	local pitch = math.asin( dir.z )
	local right = sm.localPlayer.getRight()

	local fireOffset = sm.vec3.new( 0.0, 0.0, 0.0 )

	if crouching then
		fireOffset.z = 0.15
	else
		fireOffset.z = 0.45
	end

	if firstPerson then
		fireOffset = fireOffset + right * 0.05
	else
		fireOffset = fireOffset + right * 0.25
		fireOffset = fireOffset:rotate( math.rad( pitch ), right )
	end
	local firePosition = GetOwnerPosition( self.tool ) + fireOffset
	return firePosition
end