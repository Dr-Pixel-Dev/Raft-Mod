-- OilGeyser.lua --
dofile "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua"

OilGeyser = class( nil )

--Raft
OilGeyser.spawnJunk = -1

function OilGeyser.server_onCreate( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = true
		self.storage:save( self.saved )
		self.spawnJunk = 10
	end
end

function OilGeyser.server_spawnJunk(self)
	local vec = self.harvestable:getPosition()
	vec.z = -2

	local random = math.random(1,1000)
	local junkIndex
	if random <= 10 then
		local crate = hvs_lootcrate
		if math.random(1,25) == 25 then
			crate = hvs_lootcrateepic
		end

		sm.harvestable.create( crate, vec, self.harvestable.worldRotation )
		return
	elseif random <= 100 then
		return
	elseif random <= 110 then
		junkIndex = 6
	elseif random <= 125 then
		junkIndex = 5
	elseif random <= 200 then
		junkIndex = 4
	elseif random <= 275 then
		junkIndex = 3
	elseif random <= 600 then
		junkIndex = 2
	elseif random <= 602 then
		junkIndex = 100 + math.random(1,3) --Abandoned raft
	else
		junkIndex = 1
	end

	local status, error = pcall( sm.creation.importFromFile( sm.player.getAllPlayers()[1]:getCharacter():getWorld(), "$SURVIVAL_DATA/LocalBlueprints/junk" .. tostring(junkIndex) .. ".blueprint", vec ) )
end

function OilGeyser.server_onFixedUpdate( self, state )
	if self.spawnJunk == 0 then
		self:server_spawnJunk()
	end
	self.spawnJunk = self.spawnJunk - 1
end



function OilGeyser.client_onInteract( self, state )
	self.network:sendToServer( "sv_n_harvest" )
end

function OilGeyser.client_canInteract( self )
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Attack" ), "#{INTERACTION_PICK_UP}" )
	return true
end

function OilGeyser.server_canErase( self ) return true end
function OilGeyser.client_canErase( self ) return true end

function OilGeyser.server_onRemoved( self, player )
	self:sv_n_harvest( nil, player )
end

function OilGeyser.client_onCreate( self )
	self.cl = {}
	self.cl.acitveGeyser = sm.effect.createEffect( "Oilgeyser - OilgeyserLoop" )
	self.cl.acitveGeyser:setPosition( self.harvestable.worldPosition )
	self.cl.acitveGeyser:setRotation( self.harvestable.worldRotation )
	self.cl.acitveGeyser:start()
end

function OilGeyser.cl_n_onInventoryFull( self )
	sm.gui.displayAlertText( "#{INFO_INVENTORY_FULL}", 4 )
end

function OilGeyser.sv_n_harvest( self, params, player )
	if not self.harvested and sm.exists( self.harvestable ) then
		if SurvivalGame then
			local container = player:getInventory()
			local quantity = randomStackAmount( 1, 2, 4 )
			if sm.container.beginTransaction() then
				sm.container.collect( container, obj_resource_crudeoil, quantity )
				if sm.container.endTransaction() then
					sm.event.sendToPlayer( player, "sv_e_onLoot", { uuid = obj_resource_crudeoil, quantity = quantity, pos = self.harvestable.worldPosition } )
					sm.effect.playEffect( "Oilgeyser - Picked", self.harvestable.worldPosition )
					sm.harvestable.create( hvs_farmables_growing_oilgeyser, self.harvestable.worldPosition, self.harvestable.worldRotation )
					sm.harvestable.destroy( self.harvestable )
					self.harvested = true
				else
					self.network:sendToClient( player, "cl_n_onInventoryFull" )
				end
			end
		else
			sm.effect.playEffect( "Oilgeyser - Picked", self.harvestable.worldPosition )
			sm.harvestable.create( hvs_farmables_growing_oilgeyser, self.harvestable.worldPosition, self.harvestable.worldRotation )
			sm.harvestable.destroy( self.harvestable )
			self.harvested = true
		end
	end
end

function OilGeyser.client_onDestroy( self )
	self.cl.acitveGeyser:stop()
	self.cl.acitveGeyser:destroy()
end