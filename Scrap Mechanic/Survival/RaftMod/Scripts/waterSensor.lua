Sensor = class()
Sensor.maxChildCount = -1
Sensor.maxParentCount = 0
Sensor.connectionInput = sm.interactable.connectionType.none
Sensor.connectionOutput = sm.interactable.connectionType.logic
Sensor.colorNormal = sm.color.new("#0033ff")
Sensor.colorHighlight = sm.color.new("#0000ff")

local maxTriggerSize = 25
local blockDivide = 4

local function vec3Num(num)
    return sm.vec3.new(num, num, num)
end

function Sensor:server_onCreate()
    self.sv = {}
    self.sv.data = self.storage:load()

    if self.sv.data == nil then
        self.sv.data = {
            slider = 1,
            visualize = false
        }
    end

    self.network:sendToClients("cl_updateData", self.sv.data)

    self.trigger = sm.areaTrigger.createAttachedBox( self.interactable, vec3Num(self.sv.data.slider) / blockDivide, sm.vec3.zero(), sm.quat.identity(), sm.areaTrigger.filter.areaTrigger )
end

function Sensor:client_onCreate()
    self.cl = {
        data = {},
        gui = sm.gui.createEngineGui(),
        visualization = sm.effect.createEffect("WaterSensor - Visualization", self.interactable)
    }

    self.cl.gui:setText( "Name", "Water Sensor" )
	self.cl.gui:setText( "Interaction", "Sensing Radius(blocks)" )
	self.cl.gui:setSliderCallback( "Setting", "cl_onSliderChange" )
	self.cl.gui:setIconImage( "Icon", obj_waterSensor )

    self.cl.visualization:setParameter( "minColor", sm.color.new( 0.0, 0.0, 0.25, 0.1 ) )
	self.cl.visualization:setParameter( "maxColor", sm.color.new( 0.0, 0.3, 0.75, 0.4 ) )
	self.cl.visualization:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
	self.cl.visualization:setParameter("color", sm.color.new(1,1,1, 0.01))
end

function Sensor:cl_refreshGUI()
    self.cl.gui:setSliderData( "Setting", maxTriggerSize + 1, self.sv.data.slider )
    self.cl.gui:setText( "SubTitle", "Radius: " .. tostring( self.sv.data.slider ).." blocks" )
end

function Sensor:cl_onSliderChange( sliderName, sliderPos )
    self:cl_refreshGUI()
    self.network:sendToServer("sv_onSliderChange", sliderPos)
end

function Sensor:sv_onSliderChange( sliderPos )
    self.sv.data.slider = sliderPos

    --setSize works shit for some reason?
    --If I had the sensor just barely above water with a 1 block sensing radius it wouldnt sense anything
    --if I then increased it to 2, it would starts sensing the water
    --if I set it back to 1 it stayed active for some reason
    --creating a new trigger every time fixes it
    --weird...
    sm.areaTrigger.destroy( self.trigger )
    self.trigger = sm.areaTrigger.createAttachedBox( self.interactable, vec3Num(self.sv.data.slider) / blockDivide, sm.vec3.zero(), sm.quat.identity(), sm.areaTrigger.filter.areaTrigger )

    self.storage:save(self.sv.data)
    self.network:sendToClients("cl_visualize", self.sv.data)
end

function Sensor:server_onFixedUpdate( dt )
    if not self.sv or not self.sv.data then return end
    self.network:sendToClients("cl_updateData", self.sv.data)

    if not self.trigger then return end

    local isInWater = false
    for _, result in ipairs( self.trigger:getContents() ) do
        if sm.exists( result ) then
            local userData = result:getUserData()
            if userData and userData.water then
                isInWater = true
            end
        end
    end

    local isInWater2 = isInWater and self.trigger:getSize():length() > 0
    self:sv_updateState( { active = isInWater2, power = isInWater2 and 1 or 0, index = isInWater2 and 6 or 0  } )
end

function Sensor:cl_updateData( data )
    self.cl.data = data
end

function Sensor:sv_updateState( args )
    self.interactable:setActive( args.active )
    self.interactable:setPower( args.power )

    self.network:sendToClients("cl_uvUpdate", args.index)
end

function Sensor:cl_uvUpdate( index )
    self.interactable:setUvFrameIndex( index )
end

function Sensor:client_canInteract()
    local txt = self.cl.data.visualize and "#269e44ON" or "#9e2626OFF"
	sm.gui.setInteractionText( "", "Current sensing radius: #df7f00"..tostring(self.cl.data.slider).." block(s)#4f4f4f, Visualization: "..txt )
    sm.gui.setInteractionText( "", "'"..sm.gui.getKeyBinding( "Use" ).."' to adjust the sensing radius and '"..sm.gui.getKeyBinding( "Tinker" ).."' to toggle the radius visualisation." )

    return true
end

function Sensor:client_onInteract( char, lookAt )
    if lookAt then
        self:cl_refreshGUI()
        self.cl.gui:open()
    end
end

function Sensor:client_onTinker( char, lookAt )
    if lookAt then
        self.network:sendToServer("sv_visualize")
    end
end

function Sensor:sv_visualize()
    self.sv.data.visualize = not self.sv.data.visualize
    self.network:sendToClients("cl_visualize", self.sv.data)
end

function Sensor:cl_visualize( args )
    self.cl.visualization:setScale(vec3Num(args.slider) / blockDivide)

    if args.visualize and not self.cl.visualization:isPlaying() then
        self.cl.visualization:start()
    elseif not args.visualize and self.cl.visualization:isPlaying() then
        self.cl.visualization:stop()
    end
end